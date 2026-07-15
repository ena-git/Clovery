package migration

import (
	"context"
	"database/sql"
	"fmt"
)

func commitVerificationError(
	ctx context.Context,
	transaction *sql.Tx,
	migrationID string,
	code string,
	cause error,
) error {
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE vault_migrations
		 SET last_errors = last_errors || jsonb_build_array(jsonb_build_object('code', $2::text))
		 WHERE id = $1`,
		migrationID,
		code,
	); err != nil {
		return fmt.Errorf("record migration verification error: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit migration verification error: %w", err)
	}
	return cause
}

func (repository *PostgresRepository) rollbackVerificationError(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
	code string,
	cause error,
) error {
	if err := transaction.Rollback(); err != nil {
		return fmt.Errorf("rollback failed migration verification: %w", err)
	}
	if err := repository.RecordError(ctx, vaultID, migrationID, code); err != nil {
		return err
	}
	return cause
}
