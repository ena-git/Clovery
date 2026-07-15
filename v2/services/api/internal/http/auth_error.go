package httpapi

import (
	"errors"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/account"
	"github.com/clovery/clovery/services/api/internal/application/authflow"
	"github.com/clovery/clovery/services/api/internal/auth"
)

func writeAuthError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidCredentials), errors.Is(err, auth.ErrInvalidRecoveryCode), errors.Is(err, auth.ErrInvalidSession):
		writeAPIError(responseWriter, http.StatusUnauthorized, "invalid_credentials", "Authentication failed.")
	case errors.Is(err, auth.ErrRateLimited):
		responseWriter.Header().Set("Retry-After", "900")
		writeAPIError(responseWriter, http.StatusTooManyRequests, "rate_limited", "Too many attempts. Try again later.")
	case errors.Is(err, auth.ErrWeakPassword), errors.Is(err, account.ErrInvalidLoginID):
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
	case errors.Is(err, authflow.ErrUnsupportedRecoveryMethod):
		writeAPIError(responseWriter, http.StatusBadRequest, "recovery_method_unavailable", "The recovery method is not available.")
	case errors.Is(err, authflow.ErrRecentAuthenticationRequired):
		writeAPIError(responseWriter, http.StatusUnauthorized, "recent_authentication_required", "Recent authentication is required.")
	case errors.Is(err, auth.ErrRecentAuthenticationRequired):
		writeAPIError(responseWriter, http.StatusUnauthorized, "recent_authentication_required", "Recent authentication is required.")
	case errors.Is(err, account.ErrLoginIDUnavailable):
		writeAPIError(responseWriter, http.StatusConflict, "login_id_unavailable", "The Clovery ID is unavailable.")
	case errors.Is(err, auth.ErrUnsupportedIdentityProvider):
		writeAPIError(responseWriter, http.StatusBadRequest, "identity_provider_unsupported", "The identity provider is not supported.")
	case errors.Is(err, auth.ErrIdentityProviderDisabled):
		writeAPIError(responseWriter, http.StatusServiceUnavailable, "identity_provider_unavailable", "The identity provider is unavailable.")
	case errors.Is(err, auth.ErrFederatedIdentityNotBound):
		writeAPIError(responseWriter, http.StatusConflict, "identity_not_bound", "This login method is not bound to a Clovery account.")
	case errors.Is(err, auth.ErrFederatedIdentityAlreadyBound):
		writeAPIError(responseWriter, http.StatusConflict, "identity_already_bound", "This login method is already bound.")
	case errors.Is(err, auth.ErrFederatedAuthentication), errors.Is(err, auth.ErrPasskeyAuthentication):
		writeAPIError(responseWriter, http.StatusUnauthorized, "authentication_failed", "Authentication failed.")
	case errors.Is(err, auth.ErrLastRecoveryCredential):
		writeAPIError(responseWriter, http.StatusConflict, "last_recovery_credential", "Add another recovery credential before removing this one.")
	default:
		writeAPIError(responseWriter, http.StatusInternalServerError, "internal_error", "The service could not complete the request.")
	}
}
