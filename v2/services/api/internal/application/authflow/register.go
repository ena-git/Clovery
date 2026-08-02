package authflow

import (
	"context"
	"errors"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/account"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/google/uuid"
)

var (
	ErrInvalidAuthRequest        = errors.New("invalid authentication request")
	ErrUnsupportedRecoveryMethod = errors.New("recovery method is not available")
)

func (service *Service) Register(ctx context.Context, command RegisterCommand) (SessionResult, error) {
	if command.IdentityClaimToken != nil || command.RegistrationRequestID != nil || command.SourceKind != nil ||
		command.RecoveryMethod == "bound_identity" {
		return service.registerClaimedAccount(ctx, command)
	}
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

func (service *Service) registerClaimedAccount(ctx context.Context, command RegisterCommand) (SessionResult, error) {
	if command.RecoveryMethod != "bound_identity" || command.IdentityClaimToken == nil ||
		command.RegistrationRequestID == nil || command.SourceKind == nil ||
		!command.IdentityClaimToken.Valid() || !validSourceKind(*command.SourceKind) {
		return SessionResult{}, ErrInvalidAuthRequest
	}
	requestUUID, err := uuid.Parse(*command.RegistrationRequestID)
	if err != nil || requestUUID == uuid.Nil {
		return SessionResult{}, ErrInvalidAuthRequest
	}
	registrationRequestID := requestUUID.String()
	passwordHash, err := service.hasher.Hash(command.Password)
	if err != nil {
		return SessionResult{}, err
	}
	accountID, err := newUUID()
	if err != nil {
		return SessionResult{}, fmt.Errorf("generate account ID: %w", err)
	}
	vaultID, err := newUUID()
	if err != nil {
		return SessionResult{}, fmt.Errorf("generate vault ID: %w", err)
	}
	created, err := service.accounts.CreateClaimedAccount(ctx, account.CreateClaimedAccountParams{
		AccountID:             accountID,
		VaultID:               vaultID,
		LoginID:               command.LoginID,
		PasswordHash:          passwordHash,
		IdentityClaimToken:    *command.IdentityClaimToken,
		RegistrationRequestID: registrationRequestID,
		SourceKind:            *command.SourceKind,
	}, service.claimRepository, service.claims)
	if err != nil {
		return SessionResult{}, err
	}
	tokens, err := service.sessions.Create(ctx, auth.SessionCreateParams{
		AccountID:   created.AccountID,
		VaultID:     created.VaultID,
		DeviceID:    command.Device.ID,
		Platform:    command.Device.Platform,
		DisplayName: command.Device.DisplayName,
	})
	if err != nil {
		return SessionResult{}, err
	}
	return sessionResult(tokens), nil
}

func validSourceKind(sourceKind string) bool {
	switch sourceKind {
	case "new_install", "legacy_local", "legacy_cloudkit":
		return true
	default:
		return false
	}
}
