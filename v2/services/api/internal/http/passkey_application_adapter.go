package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/application/identityflow"
)

type passkeyFlowApplication interface {
	BeginLogin(ctx context.Context) (identityflow.PasskeyCeremony, error)
	CompleteLogin(
		ctx context.Context,
		command identityflow.PasskeyLoginCommand,
	) (identityflow.SessionResult, error)
	BeginRegistration(ctx context.Context, accessToken string) (identityflow.PasskeyCeremony, error)
	CompleteRegistration(ctx context.Context, command identityflow.PasskeyRegistrationCommand) error
}

type passkeyApplicationAdapter struct {
	flow passkeyFlowApplication
}

func NewPasskeyApplication(flow passkeyFlowApplication) PasskeyHTTPApplication {
	return &passkeyApplicationAdapter{flow: flow}
}

func (adapter *passkeyApplicationAdapter) BeginLogin(ctx context.Context) (PasskeyCeremony, error) {
	ceremony, err := adapter.flow.BeginLogin(ctx)
	return passkeyCeremonyFromFlow(ceremony), err
}

func (adapter *passkeyApplicationAdapter) CompleteLogin(
	ctx context.Context,
	command PasskeyLoginHTTPCommand,
) (AuthSession, error) {
	session, err := adapter.flow.CompleteLogin(ctx, identityflow.PasskeyLoginCommand{
		ChallengeID: command.ChallengeID,
		Response:    command.Response,
		Device:      identityflowDevice(command.Device),
	})
	return authSessionFromIdentityFlow(session), err
}

func (adapter *passkeyApplicationAdapter) BeginRegistration(
	ctx context.Context,
	accessToken string,
) (PasskeyCeremony, error) {
	ceremony, err := adapter.flow.BeginRegistration(ctx, accessToken)
	return passkeyCeremonyFromFlow(ceremony), err
}

func (adapter *passkeyApplicationAdapter) CompleteRegistration(
	ctx context.Context,
	command PasskeyRegistrationHTTPCommand,
) error {
	return adapter.flow.CompleteRegistration(ctx, identityflow.PasskeyRegistrationCommand{
		AccessToken:    command.AccessToken,
		ChallengeID:    command.ChallengeID,
		Response:       command.Response,
		DeviceMetadata: command.DeviceMetadata,
	})
}

func passkeyCeremonyFromFlow(ceremony identityflow.PasskeyCeremony) PasskeyCeremony {
	return PasskeyCeremony{
		ChallengeID: ceremony.ChallengeID,
		Options:     ceremony.Options,
		ExpiresAt:   ceremony.ExpiresAt,
	}
}
