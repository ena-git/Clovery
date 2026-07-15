package account

import (
	"context"
	"fmt"
)

type CreateAccountParams struct {
	AccountID    string
	VaultID      string
	LoginID      string
	PasswordHash string
}

func (repository *Repository) CreateAccount(ctx context.Context, params CreateAccountParams) error {
	normalizedID, err := NormalizeLoginID(params.LoginID)
	if err != nil {
		return err
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin account transaction: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	if _, err := transaction.ExecContext(ctx, "INSERT INTO clovery_accounts (id) VALUES ($1)", params.AccountID); err != nil {
		return fmt.Errorf("insert account: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		"INSERT INTO account_login_ids (account_id, normalized_id, status) VALUES ($1, $2, 'active')",
		params.AccountID,
		normalizedID,
	); err != nil {
		if isConstraint(err, "account_login_ids_normalized_id_key") {
			return ErrLoginIDUnavailable
		}
		return fmt.Errorf("insert Clovery ID: %w", err)
	}
	if params.PasswordHash != "" {
		if _, err := transaction.ExecContext(
			ctx,
			"INSERT INTO password_credentials (account_id, password_hash) VALUES ($1, $2)",
			params.AccountID,
			params.PasswordHash,
		); err != nil {
			return fmt.Errorf("insert password credential: %w", err)
		}
	}
	if _, err := transaction.ExecContext(
		ctx,
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')",
		params.VaultID,
		params.AccountID,
	); err != nil {
		return fmt.Errorf("insert account vault: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit account transaction: %w", err)
	}
	return nil
}
