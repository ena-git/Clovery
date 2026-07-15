package authflow

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func (service *Service) Authenticate(ctx context.Context, accessToken string) (auth.AccessClaims, error) {
	return service.sessions.Authenticate(ctx, accessToken)
}

func (service *Service) Refresh(ctx context.Context, refreshToken string) (auth.SessionTokens, error) {
	return service.sessions.Refresh(ctx, refreshToken)
}
