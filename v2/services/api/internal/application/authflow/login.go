package authflow

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func (service *Service) Login(ctx context.Context, command LoginCommand) (SessionResult, error) {
	loginResult, err := service.login.Login(ctx, command.LoginID, command.Password)
	if err != nil {
		return SessionResult{}, err
	}
	tokens, err := service.sessions.Create(ctx, auth.SessionCreateParams{
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
