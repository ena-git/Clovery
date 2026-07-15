package identityflow

import (
	"context"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/auth"
)

type passkeyLoginCompleter interface {
	BeginLogin(ctx context.Context) (auth.PasskeyCeremony, error)
	BeginRegistration(ctx context.Context, accessToken string) (auth.PasskeyCeremony, error)
	CompleteRegistration(ctx context.Context, command auth.PasskeyRegistrationCommand) error
	CompleteLogin(ctx context.Context, command auth.PasskeyLoginCommand) (auth.PasskeyLoginResult, error)
}

func (flow *PasskeyFlow) BeginLogin(ctx context.Context) (PasskeyCeremony, error) {
	ceremony, err := flow.passkeys.BeginLogin(ctx)
	if err != nil {
		return PasskeyCeremony{}, err
	}
	return passkeyCeremony(ceremony), nil
}

func (flow *PasskeyFlow) CompleteRegistration(
	ctx context.Context,
	command PasskeyRegistrationCommand,
) error {
	return flow.passkeys.CompleteRegistration(ctx, auth.PasskeyRegistrationCommand{
		AccessToken:    command.AccessToken,
		ChallengeID:    command.ChallengeID,
		Response:       command.Response,
		DeviceMetadata: command.DeviceMetadata,
	})
}

func (flow *PasskeyFlow) BeginRegistration(
	ctx context.Context,
	accessToken string,
) (PasskeyCeremony, error) {
	ceremony, err := flow.passkeys.BeginRegistration(ctx, accessToken)
	if err != nil {
		return PasskeyCeremony{}, err
	}
	return passkeyCeremony(ceremony), nil
}

func passkeyCeremony(ceremony auth.PasskeyCeremony) PasskeyCeremony {
	return PasskeyCeremony{
		ChallengeID: ceremony.ChallengeID,
		Options:     ceremony.Options,
		ExpiresAt:   ceremony.ExpiresAt,
	}
}

type PasskeyFlow struct {
	passkeys passkeyLoginCompleter
	sessions sessionIssuer
}

func NewPasskeyFlow(
	passkeys passkeyLoginCompleter,
	sessions sessionIssuer,
) (*PasskeyFlow, error) {
	if passkeys == nil || sessions == nil {
		return nil, fmt.Errorf("passkey flow dependencies are required")
	}
	return &PasskeyFlow{passkeys: passkeys, sessions: sessions}, nil
}

func (flow *PasskeyFlow) CompleteLogin(
	ctx context.Context,
	command PasskeyLoginCommand,
) (SessionResult, error) {
	loginResult, err := flow.passkeys.CompleteLogin(ctx, auth.PasskeyLoginCommand{
		ChallengeID: command.ChallengeID,
		Response:    command.Response,
	})
	if err != nil {
		return SessionResult{}, err
	}
	tokens, err := flow.sessions.Create(ctx, auth.SessionCreateParams{
		AccountID:   loginResult.AccountID,
		VaultID:     loginResult.VaultID,
		DeviceID:    command.Device.ID,
		Platform:    command.Device.Platform,
		DisplayName: command.Device.DisplayName,
	})
	if err != nil {
		return SessionResult{}, err
	}
	return sessionResult(tokens), nil
}
