package httpapi

import (
	"net/http"

	"github.com/clovery/clovery/services/api/legal"
	"github.com/go-chi/chi/v5"
)

func registerLegalRoutes(router chi.Router) {
	router.Get("/v1/legal/privacy", privacyLegalHandler)
	router.Get("/v1/legal/terms", termsLegalHandler)
}

func privacyLegalHandler(responseWriter http.ResponseWriter, _ *http.Request) {
	writeLegalPage(responseWriter, legal.Privacy())
}

func termsLegalHandler(responseWriter http.ResponseWriter, _ *http.Request) {
	writeLegalPage(responseWriter, legal.Terms())
}

func writeLegalPage(responseWriter http.ResponseWriter, page []byte) {
	header := responseWriter.Header()
	header.Set("Content-Type", "text/html; charset=utf-8")
	header.Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
	header.Set("X-Content-Type-Options", "nosniff")
	header.Set("Referrer-Policy", "no-referrer")
	header.Set("Cache-Control", "public, max-age=300")
	responseWriter.WriteHeader(http.StatusOK)
	_, _ = responseWriter.Write(page)
}
