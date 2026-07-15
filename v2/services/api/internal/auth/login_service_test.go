package auth

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

func TestPasswordLoginUsesGenericErrorsAndPersistentRateLimits(t *testing.T) {
	databaseHandle := openAuthTestDatabase(t)
	service, err := NewLoginService(databaseHandle)
	if err != nil {
		t.Fatalf("create login service: %v", err)
	}
	ctx := context.Background()

	registration := Registration{
		AccountID: "55555555-5555-4555-8555-555555555555",
		VaultID:   "ffffffff-ffff-4fff-8fff-ffffffffffff",
		LoginID:   "Login_User",
		Password:  "four quiet words together",
	}
	if err := service.Register(ctx, registration); err != nil {
		t.Fatalf("register account: %v", err)
	}

	if _, err := service.Login(ctx, "login_user", "four wrong words together"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("wrong password error = %v", err)
	}
	if _, err := service.Login(ctx, "missing_user", "four wrong words together"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("missing account error = %v", err)
	}

	result, err := service.Login(ctx, " LOGIN_USER ", "four quiet words together")
	if err != nil {
		t.Fatalf("login with correct password: %v", err)
	}
	if result.AccountID != registration.AccountID || result.VaultID != registration.VaultID {
		t.Fatalf("login result = %#v", result)
	}

	for attempt := 1; attempt <= 4; attempt++ {
		if _, err := service.Login(ctx, "limited_user", "four wrong words together"); !errors.Is(err, ErrInvalidCredentials) {
			t.Fatalf("attempt %d error = %v", attempt, err)
		}
	}
	if _, err := service.Login(ctx, "limited_user", "four wrong words together"); !errors.Is(err, ErrRateLimited) {
		t.Fatalf("fifth failed attempt error = %v", err)
	}
	if _, err := service.Login(ctx, "limited_user", "four wrong words together"); !errors.Is(err, ErrRateLimited) {
		t.Fatalf("blocked login error = %v", err)
	}
}

func openAuthTestDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for auth integration tests")
	}

	const schemaName = "clovery_w2_auth_test"
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open auth test database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	if _, err := adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)); err != nil {
		t.Fatalf("reset auth test schema: %v", err)
	}
	if _, err := adminDatabase.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create auth test schema: %v", err)
	}
	t.Cleanup(func() {
		_, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	})

	schemaURL := authTestDatabaseURL(t, databaseURL, schemaName)
	if err := database.Apply(schemaURL, authMigrationsPath(t), database.Up); err != nil {
		t.Fatalf("apply auth migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open migrated auth schema: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	return databaseHandle
}

func authTestDatabaseURL(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse auth test database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	return parsedURL.String()
}

func authMigrationsPath(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve auth test path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
