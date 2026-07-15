package auth

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestRecoveryPasswordResetRevokesSessionsAndConsumesProof(t *testing.T) {
	databaseHandle := openAuthTestDatabase(t)
	registration := registerSessionTestAccount(t, databaseHandle)
	loginService, err := NewLoginService(databaseHandle)
	if err != nil {
		t.Fatalf("create login service: %v", err)
	}
	signer, err := NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create access token signer: %v", err)
	}
	sessionService := NewSessionService(databaseHandle, signer)
	session, err := sessionService.Create(context.Background(), SessionCreateParams{
		AccountID:   registration.AccountID,
		VaultID:     registration.VaultID,
		DeviceID:    "99999999-7777-4777-8777-777777777777",
		Platform:    "ios",
		DisplayName: "Reset iPhone",
	})
	if err != nil {
		t.Fatalf("create pre-reset session: %v", err)
	}

	recoveryService := NewRecoveryCodeService(databaseHandle)
	codes, err := recoveryService.Replace(context.Background(), registration.AccountID)
	if err != nil {
		t.Fatalf("create recovery codes: %v", err)
	}
	recoveredAccountID, err := recoveryService.Consume(context.Background(), registration.LoginID, codes[0])
	if err != nil {
		t.Fatalf("consume recovery code: %v", err)
	}
	resetService := NewPasswordResetService(databaseHandle)
	proof, err := resetService.CreateRecoveryProof(context.Background(), recoveredAccountID)
	if err != nil {
		t.Fatalf("create recovery proof: %v", err)
	}

	const newPassword = "five private words stay together"
	if err := resetService.Complete(
		context.Background(),
		proof.ResetIntentID,
		proof.Proof,
		newPassword,
	); err != nil {
		t.Fatalf("complete password reset: %v", err)
	}
	if _, err := loginService.Login(context.Background(), registration.LoginID, registration.Password); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("old password error = %v", err)
	}
	if _, err := loginService.Login(context.Background(), registration.LoginID, newPassword); err != nil {
		t.Fatalf("new password login: %v", err)
	}
	if _, err := sessionService.Authenticate(context.Background(), session.AccessToken); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("old access token error = %v", err)
	}
	if _, err := sessionService.Refresh(context.Background(), session.RefreshToken); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("old refresh token error = %v", err)
	}
	if err := resetService.Complete(context.Background(), proof.ResetIntentID, proof.Proof, newPassword); !errors.Is(err, ErrInvalidResetProof) {
		t.Fatalf("reused reset proof error = %v", err)
	}

	var auditPayload string
	if err := databaseHandle.QueryRow(
		"SELECT payload::text FROM audit_events WHERE account_id = $1 AND event_type = 'password_reset' ORDER BY created_at DESC LIMIT 1",
		registration.AccountID,
	).Scan(&auditPayload); err != nil {
		t.Fatalf("read password reset audit: %v", err)
	}
	if strings.Contains(auditPayload, newPassword) || strings.Contains(auditPayload, proof.Proof) {
		t.Fatalf("audit payload contains secret material: %s", auditPayload)
	}
}
