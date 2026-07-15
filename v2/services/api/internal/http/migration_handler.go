package httpapi

import (
	"net/http"
	"strings"

	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
	"github.com/go-chi/chi/v5"
)

type migrationHandler struct {
	application   MigrationHTTPApplication
	writesEnabled bool
}

func registerMigrationRoutes(
	router chi.Router,
	application MigrationHTTPApplication,
	sessions HTTPSessionService,
	writesEnabled bool,
) {
	handler := migrationHandler{application: application, writesEnabled: writesEnabled}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Post("/v1/vault/migrations", handler.create)
		protected.Post("/v1/vault/migrations/{migrationId}/entries", handler.addEntry)
		protected.Post("/v1/vault/migrations/{migrationId}/assets", handler.addAsset)
		protected.Post("/v1/vault/migrations/{migrationId}/verify", handler.verify)
		protected.Get("/v1/vault/migrations/{migrationId}/report", handler.report)
	})
}

func (handler migrationHandler) create(responseWriter http.ResponseWriter, request *http.Request) {
	if !handler.allowWrite(responseWriter) {
		return
	}
	claims, ok := authClaimsFromContext(request.Context())
	var payload cloverymigration.CreateRequest
	if !ok || decodeJSONWithLimit(
		responseWriter, request, &payload, maximumMigrationCreateRequestBytes,
	) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	created, err := handler.application.Create(request.Context(), claims.AccountID, claims.VaultID, payload)
	if err != nil {
		writeMigrationError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, created)
}

func (handler migrationHandler) addEntry(responseWriter http.ResponseWriter, request *http.Request) {
	if !handler.allowWrite(responseWriter) {
		return
	}
	claims, migrationID, ok := migrationRequestScope(request)
	var payload cloverymigration.EntryInput
	if !ok || decodeJSONWithLimit(
		responseWriter, request, &payload, maximumMigrationEntryRequestBytes,
	) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.AddEntry(
		request.Context(), claims.AccountID, claims.VaultID, migrationID, payload,
	); err != nil {
		writeMigrationError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}

func (handler migrationHandler) addAsset(responseWriter http.ResponseWriter, request *http.Request) {
	if !handler.allowWrite(responseWriter) {
		return
	}
	claims, migrationID, ok := migrationRequestScope(request)
	var payload cloverymigration.AssetInput
	if !ok || decodeJSON(responseWriter, request, &payload) != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	ticket, err := handler.application.AddAsset(
		request.Context(), claims.AccountID, claims.VaultID, migrationID, payload,
	)
	if err != nil {
		writeMigrationError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, ticket)
}

func (handler migrationHandler) verify(responseWriter http.ResponseWriter, request *http.Request) {
	if !handler.allowWrite(responseWriter) {
		return
	}
	claims, migrationID, ok := migrationRequestScope(request)
	if !ok {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	report, err := handler.application.Verify(request.Context(), claims.AccountID, claims.VaultID, migrationID)
	if err != nil {
		writeMigrationError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, report)
}

func (handler migrationHandler) allowWrite(responseWriter http.ResponseWriter) bool {
	if handler.writesEnabled {
		return true
	}
	writeAPIError(
		responseWriter, http.StatusServiceUnavailable,
		"migration_disabled", "Migration writes are temporarily disabled.",
	)
	return false
}

func (handler migrationHandler) report(responseWriter http.ResponseWriter, request *http.Request) {
	claims, migrationID, ok := migrationRequestScope(request)
	if !ok {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	report, err := handler.application.Report(request.Context(), claims.AccountID, claims.VaultID, migrationID)
	if err != nil {
		writeMigrationError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, report)
}

func migrationRequestScope(request *http.Request) (accessClaims, string, bool) {
	claims, found := authClaimsFromContext(request.Context())
	migrationID := strings.TrimSpace(chi.URLParam(request, "migrationId"))
	return accessClaims{AccountID: claims.AccountID, VaultID: claims.VaultID}, migrationID, found && migrationID != ""
}
