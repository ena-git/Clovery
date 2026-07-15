package billing

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	cloverydatabase "github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresPurchaseChainCannotSplitAcrossAccounts(t *testing.T) {
	databaseHandle := openBillingIntegrationDatabase(t)
	seedBillingAccounts(t, databaseHandle)
	repository := NewPostgresRepository(databaseHandle)
	now := time.Now().UTC()
	first := verifiedTransactionFixture()
	first.AppAccountToken = billingAccountID
	if _, err := repository.Record(context.Background(), billingAccountID, first, now); err != nil {
		t.Fatalf("Record() first purchase error = %v", err)
	}
	second := first
	second.TransactionID = "renewal-tx-2"
	second.AppAccountToken = otherAccountID
	second.PurchaseAt = first.PurchaseAt.Add(30 * 24 * time.Hour)
	second.Metadata.SignedAt = first.Metadata.SignedAt.Add(30 * 24 * time.Hour)

	if _, err := repository.Record(context.Background(), otherAccountID, second, now); !errors.Is(err, ErrTransactionClaimed) {
		t.Fatalf("Record() split purchase chain error = %v", err)
	}
	var owner string
	if err := databaseHandle.QueryRow(`SELECT account_id::text FROM store_purchase_chains
		WHERE storefront = $1 AND original_transaction_id = $2`,
		first.Storefront, first.OriginalTransactionID,
	).Scan(&owner); err != nil || owner != billingAccountID {
		t.Fatalf("purchase chain owner = %q, error = %v", owner, err)
	}
}

func TestPostgresOlderNotificationStateCannotOverrideNewerState(t *testing.T) {
	databaseHandle := openBillingIntegrationDatabase(t)
	seedBillingAccounts(t, databaseHandle)
	repository := NewPostgresRepository(databaseHandle)
	now := time.Now().UTC()
	newer := verifiedTransactionFixture()
	newer.AppAccountToken = billingAccountID
	newer.Metadata.SignedAt = now
	revokedAt := now.Add(-time.Minute)
	newer.RevokedAt = &revokedAt
	newer.Status = StateRevoked
	if _, err := repository.Record(context.Background(), billingAccountID, newer, now); err != nil {
		t.Fatalf("Record() newer state error = %v", err)
	}
	older := newer
	older.Metadata.SignedAt = now.Add(-time.Hour)
	older.RevokedAt = nil
	older.Status = StateActive
	entitlement, err := repository.Record(context.Background(), billingAccountID, older, now.Add(time.Minute))
	if err != nil {
		t.Fatalf("Record() older state error = %v", err)
	}
	if entitlement.State != StateRevoked || entitlement.RevokedAt == nil {
		t.Fatalf("entitlement after stale replay = %#v", entitlement)
	}
}

func TestPostgresPersistsLegacyNotificationBeforeAccountClaim(t *testing.T) {
	databaseHandle := openBillingIntegrationDatabase(t)
	repository := NewPostgresRepository(databaseHandle)
	now := time.Now().UTC()
	verified := verifiedTransactionFixture()
	verified.AppAccountToken = ""
	notification := AppleNotification{
		ID: "33333333-3333-4333-8333-333333333333", Type: "DID_RENEW",
		Environment: verified.Environment, SignedAt: now.Add(-time.Minute),
		PayloadSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		Transaction:   &verified,
	}
	if err := repository.RecordNotification(context.Background(), "", notification, now); err != nil {
		t.Fatalf("RecordNotification() legacy notification error = %v", err)
	}
	var accountID sql.NullString
	var storefront, transactionID string
	if err := databaseHandle.QueryRow(`SELECT account_id::text, storefront, transaction_id
		FROM apple_store_notifications WHERE notification_uuid = $1`, notification.ID,
	).Scan(&accountID, &storefront, &transactionID); err != nil {
		t.Fatalf("load legacy notification: %v", err)
	}
	if accountID.Valid || storefront != verified.Storefront || transactionID != verified.TransactionID {
		t.Fatalf(
			"legacy notification account=%#v storefront=%q transaction=%q",
			accountID, storefront, transactionID,
		)
	}
}

func TestPostgresTransactionRefreshDoesNotEndActiveGracePeriod(t *testing.T) {
	databaseHandle := openBillingIntegrationDatabase(t)
	seedBillingAccounts(t, databaseHandle)
	repository := NewPostgresRepository(databaseHandle)
	now := time.Now().UTC().Truncate(time.Microsecond)
	grace := verifiedTransactionFixture()
	grace.AppAccountToken = billingAccountID
	grace.Status = StateActive
	grace.Metadata.Source = "app_store_server_notification_v2"
	grace.Metadata.SignedAt = now.Add(-time.Minute)
	graceExpiresAt := now.Add(24 * time.Hour)
	grace.ExpiresAt = &graceExpiresAt
	if _, err := repository.Record(context.Background(), billingAccountID, grace, now); err != nil {
		t.Fatalf("Record() grace state error = %v", err)
	}

	refresh := grace
	refresh.Status = StateExpired
	refresh.Metadata.Source = "app_store_server_api"
	refresh.Metadata.SignedAt = now
	expiredAt := now.Add(-time.Hour)
	refresh.ExpiresAt = &expiredAt
	entitlement, err := repository.Record(context.Background(), billingAccountID, refresh, now)
	if err != nil {
		t.Fatalf("Record() refresh state error = %v", err)
	}
	if entitlement.State != StateActive || entitlement.ExpiresAt == nil ||
		!entitlement.ExpiresAt.Equal(graceExpiresAt) {
		t.Fatalf("entitlement after refresh = %#v", entitlement)
	}
}

func openBillingIntegrationDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for billing integration tests")
	}
	const schemaName = "clovery_billing_integration_test"
	admin, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open billing integration database: %v", err)
	}
	t.Cleanup(func() { _ = admin.Close() })
	_, _ = admin.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	if _, err := admin.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create billing integration schema: %v", err)
	}
	t.Cleanup(func() { _, _ = admin.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)) })

	schemaURL := billingIntegrationDatabaseURL(t, databaseURL, schemaName)
	if err := cloverydatabase.Apply(schemaURL, billingMigrationsPath(t), cloverydatabase.Up); err != nil {
		t.Fatalf("apply billing integration migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open migrated billing database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	return databaseHandle
}

func seedBillingAccounts(t *testing.T, databaseHandle *sql.DB) {
	t.Helper()
	if _, err := databaseHandle.Exec(
		"INSERT INTO clovery_accounts (id) VALUES ($1), ($2)", billingAccountID, otherAccountID,
	); err != nil {
		t.Fatalf("seed billing accounts: %v", err)
	}
}

func billingIntegrationDatabaseURL(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse billing integration database URL: %v", err)
	}
	query := parsed.Query()
	query.Set("search_path", schemaName)
	parsed.RawQuery = query.Encode()
	return parsed.String()
}

func billingMigrationsPath(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve billing integration test path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
