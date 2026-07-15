package auth

import (
	"encoding/json"
	"fmt"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
)

func (engine *WebAuthnEngine) FinishRegistration(
	user PasskeyUser,
	sessionData []byte,
	response json.RawMessage,
) (PasskeyCredential, error) {
	webAuthnUser, err := newWebAuthnUser(user)
	if err != nil {
		return PasskeyCredential{}, err
	}
	var session webauthn.SessionData
	if err := json.Unmarshal(sessionData, &session); err != nil {
		return PasskeyCredential{}, fmt.Errorf("decode WebAuthn registration session: %w", err)
	}
	parsedResponse, err := protocol.ParseCredentialCreationResponseBytes(response)
	if err != nil {
		return PasskeyCredential{}, fmt.Errorf("parse WebAuthn registration response: %w", err)
	}
	credential, err := engine.webAuthn.CreateCredential(webAuthnUser, session, parsedResponse)
	if err != nil {
		return PasskeyCredential{}, fmt.Errorf("verify WebAuthn registration response: %w", err)
	}
	record, err := json.Marshal(credential)
	if err != nil {
		return PasskeyCredential{}, fmt.Errorf("encode WebAuthn credential: %w", err)
	}
	return PasskeyCredential{
		ID:        append([]byte(nil), credential.ID...),
		PublicKey: append([]byte(nil), credential.PublicKey...),
		Record:    record,
		SignCount: credential.Authenticator.SignCount,
	}, nil
}
