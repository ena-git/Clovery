package httpapi

import "net/http"

func (handler authHandler) createAccount(responseWriter http.ResponseWriter, request *http.Request) {
	var command CreateAccountCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	session, err := handler.application.Register(request.Context(), command)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, session)
}
