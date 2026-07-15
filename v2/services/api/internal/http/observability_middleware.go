package httpapi

import (
	"net/http"
	"strings"

	"github.com/clovery/clovery/services/api/internal/observability"
)

func operationalMetricsMiddleware(metrics *observability.Registry) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(responseWriter http.ResponseWriter, request *http.Request) {
			tracked := &statusResponseWriter{ResponseWriter: responseWriter, status: http.StatusOK}
			next.ServeHTTP(tracked, request)
			recordOperationalRequest(metrics, request.Method, request.URL.Path, tracked.status)
		})
	}
}

type statusResponseWriter struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (writer *statusResponseWriter) WriteHeader(status int) {
	if writer.wroteHeader {
		return
	}
	writer.wroteHeader = true
	writer.status = status
	writer.ResponseWriter.WriteHeader(status)
}

func (writer *statusResponseWriter) Write(contents []byte) (int, error) {
	if !writer.wroteHeader {
		writer.WriteHeader(writer.status)
	}
	return writer.ResponseWriter.Write(contents)
}

func recordOperationalRequest(metrics *observability.Registry, method string, path string, status int) {
	failed := status >= http.StatusBadRequest
	succeeded := status >= http.StatusOK && status < http.StatusBadRequest
	if failed && strings.HasPrefix(path, "/v1/auth/") {
		metrics.Increment(observability.AuthenticationFailures)
	}
	if failed && strings.Contains(path, "/bindings/") {
		metrics.Increment(observability.BindingFailures)
	}
	if succeeded && method == http.MethodDelete && strings.HasPrefix(path, "/v1/account/devices/") {
		metrics.Increment(observability.DeviceRevocations)
	}
	if method == http.MethodPost && path == "/v1/vault/migrations" {
		if succeeded {
			metrics.Increment(observability.MigrationStarted)
		} else {
			metrics.Increment(observability.MigrationFailed)
		}
	}
	if method == http.MethodPost && strings.HasSuffix(path, "/verify") &&
		strings.HasPrefix(path, "/v1/vault/migrations/") {
		if succeeded {
			metrics.Increment(observability.MigrationCompleted)
		} else {
			metrics.Increment(observability.MigrationFailed)
			if status == http.StatusConflict || status == http.StatusUnprocessableEntity {
				metrics.Increment(observability.MigrationValidationMismatch)
			}
		}
	}
	if succeeded && method == http.MethodPost && path == "/v1/billing/apple/restore" {
		metrics.Increment(observability.BillingRestores)
	}
}
