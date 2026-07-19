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
	"sync/atomic"
	"testing"
	"time"

	cloverydatabase "github.com/clovery/clovery/services/api/internal/database"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestCreateClaimedAccountCommitsEveryRequiredRow(t *testing.T) {
	databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
	rawToken := issueClaimedCreateToken(t, databaseHandle, claims, "apple", "success-subject")
	passwordHash := claimedCreatePasswordHash(t)

	result, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID:             "10000000-0000-4000-8000-000000000001",
		VaultID:               "10000000-0000-4000-8000-000000000002",
		LoginID:               "claimed_user",
		PasswordHash:          passwordHash,
		IdentityClaimToken:    rawToken,
		RegistrationRequestID: "10000000-0000-4000-8000-000000000003",
		SourceKind:            "new_install",
	}, claimRepository, claims)
	if err != nil {
		t.Fatalf("CreateClaimedAccount() error = %v", err)
	}
	if result.AccountID != "10000000-0000-4000-8000-000000000001" ||
		result.VaultID != "10000000-0000-4000-8000-000000000002" {
		t.Fatalf("CreateClaimedAccount() result = %#v", result)
	}

	assertClaimedCreateCounts(t, databaseHandle, map[string]int{
		"clovery_accounts":       1,
		"vaults":                 1,
		"account_login_ids":      1,
		"password_credentials":   1,
		"external_identities":    1,
		"account_bootstrap_jobs": 1,
	})
	var consumedClaims int
	if err := databaseHandle.QueryRow("SELECT COUNT(*) FROM identity_claims WHERE consumed_at IS NOT NULL").Scan(&consumedClaims); err != nil {
		t.Fatalf("count consumed claims: %v", err)
	}
	if consumedClaims != 1 {
		t.Fatalf("consumed claim count = %d", consumedClaims)
	}
	var identityState string
	var migrationState string
	var entitlementState string
	var vaultState string
	if err := databaseHandle.QueryRow(`
		SELECT identity_state, migration_state, entitlement_state, vault_state
		FROM account_bootstrap_jobs
	`).Scan(&identityState, &migrationState, &entitlementState, &vaultState); err != nil {
		t.Fatalf("load bootstrap states: %v", err)
	}
	if identityState != "complete" || migrationState != "complete" ||
		entitlementState != "pending" || vaultState != "pending" {
		t.Fatalf("bootstrap states = %q %q %q %q", identityState, migrationState, entitlementState, vaultState)
	}
}

func TestCreateClaimedAccountRollsBackEveryRowAndClaimConsumption(t *testing.T) {
	databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
	rawToken := issueClaimedCreateToken(t, databaseHandle, claims, "google", "rollback-subject")
	if _, err := databaseHandle.Exec(`
		CREATE FUNCTION fail_claimed_bootstrap() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN
			RAISE EXCEPTION 'injected bootstrap failure';
		END
		$$;
		CREATE TRIGGER fail_claimed_bootstrap
		BEFORE INSERT ON account_bootstrap_jobs
		FOR EACH ROW EXECUTE FUNCTION fail_claimed_bootstrap();
	`); err != nil {
		t.Fatalf("install bootstrap failure trigger: %v", err)
	}

	_, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID:             "20000000-0000-4000-8000-000000000001",
		VaultID:               "20000000-0000-4000-8000-000000000002",
		LoginID:               "rollback_user",
		PasswordHash:          claimedCreatePasswordHash(t),
		IdentityClaimToken:    rawToken,
		RegistrationRequestID: "20000000-0000-4000-8000-000000000003",
		SourceKind:            "legacy_local",
	}, claimRepository, claims)
	if err == nil {
		t.Fatal("CreateClaimedAccount() error = nil")
	}

	assertClaimedCreateCounts(t, databaseHandle, map[string]int{
		"clovery_accounts":       0,
		"vaults":                 0,
		"account_login_ids":      0,
		"password_credentials":   0,
		"external_identities":    0,
		"account_bootstrap_jobs": 0,
	})
	var unconsumedClaims int
	if err := databaseHandle.QueryRow("SELECT COUNT(*) FROM identity_claims WHERE consumed_at IS NULL").Scan(&unconsumedClaims); err != nil {
		t.Fatalf("count unconsumed claims: %v", err)
	}
	if unconsumedClaims != 1 {
		t.Fatalf("unconsumed claim count = %d", unconsumedClaims)
	}
}

