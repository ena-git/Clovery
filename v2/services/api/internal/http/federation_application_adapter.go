package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/application/identityflow"
)

type federatedFlowApplication interface {
	StartFederatedLogin(ctx context.Context, provider string) (identityflow.FederationIntent, error)
	CompleteFederatedLogin(
		ctx context.Context,
		command identityflow.FederatedLoginCommand,
	) (identityflow.SessionResult, error)
	StartBinding(ctx context.Context, accessToken string, provider string) (identityflow.FederationIntent, error)
	CompleteBinding(ctx context.Context, command identityflow.FederatedBindingCommand) error
	Unbind(ctx context.Context, accessToken string, provider string) error
}

func (adapter *federatedApplicationAdapter) Unbind(
	ctx context.Context,
	accessToken string,
	provider string,
) error {
	return adapter.flow.Unbind(ctx, accessToken, provider)
}

type federatedApplicationAdapter struct {
	flow federatedFlowApplication
}

func NewFederatedApplication(flow federatedFlowApplication) FederatedHTTPApplication {
	return &federatedApplicationAdapter{flow: flow}
}

func (adapter *federatedApplicationAdapter) StartFederatedLogin(
	ctx context.Context,
	provider string,
) (FederationIntent, error) {
	intent, err := adapter.flow.StartFederatedLogin(ctx, provider)
	return federationIntentFromFlow(intent), err
}

func (adapter *federatedApplicationAdapter) CompleteFederatedLogin(
	ctx context.Context,
	command FederatedLoginHTTPCommand,
) (AuthSession, error) {
	session, err := adapter.flow.CompleteFederatedLogin(ctx, identityflow.FederatedLoginCommand{
		IntentID:          command.IntentID,
		Provider:          command.Provider,
		AuthorizationCode: command.AuthorizationCode,
		Nonce:             command.Nonce,
		Device:            identityflowDevice(command.Device),
	})
	return authSessionFromIdentityFlow(session), err
}

func (adapter *federatedApplicationAdapter) StartBinding(
	ctx context.Context,
	accessToken string,
	provider string,
) (FederationIntent, error) {
	intent, err := adapter.flow.StartBinding(ctx, accessToken, provider)
	return federationIntentFromFlow(intent), err
}

func (adapter *federatedApplicationAdapter) CompleteBinding(
	ctx context.Context,
	command FederatedBindingHTTPCommand,
) error {
	return adapter.flow.CompleteBinding(ctx, identityflow.FederatedBindingCommand{
		AccessToken:       command.AccessToken,
		IntentID:          command.IntentID,
		Provider:          command.Provider,
		AuthorizationCode: command.AuthorizationCode,
		Nonce:             command.Nonce,
	})
}

func federationIntentFromFlow(intent identityflow.FederationIntent) FederationIntent {
	return FederationIntent{
		ID:        intent.ID,
		Provider:  intent.Provider,
		Nonce:     intent.Nonce,
		ExpiresAt: intent.ExpiresAt,
	}
}

func identityflowDevice(device DeviceRegistration) identityflow.Device {
	return identityflow.Device{ID: device.DeviceID, Platform: device.Platform, DisplayName: device.DisplayName}
}

func authSessionFromIdentityFlow(session identityflow.SessionResult) AuthSession {
	return AuthSession{
		AccountID:            session.AccountID,
		VaultID:              session.VaultID,
		AccessToken:          session.AccessToken,
		AccessTokenExpiresIn: session.AccessTokenExpiresIn,
		RefreshToken:         session.RefreshToken,
	}
}
