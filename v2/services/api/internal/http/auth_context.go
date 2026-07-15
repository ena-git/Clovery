package httpapi

import "context"

import "github.com/clovery/clovery/services/api/internal/auth"

type authClaimsContextKey struct{}

func withAuthClaims(ctx context.Context, claims auth.AccessClaims) context.Context {
	return context.WithValue(ctx, authClaimsContextKey{}, claims)
}

func authClaimsFromContext(ctx context.Context) (auth.AccessClaims, bool) {
	claims, ok := ctx.Value(authClaimsContextKey{}).(auth.AccessClaims)
	return claims, ok
}

func AccountIDFromContext(ctx context.Context) (string, bool) {
	claims, ok := authClaimsFromContext(ctx)
	return claims.AccountID, ok && claims.AccountID != ""
}

func VaultIDFromContext(ctx context.Context) (string, bool) {
	claims, ok := authClaimsFromContext(ctx)
	return claims.VaultID, ok && claims.VaultID != ""
}
