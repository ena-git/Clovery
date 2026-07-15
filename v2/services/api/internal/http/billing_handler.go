package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type billingHandler struct {
	application BillingHTTPApplication
}

func registerBillingRoutes(
	router chi.Router,
	application BillingHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := billingHandler{application: application}
	router.Post("/v1/billing/apple/notifications", handler.notification)
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Post("/v1/billing/apple/transactions/verify", handler.verify)
		protected.Post("/v1/billing/apple/legacy-claims", handler.claimLegacy)
		protected.Post("/v1/billing/apple/restore", handler.restore)
		protected.Get("/v1/account/entitlements", handler.list)
	})
}

func (handler billingHandler) claimLegacy(responseWriter http.ResponseWriter, request *http.Request) {
	accountID, ok := AccountIDFromContext(request.Context())
	var payload appleLegacyClaimRequest
	if !ok || decodeJSONWithLimit(responseWriter, request, &payload, 1024*1024+1024) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_billing_request", "The billing request is invalid.")
		return
	}
	entitlement, err := handler.application.ClaimLegacy(
		request.Context(), accountID, payload.SignedTransactionInfo, payload.Environment,
	)
	if err != nil {
		writeBillingError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, entitlement)
}

func (handler billingHandler) notification(responseWriter http.ResponseWriter, request *http.Request) {
	var payload appleNotificationRequest
	if decodeJSONWithLimit(responseWriter, request, &payload, 1024*1024+1024) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_billing_request", "The billing request is invalid.")
		return
	}
	if err := handler.application.ProcessAppleNotification(request.Context(), payload.SignedPayload); err != nil {
		writeBillingError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}

func (handler billingHandler) verify(responseWriter http.ResponseWriter, request *http.Request) {
	accountID, ok := AccountIDFromContext(request.Context())
	var payload appleTransactionVerifyRequest
	if !ok || decodeJSON(responseWriter, request, &payload) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_billing_request", "The billing request is invalid.")
		return
	}
	entitlement, err := handler.application.Verify(
		request.Context(), accountID, payload.TransactionID, payload.Environment,
	)
	if err != nil {
		writeBillingError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, entitlement)
}

func (handler billingHandler) restore(responseWriter http.ResponseWriter, request *http.Request) {
	accountID, ok := AccountIDFromContext(request.Context())
	var payload appleRestoreRequest
	if !ok || decodeJSON(responseWriter, request, &payload) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_billing_request", "The billing request is invalid.")
		return
	}
	entitlements, err := handler.application.Restore(
		request.Context(), accountID, payload.TransactionIDs, payload.Environment,
	)
	if err != nil {
		writeBillingError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, entitlementListResponse{Entitlements: entitlements})
}

func (handler billingHandler) list(responseWriter http.ResponseWriter, request *http.Request) {
	accountID, ok := AccountIDFromContext(request.Context())
	if !ok {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	entitlements, err := handler.application.List(request.Context(), accountID)
	if err != nil {
		writeBillingError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, entitlementListResponse{Entitlements: entitlements})
}
