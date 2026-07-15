package observability

import (
	"crypto/subtle"
	"net/http"
	"strings"
)

func (registry *Registry) ProtectedHandler(token string) http.Handler {
	metricsHandler := registry.Handler()
	return http.HandlerFunc(func(responseWriter http.ResponseWriter, request *http.Request) {
		provided := strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer ")
		if subtle.ConstantTimeCompare([]byte(provided), []byte(token)) != 1 {
			responseWriter.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(responseWriter, "Unauthorized", http.StatusUnauthorized)
			return
		}
		metricsHandler.ServeHTTP(responseWriter, request)
	})
}
