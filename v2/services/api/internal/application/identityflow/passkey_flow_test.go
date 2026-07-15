package identityflow

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestPasskeyLoginIssuesSessionForVerifiedVault(t *testing.T) {
	passkeys := &stubPasskeyApplication{loginResult: auth.PasskeyLoginResult{
		AccountID: "88888888-8888-4888-8888-888888888888",
		VaultID:   "99999999-9999-4999-8999-999999999999",
	}}
	sessions := &stubSessionIssuer{tokens: auth.SessionTokens{
		AccountID:    passkeys.loginResult.AccountID,
		VaultID:      passkeys.loginResult.VaultID,
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}}
	flow, err := NewPasskeyFlow(passkeys, sessions)
	if err != nil {
		t.Fatalf("create passkey flow: %v", err)
	}

	result, err := flow.CompleteLogin(context.Background(), PasskeyLoginCommand{
		ChallengeID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		Response:    json.RawMessage(`{"id":"assertion"}`),
		Device: Device{
			ID:          "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
			Platform:    "ios",
			DisplayName: "iPhone",
		},
	})
	if err != nil {
		t.Fatalf("complete passkey login: %v", err)
	}
	if result.AccountID != passkeys.loginResult.AccountID || result.VaultID != passkeys.loginResult.VaultID {
		t.Fatalf("passkey session result = %#v", result)
	}
	if sessions.created.AccountID != passkeys.loginResult.AccountID ||
		sessions.created.VaultID != passkeys.loginResult.VaultID {
		t.Fatalf("session creation = %#v", sessions.created)
	}
}

func TestPasskeyRegistrationPassesCurrentAccessToken(t *testing.T) {
	passkeys := &stubPasskeyApplication{ceremony: auth.PasskeyCeremony{
		ChallengeID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
		Options:     json.RawMessage(`{"publicKey":{}}`),
	}}
	flow, err := NewPasskeyFlow(passkeys, &stubSessionIssuer{})
	if err != nil {
		t.Fatalf("create passkey flow: %v", err)
	}

	_, err = flow.BeginRegistration(context.Background(), "current-access-token")
	if err != nil {
		t.Fatalf("begin passkey registration: %v", err)
	}
	if passkeys.accessToken != "current-access-token" {
		t.Fatalf("registration access token = %q", passkeys.accessToken)
	}
}

func TestPasskeyRegistrationCompletePassesOpaqueAuthenticatorResponse(t *testing.T) {
	passkeys := &stubPasskeyApplication{}
	flow, err := NewPasskeyFlow(passkeys, &stubSessionIssuer{})
	if err != nil {
		t.Fatalf("create passkey flow: %v", err)
	}
	command := PasskeyRegistrationCommand{
		AccessToken:    "current-access-token",
		ChallengeID:    "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
		Response:       json.RawMessage(`{"id":"attestation"}`),
		DeviceMetadata: json.RawMessage(`{"platform":"ios"}`),
	}

	if err := flow.CompleteRegistration(context.Background(), command); err != nil {
		t.Fatalf("complete passkey registration: %v", err)
	}
	if passkeys.registrationCommand.ChallengeID != command.ChallengeID ||
		string(passkeys.registrationCommand.Response) != string(command.Response) {
		t.Fatalf("core registration command = %#v", passkeys.registrationCommand)
	}
}

func TestPasskeyLoginStartCreatesDiscoverableCeremony(t *testing.T) {
	passkeys := &stubPasskeyApplication{ceremony: auth.PasskeyCeremony{
		ChallengeID: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
		Options:     json.RawMessage(`{"publicKey":{"allowCredentials":[]}}`),
	}}
	flow, err := NewPasskeyFlow(passkeys, &stubSessionIssuer{})
	if err != nil {
		t.Fatalf("create passkey flow: %v", err)
	}

	ceremony, err := flow.BeginLogin(context.Background())
	if err != nil {
		t.Fatalf("begin passkey login: %v", err)
	}
	if ceremony.ChallengeID != passkeys.ceremony.ChallengeID {
		t.Fatalf("passkey ceremony = %#v", ceremony)
	}
}

type stubPasskeyApplication struct {
	loginResult         auth.PasskeyLoginResult
	ceremony            auth.PasskeyCeremony
	accessToken         string
	registrationCommand auth.PasskeyRegistrationCommand
}

func (stub *stubPasskeyApplication) CompleteRegistration(
	_ context.Context,
	command auth.PasskeyRegistrationCommand,
) error {
	stub.registrationCommand = command
	return nil
}

func (stub *stubPasskeyApplication) BeginRegistration(
	_ context.Context,
	accessToken string,
) (auth.PasskeyCeremony, error) {
	stub.accessToken = accessToken
	return stub.ceremony, nil
}

func (stub *stubPasskeyApplication) BeginLogin(context.Context) (auth.PasskeyCeremony, error) {
	return stub.ceremony, nil
}

func (stub *stubPasskeyApplication) CompleteLogin(
	context.Context,
	auth.PasskeyLoginCommand,
) (auth.PasskeyLoginResult, error) {
	return stub.loginResult, nil
}
