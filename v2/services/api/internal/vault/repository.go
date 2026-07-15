package vault

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

type PostgresRepository struct {
	database *sql.DB
	now      func() time.Time
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{
		database: database,
		now:      func() time.Time { return time.Now().UTC() },
	}
}

func (repository *PostgresRepository) GetOwned(
	ctx context.Context,
	accountID string,
	vaultID string,
) (Metadata, error) {
	var metadata Metadata
	err := repository.database.QueryRowContext(
		ctx,
		"SELECT id, status, created_at FROM vaults WHERE id = $1 AND owner_account_id = $2",
		vaultID,
		accountID,
	).Scan(&metadata.ID, &metadata.Status, &metadata.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Metadata{}, ErrForbidden
	}
	if err != nil {
		return Metadata{}, fmt.Errorf("load owned vault: %w", err)
	}
	return metadata, nil
}

func (repository *PostgresRepository) RecordAccessDenial(
	ctx context.Context,
	accountID string,
	vaultID string,
) error {
	_, err := repository.database.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload, created_at)
		 VALUES ($1, $2, 'vault_access_denied', jsonb_build_object('requested_vault_id', $3::text), $4)`,
		uuid.NewString(),
		accountID,
		vaultID,
		repository.now(),
	)
	if err != nil {
		return fmt.Errorf("insert vault access audit: %w", err)
	}
	return nil
}
