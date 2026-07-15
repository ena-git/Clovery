package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/clovery/clovery/services/api/internal/account"
)

var (
	ErrInvalidCredentials = errors.New("invalid login ID or password")
	ErrRateLimited        = errors.New("too many authentication attempts")
)

type Registration struct {
	AccountID string
	VaultID   string
	LoginID   string
	Password  string
}

type LoginResult struct {
	AccountID string
	VaultID   string
}

type LoginService struct {
	database  *sql.DB
	accounts  *account.Repository
	hasher    PasswordHasher
	dummyHash string
	now       func() time.Time
}

func NewLoginService(database *sql.DB) (*LoginService, error) {
	hasher := NewPasswordHasher()
	dummyHash, err := hasher.Hash("timing defense password only")
	if err != nil {
		return nil, fmt.Errorf("create timing defense hash: %w", err)
	}
	return &LoginService{
		database:  database,
		accounts:  account.NewRepository(database),
		hasher:    hasher,
		dummyHash: dummyHash,
		now:       func() time.Time { return time.Now().UTC() },
	}, nil
}

func (service *LoginService) Register(ctx context.Context, registration Registration) error {
	passwordHash, err := service.hasher.Hash(registration.Password)
	if err != nil {
		return err
	}
	return service.accounts.CreateAccount(ctx, account.CreateAccountParams{
		AccountID:    registration.AccountID,
		VaultID:      registration.VaultID,
		LoginID:      registration.LoginID,
		PasswordHash: passwordHash,
	})
}
