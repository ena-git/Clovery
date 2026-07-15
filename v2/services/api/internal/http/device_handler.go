package httpapi

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
)

type deviceHandler struct {
	application DeviceHTTPApplication
}

func registerDeviceRoutes(
	router chi.Router,
	application DeviceHTTPApplication,
	sessions HTTPSessionService,
) {
	handler := deviceHandler{application: application}
	router.Group(func(protected chi.Router) {
		protected.Use(RequireAuthentication(sessions))
		protected.Get("/v1/account/devices", handler.list)
		protected.Delete("/v1/account/devices/{deviceId}", handler.revoke)
	})
}

func (handler deviceHandler) list(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	if !ok {
		writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
		return
	}
	devices, err := handler.application.ListDevices(request.Context(), claims.AccountID, claims.DeviceID)
	if err != nil {
		writeManagementError(responseWriter, err)
		return
	}
	writeJSON(responseWriter, http.StatusOK, map[string][]DeviceSummary{"devices": devices})
}

func (handler deviceHandler) revoke(responseWriter http.ResponseWriter, request *http.Request) {
	claims, ok := authClaimsFromContext(request.Context())
	deviceID := strings.TrimSpace(chi.URLParam(request, "deviceId"))
	if !ok || deviceID == "" {
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_request", "The request is invalid.")
		return
	}
	if err := handler.application.RevokeDevice(request.Context(), claims.AccountID, deviceID); err != nil {
		writeManagementError(responseWriter, err)
		return
	}
	responseWriter.WriteHeader(http.StatusNoContent)
}
