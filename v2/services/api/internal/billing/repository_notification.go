package billing

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

func (repository *PostgresRepository) RecordNotification(
	ctx context.Context,
	accountID string,
	notification AppleNotification,
	now time.Time,
) error {
	if notification.Transaction == nil && accountID != "" {
		return ErrVerificationFailed
	}
	if notification.Transaction != nil &&
		((accountID == "" && notification.Transaction.AppAccountToken != "") ||
			(accountID != "" && notification.Transaction.AppAccountToken != accountID)) {
		return ErrVerificationFailed
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Apple notification write: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	var environmentValue, accountIDValue, storefrontValue, transactionIDValue any
	if notification.Environment.Valid() {
		environmentValue = notification.Environment
	}
	if notification.Transaction != nil {
		if accountID != "" {
			accountIDValue = accountID
		}
		storefrontValue = notification.Transaction.Storefront
		transactionIDValue = notification.Transaction.TransactionID
	}
	var notificationID string
	err = transaction.QueryRowContext(ctx, `INSERT INTO apple_store_notifications (
		notification_uuid, notification_type, subtype, environment, account_id, storefront,
		transaction_id, signed_at, payload_sha256, received_at, processed_at
	) VALUES ($1,$2,NULLIF($3,''),$4,$5,$6,$7,$8,$9,$10,$10)
	ON CONFLICT (notification_uuid) DO NOTHING RETURNING notification_uuid`,
		notification.ID, notification.Type, notification.Subtype, environmentValue,
		accountIDValue, storefrontValue, transactionIDValue,
		notification.SignedAt, notification.PayloadSHA256, now,
	).Scan(&notificationID)
	if errors.Is(err, sql.ErrNoRows) {
		if err := transaction.Commit(); err != nil {
			return fmt.Errorf("commit duplicate Apple notification: %w", err)
		}
		return nil
	}
	if err != nil {
		return fmt.Errorf("record Apple notification: %w", err)
	}
	if notification.Transaction != nil && accountID != "" {
		if _, err := recordVerifiedTransaction(
			ctx, transaction, accountID, *notification.Transaction, now,
		); err != nil {
			return err
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Apple notification: %w", err)
	}
	return nil
}
