package auth

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"
)

func (service *FederationService) CompleteBinding(
	ctx context.Context,
	command FederatedBindingCommand,
) error {
	claims, err := service.sessions.AuthenticateRecent(
		ctx,
		command.AccessToken,
		bindingAuthenticationMaximumAge,
	)
	if err != nil {
		return ErrRecentAuthenticationRequired
	}
	providerName := strings.ToLower(strings.TrimSpace(command.Provider))
	provider := service.providers[providerName]
	if provider == nil {
		return ErrUnsupportedIdentityProvider
	}
	nonceHash := sha256.Sum256([]byte(command.Nonce))
	if err := service.store.ConsumeBindingIntent(ctx, ConsumeFederatedBindingIntent{
		ID:        command.IntentID,
		AccountID: claims.AccountID,
		SessionID: claims.SessionID,
		Provider:  providerName,
		NonceHash: nonceHash[:],
		UsedAt:    service.now(),
	}); err != nil {
		return ErrFederatedAuthentication
	}
	identity, err := provider.Verify(ctx, command.AuthorizationCode, command.Nonce)
	if err != nil {
		return ErrFederatedAuthentication
	}
	issuer := strings.TrimSpace(identity.Issuer)
	subject := strings.TrimSpace(identity.Subject)
	if issuer == "" || subject == "" {
		return ErrFederatedAuthentication
	}
	if err := service.store.BindIdentity(ctx, claims.AccountID, FederatedIdentityKey{
		Provider: providerName,
		Issuer:   issuer,
		Subject:  subject,
	}); err != nil {
		return fmt.Errorf("bind federated identity: %w", err)
	}
	return nil
}
