package auth

import (
	"context"
	"fmt"
)

func (service *PasskeyService) BeginRegistration(
	ctx context.Context,
	accessToken string,
) (PasskeyCeremony, error) {
	claims, err := service.sessions.AuthenticateRecent(
		ctx,
		accessToken,
		bindingAuthenticationMaximumAge,
	)
	if err != nil {
		return PasskeyCeremony{}, ErrRecentAuthenticationRequired
	}
	user, err := service.store.EnsureUser(ctx, claims.AccountID)
	if err != nil {
		return PasskeyCeremony{}, fmt.Errorf("load passkey user: %w", err)
	}
	options, sessionData, err := service.engine.BeginRegistration(user)
	if err != nil {
		return PasskeyCeremony{}, fmt.Errorf("begin WebAuthn registration: %w", err)
	}
	challengeID, err := randomUUID(service.random)
	if err != nil {
		return PasskeyCeremony{}, fmt.Errorf("generate passkey challenge ID: %w", err)
	}
	expiresAt := service.now().Add(passkeyChallengeLifetime)
	if err := service.store.CreateChallenge(ctx, PasskeyChallengeRecord{
		ID:          challengeID,
		Purpose:     PasskeyChallengeRegistration,
		AccountID:   claims.AccountID,
		SessionID:   claims.SessionID,
		SessionData: sessionData,
		ExpiresAt:   expiresAt,
	}); err != nil {
		return PasskeyCeremony{}, fmt.Errorf("store passkey registration challenge: %w", err)
	}
	return PasskeyCeremony{
		ChallengeID: challengeID,
		Options:     options,
		ExpiresAt:   expiresAt,
	}, nil
}

func (service *PasskeyService) CompleteRegistration(
	ctx context.Context,
	command PasskeyRegistrationCommand,
) error {
	claims, err := service.sessions.AuthenticateRecent(
		ctx,
		command.AccessToken,
		bindingAuthenticationMaximumAge,
	)
	if err != nil {
		return ErrRecentAuthenticationRequired
	}
	sessionData, err := service.store.ConsumeChallenge(ctx, ConsumePasskeyChallenge{
		ID:        command.ChallengeID,
		Purpose:   PasskeyChallengeRegistration,
		AccountID: claims.AccountID,
		SessionID: claims.SessionID,
		UsedAt:    service.now(),
	})
	if err != nil {
		return ErrPasskeyAuthentication
	}
	user, err := service.store.EnsureUser(ctx, claims.AccountID)
	if err != nil {
		return fmt.Errorf("load passkey user: %w", err)
	}
	credential, err := service.engine.FinishRegistration(user, sessionData, command.Response)
	if err != nil {
		return ErrPasskeyAuthentication
	}
	if len(credential.ID) == 0 || len(credential.PublicKey) == 0 || len(credential.Record) == 0 {
		return ErrPasskeyAuthentication
	}
	credential.DeviceMetadata = command.DeviceMetadata
	if err := service.store.SaveCredential(ctx, claims.AccountID, credential); err != nil {
		return fmt.Errorf("save passkey credential: %w", err)
	}
	return nil
}
