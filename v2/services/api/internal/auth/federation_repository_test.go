package auth

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/jackc/pgx/v5/pgconn"
)

func TestFederationStoreRejectsUnbindingLastRecoveryCredential(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	accountID := "55555555-5555-4555-8555-555555555555"

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(
		"SELECT id FROM clovery_accounts WHERE id = $1 FOR UPDATE",
	)).WithArgs(accountID).WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(accountID))
	mock.ExpectQuery("SELECT").WithArgs(accountID).WillReturnRows(
		sqlmock.NewRows([]string{"credential_count"}).AddRow(1),
	)
	mock.ExpectRollback()

	err = store.UnbindIdentity(context.Background(), accountID, "huawei")
	if !errors.Is(err, ErrLastRecoveryCredential) {
		t.Fatalf("unbind identity error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStoreConsumesLoginIntentOnlyOnce(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	consumption := ConsumeFederatedLoginIntent{
		ID:        "11111111-1111-4111-8111-111111111111",
		Provider:  "google",
		NonceHash: make([]byte, sha256.Size),
		UsedAt:    time.Date(2026, time.July, 14, 10, 0, 0, 0, time.UTC),
	}

	mock.ExpectQuery("UPDATE federation_intents").
		WithArgs(consumption.ID, consumption.Provider, consumption.NonceHash, consumption.UsedAt).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(consumption.ID))
	mock.ExpectQuery("UPDATE federation_intents").
		WithArgs(consumption.ID, consumption.Provider, consumption.NonceHash, consumption.UsedAt).
		WillReturnError(sql.ErrNoRows)

	if err := store.ConsumeLoginIntent(context.Background(), consumption); err != nil {
		t.Fatalf("consume login intent: %v", err)
	}
	if err := store.ConsumeLoginIntent(context.Background(), consumption); !errors.Is(err, ErrFederatedAuthentication) {
		t.Fatalf("replayed login intent error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStoreRejectsBindingIntentFromDifferentSession(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	consumption := ConsumeFederatedBindingIntent{
		ID:        "22222222-2222-4222-8222-222222222222",
		AccountID: "33333333-3333-4333-8333-333333333333",
		SessionID: "44444444-4444-4444-8444-444444444444",
		Provider:  "apple",
		NonceHash: make([]byte, sha256.Size),
		UsedAt:    time.Date(2026, time.July, 14, 10, 30, 0, 0, time.UTC),
	}

	mock.ExpectQuery("UPDATE federation_intents").
		WithArgs(
			consumption.ID,
			consumption.AccountID,
			consumption.SessionID,
			consumption.Provider,
			consumption.NonceHash,
			consumption.UsedAt,
		).
		WillReturnError(sql.ErrNoRows)

	err = store.ConsumeBindingIntent(context.Background(), consumption)
	if !errors.Is(err, ErrFederatedAuthentication) {
		t.Fatalf("different-session binding intent error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStorePersistsSessionBoundBindingIntent(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	intent := BindingIntentRecord{
		ID:        "66666666-6666-4666-8666-666666666666",
		AccountID: "77777777-7777-4777-8777-777777777777",
		SessionID: "88888888-8888-4888-8888-888888888888",
		Provider:  "google",
		NonceHash: make([]byte, sha256.Size),
		ExpiresAt: time.Date(2026, time.July, 14, 11, 0, 0, 0, time.UTC),
	}

	mock.ExpectExec("INSERT INTO federation_intents").WithArgs(
		intent.ID,
		intent.AccountID,
		intent.SessionID,
		intent.Provider,
		intent.NonceHash,
		intent.ExpiresAt,
	).WillReturnResult(sqlmock.NewResult(0, 1))

	if err := store.CreateBindingIntent(context.Background(), intent); err != nil {
		t.Fatalf("create binding intent: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStorePersistsUnownedLoginIntent(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	intent := FederatedLoginIntentRecord{
		ID:        "99999999-9999-4999-8999-999999999999",
		Provider:  "apple",
		NonceHash: make([]byte, sha256.Size),
		ExpiresAt: time.Date(2026, time.July, 14, 11, 15, 0, 0, time.UTC),
	}

	mock.ExpectExec("INSERT INTO federation_intents").WithArgs(
		intent.ID,
		intent.Provider,
		intent.NonceHash,
		intent.ExpiresAt,
	).WillReturnResult(sqlmock.NewResult(0, 1))

	if err := store.CreateLoginIntent(context.Background(), intent); err != nil {
		t.Fatalf("create login intent: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStoreDoesNotFallbackWhenStableIdentityIsUnbound(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	key := FederatedIdentityKey{
		Provider: "google",
		Issuer:   "https://accounts.google.com",
		Subject:  "unbound-subject",
	}

	mock.ExpectQuery("SELECT external_identities.account_id, vaults.id").WithArgs(
		key.Provider,
		key.Issuer,
		key.Subject,
	).WillReturnError(sql.ErrNoRows)

	_, err = store.FindAccountByIdentity(context.Background(), key)
	if !errors.Is(err, ErrFederatedIdentityNotBound) {
		t.Fatalf("find unbound identity error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStoreMapsDuplicateStableIdentity(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	accountID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	key := FederatedIdentityKey{
		Provider: "apple",
		Issuer:   "https://appleid.apple.com",
		Subject:  "already-bound-subject",
	}

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(
		"SELECT id FROM clovery_accounts WHERE id = $1 FOR UPDATE",
	)).WithArgs(accountID).WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(accountID))
	mock.ExpectExec("INSERT INTO external_identities").WithArgs(
		accountID,
		key.Provider,
		key.Issuer,
		key.Subject,
	).WillReturnError(&pgconn.PgError{
		Code:           "23505",
		ConstraintName: "external_identities_provider_subject_key",
	})
	mock.ExpectRollback()

	err = store.BindIdentity(context.Background(), accountID, key)
	if !errors.Is(err, ErrFederatedIdentityAlreadyBound) {
		t.Fatalf("duplicate identity error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestFederationStoreMapsSecondProviderBindingForSameAccount(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	accountID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	key := FederatedIdentityKey{Provider: "apple", Issuer: "issuer", Subject: "second-subject"}

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT id FROM clovery_accounts").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(accountID))
	mock.ExpectExec("INSERT INTO external_identities").
		WithArgs(accountID, key.Provider, key.Issuer, key.Subject).
		WillReturnError(&pgconn.PgError{
			Code:           "23505",
			ConstraintName: "external_identities_account_provider_key",
		})
	mock.ExpectRollback()

	err = store.BindIdentity(context.Background(), accountID, key)
	if !errors.Is(err, ErrFederatedIdentityAlreadyBound) {
		t.Fatalf("second provider binding error = %v", err)
	}
}

func TestFederationStoreAuditsSuccessfulBinding(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	accountID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	key := FederatedIdentityKey{Provider: "google", Issuer: "https://accounts.google.com", Subject: "subject"}

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT id FROM clovery_accounts").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(accountID))
	mock.ExpectExec("INSERT INTO external_identities").
		WithArgs(accountID, key.Provider, key.Issuer, key.Subject).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO audit_events").
		WithArgs(sqlmock.AnyArg(), accountID, key.Provider, key.Issuer).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if err := store.BindIdentity(context.Background(), accountID, key); err != nil {
		t.Fatalf("BindIdentity() error = %v", err)
	}
}

func TestFederationStoreAuditsSuccessfulUnbinding(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	store := NewPostgresFederationStore(databaseHandle)
	accountID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT id FROM clovery_accounts").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(accountID))
	mock.ExpectQuery("SELECT").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"credential_count"}).AddRow(2))
	mock.ExpectExec("DELETE FROM external_identities").
		WithArgs(accountID, "google").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO audit_events").
		WithArgs(sqlmock.AnyArg(), accountID, "google").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if err := store.UnbindIdentity(context.Background(), accountID, "google"); err != nil {
		t.Fatalf("UnbindIdentity() error = %v", err)
	}
}
