package main

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/config"
)

type oidcProviderFactory func(context.Context, auth.ProductionOIDCConfig) (auth.IdentityProvider, error)

func buildOIDCProviders(ctx context.Context, applicationConfig config.Config) ([]auth.IdentityProvider, error) {
	configuredProviders := []struct {
		config  config.OIDCProviderConfig
		factory oidcProviderFactory
	}{
		{applicationConfig.AppleOIDC, auth.NewAppleIdentityProvider},
		{applicationConfig.GoogleOIDC, auth.NewGoogleIdentityProvider},
		{applicationConfig.HuaweiOIDC, auth.NewHuaweiIdentityProvider},
	}
	providers := make([]auth.IdentityProvider, 0, len(configuredProviders))
	for _, configuredProvider := range configuredProviders {
		if !configuredProvider.config.Enabled() {
			continue
		}
		provider, err := configuredProvider.factory(ctx, auth.ProductionOIDCConfig{
			ClientID:     configuredProvider.config.ClientID,
			ClientSecret: auth.StaticOIDCClientSecret(configuredProvider.config.ClientSecret),
			RedirectURL:  configuredProvider.config.RedirectURL,
		})
		if err != nil {
			return nil, err
		}
		providers = append(providers, provider)
	}
	return providers, nil
}
