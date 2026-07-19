package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestFederatedBindingRouteRequiresBearerSession(t *testing.T) {
	application := &stubFederatedHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Federation: application,
		Sessions:   &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/account/bindings/start",
		strings.NewReader(`{"provider":"apple"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.startBindingCalls != 0 {
		t.Fatalf("binding calls = %d", application.startBindingCalls)
	}
}

func TestFederatedLoginStartUsesProviderPathOnly(t *testing.T) {
	application := &stubFederatedHTTPApplication{intent: FederationIntent{
		ID:        "11111111-1111-4111-8111-111111111111",
		Provider:  "google",
		Nonce:     "0123456789abcdef0123456789abcdef",
		ExpiresAt: time.Now().Add(10 * time.Minute),
	}}
	router := NewRouter(RouterDependencies{
		Federation: application,
		Sessions:   &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/federated/google/start", nil)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated || !strings.Contains(response.Body.String(), application.intent.ID) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.provider != "google" {
		t.Fatalf("provider = %q", application.provider)
	}
}

func TestFederatedLoginCompleteReturnsRootAccountSession(t *testing.T) {
	session := AuthSession{
		AccountID:    "22222222-2222-4222-8222-222222222222",
		VaultID:      "33333333-3333-4333-8333-333333333333",
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}
	application := &stubFederatedHTTPApplication{completion: FederatedHTTPCompletion{Session: &session}}
	router := NewRouter(RouterDependencies{
		Federation: application,
		Sessions:   &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/federated/apple/complete",
		strings.NewReader(`{"intent_id":"44444444-4444-4444-8444-444444444444","nonce":"nonce","authorization_code":"code","device":{"device_id":"55555555-5555-4555-8555-555555555555","platform":"ios","display_name":"iPhone"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	wantBody := `{"account_id":"22222222-2222-4222-8222-222222222222","vault_id":"33333333-3333-4333-8333-333333333333","access_token":"access-token","access_token_expires_in":0,"refresh_token":"refresh-token"}` + "\n"
	if response.Body.String() != wantBody {
		t.Fatalf("session body = %s, want %s", response.Body.String(), wantBody)
	}
	if response.Header().Get("Cache-Control") != "" {
		t.Fatalf("200 Cache-Control = %q, want empty", response.Header().Get("Cache-Control"))
	}
	if application.loginCommand.Provider != "apple" || application.loginCommand.Device.Platform != "ios" {
		t.Fatalf("federated login command = %#v", application.loginCommand)
	}
	if application.loginCalls != 1 {
		t.Fatalf("application calls = %d", application.loginCalls)
	}
}

func TestFederatedLoginCompleteReturnsAcceptedIdentityClaim(t *testing.T) {
	const rawToken = "claim_token_visible_only_in_transport"
	claim := newIdentityClaimHTTPResult("google", 600, rawToken)
	application := &stubFederatedHTTPApplication{completion: FederatedHTTPCompletion{Claim: claim}}
	router := NewRouter(RouterDependencies{
		Federation: application,
		Sessions:   &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/federated/google/complete",
		strings.NewReader(`{"intent_id":"44444444-4444-4444-8444-444444444444","nonce":"nonce","authorization_code":"code","device":{"device_id":"55555555-5555-4555-8555-555555555555","platform":"android","display_name":"Pixel"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	wantBody := `{"status":"identity_claim_required","provider":"google","identity_claim_token":"claim_token_visible_only_in_transport","expires_in":600}` + "\n"
	if response.Code != http.StatusAccepted || response.Body.String() != wantBody {
		t.Fatalf("claim response status = %d or body schema differed", response.Code)
	}
	if strings.Contains(response.Body.String(), "identity_not_bound") || strings.Count(response.Body.String(), rawToken) != 1 {
		t.Fatal("claim response contained identity_not_bound or repeated the token")
	}
	if response.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("202 Cache-Control = %q, want no-store", response.Header().Get("Cache-Control"))
	}
	assertSingleJSONDocument(t, response.Body.String())
	if token, ok := claim.takeToken(); ok || token != "" {
		t.Fatal("handler did not consume the HTTP claim token exactly once")
	}
	if application.loginCalls != 1 {
		t.Fatalf("application calls = %d", application.loginCalls)
	}
}

func TestFederatedLoginCompleteRejectsMalformedRequest(t *testing.T) {
	application := &stubFederatedHTTPApplication{}
	router := NewRouter(RouterDependencies{Federation: application, Sessions: &fakeHTTPSessionService{}})
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/federated/apple/complete", strings.NewReader(`{"intent_id":`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest || application.loginCalls != 0 {
		t.Fatalf("status = %d, calls = %d, body = %s", response.Code, application.loginCalls, response.Body.String())
	}
}

func TestFederatedLoginCompletePreservesAuthenticationErrorMappings(t *testing.T) {
	for name, test := range map[string]struct {
		err    error
		status int
		code   string
	}{
		"unsupported provider":  {err: auth.ErrUnsupportedIdentityProvider, status: http.StatusBadRequest, code: "identity_provider_unsupported"},
		"provider verification": {err: auth.ErrFederatedAuthentication, status: http.StatusUnauthorized, code: "authentication_failed"},
		"expired intent":        {err: errors.Join(errors.New("expired intent"), auth.ErrFederatedAuthentication), status: http.StatusUnauthorized, code: "authentication_failed"},
	} {
		t.Run(name, func(t *testing.T) {
			application := &stubFederatedHTTPApplication{loginErr: test.err}
			router := NewRouter(RouterDependencies{Federation: application, Sessions: &fakeHTTPSessionService{}})
			request := httptest.NewRequest(
				http.MethodPost,
				"/v1/auth/federated/apple/complete",
				strings.NewReader(`{"intent_id":"44444444-4444-4444-8444-444444444444","nonce":"nonce","authorization_code":"code","device":{}}`),
			)
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			if response.Code != test.status || !strings.Contains(response.Body.String(), `"code":"`+test.code+`"`) {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
			if application.loginCalls != 1 {
				t.Fatalf("application calls = %d", application.loginCalls)
			}
		})
	}
}

func TestFederatedLoginCompleteRejectsImpossibleUnionWithoutTokenDisclosure(t *testing.T) {
	const rawToken = "must_not_appear_in_error"
	session := AuthSession{AccountID: "account-id"}
	claim := newIdentityClaimHTTPResult("apple", 600, rawToken)
	application := &stubFederatedHTTPApplication{completion: FederatedHTTPCompletion{Session: &session, Claim: claim}}
	router := NewRouter(RouterDependencies{Federation: application, Sessions: &fakeHTTPSessionService{}})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/federated/apple/complete",
		strings.NewReader(`{"intent_id":"44444444-4444-4444-8444-444444444444","nonce":"nonce","authorization_code":"code","device":{}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError || strings.Contains(response.Body.String(), rawToken) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	assertSingleJSONDocument(t, response.Body.String())
	if application.loginCalls != 1 {
		t.Fatalf("application calls = %d", application.loginCalls)
	}
	if token, ok := claim.takeToken(); !ok || token != rawToken {
		t.Fatal("impossible union consumed or changed the HTTP claim token")
	}
}

func TestFederatedLoginCompleteRejectsAlreadyTakenHTTPClaimToken(t *testing.T) {
	const rawToken = "already_taken_http_transport_secret"
	claim := newIdentityClaimHTTPResult("apple", 600, rawToken)
	if token, ok := claim.takeToken(); !ok || token != rawToken {
		t.Fatal("test setup could not take the HTTP claim token")
	}
	application := &stubFederatedHTTPApplication{completion: FederatedHTTPCompletion{Claim: claim}}
	router := NewRouter(RouterDependencies{Federation: application, Sessions: &fakeHTTPSessionService{}})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/federated/apple/complete",
		strings.NewReader(`{"intent_id":"44444444-4444-4444-8444-444444444444","nonce":"nonce","authorization_code":"code","device":{}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError || strings.Contains(response.Body.String(), rawToken) {
		t.Fatalf("status = %d or error disclosed the token", response.Code)
	}
	assertSingleJSONDocument(t, response.Body.String())
}

func TestFederatedBindingCompletePassesBearerAndIntent(t *testing.T) {
	application := &stubFederatedHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Federation: application,
		Sessions:   &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/account/bindings/complete",
		strings.NewReader(`{"intent_id":"66666666-6666-4666-8666-666666666666","provider":"apple","nonce":"nonce","authorization_code":"code"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer current-access-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.bindingCommand.AccessToken != "current-access-token" ||
		application.bindingCommand.IntentID != "66666666-6666-4666-8666-666666666666" {
		t.Fatalf("binding command = %#v", application.bindingCommand)
	}
}

func TestFederatedUnbindingPassesBearerAndProvider(t *testing.T) {
	application := &stubFederatedHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Federation: application,
		Sessions:   &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(http.MethodDelete, "/v1/account/bindings/huawei", nil)
	request.Header.Set("Authorization", "Bearer current-access-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.unbindAccessToken != "current-access-token" || application.unbindProvider != "huawei" {
		t.Fatalf("unbind token = %q, provider = %q", application.unbindAccessToken, application.unbindProvider)
	}
}

func TestPasskeyRegistrationRouteRequiresBearerSession(t *testing.T) {
	application := &stubPasskeyHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Passkeys: application,
		Sessions: &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/account/passkeys/registration/start",
		nil,
	)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.beginRegistrationCalls != 0 {
		t.Fatalf("registration calls = %d", application.beginRegistrationCalls)
	}
}

func TestPasskeyLoginStartIsPublicAndReturnsOptions(t *testing.T) {
	application := &stubPasskeyHTTPApplication{ceremony: PasskeyCeremony{
		ChallengeID: "77777777-7777-4777-8777-777777777777",
		Options:     []byte(`{"publicKey":{"challenge":"discoverable"}}`),
		ExpiresAt:   time.Now().Add(5 * time.Minute),
	}}
	router := NewRouter(RouterDependencies{
		Passkeys: application,
		Sessions: &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/passkeys/login/start", nil)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated || !strings.Contains(response.Body.String(), application.ceremony.ChallengeID) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestPasskeyLoginCompleteReturnsCloverySession(t *testing.T) {
	application := &stubPasskeyHTTPApplication{session: AuthSession{
		AccountID:    "88888888-8888-4888-8888-888888888888",
		VaultID:      "99999999-9999-4999-8999-999999999999",
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
	}}
	router := NewRouter(RouterDependencies{
		Passkeys: application,
		Sessions: &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/passkeys/login/complete",
		strings.NewReader(`{"challenge_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","response":{"id":"assertion"},"device":{"device_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","platform":"ios","display_name":"iPhone"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), application.session.VaultID) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.loginCommand.ChallengeID != "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" ||
		application.loginCommand.Device.Platform != "ios" {
		t.Fatalf("passkey login command = %#v", application.loginCommand)
	}
}

func TestPasskeyRegistrationCompletePassesBearerAndAttestation(t *testing.T) {
	application := &stubPasskeyHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Passkeys: application,
		Sessions: &fakeHTTPSessionService{},
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/account/passkeys/registration/complete",
		strings.NewReader(`{"challenge_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","response":{"id":"attestation"},"device_metadata":{"platform":"ios"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer current-access-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if application.registrationCommand.AccessToken != "current-access-token" ||
		application.registrationCommand.ChallengeID != "cccccccc-cccc-4ccc-8ccc-cccccccccccc" {
		t.Fatalf("registration command = %#v", application.registrationCommand)
	}
}

type stubFederatedHTTPApplication struct {
	startBindingCalls int
	intent            FederationIntent
	provider          string
	completion        FederatedHTTPCompletion
	loginErr          error
	loginCalls        int
	loginCommand      FederatedLoginHTTPCommand
	bindingCommand    FederatedBindingHTTPCommand
	unbindAccessToken string
	unbindProvider    string
}

func (stub *stubFederatedHTTPApplication) StartFederatedLogin(
	_ context.Context,
	provider string,
) (FederationIntent, error) {
	stub.provider = provider
	return stub.intent, nil
}

func (stub *stubFederatedHTTPApplication) CompleteFederatedLogin(
	_ context.Context,
	command FederatedLoginHTTPCommand,
) (FederatedHTTPCompletion, error) {
	stub.loginCalls++
	stub.loginCommand = command
	return stub.completion, stub.loginErr
}

func (stub *stubFederatedHTTPApplication) StartBinding(
	context.Context,
	string,
	string,
) (FederationIntent, error) {
	stub.startBindingCalls++
	return FederationIntent{}, nil
}

func (stub *stubFederatedHTTPApplication) CompleteBinding(
	_ context.Context,
	command FederatedBindingHTTPCommand,
) error {
	stub.bindingCommand = command
	return nil
}

func (stub *stubFederatedHTTPApplication) Unbind(
	_ context.Context,
	accessToken string,
	provider string,
) error {
	stub.unbindAccessToken = accessToken
	stub.unbindProvider = provider
	return nil
}

type stubPasskeyHTTPApplication struct {
	beginRegistrationCalls int
	ceremony               PasskeyCeremony
	session                AuthSession
	loginCommand           PasskeyLoginHTTPCommand
	registrationCommand    PasskeyRegistrationHTTPCommand
}

func (stub *stubPasskeyHTTPApplication) BeginLogin(context.Context) (PasskeyCeremony, error) {
	return stub.ceremony, nil
}

func (stub *stubPasskeyHTTPApplication) CompleteLogin(
	_ context.Context,
	command PasskeyLoginHTTPCommand,
) (AuthSession, error) {
	stub.loginCommand = command
	return stub.session, nil
}

func (stub *stubPasskeyHTTPApplication) BeginRegistration(
	context.Context,
	string,
) (PasskeyCeremony, error) {
	stub.beginRegistrationCalls++
	return PasskeyCeremony{}, nil
}

func (stub *stubPasskeyHTTPApplication) CompleteRegistration(
	_ context.Context,
	command PasskeyRegistrationHTTPCommand,
) error {
	stub.registrationCommand = command
	return nil
}

func assertSingleJSONDocument(t *testing.T, body string) {
	t.Helper()
	decoder := json.NewDecoder(strings.NewReader(body))
	var document any
	if err := decoder.Decode(&document); err != nil {
		t.Fatalf("decode response JSON: %v", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		t.Fatalf("response contains more than one JSON document: %v", err)
	}
}
