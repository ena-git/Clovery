package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/clovery/clovery/services/api/internal/config"
)

func TestBuildHandlerRegistersBillingOnlyWhenAppleIAPConfigured(t *testing.T) {
	databaseHandle, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create mock database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })

	withoutBilling, err := buildHandler(databaseHandle, identityTestConfig())
	if err != nil {
		t.Fatalf("build handler without billing: %v", err)
	}
	missing := httptest.NewRecorder()
	withoutBilling.ServeHTTP(missing, httptest.NewRequest(
		http.MethodGet, "/v1/account/entitlements", nil,
	))
	if missing.Code != http.StatusNotFound {
		t.Fatalf("unconfigured billing status = %d", missing.Code)
	}

	configured := identityTestConfig()
	configured.AppleIAP = appleBillingConfigFixture(t)
	withBilling, err := buildHandler(databaseHandle, configured)
	if err != nil {
		t.Fatalf("build handler with billing: %v", err)
	}
	protected := httptest.NewRecorder()
	withBilling.ServeHTTP(protected, httptest.NewRequest(
		http.MethodGet, "/v1/account/entitlements", nil,
	))
	if protected.Code != http.StatusUnauthorized {
		t.Fatalf("configured billing status = %d, body = %s", protected.Code, protected.Body.String())
	}
}

func TestBuildHandlerRejectsInvalidConfiguredAppleVerifier(t *testing.T) {
	databaseHandle, _, _ := sqlmock.New()
	t.Cleanup(func() { _ = databaseHandle.Close() })
	applicationConfig := identityTestConfig()
	applicationConfig.AppleIAP = appleBillingConfigFixture(t)
	applicationConfig.AppleIAP.PrivateKey = []byte("not a p8 key")

	if _, err := buildHandler(databaseHandle, applicationConfig); err == nil {
		t.Fatal("buildHandler() accepted invalid configured Apple verifier")
	}
}

func appleBillingConfigFixture(t *testing.T) config.AppleBillingConfig {
	t.Helper()
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate billing key: %v", err)
	}
	privateDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		t.Fatalf("marshal billing key: %v", err)
	}
	now := time.Now().UTC()
	certificate := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Apple Test Root"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), IsCA: true,
		BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	rootDER, err := x509.CreateCertificate(
		rand.Reader, certificate, certificate, &privateKey.PublicKey, privateKey,
	)
	if err != nil {
		t.Fatalf("create billing root: %v", err)
	}
	return config.AppleBillingConfig{
		IssuerID: "issuer-id", KeyID: "key-id",
		PrivateKey: pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privateDER}),
		BundleID:   "com.clovery.app", AppAppleID: 1234567890, RootCA: rootDER,
		ProductIDs: []string{"com.clovery.pro.monthly"},
	}
}
