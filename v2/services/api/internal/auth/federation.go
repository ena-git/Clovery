package auth

import (
	"context"
	"errors"
	"time"
)

var (
	ErrRecentAuthenticationRequired  = errors.New("recent Clovery authentication is required")
	ErrUnsupportedIdentityProvider   = errors.New("unsupported identity provider")
	ErrFederatedIdentityNotBound     = errors.New("federated identity is not bound")
	ErrFederatedIdentityAlreadyBound = errors.New("federated identity is already bound")
	ErrFederatedAuthentication       = errors.New("federated authentication failed")
	ErrLastRecoveryCredential        = errors.New("cannot remove the last recovery credential")
)

type VerifiedIdentity struct {
	Issuer  string
	Subject string
	Email   string
}

type IdentityProvider interface {
	Name() string
	Verify(ctx context.Context, authorizationCode string, nonce string) (VerifiedIdentity, error)
}

type RecentSessionAuthenticator interface {
	AuthenticateRecent(ctx context.Context, accessToken string, maximumAge time.Duration) (AccessClaims, error)
}

type BindingIntentRecord struct {
	ID        string
	AccountID string
	SessionID string
	Provider  string
	NonceHash []byte
	ExpiresAt time.Time
}

type FederationStore interface {
	CreateBindingIntent(ctx context.Context, intent BindingIntentRecord) error
	CreateLoginIntent(ctx context.Context, intent FederatedLoginIntentRecord) error
	ConsumeBindingIntent(ctx context.Context, intent ConsumeFederatedBindingIntent) error
	ConsumeLoginIntent(ctx context.Context, intent ConsumeFederatedLoginIntent) error
	FindAccountByIdentity(ctx context.Context, key FederatedIdentityKey) (FederatedAccount, error)
	BindIdentity(ctx context.Context, accountID string, key FederatedIdentityKey) error
	UnbindIdentity(ctx context.Context, accountID string, provider string) error
}

type BindingIntent struct {
	ID        string
	Provider  string
	Nonce     string
	ExpiresAt time.Time
}

type FederatedLoginIntentRecord struct {
	ID        string
	Provider  string
	NonceHash []byte
	ExpiresAt time.Time
}

type FederatedLoginIntent struct {
	ID        string
	Provider  string
	Nonce     string
	ExpiresAt time.Time
}

type FederatedLoginCommand struct {
	IntentID          string
	Provider          string
	AuthorizationCode string
	Nonce             string
}

type FederatedBindingCommand struct {
	AccessToken       string
	IntentID          string
	Provider          string
	AuthorizationCode string
	Nonce             string
}

type FederatedUnbindingCommand struct {
	AccessToken string
	Provider    string
}

type ConsumeFederatedBindingIntent struct {
	ID        string
	AccountID string
	SessionID string
	Provider  string
	NonceHash []byte
	UsedAt    time.Time
}

type ConsumeFederatedLoginIntent struct {
	ID        string
	Provider  string
	NonceHash []byte
	UsedAt    time.Time
}

type FederatedIdentityKey struct {
	Provider string
	Issuer   string
	Subject  string
}

type FederatedAccount struct {
	AccountID string
	VaultID   string
}
