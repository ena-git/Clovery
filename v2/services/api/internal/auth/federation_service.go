package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"strings"
	"time"
)

const (
	bindingAuthenticationMaximumAge = 5 * time.Minute
	bindingIntentLifetime           = 10 * time.Minute
)

type FederationService struct {
	sessions  RecentSessionAuthenticator
	store     FederationStore
	providers map[string]IdentityProvider
	now       func() time.Time
	random    io.Reader
}

func NewFederationService(
	sessions RecentSessionAuthenticator,
	store FederationStore,
	providers []IdentityProvider,
) (*FederationService, error) {
	if sessions == nil || store == nil {
		return nil, fmt.Errorf("federation dependencies are required")
	}
	registeredProviders := make(map[string]IdentityProvider, len(providers))
	for _, provider := range providers {
		if provider == nil {
			return nil, fmt.Errorf("identity provider is required")
		}
		name := strings.ToLower(strings.TrimSpace(provider.Name()))
		if name == "" || registeredProviders[name] != nil {
			return nil, fmt.Errorf("identity provider name is invalid or duplicated")
		}
		registeredProviders[name] = provider
	}
	return &FederationService{
		sessions:  sessions,
		store:     store,
		providers: registeredProviders,
		now:       func() time.Time { return time.Now().UTC() },
		random:    rand.Reader,
	}, nil
}

func (service *FederationService) StartBinding(
	ctx context.Context,
	accessToken string,
	providerName string,
) (BindingIntent, error) {
	claims, err := service.sessions.AuthenticateRecent(ctx, accessToken, bindingAuthenticationMaximumAge)
	if err != nil {
		return BindingIntent{}, ErrRecentAuthenticationRequired
	}
	providerName = strings.ToLower(strings.TrimSpace(providerName))
	if service.providers[providerName] == nil {
		return BindingIntent{}, ErrUnsupportedIdentityProvider
	}

	intentID, err := randomUUID(service.random)
	if err != nil {
		return BindingIntent{}, fmt.Errorf("generate binding intent ID: %w", err)
	}
	nonceBytes := make([]byte, 32)
	if _, err := io.ReadFull(service.random, nonceBytes); err != nil {
		return BindingIntent{}, fmt.Errorf("generate binding nonce: %w", err)
	}
	nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
	nonceHash := sha256.Sum256([]byte(nonce))
	expiresAt := service.now().Add(bindingIntentLifetime)
	if err := service.store.CreateBindingIntent(ctx, BindingIntentRecord{
		ID:        intentID,
		AccountID: claims.AccountID,
		SessionID: claims.SessionID,
		Provider:  providerName,
		NonceHash: nonceHash[:],
		ExpiresAt: expiresAt,
	}); err != nil {
		return BindingIntent{}, fmt.Errorf("create binding intent: %w", err)
	}
	return BindingIntent{ID: intentID, Provider: providerName, Nonce: nonce, ExpiresAt: expiresAt}, nil
}
