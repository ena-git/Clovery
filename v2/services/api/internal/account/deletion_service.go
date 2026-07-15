package account

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

const deletionRetentionPeriod = 30 * 24 * time.Hour

type DeletionRequest struct {
	ID           string
	AccountID    string
	Status       string
	RequestedAt  time.Time
	ScheduledFor time.Time
}

type CreateDeletionRequestParams struct {
	ID           string
	AccountID    string
	RequestedAt  time.Time
	ScheduledFor time.Time
}

type deletionStore interface {
	CreateDeletionRequest(ctx context.Context, params CreateDeletionRequestParams) (DeletionRequest, error)
}

type DeletionService struct {
	store deletionStore
	now   func() time.Time
	newID func() string
}

func NewDeletionService(store deletionStore) (*DeletionService, error) {
	if store == nil {
		return nil, fmt.Errorf("account deletion store is required")
	}
	return &DeletionService{
		store: store,
		now:   func() time.Time { return time.Now().UTC() },
		newID: uuid.NewString,
	}, nil
}

func (service *DeletionService) Request(ctx context.Context, accountID string) (DeletionRequest, error) {
	requestedAt := service.now()
	return service.store.CreateDeletionRequest(ctx, CreateDeletionRequestParams{
		ID:           service.newID(),
		AccountID:    accountID,
		RequestedAt:  requestedAt,
		ScheduledFor: requestedAt.Add(deletionRetentionPeriod),
	})
}
