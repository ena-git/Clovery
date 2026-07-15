package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

func (repository *PostgresRepository) beginUploadingMigration(
	ctx context.Context,
	vaultID string,
	migrationID string,
) (*sql.Tx, error) {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin migration upload: %w", err)
	}

	var status string
	err = transaction.QueryRowContext(
		ctx,
		"SELECT status FROM vault_migrations WHERE id = $1 AND vault_id = $2 FOR UPDATE",
		migrationID,
		vaultID,
	).Scan(&status)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && status != "uploading") {
		_ = transaction.Rollback()
		return nil, ErrMigrationMismatch
	}
	if err != nil {
		_ = transaction.Rollback()
		return nil, fmt.Errorf("lock uploading migration: %w", err)
	}
	return transaction, nil
}
