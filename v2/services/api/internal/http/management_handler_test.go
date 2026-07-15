package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func TestAccountAndVaultRoutesUseAuthenticatedClaimsOnly(t *testing.T) {
	accountApplication := &stubAccountHTTPApplication{account: AccountSummary{CloveryID: "clovery_user"}}
	vaultApplication := &stubVaultHTTPApplication{vault: VaultSummary{ID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}}
	sessions := managementSessions()
	router := NewRouter(RouterDependencies{
		Sessions: sessions,
		Account:  accountApplication,
		Vault:    vaultApplication,
	})

	for _, path := range []string{"/v1/account", "/v1/vault"} {
		request := httptest.NewRequest(http.MethodGet, path, nil)
		request.Header.Set("Authorization", "Bearer access-token")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != http.StatusOK {
			t.Fatalf("%s status = %d, body = %s", path, response.Code, response.Body.String())
		}
	}
	if accountApplication.accountID != sessions.claims.AccountID {
		t.Fatalf("account ID = %q", accountApplication.accountID)
	}
	if vaultApplication.accountID != sessions.claims.AccountID || vaultApplication.vaultID != sessions.claims.VaultID {
		t.Fatalf("vault account = %q, vault = %q", vaultApplication.accountID, vaultApplication.vaultID)
	}
}

func TestDeviceRoutesScopeOperationsToAuthenticatedAccount(t *testing.T) {
	devices := &stubDeviceHTTPApplication{devices: []DeviceSummary{{ID: "device"}}}
	sessions := managementSessions()
	router := NewRouter(RouterDependencies{Sessions: sessions, Devices: devices})

	listRequest := httptest.NewRequest(http.MethodGet, "/v1/account/devices", nil)
	listRequest.Header.Set("Authorization", "Bearer access-token")
	listResponse := httptest.NewRecorder()
	router.ServeHTTP(listResponse, listRequest)
	if listResponse.Code != http.StatusOK {
		t.Fatalf("list status = %d, body = %s", listResponse.Code, listResponse.Body.String())
	}

	revokeRequest := httptest.NewRequest(http.MethodDelete, "/v1/account/devices/device", nil)
	revokeRequest.Header.Set("Authorization", "Bearer access-token")
	revokeResponse := httptest.NewRecorder()
	router.ServeHTTP(revokeResponse, revokeRequest)
	if revokeResponse.Code != http.StatusNoContent {
		t.Fatalf("revoke status = %d, body = %s", revokeResponse.Code, revokeResponse.Body.String())
	}
	if devices.accountID != sessions.claims.AccountID || devices.currentDeviceID != sessions.claims.DeviceID {
		t.Fatalf("device scope account = %q, current = %q", devices.accountID, devices.currentDeviceID)
	}
}

func TestVaultRouteReturnsForbiddenWithoutLeakingMetadata(t *testing.T) {
	application := &stubVaultHTTPApplication{err: vault.ErrForbidden}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Vault: application})
	request := httptest.NewRequest(http.MethodGet, "/v1/vault", nil)
	request.Header.Set("Authorization", "Bearer access-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden || !strings.Contains(response.Body.String(), `"vault_access_denied"`) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if strings.Contains(response.Body.String(), "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") {
		t.Fatalf("response leaked vault metadata: %s", response.Body.String())
	}
}

func TestDeletionRequestReturnsAcceptedSchedule(t *testing.T) {
	application := &stubAccountHTTPApplication{deletion: DeletionRequestSummary{
		ID:           "request",
		Status:       "pending",
		ScheduledFor: time.Date(2026, time.August, 13, 16, 0, 0, 0, time.UTC),
	}}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Account: application})
	request := httptest.NewRequest(http.MethodPost, "/v1/account/deletion-requests", nil)
	request.Header.Set("Authorization", "Bearer access-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusAccepted || !strings.Contains(response.Body.String(), `"pending"`) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func managementSessions() *fakeHTTPSessionService {
	return &fakeHTTPSessionService{claims: auth.AccessClaims{
		AccountID: "11111111-1111-4111-8111-111111111111",
		VaultID:   "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		DeviceID:  "22222222-2222-4222-8222-222222222222",
	}}
}

type stubAccountHTTPApplication struct {
	accountID string
	account   AccountSummary
	deletion  DeletionRequestSummary
}

func (stub *stubAccountHTTPApplication) GetAccount(_ context.Context, accountID string) (AccountSummary, error) {
	stub.accountID = accountID
	return stub.account, nil
}

func (stub *stubAccountHTTPApplication) RequestDeletion(
	_ context.Context,
	accountID string,
) (DeletionRequestSummary, error) {
	stub.accountID = accountID
	return stub.deletion, nil
}

type stubDeviceHTTPApplication struct {
	accountID       string
	currentDeviceID string
	devices         []DeviceSummary
}

func (stub *stubDeviceHTTPApplication) ListDevices(
	_ context.Context,
	accountID string,
	currentDeviceID string,
) ([]DeviceSummary, error) {
	stub.accountID = accountID
	stub.currentDeviceID = currentDeviceID
	return stub.devices, nil
}

func (stub *stubDeviceHTTPApplication) RevokeDevice(
	_ context.Context,
	accountID string,
	_ string,
) error {
	stub.accountID = accountID
	return nil
}

type stubVaultHTTPApplication struct {
	accountID string
	vaultID   string
	vault     VaultSummary
	err       error
}

func (stub *stubVaultHTTPApplication) GetVault(
	_ context.Context,
	accountID string,
	vaultID string,
) (VaultSummary, error) {
	stub.accountID = accountID
	stub.vaultID = vaultID
	return stub.vault, stub.err
}
