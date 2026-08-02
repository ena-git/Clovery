package authflow

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
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

func TestNewServiceWithIdentityClaimsRejectsNilClaimDependencies(t *testing.T) {
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
	claimRepository := identityclaim.NewPostgresRepository(databaseHandle)
	claims := identityclaim.NewService(claimRepository)
	var nilClaimRepository *identityclaim.PostgresRepository
	var nilClaims *identityclaim.Service

	for _, test := range []struct {
		name            string
		claimRepository *identityclaim.PostgresRepository
		claims          *identityclaim.Service
	}{
		{name: "nil claim repository", claimRepository: nilClaimRepository, claims: claims},
		{name: "nil claim service", claimRepository: claimRepository, claims: nilClaims},
	} {
		t.Run(test.name, func(t *testing.T) {
			service, err := NewServiceWithIdentityClaims(
				databaseHandle,
				sessions,
				test.claimRepository,
				test.claims,
			)
			if err == nil || service != nil {
				t.Fatalf("NewServiceWithIdentityClaims() service = %#v, error = %v", service, err)
			}
		})
	}
}
