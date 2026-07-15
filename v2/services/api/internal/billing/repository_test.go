package billing

import (
	"context"
	"database/sql"
	"errors"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPostgresRepositoryRecordsTransactionAndEntitlementAtomically(t *testing.T) {
	database, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() error = %v", err)
	}
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	transaction := verifiedTransactionFixture()
	now := time.Date(2026, 7, 14, 13, 0, 0, 0, time.UTC)

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, transaction, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(regexp.QuoteMeta(
		"SELECT account_id::text, NULLIF(verification_metadata->>'signed_at', '')::timestamptz FROM store_transactions WHERE storefront = $1 AND transaction_id = $2 FOR UPDATE",
	)).WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("INSERT INTO store_transactions").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO entitlements").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery("SELECT product_id, state").WillReturnRows(entitlementRows(transaction, now))
	mock.ExpectCommit()

	entitlement, err := repository.Record(context.Background(), billingAccountID, transaction, now)
	if err != nil {
		t.Fatalf("Record() error = %v", err)
	}
	if entitlement.State != StateActive || entitlement.SourceTransactionID != transaction.TransactionID {
		t.Fatalf("Record() entitlement = %#v", entitlement)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryReservesPurchaseChainBeforeExternalMutation(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	verified := verifiedTransactionFixture()
	verified.AppAccountToken = ""
	now := time.Date(2026, time.July, 14, 13, 0, 0, 0, time.UTC)

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, verified, billingAccountID)
	mock.ExpectCommit()

	if err := repository.ReservePurchaseChain(
		context.Background(), billingAccountID, verified, now,
	); err != nil {
		t.Fatalf("ReservePurchaseChain() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryRejectsTransactionOwnedByAnotherAccount(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	verified := verifiedTransactionFixture()

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, verified, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT account_id::text, NULLIF\\(verification_metadata->>'signed_at'").
		WillReturnRows(sqlmock.NewRows([]string{"account_id", "signed_at"}).AddRow(otherAccountID, time.Now().UTC()))
	mock.ExpectRollback()

	_, err := repository.Record(
		context.Background(), billingAccountID, verified, time.Now().UTC(),
	)
	if !errors.Is(err, ErrTransactionClaimed) {
		t.Fatalf("Record() error = %v, want ErrTransactionClaimed", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryRejectsRenewalChainOwnedByAnotherAccount(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	verified := verifiedTransactionFixture()
	verified.TransactionID = "renewal-tx-2"

	mock.ExpectBegin()
	mock.ExpectExec("pg_advisory_xact_lock").
		WithArgs(verified.Storefront + ":" + verified.OriginalTransactionID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO store_purchase_chains").
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery("SELECT account_id::text FROM store_purchase_chains").
		WillReturnRows(sqlmock.NewRows([]string{"account_id"}).AddRow(otherAccountID))
	mock.ExpectRollback()

	_, err := repository.Record(context.Background(), billingAccountID, verified, time.Now().UTC())
	if !errors.Is(err, ErrTransactionClaimed) {
		t.Fatalf("Record() error = %v, want ErrTransactionClaimed", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryRefreshesStateForIdenticalTransactionReplay(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	transaction := verifiedTransactionFixture()
	storedAt := time.Date(2026, 7, 14, 12, 30, 0, 0, time.UTC)
	replayedAt := storedAt.Add(time.Hour)

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, transaction, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT account_id::text, NULLIF\\(verification_metadata->>'signed_at'").
		WillReturnRows(sqlmock.NewRows([]string{"account_id", "signed_at"}).
			AddRow(billingAccountID, transaction.Metadata.SignedAt))
	mock.ExpectExec("INSERT INTO store_transactions").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO entitlements").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery("SELECT product_id, state").WillReturnRows(entitlementRows(transaction, replayedAt))
	mock.ExpectCommit()

	entitlement, err := repository.Record(
		context.Background(), billingAccountID, transaction, replayedAt,
	)
	if err != nil {
		t.Fatalf("Record() replay error = %v", err)
	}
	if !entitlement.UpdatedAt.Equal(replayedAt) {
		t.Fatalf("replay entitlement timestamp = %v", entitlement.UpdatedAt)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryDoesNotLetOlderSignedStateOverwriteNewerState(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	incoming := verifiedTransactionFixture()
	newerSignedAt := incoming.Metadata.SignedAt.Add(time.Hour)
	now := newerSignedAt.Add(time.Minute)
	stored := incoming
	stored.Status = StateRevoked

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, incoming, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT account_id::text, NULLIF\\(verification_metadata->>'signed_at'").
		WillReturnRows(sqlmock.NewRows([]string{"account_id", "signed_at"}).
			AddRow(billingAccountID, newerSignedAt))
	mock.ExpectQuery("SELECT product_id, state").WillReturnRows(entitlementRows(stored, now))
	mock.ExpectCommit()

	entitlement, err := repository.Record(context.Background(), billingAccountID, incoming, now)
	if err != nil {
		t.Fatalf("Record() stale state error = %v", err)
	}
	if entitlement.State != StateRevoked {
		t.Fatalf("Record() stale entitlement = %#v", entitlement)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryDoesNotLetTransactionRefreshEndGraceEarly(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	now := time.Date(2026, time.July, 14, 20, 0, 0, 0, time.UTC)
	incoming := verifiedTransactionFixture()
	incoming.Status = StateExpired
	incoming.Metadata.Source = "app_store_server_api"
	incoming.Metadata.SignedAt = now
	expiredAt := now.Add(-time.Hour)
	incoming.ExpiresAt = &expiredAt
	grace := incoming
	grace.Status = StateActive
	graceExpiresAt := now.Add(24 * time.Hour)
	grace.ExpiresAt = &graceExpiresAt

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, incoming, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT account_id::text, NULLIF\\(verification_metadata->>'signed_at'").
		WillReturnRows(sqlmock.NewRows([]string{"account_id", "signed_at"}).
			AddRow(billingAccountID, now.Add(-time.Minute)))
	mock.ExpectExec("INSERT INTO store_transactions").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO entitlements").WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery("SELECT product_id, state").WillReturnRows(entitlementRows(grace, now))
	mock.ExpectCommit()

	entitlement, err := repository.Record(context.Background(), billingAccountID, incoming, now)
	if err != nil {
		t.Fatalf("Record() transaction refresh error = %v", err)
	}
	if entitlement.State != StateActive || entitlement.ExpiresAt == nil ||
		!entitlement.ExpiresAt.Equal(graceExpiresAt) {
		t.Fatalf("Record() grace entitlement = %#v", entitlement)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryRollsBackWhenEntitlementWriteFails(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	verified := verifiedTransactionFixture()

	mock.ExpectBegin()
	expectPurchaseChainClaim(mock, verified, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT account_id::text, NULLIF\\(verification_metadata->>'signed_at'").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("INSERT INTO store_transactions").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO entitlements").WillReturnError(errors.New("write failed"))
	mock.ExpectRollback()

	_, err := repository.Record(
		context.Background(), billingAccountID, verified, time.Now().UTC(),
	)
	if err == nil {
		t.Fatal("Record() accepted a failed entitlement write")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryListsOnlyRequestedAccount(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	transaction := verifiedTransactionFixture()
	now := time.Now().UTC()
	mock.ExpectQuery("FROM entitlements WHERE account_id = \\$1").
		WithArgs(billingAccountID).
		WillReturnRows(entitlementRows(transaction, now))

	entitlements, err := repository.List(context.Background(), billingAccountID)
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(entitlements) != 1 || entitlements[0].ProductID != transaction.ProductID {
		t.Fatalf("List() = %#v", entitlements)
	}
}

func TestPostgresRepositoryRecordsNotificationAndEntitlementAtomically(t *testing.T) {
	database, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() error = %v", err)
	}
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	verified := verifiedTransactionFixture()
	now := time.Date(2026, time.July, 14, 19, 30, 0, 0, time.UTC)
	notification := AppleNotification{
		ID: "33333333-3333-4333-8333-333333333333", Type: "REFUND",
		Environment: verified.Environment, SignedAt: now.Add(-time.Minute),
		PayloadSHA256: strings.Repeat("a", 64), Transaction: &verified,
	}

	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO apple_store_notifications").
		WillReturnRows(sqlmock.NewRows([]string{"notification_uuid"}).AddRow(notification.ID))
	expectPurchaseChainClaim(mock, verified, billingAccountID)
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT account_id::text, NULLIF\\(verification_metadata->>'signed_at'").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("INSERT INTO store_transactions").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO entitlements").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery("SELECT product_id, state").WillReturnRows(entitlementRows(verified, now))
	mock.ExpectCommit()

	if err := repository.RecordNotification(
		context.Background(), billingAccountID, notification, now,
	); err != nil {
		t.Fatalf("RecordNotification() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryAcknowledgesDuplicateNotificationIdempotently(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	verified := verifiedTransactionFixture()
	notification := AppleNotification{
		ID: "33333333-3333-4333-8333-333333333333", Type: "DID_RENEW",
		Environment: verified.Environment, SignedAt: time.Now().UTC(),
		PayloadSHA256: strings.Repeat("a", 64), Transaction: &verified,
	}

	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO apple_store_notifications").WillReturnError(sql.ErrNoRows)
	mock.ExpectCommit()

	if err := repository.RecordNotification(
		context.Background(), billingAccountID, notification, time.Now().UTC(),
	); err != nil {
		t.Fatalf("RecordNotification() duplicate error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryRecordsNotificationWithoutTransaction(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	now := time.Date(2026, time.July, 14, 20, 0, 0, 0, time.UTC)
	notification := AppleNotification{
		ID: "33333333-3333-4333-8333-333333333333", Type: "TEST",
		SignedAt: now.Add(-time.Minute), PayloadSHA256: strings.Repeat("a", 64),
	}

	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO apple_store_notifications").
		WithArgs(
			notification.ID, notification.Type, notification.Subtype, nil, nil, nil, nil,
			notification.SignedAt, notification.PayloadSHA256, now,
		).
		WillReturnRows(sqlmock.NewRows([]string{"notification_uuid"}).AddRow(notification.ID))
	mock.ExpectCommit()

	if err := repository.RecordNotification(
		context.Background(), "", notification, now,
	); err != nil {
		t.Fatalf("RecordNotification() no-transaction error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryRecordsUnassignedLegacyTransactionNotification(t *testing.T) {
	database, mock, _ := sqlmock.New()
	t.Cleanup(func() { _ = database.Close() })
	repository := NewPostgresRepository(database)
	now := time.Date(2026, time.July, 14, 20, 0, 0, 0, time.UTC)
	verified := verifiedTransactionFixture()
	verified.AppAccountToken = ""
	notification := AppleNotification{
		ID: "33333333-3333-4333-8333-333333333333", Type: "DID_RENEW",
		Environment: verified.Environment, SignedAt: now.Add(-time.Minute),
		PayloadSHA256: strings.Repeat("a", 64), Transaction: &verified,
	}

	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO apple_store_notifications").
		WithArgs(
			notification.ID, notification.Type, notification.Subtype, notification.Environment,
			nil, verified.Storefront, verified.TransactionID, notification.SignedAt,
			notification.PayloadSHA256, now,
		).
		WillReturnRows(sqlmock.NewRows([]string{"notification_uuid"}).AddRow(notification.ID))
	mock.ExpectCommit()

	if err := repository.RecordNotification(context.Background(), "", notification, now); err != nil {
		t.Fatalf("RecordNotification() unassigned legacy error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func entitlementRows(transaction VerifiedTransaction, updatedAt time.Time) *sqlmock.Rows {
	return sqlmock.NewRows([]string{
		"product_id", "state", "expires_at", "revoked_at", "source_storefront",
		"source_transaction_id", "updated_at",
	}).AddRow(
		transaction.ProductID, transaction.Status, transaction.ExpiresAt, transaction.RevokedAt,
		transaction.Storefront, transaction.TransactionID, updatedAt,
	)
}

func expectPurchaseChainClaim(
	mock sqlmock.Sqlmock,
	verified VerifiedTransaction,
	ownerAccountID string,
) {
	mock.ExpectExec("pg_advisory_xact_lock").
		WithArgs(verified.Storefront + ":" + verified.OriginalTransactionID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO store_purchase_chains").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery("SELECT account_id::text").
		WithArgs(verified.Storefront, verified.OriginalTransactionID).
		WillReturnRows(sqlmock.NewRows([]string{"account_id"}).AddRow(ownerAccountID))
}
