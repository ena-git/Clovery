package httpapi

import (
	"errors"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/billing"
)

func writeBillingError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, billing.ErrInvalidRequest):
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_billing_request", "The billing request is invalid.")
	case errors.Is(err, billing.ErrAccountMismatch):
		writeAPIError(responseWriter, http.StatusForbidden, "apple_transaction_account_mismatch", "The transaction belongs to another Clovery account.")
	case errors.Is(err, billing.ErrTransactionClaimed):
		writeAPIError(responseWriter, http.StatusConflict, "apple_transaction_claimed", "The transaction is already claimed.")
	case errors.Is(err, billing.ErrVerificationFailed):
		writeAPIError(responseWriter, http.StatusUnprocessableEntity, "apple_transaction_invalid", "Apple could not verify the transaction.")
	case errors.Is(err, billing.ErrVerificationUnavailable):
		writeAPIError(responseWriter, http.StatusServiceUnavailable, "apple_verification_unavailable", "Apple verification is temporarily unavailable.")
	default:
		writeManagementError(responseWriter, err)
	}
}
