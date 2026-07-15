package auth

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/clovery/clovery/services/api/internal/account"
)

func (service *LoginService) Login(ctx context.Context, loginID string, password string) (LoginResult, error) {
	rateLimitKey := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(loginID))))
	blocked, err := service.isRateLimited(ctx, rateLimitKey[:])
	if err != nil {
		return LoginResult{}, err
	}
	if blocked {
		return LoginResult{}, ErrRateLimited
	}

	normalizedID, normalizationErr := account.NormalizeLoginID(loginID)
	result, encodedHash, lookupErr := service.lookupPasswordCredential(ctx, normalizedID)
	if normalizationErr != nil || errors.Is(lookupErr, sql.ErrNoRows) {
		encodedHash = service.dummyHash
		result = LoginResult{}
		lookupErr = nil
	}
	if lookupErr != nil {
		return LoginResult{}, lookupErr
	}

	verified, err := service.hasher.Verify(password, encodedHash)
	if err != nil {
		return LoginResult{}, fmt.Errorf("verify stored password: %w", err)
	}
	if !verified || result.AccountID == "" {
		limited, err := service.recordFailedLogin(ctx, rateLimitKey[:])
		if err != nil {
			return LoginResult{}, err
		}
		if limited {
			return LoginResult{}, ErrRateLimited
		}
		return LoginResult{}, ErrInvalidCredentials
	}

	if err := service.clearFailedLogins(ctx, rateLimitKey[:]); err != nil {
		return LoginResult{}, err
	}
	return result, nil
}
