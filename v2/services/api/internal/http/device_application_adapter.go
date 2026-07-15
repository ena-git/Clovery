package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/device"
)

type deviceService interface {
	List(ctx context.Context, accountID string, currentDeviceID string) ([]device.Device, error)
	Revoke(ctx context.Context, accountID string, deviceID string) error
}

type deviceApplicationAdapter struct {
	service deviceService
}

func NewDeviceApplication(service deviceService) DeviceHTTPApplication {
	return &deviceApplicationAdapter{service: service}
}

func (adapter *deviceApplicationAdapter) ListDevices(
	ctx context.Context,
	accountID string,
	currentDeviceID string,
) ([]DeviceSummary, error) {
	devices, err := adapter.service.List(ctx, accountID, currentDeviceID)
	if err != nil {
		return nil, err
	}
	summaries := make([]DeviceSummary, 0, len(devices))
	for _, listed := range devices {
		summaries = append(summaries, DeviceSummary{
			ID:          listed.ID,
			DisplayName: listed.DisplayName,
			Platform:    listed.Platform,
			CreatedAt:   listed.CreatedAt,
			RevokedAt:   listed.RevokedAt,
			Current:     listed.Current,
		})
	}
	return summaries, nil
}

func (adapter *deviceApplicationAdapter) RevokeDevice(
	ctx context.Context,
	accountID string,
	deviceID string,
) error {
	return adapter.service.Revoke(ctx, accountID, deviceID)
}
