package billing

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

func claimPurchaseChain(
	ctx context.Context,
	transaction *sql.Tx,
	accountID string,
	verified VerifiedTransaction,
	now time.Time,
) error {
	chainKey := verified.Storefront + ":" + verified.OriginalTransactionID
	if _, err := transaction.ExecContext(
		ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", chainKey,
	); err != nil {
		return fmt.Errorf("lock purchase chain: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO store_purchase_chains (
		storefront, original_transaction_id, account_id, created_at, updated_at
	) VALUES ($1,$2,$3,$4,$4)
	ON CONFLICT (storefront, original_transaction_id) DO NOTHING`,
		verified.Storefront, verified.OriginalTransactionID, accountID, now,
	); err != nil {
		return fmt.Errorf("claim purchase chain: %w", err)
	}
	var ownerAccountID string
	err := transaction.QueryRowContext(ctx, `SELECT account_id::text
		FROM store_purchase_chains
		WHERE storefront = $1 AND original_transaction_id = $2
		FOR UPDATE`, verified.Storefront, verified.OriginalTransactionID).Scan(&ownerAccountID)
	if errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("load purchase chain owner: %w", err)
	}
	if err != nil {
		return fmt.Errorf("load purchase chain owner: %w", err)
	}
	if ownerAccountID != accountID {
		return ErrTransactionClaimed
	}
	return nil
}
