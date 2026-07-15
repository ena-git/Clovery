package httpapi

import (
	"net/http"
	"strings"

	"github.com/clovery/clovery/services/api/internal/asset"
	"github.com/go-chi/chi/v5"
)

type assetHandler struct {
	application AssetHTTPApplication
}

func registerAssetRoutes(
	router chi.Router,
	application AssetHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := assetHandler{application: application}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Post("/v1/vault/assets/uploads", handler.startUpload)
		protected.Post("/v1/vault/assets/{assetId}/complete", handler.complete)
		protected.Get("/v1/vault/assets/{assetId}/download", handler.download)
	})
}

func (handler assetHandler) startUpload(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	var payload asset.UploadRequest
	if !ok || decodeJSON(responseWriter, request, &payload) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	ticket, err := handler.application.StartUpload(
		request.Context(), claims.AccountID, claims.VaultID, payload,
	)
	if err != nil {
		writeAssetError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, ticket)
}

func (handler assetHandler) complete(responseWriter http.ResponseWriter, request *http.Request) {
	claims, assetID, ok := assetRequestScope(request)
	if !ok {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.Complete(
		request.Context(), claims.AccountID, claims.VaultID, assetID,
	); err != nil {
		writeAssetError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}

func (handler assetHandler) download(responseWriter http.ResponseWriter, request *http.Request) {
	claims, assetID, ok := assetRequestScope(request)
	if !ok {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	ticket, err := handler.application.Download(
		request.Context(), claims.AccountID, claims.VaultID, assetID,
	)
	if err != nil {
		writeAssetError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, ticket)
}

func assetRequestScope(request *http.Request) (claims accessClaims, assetID string, ok bool) {
	authClaims, found := authClaimsFromContext(request.Context())
	assetID = strings.TrimSpace(chi.URLParam(request, "assetId"))
	return accessClaims{AccountID: authClaims.AccountID, VaultID: authClaims.VaultID},
		assetID,
		found && assetID != ""
}

type accessClaims struct {
	AccountID string
	VaultID   string
}
