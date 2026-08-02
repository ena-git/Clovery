package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

const testRegistrationClaimToken = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

func TestCreateAccountCommandRedactsClaimTokenFromNestedValuesAndPointers(t *testing.T) {
	rawToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0x71}, 32))
	token, err := identityclaim.ParseRegistrationToken(rawToken)
	if err != nil {
		t.Fatalf("parse registration token: %v", err)
	}
	command := CreateAccountCommand{IdentityClaimToken: &token}
	assertClaimTokenRedactedFromValues(t, rawToken, command, &command)
}

func TestAuthHandlerRejectsMalformedCanonicalClaimTokenGenerically(t *testing.T) {
	application := &fakeAuthApplication{}
	router := NewRouter(RouterDependencies{Auth: application})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/accounts",
		strings.NewReader(`{"login_id":"garden_user","password":"four quiet words together","recovery_method":"bound_identity","identity_claim_token":"not-canonical","registration_request_id":"33333333-3333-4333-8333-333333333333","source_kind":"new_install","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest || !strings.Contains(response.Body.String(), `"code":"invalid_auth_request"`) {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if len(application.registerCommands) != 0 {
		t.Fatal("malformed claim token reached the application")
	}
}

func TestAuthHandlerMapsClaimRegistrationErrorsWithoutAccountDetails(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		statusCode int
		code       string
		message    string
	}{
		{"invalid", identityclaim.ErrInvalidClaim, http.StatusBadRequest, "invalid_auth_request", "The request is invalid."},
		{"expired", identityclaim.ErrExpiredClaim, http.StatusUnauthorized, "identity_claim_expired", "The identity claim has expired. Reauthorize and try again."},
		{"consumed", identityclaim.ErrConsumedClaim, http.StatusConflict, "identity_claim_consumed", "The identity claim has already been used."},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			application := &fakeAuthApplication{registerErr: fmt.Errorf("wrapped claim failure: %w", test.err)}
			router := NewRouter(RouterDependencies{Auth: application})
			body := `{"login_id":"garden_user","password":"four quiet words together","recovery_method":"bound_identity","identity_claim_token":"` + testRegistrationClaimToken + `","registration_request_id":"33333333-3333-4333-8333-333333333333","source_kind":"new_install","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`
			request := httptest.NewRequest(http.MethodPost, "/v1/auth/accounts", strings.NewReader(body))
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			if response.Code != test.statusCode {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
			var responseBody map[string]string
			if err := json.Unmarshal(response.Body.Bytes(), &responseBody); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			if responseBody["code"] != test.code || responseBody["message"] != test.message {
				t.Fatalf("response body = %#v", responseBody)
			}
			if strings.Contains(response.Body.String(), "account") {
				t.Fatalf("response disclosed account details: %s", response.Body.String())
			}
		})
	}
}

func assertClaimTokenRedactedFromValues(t *testing.T, rawToken string, values ...any) {
	t.Helper()
	for _, value := range values {
		for _, format := range []string{"%v", "%+v", "%#v", "%q"} {
			formatted := fmt.Sprintf(format, value)
			if strings.Contains(formatted, rawToken) || !strings.Contains(formatted, "<redacted>") {
				t.Fatalf("format %s for %T was not redacted: %q", format, value, formatted)
			}
		}
		encoded, err := json.Marshal(value)
		if err != nil {
			t.Fatalf("marshal %T: %v", value, err)
		}
		if strings.Contains(string(encoded), rawToken) ||
			(!strings.Contains(string(encoded), "<redacted>") && !strings.Contains(string(encoded), `\u003credacted\u003e`)) {
			t.Fatalf("JSON for %T was not redacted: %s", value, encoded)
		}
	}
	var logOutput bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logOutput, nil))
	for _, value := range values {
		logger.Info("claim registration value", "value", value)
	}
	if strings.Contains(logOutput.String(), rawToken) ||
		(!strings.Contains(logOutput.String(), "<redacted>") && !strings.Contains(logOutput.String(), `\u003credacted\u003e`)) {
		t.Fatalf("structured log was not redacted: %s", logOutput.String())
	}
}

