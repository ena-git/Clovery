package httpapi

import (
	"errors"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
	"github.com/go-chi/chi/v5"
)

type bootstrapHandler struct {
	application BootstrapHTTPApplication
}

func registerBootstrapRoutes(
	router chi.Router,
	application BootstrapHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := bootstrapHandler{application: application}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Get("/v1/account/bootstrap", handler.get)
		protected.Post("/v1/account/bootstrap/resume", handler.resume)
	})
}

func (handler bootstrapHandler) get(responseWriter http.ResponseWriter, request *http.Request) {
	accountID, ok := AccountIDFromContext(request.Context())
	if !ok {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	snapshot, err := handler.application.GetBootstrap(request.Context(), accountID)
	if err != nil {
		writeBootstrapGetError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, snapshot)
}

func (handler bootstrapHandler) resume(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	if !ok || claims.AccountID == "" || claims.VaultID == "" {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	var resumeRequest bootstrapResumeRequest
	if err := decodeJSON(responseWriter, request, &resumeRequest); err != nil ||
		!bootstrapjob.SourceKind(resumeRequest.SourceKind).Valid() {
		writeAPIError(
			responseWriter,
			http.StatusBadRequest,
			"invalid_bootstrap_request",
			"The bootstrap request is invalid.",
		)
		return
	}
	snapshot, err := handler.application.ResumeBootstrap(
		request.Context(), claims.AccountID, claims.VaultID, resumeRequest.SourceKind,
	)
	if err != nil {
		writeBootstrapResumeError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, snapshot)
}

func writeBootstrapGetError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, bootstrapjob.ErrNotFound):
		writeAPIError(responseWriter, http.StatusNotFound, "bootstrap_not_found", "Bootstrap state was not found.")
	case errors.Is(err, bootstrapjob.ErrInvalidRequest):
		writeAPIError(
			responseWriter,
			http.StatusBadRequest,
			"invalid_bootstrap_request",
			"The bootstrap request is invalid.",
		)
	default:
		writeAPIError(responseWriter, http.StatusInternalServerError, "internal_error", "The service could not complete the request.")
	}
}

func writeBootstrapResumeError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, bootstrapjob.ErrInvalidRequest):
		writeAPIError(
			responseWriter,
			http.StatusBadRequest,
			"invalid_bootstrap_request",
			"The bootstrap request is invalid.",
		)
	case errors.Is(err, bootstrapjob.ErrConflict),
		errors.Is(err, bootstrapjob.ErrInvalidTransition),
		errors.Is(err, bootstrapjob.ErrNotFound):
		writeAPIError(responseWriter, http.StatusConflict, "bootstrap_conflict", "Bootstrap state could not be resumed.")
	default:
		writeAPIError(responseWriter, http.StatusInternalServerError, "internal_error", "The service could not complete the request.")
	}
}
