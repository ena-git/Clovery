package httpapi

import (
	"errors"
	"net/http"

	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
)

func writeMigrationError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, cloverymigration.ErrUnsupportedFormat), errors.Is(err, cloverymigration.ErrInvalidBundle):
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_migration_bundle", "The migration bundle is invalid.")
	case errors.Is(err, cloverymigration.ErrIntegrityMismatch),
		errors.Is(err, cloverymigration.ErrVerificationFailed),
		errors.Is(err, cloverymigration.ErrResolutionRace):
		writeAPIError(responseWriter, http.StatusUnprocessableEntity, "migration_verification_failed", "The migration bundle failed verification.")
	case errors.Is(err, cloverymigration.ErrMigrationMismatch):
		writeAPIError(responseWriter, http.StatusConflict, "migration_conflict", "The migration conflicts with existing data.")
	case errors.Is(err, cloverymigration.ErrMigrationNotVerified):
		writeAPIError(responseWriter, http.StatusConflict, "migration_not_verified", "The migration is not verified.")
	case errors.Is(err, cloverymigration.ErrMigrationNotFound):
		writeAPIError(responseWriter, http.StatusNotFound, "migration_not_found", "The migration was not found.")
	default:
		writeAssetError(responseWriter, err)
	}
}
