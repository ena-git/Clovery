package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/observability"
)

func TestMetricsEndpointRequiresOperationalBearerToken(t *testing.T) {
	metrics := observability.NewRegistry()
	metrics.Increment(observability.MigrationStarted)
	router := NewRouter(RouterDependencies{
		Metrics: metrics, MetricsBearerToken: "0123456789abcdef0123456789abcdef",
	})

	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/internal/metrics", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d", unauthorized.Code)
	}

	request := httptest.NewRequest(http.MethodGet, "/internal/metrics", nil)
	request.Header.Set("Authorization", "Bearer 0123456789abcdef0123456789abcdef")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), "clovery_migration_started_total 1") {
		t.Fatalf("metrics status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestDisabledMigrationWritesKeepReportsReadable(t *testing.T) {
	application := &stubMigrationHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Sessions: managementSessions(), Migrations: application, MigrationWritesEnabled: false,
	})
	createRequest := httptest.NewRequest(http.MethodPost, "/v1/vault/migrations", strings.NewReader(`{}`))
	createRequest.Header.Set("Authorization", "Bearer access-token")
	createResponse := httptest.NewRecorder()
	router.ServeHTTP(createResponse, createRequest)
	if createResponse.Code != http.StatusServiceUnavailable || application.vaultID != "" {
		t.Fatalf("create status = %d, application vault = %q", createResponse.Code, application.vaultID)
	}

	reportRequest := httptest.NewRequest(http.MethodGet, "/v1/vault/migrations/migration/report", nil)
	reportRequest.Header.Set("Authorization", "Bearer access-token")
	reportResponse := httptest.NewRecorder()
	router.ServeHTTP(reportResponse, reportRequest)
	if reportResponse.Code != http.StatusOK {
		t.Fatalf("report status = %d, body = %s", reportResponse.Code, reportResponse.Body.String())
	}
}
