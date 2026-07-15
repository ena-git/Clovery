package auth

import (
	"encoding/json"
	"fmt"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
)

func (engine *WebAuthnEngine) FinishLogin(
	sessionData []byte,
	response json.RawMessage,
	resolver PasskeyUserResolver,
) (PasskeyUser, PasskeyCredential, error) {
	var session webauthn.SessionData
	if err := json.Unmarshal(sessionData, &session); err != nil {
		return PasskeyUser{}, PasskeyCredential{}, fmt.Errorf("decode WebAuthn login session: %w", err)
	}
	parsedResponse, err := protocol.ParseCredentialRequestResponseBytes(response)
	if err != nil {
		return PasskeyUser{}, PasskeyCredential{}, fmt.Errorf("parse WebAuthn login response: %w", err)
	}
	var resolvedUser PasskeyUser
	_, credential, err := engine.webAuthn.ValidatePasskeyLogin(
		func(credentialID []byte, userHandle []byte) (webauthn.User, error) {
			user, err := resolver(credentialID, userHandle)
			if err != nil {
				return nil, err
			}
			webAuthnUser, err := newWebAuthnUser(user)
			if err != nil {
				return nil, err
			}
			resolvedUser = user
			return webAuthnUser, nil
		},
		session,
		parsedResponse,
	)
	if err != nil {
		return PasskeyUser{}, PasskeyCredential{}, fmt.Errorf("verify WebAuthn login response: %w", err)
	}
	record, err := json.Marshal(credential)
	if err != nil {
		return PasskeyUser{}, PasskeyCredential{}, fmt.Errorf("encode updated WebAuthn credential: %w", err)
	}
	return resolvedUser, PasskeyCredential{
		ID:        append([]byte(nil), credential.ID...),
		PublicKey: append([]byte(nil), credential.PublicKey...),
		Record:    record,
		SignCount: credential.Authenticator.SignCount,
	}, nil
}
