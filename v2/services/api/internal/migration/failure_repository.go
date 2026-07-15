package migration

import (
	"context"
	"fmt"
)

func (repository *PostgresRepository) RecordError(
	ctx context.Context,
	vaultID string,
	migrationID string,
	code string,
) error {
	_, err := repository.database.ExecContext(
		ctx,
		`UPDATE vault_migrations
		 SET last_errors = last_errors || jsonb_build_array(jsonb_build_object('code', $3::text))
		 WHERE id = $1 AND vault_id = $2`,
		migrationID,
		vaultID,
		code,
	)
	if err != nil {
		return fmt.Errorf("record migration error: %w", err)
	}
	return nil
}
