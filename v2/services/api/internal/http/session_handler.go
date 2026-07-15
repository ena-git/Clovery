package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type sessionHandler struct {
	sessions HTTPSessionService
}

func registerSessionRoutes(router chi.Router, sessions HTTPSessionService) {
	handler := sessionHandler{sessions: sessions}
	router.Post("/v1/auth/sessions/refresh", handler.refresh)
}

func (handler sessionHandler) refresh(responseWriter http.ResponseWriter, request *http.Request) {
	var payload refreshSessionRequest
	if err := decodeJSON(responseWriter, request, &payload); err != nil || payload.RefreshToken == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	tokens, err := handler.sessions.Refresh(request.Context(), payload.RefreshToken)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, authSessionFromTokens(tokens))
}
