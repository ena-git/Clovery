package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

type PostgresFederationStore struct {
	database *sql.DB
}

func NewPostgresFederationStore(database *sql.DB) *PostgresFederationStore {
	return &PostgresFederationStore{database: database}
}

func (store *PostgresFederationStore) UnbindIdentity(
	ctx context.Context,
	accountID string,
	provider string,
) error {
	transaction, err := store.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin identity unbinding: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	var lockedAccountID string
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT id FROM clovery_accounts WHERE id = $1 FOR UPDATE",
		accountID,
	).Scan(&lockedAccountID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrFederatedIdentityNotBound
		}
		return fmt.Errorf("lock account credentials: %w", err)
	}

	var credentialCount int
	if err := transaction.QueryRowContext(ctx, recoveryCredentialCountQuery, accountID).Scan(
		&credentialCount,
	); err != nil {
		return fmt.Errorf("count recovery credentials: %w", err)
	}
	if credentialCount <= 1 {
		return ErrLastRecoveryCredential
	}

	result, err := transaction.ExecContext(
		ctx,
		`DELETE FROM external_identities
		 WHERE account_id = $1 AND provider = $2`,
		accountID,
		provider,
	)
	if err != nil {
		return fmt.Errorf("delete federated identity: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect deleted federated identity: %w", err)
	}
	if rowsAffected != 1 {
		return ErrFederatedIdentityNotBound
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload)
		 VALUES ($1, $2, 'identity_unbound', jsonb_build_object('provider', $3::text))`,
		uuid.NewString(),
		accountID,
		provider,
	); err != nil {
		return fmt.Errorf("audit federated identity unbinding: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit identity unbinding: %w", err)
	}
	return nil
}

const recoveryCredentialCountQuery = `SELECT
	(SELECT COUNT(*) FROM password_credentials WHERE account_id = $1)
	+ (SELECT COUNT(*) FROM passkeys WHERE account_id = $1)
	+ (SELECT COUNT(*) FROM external_identities WHERE account_id = $1)
	+ CASE WHEN EXISTS (
		SELECT 1 FROM recovery_codes WHERE account_id = $1 AND used_at IS NULL
	) THEN 1 ELSE 0 END`
