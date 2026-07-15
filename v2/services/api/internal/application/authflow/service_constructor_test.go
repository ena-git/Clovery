package authflow

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/clovery/clovery/services/api/internal/auth"
)

func TestNewServiceWithSessionsUsesSharedSessionService(t *testing.T) {
	databaseHandle, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create mock database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	signer, err := auth.NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create signer: %v", err)
	}
	sessions := auth.NewSessionService(databaseHandle, signer)

	service, err := NewServiceWithSessions(databaseHandle, sessions)
	if err != nil {
		t.Fatalf("create service: %v", err)
	}
	if service.sessions != sessions {
		t.Fatal("auth flow did not retain the shared session service")
	}
}
