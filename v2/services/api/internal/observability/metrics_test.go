package observability

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRegistryExportsOnlyAllowlistedCountersAndGauges(t *testing.T) {
	registry := NewRegistry()
	registry.Increment(MigrationStarted)
	registry.Add(SyncConflicts, 2)
	registry.Set(SyncBacklog, 7)

	response := httptest.NewRecorder()
	request := httptest.NewRequest("GET", "/metrics", nil)
	registry.Handler().ServeHTTP(response, request)

	if response.Code != 200 {
		t.Fatalf("status = %d", response.Code)
	}
	for _, expected := range []string{
		"clovery_migration_started_total 1",
		"clovery_sync_conflicts_total 2",
		"clovery_sync_backlog_operations 7",
	} {
		if !strings.Contains(response.Body.String(), expected) {
			t.Fatalf("metrics body missing %q:\n%s", expected, response.Body.String())
		}
	}
	if strings.Contains(response.Body.String(), "account") || strings.Contains(response.Body.String(), "vault") {
		t.Fatalf("metrics body contains identity labels: %s", response.Body.String())
	}
}

func TestRegistryRejectsUnknownMetricKinds(t *testing.T) {
	registry := NewRegistry()
	registry.Add(Counter("journal_body"), 1)
	registry.Set(Gauge("email"), 3)

	response := httptest.NewRecorder()
	registry.Handler().ServeHTTP(response, httptest.NewRequest("GET", "/metrics", nil))

	if strings.Contains(response.Body.String(), "journal_body") || strings.Contains(response.Body.String(), "email") {
		t.Fatalf("unknown metric was exported: %s", response.Body.String())
	}
}

func TestRegistryAdjustsBacklogWithoutGoingNegative(t *testing.T) {
	registry := NewRegistry()
	registry.Adjust(SyncBacklog, 5)
	registry.Adjust(SyncBacklog, -9)

	response := httptest.NewRecorder()
	registry.Handler().ServeHTTP(response, httptest.NewRequest("GET", "/metrics", nil))
	if !strings.Contains(response.Body.String(), "clovery_sync_backlog_operations 0") {
		t.Fatalf("metrics body = %s", response.Body.String())
	}
}