func TestAuthHandlerCreatesAccountWithoutEchoingSecrets(t *testing.T) {
	application := &fakeAuthApplication{
		session: AuthSession{
			AccountID:            "11111111-1111-4111-8111-111111111111",
			VaultID:              "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
			AccessToken:          "access-secret",
			AccessTokenExpiresIn: 900,
			RefreshToken:         "refresh-secret",
		},
	}
	router := NewRouter(RouterDependencies{Auth: application})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/accounts",
		strings.NewReader(`{"login_id":"garden_user","password":"four quiet words together","recovery_method":"recovery_codes","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if strings.Contains(response.Body.String(), "four quiet words together") {
		t.Fatal("response echoed the password")
	}
	if !strings.Contains(response.Body.String(), `"account_id":"11111111-1111-4111-8111-111111111111"`) {
		t.Fatalf("response body = %s", response.Body.String())
	}
	if len(application.registerCommands) != 1 {
		t.Fatalf("register command count = %d", len(application.registerCommands))
	}
	command := application.registerCommands[0]
	if command.IdentityClaimToken != nil || command.RegistrationRequestID != nil || command.SourceKind != nil {
		t.Fatalf("plain registration command = %#v", command)
	}
}

func TestAuthHandlerRejectsMalformedClaimRegistrationCombinations(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{
			name: "claim token without registration request ID",
			body: `{"login_id":"garden_user","password":"four quiet words together","recovery_method":"bound_identity","identity_claim_token":"` + testRegistrationClaimToken + `","source_kind":"new_install","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
		},
		{
			name: "registration request ID without claim token",
			body: `{"login_id":"garden_user","password":"four quiet words together","recovery_method":"bound_identity","registration_request_id":"33333333-3333-4333-8333-333333333333","source_kind":"new_install","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
		},
		{
			name: "claim registration without bound identity recovery",
			body: `{"login_id":"garden_user","password":"four quiet words together","recovery_method":"recovery_codes","identity_claim_token":"` + testRegistrationClaimToken + `","registration_request_id":"33333333-3333-4333-8333-333333333333","source_kind":"new_install","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
		},
		{
			name: "plain registration with bound identity recovery",
			body: `{"login_id":"garden_user","password":"four quiet words together","recovery_method":"bound_identity","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
		},
		{
			name: "claim registration without source kind",
			body: `{"login_id":"garden_user","password":"four quiet words together","recovery_method":"bound_identity","identity_claim_token":"` + testRegistrationClaimToken + `","registration_request_id":"33333333-3333-4333-8333-333333333333","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			application := &fakeAuthApplication{}
			router := NewRouter(RouterDependencies{Auth: application})
			request := httptest.NewRequest(http.MethodPost, "/v1/auth/accounts", strings.NewReader(test.body))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			if response.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
			if !strings.Contains(response.Body.String(), `"code":"invalid_auth_request"`) {
				t.Fatalf("response body = %s", response.Body.String())
			}
			if len(application.registerCommands) != 0 {
				t.Fatal("malformed registration reached the application")
			}
		})
	}
}

func TestAuthHandlerEnforcesRegistrationPasswordLength(t *testing.T) {
	tests := []struct {
		name       string
		password   string
		wantStatus int
	}{
		{name: "seven characters", password: "1234567", wantStatus: http.StatusBadRequest},
		{name: "eight characters", password: "valid888", wantStatus: http.StatusCreated},
		{name: "256 characters", password: strings.Repeat("a", 256), wantStatus: http.StatusCreated},
		{name: "257 characters", password: strings.Repeat("a", 257), wantStatus: http.StatusBadRequest},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			application := &fakeAuthApplication{}
			router := NewRouter(RouterDependencies{Auth: application})
			body := `{"login_id":"garden_user","password":"` + test.password + `","recovery_method":"recovery_codes","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`
			request := httptest.NewRequest(http.MethodPost, "/v1/auth/accounts", strings.NewReader(body))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			if response.Code != test.wantStatus {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
		})
	}
}

func TestAuthHandlerUsesSameUnauthorizedResponseForInvalidCredentials(t *testing.T) {
	application := &fakeAuthApplication{loginErr: auth.ErrInvalidCredentials}
	router := NewRouter(RouterDependencies{Auth: application})

	bodies := []string{
		`{"login_id":"existing_user","password":"wrong password here","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
		`{"login_id":"missing_user","password":"wrong password here","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`,
	}
	var firstBody string
	for index, body := range bodies {
		request := httptest.NewRequest(http.MethodPost, "/v1/auth/password/login", strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
		}
		if index == 0 {
			firstBody = response.Body.String()
		} else if response.Body.String() != firstBody {
			t.Fatalf("credential failures differ: %q != %q", response.Body.String(), firstBody)
		}
	}
}

func TestAuthHandlerReturnsRetryAfterWhenRateLimited(t *testing.T) {
	application := &fakeAuthApplication{loginErr: auth.ErrRateLimited}
	router := NewRouter(RouterDependencies{Auth: application})
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/password/login",
		strings.NewReader(`{"login_id":"limited_user","password":"wrong password here","device":{"device_id":"22222222-2222-4222-8222-222222222222","platform":"ios","display_name":"iPhone"}}`),
	)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if response.Header().Get("Retry-After") != "900" {
		t.Fatalf("Retry-After = %q", response.Header().Get("Retry-After"))
	}
}

type fakeAuthApplication struct {
	session          AuthSession
	loginErr         error
	registerErr      error
	registerCommands []CreateAccountCommand
}

func (application *fakeAuthApplication) Register(_ context.Context, command CreateAccountCommand) (AuthSession, error) {
	application.registerCommands = append(application.registerCommands, command)
	return application.session, application.registerErr
}

func (application *fakeAuthApplication) Login(context.Context, PasswordLoginCommand) (AuthSession, error) {
	return application.session, application.loginErr
}

func (application *fakeAuthApplication) StartPasswordReset(
	context.Context,
	PasswordResetStartCommand,
) (PasswordResetStartResult, error) {
	return PasswordResetStartResult{}, errors.New("not implemented in fake")
}

func (application *fakeAuthApplication) CompletePasswordReset(
	context.Context,
	PasswordResetCompleteCommand,
) error {
	return errors.New("not implemented in fake")
}

func (application *fakeAuthApplication) ReplaceRecoveryCodes(
	context.Context,
	string,
	string,
) ([]string, error) {
	return nil, errors.New("not implemented in fake")
}

func (application *fakeAuthApplication) ConsumeRecoveryCode(
	context.Context,
	RecoveryCodeConsumeCommand,
) (RecoveryProof, error) {
	return RecoveryProof{}, errors.New("not implemented in fake")
}
