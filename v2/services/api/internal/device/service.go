package device

import (
	"context"
	"fmt"
	"time"
)

type Device struct {
	ID          string
	DisplayName string
	Platform    string
	CreatedAt   time.Time
	RevokedAt   *time.Time
	Current     bool
}

type repository interface {
	List(ctx context.Context, accountID string) ([]Device, error)
}

type revoker interface {
	RevokeDevice(ctx context.Context, accountID string, deviceID string) error
}

type Service struct {
	repository repository
	revoker    revoker
}

func NewService(repository repository, revoker revoker) (*Service, error) {
	if repository == nil || revoker == nil {
		return nil, fmt.Errorf("device service dependencies are required")
	}
	return &Service{repository: repository, revoker: revoker}, nil
}

func (service *Service) List(
	ctx context.Context,
	accountID string,
	currentDeviceID string,
) ([]Device, error) {
	devices, err := service.repository.List(ctx, accountID)
	if err != nil {
		return nil, err
	}
	for index := range devices {
		devices[index].Current = devices[index].ID == currentDeviceID
	}
	return devices, nil
}

func (service *Service) Revoke(ctx context.Context, accountID string, deviceID string) error {
	return service.revoker.RevokeDevice(ctx, accountID, deviceID)
}
