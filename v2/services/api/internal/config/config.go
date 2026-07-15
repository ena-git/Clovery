package config

import (
	"encoding/base64"
	"fmt"
	"os"
	"strings"
)

type Config struct {
	DeploymentEnvironment          DeploymentEnvironment
	DatabaseURL                    string
	S3Endpoint                     string
	S3Bucket                       string
	S3AccessKey                    string
	S3SecretKey                    string
	S3AllowInsecure                bool
	JWTIssuer                      string
	JWTSigningKey                  string
	WebAuthnRPID                   string
	WebAuthnRPDisplayName          string
	WebAuthnOrigins                []string
	PasskeyCredentialEncryptionKey []byte
	AppleOIDC                      OIDCProviderConfig
	GoogleOIDC                     OIDCProviderConfig
	HuaweiOIDC                     OIDCProviderConfig
	AppleIAP                       AppleBillingConfig
	MigrationWritesEnabled         bool
	MetricsBearerToken             string
	Port                           string
}

func Load() (Config, error) {
	config := Config{
		DeploymentEnvironment: DeploymentEnvironment(os.Getenv("DEPLOYMENT_ENVIRONMENT")),
		DatabaseURL:           os.Getenv("DATABASE_URL"),
		S3Endpoint:            os.Getenv("S3_ENDPOINT"),
		S3Bucket:              os.Getenv("S3_BUCKET"),
		S3AccessKey:           os.Getenv("S3_ACCESS_KEY"),
		S3SecretKey:           os.Getenv("S3_SECRET_KEY"),
		JWTIssuer:             os.Getenv("JWT_ISSUER"),
		JWTSigningKey:         os.Getenv("JWT_SIGNING_KEY"),
		WebAuthnRPID:          os.Getenv("WEBAUTHN_RP_ID"),
		WebAuthnRPDisplayName: os.Getenv("WEBAUTHN_RP_DISPLAY_NAME"),
		WebAuthnOrigins:       splitConfigurationList(os.Getenv("WEBAUTHN_RP_ORIGINS")),
		MetricsBearerToken:    os.Getenv("METRICS_BEARER_TOKEN"),
		Port:                  os.Getenv("PORT"),
	}

	requiredValues := []struct {
		name  string
		value string
	}{
		{name: "DATABASE_URL", value: config.DatabaseURL},
		{name: "DEPLOYMENT_ENVIRONMENT", value: string(config.DeploymentEnvironment)},
		{name: "S3_ENDPOINT", value: config.S3Endpoint},
		{name: "S3_BUCKET", value: config.S3Bucket},
		{name: "S3_ACCESS_KEY", value: config.S3AccessKey},
		{name: "S3_SECRET_KEY", value: config.S3SecretKey},
		{name: "JWT_ISSUER", value: config.JWTIssuer},
		{name: "JWT_SIGNING_KEY", value: config.JWTSigningKey},
		{name: "WEBAUTHN_RP_ID", value: config.WebAuthnRPID},
		{name: "WEBAUTHN_RP_DISPLAY_NAME", value: config.WebAuthnRPDisplayName},
		{name: "WEBAUTHN_RP_ORIGINS", value: strings.Join(config.WebAuthnOrigins, ",")},
		{name: "PASSKEY_CREDENTIAL_ENCRYPTION_KEY", value: os.Getenv("PASSKEY_CREDENTIAL_ENCRYPTION_KEY")},
		{name: "MIGRATION_WRITES_ENABLED", value: os.Getenv("MIGRATION_WRITES_ENABLED")},
		{name: "METRICS_BEARER_TOKEN", value: config.MetricsBearerToken},
		{name: "PORT", value: config.Port},
	}

	for _, requiredValue := range requiredValues {
		if strings.TrimSpace(requiredValue.value) == "" {
			return Config{}, fmt.Errorf("%s is required", requiredValue.name)
		}
	}
	if len(config.JWTSigningKey) < 32 {
		return Config{}, fmt.Errorf("JWT_SIGNING_KEY must contain at least 32 bytes")
	}
	if len(config.MetricsBearerToken) < 32 {
		return Config{}, fmt.Errorf("METRICS_BEARER_TOKEN must contain at least 32 bytes")
	}
	deploymentEnvironment, err := parseDeploymentEnvironment(string(config.DeploymentEnvironment))
	if err != nil {
		return Config{}, err
	}
	config.DeploymentEnvironment = deploymentEnvironment
	migrationWritesEnabled, err := parseRequiredBoolean(
		"MIGRATION_WRITES_ENABLED", os.Getenv("MIGRATION_WRITES_ENABLED"),
	)
	if err != nil {
		return Config{}, err
	}
	config.MigrationWritesEnabled = migrationWritesEnabled
	passkeyKey, err := base64.StdEncoding.DecodeString(os.Getenv("PASSKEY_CREDENTIAL_ENCRYPTION_KEY"))
	if err != nil || len(passkeyKey) != 32 {
		return Config{}, fmt.Errorf("PASSKEY_CREDENTIAL_ENCRYPTION_KEY must be base64 for exactly 32 bytes")
	}
	config.PasskeyCredentialEncryptionKey = passkeyKey
	allowInsecureS3, err := loadS3AllowInsecure(config.S3Endpoint, os.Getenv("S3_ALLOW_INSECURE"))
	if err != nil {
		return Config{}, err
	}
	config.S3AllowInsecure = allowInsecureS3

	providers := []*OIDCProviderConfig{&config.AppleOIDC, &config.GoogleOIDC, &config.HuaweiOIDC}
	for index, prefix := range []string{"APPLE", "GOOGLE", "HUAWEI"} {
		provider, providerErr := loadOIDCProvider(prefix)
		if providerErr != nil {
			return Config{}, providerErr
		}
		*providers[index] = provider
	}
	appleIAP, err := loadAppleBillingConfig(config.DeploymentEnvironment)
	if err != nil {
		return Config{}, err
	}
	config.AppleIAP = appleIAP

	return config, nil
}

func splitConfigurationList(value string) []string {
	var values []string
	for _, candidate := range strings.Split(value, ",") {
		if candidate = strings.TrimSpace(candidate); candidate != "" {
			values = append(values, candidate)
		}
	}
	return values
}
