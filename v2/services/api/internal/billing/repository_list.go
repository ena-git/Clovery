package billing

import (
	"context"
	"database/sql"
	"fmt"
)

const entitlementSelect = `SELECT product_id, state, expires_at, revoked_at,
	source_storefront, source_transaction_id, updated_at FROM entitlements`

func (repository *PostgresRepository) List(
	ctx context.Context,
	accountID string,
) ([]Entitlement, error) {
	rows, err := repository.database.QueryContext(
		ctx, entitlementSelect+" WHERE account_id = $1 ORDER BY product_id", accountID,
	)
	if err != nil {
		return nil, fmt.Errorf("list account entitlements: %w", err)
	}
	defer rows.Close()
	var entitlements []Entitlement
	for rows.Next() {
		entitlement, err := scanEntitlement(rows)
		if err != nil {
			return nil, fmt.Errorf("scan account entitlement: %w", err)
		}
		entitlements = append(entitlements, entitlement)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate account entitlements: %w", err)
	}
	return entitlements, nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanEntitlement(row rowScanner) (Entitlement, error) {
	var entitlement Entitlement
	var expiresAt, revokedAt sql.NullTime
	err := row.Scan(
		&entitlement.ProductID, &entitlement.State, &expiresAt, &revokedAt,
		&entitlement.SourceStorefront, &entitlement.SourceTransactionID, &entitlement.UpdatedAt,
	)
	if expiresAt.Valid {
		entitlement.ExpiresAt = &expiresAt.Time
	}
	if revokedAt.Valid {
		entitlement.RevokedAt = &revokedAt.Time
	}
	return entitlement, err
}
