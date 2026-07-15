package auth

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

var ErrDeviceNotFound = errors.New("device not found")

func (service *SessionService) RevokeDevice(ctx context.Context, accountID string, deviceID string) error {
	now := service.now()
	transaction, err := service.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin device revocation: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	result, err := transaction.ExecContext(
		ctx,
		`UPDATE devices SET revoked_at = $3
		 WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL`,
		deviceID,
		accountID,
		now,
	)
	if err != nil {
		return fmt.Errorf("revoke device: %w", err)
	}
	updated, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect device revocation: %w", err)
	}
	if updated != 1 {
		return ErrDeviceNotFound
	}
	_, err = transaction.ExecContext(
		ctx,
		"UPDATE sessions SET revoked_at = COALESCE(revoked_at, $2) WHERE device_id = $1",
		deviceID,
		now,
	)
	if err != nil {
		return fmt.Errorf("revoke device sessions: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload, created_at)
		 VALUES ($1, $2, 'device_revoked', jsonb_build_object('device_id', $3::uuid), $4)`,
		uuid.NewString(),
		accountID,
		deviceID,
		now,
	); err != nil {
		return fmt.Errorf("audit device revocation: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit device revocation: %w", err)
	}
	return nil
}
