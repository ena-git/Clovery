package httpapi

import (
	"errors"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/account"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func writeManagementError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, vault.ErrForbidden):
		writeAPIError(responseWriter, http.StatusForbidden, "vault_access_denied", "Vault access is denied.")
	case errors.Is(err, auth.ErrDeviceNotFound):
		writeAPIError(responseWriter, http.StatusNotFound, "device_not_found", "The device was not found.")
	case errors.Is(err, account.ErrAccountNotFound):
		writeAPIError(responseWriter, http.StatusNotFound, "account_not_found", "The account was not found.")
	case errors.Is(err, account.ErrAccountUnavailable):
		writeAPIError(responseWriter, http.StatusConflict, "account_unavailable", "The account is unavailable.")
	default:
		writeAPIError(responseWriter, http.StatusInternalServerError, "internal_error", "The service could not complete the request.")
	}
}
