package auth

import (
	"database/sql"
	"errors"
	"time"
)

var ErrInvalidSession = errors.New("invalid or revoked session")

const (
	accessTokenLifetime  = 15 * time.Minute
	refreshTokenLifetime = 30 * 24 * time.Hour
)

type SessionCreateParams struct {
	AccountID   string
	VaultID     string
	DeviceID    string
	Platform    string
	DisplayName string
}

type SessionTokens struct {
	SessionID            string
	AccountID            string
	VaultID              string
	AccessToken          string
	AccessTokenExpiresIn int
	RefreshToken         string
}

type SessionService struct {
	database *sql.DB
	signer   *AccessTokenSigner
	now      func() time.Time
}

func NewSessionService(database *sql.DB, signer *AccessTokenSigner) *SessionService {
	return &SessionService{
		database: database,
		signer:   signer,
		now:      func() time.Time { return time.Now().UTC() },
	}
}

func (service *SessionService) issueTokens(
	record sessionRecord,
	refreshToken string,
	now time.Time,
) (SessionTokens, error) {
	accessToken, err := service.signer.Sign(AccessClaims{
		AccountID:       record.AccountID,
		VaultID:         record.VaultID,
		SessionID:       record.SessionID,
		DeviceID:        record.DeviceID,
		AuthenticatedAt: record.AuthenticatedAt,
	}, now, accessTokenLifetime)
	if err != nil {
		return SessionTokens{}, err
	}
	return SessionTokens{
		SessionID:            record.SessionID,
		AccountID:            record.AccountID,
		VaultID:              record.VaultID,
		AccessToken:          accessToken,
		AccessTokenExpiresIn: int(accessTokenLifetime.Seconds()),
		RefreshToken:         refreshToken,
	}, nil
}
