package migration

import (
	"context"
	"database/sql"
	"fmt"
)

func lockMigrationEntries(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
) error {
	_, err := transaction.ExecContext(
		ctx,
		"SELECT pg_advisory_xact_lock(hashtextextended('journal_entry:' || $1 || ':' || entry_id::text, 0)) FROM migration_entries WHERE migration_id = $2 ORDER BY entry_id",
		vaultID,
		migrationID,
	)
	if err != nil {
		return fmt.Errorf("lock migration journal entries: %w", err)
	}
	return nil
}
