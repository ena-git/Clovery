package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/observability"
)

func TestOperationalMetricsRecordOnlyAggregateEvents(t *testing.T) {
	metrics := observability.NewRegistry()
	handler := operationalMetricsMiddleware(metrics)(http.HandlerFunc(
		func(responseWriter http.ResponseWriter, request *http.Request) {
			switch request.URL.Path {
			case "/v1/auth/password/login":
				responseWriter.WriteHeader(http.StatusUnauthorized)
			case "/v1/account/bindings/apple":
				responseWriter.WriteHeader(http.StatusConflict)
			case "/v1/vault/migrations/migration/verify":
				responseWriter.WriteHeader(http.StatusConflict)
			default:
				responseWriter.WriteHeader(http.StatusNoContent)
			}
		},
	))

	for method, path := range map[string]string{
		http.MethodPost + " auth":      "/v1/auth/password/login",
		http.MethodPost + " binding":   "/v1/account/bindings/apple",
		http.MethodDelete + " device":  "/v1/account/devices/secret-device-id",
		http.MethodPost + " migration": "/v1/vault/migrations/migration/verify",
		http.MethodPost + " billing":   "/v1/billing/apple/restore",
	} {
		actualMethod := strings.Fields(method)[0]
		handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(actualMethod, path, nil))
	}

	response := httptest.NewRecorder()
	metrics.Handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	for _, expected := range []string{
		"clovery_authentication_failures_total 1",
		"clovery_binding_failures_total 1",
		"clovery_device_revocations_total 1",
		"clovery_migration_failed_total 1",
		"clovery_migration_validation_mismatch_total 1",
		"clovery_billing_restores_total 1",
	} {
		if !strings.Contains(response.Body.String(), expected) {
			t.Fatalf("metrics missing %q:\n%s", expected, response.Body.String())
		}
	}
	if strings.Contains(response.Body.String(), "secret-device-id") {
		t.Fatal("metrics exposed a resource identifier")
	}
}

func TestStatusResponseWriterKeepsFirstCommittedStatus(t *testing.T) {
	response := httptest.NewRecorder()
	tracked := &statusResponseWriter{ResponseWriter: response, status: http.StatusOK}

	tracked.WriteHeader(http.StatusConflict)
	tracked.WriteHeader(http.StatusInternalServerError)

	if tracked.status != http.StatusConflict || response.Code != http.StatusConflict {
		t.Fatalf("tracked status = %d, response status = %d", tracked.status, response.Code)
	}
}

func TestStatusResponseWriterTreatsImplicitWriteAsSuccess(t *testing.T) {
	response := httptest.NewRecorder()
	tracked := &statusResponseWriter{ResponseWriter: response, status: http.StatusOK}

	_, _ = tracked.Write([]byte("ok"))
	tracked.WriteHeader(http.StatusInternalServerError)

	if tracked.status != http.StatusOK || response.Code != http.StatusOK {
		t.Fatalf("tracked status = %d, response status = %d", tracked.status, response.Code)
	}
}
