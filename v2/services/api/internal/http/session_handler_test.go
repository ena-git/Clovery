package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestRefreshSessionReturnsRotatedTokens(t *testing.T) {
	sessions := &fakeHTTPSessionService{refreshTokens: auth.SessionTokens{
		SessionID:            "11111111-1111-4111-8111-111111111111",
		AccountID:            "22222222-2222-4222-8222-222222222222",
		VaultID:              "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		AccessToken:          "new-access",
		AccessTokenExpiresIn: 900,
		RefreshToken:         "new-refresh",
	}}
	router := NewRouter(RouterDependencies{Sessions: sessions})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/sessions/refresh",
		strings.NewReader(`{"refresh_token":"old-refresh"}`),
	)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"refresh_token":"new-refresh"`) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}
