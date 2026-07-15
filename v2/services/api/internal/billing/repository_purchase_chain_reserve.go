package billing

import (
	"context"
	"fmt"
	"time"
)

func (repository *PostgresRepository) ReservePurchaseChain(
	ctx context.Context,
	accountID string,
	verified VerifiedTransaction,
	now time.Time,
) error {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin purchase chain reservation: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()
	if err := claimPurchaseChain(ctx, transaction, accountID, verified, now); err != nil {
		return err
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit purchase chain reservation: %w", err)
	}
	return nil
}
