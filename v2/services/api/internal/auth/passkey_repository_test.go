package auth

import (
	"bytes"
	"context"
	"database/sql"
	"database/sql/driver"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPasskeyStoreConsumesChallengeOnlyOnce(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey cipher: %v", err)
	}
	store := NewPostgresPasskeyStore(databaseHandle, cipher)
	consumption := ConsumePasskeyChallenge{
		ID:        "11111111-1111-4111-8111-111111111111",
		Purpose:   PasskeyChallengeRegistration,
		AccountID: "22222222-2222-4222-8222-222222222222",
		SessionID: "33333333-3333-4333-8333-333333333333",
		UsedAt:    time.Date(2026, time.July, 14, 14, 0, 0, 0, time.UTC),
	}
	sessionData := []byte(`{"challenge":"stored"}`)

	mock.ExpectQuery("UPDATE passkey_challenges").WithArgs(
		consumption.ID,
		consumption.Purpose,
		consumption.AccountID,
		consumption.SessionID,
		consumption.UsedAt,
	).WillReturnRows(sqlmock.NewRows([]string{"session_data"}).AddRow(sessionData))
	mock.ExpectQuery("UPDATE passkey_challenges").WithArgs(
		consumption.ID,
		consumption.Purpose,
		consumption.AccountID,
		consumption.SessionID,
		consumption.UsedAt,
	).WillReturnError(sql.ErrNoRows)

	if _, err := store.ConsumeChallenge(context.Background(), consumption); err != nil {
		t.Fatalf("consume passkey challenge: %v", err)
	}
	if _, err := store.ConsumeChallenge(context.Background(), consumption); !errors.Is(err, ErrPasskeyAuthentication) {
		t.Fatalf("replayed passkey challenge error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestPasskeyStorePersistsServerSessionData(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey cipher: %v", err)
	}
	store := NewPostgresPasskeyStore(databaseHandle, cipher)
	challenge := PasskeyChallengeRecord{
		ID:          "44444444-4444-4444-8444-444444444444",
		Purpose:     PasskeyChallengeRegistration,
		AccountID:   "55555555-5555-4555-8555-555555555555",
		SessionID:   "66666666-6666-4666-8666-666666666666",
		SessionData: []byte(`{"challenge":"server-only","user_id":"opaque"}`),
		ExpiresAt:   time.Date(2026, time.July, 14, 14, 15, 0, 0, time.UTC),
	}

	mock.ExpectExec("INSERT INTO passkey_challenges").WithArgs(
		challenge.ID,
		challenge.Purpose,
		challenge.AccountID,
		challenge.SessionID,
		challenge.SessionData,
		challenge.ExpiresAt,
	).WillReturnResult(sqlmock.NewResult(0, 1))

	if err := store.CreateChallenge(context.Background(), challenge); err != nil {
		t.Fatalf("create passkey challenge: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestPasskeyStoreCreatesOpaquePersistentUserHandle(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey cipher: %v", err)
	}
	store := NewPostgresPasskeyStore(databaseHandle, cipher)
	expectedHandle := bytes.Repeat([]byte{9}, 32)
	store.random = bytes.NewReader(expectedHandle)
	accountID := "77777777-7777-4777-8777-777777777777"
	vaultID := "88888888-8888-4888-8888-888888888888"

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT account_login_ids.normalized_id, vaults.id").WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"normalized_id", "vault_id"}).AddRow("garden_user", vaultID))
	mock.ExpectQuery("SELECT user_handle FROM webauthn_users").WithArgs(accountID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("INSERT INTO webauthn_users").WithArgs(accountID, expectedHandle).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT credential_id").WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{
			"credential_id", "credential_key_version", "credential_record_nonce", "credential_record_ciphertext",
		}))
	mock.ExpectCommit()

	user, err := store.EnsureUser(context.Background(), accountID)
	if err != nil {
		t.Fatalf("ensure passkey user: %v", err)
	}
	if !bytes.Equal(user.Handle, expectedHandle) || user.Name != "garden_user" || user.VaultID != vaultID {
		t.Fatalf("passkey user = %#v", user)
	}
	if bytes.Contains(user.Handle, []byte(accountID)) || bytes.Contains(user.Handle, []byte(user.Name)) {
		t.Fatal("passkey user handle exposes account identifiers")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestPasskeyStoreEncryptsFullCredentialRecord(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey cipher: %v", err)
	}
	cipher.random = bytes.NewReader(bytes.Repeat([]byte{4}, 12))
	store := NewPostgresPasskeyStore(databaseHandle, cipher)
	store.random = bytes.NewReader(make([]byte, 16))
	accountID := "99999999-9999-4999-8999-999999999999"
	credential := PasskeyCredential{
		ID:             []byte("credential-id"),
		PublicKey:      []byte("cose-public-key"),
		Record:         []byte(`{"id":"credential-id","privateMetadata":"must-encrypt"}`),
		SignCount:      3,
		DeviceMetadata: json.RawMessage(`{"platform":"ios"}`),
	}

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT id FROM clovery_accounts").WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(accountID))
	mock.ExpectExec("INSERT INTO passkeys").WithArgs(
		"00000000-0000-4000-8000-000000000000",
		accountID,
		credential.ID,
		credential.PublicKey,
		credential.SignCount,
		[]byte(credential.DeviceMetadata),
		passkeyCredentialKeyVersion,
		sqlmock.AnyArg(),
		encryptedRecordArgument{plaintext: credential.Record},
	).WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO audit_events").WithArgs(
		sqlmock.AnyArg(),
		accountID,
		"00000000-0000-4000-8000-000000000000",
	).WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if err := store.SaveCredential(context.Background(), accountID, credential); err != nil {
		t.Fatalf("save passkey credential: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestPasskeyStoreRequiresCredentialAndUserHandleMatch(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey cipher: %v", err)
	}
	store := NewPostgresPasskeyStore(databaseHandle, cipher)
	credentialID := []byte("known-credential")
	wrongHandle := bytes.Repeat([]byte{5}, 32)

	mock.ExpectQuery("SELECT passkeys.account_id").WithArgs(credentialID, wrongHandle).
		WillReturnError(sql.ErrNoRows)

	_, err = store.FindUserByCredential(context.Background(), credentialID, wrongHandle)
	if !errors.Is(err, ErrPasskeyAuthentication) {
		t.Fatalf("mismatched credential lookup error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestPasskeyStoreUpdatesEncryptedCredentialStateAfterLogin(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey cipher: %v", err)
	}
	cipher.random = bytes.NewReader(bytes.Repeat([]byte{6}, 12))
	store := NewPostgresPasskeyStore(databaseHandle, cipher)
	accountID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	credential := PasskeyCredential{
		ID:        []byte("credential-id"),
		PublicKey: []byte("cose-public-key"),
		Record:    []byte(`{"id":"credential-id","signCount":9,"backupState":true}`),
		SignCount: 9,
	}

	mock.ExpectQuery("UPDATE passkeys").WithArgs(
		accountID,
		credential.ID,
		credential.PublicKey,
		credential.SignCount,
		passkeyCredentialKeyVersion,
		sqlmock.AnyArg(),
		encryptedRecordArgument{plaintext: credential.Record},
	).WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))

	if err := store.UpdateCredential(context.Background(), accountID, credential); err != nil {
		t.Fatalf("update passkey credential: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

type encryptedRecordArgument struct {
	plaintext []byte
}

func (argument encryptedRecordArgument) Match(value driver.Value) bool {
	ciphertext, ok := value.([]byte)
	return ok && len(ciphertext) > len(argument.plaintext) && !bytes.Contains(ciphertext, argument.plaintext)
}
