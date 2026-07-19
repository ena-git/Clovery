package httpapi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strconv"
	"sync"
	"time"
)

var (
	errInvalidFederatedCompletion    = errors.New("invalid federated completion")
	errInvalidIdentityClaimMetadata  = errors.New("invalid identity claim metadata")
	errIdentityClaimTokenUnavailable = errors.New("identity claim token unavailable")
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

type IdentityClaimHTTPResult struct {
	Provider  string
	ExpiresIn int
	secret    *identityClaimHTTPSecret
}

type identityClaimHTTPSecret struct {
	mutex    sync.Mutex
	rawToken string
}

func newIdentityClaimHTTPResult(provider string, expiresIn int, rawToken string) *IdentityClaimHTTPResult {
	return &IdentityClaimHTTPResult{
		Provider:  provider,
		ExpiresIn: expiresIn,
		secret:    &identityClaimHTTPSecret{rawToken: rawToken},
	}
}

func (result *IdentityClaimHTTPResult) takeToken() (string, bool) {
	if result == nil || result.secret == nil {
		return "", false
	}
	result.secret.mutex.Lock()
	defer result.secret.mutex.Unlock()
	if result.secret.rawToken == "" {
		return "", false
	}
	rawToken := result.secret.rawToken
	result.secret.rawToken = ""
	return rawToken, true
}

func (result IdentityClaimHTTPResult) Format(state fmt.State, verb rune) {
	formatted := "IdentityClaimHTTPResult{Provider:" + strconv.Quote(result.Provider) +
		" ExpiresIn:" + strconv.Itoa(result.ExpiresIn) + " Token:<redacted>}"
	if verb == 'q' {
		formatted = strconv.Quote(formatted)
	}
	_, _ = io.WriteString(state, formatted)
}

func (result IdentityClaimHTTPResult) LogValue() slog.Value {
	return slog.GroupValue(
		slog.String("provider", result.Provider),
		slog.Int("expires_in", result.ExpiresIn),
		slog.String("token", "<redacted>"),
	)
}

type FederatedHTTPCompletion struct {
	Session *AuthSession
	Claim   *IdentityClaimHTTPResult
}

func (completion FederatedHTTPCompletion) Format(state fmt.State, verb rune) {
	claim := "<nil>"
	if completion.Claim != nil {
		claim = fmt.Sprintf("%v", *completion.Claim)
	}
	formatted := "FederatedHTTPCompletion{SessionPresent:" +
		strconv.FormatBool(completion.Session != nil) + " Claim:" + claim + "}"
	if verb == 'q' {
		formatted = strconv.Quote(formatted)
	}
	_, _ = io.WriteString(state, formatted)
}

func (completion FederatedHTTPCompletion) LogValue() slog.Value {
	return slog.GroupValue(
		slog.Bool("session_present", completion.Session != nil),
		slog.Any("claim", completion.Claim),
	)
}

type FederatedHTTPApplication interface {
	StartFederatedLogin(ctx context.Context, provider string) (FederationIntent, error)
	CompleteFederatedLogin(ctx context.Context, command FederatedLoginHTTPCommand) (FederatedHTTPCompletion, error)
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

type identityClaimRequiredResponse struct {
	Status             string `json:"status"`
	Provider           string `json:"provider"`
	IdentityClaimToken string `json:"identity_claim_token"`
	ExpiresIn          int    `json:"expires_in"`
}
