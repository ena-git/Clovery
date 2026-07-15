package httpapi

import (
	"context"
	"time"
)

type DeviceSummary struct {
	ID          string     `json:"device_id"`
	DisplayName string     `json:"display_name"`
	Platform    string     `json:"platform"`
	CreatedAt   time.Time  `json:"created_at"`
	RevokedAt   *time.Time `json:"revoked_at,omitempty"`
	Current     bool       `json:"current"`
}

type DeviceHTTPApplication interface {
	ListDevices(ctx context.Context, accountID string, currentDeviceID string) ([]DeviceSummary, error)
	RevokeDevice(ctx context.Context, accountID string, deviceID string) error
}
