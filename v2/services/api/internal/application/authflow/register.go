package authflow

import (
	"context"
	"errors"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/auth"
)

var ErrUnsupportedRecoveryMethod = errors.New("recovery method is not available")

func (service *Service) Register(ctx context.Context, command RegisterCommand) (SessionResult, error) {
	if command.RecoveryMethod != "recovery_codes" {
		return SessionResult{}, ErrUnsupportedRecoveryMethod
	}
	accountID, err := newUUID()
	if err != nil {
		return SessionResult{}, fmt.Errorf("generate account ID: %w", err)
	}
	vaultID, err := newUUID()
	if err != nil {
		return SessionResult{}, fmt.Errorf("generate vault ID: %w", err)
	}
	if err := service.login.Register(ctx, auth.Registration{
		AccountID: accountID,
		VaultID:   vaultID,
		LoginID:   command.LoginID,
		Password:  command.Password,
	}); err != nil {
		return SessionResult{}, err
	}

	cleanup := func() {
		_ = service.accounts.DeleteFailedRegistration(ctx, accountID)
	}
	recoveryCodes, err := service.recovery.Replace(ctx, accountID)
	if err != nil {
		cleanup()
		return SessionResult{}, err
	}
	tokens, err := service.sessions.Create(ctx, auth.SessionCreateParams{
		AccountID:   accountID,
		VaultID:     vaultID,
		DeviceID:    command.Device.ID,
		Platform:    command.Device.Platform,
		DisplayName: command.Device.DisplayName,
	})
	if err != nil {
		cleanup()
		return SessionResult{}, err
	}
	result := sessionResult(tokens)
	result.RecoveryCodes = recoveryCodes
	return result, nil
}
