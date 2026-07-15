package sync

import (
	"context"
	"fmt"
	"time"

	"github.com/clovery/clovery/services/api/internal/vault"
)

const (
	maximumPushOperations = 100
	maximumPullLimit      = 500
)

type vaultAuthorizer interface {
	Get(ctx context.Context, accountID string, vaultID string) (vault.Metadata, error)
}

type repository interface {
	Apply(ctx context.Context, vaultID string, operation Operation, now time.Time) (Decision, error)
	ListChanges(ctx context.Context, vaultID string, cursor int64, limit int) ([]Change, error)
}

type Service struct {
	vaults     vaultAuthorizer
	repository repository
	now        func() time.Time
}

func NewService(vaults vaultAuthorizer, repository repository) (*Service, error) {
	if vaults == nil || repository == nil {
		return nil, fmt.Errorf("sync service dependencies are required")
	}
	return &Service{
		vaults:     vaults,
		repository: repository,
		now:        func() time.Time { return time.Now().UTC() },
	}, nil
}

func (service *Service) Push(
	ctx context.Context,
	accountID string,
	vaultID string,
	operations []Operation,
) ([]Decision, error) {
	if len(operations) == 0 || len(operations) > maximumPushOperations {
		return nil, ErrInvalidOperation
	}
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return nil, err
	}
	results := make([]Decision, 0, len(operations))
	for _, operation := range operations {
		result, err := service.repository.Apply(ctx, vaultID, operation, service.now())
		if err != nil {
			return nil, err
		}
		results = append(results, result)
	}
	return results, nil
}

func (service *Service) Pull(
	ctx context.Context,
	accountID string,
	vaultID string,
	cursor int64,
	limit int,
) (PullPage, error) {
	if cursor < 0 {
		return PullPage{}, ErrInvalidOperation
	}
	if limit < 1 {
		limit = 100
	}
	if limit > maximumPullLimit {
		limit = maximumPullLimit
	}
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return PullPage{}, err
	}
	changes, err := service.repository.ListChanges(ctx, vaultID, cursor, limit+1)
	if err != nil {
		return PullPage{}, err
	}
	return BuildPullPage(changes, limit, cursor), nil
}
