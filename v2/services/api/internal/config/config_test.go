package config

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestLoadReturnsExplicitConfiguration(t *testing.T) {
	t.Setenv("DEPLOYMENT_ENVIRONMENT", "development")
	t.Setenv("DATABASE_URL", "postgres://clovery:secret@localhost:5432/clovery")
	t.Setenv("S3_ENDPOINT", "http://localhost:9000")
	t.Setenv("S3_BUCKET", "clovery-dev")
	t.Setenv("S3_ACCESS_KEY", "clovery-access")
	t.Setenv("S3_SECRET_KEY", "clovery-secret")
	t.Setenv("S3_ALLOW_INSECURE", "true")
	t.Setenv("MIGRATION_WRITES_ENABLED", "true")
	t.Setenv("METRICS_BEARER_TOKEN", "0123456789abcdef0123456789abcdef")
	t.Setenv("JWT_ISSUER", "https://accounts.clovery.example")
	t.Setenv("JWT_SIGNING_KEY", "0123456789abcdef0123456789abcdef")
	t.Setenv("WEBAUTHN_RP_ID", "accounts.clovery.example")
	t.Setenv("WEBAUTHN_RP_DISPLAY_NAME", "Clovery")
	t.Setenv("WEBAUTHN_RP_ORIGINS", "https://accounts.clovery.example,https://app.clovery.example")
	t.Setenv(
		"PASSKEY_CREDENTIAL_ENCRYPTION_KEY",
		base64.StdEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef")),
	)
	t.Setenv("PORT", "8080")

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() returned an unexpected error: %v", err)
	}

	if config.DatabaseURL != "postgres://clovery:secret@localhost:5432/clovery" {
		t.Fatalf("DatabaseURL = %q", config.DatabaseURL)
	}
	if config.DeploymentEnvironment != DeploymentDevelopment {
		t.Fatalf("DeploymentEnvironment = %q", config.DeploymentEnvironment)
	}
	if config.S3Endpoint != "http://localhost:9000" {
		t.Fatalf("S3Endpoint = %q", config.S3Endpoint)
	}
	if config.S3Bucket != "clovery-dev" {
		t.Fatalf("S3Bucket = %q", config.S3Bucket)
	}
	if config.S3AccessKey != "clovery-access" || config.S3SecretKey != "clovery-secret" {
		t.Fatal("S3 credentials were not loaded")
	}
	if !config.S3AllowInsecure {
		t.Fatal("S3AllowInsecure was not loaded")
	}
	if !config.MigrationWritesEnabled || len(config.MetricsBearerToken) < 32 {
		t.Fatal("operational controls were not loaded")
	}
	if config.JWTIssuer != "https://accounts.clovery.example" {
		t.Fatalf("JWTIssuer = %q", config.JWTIssuer)
	}
	if config.JWTSigningKey != "0123456789abcdef0123456789abcdef" {
		t.Fatalf("JWTSigningKey was not loaded")
	}
	if config.WebAuthnRPID != "accounts.clovery.example" {
		t.Fatalf("WebAuthnRPID = %q", config.WebAuthnRPID)
	}
	if len(config.WebAuthnOrigins) != 2 {
		t.Fatalf("WebAuthnOrigins = %#v", config.WebAuthnOrigins)
	}
	if len(config.PasskeyCredentialEncryptionKey) != 32 {
		t.Fatalf("PasskeyCredentialEncryptionKey length = %d", len(config.PasskeyCredentialEncryptionKey))
	}
	if config.Port != "8080" {
		t.Fatalf("Port = %q", config.Port)
	}
}

func TestLoadRejectsMissingRequiredConfiguration(t *testing.T) {
	requiredKeys := []string{
		"DEPLOYMENT_ENVIRONMENT",
		"DATABASE_URL",
		"S3_ENDPOINT",
		"S3_BUCKET",
		"S3_ACCESS_KEY",
		"S3_SECRET_KEY",
		"JWT_ISSUER",
		"JWT_SIGNING_KEY",
		"WEBAUTHN_RP_ID",
		"WEBAUTHN_RP_DISPLAY_NAME",
		"WEBAUTHN_RP_ORIGINS",
		"PASSKEY_CREDENTIAL_ENCRYPTION_KEY",
		"MIGRATION_WRITES_ENABLED",
		"METRICS_BEARER_TOKEN",
		"PORT",
	}

	for _, key := range requiredKeys {
		t.Run(key, func(t *testing.T) {
			setValidEnvironment(t)
			t.Setenv(key, "")

			_, err := Load()
			if err == nil {
				t.Fatalf("Load() accepted missing %s", key)
			}
			if !strings.Contains(err.Error(), key) {
				t.Fatalf("Load() error %q does not identify %s", err, key)
			}
		})
	}
}

