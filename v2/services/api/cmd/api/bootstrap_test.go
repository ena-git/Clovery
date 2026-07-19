package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/clovery/clovery/services/api/internal/application/identityflow"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/config"
	"github.com/clovery/clovery/services/api/internal/database"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestBuildHandlerRegistersIdentityRoutesWithoutProviderCredentials(t *testing.T) {
	databaseHandle, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create mock database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	handler, err := buildHandler(databaseHandle, identityTestConfig())
	if err != nil {
		t.Fatalf("build API handler: %v", err)
	}

	federatedRequest := httptest.NewRequest(http.MethodPost, "/v1/auth/federated/apple/start", nil)
	federatedResponse := httptest.NewRecorder()
	handler.ServeHTTP(federatedResponse, federatedRequest)
	if federatedResponse.Code != http.StatusBadRequest ||
		!strings.Contains(federatedResponse.Body.String(), `"identity_provider_unsupported"`) {
		t.Fatalf("federated route status = %d, body = %s", federatedResponse.Code, federatedResponse.Body.String())
	}

	passkeyRequest := httptest.NewRequest(http.MethodGet, "/v1/auth/passkeys/login/start", nil)
	passkeyResponse := httptest.NewRecorder()
	handler.ServeHTTP(passkeyResponse, passkeyRequest)
	if passkeyResponse.Code != http.StatusMethodNotAllowed {
		t.Fatalf("passkey route status = %d, want %d", passkeyResponse.Code, http.StatusMethodNotAllowed)
	}
}

func TestBuildIdentityApplicationsPassesSharedClaimIssuerToFederatedFlow(t *testing.T) {
	databaseHandle, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create mock database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	applicationConfig := identityTestConfig()
	signer, err := auth.NewAccessTokenSigner(applicationConfig.JWTIssuer, []byte(applicationConfig.JWTSigningKey))
	if err != nil {
		t.Fatalf("create access token signer: %v", err)
	}
	sessions := auth.NewSessionService(databaseHandle, signer)
	claims := &bootstrapClaimIssuer{}
	var capturedClaims identityflow.IdentityClaimIssuer
	builder := func(
		federation *auth.FederationService,
		sessions *auth.SessionService,
		claims identityflow.IdentityClaimIssuer,
	) (*identityflow.FederatedFlow, error) {
		capturedClaims = claims
		return identityflow.NewFederatedFlow(federation, sessions, claims)
	}

	federation, passkeys, err := buildIdentityApplicationsWithFederatedFlowBuilder(
		databaseHandle,
		sessions,
		claims,
		applicationConfig,
		builder,
	)
	if err != nil {
		t.Fatalf("build identity applications: %v", err)
	}
	if federation == nil || passkeys == nil {
		t.Fatalf("identity applications = %#v, %#v", federation, passkeys)
	}
	if capturedClaims != claims {
		t.Fatal("federated flow builder did not receive the shared claim issuer")
	}
}

func TestBuildHandlerRegistersProtectedManagementRoutes(t *testing.T) {
	databaseHandle, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create mock database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	handler, err := buildHandler(databaseHandle, identityTestConfig())
	if err != nil {
		t.Fatalf("build API handler: %v", err)
	}

	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/v1/account", nil),
		httptest.NewRequest(http.MethodGet, "/v1/account/bootstrap", nil),
		httptest.NewRequest(http.MethodPost, "/v1/account/bootstrap/resume", nil),
		httptest.NewRequest(http.MethodGet, "/v1/account/devices", nil),
		httptest.NewRequest(http.MethodGet, "/v1/vault", nil),
		httptest.NewRequest(http.MethodPost, "/v1/account/deletion-requests", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/sync/push", nil),
		httptest.NewRequest(http.MethodGet, "/v1/vault/sync/pull", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/assets/uploads", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/assets/asset/complete", nil),
		httptest.NewRequest(http.MethodGet, "/v1/vault/assets/asset/download", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/migrations", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/migrations/id/entries", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/migrations/id/assets", nil),
		httptest.NewRequest(http.MethodPost, "/v1/vault/migrations/id/verify", nil),
		httptest.NewRequest(http.MethodGet, "/v1/vault/migrations/id/report", nil),
	} {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("%s status = %d, body = %s", request.URL.Path, response.Code, response.Body.String())
		}
	}
}

func identityTestConfig() config.Config {
	return config.Config{
		JWTIssuer:                      "clovery-test",
		JWTSigningKey:                  "0123456789abcdef0123456789abcdef",
		WebAuthnRPID:                   "accounts.clovery.example",
		WebAuthnRPDisplayName:          "Clovery",
		WebAuthnOrigins:                []string{"https://accounts.clovery.example"},
		PasskeyCredentialEncryptionKey: []byte("0123456789abcdef0123456789abcdef"),
		S3Endpoint:                     "http://localhost:9000",
		S3Bucket:                       "clovery-test",
		S3AccessKey:                    "test-access",
		S3SecretKey:                    "test-secret",
		S3AllowInsecure:                true,
		MigrationWritesEnabled:         true,
		MetricsBearerToken:             "0123456789abcdef0123456789abcdef",
	}
}

func TestBuildHandlerServesRegistrationWithoutFrontend(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for API bootstrap integration tests")
	}
	const schemaName = "clovery_w2_api_bootstrap_test"
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open bootstrap database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	_, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	if _, err := adminDatabase.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create bootstrap schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)) })

	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse bootstrap database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	migrationsPath := filepath.Join("..", "..", "migrations")
	if err := database.Apply(parsedURL.String(), migrationsPath, database.Up); err != nil {
		t.Fatalf("apply bootstrap migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", parsedURL.String())
	if err != nil {
		t.Fatalf("open migrated bootstrap database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })

	handler, err := buildHandler(databaseHandle, identityTestConfig())
	if err != nil {
		t.Fatalf("build API handler: %v", err)
	}
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/accounts",
		strings.NewReader(`{"login_id":"api_backend_user","password":"four quiet words together","recovery_method":"recovery_codes","device":{"device_id":"dddddddd-4444-4444-8444-444444444444","platform":"ios","display_name":"API Device"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusCreated || !strings.Contains(response.Body.String(), `"recovery_codes"`) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

type bootstrapClaimIssuer struct{}

func (*bootstrapClaimIssuer) Issue(
	context.Context,
	identityclaim.Identity,
) (identityclaim.IssuedClaim, error) {
	return identityclaim.IssuedClaim{}, nil
}
