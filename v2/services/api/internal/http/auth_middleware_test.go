package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestAuthenticationMiddlewareInjectsRootAccountAndVault(t *testing.T) {
	sessions := &fakeHTTPSessionService{
		claims: auth.AccessClaims{
			AccountID: "11111111-1111-4111-8111-111111111111",
			VaultID:   "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
			SessionID: "22222222-2222-4222-8222-222222222222",
			DeviceID:  "33333333-3333-4333-8333-333333333333",
		},
	}
	handler := RequireAuthentication(sessions)(http.HandlerFunc(func(responseWriter http.ResponseWriter, request *http.Request) {
		accountID, accountOK := AccountIDFromContext(request.Context())
		vaultID, vaultOK := VaultIDFromContext(request.Context())
		if !accountOK || !vaultOK {
			t.Fatal("authentication context is missing")
		}
		writeJSON(responseWriter, http.StatusOK, map[string]string{"account_id": accountID, "vault_id": vaultID})
	}))
	request := httptest.NewRequest(http.MethodGet, "/protected", nil)
	request.Header.Set("Authorization", "Bearer access-token")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestAuthenticationMiddlewareRejectsInvalidBearerToken(t *testing.T) {
	sessions := &fakeHTTPSessionService{authenticateErr: auth.ErrInvalidSession}
	handler := RequireAuthentication(sessions)(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("protected handler was called")
	}))
	request := httptest.NewRequest(http.MethodGet, "/protected", nil)
	request.Header.Set("Authorization", "Bearer invalid")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

type fakeHTTPSessionService struct {
	claims          auth.AccessClaims
	authenticateErr error
	refreshTokens   auth.SessionTokens
	refreshErr      error
}

func (service *fakeHTTPSessionService) Authenticate(context.Context, string) (auth.AccessClaims, error) {
	return service.claims, service.authenticateErr
}

func (service *fakeHTTPSessionService) Refresh(context.Context, string) (auth.SessionTokens, error) {
	return service.refreshTokens, service.refreshErr
}
