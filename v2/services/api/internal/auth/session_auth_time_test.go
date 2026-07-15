package auth

import (
	"testing"
	"time"
)

func TestIssueTokensPreservesOriginalAuthenticationTime(t *testing.T) {
	signer, err := NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create access token signer: %v", err)
	}
	service := NewSessionService(nil, signer)
	authenticatedAt := time.Date(2026, time.July, 14, 9, 0, 0, 0, time.UTC)
	refreshedAt := authenticatedAt.Add(30 * time.Minute)

	tokens, err := service.issueTokens(sessionRecord{
		SessionID:       "77777777-7777-4777-8777-777777777777",
		DeviceID:        "88888888-8888-4888-8888-888888888888",
		AccountID:       "99999999-9999-4999-8999-999999999999",
		VaultID:         "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		AuthenticatedAt: authenticatedAt,
	}, "refresh-token", refreshedAt)
	if err != nil {
		t.Fatalf("issue refreshed tokens: %v", err)
	}

	claims, err := signer.Verify(tokens.AccessToken, refreshedAt)
	if err != nil {
		t.Fatalf("verify refreshed access token: %v", err)
	}
	if !claims.AuthenticatedAt.Equal(authenticatedAt) {
		t.Fatalf("authenticated_at = %v, want %v", claims.AuthenticatedAt, authenticatedAt)
	}
}
