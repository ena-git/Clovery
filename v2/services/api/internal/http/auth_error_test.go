package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestWriteAuthErrorMapsIdentityFailures(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		statusCode int
		code       string
	}{
		{"unsupported provider", auth.ErrUnsupportedIdentityProvider, http.StatusBadRequest, "identity_provider_unsupported"},
		{"disabled provider", auth.ErrIdentityProviderDisabled, http.StatusServiceUnavailable, "identity_provider_unavailable"},
		{"identity not bound", auth.ErrFederatedIdentityNotBound, http.StatusConflict, "identity_not_bound"},
		{"identity already bound", auth.ErrFederatedIdentityAlreadyBound, http.StatusConflict, "identity_already_bound"},
		{"federated authentication", auth.ErrFederatedAuthentication, http.StatusUnauthorized, "authentication_failed"},
		{"passkey authentication", auth.ErrPasskeyAuthentication, http.StatusUnauthorized, "authentication_failed"},
		{"recent authentication", auth.ErrRecentAuthenticationRequired, http.StatusUnauthorized, "recent_authentication_required"},
		{"last recovery credential", auth.ErrLastRecoveryCredential, http.StatusConflict, "last_recovery_credential"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			response := httptest.NewRecorder()
			writeAuthError(response, errors.Join(errors.New("wrapped"), test.err))

			if response.Code != test.statusCode {
				t.Fatalf("status = %d, want %d", response.Code, test.statusCode)
			}
			var body map[string]string
			if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			if body["code"] != test.code {
				t.Fatalf("code = %q, want %q", body["code"], test.code)
			}
		})
	}
}
