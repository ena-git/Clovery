package device

import (
	"context"
	"testing"
)

func TestListMarksOnlyTheCurrentSessionDevice(t *testing.T) {
	repository := &stubRepository{devices: []Device{{ID: "first"}, {ID: "second"}}}
	service, err := NewService(repository, &stubRevoker{})
	if err != nil {
		t.Fatalf("create device service: %v", err)
	}

	devices, err := service.List(context.Background(), "account", "second")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if devices[0].Current || !devices[1].Current {
		t.Fatalf("devices = %#v", devices)
	}
}

func TestRevokeScopesDeviceToAuthenticatedAccount(t *testing.T) {
	revoker := &stubRevoker{}
	service, err := NewService(&stubRepository{}, revoker)
	if err != nil {
		t.Fatalf("create device service: %v", err)
	}

	if err := service.Revoke(context.Background(), "account", "device"); err != nil {
		t.Fatalf("Revoke() error = %v", err)
	}
	if revoker.accountID != "account" || revoker.deviceID != "device" {
		t.Fatalf("revoke account = %q, device = %q", revoker.accountID, revoker.deviceID)
	}
}

type stubRepository struct {
	devices []Device
}

func (repository *stubRepository) List(context.Context, string) ([]Device, error) {
	return repository.devices, nil
}

type stubRevoker struct {
	accountID string
	deviceID  string
}

func (revoker *stubRevoker) RevokeDevice(
	_ context.Context,
	accountID string,
	deviceID string,
) error {
	revoker.accountID = accountID
	revoker.deviceID = deviceID
	return nil
}
