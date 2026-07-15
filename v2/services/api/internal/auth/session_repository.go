package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type sessionRecord struct {
	SessionID       string
	FamilyID        string
	DeviceID        string
	AccountID       string
	VaultID         string
	AuthenticatedAt time.Time
	RefreshExpiry   time.Time
	SessionRevoked  sql.NullTime
	DeviceRevoked   sql.NullTime
}

func upsertSessionDevice(
	ctx context.Context,
	transaction *sql.Tx,
	params SessionCreateParams,
) error {
	var accountID string
	err := transaction.QueryRowContext(
		ctx,
		`INSERT INTO devices (id, account_id, display_name, platform)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (id) DO UPDATE
		 SET display_name = EXCLUDED.display_name, platform = EXCLUDED.platform
		 WHERE devices.account_id = EXCLUDED.account_id AND devices.revoked_at IS NULL
		 RETURNING account_id`,
		params.DeviceID,
		params.AccountID,
		params.DisplayName,
		params.Platform,
	).Scan(&accountID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInvalidSession
	}
	if err != nil {
		return fmt.Errorf("upsert session device: %w", err)
	}
	return nil
}

func verifySessionVault(ctx context.Context, transaction *sql.Tx, accountID string, vaultID string) error {
	var exists bool
	err := transaction.QueryRowContext(
		ctx,
		`SELECT EXISTS (
		    SELECT 1 FROM vaults
		    WHERE id = $1 AND owner_account_id = $2 AND status = 'active'
		)`,
		vaultID,
		accountID,
	).Scan(&exists)
	if err != nil {
		return fmt.Errorf("verify session vault: %w", err)
	}
	if !exists {
		return ErrInvalidSession
	}
	return nil
}

func insertSessionRecord(
	ctx context.Context,
	transaction *sql.Tx,
	record sessionRecord,
	refreshHash []byte,
) error {
	_, err := transaction.ExecContext(
		ctx,
		`INSERT INTO sessions (id, device_id, refresh_token_hash, expires_at, token_family_id, authenticated_at)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		record.SessionID,
		record.DeviceID,
		refreshHash,
		record.RefreshExpiry,
		record.FamilyID,
		record.AuthenticatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert session: %w", err)
	}
	return nil
}

func lockSessionByRefreshHash(
	ctx context.Context,
	transaction *sql.Tx,
	refreshHash []byte,
) (sessionRecord, error) {
	record := sessionRecord{}
	err := transaction.QueryRowContext(
		ctx,
		`SELECT sessions.id, sessions.token_family_id, devices.id, devices.account_id,
		        vaults.id, sessions.authenticated_at, sessions.expires_at,
		        sessions.revoked_at, devices.revoked_at
		 FROM sessions
		 JOIN devices ON devices.id = sessions.device_id
		 JOIN vaults ON vaults.owner_account_id = devices.account_id
		 WHERE sessions.refresh_token_hash = $1
		   AND vaults.status = 'active'
		 FOR UPDATE OF sessions`,
		refreshHash,
	).Scan(
		&record.SessionID,
		&record.FamilyID,
		&record.DeviceID,
		&record.AccountID,
		&record.VaultID,
		&record.AuthenticatedAt,
		&record.RefreshExpiry,
		&record.SessionRevoked,
		&record.DeviceRevoked,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return sessionRecord{}, ErrInvalidSession
	}
	if err != nil {
		return sessionRecord{}, fmt.Errorf("lock refresh session: %w", err)
	}
	return record, nil
}
