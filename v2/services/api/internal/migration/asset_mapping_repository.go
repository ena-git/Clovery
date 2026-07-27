package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

func (repository *PostgresRepository) GetAssetMappings(
	ctx context.Context,
	vaultID string,
	migrationID string,
) ([]AssetMapping, error) {
	var status string
	err := repository.database.QueryRowContext(
		ctx,
		"SELECT status FROM vault_migrations WHERE id = $1 AND vault_id = $2",
		migrationID,
		vaultID,
	).Scan(&status)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrMigrationNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("load migration asset status: %w", err)
	}
	if status != "verified" {
		return nil, ErrMigrationNotVerified
	}

	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT item.source_filename, item.asset_id, item.byte_size, item.sha256
		 FROM migration_assets item
		 JOIN vault_assets asset ON asset.id = item.asset_id
		 WHERE item.migration_id = $1 AND asset.vault_id = $2 AND asset.status = 'complete'
		 ORDER BY item.source_filename, item.asset_id`,
		migrationID,
		vaultID,
	)
	if err != nil {
		return nil, fmt.Errorf("load migration asset mappings: %w", err)
	}
	defer rows.Close()

	mappings := make([]AssetMapping, 0)
	for rows.Next() {
		var mapping AssetMapping
		if err := rows.Scan(
			&mapping.SourceFilename,
			&mapping.AssetID,
			&mapping.ByteSize,
			&mapping.SHA256,
		); err != nil {
			return nil, fmt.Errorf("scan migration asset mapping: %w", err)
		}
		mappings = append(mappings, mapping)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate migration asset mappings: %w", err)
	}
	return mappings, nil
}
