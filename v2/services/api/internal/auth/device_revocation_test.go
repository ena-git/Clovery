package auth

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestRevokeDeviceAtomicallyRevokesSessionsAndAudits(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	service := NewSessionService(databaseHandle, testAccessTokenSigner(t))
	now := time.Date(2026, time.July, 14, 13, 0, 0, 0, time.UTC)
	service.now = func() time.Time { return now }
	accountID := "11111111-1111-4111-8111-111111111111"
	deviceID := "22222222-2222-4222-8222-222222222222"

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE devices SET revoked_at").
		WithArgs(deviceID, accountID, now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE sessions SET revoked_at").
		WithArgs(deviceID, now).
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec("INSERT INTO audit_events").
		WithArgs(sqlmock.AnyArg(), accountID, deviceID, now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if err := service.RevokeDevice(context.Background(), accountID, deviceID); err != nil {
		t.Fatalf("RevokeDevice() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestRevokeDeviceHidesUnknownOrForeignDevice(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	service := NewSessionService(databaseHandle, testAccessTokenSigner(t))

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE devices SET revoked_at").
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectRollback()

	err = service.RevokeDevice(
		context.Background(),
		"11111111-1111-4111-8111-111111111111",
		"33333333-3333-4333-8333-333333333333",
	)
	if !errors.Is(err, ErrDeviceNotFound) {
		t.Fatalf("RevokeDevice() error = %v", err)
	}
}

func testAccessTokenSigner(t *testing.T) *AccessTokenSigner {
	t.Helper()
	signer, err := NewAccessTokenSigner("clovery-test", []byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create signer: %v", err)
	}
	return signer
}
