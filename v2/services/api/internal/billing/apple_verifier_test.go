package billing

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestAppleVerifierCallsServerAndVerifiesSignedTransaction(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	apiKey, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC)
	payload := appleTransactionPayload(now)
	client := appleHTTPDoer(func(request *http.Request) (*http.Response, error) {
		if request.Method != http.MethodGet || request.URL.Path != "/inApps/v1/transactions/tx-1" {
			t.Errorf("request = %s %s", request.Method, request.URL.Path)
		}
		assertAppleBearerToken(t, request.Header.Get("Authorization"), &apiKey.PublicKey, now)
		contents, _ := json.Marshal(map[string]string{
			"signedTransactionInfo": fixture.signTransaction(t, payload),
		})
		return appleHTTPResponse(http.StatusOK, contents), nil
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, client, now)

	transaction, err := verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
	if err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	if transaction.ProductID != payload["productId"] || transaction.Status != StateActive {
		t.Fatalf("Verify() = %#v", transaction)
	}
	if transaction.Metadata.Source != "app_store_server_api" || transaction.Metadata.JWSHash == "" {
		t.Fatalf("verification metadata = %#v", transaction.Metadata)
	}
}

func TestAppleVerifierRejectsTamperedJWS(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Now().UTC()
	signed := fixture.signTransaction(t, appleTransactionPayload(now))
	if strings.HasSuffix(signed, "A") {
		signed = signed[:len(signed)-1] + "B"
	} else {
		signed = signed[:len(signed)-1] + "A"
	}
	verifier := newTestAppleVerifier(
		t, fixture.rootDER, privateKeyPEM, signedTransactionDoer(t, signed), now,
	)

	_, err := verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("Verify() tampered JWS error = %v", err)
	}
}

func TestAppleVerifierRejectsUntrustedCertificateChain(t *testing.T) {
	signer := newAppleCertificateFixture(t)
	untrustedRoot := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Now().UTC()
	client := signedTransactionDoer(t, signer.signTransaction(t, appleTransactionPayload(now)))
	verifier := newTestAppleVerifier(t, untrustedRoot.rootDER, privateKeyPEM, client, now)

	_, err := verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("Verify() untrusted chain error = %v", err)
	}
}

func TestAppleVerifierRejectsInvalidSignedClaims(t *testing.T) {
	for name, mutate := range map[string]func(map[string]any){
		"bundle":      func(payload map[string]any) { payload["bundleId"] = "com.attacker.app" },
		"environment": func(payload map[string]any) { payload["environment"] = "Production" },
		"product":     func(payload map[string]any) { payload["productId"] = "unknown.product" },
		"account":     func(payload map[string]any) { payload["appAccountToken"] = "not-a-uuid" },
	} {
		t.Run(name, func(t *testing.T) {
			fixture := newAppleCertificateFixture(t)
			_, privateKeyPEM := newAPISigningKey(t)
			now := time.Now().UTC()
			payload := appleTransactionPayload(now)
			mutate(payload)
			client := signedTransactionDoer(t, fixture.signTransaction(t, payload))
			verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, client, now)

			_, err := verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
			if !errors.Is(err, ErrVerificationFailed) {
				t.Fatalf("Verify() invalid %s error = %v", name, err)
			}
		})
	}
}

