package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

type queryRower interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func (repository *PostgresRepository) GetReport(
	ctx context.Context,
	vaultID string,
	migrationID string,
) (Report, error) {
	return loadReport(ctx, repository.database, vaultID, migrationID)
}

func loadReport(
	ctx context.Context,
	queryer queryRower,
	vaultID string,
	migrationID string,
) (Report, error) {
	var report Report
	err := queryer.QueryRowContext(
		ctx,
		`SELECT migration.id, migration.status,
		 migration.expected_entry_count,
		 (SELECT COUNT(*) FROM migration_entries WHERE migration_id = migration.id AND deleted_at IS NULL),
		 migration.expected_deleted_count,
		 (SELECT COUNT(*) FROM migration_entries WHERE migration_id = migration.id AND deleted_at IS NOT NULL),
		 migration.expected_asset_count,
		 (SELECT COUNT(*) FROM migration_assets item JOIN vault_assets asset ON asset.id = item.asset_id
		  WHERE item.migration_id = migration.id AND asset.status = 'complete'),
		 migration.expected_total_bytes,
		 COALESCE((SELECT SUM(byte_size) FROM migration_entries WHERE migration_id = migration.id), 0)
		 + COALESCE((SELECT SUM(byte_size) FROM migration_assets WHERE migration_id = migration.id), 0),
		 migration.last_errors, migration.verified_at
		 FROM vault_migrations migration WHERE migration.id = $1 AND migration.vault_id = $2`,
		migrationID,
		vaultID,
	).Scan(
		&report.MigrationID, &report.Status, &report.ExpectedEntries, &report.ImportedEntries,
		&report.ExpectedDeletedEntries, &report.ImportedDeletedEntries,
		&report.ExpectedAssets, &report.VerifiedAssets, &report.ExpectedBytes,
		&report.VerifiedBytes, &report.Errors, &report.VerifiedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Report{}, ErrMigrationNotFound
	}
	if err != nil {
		return Report{}, fmt.Errorf("load migration report: %w", err)
	}
	return report, nil
}
