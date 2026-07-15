package httpapi

import (
	"context"
	"testing"

	"github.com/clovery/clovery/services/api/internal/account"
	"github.com/clovery/clovery/services/api/internal/device"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func TestAccountApplicationMapsProfileAndDeletionRequest(t *testing.T) {
	profiles := &stubProfileReader{profile: account.Profile{
		AccountID: "account",
		CloveryID: "clovery_user",
		Bindings:  []account.Binding{{Provider: "apple"}},
	}}
	deletions := &stubDeletionRequester{request: account.DeletionRequest{ID: "request", Status: "pending"}}
	application := NewAccountApplication(profiles, deletions)

	summary, err := application.GetAccount(context.Background(), "account")
	if err != nil {
		t.Fatalf("GetAccount() error = %v", err)
	}
	deletion, err := application.RequestDeletion(context.Background(), "account")
	if err != nil {
		t.Fatalf("RequestDeletion() error = %v", err)
	}
	if summary.CloveryID != "clovery_user" || summary.Bindings[0].Provider != "apple" || deletion.ID != "request" {
		t.Fatalf("summary = %#v, deletion = %#v", summary, deletion)
	}
}

func TestDeviceAndVaultApplicationsMapDomainResults(t *testing.T) {
	devices := &stubDeviceService{devices: []device.Device{{ID: "device", Current: true}}}
	vaults := &stubVaultService{metadata: vault.Metadata{ID: "vault", Status: "active"}}
	deviceApplication := NewDeviceApplication(devices)
	vaultApplication := NewVaultApplication(vaults)

	listed, err := deviceApplication.ListDevices(context.Background(), "account", "device")
	if err != nil {
		t.Fatalf("ListDevices() error = %v", err)
	}
	metadata, err := vaultApplication.GetVault(context.Background(), "account", "vault")
	if err != nil {
		t.Fatalf("GetVault() error = %v", err)
	}
	if !listed[0].Current || metadata.Status != "active" {
		t.Fatalf("devices = %#v, vault = %#v", listed, metadata)
	}
}

type stubProfileReader struct {
	profile account.Profile
}

func (stub *stubProfileReader) GetProfile(context.Context, string) (account.Profile, error) {
	return stub.profile, nil
}

type stubDeletionRequester struct {
	request account.DeletionRequest
}

func (stub *stubDeletionRequester) Request(context.Context, string) (account.DeletionRequest, error) {
	return stub.request, nil
}

type stubDeviceService struct {
	devices []device.Device
}

func (stub *stubDeviceService) List(context.Context, string, string) ([]device.Device, error) {
	return stub.devices, nil
}

func (*stubDeviceService) Revoke(context.Context, string, string) error {
	return nil
}

type stubVaultService struct {
	metadata vault.Metadata
}

func (stub *stubVaultService) Get(context.Context, string, string) (vault.Metadata, error) {
	return stub.metadata, nil
}
