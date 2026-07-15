package database

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBillingEntitlementsMigrationDefinesAtomicLedger(t *testing.T) {
	migrations := migrationDirectory(t)
	up := readMigration(t, filepath.Join(migrations, "000014_billing_entitlements.up.sql"))
	down := readMigration(t, filepath.Join(migrations, "000014_billing_entitlements.down.sql"))

	for _, fragment := range []string{
		"CREATE TABLE store_purchase_chains",
		"PRIMARY KEY (storefront, original_transaction_id)",
		"CREATE TABLE store_transactions",
		"account_id UUID NOT NULL REFERENCES clovery_accounts(id)",
		"original_transaction_id TEXT NOT NULL",
		"app_account_token UUID NOT NULL",
		"verification_metadata JSONB NOT NULL",
		"PRIMARY KEY (storefront, transaction_id)",
		"REFERENCES store_purchase_chains(account_id, storefront, original_transaction_id)",
		"CREATE TABLE entitlements",
		"PRIMARY KEY (account_id, product_id)",
		"source_transaction_id TEXT NOT NULL",
		"FOREIGN KEY (account_id, source_storefront, source_transaction_id)",
		"CREATE TABLE apple_store_notifications",
		"notification_uuid UUID PRIMARY KEY",
		"payload_sha256 CHAR(64) NOT NULL",
	} {
		if !strings.Contains(up, fragment) {
			t.Fatalf("up migration is missing %q", fragment)
		}
	}
	if !strings.Contains(down, "DROP TABLE entitlements") ||
		!strings.Contains(down, "DROP TABLE apple_store_notifications") ||
		!strings.Contains(down, "DROP TABLE store_transactions") ||
		!strings.Contains(down, "DROP TABLE store_purchase_chains") {
		t.Fatalf("down migration does not reverse billing tables:\n%s", down)
	}
}

func readMigration(t *testing.T, path string) string {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read migration %s: %v", path, err)
	}
	return string(contents)
}