func TestCreateClaimedAccountReplaysSameRegistrationRequest(t *testing.T) {
	databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
	rawToken := issueClaimedCreateToken(t, databaseHandle, claims, "huawei", "replay-subject")
	requestID := "30000000-0000-4000-8000-000000000003"
	first, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID:             "30000000-0000-4000-8000-000000000001",
		VaultID:               "30000000-0000-4000-8000-000000000002",
		LoginID:               "replay_user",
		PasswordHash:          claimedCreatePasswordHash(t),
		IdentityClaimToken:    rawToken,
		RegistrationRequestID: requestID,
		SourceKind:            "new_install",
	}, claimRepository, claims)
	if err != nil {
		t.Fatalf("first CreateClaimedAccount() error = %v", err)
	}
	second, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID:             "30000000-0000-4000-8000-000000000004",
		VaultID:               "30000000-0000-4000-8000-000000000005",
		LoginID:               "ignored_replay_user",
		PasswordHash:          claimedCreatePasswordHash(t),
		IdentityClaimToken:    rawToken,
		RegistrationRequestID: requestID,
		SourceKind:            "legacy_cloudkit",
	}, claimRepository, claims)
	if err != nil {
		t.Fatalf("replayed CreateClaimedAccount() error = %v", err)
	}
	if second != first {
		t.Fatalf("replayed result = %#v, want %#v", second, first)
	}
	assertClaimedCreateCounts(t, databaseHandle, map[string]int{"clovery_accounts": 1, "vaults": 1})
}

func TestCreateClaimedAccountRejectsConsumedClaimForDifferentRequest(t *testing.T) {
	databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
	rawToken := issueClaimedCreateToken(t, databaseHandle, claims, "apple", "consumed-subject")
	params := CreateClaimedAccountParams{
		AccountID:             "40000000-0000-4000-8000-000000000001",
		VaultID:               "40000000-0000-4000-8000-000000000002",
		LoginID:               "consumed_user",
		PasswordHash:          claimedCreatePasswordHash(t),
		IdentityClaimToken:    rawToken,
		RegistrationRequestID: "40000000-0000-4000-8000-000000000003",
		SourceKind:            "new_install",
	}
	if _, err := repository.CreateClaimedAccount(context.Background(), params, claimRepository, claims); err != nil {
		t.Fatalf("first CreateClaimedAccount() error = %v", err)
	}
	params.RegistrationRequestID = "40000000-0000-4000-8000-000000000004"
	_, err := repository.CreateClaimedAccount(context.Background(), params, claimRepository, claims)
	if !errors.Is(err, identityclaim.ErrConsumedClaim) {
		t.Fatalf("second CreateClaimedAccount() error = %v, want ErrConsumedClaim", err)
	}
}

func TestCreateClaimedAccountRejectsAlreadyBoundExternalIdentity(t *testing.T) {
	databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
	firstToken := issueClaimedCreateToken(t, databaseHandle, claims, "google", "duplicate-identity-subject")
	if _, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID: "50000000-0000-4000-8000-000000000001", VaultID: "50000000-0000-4000-8000-000000000002",
		LoginID: "identity_first", PasswordHash: claimedCreatePasswordHash(t), IdentityClaimToken: firstToken,
		RegistrationRequestID: "50000000-0000-4000-8000-000000000003", SourceKind: "new_install",
	}, claimRepository, claims); err != nil {
		t.Fatalf("first CreateClaimedAccount() error = %v", err)
	}
	secondToken := issueClaimedCreateToken(t, databaseHandle, claims, "google", "duplicate-identity-subject")
	_, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID: "50000000-0000-4000-8000-000000000004", VaultID: "50000000-0000-4000-8000-000000000005",
		LoginID: "identity_second", PasswordHash: claimedCreatePasswordHash(t), IdentityClaimToken: secondToken,
		RegistrationRequestID: "50000000-0000-4000-8000-000000000006", SourceKind: "new_install",
	}, claimRepository, claims)
	if !errors.Is(err, ErrIdentityAlreadyBound) {
		t.Fatalf("second CreateClaimedAccount() error = %v, want ErrIdentityAlreadyBound", err)
	}
	assertClaimedCreateCounts(t, databaseHandle, map[string]int{"clovery_accounts": 1, "external_identities": 1})
}

func TestCreateClaimedAccountPreservesLoginIDUnavailableError(t *testing.T) {
	databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
	if err := repository.CreateAccount(context.Background(), CreateAccountParams{
		AccountID: "60000000-0000-4000-8000-000000000001", VaultID: "60000000-0000-4000-8000-000000000002",
		LoginID: "taken_claim_id", PasswordHash: claimedCreatePasswordHash(t),
	}); err != nil {
		t.Fatalf("seed duplicate login ID: %v", err)
	}
	rawToken := issueClaimedCreateToken(t, databaseHandle, claims, "apple", "duplicate-login-subject")
	_, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
		AccountID: "60000000-0000-4000-8000-000000000003", VaultID: "60000000-0000-4000-8000-000000000004",
		LoginID: "TAKEN_CLAIM_ID", PasswordHash: claimedCreatePasswordHash(t), IdentityClaimToken: rawToken,
		RegistrationRequestID: "60000000-0000-4000-8000-000000000005", SourceKind: "new_install",
	}, claimRepository, claims)
	if !errors.Is(err, ErrLoginIDUnavailable) {
		t.Fatalf("CreateClaimedAccount() error = %v, want ErrLoginIDUnavailable", err)
	}
	assertClaimedCreateCounts(t, databaseHandle, map[string]int{"clovery_accounts": 1, "account_login_ids": 1})
}

