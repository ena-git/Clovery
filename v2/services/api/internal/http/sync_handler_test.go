package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/observability"
	cloverysync "github.com/clovery/clovery/services/api/internal/sync"
)

func TestSyncPushUsesAuthenticatedVaultAndReturnsConflictSnapshot(t *testing.T) {
	metrics := observability.NewRegistry()
	observedBacklog := ""
	application := &stubSyncHTTPApplication{decisions: []cloverysync.Decision{{
		OperationID: "11111111-1111-4111-8111-111111111111",
		Status:      cloverysync.StatusConflict,
		ServerSnapshot: &cloverysync.Entry{
			ID: "22222222-2222-4222-8222-222222222222", Revision: 4,
		},
	}}}
	application.onPush = func() {
		metricsResponse := httptest.NewRecorder()
		metrics.Handler().ServeHTTP(metricsResponse, httptest.NewRequest(http.MethodGet, "/metrics", nil))
		observedBacklog = metricsResponse.Body.String()
	}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Sync: application, Metrics: metrics})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/vault/sync/push",
		strings.NewReader(`{"operations":[{"operation_id":"11111111-1111-4111-8111-111111111111","entry_id":"22222222-2222-4222-8222-222222222222","base_revision":3,"payload":{"text":"client"},"deleted":false}]}`),
	)
	request.Header.Set("Authorization", "Bearer access-token")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"server_snapshot"`) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.accountID != managementSessions().claims.AccountID ||
		application.vaultID != managementSessions().claims.VaultID {
		t.Fatalf("sync scope account = %q, vault = %q", application.accountID, application.vaultID)
	}
	metricsResponse := httptest.NewRecorder()
	metrics.Handler().ServeHTTP(metricsResponse, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if !strings.Contains(observedBacklog, "clovery_sync_backlog_operations 1") ||
		!strings.Contains(metricsResponse.Body.String(), "clovery_sync_conflicts_total 1") ||
		!strings.Contains(metricsResponse.Body.String(), "clovery_sync_backlog_operations 0") {
		t.Fatalf("during metrics = %s, after metrics = %s", observedBacklog, metricsResponse.Body.String())
	}
}

func TestSyncPullParsesCursorAndLimit(t *testing.T) {
	application := &stubSyncHTTPApplication{page: cloverysync.PullPage{NextCursor: 12}}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Sync: application})
	request := httptest.NewRequest(http.MethodGet, "/v1/vault/sync/pull?cursor=9&limit=50", nil)
	request.Header.Set("Authorization", "Bearer access-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK || application.cursor != 9 || application.limit != 50 {
		t.Fatalf("status = %d, cursor = %d, limit = %d", response.Code, application.cursor, application.limit)
	}
}

func TestSyncPushAcceptsDocumentedBatchAboveDefaultJSONLimit(t *testing.T) {
	application := &stubSyncHTTPApplication{}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Sync: application})
	largeText := strings.Repeat("a", 70*1024)
	body := `{"operations":[{"operation_id":"11111111-1111-4111-8111-111111111111",` +
		`"entry_id":"22222222-2222-4222-8222-222222222222","base_revision":0,` +
		`"payload":{"text":"` + largeText + `"},"deleted":false}]}`
	response := authenticatedBillingRequest(
		t, router, http.MethodPost, "/v1/vault/sync/push", body,
	)
	if response.Code != http.StatusOK {
		t.Fatalf("large sync push status = %d, body = %s", response.Code, response.Body.String())
	}
}

type stubSyncHTTPApplication struct {
	accountID string
	vaultID   string
	cursor    int64
	limit     int
	decisions []cloverysync.Decision
	page      cloverysync.PullPage
	onPush    func()
}

func (stub *stubSyncHTTPApplication) Push(
	_ context.Context,
	accountID string,
	vaultID string,
	_ []cloverysync.Operation,
) ([]cloverysync.Decision, error) {
	stub.accountID = accountID
	stub.vaultID = vaultID
	if stub.onPush != nil {
		stub.onPush()
	}
	return stub.decisions, nil
}

func (stub *stubSyncHTTPApplication) Pull(
	_ context.Context,
	accountID string,
	vaultID string,
	cursor int64,
	limit int,
) (cloverysync.PullPage, error) {
	stub.accountID = accountID
	stub.vaultID = vaultID
	stub.cursor = cursor
	stub.limit = limit
	return stub.page, nil
}
