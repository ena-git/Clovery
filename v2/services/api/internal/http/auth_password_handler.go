package httpapi

import "net/http"

func (handler authHandler) passwordLogin(responseWriter http.ResponseWriter, request *http.Request) {
	var command PasswordLoginCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	session, err := handler.application.Login(request.Context(), command)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, session)
}

func (handler authHandler) startPasswordReset(responseWriter http.ResponseWriter, request *http.Request) {
	var command PasswordResetStartCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	result, err := handler.application.StartPasswordReset(request.Context(), command)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusAccepted, result)
}

func (handler authHandler) completePasswordReset(responseWriter http.ResponseWriter, request *http.Request) {
	var command PasswordResetCompleteCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.CompletePasswordReset(request.Context(), command); err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}
