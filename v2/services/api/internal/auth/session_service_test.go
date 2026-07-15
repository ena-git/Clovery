package auth

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"
)

func TestSessionRefreshRotatesTokenAndRejectsReuse(t *testing.T) {
	databaseHandle := openAuthTestDatabase(t)
	registration := registerSessionTestAccount(t, databaseHandle)
	now := time.Date(2026, time.July, 12, 12, 0, 0, 0, time.UTC)
	signer, err := NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create access token signer: %v", err)
	}
	service := NewSessionService(databaseHandle, signer)
	service.now = func() time.Time { return now }

	created, err := service.Create(context.Background(), SessionCreateParams{
		AccountID:   registration.AccountID,
		VaultID:     registration.VaultID,
		DeviceID:    "77777777-7777-4777-8777-777777777777",
		Platform:    "ios",
		DisplayName: "Test iPhone",
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if created.AccessToken == "" || created.RefreshToken == "" {
		t.Fatal("session tokens are empty")
	}

	var storedHash []byte
	if err := databaseHandle.QueryRow(
		"SELECT refresh_token_hash FROM sessions WHERE id = $1",
		created.SessionID,
	).Scan(&storedHash); err != nil {
		t.Fatalf("read refresh token hash: %v", err)
	}
	if bytes.Equal(storedHash, []byte(created.RefreshToken)) {
		t.Fatal("refresh token was stored in plaintext")
	}

	refreshed, err := service.Refresh(context.Background(), created.RefreshToken)
	if err != nil {
		t.Fatalf("refresh session: %v", err)
	}
	if refreshed.RefreshToken == created.RefreshToken || refreshed.SessionID == created.SessionID {
		t.Fatal("refresh did not rotate the session and token")
	}
	claims, err := service.Authenticate(context.Background(), refreshed.AccessToken)
	if err != nil {
		t.Fatalf("authenticate refreshed access token: %v", err)
	}
	if claims.AccountID != registration.AccountID || claims.VaultID != registration.VaultID {
		t.Fatalf("access token claims = %#v", claims)
	}

	if _, err := service.Refresh(context.Background(), created.RefreshToken); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("reused refresh token error = %v", err)
	}
	if _, err := service.Authenticate(context.Background(), refreshed.AccessToken); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("replay-compromised token family error = %v", err)
	}
}

func TestRevokedDeviceInvalidatesAccessAndRefreshTokens(t *testing.T) {
	databaseHandle := openAuthTestDatabase(t)
	registration := registerSessionTestAccount(t, databaseHandle)
	signer, err := NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create access token signer: %v", err)
	}
	service := NewSessionService(databaseHandle, signer)
	created, err := service.Create(context.Background(), SessionCreateParams{
		AccountID:   registration.AccountID,
		VaultID:     registration.VaultID,
		DeviceID:    "88888888-8888-4888-8888-888888888888",
		Platform:    "ios",
		DisplayName: "Revoked iPhone",
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	if err := service.RevokeDevice(context.Background(), registration.AccountID, "88888888-8888-4888-8888-888888888888"); err != nil {
		t.Fatalf("revoke device: %v", err)
	}
	if _, err := service.Authenticate(context.Background(), created.AccessToken); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("revoked access token error = %v", err)
	}
	if _, err := service.Refresh(context.Background(), created.RefreshToken); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("revoked refresh token error = %v", err)
	}
}

func registerSessionTestAccount(t *testing.T, databaseHandle *sql.DB) Registration {
	t.Helper()
	loginService, err := NewLoginService(databaseHandle)
	if err != nil {
		t.Fatalf("create login service: %v", err)
	}
	registration := Registration{
		AccountID: "77777777-1111-4111-8111-111111111111",
		VaultID:   "77777777-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		LoginID:   "session_user",
		Password:  "four quiet words together",
	}
	if err := loginService.Register(context.Background(), registration); err != nil {
		t.Fatalf("register session account: %v", err)
	}
	return registration
}
