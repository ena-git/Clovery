package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

const (
	passwordLoginRateLimitScope = "password_login"
	passwordLoginMaxFailures    = 5
	passwordLoginWindow         = 15 * time.Minute
	passwordLoginBlockDuration  = 15 * time.Minute
)

func (service *LoginService) isRateLimited(ctx context.Context, keyHash []byte) (bool, error) {
	var blockedUntil sql.NullTime
	err := service.database.QueryRowContext(
		ctx,
		"SELECT blocked_until FROM auth_rate_limits WHERE scope = $1 AND key_hash = $2",
		passwordLoginRateLimitScope,
		keyHash,
	).Scan(&blockedUntil)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("read password login rate limit: %w", err)
	}
	return blockedUntil.Valid && blockedUntil.Time.After(service.now()), nil
}

func (service *LoginService) clearFailedLogins(ctx context.Context, keyHash []byte) error {
	_, err := service.database.ExecContext(
		ctx,
		"DELETE FROM auth_rate_limits WHERE scope = $1 AND key_hash = $2",
		passwordLoginRateLimitScope,
		keyHash,
	)
	if err != nil {
		return fmt.Errorf("clear password login failures: %w", err)
	}
	return nil
}

func (service *LoginService) recordFailedLogin(ctx context.Context, keyHash []byte) (bool, error) {
	transaction, err := service.database.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("begin password rate limit update: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	now := service.now()
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO auth_rate_limits (scope, key_hash, failed_count, window_started_at)
		 VALUES ($1, $2, 0, $3)
		 ON CONFLICT (scope, key_hash) DO NOTHING`,
		passwordLoginRateLimitScope,
		keyHash,
		now,
	); err != nil {
		return false, fmt.Errorf("initialize password rate limit: %w", err)
	}

	var failedCount int
	var windowStartedAt time.Time
	if err := transaction.QueryRowContext(
		ctx,
		`SELECT failed_count, window_started_at
		 FROM auth_rate_limits
		 WHERE scope = $1 AND key_hash = $2
		 FOR UPDATE`,
		passwordLoginRateLimitScope,
		keyHash,
	).Scan(&failedCount, &windowStartedAt); err != nil {
		return false, fmt.Errorf("lock password rate limit: %w", err)
	}
	if now.Sub(windowStartedAt) >= passwordLoginWindow {
		failedCount = 0
		windowStartedAt = now
	}
	failedCount++

	var blockedUntil any
	limited := failedCount >= passwordLoginMaxFailures
	if limited {
		blockedUntil = now.Add(passwordLoginBlockDuration)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE auth_rate_limits
		 SET failed_count = $3, window_started_at = $4, blocked_until = $5, updated_at = $6
		 WHERE scope = $1 AND key_hash = $2`,
		passwordLoginRateLimitScope,
		keyHash,
		failedCount,
		windowStartedAt,
		blockedUntil,
		now,
	); err != nil {
		return false, fmt.Errorf("update password rate limit: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return false, fmt.Errorf("commit password rate limit: %w", err)
	}
	return limited, nil
}
