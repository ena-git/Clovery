package device

import (
	"context"
	"database/sql"
	"fmt"
)

type PostgresRepository struct {
	database *sql.DB
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{database: database}
}

func (repository *PostgresRepository) List(
	ctx context.Context,
	accountID string,
) ([]Device, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT id, display_name, platform, created_at, revoked_at FROM devices
		 WHERE account_id = $1 ORDER BY created_at DESC`,
		accountID,
	)
	if err != nil {
		return nil, fmt.Errorf("list account devices: %w", err)
	}
	defer rows.Close()

	var devices []Device
	for rows.Next() {
		var listed Device
		var revokedAt sql.NullTime
		if err := rows.Scan(
			&listed.ID,
			&listed.DisplayName,
			&listed.Platform,
			&listed.CreatedAt,
			&revokedAt,
		); err != nil {
			return nil, fmt.Errorf("scan account device: %w", err)
		}
		if revokedAt.Valid {
			listed.RevokedAt = &revokedAt.Time
		}
		devices = append(devices, listed)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate account devices: %w", err)
	}
	return devices, nil
}
