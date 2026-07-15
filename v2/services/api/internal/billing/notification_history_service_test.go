package billing

import (
	"context"
	"testing"
	"time"
)

func TestServiceReplaysEveryNotificationHistoryPage(t *testing.T) {
	now := time.Now().UTC()
	verifier := &historyStubVerifier{
		stubVerifier: stubVerifier{notification: AppleNotification{
			ID: "33333333-3333-4333-8333-333333333333", Type: "TEST",
			SignedAt: now, PayloadSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		}},
		pages: map[string]NotificationHistoryPage{
			"":       {SignedPayloads: []string{"signed-1"}, HasMore: true, PaginationToken: "page-2"},
			"page-2": {SignedPayloads: []string{"signed-2"}},
		},
	}
	repository := &stubRepository{}
	service, _ := NewService(verifier, repository)

	processed, err := service.ReplayNotificationHistory(context.Background(), NotificationHistoryQuery{
		StartAt: now.Add(-time.Hour), EndAt: now, Environment: EnvironmentSandbox,
	})
	if err != nil {
		t.Fatalf("ReplayNotificationHistory() error = %v", err)
	}
	if processed != 2 || verifier.fetchCalls != 2 || repository.notificationCalls != 2 {
		t.Fatalf(
			"replay processed=%d fetches=%d records=%d",
			processed, verifier.fetchCalls, repository.notificationCalls,
		)
	}
}

type historyStubVerifier struct {
	stubVerifier
	pages      map[string]NotificationHistoryPage
	fetchCalls int
}

func (stub *historyStubVerifier) FetchNotificationHistoryPage(
	_ context.Context,
	query NotificationHistoryQuery,
) (NotificationHistoryPage, error) {
	stub.fetchCalls++
	return stub.pages[query.PaginationToken], nil
}
