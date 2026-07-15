package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
)

func (store *PostgresFederationStore) BindIdentity(
	ctx context.Context,
	accountID string,
	key FederatedIdentityKey,
) error {
	transaction, err := store.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin identity binding: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	var lockedAccountID string
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT id FROM clovery_accounts WHERE id = $1 FOR UPDATE",
		accountID,
	).Scan(&lockedAccountID); err != nil {
		return fmt.Errorf("lock account for identity binding: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO external_identities (account_id, provider, issuer, subject)
		 VALUES ($1, $2, $3, $4)`,
		accountID,
		key.Provider,
		key.Issuer,
		key.Subject,
	); err != nil {
		if hasPostgresConstraint(err, "external_identities_provider_subject_key") ||
			hasPostgresConstraint(err, "external_identities_account_provider_key") {
			return ErrFederatedIdentityAlreadyBound
		}
		return fmt.Errorf("insert federated identity: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload)
		 VALUES ($1, $2, 'identity_bound', jsonb_build_object('provider', $3::text, 'issuer', $4::text))`,
		uuid.NewString(),
		accountID,
		key.Provider,
		key.Issuer,
	); err != nil {
		return fmt.Errorf("audit federated identity binding: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit identity binding: %w", err)
	}
	return nil
}

func (store *PostgresFederationStore) FindAccountByIdentity(
	ctx context.Context,
	key FederatedIdentityKey,
) (FederatedAccount, error) {
	var account FederatedAccount
	err := store.database.QueryRowContext(
		ctx,
		`SELECT external_identities.account_id, vaults.id
		 FROM external_identities
		 JOIN vaults ON vaults.owner_account_id = external_identities.account_id
		 WHERE external_identities.provider = $1
		   AND external_identities.issuer = $2
		   AND external_identities.subject = $3
		   AND vaults.status = 'active'`,
		key.Provider,
		key.Issuer,
		key.Subject,
	).Scan(&account.AccountID, &account.VaultID)
	if errors.Is(err, sql.ErrNoRows) {
		return FederatedAccount{}, ErrFederatedIdentityNotBound
	}
	if err != nil {
		return FederatedAccount{}, fmt.Errorf("find federated identity account: %w", err)
	}
	return account, nil
}

func hasPostgresConstraint(err error, name string) bool {
	var postgresError *pgconn.PgError
	return errors.As(err, &postgresError) && postgresError.ConstraintName == name
}
