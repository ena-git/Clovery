package auth

import (
	"context"
	"fmt"
	"strings"
)

func (service *FederationService) UnbindIdentity(
	ctx context.Context,
	command FederatedUnbindingCommand,
) error {
	claims, err := service.sessions.AuthenticateRecent(
		ctx,
		command.AccessToken,
		bindingAuthenticationMaximumAge,
	)
	if err != nil {
		return ErrRecentAuthenticationRequired
	}
	provider := strings.ToLower(strings.TrimSpace(command.Provider))
	if service.providers[provider] == nil {
		return ErrUnsupportedIdentityProvider
	}
	if err := service.store.UnbindIdentity(ctx, claims.AccountID, provider); err != nil {
		return fmt.Errorf("unbind federated identity: %w", err)
	}
	return nil
}
