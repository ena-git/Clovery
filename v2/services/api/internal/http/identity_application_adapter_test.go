package httpapi

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/clovery/clovery/services/api/internal/application/identityflow"
)

func TestFederatedApplicationAdapterMapsDeviceToIdentityFlow(t *testing.T) {
	flow := &stubFederatedFlowApplication{session: identityflow.SessionResult{
		AccountID:    "11111111-1111-4111-8111-111111111111",
		VaultID:      "22222222-2222-4222-8222-222222222222",
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}}
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
	if result.VaultID != flow.session.VaultID || flow.command.Device.ID != "44444444-4444-4444-8444-444444444444" {
		t.Fatalf("adapter result = %#v, command = %#v", result, flow.command)
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
	command identityflow.FederatedLoginCommand
	session identityflow.SessionResult
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
) (identityflow.SessionResult, error) {
	stub.command = command
	return stub.session, nil
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
