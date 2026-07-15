package account

import (
	"context"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestGetProfileReturnsRootAccountWithoutCredentialSecrets(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewRepository(databaseHandle)
	accountID := "11111111-1111-4111-8111-111111111111"
	createdAt := time.Date(2026, time.July, 14, 15, 0, 0, 0, time.UTC)

	mock.ExpectQuery("SELECT a.id, login.normalized_id, a.status, a.created_at").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "normalized_id", "status", "created_at", "has_password", "passkey_count", "recovery_code_count",
		}).AddRow(accountID, "clovery_user", "active", createdAt, true, 2, 7))
	mock.ExpectQuery("SELECT provider, issuer, created_at FROM external_identities").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"provider", "issuer", "created_at"}).
			AddRow("apple", "https://appleid.apple.com", createdAt))

	profile, err := repository.GetProfile(context.Background(), accountID)
	if err != nil {
		t.Fatalf("GetProfile() error = %v", err)
	}
	if profile.CloveryID != "clovery_user" || !profile.HasPassword || profile.PasskeyCount != 2 {
		t.Fatalf("profile = %#v", profile)
	}
	if len(profile.Bindings) != 1 || profile.Bindings[0].Provider != "apple" {
		t.Fatalf("bindings = %#v", profile.Bindings)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}
