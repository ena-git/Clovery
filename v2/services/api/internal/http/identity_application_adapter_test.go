package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"sync/atomic"
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

	result, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{Provider: " Google "})
	if err != nil {
		t.Fatalf("complete federated login: %v", err)
	}
	if result.Session != nil || result.Claim == nil || result.Claim.Provider != "google" ||
		result.Claim.ExpiresIn != 600 {
		t.Fatal("adapter did not return the expected claim metadata and token")
	}
	firstToken, ok := result.Claim.takeToken()
	if !ok || firstToken == "" {
		t.Fatal("HTTP claim token was unavailable")
	}

	second, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{Provider: "google"})
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

func TestFederatedApplicationAdapterValidatesClaimMetadataBeforeTakingToken(t *testing.T) {
	for name, mutate := range map[string]func(*identityclaim.IssuedClaim){
		"empty provider":       func(claim *identityclaim.IssuedClaim) { claim.Provider = "" },
		"unsupported provider": func(claim *identityclaim.IssuedClaim) { claim.Provider = "github" },
		"mismatched provider":  func(claim *identityclaim.IssuedClaim) { claim.Provider = "google" },
		"zero expiry":          func(claim *identityclaim.IssuedClaim) { claim.ExpiresIn = 0 },
		"non-600 expiry":       func(claim *identityclaim.IssuedClaim) { claim.ExpiresIn = 5 * time.Minute },
	} {
		t.Run(name, func(t *testing.T) {
			issued := issueAdapterTestClaim(t, "apple")
			mutate(&issued)
			flow := &stubFederatedFlowApplication{completion: identityflow.FederatedCompletion{
				Claim: &identityflow.IdentityClaimResult{Issued: issued},
			}}
			adapter := NewFederatedApplication(flow)

			result, err := adapter.CompleteFederatedLogin(
				context.Background(),
				FederatedLoginHTTPCommand{Provider: "apple"},
			)
			if !errors.Is(err, errInvalidIdentityClaimMetadata) {
				t.Fatalf("metadata validation error = %v", err)
			}
			if result != (FederatedHTTPCompletion{}) {
				t.Fatal("metadata validation returned a partial result")
			}
			rawToken, ok := issued.TakeToken()
			if !ok || rawToken == "" {
				t.Fatal("metadata validation consumed the domain claim token")
			}
			if strings.Contains(err.Error(), rawToken) {
				t.Fatal("metadata validation error disclosed the raw token")
			}
		})
	}
}

func TestFederatedHTTPCompletionRedactsClaimTokenFromFormattingLoggingAndJSON(t *testing.T) {
	const rawToken = "http_transport_secret_must_be_redacted"
	claim := newIdentityClaimHTTPResult("huawei", 600, rawToken)
	completion := FederatedHTTPCompletion{Claim: claim}

	formatted := []string{
		fmt.Sprintf("%v", completion),
		fmt.Sprintf("%+v", completion),
		fmt.Sprintf("%#v", completion),
		fmt.Sprintf("%q", completion),
		fmt.Sprintf("%s", completion),
		fmt.Sprintf("%v", *claim),
		fmt.Sprintf("%#v", *claim),
	}
	var logBuffer bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logBuffer, nil))
	logger.Info("federated completion", "completion", completion)
	jsonValue, err := json.Marshal(completion)
	if err != nil {
		t.Fatalf("marshal federated completion: %v", err)
	}
	formatted = append(formatted, logBuffer.String(), string(jsonValue))
	for _, value := range formatted {
		if strings.Contains(value, rawToken) {
			t.Fatal("generic formatting, logging, or JSON disclosed the HTTP claim token")
		}
	}
	if token, ok := claim.takeToken(); !ok || token != rawToken {
		t.Fatal("redaction consumed or changed the HTTP claim token")
	}
}

func TestIdentityClaimHTTPResultTakeTokenSucceedsOnceAcrossConcurrentCopies(t *testing.T) {
	const rawToken = "concurrent_http_transport_secret"
	original := newIdentityClaimHTTPResult("apple", 600, rawToken)
	const workers = 64
	start := make(chan struct{})
	var waitGroup sync.WaitGroup
	var successes atomic.Int32
	for index := 0; index < workers; index++ {
		copyOfClaim := *original
		waitGroup.Add(1)
		go func(claim IdentityClaimHTTPResult) {
			defer waitGroup.Done()
			<-start
			token, ok := claim.takeToken()
			if ok {
				if token != rawToken {
					t.Errorf("takeToken() returned an unexpected token")
				}
				successes.Add(1)
			} else if token != "" {
				t.Error("failed takeToken() returned token data")
			}
		}(copyOfClaim)
	}
	close(start)
	waitGroup.Wait()
	if successes.Load() != 1 {
		t.Fatalf("successful token extractions = %d, want 1", successes.Load())
	}
	if token, ok := original.takeToken(); ok || token != "" {
		t.Fatal("takeToken() succeeded after concurrent extraction")
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
			result, err := adapter.CompleteFederatedLogin(context.Background(), FederatedLoginHTTPCommand{Provider: "apple"})
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
