package httpapi

import (
	"context"
	"encoding/json"
	"time"
)

type PasskeyCeremony struct {
	ChallengeID string
	Options     json.RawMessage
	ExpiresAt   time.Time
}

type PasskeyLoginHTTPCommand struct {
	ChallengeID string
	Response    json.RawMessage
	Device      DeviceRegistration
}

type PasskeyRegistrationHTTPCommand struct {
	AccessToken    string
	ChallengeID    string
	Response       json.RawMessage
	DeviceMetadata json.RawMessage
}

type PasskeyHTTPApplication interface {
	BeginLogin(ctx context.Context) (PasskeyCeremony, error)
	CompleteLogin(ctx context.Context, command PasskeyLoginHTTPCommand) (AuthSession, error)
	BeginRegistration(ctx context.Context, accessToken string) (PasskeyCeremony, error)
	CompleteRegistration(ctx context.Context, command PasskeyRegistrationHTTPCommand) error
}

type passkeyCeremonyResponse struct {
	ChallengeID string          `json:"challenge_id"`
	Options     json.RawMessage `json:"options"`
	ExpiresIn   int             `json:"expires_in"`
}

type passkeyLoginCompleteRequest struct {
	ChallengeID string             `json:"challenge_id"`
	Response    json.RawMessage    `json:"response"`
	Device      DeviceRegistration `json:"device"`
}

type passkeyRegistrationCompleteRequest struct {
	ChallengeID    string          `json:"challenge_id"`
	Response       json.RawMessage `json:"response"`
	DeviceMetadata json.RawMessage `json:"device_metadata"`
}
