package auth

import (
	"context"

	"golang.org/x/oauth2"
)

var appleOIDCMetadata = oidcProviderMetadata{
	Name:       "apple",
	Issuer:     "https://appleid.apple.com",
	AuthURL:    "https://appleid.apple.com/auth/authorize",
	TokenURL:   "https://appleid.apple.com/auth/token",
	JWKSURL:    "https://appleid.apple.com/auth/keys",
	Algorithms: []string{"RS256"},
	AuthStyle:  oauth2.AuthStyleInParams,
}

var googleOIDCMetadata = oidcProviderMetadata{
	Name:       "google",
	Issuer:     "https://accounts.google.com",
	AuthURL:    "https://accounts.google.com/o/oauth2/v2/auth",
	TokenURL:   "https://oauth2.googleapis.com/token",
	JWKSURL:    "https://www.googleapis.com/oauth2/v3/certs",
	Algorithms: []string{"RS256"},
	AuthStyle:  oauth2.AuthStyleAutoDetect,
}

var huaweiOIDCMetadata = oidcProviderMetadata{
	Name:       "huawei",
	Issuer:     "https://accounts.huawei.com",
	AuthURL:    "https://oauth-login.cloud.huawei.com/oauth2/v3/authorize",
	TokenURL:   "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
	JWKSURL:    "https://oauth-login.cloud.huawei.com/oauth2/v3/certs",
	Algorithms: []string{"RS256", "PS256"},
	AuthStyle:  oauth2.AuthStyleInParams,
}

func NewAppleIdentityProvider(
	ctx context.Context,
	config ProductionOIDCConfig,
) (IdentityProvider, error) {
	return newProductionOIDCIdentityProvider(ctx, appleOIDCMetadata, config)
}

func NewGoogleIdentityProvider(
	ctx context.Context,
	config ProductionOIDCConfig,
) (IdentityProvider, error) {
	return newProductionOIDCIdentityProvider(ctx, googleOIDCMetadata, config)
}

func NewHuaweiIdentityProvider(
	ctx context.Context,
	config ProductionOIDCConfig,
) (IdentityProvider, error) {
	return newProductionOIDCIdentityProvider(ctx, huaweiOIDCMetadata, config)
}
