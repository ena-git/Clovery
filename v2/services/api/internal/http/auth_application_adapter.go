package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/application/authflow"
)

type authApplicationAdapter struct {
	service *authflow.Service
}

func NewAuthApplication(service *authflow.Service) AuthApplication {
	return &authApplicationAdapter{service: service}
}

func (adapter *authApplicationAdapter) Register(
	ctx context.Context,
	command CreateAccountCommand,
) (AuthSession, error) {
	result, err := adapter.service.Register(ctx, authflow.RegisterCommand{
		LoginID:               command.LoginID,
		Password:              command.Password,
		RecoveryMethod:        command.RecoveryMethod,
		IdentityClaimToken:    command.IdentityClaimToken,
		RegistrationRequestID: command.RegistrationRequestID,
		SourceKind:            command.SourceKind,
		Device:                authflowDevice(command.Device),
	})
	return authSessionFromFlow(result), err
}

func (adapter *authApplicationAdapter) Login(
	ctx context.Context,
	command PasswordLoginCommand,
) (AuthSession, error) {
	result, err := adapter.service.Login(ctx, authflow.LoginCommand{
		LoginID:  command.LoginID,
		Password: command.Password,
		Device:   authflowDevice(command.Device),
	})
	return authSessionFromFlow(result), err
}

func (adapter *authApplicationAdapter) StartPasswordReset(
	ctx context.Context,
	command PasswordResetStartCommand,
) (PasswordResetStartResult, error) {
	result, err := adapter.service.StartPasswordReset(ctx, command.LoginID, command.RecoveryMethod)
	return PasswordResetStartResult{Accepted: result.Accepted, ExpiresIn: result.ExpiresIn}, err
}

func (adapter *authApplicationAdapter) CompletePasswordReset(
	ctx context.Context,
	command PasswordResetCompleteCommand,
) error {
	return adapter.service.CompletePasswordReset(ctx, command.ResetIntentID, command.Proof, command.NewPassword)
}

func (adapter *authApplicationAdapter) ReplaceRecoveryCodes(
	ctx context.Context,
	accountID string,
	reauthenticationProof string,
) ([]string, error) {
	return adapter.service.ReplaceRecoveryCodes(ctx, accountID, reauthenticationProof)
}

func (adapter *authApplicationAdapter) ConsumeRecoveryCode(
	ctx context.Context,
	command RecoveryCodeConsumeCommand,
) (RecoveryProof, error) {
	result, err := adapter.service.ConsumeRecoveryCode(ctx, command.LoginID, command.RecoveryCode)
	return RecoveryProof{
		ResetIntentID: result.ResetIntentID,
		Proof:         result.Proof,
		ExpiresIn:     result.ExpiresIn,
	}, err
}

func authflowDevice(device DeviceRegistration) authflow.Device {
	return authflow.Device{ID: device.DeviceID, Platform: device.Platform, DisplayName: device.DisplayName}
}

func authSessionFromFlow(result authflow.SessionResult) AuthSession {
	return AuthSession{
		AccountID:            result.AccountID,
		VaultID:              result.VaultID,
		AccessToken:          result.AccessToken,
		AccessTokenExpiresIn: result.AccessTokenExpiresIn,
		RefreshToken:         result.RefreshToken,
		RecoveryCodes:        result.RecoveryCodes,
	}
}
