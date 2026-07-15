package billing

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

func TestAppleVerifierFetchesNotificationHistoryPage(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	apiKey, privateKeyPEM := newAPISigningKey(t)
	now := time.Now().UTC()
	startAt := now.Add(-24 * time.Hour)
	client := appleHTTPDoer(func(request *http.Request) (*http.Response, error) {
		if request.Method != http.MethodPost || request.URL.Path != "/inApps/v1/notifications/history" ||
			request.URL.Query().Get("paginationToken") != "page-1" {
			t.Fatalf("history request = %s %s", request.Method, request.URL.String())
		}
		assertAppleBearerToken(t, request.Header.Get("Authorization"), &apiKey.PublicKey, now)
		var body struct {
			StartDate    int64 `json:"startDate"`
			EndDate      int64 `json:"endDate"`
			OnlyFailures bool  `json:"onlyFailures"`
		}
		if json.NewDecoder(request.Body).Decode(&body) != nil || body.StartDate != startAt.UnixMilli() ||
			body.EndDate != now.UnixMilli() || !body.OnlyFailures {
			t.Fatalf("history request body = %#v", body)
		}
		contents, _ := json.Marshal(map[string]any{
			"notificationHistory": []map[string]string{{"signedPayload": "signed-1"}},
			"hasMore":             true,
			"paginationToken":     "page-2",
		})
		return appleHTTPResponse(http.StatusOK, contents), nil
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, client, now)

	page, err := verifier.FetchNotificationHistoryPage(context.Background(), NotificationHistoryQuery{
		StartAt: startAt, EndAt: now, Environment: EnvironmentSandbox,
		OnlyFailures: true, PaginationToken: "page-1",
	})
	if err != nil {
		t.Fatalf("FetchNotificationHistoryPage() error = %v", err)
	}
	if len(page.SignedPayloads) != 1 || page.SignedPayloads[0] != "signed-1" ||
		!page.HasMore || page.PaginationToken != "page-2" {
		t.Fatalf("FetchNotificationHistoryPage() = %#v", page)
	}
}
