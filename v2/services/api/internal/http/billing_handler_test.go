package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/billing"
)

func TestBillingRoutesUseOnlyAuthenticatedAccount(t *testing.T) {
	application := &stubBillingHTTPApplication{
		entitlement:  billing.Entitlement{ProductID: "com.clovery.pro.monthly", State: billing.StateActive},
		entitlements: []billing.Entitlement{{ProductID: "com.clovery.pro.monthly", State: billing.StateActive}},
	}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Billing: application})

	verifyResponse := authenticatedBillingRequest(
		t, router, http.MethodPost, "/v1/billing/apple/transactions/verify",
		`{"transaction_id":"tx-1","environment":"sandbox"}`,
	)
	if verifyResponse.Code != http.StatusOK {
		t.Fatalf("verify status = %d, body = %s", verifyResponse.Code, verifyResponse.Body.String())
	}
	claims := managementSessions().claims
	if application.accountID != claims.AccountID || application.transactionID != "tx-1" {
		t.Fatalf("verify account = %q, transaction = %q", application.accountID, application.transactionID)
	}

	restoreResponse := authenticatedBillingRequest(
		t, router, http.MethodPost, "/v1/billing/apple/restore",
		`{"transaction_ids":["tx-1","tx-2"],"environment":"sandbox"}`,
	)
	if restoreResponse.Code != http.StatusOK || len(application.transactionIDs) != 2 {
		t.Fatalf("restore status = %d, transactions = %#v", restoreResponse.Code, application.transactionIDs)
	}

	legacyResponse := authenticatedBillingRequest(
		t, router, http.MethodPost, "/v1/billing/apple/legacy-claims",
		`{"signed_transaction_info":"signed-legacy-proof","environment":"sandbox"}`,
	)
	if legacyResponse.Code != http.StatusOK ||
		application.signedTransactionInfo != "signed-legacy-proof" ||
		application.accountID != claims.AccountID {
		t.Fatalf(
			"legacy claim status = %d, account = %q, proof = %q",
			legacyResponse.Code, application.accountID, application.signedTransactionInfo,
		)
	}

	listResponse := authenticatedBillingRequest(t, router, http.MethodGet, "/v1/account/entitlements", "")
	if listResponse.Code != http.StatusOK || application.accountID != claims.AccountID {
		t.Fatalf("list status = %d, account = %q", listResponse.Code, application.accountID)
	}
}

func TestBillingVerifyRejectsClientSuppliedAccount(t *testing.T) {
	application := &stubBillingHTTPApplication{}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Billing: application})
	response := authenticatedBillingRequest(
		t, router, http.MethodPost, "/v1/billing/apple/transactions/verify",
		`{"transaction_id":"tx-1","environment":"sandbox","account_id":"22222222-2222-4222-8222-222222222222"}`,
	)

	if response.Code != http.StatusBadRequest || application.verifyCalls != 0 {
		t.Fatalf("status = %d, calls = %d, body = %s", response.Code, application.verifyCalls, response.Body.String())
	}
}

func TestAppleNotificationRouteUsesSignedPayloadWithoutUserSession(t *testing.T) {
	application := &stubBillingHTTPApplication{}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Billing: application})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/billing/apple/notifications",
		strings.NewReader(`{"signedPayload":"signed-notification"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent || application.signedPayload != "signed-notification" {
		t.Fatalf("status = %d, signed payload = %q, body = %s", response.Code, application.signedPayload, response.Body.String())
	}
}

func TestBillingRoutesMapStableErrors(t *testing.T) {
	for _, testCase := range []struct {
		name   string
		err    error
		status int
		code   string
	}{
		{name: "invalid", err: billing.ErrInvalidRequest, status: 400, code: "invalid_billing_request"},
		{name: "account", err: billing.ErrAccountMismatch, status: 403, code: "apple_transaction_account_mismatch"},
		{name: "claimed", err: billing.ErrTransactionClaimed, status: 409, code: "apple_transaction_claimed"},
		{name: "verification", err: billing.ErrVerificationFailed, status: 422, code: "apple_transaction_invalid"},
		{name: "unavailable", err: billing.ErrVerificationUnavailable, status: 503, code: "apple_verification_unavailable"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			application := &stubBillingHTTPApplication{err: testCase.err}
			router := NewRouter(RouterDependencies{Sessions: managementSessions(), Billing: application})
			response := authenticatedBillingRequest(
				t, router, http.MethodPost, "/v1/billing/apple/transactions/verify",
				`{"transaction_id":"tx-1","environment":"sandbox"}`,
			)
			if response.Code != testCase.status || !strings.Contains(response.Body.String(), `"code":"`+testCase.code+`"`) {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
		})
	}
}

func authenticatedBillingRequest(
	t *testing.T,
	handler http.Handler,
	method string,
	path string,
	body string,
) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, path, strings.NewReader(body))
	request.Header.Set("Authorization", "Bearer access-token")
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

type stubBillingHTTPApplication struct {
	accountID             string
	transactionID         string
	transactionIDs        []string
	signedPayload         string
	signedTransactionInfo string
	verifyCalls           int
	entitlement           billing.Entitlement
	entitlements          []billing.Entitlement
	err                   error
}

func (stub *stubBillingHTTPApplication) ClaimLegacy(
	_ context.Context,
	accountID string,
	signedTransactionInfo string,
	_ billing.Environment,
) (billing.Entitlement, error) {
	stub.accountID = accountID
	stub.signedTransactionInfo = signedTransactionInfo
	return stub.entitlement, stub.err
}

func (stub *stubBillingHTTPApplication) ProcessAppleNotification(
	_ context.Context,
	signedPayload string,
) error {
	stub.signedPayload = signedPayload
	return stub.err
}

func (stub *stubBillingHTTPApplication) Verify(
	_ context.Context,
	accountID string,
	transactionID string,
	_ billing.Environment,
) (billing.Entitlement, error) {
	stub.verifyCalls++
	stub.accountID = accountID
	stub.transactionID = transactionID
	return stub.entitlement, stub.err
}

func (stub *stubBillingHTTPApplication) Restore(
	_ context.Context,
	accountID string,
	transactionIDs []string,
	_ billing.Environment,
) ([]billing.Entitlement, error) {
	stub.accountID = accountID
	stub.transactionIDs = transactionIDs
	return stub.entitlements, stub.err
}

func (stub *stubBillingHTTPApplication) List(
	_ context.Context,
	accountID string,
) ([]billing.Entitlement, error) {
	stub.accountID = accountID
	return stub.entitlements, stub.err
}
