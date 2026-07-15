package auth

import (
	"context"
	"crypto/rand"
	"database/sql"
	"fmt"
)

func (service *SessionService) Refresh(ctx context.Context, refreshToken string) (SessionTokens, error) {
	now := service.now()
	refreshHash := hashRefreshToken(refreshToken)
	transaction, err := service.database.BeginTx(ctx, nil)
	if err != nil {
		return SessionTokens{}, fmt.Errorf("begin session refresh: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	current, err := lockSessionByRefreshHash(ctx, transaction, refreshHash[:])
	if err != nil {
		return SessionTokens{}, err
	}
	if current.SessionRevoked.Valid || current.DeviceRevoked.Valid || !current.RefreshExpiry.After(now) {
		_, _ = transaction.ExecContext(
			ctx,
			"UPDATE sessions SET revoked_at = COALESCE(revoked_at, $2) WHERE token_family_id = $1",
			current.FamilyID,
			now,
		)
		_ = transaction.Commit()
		return SessionTokens{}, ErrInvalidSession
	}

	newSessionID, err := randomUUID(rand.Reader)
	if err != nil {
		return SessionTokens{}, fmt.Errorf("generate rotated session ID: %w", err)
	}
	newRefreshToken, newRefreshHash, err := newRefreshToken(sessionRandomSource)
	if err != nil {
		return SessionTokens{}, err
	}
	replacement := current
	replacement.SessionID = newSessionID
	replacement.RefreshExpiry = now.Add(refreshTokenLifetime)
	replacement.SessionRevoked = sql.NullTime{}
	if err := insertSessionRecord(ctx, transaction, replacement, newRefreshHash[:]); err != nil {
		return SessionTokens{}, err
	}
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE sessions
		 SET revoked_at = $2, rotated_at = $2, replaced_by_session_id = $3
		 WHERE id = $1 AND revoked_at IS NULL`,
		current.SessionID,
		now,
		newSessionID,
	); err != nil {
		return SessionTokens{}, fmt.Errorf("revoke rotated session: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return SessionTokens{}, fmt.Errorf("commit session refresh: %w", err)
	}
	return service.issueTokens(replacement, newRefreshToken, now)
}
