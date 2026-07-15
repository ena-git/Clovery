package identityflow

import (
	"context"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/auth"
)

type federatedLoginCompleter interface {
	StartLogin(ctx context.Context, providerName string) (auth.FederatedLoginIntent, error)
	CompleteLogin(ctx context.Context, command auth.FederatedLoginCommand) (auth.FederatedAccount, error)
	StartBinding(ctx context.Context, accessToken string, providerName string) (auth.BindingIntent, error)
	CompleteBinding(ctx context.Context, command auth.FederatedBindingCommand) error
	UnbindIdentity(ctx context.Context, command auth.FederatedUnbindingCommand) error
}

func (flow *FederatedFlow) Unbind(
	ctx context.Context,
	accessToken string,
	provider string,
) error {
	return flow.federation.UnbindIdentity(ctx, auth.FederatedUnbindingCommand{
		AccessToken: accessToken,
		Provider:    provider,
	})
}

func (flow *FederatedFlow) CompleteBinding(
	ctx context.Context,
	command FederatedBindingCommand,
) error {
	return flow.federation.CompleteBinding(ctx, auth.FederatedBindingCommand{
		AccessToken:       command.AccessToken,
		IntentID:          command.IntentID,
		Provider:          command.Provider,
		AuthorizationCode: command.AuthorizationCode,
		Nonce:             command.Nonce,
	})
}

func (flow *FederatedFlow) StartFederatedLogin(
	ctx context.Context,
	provider string,
) (FederationIntent, error) {
	intent, err := flow.federation.StartLogin(ctx, provider)
	if err != nil {
		return FederationIntent{}, err
	}
	return FederationIntent{
		ID:        intent.ID,
		Provider:  intent.Provider,
		Nonce:     intent.Nonce,
		ExpiresAt: intent.ExpiresAt,
	}, nil
}

func (flow *FederatedFlow) StartBinding(
	ctx context.Context,
	accessToken string,
	provider string,
) (FederationIntent, error) {
	intent, err := flow.federation.StartBinding(ctx, accessToken, provider)
	if err != nil {
		return FederationIntent{}, err
	}
	return FederationIntent{
		ID:        intent.ID,
		Provider:  intent.Provider,
		Nonce:     intent.Nonce,
		ExpiresAt: intent.ExpiresAt,
	}, nil
}

type sessionIssuer interface {
	Create(ctx context.Context, params auth.SessionCreateParams) (auth.SessionTokens, error)
}

type FederatedFlow struct {
	federation federatedLoginCompleter
	sessions   sessionIssuer
}

func NewFederatedFlow(
	federation federatedLoginCompleter,
	sessions sessionIssuer,
) (*FederatedFlow, error) {
	if federation == nil || sessions == nil {
		return nil, fmt.Errorf("federated flow dependencies are required")
	}
	return &FederatedFlow{federation: federation, sessions: sessions}, nil
}

func (flow *FederatedFlow) CompleteFederatedLogin(
	ctx context.Context,
	command FederatedLoginCommand,
) (SessionResult, error) {
	account, err := flow.federation.CompleteLogin(ctx, auth.FederatedLoginCommand{
		IntentID:          command.IntentID,
		Provider:          command.Provider,
		AuthorizationCode: command.AuthorizationCode,
		Nonce:             command.Nonce,
	})
	if err != nil {
		return SessionResult{}, err
	}
	tokens, err := flow.sessions.Create(ctx, auth.SessionCreateParams{
		AccountID:   account.AccountID,
		VaultID:     account.VaultID,
		DeviceID:    command.Device.ID,
		Platform:    command.Device.Platform,
		DisplayName: command.Device.DisplayName,
	})
	if err != nil {
		return SessionResult{}, err
	}
	return sessionResult(tokens), nil
}

func sessionResult(tokens auth.SessionTokens) SessionResult {
	return SessionResult{
		AccountID:            tokens.AccountID,
		VaultID:              tokens.VaultID,
		AccessToken:          tokens.AccessToken,
		AccessTokenExpiresIn: tokens.AccessTokenExpiresIn,
		RefreshToken:         tokens.RefreshToken,
	}
}
