package auth

import (
	"context"
	"crypto/rand"
	"fmt"
)

func (service *SessionService) Create(ctx context.Context, params SessionCreateParams) (SessionTokens, error) {
	now := service.now()
	sessionID, err := randomUUID(rand.Reader)
	if err != nil {
		return SessionTokens{}, fmt.Errorf("generate session ID: %w", err)
	}
	refreshToken, refreshHash, err := newRefreshToken(sessionRandomSource)
	if err != nil {
		return SessionTokens{}, err
	}
	record := sessionRecord{
		SessionID:       sessionID,
		FamilyID:        sessionID,
		DeviceID:        params.DeviceID,
		AccountID:       params.AccountID,
		VaultID:         params.VaultID,
		AuthenticatedAt: now,
		RefreshExpiry:   now.Add(refreshTokenLifetime),
	}

	transaction, err := service.database.BeginTx(ctx, nil)
	if err != nil {
		return SessionTokens{}, fmt.Errorf("begin session creation: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()
	if err := verifySessionVault(ctx, transaction, params.AccountID, params.VaultID); err != nil {
		return SessionTokens{}, err
	}
	if err := upsertSessionDevice(ctx, transaction, params); err != nil {
		return SessionTokens{}, err
	}
	if err := insertSessionRecord(ctx, transaction, record, refreshHash[:]); err != nil {
		return SessionTokens{}, err
	}
	if err := transaction.Commit(); err != nil {
		return SessionTokens{}, fmt.Errorf("commit session creation: %w", err)
	}
	return service.issueTokens(record, refreshToken, now)
}
