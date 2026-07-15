package sync

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPostgresRepositoryReturnsStoredResultForIdenticalReplay(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	operation := Operation{OperationID: "11111111-1111-4111-8111-111111111111", EntryID: "22222222-2222-4222-8222-222222222222", Payload: json.RawMessage(`{"text":"hello"}`)}
	fingerprint, err := OperationFingerprint(operation)
	if err != nil {
		t.Fatalf("fingerprint operation: %v", err)
	}
	stored := Decision{OperationID: operation.OperationID, Status: StatusApplied, Cursor: 9}
	storedJSON, _ := json.Marshal(stored)

	mock.ExpectBegin()
	mock.ExpectExec("pg_advisory_xact_lock").WithArgs(operation.OperationID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT request_hash, result FROM sync_operations").
		WithArgs(operation.OperationID, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa").
		WillReturnRows(sqlmock.NewRows([]string{"request_hash", "result"}).AddRow(fingerprint, storedJSON))
	mock.ExpectCommit()

	result, err := repository.Apply(
		context.Background(),
		"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		operation,
		time.Now(),
	)
	if err != nil {
		t.Fatalf("Apply() error = %v", err)
	}
	if result.Cursor != 9 || result.OperationID != operation.OperationID {
		t.Fatalf("result = %#v", result)
	}
}

func TestPostgresRepositoryRejectsChangedReplay(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	operation := Operation{OperationID: "11111111-1111-4111-8111-111111111111", EntryID: "22222222-2222-4222-8222-222222222222", Payload: json.RawMessage(`{"text":"changed"}`)}

	mock.ExpectBegin()
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT request_hash, result FROM sync_operations").
		WillReturnRows(sqlmock.NewRows([]string{"request_hash", "result"}).AddRow(make([]byte, 32), []byte(`{}`)))
	mock.ExpectRollback()

	_, err = repository.Apply(context.Background(), "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", operation, time.Now())
	if !errors.Is(err, ErrOperationReplayMismatch) {
		t.Fatalf("changed replay error = %v", err)
	}
}

func TestPostgresRepositoryLocksEntryBeforeReadingCurrentState(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	vaultID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	operation := Operation{
		OperationID: "11111111-1111-4111-8111-111111111111",
		EntryID:     "22222222-2222-4222-8222-222222222222",
		Payload:     json.RawMessage(`{"text":"created"}`),
	}

	mock.ExpectBegin()
	mock.ExpectExec("pg_advisory_xact_lock").WithArgs(operation.OperationID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT request_hash, result FROM sync_operations").
		WithArgs(operation.OperationID, vaultID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("pg_advisory_xact_lock").
		WithArgs("journal_entry:" + vaultID + ":" + operation.EntryID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT id, revision, payload, deleted_at FROM journal_entries").
		WithArgs(operation.EntryID, vaultID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec("INSERT INTO journal_entries").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("INSERT INTO sync_changes").WillReturnRows(sqlmock.NewRows([]string{"cursor"}).AddRow(1))
	mock.ExpectExec("INSERT INTO sync_operations").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if _, err := repository.Apply(context.Background(), vaultID, operation, time.Now()); err != nil {
		t.Fatalf("Apply() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestPostgresRepositoryListsChangesAfterCursor(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	changedAt := time.Date(2026, time.July, 14, 17, 0, 0, 0, time.UTC)

	mock.ExpectQuery("SELECT cursor, entity_type, entity_id, revision, operation_id, payload, deleted, changed_at").
		WithArgs("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", int64(4), 101).
		WillReturnRows(sqlmock.NewRows([]string{
			"cursor", "entity_type", "entity_id", "revision", "operation_id", "payload", "deleted", "changed_at",
		}).AddRow(5, "journal_entry", "entry", 2, "operation", []byte(`{"text":"hello"}`), false, changedAt))

	changes, err := repository.ListChanges(context.Background(), "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", 4, 101)
	if err != nil {
		t.Fatalf("ListChanges() error = %v", err)
	}
	if len(changes) != 1 || changes[0].Cursor != 5 || changes[0].Deleted {
		t.Fatalf("changes = %#v", changes)
	}
}
