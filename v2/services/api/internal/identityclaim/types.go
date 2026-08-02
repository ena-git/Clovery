package identityclaim

import (
	"database/sql"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strconv"
	"sync"
	"time"
)

var (
	ErrInvalidClaim    = errors.New("invalid identity claim")
	ErrExpiredClaim    = errors.New("expired identity claim")
	ErrConsumedClaim   = errors.New("consumed identity claim")
	ErrInvalidIdentity = errors.New("invalid verified identity")
)

type Identity struct {
	Provider string
	Issuer   string
	Subject  string
	IntentID string
}

type IssuedClaim struct {
	secret    *issuedClaimSecret
	Provider  string
	ExpiresIn time.Duration
}

type issuedClaimSecret struct {
	mutex    sync.Mutex
	rawToken string
}

func (claim *IssuedClaim) TakeToken() (string, bool) {
	if claim == nil || claim.secret == nil {
		return "", false
	}
	claim.secret.mutex.Lock()
	defer claim.secret.mutex.Unlock()
	if claim.secret.rawToken == "" {
		return "", false
	}
	rawToken := claim.secret.rawToken
	claim.secret.rawToken = ""
	return rawToken, true
}

func (claim IssuedClaim) Format(state fmt.State, verb rune) {
	formatted := "IssuedClaim{Provider:" + strconv.Quote(claim.Provider) +
		" ExpiresIn:" + claim.ExpiresIn.String() + " Token:<redacted>}"
	if verb == 'q' {
		formatted = strconv.Quote(formatted)
	}
	_, _ = io.WriteString(state, formatted)
}

func (claim IssuedClaim) LogValue() slog.Value {
	return slog.GroupValue(
		slog.String("provider", claim.Provider),
		slog.Duration("expires_in", claim.ExpiresIn),
		slog.String("token", "<redacted>"),
	)
}

type StoredClaim struct {
	ID          string
	TokenSHA256 string
	Identity    Identity
	ExpiresAt   time.Time
	CreatedAt   time.Time
}

type LockedClaim struct {
	id                    string
	transaction           *sql.Tx
	identity              Identity
	expiresAt             time.Time
	consumedAt            *time.Time
	consumedByAccountID   *string
	registrationRequestID *string
	existingVaultID       *string
}

type PendingConsumption struct {
	claimID               string
	transaction           *sql.Tx
	registrationRequestID string
}

type ExistingRegistration struct {
	AccountID string
	VaultID   string
}

type RegistrationResolution struct {
	Identity           Identity
	Existing           *ExistingRegistration
	PendingConsumption *PendingConsumption
}
