package httpapi

import (
	"errors"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
	"github.com/google/uuid"
)

func (handler authHandler) createAccount(responseWriter http.ResponseWriter, request *http.Request) {
	var command CreateAccountCommand
	if err := decodeJSON(responseWriter, request, &command); err != nil {
		if errors.Is(err, identityclaim.ErrInvalidClaim) {
			writeAPIError(responseWriter, http.StatusBadRequest, "invalid_auth_request", "The request is invalid.")
			return
		}
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
	if command.IdentityClaimToken != nil {
		claimFieldCount++
	}
	if command.RegistrationRequestID != nil {
		claimFieldCount++
	}
	if command.SourceKind != nil {
		claimFieldCount++
	}
	if claimFieldCount == 0 {
		return command.RecoveryMethod != "bound_identity"
	}
	if claimFieldCount != 3 || command.RecoveryMethod != "bound_identity" ||
		!command.IdentityClaimToken.Valid() || !validRegistrationSourceKind(*command.SourceKind) {
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
