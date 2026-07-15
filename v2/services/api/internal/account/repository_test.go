package account

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

	"github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestNormalizeLoginIDEnforcesCloveryRules(t *testing.T) {
	normalized, err := NormalizeLoginID("  Clover_2026  ")
	if err != nil {
		t.Fatalf("NormalizeLoginID() error = %v", err)
	}
	if normalized != "clover_2026" {
		t.Fatalf("normalized ID = %q", normalized)
	}

	for _, candidate := range []string{"abc", "1clover", "clover-name", "admin"} {
		t.Run(candidate, func(t *testing.T) {
			if _, err := NormalizeLoginID(candidate); !errors.Is(err, ErrInvalidLoginID) {
				t.Fatalf("NormalizeLoginID(%q) error = %v", candidate, err)
			}
		})
	}
}

func TestAccountConstraintsProtectLoginIdentityAndVaultOwnership(t *testing.T) {
	databaseHandle := openAccountTestDatabase(t)
	repository := NewRepository(databaseHandle)
	ctx := context.Background()

	first := CreateAccountParams{
		AccountID: "11111111-1111-4111-8111-111111111111",
		VaultID:   "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		LoginID:   "First_User",
	}
	if err := repository.CreateAccount(ctx, first); err != nil {
		t.Fatalf("create first account: %v", err)
	}

	duplicate := CreateAccountParams{
		AccountID: "22222222-2222-4222-8222-222222222222",
		VaultID:   "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
		LoginID:   "first_user",
	}
	if err := repository.CreateAccount(ctx, duplicate); !errors.Is(err, ErrLoginIDUnavailable) {
		t.Fatalf("duplicate normalized ID error = %v", err)
	}

	second := CreateAccountParams{
		AccountID: "33333333-3333-4333-8333-333333333333",
		VaultID:   "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
		LoginID:   "second_user",
	}
	if err := repository.CreateAccount(ctx, second); err != nil {
		t.Fatalf("create second account: %v", err)
	}

	if _, err := databaseHandle.ExecContext(
		ctx,
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')",
		"dddddddd-dddd-4ddd-8ddd-dddddddddddd",
		first.AccountID,
	); err == nil {
		t.Fatal("database allowed a second vault for one account")
	}

	identity := ExternalIdentity{
		Provider: "apple",
		Issuer:   "https://appleid.apple.com",
		Subject:  "apple-stable-subject",
	}
	if err := repository.BindExternalIdentity(ctx, first.AccountID, identity); err != nil {
		t.Fatalf("bind identity to first account: %v", err)
	}
	if err := repository.BindExternalIdentity(ctx, second.AccountID, identity); !errors.Is(err, ErrIdentityAlreadyBound) {
		t.Fatalf("duplicate provider identity error = %v", err)
	}

	if err := repository.RenameLoginID(ctx, first.AccountID, "garden_user"); err != nil {
		t.Fatalf("rename login ID: %v", err)
	}
	retiredIDReuse := CreateAccountParams{
		AccountID: "44444444-4444-4444-8444-444444444444",
		VaultID:   "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
		LoginID:   "first_user",
	}
	if err := repository.CreateAccount(ctx, retiredIDReuse); !errors.Is(err, ErrLoginIDUnavailable) {
		t.Fatalf("retired login ID reuse error = %v", err)
	}
}

func openAccountTestDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for account integration tests")
	}

	const schemaName = "clovery_w2_account_test"
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open account test database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })

	if _, err := adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)); err != nil {
		t.Fatalf("reset account test schema: %v", err)
	}
	if _, err := adminDatabase.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create account test schema: %v", err)
	}
	t.Cleanup(func() {
		_, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	})

	schemaURL := accountTestDatabaseURL(t, databaseURL, schemaName)
	if err := database.Apply(schemaURL, accountMigrationsPath(t), database.Up); err != nil {
		t.Fatalf("apply account migrations: %v", err)
	}

	databaseHandle, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open migrated account schema: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	return databaseHandle
}

func accountTestDatabaseURL(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse account test database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	return parsedURL.String()
}

func accountMigrationsPath(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve account test path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
