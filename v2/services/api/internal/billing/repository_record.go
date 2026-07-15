package billing

import (
	"context"
	"fmt"
	"time"
)

func (repository *PostgresRepository) Record(
	ctx context.Context,
	accountID string,
	verified VerifiedTransaction,
	now time.Time,
) (Entitlement, error) {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return Entitlement{}, fmt.Errorf("begin billing ledger write: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()
	entitlement, err := recordVerifiedTransaction(ctx, transaction, accountID, verified, now)
	if err != nil {
		return Entitlement{}, err
	}
	if err := transaction.Commit(); err != nil {
		return Entitlement{}, fmt.Errorf("commit billing ledger write: %w", err)
	}
	return entitlement, nil
}
