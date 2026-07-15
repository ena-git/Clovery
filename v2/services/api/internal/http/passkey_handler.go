package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type passkeyHandler struct {
	application PasskeyHTTPApplication
}

func registerPasskeyRoutes(
	router chi.Router,
	application PasskeyHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := passkeyHandler{application: application}
	router.Post("/v1/auth/passkeys/login/start", handler.beginLogin)
	router.Post("/v1/auth/passkeys/login/complete", handler.completeLogin)
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Post("/v1/account/passkeys/registration/start", handler.beginRegistration)
		protected.Post("/v1/account/passkeys/registration/complete", handler.completeRegistration)
	})
}

func (handler passkeyHandler) completeRegistration(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	var payload passkeyRegistrationCompleteRequest
	if err := decodeJSON(responseWriter, request, &payload); err != nil ||
		payload.ChallengeID == "" || len(payload.Response) == 0 {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.CompleteRegistration(
		request.Context(),
		PasskeyRegistrationHTTPCommand{
			AccessToken:    bearerToken(request),
			ChallengeID:    payload.ChallengeID,
			Response:       payload.Response,
			DeviceMetadata: payload.DeviceMetadata,
		},
	); err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}

func (handler passkeyHandler) completeLogin(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	var payload passkeyLoginCompleteRequest
	if err := decodeJSON(responseWriter, request, &payload); err != nil ||
		payload.ChallengeID == "" || len(payload.Response) == 0 {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	session, err := handler.application.CompleteLogin(request.Context(), PasskeyLoginHTTPCommand{
		ChallengeID: payload.ChallengeID,
		Response:    payload.Response,
		Device:      payload.Device,
	})
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, session)
}

func (handler passkeyHandler) beginLogin(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	ceremony, err := handler.application.BeginLogin(request.Context())
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, passkeyCeremonyResponse{
		ChallengeID: ceremony.ChallengeID,
		Options:     ceremony.Options,
		ExpiresIn:   expiresInSeconds(ceremony.ExpiresAt),
	})
}

func (handler passkeyHandler) beginRegistration(
	responseWriter http.ResponseWriter,
	request *http.Request,
) {
	ceremony, err := handler.application.BeginRegistration(request.Context(), bearerToken(request))
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, passkeyCeremonyResponse{
		ChallengeID: ceremony.ChallengeID,
		Options:     ceremony.Options,
		ExpiresIn:   expiresInSeconds(ceremony.ExpiresAt),
	})
}
