package account

import (
	"context"
	"fmt"
)

func (repository *Repository) RenameLoginID(ctx context.Context, accountID string, candidate string) error {
	normalizedID, err := NormalizeLoginID(candidate)
	if err != nil {
		return err
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin login ID rename: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	result, err := transaction.ExecContext(
		ctx,
		`UPDATE account_login_ids
		 SET status = 'retired', retired_at = CURRENT_TIMESTAMP
		 WHERE account_id = $1 AND status = 'active'`,
		accountID,
	)
	if err != nil {
		return fmt.Errorf("retire current Clovery ID: %w", err)
	}
	updatedRows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect retired Clovery ID: %w", err)
	}
	if updatedRows != 1 {
		return ErrAccountNotFound
	}
	if _, err := transaction.ExecContext(
		ctx,
		"INSERT INTO account_login_ids (account_id, normalized_id, status) VALUES ($1, $2, 'active')",
		accountID,
		normalizedID,
	); err != nil {
		if isConstraint(err, "account_login_ids_normalized_id_key") {
			return ErrLoginIDUnavailable
		}
		return fmt.Errorf("insert replacement Clovery ID: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit login ID rename: %w", err)
	}
	return nil
}
