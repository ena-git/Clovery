package authflow

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/database"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
	"github.com/google/uuid"
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

func TestClaimRegistrationRetriesSessionIssuanceWithoutDuplicateAccounts(t *testing.T) {
	databaseHandle := openAuthFlowDatabase(t)
	signer, err := auth.NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create signer: %v", err)
	}
	claimRepository := identityclaim.NewPostgresRepository(databaseHandle)
	claims := identityclaim.NewService(claimRepository)
	service, err := NewServiceWithIdentityClaims(
		databaseHandle,
		auth.NewSessionService(databaseHandle, signer),
		claimRepository,
		claims,
	)
	if err != nil {
		t.Fatalf("create auth flow service: %v", err)
	}
	rawToken := issueAuthFlowClaim(t, databaseHandle, claims)
	if _, err := databaseHandle.Exec(`
		CREATE FUNCTION fail_claim_session() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN
			RAISE EXCEPTION 'injected session failure';
		END
		$$;
		CREATE TRIGGER fail_claim_session BEFORE INSERT ON sessions
		FOR EACH ROW EXECUTE FUNCTION fail_claim_session();
	`); err != nil {
		t.Fatalf("install session failure trigger: %v", err)
	}
	claimToken := rawToken
	requestID := strings.ToUpper("71000000-0000-4000-8000-000000000001")
	sourceKind := "new_install"
	command := RegisterCommand{
		LoginID: "session_retry_user", Password: "four quiet words together", RecoveryMethod: "bound_identity",
		IdentityClaimToken: &claimToken, RegistrationRequestID: &requestID, SourceKind: &sourceKind,
		Device: Device{ID: "71000000-0000-4000-8000-000000000002", Platform: "ios", DisplayName: "Retry iPhone"},
	}

	if _, err := service.Register(context.Background(), command); err == nil {
		t.Fatal("first Register() error = nil")
	}
	var committedAccountID string
	var committedVaultID string
	if err := databaseHandle.QueryRow(`
		SELECT account.id::text, vault.id::text
		FROM clovery_accounts AS account
		JOIN vaults AS vault ON vault.owner_account_id = account.id
	`).Scan(&committedAccountID, &committedVaultID); err != nil {
		t.Fatalf("load committed claimed account after session failure: %v", err)
	}
	if _, err := databaseHandle.Exec("DROP TRIGGER fail_claim_session ON sessions"); err != nil {
		t.Fatalf("drop session failure trigger: %v", err)
	}
	registered, err := service.Register(context.Background(), command)
	if err != nil {
		t.Fatalf("retried Register() error = %v", err)
	}
	if registered.AccountID == "" || registered.VaultID == "" || len(registered.RecoveryCodes) != 0 {
		t.Fatalf("retried registration result = %#v", registered)
	}
	if registered.AccountID != committedAccountID || registered.VaultID != committedVaultID {
		t.Fatalf("retried registration roots = %q/%q, want %q/%q", registered.AccountID, registered.VaultID, committedAccountID, committedVaultID)
	}
	for table, want := range map[string]int{
		"clovery_accounts": 1, "vaults": 1, "external_identities": 1,
		"account_bootstrap_jobs": 1, "devices": 1, "sessions": 1, "recovery_codes": 0,
	} {
		var count int
		if err := databaseHandle.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&count); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		if count != want {
			t.Errorf("%s count = %d, want %d", table, count, want)
		}
	}
}

func openAuthFlowDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is required for auth flow integration tests")
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

func issueAuthFlowClaim(t *testing.T, databaseHandle *sql.DB, claims *identityclaim.Service) string {
	t.Helper()
	intentID := uuid.NewString()
	now := time.Now().UTC()
	if _, err := databaseHandle.Exec(`
		INSERT INTO federation_intents (id, purpose, provider, nonce_hash, created_at, expires_at, used_at)
		VALUES ($1, 'login', 'apple', decode(repeat('00', 32), 'hex'), $2, $3, $2)
	`, intentID, now.Add(-time.Minute), now.Add(time.Hour)); err != nil {
		t.Fatalf("seed auth flow claim intent: %v", err)
	}
	issued, err := claims.Issue(context.Background(), identityclaim.Identity{
		Provider: "apple", Issuer: "https://appleid.apple.com", Subject: "session-retry-subject", IntentID: intentID,
	})
	if err != nil {
		t.Fatalf("issue auth flow claim: %v", err)
	}
	rawToken, ok := issued.TakeToken()
	if !ok {
		t.Fatal("auth flow claim did not reveal token")
	}
	return rawToken
}
