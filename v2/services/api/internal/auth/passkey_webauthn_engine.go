package auth

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
)

type WebAuthnConfig struct {
	RelyingPartyID          string
	RelyingPartyDisplayName string
	Origins                 []string
}

type WebAuthnEngine struct {
	webAuthn *webauthn.WebAuthn
}

func NewWebAuthnEngine(config WebAuthnConfig) (*WebAuthnEngine, error) {
	if strings.TrimSpace(config.RelyingPartyDisplayName) == "" {
		return nil, fmt.Errorf("WebAuthn relying party display name is required")
	}
	webAuthn, err := webauthn.New(&webauthn.Config{
		RPID:                  config.RelyingPartyID,
		RPDisplayName:         config.RelyingPartyDisplayName,
		RPOrigins:             append([]string(nil), config.Origins...),
		AttestationPreference: protocol.PreferNoAttestation,
		AuthenticatorSelection: protocol.AuthenticatorSelection{
			ResidentKey:      protocol.ResidentKeyRequirementRequired,
			UserVerification: protocol.VerificationRequired,
		},
		Timeouts: webauthn.TimeoutsConfig{
			Registration: webauthn.TimeoutConfig{Enforce: true, Timeout: passkeyChallengeLifetime},
			Login:        webauthn.TimeoutConfig{Enforce: true, Timeout: passkeyChallengeLifetime},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("configure WebAuthn: %w", err)
	}
	return &WebAuthnEngine{webAuthn: webAuthn}, nil
}

func (engine *WebAuthnEngine) BeginRegistration(
	user PasskeyUser,
) (json.RawMessage, []byte, error) {
	webAuthnUser, err := newWebAuthnUser(user)
	if err != nil {
		return nil, nil, err
	}
	options, sessionData, err := engine.webAuthn.BeginRegistration(webAuthnUser)
	if err != nil {
		return nil, nil, err
	}
	encodedOptions, err := json.Marshal(options)
	if err != nil {
		return nil, nil, fmt.Errorf("encode WebAuthn registration options: %w", err)
	}
	encodedSession, err := json.Marshal(sessionData)
	if err != nil {
		return nil, nil, fmt.Errorf("encode WebAuthn registration session: %w", err)
	}
	return encodedOptions, encodedSession, nil
}

func (engine *WebAuthnEngine) BeginLogin() (json.RawMessage, []byte, error) {
	options, sessionData, err := engine.webAuthn.BeginDiscoverableLogin()
	if err != nil {
		return nil, nil, err
	}
	encodedOptions, err := json.Marshal(options)
	if err != nil {
		return nil, nil, fmt.Errorf("encode WebAuthn login options: %w", err)
	}
	encodedSession, err := json.Marshal(sessionData)
	if err != nil {
		return nil, nil, fmt.Errorf("encode WebAuthn login session: %w", err)
	}
	return encodedOptions, encodedSession, nil
}
