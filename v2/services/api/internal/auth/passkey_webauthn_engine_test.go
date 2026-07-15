package auth

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestWebAuthnEngineCreatesRegistrationChallenge(t *testing.T) {
	engine, err := NewWebAuthnEngine(WebAuthnConfig{
		RelyingPartyID:          "accounts.clovery.example",
		RelyingPartyDisplayName: "Clovery",
		Origins:                 []string{"https://accounts.clovery.example"},
	})
	if err != nil {
		t.Fatalf("create WebAuthn engine: %v", err)
	}

	options, sessionData, err := engine.BeginRegistration(PasskeyUser{
		Handle: bytes.Repeat([]byte{7}, 32),
		Name:   "garden_user",
	})
	if err != nil {
		t.Fatalf("begin WebAuthn registration: %v", err)
	}
	var decodedOptions map[string]any
	if err := json.Unmarshal(options, &decodedOptions); err != nil {
		t.Fatalf("decode registration options: %v", err)
	}
	if decodedOptions["publicKey"] == nil {
		t.Fatalf("registration options = %s", options)
	}
	var decodedSession map[string]any
	if err := json.Unmarshal(sessionData, &decodedSession); err != nil {
		t.Fatalf("decode registration session: %v", err)
	}
	if decodedSession["challenge"] == nil {
		t.Fatalf("registration session = %s", sessionData)
	}
}

func TestWebAuthnEngineRejectsMalformedRegistrationResponse(t *testing.T) {
	engine, err := NewWebAuthnEngine(WebAuthnConfig{
		RelyingPartyID:          "accounts.clovery.example",
		RelyingPartyDisplayName: "Clovery",
		Origins:                 []string{"https://accounts.clovery.example"},
	})
	if err != nil {
		t.Fatalf("create WebAuthn engine: %v", err)
	}
	user := PasskeyUser{
		Handle: bytes.Repeat([]byte{8}, 32),
		Name:   "garden_user",
	}
	_, sessionData, err := engine.BeginRegistration(user)
	if err != nil {
		t.Fatalf("begin WebAuthn registration: %v", err)
	}

	if _, err := engine.FinishRegistration(
		user,
		sessionData,
		json.RawMessage(`{"id":"not-a-webauthn-response"}`),
	); err == nil {
		t.Fatal("WebAuthn engine accepted malformed registration response")
	}
}

func TestWebAuthnEngineCreatesDiscoverableLoginChallenge(t *testing.T) {
	engine, err := NewWebAuthnEngine(WebAuthnConfig{
		RelyingPartyID:          "accounts.clovery.example",
		RelyingPartyDisplayName: "Clovery",
		Origins:                 []string{"https://accounts.clovery.example"},
	})
	if err != nil {
		t.Fatalf("create WebAuthn engine: %v", err)
	}

	options, sessionData, err := engine.BeginLogin()
	if err != nil {
		t.Fatalf("begin WebAuthn login: %v", err)
	}
	var decodedOptions map[string]any
	if err := json.Unmarshal(options, &decodedOptions); err != nil {
		t.Fatalf("decode login options: %v", err)
	}
	if decodedOptions["publicKey"] == nil {
		t.Fatalf("login options = %s", options)
	}
	var decodedSession struct {
		UserID               []byte   `json:"user_id"`
		AllowedCredentialIDs [][]byte `json:"allowed_credentials"`
	}
	if err := json.Unmarshal(sessionData, &decodedSession); err != nil {
		t.Fatalf("decode login session: %v", err)
	}
	if len(decodedSession.UserID) != 0 || len(decodedSession.AllowedCredentialIDs) != 0 {
		t.Fatalf("discoverable login session = %s", sessionData)
	}
}

func TestWebAuthnEngineRejectsMalformedLoginBeforeAccountLookup(t *testing.T) {
	engine, err := NewWebAuthnEngine(WebAuthnConfig{
		RelyingPartyID:          "accounts.clovery.example",
		RelyingPartyDisplayName: "Clovery",
		Origins:                 []string{"https://accounts.clovery.example"},
	})
	if err != nil {
		t.Fatalf("create WebAuthn engine: %v", err)
	}
	_, sessionData, err := engine.BeginLogin()
	if err != nil {
		t.Fatalf("begin WebAuthn login: %v", err)
	}
	lookupCalled := false

	_, _, err = engine.FinishLogin(
		sessionData,
		json.RawMessage(`{"id":"not-an-assertion"}`),
		func([]byte, []byte) (PasskeyUser, error) {
			lookupCalled = true
			return PasskeyUser{}, nil
		},
	)
	if err == nil {
		t.Fatal("WebAuthn engine accepted malformed login response")
	}
	if lookupCalled {
		t.Fatal("account lookup ran before assertion parsing succeeded")
	}
}
