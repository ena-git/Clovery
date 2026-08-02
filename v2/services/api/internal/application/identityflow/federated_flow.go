package identityflow

import (
	"context"
	"fmt"
	"reflect"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

type federatedLoginCompleter interface {
	StartLogin(ctx context.Context, providerName string) (auth.FederatedLoginIntent, error)
	CompleteLogin(ctx context.Context, command auth.FederatedLoginCommand) (auth.FederatedLoginResolution, error)
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

type IdentityClaimIssuer interface {
	Issue(context.Context, identityclaim.Identity) (identityclaim.IssuedClaim, error)
}

type FederatedFlow struct {
	federation federatedLoginCompleter
	sessions   sessionIssuer
	claims     IdentityClaimIssuer
}

func NewFederatedFlow(
	federation federatedLoginCompleter,
	sessions sessionIssuer,
	claims IdentityClaimIssuer,
) (*FederatedFlow, error) {
	if nilFederatedFlowDependency(federation) ||
		nilFederatedFlowDependency(sessions) ||
		nilFederatedFlowDependency(claims) {
		return nil, fmt.Errorf("federated flow dependencies are required")
	}
	return &FederatedFlow{federation: federation, sessions: sessions, claims: claims}, nil
}

func nilFederatedFlowDependency(dependency any) bool {
	if dependency == nil {
		return true
	}
	value := reflect.ValueOf(dependency)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	default:
		return false
	}
}

func (flow *FederatedFlow) CompleteFederatedLogin(
	ctx context.Context,
	command FederatedLoginCommand,
) (FederatedCompletion, error) {
	resolution, err := flow.federation.CompleteLogin(ctx, auth.FederatedLoginCommand{
		IntentID:          command.IntentID,
		Provider:          command.Provider,
		AuthorizationCode: command.AuthorizationCode,
		Nonce:             command.Nonce,
	})
	if err != nil {
		return FederatedCompletion{}, err
	}
	if resolution.Account == nil {
		issued, err := flow.claims.Issue(ctx, identityclaim.Identity{
			Provider: resolution.Identity.Provider,
			Issuer:   resolution.Identity.Issuer,
			Subject:  resolution.Identity.Subject,
			IntentID: command.IntentID,
		})
		if err != nil {
			return FederatedCompletion{}, err
		}
		return FederatedCompletion{Claim: &IdentityClaimResult{Issued: issued}}, nil
	}
	tokens, err := flow.sessions.Create(ctx, auth.SessionCreateParams{
		AccountID:   resolution.Account.AccountID,
		VaultID:     resolution.Account.VaultID,
		DeviceID:    command.Device.ID,
		Platform:    command.Device.Platform,
		DisplayName: command.Device.DisplayName,
	})
	if err != nil {
		return FederatedCompletion{}, err
	}
	session := sessionResult(tokens)
	return FederatedCompletion{Session: &session}, nil
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
