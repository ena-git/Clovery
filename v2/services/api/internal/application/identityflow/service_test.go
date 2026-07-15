package identityflow

import (
	"context"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestFederatedLoginIssuesSessionForResolvedRootAccount(t *testing.T) {
	federation := &stubFederationService{account: auth.FederatedAccount{
		AccountID: "11111111-1111-4111-8111-111111111111",
		VaultID:   "22222222-2222-4222-8222-222222222222",
	}}
	sessions := &stubSessionIssuer{tokens: auth.SessionTokens{
		AccountID:    federation.account.AccountID,
		VaultID:      federation.account.VaultID,
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}}
	service, err := NewFederatedFlow(federation, sessions)
	if err != nil {
		t.Fatalf("create identity flow service: %v", err)
	}

	result, err := service.CompleteFederatedLogin(context.Background(), FederatedLoginCommand{
		IntentID:          "33333333-3333-4333-8333-333333333333",
		Provider:          "apple",
		AuthorizationCode: "authorization-code",
		Nonce:             "nonce",
		Device: Device{
			ID:          "44444444-4444-4444-8444-444444444444",
			Platform:    "ios",
			DisplayName: "iPhone",
		},
	})
	if err != nil {
		t.Fatalf("complete federated login: %v", err)
	}
	if result.AccountID != federation.account.AccountID || result.VaultID != federation.account.VaultID {
		t.Fatalf("identity session = %#v", result)
	}
	if sessions.created.AccountID != federation.account.AccountID ||
		sessions.created.VaultID != federation.account.VaultID {
		t.Fatalf("session creation = %#v", sessions.created)
	}
}

func TestFederatedBindingPassesCurrentAccessTokenToRecentAuthentication(t *testing.T) {
	federation := &stubFederationService{intent: auth.BindingIntent{
		ID:       "55555555-5555-4555-8555-555555555555",
		Provider: "google",
		Nonce:    "nonce",
	}}
	service, err := NewFederatedFlow(federation, &stubSessionIssuer{})
	if err != nil {
		t.Fatalf("create federated flow: %v", err)
	}

	_, err = service.StartBinding(context.Background(), "current-access-token", "google")
	if err != nil {
		t.Fatalf("start federated binding: %v", err)
	}
	if federation.accessToken != "current-access-token" {
		t.Fatalf("binding access token = %q", federation.accessToken)
	}
}

func TestFederatedLoginStartCreatesUnownedProviderIntent(t *testing.T) {
	federation := &stubFederationService{loginIntent: auth.FederatedLoginIntent{
		ID:       "66666666-6666-4666-8666-666666666666",
		Provider: "huawei",
		Nonce:    "login-nonce",
	}}
	service, err := NewFederatedFlow(federation, &stubSessionIssuer{})
	if err != nil {
		t.Fatalf("create federated flow: %v", err)
	}

	intent, err := service.StartFederatedLogin(context.Background(), "huawei")
	if err != nil {
		t.Fatalf("start federated login: %v", err)
	}
	if intent.ID != federation.loginIntent.ID || intent.Provider != "huawei" {
		t.Fatalf("federated login intent = %#v", intent)
	}
}

func TestFederatedBindingCompleteRetainsCurrentSessionProof(t *testing.T) {
	federation := &stubFederationService{}
	service, err := NewFederatedFlow(federation, &stubSessionIssuer{})
	if err != nil {
		t.Fatalf("create federated flow: %v", err)
	}
	command := FederatedBindingCommand{
		AccessToken:       "current-access-token",
		IntentID:          "77777777-7777-4777-8777-777777777777",
		Provider:          "apple",
		AuthorizationCode: "authorization-code",
		Nonce:             "binding-nonce",
	}

	if err := service.CompleteBinding(context.Background(), command); err != nil {
		t.Fatalf("complete federated binding: %v", err)
	}
	if federation.bindingCommand.AccessToken != command.AccessToken ||
		federation.bindingCommand.IntentID != command.IntentID {
		t.Fatalf("core binding command = %#v", federation.bindingCommand)
	}
}

type stubFederationService struct {
	account        auth.FederatedAccount
	intent         auth.BindingIntent
	loginIntent    auth.FederatedLoginIntent
	accessToken    string
	bindingCommand auth.FederatedBindingCommand
}

func (stub *stubFederationService) CompleteBinding(
	_ context.Context,
	command auth.FederatedBindingCommand,
) error {
	stub.bindingCommand = command
	return nil
}

func (*stubFederationService) UnbindIdentity(
	context.Context,
	auth.FederatedUnbindingCommand,
) error {
	return nil
}

func (stub *stubFederationService) StartLogin(
	context.Context,
	string,
) (auth.FederatedLoginIntent, error) {
	return stub.loginIntent, nil
}

func (stub *stubFederationService) StartBinding(
	_ context.Context,
	accessToken string,
	_ string,
) (auth.BindingIntent, error) {
	stub.accessToken = accessToken
	return stub.intent, nil
}

func (stub *stubFederationService) CompleteLogin(
	context.Context,
	auth.FederatedLoginCommand,
) (auth.FederatedAccount, error) {
	return stub.account, nil
}

type stubSessionIssuer struct {
	created auth.SessionCreateParams
	tokens  auth.SessionTokens
}

func (stub *stubSessionIssuer) Create(
	_ context.Context,
	params auth.SessionCreateParams,
) (auth.SessionTokens, error) {
	stub.created = params
	return stub.tokens, nil
}
