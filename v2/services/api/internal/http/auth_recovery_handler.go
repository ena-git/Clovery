package httpapi

import "net/http"

type recentReauthenticationRequest struct {
	Proof string `json:"reauthentication_proof"`
}

func (handler authHandler) replaceRecoveryCodes(responseWriter http.ResponseWriter, request *http.Request) {
	accountID, authenticated := AccountIDFromContext(request.Context())
	if !authenticated {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	var reauthentication recentReauthenticationRequest
	if err := decodeJSON(responseWriter, request, &reauthentication); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	codes, err := handler.application.ReplaceRecoveryCodes(request.Context(), accountID, reauthentication.Proof)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, map[string]any{"codes": codes})
}

func (handler authHandler) consumeRecoveryCode(responseWriter http.ResponseWriter, request *http.Request) {
	var command RecoveryCodeConsumeCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	proof, err := handler.application.ConsumeRecoveryCode(request.Context(), command)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, proof)
}
