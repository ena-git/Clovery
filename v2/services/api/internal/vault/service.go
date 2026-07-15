package vault

import (
	"context"
	"errors"
	"fmt"
	"time"
)

var ErrForbidden = errors.New("vault access forbidden")

type Metadata struct {
	ID        string
	Status    string
	CreatedAt time.Time
}

type repository interface {
	GetOwned(ctx context.Context, accountID string, vaultID string) (Metadata, error)
	RecordAccessDenial(ctx context.Context, accountID string, vaultID string) error
}

type Service struct {
	repository repository
}

func NewService(repository repository) (*Service, error) {
	if repository == nil {
		return nil, fmt.Errorf("vault repository is required")
	}
	return &Service{repository: repository}, nil
}

func (service *Service) Get(
	ctx context.Context,
	accountID string,
	vaultID string,
) (Metadata, error) {
	metadata, err := service.repository.GetOwned(ctx, accountID, vaultID)
	if !errors.Is(err, ErrForbidden) {
		return metadata, err
	}
	if auditErr := service.repository.RecordAccessDenial(ctx, accountID, vaultID); auditErr != nil {
		return Metadata{}, fmt.Errorf("audit vault access denial: %w", auditErr)
	}
	return Metadata{}, ErrForbidden
}
