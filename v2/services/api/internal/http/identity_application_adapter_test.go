package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/application/identityflow"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

func TestFederatedApplicationAdapterMapsDeviceToIdentityFlow(t *testing.T) {
	session := identityflow.SessionResult{
		AccountID:    "11111111-1111-4111-8111-111111111111",
		VaultID:      "22222222-2222-4222-8222-222222222222",
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}
	flow := &stubFederatedFlowApplication{completion: identityflow.FederatedCompletion{Session: &session}}
	adapter := NewFederatedApplication(flow)

	result, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{
		IntentID:          "33333333-3333-4333-8333-333333333333",
		Provider:          "apple",
		AuthorizationCode: "authorization-code",
		Nonce:             "nonce",
		Device: DeviceRegistration{
			DeviceID:    "44444444-4444-4444-8444-444444444444",
			Platform:    "ios",
			DisplayName: "iPhone",
		},
	})
	if err != nil {
		t.Fatalf("complete federated login: %v", err)
	}
	if result.Session == nil || result.Claim != nil || result.Session.VaultID != session.VaultID ||
		flow.command.Device.ID != "44444444-4444-4444-8444-444444444444" {
		t.Fatalf("adapter result = %#v, command = %#v", result, flow.command)
	}
}

func TestFederatedApplicationAdapterExtractsClaimTokenOnce(t *testing.T) {
	issued := issueAdapterTestClaim(t, "google")
	flow := &stubFederatedFlowApplication{completion: identityflow.FederatedCompletion{
		Claim: &identityflow.IdentityClaimResult{Issued: issued},
	}}
	adapter := NewFederatedApplication(flow)

	result, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{})
	if err != nil {
		t.Fatalf("complete federated login: %v", err)
	}
	if result.Session != nil || result.Claim == nil || result.Claim.Provider != "google" ||
		result.Claim.IdentityClaimToken == "" || result.Claim.ExpiresIn != 600 {
		t.Fatal("adapter did not return the expected claim metadata and token")
	}
	firstToken := result.Claim.IdentityClaimToken

	second, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{})
	if !errors.Is(err, errIdentityClaimTokenUnavailable) {
		t.Fatalf("second mapping error = %v", err)
	}
	if second != (FederatedHTTPCompletion{}) {
		t.Fatal("second mapping returned a partial result")
	}
	if strings.Contains(err.Error(), firstToken) {
		t.Fatal("token extraction error disclosed the raw token")
	}
}

func TestFederatedApplicationAdapterRejectsImpossibleCompletions(t *testing.T) {
	session := identityflow.SessionResult{AccountID: "account-id"}
	issued := issueAdapterTestClaim(t, "apple")
	for name, completion := range map[string]identityflow.FederatedCompletion{
		"empty": {},
		"both": {
			Session: &session,
			Claim:   &identityflow.IdentityClaimResult{Issued: issued},
		},
	} {
		t.Run(name, func(t *testing.T) {
			adapter := NewFederatedApplication(&stubFederatedFlowApplication{completion: completion})
			result, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{})
			if !errors.Is(err, errInvalidFederatedCompletion) {
				t.Fatalf("mapping error = %v", err)
			}
			if result != (FederatedHTTPCompletion{}) {
				t.Fatalf("mapping result = %#v", result)
			}
		})
	}
	if token, ok := issued.TakeToken(); !ok || token == "" {
		t.Fatal("impossible union consumed the claim token")
	}
}

func TestPasskeyApplicationAdapterPreservesOpaqueRegistrationResponse(t *testing.T) {
	flow := &stubPasskeyFlowApplication{}
	adapter := NewPasskeyApplication(flow)
	command := PasskeyRegistrationHTTPCommand{
		AccessToken:    "current-access-token",
		ChallengeID:    "55555555-5555-4555-8555-555555555555",
		Response:       json.RawMessage(`{"id":"attestation"}`),
		DeviceMetadata: json.RawMessage(`{"platform":"ios"}`),
	}

	if err := adapter.CompleteRegistration(context.Background(), command); err != nil {
		t.Fatalf("complete passkey registration: %v", err)
	}
	if string(flow.registrationCommand.Response) != string(command.Response) ||
		string(flow.registrationCommand.DeviceMetadata) != string(command.DeviceMetadata) {
		t.Fatalf("identity flow command = %#v", flow.registrationCommand)
	}
}

type stubFederatedFlowApplication struct {
	command    identityflow.FederatedLoginCommand
	completion identityflow.FederatedCompletion
}

func (*stubFederatedFlowApplication) StartFederatedLogin(
	context.Context,
	string,
) (identityflow.FederationIntent, error) {
	return identityflow.FederationIntent{}, nil
}

func (stub *stubFederatedFlowApplication) CompleteFederatedLogin(
	_ context.Context,
	command identityflow.FederatedLoginCommand,
) (identityflow.FederatedCompletion, error) {
	stub.command = command
	return stub.completion, nil
}

func (*stubFederatedFlowApplication) StartBinding(
	context.Context,
	string,
	string,
) (identityflow.FederationIntent, error) {
	return identityflow.FederationIntent{}, nil
}

func (*stubFederatedFlowApplication) CompleteBinding(
	context.Context,
	identityflow.FederatedBindingCommand,
) error {
	return nil
}

func (*stubFederatedFlowApplication) Unbind(context.Context, string, string) error {
	return nil
}

type stubPasskeyFlowApplication struct {
	registrationCommand identityflow.PasskeyRegistrationCommand
}

func (*stubPasskeyFlowApplication) BeginLogin(context.Context) (identityflow.PasskeyCeremony, error) {
	return identityflow.PasskeyCeremony{}, nil
}

func (*stubPasskeyFlowApplication) CompleteLogin(
	context.Context,
	identityflow.PasskeyLoginCommand,
) (identityflow.SessionResult, error) {
	return identityflow.SessionResult{}, nil
}

func (*stubPasskeyFlowApplication) BeginRegistration(
	context.Context,
	string,
) (identityflow.PasskeyCeremony, error) {
	return identityflow.PasskeyCeremony{}, nil
}

func (stub *stubPasskeyFlowApplication) CompleteRegistration(
	_ context.Context,
	command identityflow.PasskeyRegistrationCommand,
) error {
	stub.registrationCommand = command
	return nil
}

type adapterClaimRepository struct{}

func (adapterClaimRepository) Issue(context.Context, identityclaim.StoredClaim) error {
	return nil
}

func issueAdapterTestClaim(t *testing.T, provider string) identityclaim.IssuedClaim {
	t.Helper()
	issued, err := identityclaim.NewService(adapterClaimRepository{}).Issue(context.Background(), identityclaim.Identity{
		Provider: provider,
		Issuer:   "https://issuer.example",
		Subject:  "stable-subject",
		IntentID: "55555555-5555-4555-8555-555555555555",
	})
	if err != nil {
		t.Fatalf("issue identity claim: %v", err)
	}
	if issued.ExpiresIn != 10*time.Minute {
		t.Fatalf("claim expiry = %v", issued.ExpiresIn)
	}
	return issued
}
