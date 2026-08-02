package identityflow

import (
	"encoding/json"
	"time"

	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

type Device struct {
	ID          string
	Platform    string
	DisplayName string
}

type FederatedLoginCommand struct {
	IntentID          string
	Provider          string
	AuthorizationCode string
	Nonce             string
	Device            Device
}

type FederatedBindingCommand struct {
	AccessToken       string
	IntentID          string
	Provider          string
	AuthorizationCode string
	Nonce             string
}

type PasskeyLoginCommand struct {
	ChallengeID string
	Response    json.RawMessage
	Device      Device
}

type PasskeyCeremony struct {
	ChallengeID string
	Options     json.RawMessage
	ExpiresAt   time.Time
}

type PasskeyRegistrationCommand struct {
	AccessToken    string
	ChallengeID    string
	Response       json.RawMessage
	DeviceMetadata json.RawMessage
}

type SessionResult struct {
	AccountID            string
	VaultID              string
	AccessToken          string
	AccessTokenExpiresIn int
	RefreshToken         string
}

type IdentityClaimResult struct {
	Issued identityclaim.IssuedClaim
}

type FederatedCompletion struct {
	Session *SessionResult
	Claim   *IdentityClaimResult
}

type FederationIntent struct {
	ID        string
	Provider  string
	Nonce     string
	ExpiresAt time.Time
}
