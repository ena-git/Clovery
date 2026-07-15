package httpapi

import (
	"context"

	cloverysync "github.com/clovery/clovery/services/api/internal/sync"
)

type SyncHTTPApplication interface {
	Push(
		ctx context.Context,
		accountID string,
		vaultID string,
		operations []cloverysync.Operation,
	) ([]cloverysync.Decision, error)
	Pull(
		ctx context.Context,
		accountID string,
		vaultID string,
		cursor int64,
		limit int,
	) (cloverysync.PullPage, error)
}

type syncPushRequest struct {
	Operations []cloverysync.Operation `json:"operations"`
}

type syncPushResponse struct {
	Results []cloverysync.Decision `json:"results"`
}
