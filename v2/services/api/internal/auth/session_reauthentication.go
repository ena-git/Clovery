package auth

import (
	"context"
	"time"
)

func (service *SessionService) AuthenticateRecent(
	ctx context.Context,
	accessToken string,
	maximumAge time.Duration,
) (AccessClaims, error) {
	claims, err := service.Authenticate(ctx, accessToken)
	if err != nil {
		return AccessClaims{}, err
	}
	age := service.now().Sub(claims.AuthenticatedAt)
	if age < 0 || age > maximumAge {
		return AccessClaims{}, ErrInvalidSession
	}
	return claims, nil
}
