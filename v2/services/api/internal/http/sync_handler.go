package httpapi

import (
	"net/http"
	"strconv"

	"github.com/clovery/clovery/services/api/internal/observability"
	cloverysync "github.com/clovery/clovery/services/api/internal/sync"
	"github.com/go-chi/chi/v5"
)

type syncHandler struct {
	application SyncHTTPApplication
	metrics     *observability.Registry
}

func registerSyncRoutes(
	router chi.Router,
	application SyncHTTPApplication,
	sessions HTTPSessionService,
	metrics *observability.Registry,
) {
	handler := syncHandler{application: application, metrics: metrics}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Post("/v1/vault/sync/push", handler.push)
		protected.Get("/v1/vault/sync/pull", handler.pull)
	})
}

func (handler syncHandler) push(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	var payload syncPushRequest
	if !ok || decodeJSONWithLimit(
		responseWriter, request, &payload, maximumSyncPushRequestBytes,
	) != nil || len(payload.Operations) == 0 {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	handler.metrics.Adjust(observability.SyncBacklog, int64(len(payload.Operations)))
	defer handler.metrics.Adjust(observability.SyncBacklog, -int64(len(payload.Operations)))
	results, err := handler.application.Push(
		request.Context(), claims.AccountID, claims.VaultID, payload.Operations,
	)
	if err != nil {
		writeSyncError(responseWriter, err)
		return
	}
	var conflicts uint64
	for _, result := range results {
		if result.Status == cloverysync.StatusConflict {
			conflicts++
		}
	}
	handler.metrics.Add(observability.SyncConflicts, conflicts)
	writeJSON(responseWriter, http.StatusOK, syncPushResponse{Results: results})
}

func (handler syncHandler) pull(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	cursor, cursorErr := parseIntegerQuery(request, "cursor", 0)
	limit, limitErr := parseIntegerQuery(request, "limit", 100)
	if !ok || cursorErr != nil || limitErr != nil || cursor < 0 || limit < 1 {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	page, err := handler.application.Pull(
		request.Context(), claims.AccountID, claims.VaultID, cursor, int(limit),
	)
	if err != nil {
		writeSyncError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, page)
}

func parseIntegerQuery(request *http.Request, name string, fallback int64) (int64, error) {
	value := request.URL.Query().Get(name)
	if value == "" {
		return fallback, nil
	}
	return strconv.ParseInt(value, 10, 64)
}
