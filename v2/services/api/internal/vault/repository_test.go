package vault

import (
	"context"
	"database/sql"
	"errors"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPostgresRepositoryHidesUnownedVaultAndRecordsAudit(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	accountID := "11111111-1111-4111-8111-111111111111"
	vaultID := "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

	mock.ExpectQuery(regexp.QuoteMeta(
		"SELECT id, status, created_at FROM vaults WHERE id = $1 AND owner_account_id = $2",
	)).WithArgs(vaultID, accountID).WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("INSERT INTO audit_events").
		WithArgs(sqlmock.AnyArg(), accountID, vaultID, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(0, 1))

	_, err = repository.GetOwned(context.Background(), accountID, vaultID)
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("GetOwned() error = %v", err)
	}
	if err := repository.RecordAccessDenial(context.Background(), accountID, vaultID); err != nil {
		t.Fatalf("RecordAccessDenial() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestPostgresRepositoryReturnsOwnedVaultMetadata(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	createdAt := time.Date(2026, time.July, 14, 12, 0, 0, 0, time.UTC)

	mock.ExpectQuery("SELECT id, status, created_at FROM vaults").
		WithArgs("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "11111111-1111-4111-8111-111111111111").
		WillReturnRows(sqlmock.NewRows([]string{"id", "status", "created_at"}).
			AddRow("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "active", createdAt))

	metadata, err := repository.GetOwned(
		context.Background(),
		"11111111-1111-4111-8111-111111111111",
		"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
	)
	if err != nil {
		t.Fatalf("GetOwned() error = %v", err)
	}
	if metadata.Status != "active" || !metadata.CreatedAt.Equal(createdAt) {
		t.Fatalf("metadata = %#v", metadata)
	}
}
