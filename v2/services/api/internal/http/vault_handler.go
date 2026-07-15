package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type vaultHandler struct {
	application VaultHTTPApplication
}

func registerVaultRoutes(
	router chi.Router,
	application VaultHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := vaultHandler{application: application}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Get("/v1/vault", handler.get)
	})
}

func (handler vaultHandler) get(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	if !ok {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	metadata, err := handler.application.GetVault(request.Context(), claims.AccountID, claims.VaultID)
	if err != nil {
		writeManagementError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, metadata)
}
