package auth

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"strings"
)

func (service *FederationService) StartLogin(
	ctx context.Context,
	providerName string,
) (FederatedLoginIntent, error) {
	providerName = strings.ToLower(strings.TrimSpace(providerName))
	if service.providers[providerName] == nil {
		return FederatedLoginIntent{}, ErrUnsupportedIdentityProvider
	}
	intentID, err := randomUUID(service.random)
	if err != nil {
		return FederatedLoginIntent{}, fmt.Errorf("generate federated login intent ID: %w", err)
	}
	nonceBytes := make([]byte, 32)
	if _, err := io.ReadFull(service.random, nonceBytes); err != nil {
		return FederatedLoginIntent{}, fmt.Errorf("generate federated login nonce: %w", err)
	}
	nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
	nonceHash := sha256.Sum256([]byte(nonce))
	expiresAt := service.now().Add(bindingIntentLifetime)
	if err := service.store.CreateLoginIntent(ctx, FederatedLoginIntentRecord{
		ID:        intentID,
		Provider:  providerName,
		NonceHash: nonceHash[:],
		ExpiresAt: expiresAt,
	}); err != nil {
		return FederatedLoginIntent{}, fmt.Errorf("create federated login intent: %w", err)
	}
	return FederatedLoginIntent{
		ID:        intentID,
		Provider:  providerName,
		Nonce:     nonce,
		ExpiresAt: expiresAt,
	}, nil
}

func (service *FederationService) CompleteLogin(
	ctx context.Context,
	command FederatedLoginCommand,
) (FederatedAccount, error) {
	providerName := strings.ToLower(strings.TrimSpace(command.Provider))
	provider := service.providers[providerName]
	if provider == nil {
		return FederatedAccount{}, ErrUnsupportedIdentityProvider
	}
	nonceHash := sha256.Sum256([]byte(command.Nonce))
	if err := service.store.ConsumeLoginIntent(ctx, ConsumeFederatedLoginIntent{
		ID:        command.IntentID,
		Provider:  providerName,
		NonceHash: nonceHash[:],
		UsedAt:    service.now(),
	}); err != nil {
		return FederatedAccount{}, ErrFederatedAuthentication
	}
	identity, err := provider.Verify(ctx, command.AuthorizationCode, command.Nonce)
	if err != nil {
		return FederatedAccount{}, ErrFederatedAuthentication
	}
	issuer := strings.TrimSpace(identity.Issuer)
	subject := strings.TrimSpace(identity.Subject)
	if issuer == "" || subject == "" {
		return FederatedAccount{}, ErrFederatedAuthentication
	}
	account, err := service.store.FindAccountByIdentity(ctx, FederatedIdentityKey{
		Provider: providerName,
		Issuer:   issuer,
		Subject:  subject,
	})
	if err != nil {
		return FederatedAccount{}, err
	}
	return account, nil
}
