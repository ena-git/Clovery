package auth

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

var ErrPasskeyAuthentication = errors.New("passkey authentication failed")

type PasskeyChallengePurpose string

const (
	PasskeyChallengeRegistration PasskeyChallengePurpose = "registration"
	PasskeyChallengeLogin        PasskeyChallengePurpose = "login"
)

type PasskeyUser struct {
	AccountID         string
	VaultID           string
	Handle            []byte
	Name              string
	CredentialRecords [][]byte
}

type PasskeyChallengeRecord struct {
	ID          string
	Purpose     PasskeyChallengePurpose
	AccountID   string
	SessionID   string
	SessionData []byte
	ExpiresAt   time.Time
}

type ConsumePasskeyChallenge struct {
	ID        string
	Purpose   PasskeyChallengePurpose
	AccountID string
	SessionID string
	UsedAt    time.Time
}

type PasskeyCredential struct {
	ID             []byte
	PublicKey      []byte
	Record         []byte
	SignCount      uint32
	DeviceMetadata json.RawMessage
}

type PasskeyUserResolver func(credentialID []byte, userHandle []byte) (PasskeyUser, error)

type PasskeyCeremony struct {
	ChallengeID string
	Options     json.RawMessage
	ExpiresAt   time.Time
}

type PasskeyEngine interface {
	BeginRegistration(user PasskeyUser) (json.RawMessage, []byte, error)
	BeginLogin() (json.RawMessage, []byte, error)
	FinishLogin(
		sessionData []byte,
		response json.RawMessage,
		resolver PasskeyUserResolver,
	) (PasskeyUser, PasskeyCredential, error)
	FinishRegistration(
		user PasskeyUser,
		sessionData []byte,
		response json.RawMessage,
	) (PasskeyCredential, error)
}

type PasskeyStore interface {
	EnsureUser(ctx context.Context, accountID string) (PasskeyUser, error)
	CreateChallenge(ctx context.Context, challenge PasskeyChallengeRecord) error
	ConsumeChallenge(ctx context.Context, challenge ConsumePasskeyChallenge) ([]byte, error)
	SaveCredential(ctx context.Context, accountID string, credential PasskeyCredential) error
	FindUserByCredential(ctx context.Context, credentialID []byte, userHandle []byte) (PasskeyUser, error)
	UpdateCredential(ctx context.Context, accountID string, credential PasskeyCredential) error
}

type PasskeyRegistrationCommand struct {
	AccessToken    string
	ChallengeID    string
	Response       json.RawMessage
	DeviceMetadata json.RawMessage
}

type PasskeyLoginCommand struct {
	ChallengeID string
	Response    json.RawMessage
}

type PasskeyLoginResult struct {
	AccountID string
	VaultID   string
}