func TestCreateClaimedAccountLeavesLegacyMigrationPending(t *testing.T) {
	for _, sourceKind := range []string{"legacy_local", "legacy_cloudkit"} {
		t.Run(sourceKind, func(t *testing.T) {
			databaseHandle, repository, claimRepository, claims := openClaimedCreateDatabase(t)
			rawToken := issueClaimedCreateToken(t, databaseHandle, claims, "apple", sourceKind+"-subject")
			_, err := repository.CreateClaimedAccount(context.Background(), CreateClaimedAccountParams{
				AccountID: uuid.NewString(), VaultID: uuid.NewString(), LoginID: "legacy_" + sourceKind,
				PasswordHash: claimedCreatePasswordHash(t), IdentityClaimToken: rawToken,
				RegistrationRequestID: uuid.NewString(), SourceKind: sourceKind,
			}, claimRepository, claims)
			if err != nil {
				t.Fatalf("CreateClaimedAccount() error = %v", err)
			}
			var migrationState string
			if err := databaseHandle.QueryRow("SELECT migration_state FROM account_bootstrap_jobs").Scan(&migrationState); err != nil {
				t.Fatalf("load migration state: %v", err)
			}
			if migrationState != "pending" {
				t.Fatalf("migration state = %q", migrationState)
			}
		})
	}
}

var claimedCreateSchemaSequence atomic.Uint64

func openClaimedCreateDatabase(t *testing.T) (*sql.DB, *Repository, *identityclaim.PostgresRepository, *identityclaim.Service) {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is required for claimed account PostgreSQL tests")
	}
	schemaName := fmt.Sprintf("clovery_w7_account_%d_%d", os.Getpid(), claimedCreateSchemaSequence.Add(1))
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open claimed account admin database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	if _, err := adminDatabase.Exec("CREATE SCHEMA " + schemaName); err != nil {
		t.Fatalf("create claimed account schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec("DROP SCHEMA IF EXISTS " + schemaName + " CASCADE") })

	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse claimed account database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve claimed account test path")
	}
	migrationsPath := filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
	if err := cloverydatabase.Apply(parsedURL.String(), migrationsPath, cloverydatabase.Up); err != nil {
		t.Fatalf("apply claimed account migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", parsedURL.String())
	if err != nil {
		t.Fatalf("open claimed account database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	claimRepository := identityclaim.NewPostgresRepository(databaseHandle)
	return databaseHandle, NewRepository(databaseHandle), claimRepository, identityclaim.NewService(claimRepository)
}

func issueClaimedCreateToken(
	t *testing.T,
	databaseHandle *sql.DB,
	claims *identityclaim.Service,
	provider string,
	subject string,
) string {
	t.Helper()
	intentID := uuid.NewString()
	now := time.Now().UTC()
	if _, err := databaseHandle.Exec(`
		INSERT INTO federation_intents (id, purpose, provider, nonce_hash, created_at, expires_at, used_at)
		VALUES ($1, 'login', $2, decode(repeat('00', 32), 'hex'), $3, $4, $3)
	`, intentID, provider, now.Add(-time.Minute), now.Add(time.Hour)); err != nil {
		t.Fatalf("seed federation intent: %v", err)
	}
	issuer := map[string]string{
		"apple":  "https://appleid.apple.com",
		"google": "https://accounts.google.com",
		"huawei": "https://oauth-login.cloud.huawei.com",
	}[provider]
	issued, err := claims.Issue(context.Background(), identityclaim.Identity{
		Provider: provider, Issuer: issuer, Subject: subject, IntentID: intentID,
	})
	if err != nil {
		t.Fatalf("issue identity claim: %v", err)
	}
	rawToken, ok := issued.TakeToken()
	if !ok {
		t.Fatal("identity claim did not reveal its token")
	}
	return rawToken
}

func claimedCreatePasswordHash(t *testing.T) string {
	t.Helper()
	return "$argon2id$claimed-create-test"
}

func assertClaimedCreateCounts(t *testing.T, databaseHandle *sql.DB, expected map[string]int) {
	t.Helper()
	for table, want := range expected {
		var count int
		if err := databaseHandle.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&count); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		if count != want {
			t.Errorf("%s count = %d, want %d", table, count, want)
		}
	}
}
