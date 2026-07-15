package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/auth"
)

type HTTPSessionService interface {
	Authenticate(context.Context, string) (auth.AccessClaims, error)
	Refresh(context.Context, string) (auth.SessionTokens, error)
}

type refreshSessionRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func authSessionFromTokens(tokens auth.SessionTokens) AuthSession {
	return AuthSession{
		AccountID:            tokens.AccountID,
		VaultID:              tokens.VaultID,
		AccessToken:          tokens.AccessToken,
		AccessTokenExpiresIn: tokens.AccessTokenExpiresIn,
		RefreshToken:         tokens.RefreshToken,
	}
}
