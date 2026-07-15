package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

func (service *SessionService) Authenticate(ctx context.Context, accessToken string) (AccessClaims, error) {
	claims, err := service.signer.Verify(accessToken, service.now())
	if err != nil {
		return AccessClaims{}, ErrInvalidSession
	}
	var active bool
	err = service.database.QueryRowContext(
		ctx,
		`SELECT sessions.revoked_at IS NULL AND devices.revoked_at IS NULL AND vaults.status = 'active'
		 FROM sessions
		 JOIN devices ON devices.id = sessions.device_id
		 JOIN vaults ON vaults.owner_account_id = devices.account_id
		 WHERE sessions.id = $1 AND devices.id = $2 AND devices.account_id = $3 AND vaults.id = $4`,
		claims.SessionID,
		claims.DeviceID,
		claims.AccountID,
		claims.VaultID,
	).Scan(&active)
	if errors.Is(err, sql.ErrNoRows) || !active {
		return AccessClaims{}, ErrInvalidSession
	}
	if err != nil {
		return AccessClaims{}, fmt.Errorf("validate access session: %w", err)
	}
	return claims, nil
}
