package config

import (
	"encoding/base64"
	"reflect"
	"strings"
	"testing"
)

var appleIAPEnvironmentKeys = []string{
	"APPLE_IAP_ISSUER_ID",
	"APPLE_IAP_KEY_ID",
	"APPLE_IAP_PRIVATE_KEY_BASE64",
	"APPLE_IAP_BUNDLE_ID",
	"APPLE_IAP_APP_APPLE_ID",
	"APPLE_IAP_ROOT_CA_BASE64",
	"APPLE_IAP_PRODUCT_IDS",
}

func TestLoadAllowsAbsentAppleIAPConfiguration(t *testing.T) {
	setValidEnvironment(t)
	clearAppleIAPEnvironment(t)

	if _, err := Load(); err != nil {
		t.Fatalf("Load() rejected absent Apple IAP configuration: %v", err)
	}
}

func TestLoadRejectsPartialAppleIAPConfiguration(t *testing.T) {
	setValidEnvironment(t)
	clearAppleIAPEnvironment(t)
	t.Setenv("APPLE_IAP_ISSUER_ID", "issuer-id")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "APPLE_IAP configuration is incomplete") {
		t.Fatalf("Load() partial Apple IAP error = %v", err)
	}
}

func TestLoadReturnsConfiguredAppleIAP(t *testing.T) {
	setValidEnvironment(t)
	clearAppleIAPEnvironment(t)
	privateKey := []byte("private-key-fixture")
	rootCA := []byte("root-certificate-fixture")
	t.Setenv("APPLE_IAP_ISSUER_ID", "issuer-id")
	t.Setenv("APPLE_IAP_KEY_ID", "key-id")
	t.Setenv("APPLE_IAP_PRIVATE_KEY_BASE64", base64.StdEncoding.EncodeToString(privateKey))
	t.Setenv("APPLE_IAP_BUNDLE_ID", "com.clovery.app")
	t.Setenv("APPLE_IAP_APP_APPLE_ID", "1234567890")
	t.Setenv("APPLE_IAP_ROOT_CA_BASE64", base64.StdEncoding.EncodeToString(rootCA))
	t.Setenv("APPLE_IAP_PRODUCT_IDS", "com.clovery.pro.monthly, com.clovery.pro.yearly")

	loaded, err := Load()
	if err != nil {
		t.Fatalf("Load() returned an unexpected error: %v", err)
	}
	appleIAP := reflect.ValueOf(loaded).FieldByName("AppleIAP")
	if !appleIAP.IsValid() {
		t.Fatal("Config is missing AppleIAP")
	}
	if got := appleIAP.FieldByName("PrivateKey").Bytes(); string(got) != string(privateKey) {
		t.Fatalf("AppleIAP.PrivateKey = %q", got)
	}
	if got := appleIAP.FieldByName("ProductIDs").Interface().([]string); len(got) != 2 {
		t.Fatalf("AppleIAP.ProductIDs = %#v", got)
	}
	if got := appleIAP.FieldByName("AppAppleID").Int(); got != 1234567890 {
		t.Fatalf("AppleIAP.AppAppleID = %d", got)
	}
}

func TestLoadRejectsInvalidAppleIAPEncoding(t *testing.T) {
	setValidEnvironment(t)
	setCompleteAppleIAPEnvironment(t)
	t.Setenv("APPLE_IAP_PRIVATE_KEY_BASE64", "not-base64")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "APPLE_IAP_PRIVATE_KEY_BASE64") {
		t.Fatalf("Load() invalid private key error = %v", err)
	}
}

func TestLoadRequiresAppleIAPInProduction(t *testing.T) {
	setValidEnvironment(t)
	clearAppleIAPEnvironment(t)
	t.Setenv("DEPLOYMENT_ENVIRONMENT", "production")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "APPLE_IAP") {
		t.Fatalf("Load() missing production Apple IAP error = %v", err)
	}
}

func TestLoadRejectsSandboxAppleIAPInProduction(t *testing.T) {
	setValidEnvironment(t)
	setCompleteAppleIAPEnvironment(t)
	t.Setenv("DEPLOYMENT_ENVIRONMENT", "production")
	t.Setenv("APPLE_IAP_ALLOW_SANDBOX", "true")

	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "APPLE_IAP_ALLOW_SANDBOX") {
		t.Fatalf("Load() production sandbox error = %v", err)
	}
}

func clearAppleIAPEnvironment(t *testing.T) {
	t.Helper()
	for _, key := range appleIAPEnvironmentKeys {
		t.Setenv(key, "")
	}
	t.Setenv("APPLE_IAP_ALLOW_SANDBOX", "")
}

func setCompleteAppleIAPEnvironment(t *testing.T) {
	t.Helper()
	t.Setenv("APPLE_IAP_ISSUER_ID", "issuer-id")
	t.Setenv("APPLE_IAP_KEY_ID", "key-id")
	t.Setenv("APPLE_IAP_PRIVATE_KEY_BASE64", base64.StdEncoding.EncodeToString([]byte("private-key")))
	t.Setenv("APPLE_IAP_BUNDLE_ID", "com.clovery.app")
	t.Setenv("APPLE_IAP_APP_APPLE_ID", "1234567890")
	t.Setenv("APPLE_IAP_ROOT_CA_BASE64", base64.StdEncoding.EncodeToString([]byte("root-ca")))
	t.Setenv("APPLE_IAP_PRODUCT_IDS", "com.clovery.pro.monthly")
}
