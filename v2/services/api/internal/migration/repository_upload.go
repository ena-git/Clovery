package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

func (repository *PostgresRepository) Create(ctx context.Context, migration Migration) (Migration, error) {
	err := repository.database.QueryRowContext(
		ctx,
		`INSERT INTO vault_migrations (
		 id, vault_id, format_version, source, expected_entry_count, expected_deleted_count,
		 expected_asset_count, expected_total_bytes, manifest_sha256, manifest, manifest_bytes, status, created_at
		 ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'uploading', $12)
		 ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id
		 WHERE vault_migrations.vault_id = EXCLUDED.vault_id
		   AND vault_migrations.format_version = EXCLUDED.format_version
		   AND vault_migrations.source = EXCLUDED.source
		   AND vault_migrations.expected_entry_count = EXCLUDED.expected_entry_count
		   AND vault_migrations.expected_deleted_count = EXCLUDED.expected_deleted_count
		   AND vault_migrations.expected_asset_count = EXCLUDED.expected_asset_count
		   AND vault_migrations.expected_total_bytes = EXCLUDED.expected_total_bytes
		   AND vault_migrations.manifest_sha256 = EXCLUDED.manifest_sha256
		   AND vault_migrations.manifest = EXCLUDED.manifest
		   AND vault_migrations.manifest_bytes = EXCLUDED.manifest_bytes
		 RETURNING id, vault_id, format_version, source, expected_entry_count, expected_deleted_count,
		 expected_asset_count, expected_total_bytes, manifest_sha256, status, created_at`,
		migration.ID, migration.VaultID, migration.FormatVersion, migration.Source,
		migration.EntryCount, migration.DeletedCount, migration.AssetCount, migration.TotalBytes,
		migration.ManifestSHA256, migration.Manifest, migration.ManifestBytes, migration.CreatedAt,
	).Scan(
		&migration.ID, &migration.VaultID, &migration.FormatVersion, &migration.Source,
		&migration.EntryCount, &migration.DeletedCount, &migration.AssetCount, &migration.TotalBytes,
		&migration.ManifestSHA256, &migration.Status, &migration.CreatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Migration{}, ErrMigrationMismatch
	}
	if err != nil {
		return Migration{}, fmt.Errorf("create Vault migration: %w", err)
	}
	return migration, nil
}

func (repository *PostgresRepository) AddEntry(
	ctx context.Context,
	vaultID string,
	migrationID string,
	entry EntryInput,
) error {
	if entry.SourceEntryID == "" {
		entry.SourceEntryID = entry.EntryID
	}
	transaction, err := repository.beginUploadingMigration(ctx, vaultID, migrationID)
	if err != nil {
		return err
	}
	defer func() { _ = transaction.Rollback() }()

	var entryID string
	err = transaction.QueryRowContext(
		ctx,
		`INSERT INTO migration_entries (
		 migration_id, entry_id, source_entry_id, operation_id, payload, deleted_at, sha256, byte_size
		 ) SELECT migration.id, $3::uuid, $4, $5::uuid, $6::jsonb, $7::timestamptz, $8, $9
		 FROM vault_migrations migration
		 WHERE migration.id = $1 AND migration.vault_id = $2 AND migration.status = 'uploading'
		   AND (
		     ($7::timestamptz IS NULL AND EXISTS (
		       SELECT 1 FROM jsonb_array_elements(migration.manifest -> 'entries') item
		       WHERE item ->> 'entry_id' = $4
		         AND lower(item ->> 'sha256') = $8
		         AND (item ->> 'bytes')::bigint = $9
		     ))
		     OR
		     ($7::timestamptz IS NOT NULL
		       AND migration.manifest -> 'deleted_ids' ? $4
		       AND $6::jsonb = '{}'::jsonb
		       AND $8 = '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a'
		       AND $9 = 2)
		   )
		 ON CONFLICT (migration_id, source_entry_id) DO UPDATE SET source_entry_id = EXCLUDED.source_entry_id
		 WHERE migration_entries.entry_id = EXCLUDED.entry_id
		   AND migration_entries.sha256 = EXCLUDED.sha256
		   AND migration_entries.deleted_at IS NOT DISTINCT FROM EXCLUDED.deleted_at
		 RETURNING entry_id`,
		migrationID, vaultID, entry.EntryID, entry.SourceEntryID, uuid.NewString(), entry.Payload,
		entry.DeletedAt, entry.SHA256, len(entry.Payload),
	).Scan(&entryID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrMigrationMismatch
	}
	if err != nil {
		return fmt.Errorf("add migration entry: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit migration entry: %w", err)
	}
	return nil
}

func (repository *PostgresRepository) AddAsset(
	ctx context.Context,
	vaultID string,
	migrationID string,
	assetID string,
	sourceFilename string,
	byteSize int64,
	sha256 string,
) error {
	transaction, err := repository.beginUploadingMigration(ctx, vaultID, migrationID)
	if err != nil {
		return err
	}
	defer func() { _ = transaction.Rollback() }()

	var storedAssetID string
	err = transaction.QueryRowContext(
		ctx,
		`INSERT INTO migration_assets (migration_id, asset_id, source_filename, byte_size, sha256)
		 SELECT migration.id, asset.id, $4, $5, $6
		 FROM vault_migrations migration
		 JOIN vault_assets asset ON asset.id = $3 AND asset.vault_id = migration.vault_id
		 JOIN LATERAL jsonb_array_elements(migration.manifest -> 'photos') photo ON TRUE
		 WHERE migration.id = $1 AND migration.vault_id = $2 AND migration.status = 'uploading'
		   AND photo.value ->> 'filename' = $4
		   AND (photo.value ->> 'bytes')::bigint = $5
		   AND lower(photo.value ->> 'sha256') = $6
		 ON CONFLICT (migration_id, source_filename) DO UPDATE SET source_filename = EXCLUDED.source_filename
		 WHERE migration_assets.asset_id = EXCLUDED.asset_id
		   AND migration_assets.byte_size = EXCLUDED.byte_size
		   AND migration_assets.sha256 = EXCLUDED.sha256
		 RETURNING asset_id`,
		migrationID, vaultID, assetID, sourceFilename, byteSize, sha256,
	).Scan(&storedAssetID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrMigrationMismatch
	}
	if err != nil {
		return fmt.Errorf("add migration asset: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit migration asset: %w", err)
	}
	return nil
}
