package auth

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

var ErrInvalidResetProof = errors.New("invalid or expired password reset proof")

const passwordResetProofLifetime = 10 * time.Minute

type PasswordResetProof struct {
	ResetIntentID string
	Proof         string
	ExpiresIn     int
}

type PasswordResetService struct {
	database *sql.DB
	hasher   PasswordHasher
	now      func() time.Time
}

func NewPasswordResetService(database *sql.DB) *PasswordResetService {
	return &PasswordResetService{
		database: database,
		hasher:   NewPasswordHasher(),
		now:      func() time.Time { return time.Now().UTC() },
	}
}

func (service *PasswordResetService) CreateRecoveryProof(
	ctx context.Context,
	accountID string,
) (PasswordResetProof, error) {
	intentID, err := randomUUID(rand.Reader)
	if err != nil {
		return PasswordResetProof{}, fmt.Errorf("generate password reset intent ID: %w", err)
	}
	proof, proofHash, err := newPasswordResetProof(passwordResetRandomSource)
	if err != nil {
		return PasswordResetProof{}, err
	}
	now := service.now()
	_, err = service.database.ExecContext(
		ctx,
		`INSERT INTO password_reset_intents
		    (id, account_id, recovery_method, proof_hash, expires_at)
		 VALUES ($1, $2, 'recovery_code', $3, $4)`,
		intentID,
		accountID,
		proofHash[:],
		now.Add(passwordResetProofLifetime),
	)
	if err != nil {
		return PasswordResetProof{}, fmt.Errorf("store password reset intent: %w", err)
	}
	return PasswordResetProof{
		ResetIntentID: intentID,
		Proof:         proof,
		ExpiresIn:     int(passwordResetProofLifetime.Seconds()),
	}, nil
}

func (service *PasswordResetService) Complete(
	ctx context.Context,
	intentID string,
	proof string,
	newPassword string,
) error {
	newPasswordHash, err := service.hasher.Hash(newPassword)
	if err != nil {
		return err
	}
	proofHash := hashPasswordResetProof(proof)
	now := service.now()
	transaction, err := service.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin password reset: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	intent, err := lockPasswordResetIntent(ctx, transaction, intentID)
	if err != nil {
		return err
	}
	if err := validatePasswordResetIntent(intent, proofHash[:], now); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE password_credentials
		 SET password_hash = $2, updated_at = $3
		 WHERE account_id = $1`,
		intent.AccountID,
		newPasswordHash,
		now,
	); err != nil {
		return fmt.Errorf("replace password credential: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		"UPDATE password_reset_intents SET consumed_at = $2 WHERE id = $1",
		intentID,
		now,
	); err != nil {
		return fmt.Errorf("consume password reset intent: %w", err)
	}
	if err := revokeAccountSessions(ctx, transaction, intent.AccountID, now); err != nil {
		return err
	}
	auditID, err := randomUUID(rand.Reader)
	if err != nil {
		return fmt.Errorf("generate password reset audit ID: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload)
		 VALUES ($1, $2, 'password_reset', '{"sessions_revoked":true}'::jsonb)`,
		auditID,
		intent.AccountID,
	); err != nil {
		return fmt.Errorf("record password reset audit: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit password reset: %w", err)
	}
	return nil
}