func TestAppleVerifierMapsRetryableServerFailure(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	client := appleHTTPDoer(func(_ *http.Request) (*http.Response, error) {
		return appleHTTPResponse(http.StatusServiceUnavailable, nil), nil
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, client, time.Now().UTC())

	_, err := verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
	if !errors.Is(err, ErrVerificationUnavailable) {
		t.Fatalf("Verify() server failure error = %v", err)
	}
}

func TestAppleVerifierMapsUnauthorizedServerResponseAsUnavailable(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	client := appleHTTPDoer(func(_ *http.Request) (*http.Response, error) {
		return appleHTTPResponse(http.StatusUnauthorized, nil), nil
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, client, time.Now().UTC())

	_, err := verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
	if !errors.Is(err, ErrVerificationUnavailable) {
		t.Fatalf("Verify() unauthorized server error = %v", err)
	}
}

func TestDurableEntitlementsRejectConsumableProductType(t *testing.T) {
	if validAppleProductType("Consumable") {
		t.Fatal("consumable product type can create a durable entitlement")
	}
	if validAppleProductType("Non-Renewing Subscription") {
		t.Fatal("non-renewing subscription without a server duration can create a durable entitlement")
	}
	for _, productType := range []string{"Auto-Renewable Subscription", "Non-Consumable"} {
		if !validAppleProductType(productType) {
			t.Fatalf("durable product type %q was rejected", productType)
		}
	}
}

func TestAppleVerifierRejectsSandboxWhenDeploymentDoesNotAllowIt(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	requested := false
	verifier, err := NewAppleVerifier(AppleVerifierConfig{
		IssuerID: "issuer-id", KeyID: "key-id", PrivateKey: privateKeyPEM,
		BundleID: "com.clovery.app", AppAppleID: 1234567890, RootCA: fixture.rootDER,
		ProductIDs: []string{"com.clovery.pro.monthly"},
		HTTPClient: appleHTTPDoer(func(*http.Request) (*http.Response, error) {
			requested = true
			return appleHTTPResponse(http.StatusOK, nil), nil
		}),
	})
	if err != nil {
		t.Fatalf("NewAppleVerifier() error = %v", err)
	}

	_, err = verifier.Verify(context.Background(), "tx-1", EnvironmentSandbox)
	if !errors.Is(err, ErrVerificationFailed) || requested {
		t.Fatalf("Verify() error = %v, requested = %v", err, requested)
	}
}

func newTestAppleVerifier(
	t *testing.T,
	rootDER []byte,
	privateKeyPEM []byte,
	client HTTPDoer,
	now time.Time,
) *AppleVerifier {
	t.Helper()
	verifier, err := NewAppleVerifier(AppleVerifierConfig{
		IssuerID: "issuer-id", KeyID: "key-id", PrivateKey: privateKeyPEM,
		BundleID: "com.clovery.app", AppAppleID: 1234567890, RootCA: rootDER,
		ProductIDs: []string{"com.clovery.pro.monthly"}, HTTPClient: client,
		AllowSandbox:      true,
		ProductionBaseURL: "https://apple.test", SandboxBaseURL: "https://apple.test",
		Now: func() time.Time { return now },
	})
	if err != nil {
		t.Fatalf("NewAppleVerifier() error = %v", err)
	}
	return verifier
}

type appleHTTPDoer func(request *http.Request) (*http.Response, error)

func (doer appleHTTPDoer) Do(request *http.Request) (*http.Response, error) {
	return doer(request)
}

func appleHTTPResponse(status int, contents []byte) *http.Response {
	return &http.Response{
		StatusCode: status,
		Body:       io.NopCloser(strings.NewReader(string(contents))),
		Header:     make(http.Header),
	}
}

func assertAppleBearerToken(
	t *testing.T,
	authorization string,
	publicKey *ecdsa.PublicKey,
	now time.Time,
) {
	t.Helper()
	encoded := strings.TrimPrefix(authorization, "Bearer ")
	claims := jwt.MapClaims{}
	token, err := jwt.ParseWithClaims(encoded, claims, func(token *jwt.Token) (any, error) {
		return publicKey, nil
	}, jwt.WithValidMethods([]string{"ES256"}), jwt.WithTimeFunc(func() time.Time { return now }))
	if err != nil || !token.Valid {
		t.Fatalf("invalid bearer token: %v", err)
	}
	issuer, _ := claims.GetIssuer()
	audience, _ := claims.GetAudience()
	if token.Header["kid"] != "key-id" || issuer != "issuer-id" ||
		len(audience) != 1 || audience[0] != "appstoreconnect-v1" || claims["bid"] != "com.clovery.app" {
		t.Fatalf("bearer header = %#v, claims = %#v", token.Header, claims)
	}
}

func newAPISigningKey(t *testing.T) (*ecdsa.PrivateKey, []byte) {
	t.Helper()
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate API key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		t.Fatalf("marshal API key: %v", err)
	}
	return privateKey, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
}
