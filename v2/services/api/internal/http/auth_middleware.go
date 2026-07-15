package httpapi

import (
	"net/http"
	"strings"
)

func RequireAuthentication(sessions HTTPSessionService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(responseWriter http.ResponseWriter, request *http.Request) {
			authorization := request.Header.Get("Authorization")
			if !strings.HasPrefix(authorization, "Bearer ") {
				writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
				return
			}
			token := strings.TrimSpace(strings.TrimPrefix(authorization, "Bearer "))
			if token == "" {
				writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
				return
			}
			claims, err := sessions.Authenticate(request.Context(), token)
			if err != nil {
				writeAPIError(responseWriter, http.StatusUnauthorized, "unauthorized", "Authentication failed.")
				return
			}
			ctx := withAuthClaims(request.Context(), claims)
			next.ServeHTTP(responseWriter, request.WithContext(ctx))
		})
	}
}
