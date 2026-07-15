package config

import (
	"fmt"
	"os"
	"strings"
)

type OIDCProviderConfig struct {
	ClientID     string
	ClientSecret string
	RedirectURL  string
}

func (config OIDCProviderConfig) Enabled() bool {
	return config.ClientID != "" && config.ClientSecret != "" && config.RedirectURL != ""
}

func loadOIDCProvider(prefix string) (OIDCProviderConfig, error) {
	config := OIDCProviderConfig{
		ClientID:     strings.TrimSpace(os.Getenv(prefix + "_OIDC_CLIENT_ID")),
		ClientSecret: strings.TrimSpace(os.Getenv(prefix + "_OIDC_CLIENT_SECRET")),
		RedirectURL:  strings.TrimSpace(os.Getenv(prefix + "_OIDC_REDIRECT_URL")),
	}
	configuredValues := 0
	for _, value := range []string{config.ClientID, config.ClientSecret, config.RedirectURL} {
		if value != "" {
			configuredValues++
		}
	}
	if configuredValues != 0 && configuredValues != 3 {
		return OIDCProviderConfig{}, fmt.Errorf("%s_OIDC configuration is incomplete", prefix)
	}
	return config, nil
}