func TestLoadRejectsShortJWTSigningKey(t *testing.T) {
	setValidEnvironment(t)
	t.Setenv("JWT_SIGNING_KEY", "too-short")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "JWT_SIGNING_KEY") {
		t.Fatalf("Load() short signing key error = %v", err)
	}
}

func TestLoadRejectsHTTPObjectStoreWithoutExplicitOverride(t *testing.T) {
	setValidEnvironment(t)
	t.Setenv("S3_ALLOW_INSECURE", "false")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "S3_ALLOW_INSECURE") {
		t.Fatalf("Load() insecure S3 error = %v", err)
	}
}

func TestLoadAllowsUnconfiguredOIDCProviders(t *testing.T) {
	setValidEnvironment(t)
	clearOIDCEnvironment(t)

	loaded, err := Load()
	if err != nil {
		t.Fatalf("Load() returned an unexpected error: %v", err)
	}
	if loaded.AppleOIDC.Enabled() || loaded.GoogleOIDC.Enabled() || loaded.HuaweiOIDC.Enabled() {
		t.Fatalf("unconfigured OIDC providers were enabled: %#v", loaded)
	}
}

func TestLoadRejectsPartiallyConfiguredOIDCProvider(t *testing.T) {
	setValidEnvironment(t)
	clearOIDCEnvironment(t)
	t.Setenv("APPLE_OIDC_CLIENT_ID", "com.clovery.app")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "APPLE_OIDC") {
		t.Fatalf("Load() partial Apple OIDC error = %v", err)
	}
}

func TestLoadReturnsConfiguredOIDCProvider(t *testing.T) {
	setValidEnvironment(t)
	clearOIDCEnvironment(t)
	t.Setenv("GOOGLE_OIDC_CLIENT_ID", "google-client-id")
	t.Setenv("GOOGLE_OIDC_CLIENT_SECRET", "google-client-secret")
	t.Setenv("GOOGLE_OIDC_REDIRECT_URL", "https://accounts.clovery.example/oauth/google/callback")

	loaded, err := Load()
	if err != nil {
		t.Fatalf("Load() returned an unexpected error: %v", err)
	}
	if !loaded.GoogleOIDC.Enabled() || loaded.GoogleOIDC.ClientID != "google-client-id" {
		t.Fatalf("GoogleOIDC = %#v", loaded.GoogleOIDC)
	}
}

func setValidEnvironment(t *testing.T) {
	t.Helper()
	t.Setenv("DEPLOYMENT_ENVIRONMENT", "development")
	t.Setenv("DATABASE_URL", "postgres://clovery:secret@localhost:5432/clovery")
	t.Setenv("S3_ENDPOINT", "http://localhost:9000")
	t.Setenv("S3_BUCKET", "clovery-dev")
	t.Setenv("S3_ACCESS_KEY", "clovery-access")
	t.Setenv("S3_SECRET_KEY", "clovery-secret")
	t.Setenv("S3_ALLOW_INSECURE", "true")
	t.Setenv("MIGRATION_WRITES_ENABLED", "true")
	t.Setenv("METRICS_BEARER_TOKEN", "0123456789abcdef0123456789abcdef")
	t.Setenv("JWT_ISSUER", "https://accounts.clovery.example")
	t.Setenv("JWT_SIGNING_KEY", "0123456789abcdef0123456789abcdef")
	t.Setenv("WEBAUTHN_RP_ID", "accounts.clovery.example")
	t.Setenv("WEBAUTHN_RP_DISPLAY_NAME", "Clovery")
	t.Setenv("WEBAUTHN_RP_ORIGINS", "https://accounts.clovery.example,https://app.clovery.example")
	t.Setenv(
		"PASSKEY_CREDENTIAL_ENCRYPTION_KEY",
		base64.StdEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef")),
	)
	t.Setenv("PORT", "8080")
}

func TestLoadRejectsUnknownDeploymentEnvironment(t *testing.T) {
	setValidEnvironment(t)
	t.Setenv("DEPLOYMENT_ENVIRONMENT", "release")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "DEPLOYMENT_ENVIRONMENT") {
		t.Fatalf("Load() deployment environment error = %v", err)
	}
}

func clearOIDCEnvironment(t *testing.T) {
	t.Helper()
	for _, provider := range []string{"APPLE", "GOOGLE", "HUAWEI"} {
		t.Setenv(provider+"_OIDC_CLIENT_ID", "")
		t.Setenv(provider+"_OIDC_CLIENT_SECRET", "")
		t.Setenv(provider+"_OIDC_REDIRECT_URL", "")
	}
}
