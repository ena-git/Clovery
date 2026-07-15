package authflow

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestBackendAuthFlowWorksWithoutFrontend(t *testing.T) {
	databaseHandle := openAuthFlowDatabase(t)
	signer, err := auth.NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create signer: %v", err)
	}
	service, err := NewService(databaseHandle, signer)
	if err != nil {
		t.Fatalf("create auth flow service: %v", err)
	}
	ctx := context.Background()

	registered, err := service.Register(ctx, RegisterCommand{
		LoginID:        "backend_user",
		Password:       "four quiet words together",
		RecoveryMethod: "recovery_codes",
		Device: Device{
			ID:          "aaaaaaaa-1111-4111-8111-111111111111",
			Platform:    "ios",
			DisplayName: "API Test iPhone",
		},
	})
	if err != nil {
		t.Fatalf("register via backend flow: %v", err)
	}
	if registered.AccountID == "" || registered.VaultID == "" || len(registered.RecoveryCodes) != 8 {
		t.Fatalf("registration result = %#v", registered)
	}

	loggedIn, err := service.Login(ctx, LoginCommand{
		LoginID:  "backend_user",
		Password: "four quiet words together",
		Device: Device{
			ID:          "bbbbbbbb-2222-4222-8222-222222222222",
			Platform:    "ios",
			DisplayName: "Second API Device",
		},
	})
	if err != nil {
		t.Fatalf("login via backend flow: %v", err)
	}
	if loggedIn.AccountID != registered.AccountID || loggedIn.VaultID != registered.VaultID {
		t.Fatalf("login entered another root account: %#v", loggedIn)
	}
	replacementCodes, err := service.ReplaceRecoveryCodes(ctx, registered.AccountID, loggedIn.AccessToken)
	if err != nil {
		t.Fatalf("replace recovery codes after recent login: %v", err)
	}
	if len(replacementCodes) != 8 {
		t.Fatalf("replacement recovery code count = %d", len(replacementCodes))
	}

	proof, err := service.ConsumeRecoveryCode(ctx, "backend_user", replacementCodes[0])
	if err != nil {
		t.Fatalf("consume recovery code: %v", err)
	}
	if err := service.CompletePasswordReset(ctx, proof.ResetIntentID, proof.Proof, "five private words stay together"); err != nil {
		t.Fatalf("complete password reset: %v", err)
	}
	if _, err := service.Login(ctx, LoginCommand{
		LoginID:  "backend_user",
		Password: "five private words stay together",
		Device: Device{
			ID:          "cccccccc-3333-4333-8333-333333333333",
			Platform:    "ios",
			DisplayName: "Reset API Device",
		},
	}); err != nil {
		t.Fatalf("login with reset password: %v", err)
	}
}

func openAuthFlowDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for auth flow integration tests")
	}
	const schemaName = "clovery_w2_authflow_test"
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open auth flow database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	_, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	if _, err := adminDatabase.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create auth flow schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)) })

	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve auth flow test path")
	}
	migrationsPath := filepath.Join(filepath.Dir(currentFile), "..", "..", "..", "migrations")
	if err := database.Apply(parsedURL.String(), migrationsPath, database.Up); err != nil {
		t.Fatalf("apply auth flow migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", parsedURL.String())
	if err != nil {
		t.Fatalf("open migrated auth flow database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	return databaseHandle
}
