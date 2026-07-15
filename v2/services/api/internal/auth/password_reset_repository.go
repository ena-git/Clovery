package auth

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type passwordResetIntent struct {
	AccountID  string
	ProofHash  []byte
	ExpiresAt  time.Time
	ConsumedAt sql.NullTime
}

func lockPasswordResetIntent(
	ctx context.Context,
	transaction *sql.Tx,
	intentID string,
) (passwordResetIntent, error) {
	intent := passwordResetIntent{}
	err := transaction.QueryRowContext(
		ctx,
		`SELECT account_id, proof_hash, expires_at, consumed_at
		 FROM password_reset_intents
		 WHERE id = $1
		 FOR UPDATE`,
		intentID,
	).Scan(&intent.AccountID, &intent.ProofHash, &intent.ExpiresAt, &intent.ConsumedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return passwordResetIntent{}, ErrInvalidResetProof
	}
	if err != nil {
		return passwordResetIntent{}, fmt.Errorf("lock password reset intent: %w", err)
	}
	return intent, nil
}

func validatePasswordResetIntent(intent passwordResetIntent, proofHash []byte, now time.Time) error {
	if intent.ConsumedAt.Valid || !intent.ExpiresAt.After(now) ||
		subtle.ConstantTimeCompare(intent.ProofHash, proofHash) != 1 {
		return ErrInvalidResetProof
	}
	return nil
}

func revokeAccountSessions(
	ctx context.Context,
	transaction *sql.Tx,
	accountID string,
	now time.Time,
) error {
	_, err := transaction.ExecContext(
		ctx,
		`UPDATE sessions
		 SET revoked_at = COALESCE(revoked_at, $2)
		 WHERE device_id IN (SELECT id FROM devices WHERE account_id = $1)`,
		accountID,
		now,
	)
	if err != nil {
		return fmt.Errorf("revoke password reset sessions: %w", err)
	}
	return nil
}
