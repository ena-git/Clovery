package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

func (repository *PostgresRepository) Verify(
	ctx context.Context,
	vaultID string,
	migrationID string,
) (Report, error) {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return Report{}, fmt.Errorf("begin migration verification: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	var status string
	err = transaction.QueryRowContext(
		ctx,
		"SELECT status FROM vault_migrations WHERE id = $1 AND vault_id = $2 FOR UPDATE",
		migrationID,
		vaultID,
	).Scan(&status)
	if errors.Is(err, sql.ErrNoRows) {
		return Report{}, ErrMigrationNotFound
	}
	if err != nil {
		return Report{}, fmt.Errorf("lock migration: %w", err)
	}
	if status == "verified" {
		report, err := loadReport(ctx, transaction, vaultID, migrationID)
		if err == nil {
			err = transaction.Commit()
		}
		return report, err
	}

	report, err := loadReport(ctx, transaction, vaultID, migrationID)
	if err != nil {
		return Report{}, err
	}
	if err := verifyStoredManifest(ctx, transaction, vaultID, migrationID); err != nil {
		if errors.Is(err, ErrIntegrityMismatch) {
			return Report{}, commitVerificationError(
				ctx, transaction, migrationID, "manifest_sha256_mismatch", ErrIntegrityMismatch,
			)
		}
		return Report{}, err
	}
	if report.ExpectedEntries != report.ImportedEntries ||
		report.ExpectedDeletedEntries != report.ImportedDeletedEntries ||
		report.ExpectedAssets != report.VerifiedAssets ||
		report.ExpectedBytes != report.VerifiedBytes {
		return report, commitVerificationError(
			ctx, transaction, migrationID, "count_or_size_mismatch", ErrVerificationFailed,
		)
	}
	if err := lockMigrationEntries(ctx, transaction, vaultID, migrationID); err != nil {
		return Report{}, err
	}

	var collisions int
	if err := transaction.QueryRowContext(
		ctx,
		`SELECT COUNT(*) FROM migration_entries source
		 JOIN journal_entries target ON target.id = source.entry_id AND target.vault_id = $2
		 WHERE source.migration_id = $1
		   AND target.imported_by_migration_id IS DISTINCT FROM $1::uuid`,
		migrationID,
		vaultID,
	).Scan(&collisions); err != nil {
		return Report{}, fmt.Errorf("check migration entry collisions: %w", err)
	}
	if collisions > 0 {
		return Report{}, commitVerificationError(
			ctx, transaction, migrationID, "entry_collision", ErrEntryCollision,
		)
	}
	now := time.Now().UTC()
	insertResult, err := transaction.ExecContext(
		ctx,
		`INSERT INTO journal_entries (
		 id, vault_id, revision, payload, deleted_at, updated_at, imported_by_migration_id
		 ) SELECT entry_id, $2, 1, payload, deleted_at, $3, $1
		 FROM migration_entries WHERE migration_id = $1
		 ON CONFLICT (id, vault_id) DO NOTHING`,
		migrationID, vaultID, now,
	)
	if err != nil {
		return Report{}, fmt.Errorf("import migration entries: %w", err)
	}
	insertedEntries, err := insertResult.RowsAffected()
	if err != nil {
		return Report{}, fmt.Errorf("count imported migration entries: %w", err)
	}
	if insertedEntries != int64(report.ImportedEntries+report.ImportedDeletedEntries) {
		return Report{}, repository.rollbackVerificationError(
			ctx, transaction, vaultID, migrationID, "entry_collision", ErrEntryCollision,
		)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO sync_changes (
		 vault_id, entity_type, entity_id, revision, operation_id, payload, deleted, changed_at
		 ) SELECT $2, 'journal_entry', entry_id, 1, operation_id,
		 CASE WHEN deleted_at IS NULL THEN payload ELSE '{}'::jsonb END,
		 deleted_at IS NOT NULL, $3 FROM migration_entries WHERE migration_id = $1`,
		migrationID, vaultID, now,
	); err != nil {
		return Report{}, fmt.Errorf("publish migrated entries: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE vault_migrations SET status = 'verified', verified_at = $2, last_errors = '[]'::jsonb
		 WHERE id = $1`,
		migrationID, now,
	); err != nil {
		return Report{}, fmt.Errorf("complete migration verification: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload, created_at)
		 SELECT $1, owner_account_id, 'vault_migration_verified', jsonb_build_object('migration_id', $2::uuid), $3
		 FROM vaults WHERE id = $4`,
		uuid.NewString(), migrationID, now, vaultID,
	); err != nil {
		return Report{}, fmt.Errorf("audit verified migration: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return Report{}, fmt.Errorf("commit migration verification: %w", err)
	}
	report.Status = "verified"
	report.VerifiedAt = &now
	report.Errors = []byte(`[]`)
	return report, nil
}
