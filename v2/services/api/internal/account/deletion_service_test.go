package account

import (
	"context"
	"testing"
	"time"
)

func TestDeletionServiceSchedulesThirtyDayRetentionWindow(t *testing.T) {
	store := &stubDeletionStore{}
	service, err := NewDeletionService(store)
	if err != nil {
		t.Fatalf("create deletion service: %v", err)
	}
	now := time.Date(2026, time.July, 14, 16, 0, 0, 0, time.UTC)
	service.now = func() time.Time { return now }
	service.newID = func() string { return "22222222-2222-4222-8222-222222222222" }

	request, err := service.Request(context.Background(), "11111111-1111-4111-8111-111111111111")
	if err != nil {
		t.Fatalf("Request() error = %v", err)
	}
	if !request.ScheduledFor.Equal(now.Add(30*24*time.Hour)) || request.Status != "pending" {
		t.Fatalf("deletion request = %#v", request)
	}
	if store.params.AccountID != request.AccountID || store.params.ID != request.ID {
		t.Fatalf("store params = %#v", store.params)
	}
}

type stubDeletionStore struct {
	params CreateDeletionRequestParams
}

func (store *stubDeletionStore) CreateDeletionRequest(
	_ context.Context,
	params CreateDeletionRequestParams,
) (DeletionRequest, error) {
	store.params = params
	return DeletionRequest{
		ID:           params.ID,
		AccountID:    params.AccountID,
		Status:       "pending",
		RequestedAt:  params.RequestedAt,
		ScheduledFor: params.ScheduledFor,
	}, nil
}
