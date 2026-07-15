package billing

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

func recordVerifiedTransaction(
	ctx context.Context,
	transaction *sql.Tx,
	accountID string,
	verified VerifiedTransaction,
	now time.Time,
) (Entitlement, error) {
	if err := claimPurchaseChain(ctx, transaction, accountID, verified, now); err != nil {
		return Entitlement{}, err
	}
	if _, err := transaction.ExecContext(
		ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
		verified.Storefront+":"+verified.TransactionID,
	); err != nil {
		return Entitlement{}, fmt.Errorf("lock store transaction: %w", err)
	}
	var existingAccountID string
	var existingSignedAt sql.NullTime
	err := transaction.QueryRowContext(
		ctx,
		"SELECT account_id::text, NULLIF(verification_metadata->>'signed_at', '')::timestamptz FROM store_transactions WHERE storefront = $1 AND transaction_id = $2 FOR UPDATE",
		verified.Storefront, verified.TransactionID,
	).Scan(&existingAccountID, &existingSignedAt)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return Entitlement{}, fmt.Errorf("load store transaction owner: %w", err)
	}
	if err == nil && existingAccountID != accountID {
		return Entitlement{}, ErrTransactionClaimed
	}
	if err == nil && existingSignedAt.Valid && verified.Metadata.SignedAt.Before(existingSignedAt.Time) {
		entitlement, loadErr := scanEntitlement(transaction.QueryRowContext(
			ctx, entitlementSelect+" WHERE account_id = $1 AND product_id = $2", accountID, verified.ProductID,
		))
		if loadErr != nil {
			return Entitlement{}, fmt.Errorf("load newer entitlement: %w", loadErr)
		}
		return entitlement, nil
	}
	metadata, err := json.Marshal(verified.Metadata)
	if err != nil {
		return Entitlement{}, fmt.Errorf("encode verification metadata: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO store_transactions (
		storefront, transaction_id, account_id, original_transaction_id, product_id, environment,
		purchase_at, expires_at, revoked_at, app_account_token, verification_metadata, status,
		created_at, updated_at
	) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13)
	ON CONFLICT (storefront, transaction_id) DO UPDATE SET
		original_transaction_id = EXCLUDED.original_transaction_id,
		product_id = EXCLUDED.product_id, environment = EXCLUDED.environment,
		purchase_at = EXCLUDED.purchase_at, expires_at = EXCLUDED.expires_at,
		revoked_at = EXCLUDED.revoked_at, app_account_token = EXCLUDED.app_account_token,
		verification_metadata = EXCLUDED.verification_metadata, status = EXCLUDED.status,
		updated_at = EXCLUDED.updated_at
	WHERE store_transactions.account_id = EXCLUDED.account_id
	  AND COALESCE((store_transactions.verification_metadata->>'signed_at')::timestamptz
	      <= (EXCLUDED.verification_metadata->>'signed_at')::timestamptz, TRUE)`,
		verified.Storefront, verified.TransactionID, accountID, verified.OriginalTransactionID,
		verified.ProductID, verified.Environment, verified.PurchaseAt, verified.ExpiresAt,
		verified.RevokedAt, verified.AppAccountToken, metadata, verified.Status, now,
	); err != nil {
		return Entitlement{}, fmt.Errorf("record store transaction: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO entitlements (
		account_id, product_id, state, expires_at, revoked_at, source_storefront,
		source_transaction_id, source_purchase_at, created_at, updated_at
	) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)
	ON CONFLICT (account_id, product_id) DO UPDATE SET
		state = EXCLUDED.state, expires_at = EXCLUDED.expires_at, revoked_at = EXCLUDED.revoked_at,
		source_storefront = EXCLUDED.source_storefront,
		source_transaction_id = EXCLUDED.source_transaction_id,
		source_purchase_at = EXCLUDED.source_purchase_at, updated_at = EXCLUDED.updated_at
	WHERE (
		entitlements.source_purchase_at < EXCLUDED.source_purchase_at
		OR entitlements.source_transaction_id = EXCLUDED.source_transaction_id
	)
	AND NOT (
		$10 = 'app_store_server_api'
		AND entitlements.state = 'active'
		AND entitlements.expires_at > $9
		AND EXCLUDED.state = 'expired'
		AND EXCLUDED.expires_at < entitlements.expires_at
	)`,
		accountID, verified.ProductID, verified.Status, verified.ExpiresAt, verified.RevokedAt,
		verified.Storefront, verified.TransactionID, verified.PurchaseAt, now, verified.Metadata.Source,
	); err != nil {
		return Entitlement{}, fmt.Errorf("record entitlement: %w", err)
	}
	entitlement, err := scanEntitlement(transaction.QueryRowContext(
		ctx, entitlementSelect+" WHERE account_id = $1 AND product_id = $2", accountID, verified.ProductID,
	))
	if err != nil {
		return Entitlement{}, fmt.Errorf("load recorded entitlement: %w", err)
	}
	return entitlement, nil
}
