package auth

import (
	"encoding/json"
	"fmt"

	"github.com/go-webauthn/webauthn/webauthn"
)

type webAuthnUser struct {
	handle      []byte
	name        string
	credentials []webauthn.Credential
}

func newWebAuthnUser(user PasskeyUser) (*webAuthnUser, error) {
	credentials := make([]webauthn.Credential, 0, len(user.CredentialRecords))
	for _, record := range user.CredentialRecords {
		var credential webauthn.Credential
		if err := json.Unmarshal(record, &credential); err != nil {
			return nil, fmt.Errorf("decode stored WebAuthn credential: %w", err)
		}
		credentials = append(credentials, credential)
	}
	return &webAuthnUser{
		handle:      append([]byte(nil), user.Handle...),
		name:        user.Name,
		credentials: credentials,
	}, nil
}

func (user *webAuthnUser) WebAuthnID() []byte {
	return user.handle
}

func (user *webAuthnUser) WebAuthnName() string {
	return user.name
}

func (user *webAuthnUser) WebAuthnDisplayName() string {
	return user.name
}

func (user *webAuthnUser) WebAuthnCredentials() []webauthn.Credential {
	return user.credentials
}
