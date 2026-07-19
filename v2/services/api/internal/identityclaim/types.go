package identityclaim

import (
	"errors"
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
	Token     string
	Provider  string
	ExpiresIn time.Duration
}

type StoredClaim struct {
	ID          string
	TokenSHA256 string
	Identity    Identity
	ExpiresAt   time.Time
	CreatedAt   time.Time
}

type LockedClaim struct {
	ID                    string
	Identity              Identity
	ExpiresAt             time.Time
	ConsumedAt            *time.Time
	ConsumedByAccountID   *string
	RegistrationRequestID *string
	ExistingVaultID       *string
}

type ExistingRegistration struct {
	AccountID string
	VaultID   string
}

type RegistrationResolution struct {
	Identity Identity
	Existing *ExistingRegistration
}
