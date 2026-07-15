package httpapi

import "github.com/go-chi/chi/v5"

type authHandler struct {
	application AuthApplication
}

func registerAuthRoutes(router chi.Router, application AuthApplication) {
	handler := authHandler{application: application}
	router.Post("/v1/auth/accounts", handler.createAccount)
	router.Post("/v1/auth/password/login", handler.passwordLogin)
	router.Post("/v1/auth/password/reset/start", handler.startPasswordReset)
	router.Post("/v1/auth/password/reset/complete", handler.completePasswordReset)
	router.Post("/v1/auth/recovery-codes", handler.replaceRecoveryCodes)
	router.Post("/v1/auth/recovery-codes/consume", handler.consumeRecoveryCode)
}
