package identityflow

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

func TestFederatedLoginIssuesSessionForResolvedRootAccount(t *testing.T) {
	account := auth.FederatedAccount{
		AccountID: "11111111-1111-4111-8111-111111111111",
		VaultID:   "22222222-2222-4222-8222-222222222222",
	}
	federation := &stubFederationService{resolution: auth.FederatedLoginResolution{
		Identity: auth.FederatedIdentityKey{
			Provider: "apple",
			Issuer:   "https://appleid.apple.com",
			Subject:  "stable-apple-subject",
		},
		Account: &account,
	}}
	sessions := &stubSessionIssuer{tokens: auth.SessionTokens{
		AccountID:    account.AccountID,
		VaultID:      account.VaultID,
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}}
	claims := &stubIdentityClaimIssuer{}
	service, err := NewFederatedFlow(federation, sessions, claims)
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
	if result.Session == nil || result.Claim != nil {
		t.Fatalf("federated completion = %#v", result)
	}
	if result.Session.AccountID != account.AccountID || result.Session.VaultID != account.VaultID {
		t.Fatalf("identity session = %#v", result)
	}
	if sessions.created.AccountID != account.AccountID || sessions.created.VaultID != account.VaultID {
		t.Fatalf("session creation = %#v", sessions.created)
	}
	if claims.issueCalls != 0 {
		t.Fatalf("claim issue calls = %d", claims.issueCalls)
	}
}

func TestFederatedLoginIssuesClaimForVerifiedUnboundIdentity(t *testing.T) {
	resolution := auth.FederatedLoginResolution{Identity: auth.FederatedIdentityKey{
		Provider: "google",
		Issuer:   "https://accounts.google.com",
		Subject:  "stable-google-subject",
	}}
	issued := identityclaim.IssuedClaim{Provider: "google", ExpiresIn: 10 * time.Minute}
	federation := &stubFederationService{resolution: resolution}
	sessions := &stubSessionIssuer{}
	claims := &stubIdentityClaimIssuer{issued: issued}
	service, err := NewFederatedFlow(federation, sessions, claims)
	if err != nil {
		t.Fatalf("create identity flow service: %v", err)
	}

	result, err := service.CompleteFederatedLogin(context.Background(), FederatedLoginCommand{
		IntentID:          "33333333-3333-4333-8333-333333333333",
		Provider:          "google",
		AuthorizationCode: "authorization-code",
		Nonce:             "nonce",
		Device: Device{
			ID:          "44444444-4444-4444-8444-444444444444",
			Platform:    "android",
			DisplayName: "Pixel",
		},
	})
	if err != nil {
		t.Fatalf("complete federated login: %v", err)
	}
	if result.Session != nil || result.Claim == nil {
		t.Fatalf("federated completion = %#v", result)
	}
	if result.Claim.Issued.Provider != issued.Provider || result.Claim.Issued.ExpiresIn != issued.ExpiresIn {
		t.Fatalf("identity claim = %#v", result.Claim)
	}
	if claims.identity != (identityclaim.Identity{
		Provider: resolution.Identity.Provider,
		Issuer:   resolution.Identity.Issuer,
		Subject:  resolution.Identity.Subject,
		IntentID: "33333333-3333-4333-8333-333333333333",
	}) {
		t.Fatalf("issued identity = %#v", claims.identity)
	}
	if sessions.createCalls != 0 {
		t.Fatalf("session create calls = %d", sessions.createCalls)
	}
}

func TestFederatedLoginClaimFailureReturnsNoPartialCompletion(t *testing.T) {
	issueErr := errors.New("issue failed")
	service, err := NewFederatedFlow(
		&stubFederationService{resolution: auth.FederatedLoginResolution{Identity: auth.FederatedIdentityKey{
			Provider: "huawei",
			Issuer:   "https://oauth-login.cloud.huawei.com",
			Subject:  "stable-huawei-subject",
		}}},
		&stubSessionIssuer{},
		&stubIdentityClaimIssuer{err: issueErr},
	)
	if err != nil {
		t.Fatalf("create identity flow service: %v", err)
	}

	result, err := service.CompleteFederatedLogin(context.Background(), FederatedLoginCommand{
		IntentID: "55555555-5555-4555-8555-555555555555",
		Provider: "huawei",
	})
	if !errors.Is(err, issueErr) {
		t.Fatalf("complete federated login error = %v, want issue failure", err)
	}
	if result != (FederatedCompletion{}) {
		t.Fatalf("partial federated completion = %#v", result)
	}
}

func TestNewFederatedFlowRequiresEveryDependency(t *testing.T) {
	for name, dependencies := range map[string]struct {
		federation federatedLoginCompleter
		sessions   sessionIssuer
		claims     IdentityClaimIssuer
	}{
		"federation": {sessions: &stubSessionIssuer{}, claims: &stubIdentityClaimIssuer{}},
		"sessions":   {federation: &stubFederationService{}, claims: &stubIdentityClaimIssuer{}},
		"claims":     {federation: &stubFederationService{}, sessions: &stubSessionIssuer{}},
	} {
		t.Run(name, func(t *testing.T) {
			if flow, err := NewFederatedFlow(dependencies.federation, dependencies.sessions, dependencies.claims); err == nil || flow != nil {
				t.Fatalf("NewFederatedFlow() = %#v, %v", flow, err)
			}
		})
	}
}

func TestFederatedBindingPassesCurrentAccessTokenToRecentAuthentication(t *testing.T) {
	federation := &stubFederationService{intent: auth.BindingIntent{
		ID:       "55555555-5555-4555-8555-555555555555",
		Provider: "google",
		Nonce:    "nonce",
	}}
	service, err := NewFederatedFlow(federation, &stubSessionIssuer{}, &stubIdentityClaimIssuer{})
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
	service, err := NewFederatedFlow(federation, &stubSessionIssuer{}, &stubIdentityClaimIssuer{})
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
	service, err := NewFederatedFlow(federation, &stubSessionIssuer{}, &stubIdentityClaimIssuer{})
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
	resolution     auth.FederatedLoginResolution
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
) (auth.FederatedLoginResolution, error) {
	return stub.resolution, nil
}

type stubSessionIssuer struct {
	created     auth.SessionCreateParams
	tokens      auth.SessionTokens
	createCalls int
}

func (stub *stubSessionIssuer) Create(
	_ context.Context,
	params auth.SessionCreateParams,
) (auth.SessionTokens, error) {
	stub.createCalls++
	stub.created = params
	return stub.tokens, nil
}

type stubIdentityClaimIssuer struct {
	identity   identityclaim.Identity
	issued     identityclaim.IssuedClaim
	err        error
	issueCalls int
}

func (stub *stubIdentityClaimIssuer) Issue(
	_ context.Context,
	identity identityclaim.Identity,
) (identityclaim.IssuedClaim, error) {
	stub.issueCalls++
	stub.identity = identity
	return stub.issued, stub.err
}
