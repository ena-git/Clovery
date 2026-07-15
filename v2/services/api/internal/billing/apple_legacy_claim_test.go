package billing

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
	"time"
)

func TestAppleVerifierVerifiesLegacyProofWithoutAccountToken(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Now().UTC()
	payload := appleTransactionPayload(now)
	delete(payload, "appAccountToken")
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	transaction, err := verifier.VerifyLegacyProof(
		context.Background(), fixture.signTransaction(t, payload), EnvironmentSandbox,
	)
	if err != nil {
		t.Fatalf("VerifyLegacyProof() error = %v", err)
	}
	if transaction.AppAccountToken != "" || transaction.OriginalTransactionID != "original-1" {
		t.Fatalf("VerifyLegacyProof() = %#v", transaction)
	}
}

func TestAppleVerifierAssignsAccountTokenThenReverifiesTransaction(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	apiKey, privateKeyPEM := newAPISigningKey(t)
	now := time.Now().UTC()
	payload := appleTransactionPayload(now)
	requestCount := 0
	client := appleHTTPDoer(func(request *http.Request) (*http.Response, error) {
		requestCount++
		assertAppleBearerToken(t, request.Header.Get("Authorization"), &apiKey.PublicKey, now)
		switch requestCount {
		case 1:
			if request.Method != http.MethodPut ||
				request.URL.Path != "/inApps/v1/transactions/original-1/appAccountToken" {
				t.Fatalf("assignment request = %s %s", request.Method, request.URL.Path)
			}
			contents, _ := io.ReadAll(request.Body)
			var body map[string]string
			if json.Unmarshal(contents, &body) != nil || body["appAccountToken"] != billingAccountID {
				t.Fatalf("assignment body = %s", contents)
			}
			return appleHTTPResponse(http.StatusOK, nil), nil
		case 2:
			if request.Method != http.MethodGet || request.URL.Path != "/inApps/v1/transactions/tx-1" {
				t.Fatalf("verification request = %s %s", request.Method, request.URL.Path)
			}
			contents, _ := json.Marshal(map[string]string{
				"signedTransactionInfo": fixture.signTransaction(t, payload),
			})
			return appleHTTPResponse(http.StatusOK, contents), nil
		default:
			t.Fatalf("unexpected Apple request %d", requestCount)
			return nil, nil
		}
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, client, now)

	transaction, err := verifier.AssignAccountToken(
		context.Background(), "original-1", "tx-1", billingAccountID, EnvironmentSandbox,
	)
	if err != nil {
		t.Fatalf("AssignAccountToken() error = %v", err)
	}
	if requestCount != 2 || transaction.AppAccountToken != billingAccountID {
		t.Fatalf("AssignAccountToken() requests = %d, transaction = %#v", requestCount, transaction)
	}
}
