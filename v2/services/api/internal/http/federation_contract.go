package httpapi

import (
	"context"
	"time"
)

type FederationIntent struct {
	ID        string
	Provider  string
	Nonce     string
	ExpiresAt time.Time
}

type FederatedLoginHTTPCommand struct {
	IntentID          string
	Provider          string
	AuthorizationCode string
	Nonce             string
	Device            DeviceRegistration
}

type FederatedBindingHTTPCommand struct {
	AccessToken       string
	IntentID          string
	Provider          string
	AuthorizationCode string
	Nonce             string
}

type FederatedHTTPApplication interface {
	StartFederatedLogin(ctx context.Context, provider string) (FederationIntent, error)
	CompleteFederatedLogin(ctx context.Context, command FederatedLoginHTTPCommand) (AuthSession, error)
	StartBinding(ctx context.Context, accessToken string, provider string) (FederationIntent, error)
	CompleteBinding(ctx context.Context, command FederatedBindingHTTPCommand) error
	Unbind(ctx context.Context, accessToken string, provider string) error
}

type bindingStartRequest struct {
	Provider string `json:"provider"`
}

type federatedLoginCompleteRequest struct {
	IntentID          string             `json:"intent_id"`
	Nonce             string             `json:"nonce"`
	AuthorizationCode string             `json:"authorization_code"`
	Device            DeviceRegistration `json:"device"`
}

type bindingCompleteRequest struct {
	IntentID          string `json:"intent_id"`
	Provider          string `json:"provider"`
	Nonce             string `json:"nonce"`
	AuthorizationCode string `json:"authorization_code"`
}

type federationIntentResponse struct {
	IntentID  string `json:"intent_id"`
	Provider  string `json:"provider"`
	Nonce     string `json:"nonce"`
	ExpiresIn int    `json:"expires_in"`
}
