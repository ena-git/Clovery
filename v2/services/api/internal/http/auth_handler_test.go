package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/auth"
)

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
	session  AuthSession
	loginErr error
}

func (application *fakeAuthApplication) Register(context.Context, CreateAccountCommand) (AuthSession, error) {
	return application.session, nil
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
