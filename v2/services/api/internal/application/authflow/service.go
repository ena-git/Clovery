package authflow

import (
	"database/sql"

	"github.com/clovery/clovery/services/api/internal/account"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

type Service struct {
	accounts *account.Repository
	login    *auth.LoginService
	sessions *auth.SessionService
	recovery *auth.RecoveryCodeService
	reset    *auth.PasswordResetService
	hasher   auth.PasswordHasher

	claimRepository *identityclaim.PostgresRepository
	claims          *identityclaim.Service
}

func NewService(database *sql.DB, signer *auth.AccessTokenSigner) (*Service, error) {
	return NewServiceWithSessions(database, auth.NewSessionService(database, signer))
}

func NewServiceWithSessions(
	database *sql.DB,
	sessions *auth.SessionService,
) (*Service, error) {
	claimRepository := identityclaim.NewPostgresRepository(database)
	return NewServiceWithIdentityClaims(
		database,
		sessions,
		claimRepository,
		identityclaim.NewService(claimRepository),
	)
}

func NewServiceWithIdentityClaims(
	database *sql.DB,
	sessions *auth.SessionService,
	claimRepository *identityclaim.PostgresRepository,
	claims *identityclaim.Service,
) (*Service, error) {
	loginService, err := auth.NewLoginService(database)
	if err != nil {
		return nil, err
	}
	return &Service{
		accounts: account.NewRepository(database),
		login:    loginService,
		sessions: sessions,
		recovery: auth.NewRecoveryCodeService(database),
		reset:    auth.NewPasswordResetService(database),
		hasher:   auth.NewPasswordHasher(),

		claimRepository: claimRepository,
		claims:          claims,
	}, nil
}

func sessionResult(tokens auth.SessionTokens) SessionResult {
	return SessionResult{
		AccountID:            tokens.AccountID,
		VaultID:              tokens.VaultID,
		AccessToken:          tokens.AccessToken,
		AccessTokenExpiresIn: tokens.AccessTokenExpiresIn,
		RefreshToken:         tokens.RefreshToken,
	}
}
