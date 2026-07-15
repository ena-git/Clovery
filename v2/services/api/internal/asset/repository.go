package asset

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type PostgresRepository struct {
	database *sql.DB
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{database: database}
}

func (repository *PostgresRepository) CreatePending(ctx context.Context, asset Asset) (Asset, error) {
	row := repository.database.QueryRowContext(
		ctx,
		`INSERT INTO vault_assets (
		 id, vault_id, object_key, content_type, byte_size, sha256, status, created_at
		 ) VALUES ($1, $2, $3, $4, $5, $6, 'pending', $7)
		 ON CONFLICT (id) DO NOTHING
		 RETURNING id, vault_id, object_key, content_type, byte_size, sha256, status, created_at, completed_at`,
		asset.ID,
		asset.VaultID,
		asset.ObjectKey,
		asset.ContentType,
		asset.ByteSize,
		asset.SHA256,
		asset.CreatedAt,
	)
	created, err := scanAsset(row)
	if err == nil {
		return created, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return Asset{}, fmt.Errorf("create pending asset: %w", err)
	}

	existing, err := scanAsset(repository.database.QueryRowContext(
		ctx,
		`SELECT id, vault_id, object_key, content_type, byte_size, sha256, status, created_at, completed_at
		 FROM vault_assets
		 WHERE id = $1 AND vault_id = $2 AND object_key = $3 AND content_type = $4
		   AND byte_size = $5 AND sha256 = $6`,
		asset.ID,
		asset.VaultID,
		asset.ObjectKey,
		asset.ContentType,
		asset.ByteSize,
		asset.SHA256,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return Asset{}, ErrAssetMetadataMismatch
	}
	if err != nil {
		return Asset{}, fmt.Errorf("load existing pending asset: %w", err)
	}
	return existing, nil
}

func (repository *PostgresRepository) Get(
	ctx context.Context,
	vaultID string,
	assetID string,
) (Asset, error) {
	asset, err := scanAsset(repository.database.QueryRowContext(
		ctx,
		`SELECT id, vault_id, object_key, content_type, byte_size, sha256, status, created_at, completed_at
		 FROM vault_assets WHERE vault_id = $1 AND id = $2`,
		vaultID,
		assetID,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return Asset{}, ErrAssetNotFound
	}
	if err != nil {
		return Asset{}, fmt.Errorf("load vault asset: %w", err)
	}
	return asset, nil
}

func (repository *PostgresRepository) MarkComplete(
	ctx context.Context,
	vaultID string,
	assetID string,
	completedAt time.Time,
) error {
	var id string
	err := repository.database.QueryRowContext(
		ctx,
		`UPDATE vault_assets SET status = 'complete', completed_at = COALESCE(completed_at, $3)
		 WHERE vault_id = $1 AND id = $2 AND status IN ('pending', 'complete') RETURNING id`,
		vaultID,
		assetID,
		completedAt,
	).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrAssetNotFound
	}
	if err != nil {
		return fmt.Errorf("complete vault asset: %w", err)
	}
	return nil
}

func (repository *PostgresRepository) DeletePending(
	ctx context.Context,
	vaultID string,
	assetID string,
) error {
	_, err := repository.database.ExecContext(
		ctx,
		`DELETE FROM vault_assets asset
		 WHERE asset.vault_id = $1 AND asset.id = $2 AND asset.status = 'pending'
		   AND NOT EXISTS (SELECT 1 FROM migration_assets item WHERE item.asset_id = asset.id)`,
		vaultID,
		assetID,
	)
	if err != nil {
		return fmt.Errorf("discard pending vault asset: %w", err)
	}
	return nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanAsset(row rowScanner) (Asset, error) {
	var asset Asset
	var completedAt sql.NullTime
	err := row.Scan(
		&asset.ID,
		&asset.VaultID,
		&asset.ObjectKey,
		&asset.ContentType,
		&asset.ByteSize,
		&asset.SHA256,
		&asset.Status,
		&asset.CreatedAt,
		&completedAt,
	)
	if completedAt.Valid {
		asset.CompletedAt = &completedAt.Time
	}
	return asset, err
}
