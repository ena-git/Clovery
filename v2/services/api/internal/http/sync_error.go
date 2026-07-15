package httpapi

import (
	"errors"
	"net/http"

	cloverysync "github.com/clovery/clovery/services/api/internal/sync"
)

func writeSyncError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, cloverysync.ErrInvalidOperation):
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_sync_operation", "The sync operation is invalid.")
	case errors.Is(err, cloverysync.ErrOperationReplayMismatch):
		writeAPIError(responseWriter, http.StatusConflict, "operation_replay_mismatch", "The operation ID was already used.")
	default:
		writeManagementError(responseWriter, err)
	}
}
