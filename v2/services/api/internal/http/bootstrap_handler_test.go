package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
)

func TestBootstrapRoutesUseOnlyAuthenticatedAccountAndVault(t *testing.T) {
	sessions := managementSessions()
	application := &stubBootstrapHTTPApplication{result: BootstrapStatus{
		Status:     "pending",
		SourceKind: "new_install",
		Stages: BootstrapStages{
			Identity: "complete", Migration: "complete", Entitlement: "pending", Vault: "pending",
		},
		RetryCount: 0,
		UpdatedAt:  time.Date(2026, time.July, 19, 12, 0, 0, 0, time.UTC),
	}}
	router := NewRouter(RouterDependencies{Sessions: sessions, Bootstrap: application})

	getRequest := httptest.NewRequest(http.MethodGet, "/v1/account/bootstrap", nil)
	getRequest.Header.Set("Authorization", "Bearer access-token")
	getResponse := httptest.NewRecorder()
	router.ServeHTTP(getResponse, getRequest)
	if getResponse.Code != http.StatusOK {
		t.Fatalf("GET status = %d, body = %s", getResponse.Code, getResponse.Body.String())
	}
	for _, fragment := range []string{
		`"status":"pending"`, `"source_kind":"new_install"`, `"migration_id":null`,
		`"stages":{"identity":"complete","migration":"complete","entitlement":"pending","vault":"pending"}`,
		`"last_error_code":null`, `"retry_count":0`,
	} {
		if !strings.Contains(getResponse.Body.String(), fragment) {
			t.Errorf("GET body missing %s: %s", fragment, getResponse.Body.String())
		}
	}
	for _, forbidden := range []string{`"account_id"`, `"vault_id"`, `"identity_state"`} {
		if strings.Contains(getResponse.Body.String(), forbidden) {
			t.Errorf("GET body exposed non-contract field %s: %s", forbidden, getResponse.Body.String())
		}
	}
	if application.accountID != sessions.claims.AccountID {
		t.Fatalf("GET account ID = %q", application.accountID)
	}

	resumeRequest := httptest.NewRequest(
		http.MethodPost,
		"/v1/account/bootstrap/resume?account_id=attacker&vault_id=attacker",
		strings.NewReader(`{"source_kind":"legacy_local","account_id":"attacker","vault_id":"attacker"}`),
	)
	resumeRequest.Header.Set("Authorization", "Bearer access-token")
	resumeRequest.Header.Set("Content-Type", "application/json")
	resumeResponse := httptest.NewRecorder()
	router.ServeHTTP(resumeResponse, resumeRequest)
	if resumeResponse.Code != http.StatusBadRequest {
		t.Fatalf("resume with extra ownership fields status = %d, body = %s", resumeResponse.Code, resumeResponse.Body.String())
	}

	resumeRequest = httptest.NewRequest(
		http.MethodPost,
		"/v1/account/bootstrap/resume?account_id=attacker&vault_id=attacker",
		strings.NewReader(`{"source_kind":"legacy_local"}`),
	)
	resumeRequest.Header.Set("Authorization", "Bearer access-token")
	resumeRequest.Header.Set("Content-Type", "application/json")
	resumeResponse = httptest.NewRecorder()
	router.ServeHTTP(resumeResponse, resumeRequest)
	if resumeResponse.Code != http.StatusOK {
		t.Fatalf("resume status = %d, body = %s", resumeResponse.Code, resumeResponse.Body.String())
	}
	if application.accountID != sessions.claims.AccountID || application.vaultID != sessions.claims.VaultID ||
		application.sourceKind != "legacy_local" {
		t.Fatalf("resume scope account=%q vault=%q source=%q", application.accountID, application.vaultID, application.sourceKind)
	}
}

func TestBootstrapRoutesRequireAuthentication(t *testing.T) {
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Bootstrap: &stubBootstrapHTTPApplication{}})
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/v1/account/bootstrap", nil),
		httptest.NewRequest(http.MethodPost, "/v1/account/bootstrap/resume", strings.NewReader(`{"source_kind":"new_install"}`)),
	} {
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("%s status = %d, body = %s", request.URL.Path, response.Code, response.Body.String())
		}
	}
}

func TestBootstrapHandlerReturnsStableErrors(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		body       string
		err        error
		wantStatus int
		wantCode   string
	}{
		{name: "missing job", method: http.MethodGet, err: bootstrapjob.ErrNotFound, wantStatus: http.StatusNotFound, wantCode: "bootstrap_not_found"},
		{name: "invalid source", method: http.MethodPost, body: `{"source_kind":"other"}`, wantStatus: http.StatusBadRequest, wantCode: "invalid_bootstrap_request"},
		{name: "invalid transition", method: http.MethodPost, body: `{"source_kind":"new_install"}`, err: bootstrapjob.ErrInvalidTransition, wantStatus: http.StatusConflict, wantCode: "bootstrap_conflict"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			application := &stubBootstrapHTTPApplication{err: test.err}
			router := NewRouter(RouterDependencies{Sessions: managementSessions(), Bootstrap: application})
			path := "/v1/account/bootstrap"
			if test.method == http.MethodPost {
				path += "/resume"
			}
			request := httptest.NewRequest(test.method, path, strings.NewReader(test.body))
			request.Header.Set("Authorization", "Bearer access-token")
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != test.wantStatus || !strings.Contains(response.Body.String(), `"`+test.wantCode+`"`) {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
		})
	}
}

type stubBootstrapHTTPApplication struct {
	accountID  string
	vaultID    string
	sourceKind string
	result     BootstrapStatus
	err        error
}

func (application *stubBootstrapHTTPApplication) GetBootstrap(
	_ context.Context,
	accountID string,
) (BootstrapStatus, error) {
	application.accountID = accountID
	return application.result, application.err
}

func (application *stubBootstrapHTTPApplication) ResumeBootstrap(
	_ context.Context,
	accountID string,
	vaultID string,
	sourceKind string,
) (BootstrapStatus, error) {
	application.accountID = accountID
	application.vaultID = vaultID
	application.sourceKind = sourceKind
	return application.result, application.err
}
