package httpapi

import (
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

type federationHandler struct {
	application FederatedHTTPApplication
}

func registerFederationRoutes(
	router chi.Router,
	application FederatedHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := federationHandler{application: application}
	router.Post("/v1/auth/federated/{provider}/start", handler.startFederatedLogin)
	router.Post("/v1/auth/federated/{provider}/complete", handler.completeFederatedLogin)
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Post("/v1/account/bindings/start", handler.startBinding)
		protected.Post("/v1/account/bindings/complete", handler.completeBinding)
		protected.Delete("/v1/account/bindings/{provider}", handler.unbind)
	})
}

func (handler federationHandler) unbind(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	provider := strings.TrimSpace(chi.URLParam(request, "provider"))
	if provider == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.Unbind(request.Context(), bearerToken(request), provider); err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}

func (handler federationHandler) completeBinding(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	var payload bindingCompleteRequest
	if err := decodeJSON(responseWriter, request, &payload); err != nil ||
		strings.TrimSpace(payload.IntentID) == "" || strings.TrimSpace(payload.Provider) == "" ||
		strings.TrimSpace(payload.Nonce) == "" || strings.TrimSpace(payload.AuthorizationCode) == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.CompleteBinding(
		request.Context(),
		FederatedBindingHTTPCommand{
			AccessToken:       bearerToken(request),
			IntentID:          payload.IntentID,
			Provider:          payload.Provider,
			AuthorizationCode: payload.AuthorizationCode,
			Nonce:             payload.Nonce,
		},
	); err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}

func (handler federationHandler) completeFederatedLogin(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	provider := strings.TrimSpace(chi.URLParam(request, "provider"))
	var payload federatedLoginCompleteRequest
	if err := decodeJSON(responseWriter, request, &payload); err != nil ||
		provider == "" || strings.TrimSpace(payload.IntentID) == "" ||
		strings.TrimSpace(payload.Nonce) == "" || strings.TrimSpace(payload.AuthorizationCode) == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	session, err := handler.application.CompleteFederatedLogin(
		request.Context(),
		FederatedLoginHTTPCommand{
			IntentID:          payload.IntentID,
			Provider:          provider,
			AuthorizationCode: payload.AuthorizationCode,
			Nonce:             payload.Nonce,
			Device:            payload.Device,
		},
	)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, session)
}

func (handler federationHandler) startFederatedLogin(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	provider := strings.TrimSpace(chi.URLParam(request, "provider"))
	if provider == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	intent, err := handler.application.StartFederatedLogin(request.Context(), provider)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, federationIntentResponse{
		IntentID:  intent.ID,
		Provider:  intent.Provider,
		Nonce:     intent.Nonce,
		ExpiresIn: expiresInSeconds(intent.ExpiresAt),
	})
}

func (handler federationHandler) startBinding(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	var payload bindingStartRequest
	if err := decodeJSON(responseWriter, request, &payload); err != nil || strings.TrimSpace(payload.Provider) == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	accessToken := bearerToken(request)
	intent, err := handler.application.StartBinding(request.Context(), accessToken, payload.Provider)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, federationIntentResponse{
		IntentID:  intent.ID,
		Provider:  intent.Provider,
		Nonce:     intent.Nonce,
		ExpiresIn: expiresInSeconds(intent.ExpiresAt),
	})
}

func bearerToken(request *http.Request) string {
	return strings.TrimSpace(strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer "))
}

func expiresInSeconds(expiresAt time.Time) int {
	seconds := int(time.Until(expiresAt).Seconds())
	if seconds < 1 {
		return 1
	}
	return seconds
}
