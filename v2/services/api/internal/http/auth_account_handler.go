package httpapi

import (
	"net/http"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/google/uuid"
)

func (handler authHandler) createAccount(responseWriter http.ResponseWriter, request *http.Request) {
	var command CreateAccountCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if !validCreateAccountShape(command) {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_auth_request", "The request is invalid.")
		return
	}
	if err := auth.ValidatePassword(command.Password); err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	session, err := handler.application.Register(request.Context(), command)
	if err != nil {
		writeAuthError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusCreated, session)
}

func validCreateAccountShape(command CreateAccountCommand) bool {
	claimFieldCount := 0
	for _, field := range []*string{
		command.IdentityClaimToken,
		command.RegistrationRequestID,
		command.SourceKind,
	} {
		if field != nil {
			claimFieldCount++
		}
	}
	if claimFieldCount == 0 {
		return command.RecoveryMethod != "bound_identity"
	}
	if claimFieldCount != 3 || command.RecoveryMethod != "bound_identity" ||
		*command.IdentityClaimToken == "" || !validRegistrationSourceKind(*command.SourceKind) {
		return false
	}
	requestID, err := uuid.Parse(*command.RegistrationRequestID)
	return err == nil && requestID != uuid.Nil
}

func validRegistrationSourceKind(sourceKind string) bool {
	switch sourceKind {
	case "new_install", "legacy_local", "legacy_cloudkit":
		return true
	default:
		return false
	}
}
