package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type accountHandler struct {
	application AccountHTTPApplication
}

func registerAccountRoutes(
	router chi.Router,
	application AccountHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := accountHandler{application: application}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Get("/v1/account", handler.get)
		protected.Post("/v1/account/deletion-requests", handler.requestDeletion)
	})
}

func (handler accountHandler) get(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	if !ok {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	account, err := handler.application.GetAccount(request.Context(), claims.AccountID)
	if err != nil {
		writeManagementError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, account)
}

func (handler accountHandler) requestDeletion(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	if !ok {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	deletion, err := handler.application.RequestDeletion(request.Context(), claims.AccountID)
	if err != nil {
		writeManagementError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusAccepted, deletion)
}
