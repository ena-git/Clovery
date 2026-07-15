package auth

import (
	"context"
	"fmt"
)

func (service *PasskeyService) BeginLogin(ctx context.Context) (PasskeyCeremony, error) {
	options, sessionData, err := service.engine.BeginLogin()
	if err != nil {
		return PasskeyCeremony{}, fmt.Errorf("begin WebAuthn login: %w", err)
	}
	challengeID, err := randomUUID(service.random)
	if err != nil {
		return PasskeyCeremony{}, fmt.Errorf("generate passkey login challenge ID: %w", err)
	}
	expiresAt := service.now().Add(passkeyChallengeLifetime)
	if err := service.store.CreateChallenge(ctx, PasskeyChallengeRecord{
		ID:          challengeID,
		Purpose:     PasskeyChallengeLogin,
		SessionData: sessionData,
		ExpiresAt:   expiresAt,
	}); err != nil {
		return PasskeyCeremony{}, fmt.Errorf("store passkey login challenge: %w", err)
	}
	return PasskeyCeremony{
		ChallengeID: challengeID,
		Options:     options,
		ExpiresAt:   expiresAt,
	}, nil
}

func (service *PasskeyService) CompleteLogin(
	ctx context.Context,
	command PasskeyLoginCommand,
) (PasskeyLoginResult, error) {
	sessionData, err := service.store.ConsumeChallenge(ctx, ConsumePasskeyChallenge{
		ID:      command.ChallengeID,
		Purpose: PasskeyChallengeLogin,
		UsedAt:  service.now(),
	})
	if err != nil {
		return PasskeyLoginResult{}, ErrPasskeyAuthentication
	}
	user, credential, err := service.engine.FinishLogin(
		sessionData,
		command.Response,
		func(credentialID []byte, userHandle []byte) (PasskeyUser, error) {
			return service.store.FindUserByCredential(ctx, credentialID, userHandle)
		},
	)
	if err != nil || user.AccountID == "" || user.VaultID == "" || len(credential.ID) == 0 {
		return PasskeyLoginResult{}, ErrPasskeyAuthentication
	}
	if err := service.store.UpdateCredential(ctx, user.AccountID, credential); err != nil {
		return PasskeyLoginResult{}, fmt.Errorf("update passkey credential: %w", err)
	}
	return PasskeyLoginResult{AccountID: user.AccountID, VaultID: user.VaultID}, nil
}
