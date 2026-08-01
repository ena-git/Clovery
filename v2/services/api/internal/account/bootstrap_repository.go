package account

import (
	"context"
	"database/sql"
	"fmt"
)

func insertBootstrapJob(
	ctx context.Context,
	transaction *sql.Tx,
	accountID string,
	vaultID string,
	sourceKind string,
) error {
	migrationState := "pending"
	if sourceKind == "new_install" {
		migrationState = "complete"
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO account_bootstrap_jobs (
			account_id, vault_id, source_kind,
			identity_state, migration_state, entitlement_state, vault_state
		) VALUES ($1, $2, $3, 'complete', $4, 'pending', 'pending')`,
		accountID,
		vaultID,
		sourceKind,
		migrationState,
	); err != nil {
		return fmt.Errorf("insert account bootstrap job: %w", err)
	}
	return nil
}
