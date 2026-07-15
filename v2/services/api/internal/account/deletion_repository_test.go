package account

import (
	"context"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestCreateDeletionRequestLocksDataAndRevokesSessions(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewRepository(databaseHandle)
	params := deletionRequestTestParams()

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT status FROM clovery_accounts").
		WithArgs(params.AccountID).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("active"))
	mock.ExpectExec("INSERT INTO account_deletion_requests").
		WithArgs(params.ID, params.AccountID, params.RequestedAt, params.ScheduledFor).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE clovery_accounts").
		WithArgs(params.AccountID, params.RequestedAt).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE vaults SET status = 'locked'").
		WithArgs(params.AccountID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE sessions SET revoked_at").
		WithArgs(params.AccountID, params.RequestedAt).
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec("INSERT INTO audit_events").
		WithArgs(sqlmock.AnyArg(), params.AccountID, params.ID, params.ScheduledFor, params.RequestedAt).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	request, err := repository.CreateDeletionRequest(context.Background(), params)
	if err != nil {
		t.Fatalf("CreateDeletionRequest() error = %v", err)
	}
	if request.ID != params.ID || request.Status != "pending" {
		t.Fatalf("deletion request = %#v", request)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}

func TestCreateDeletionRequestReturnsExistingPendingRequest(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewRepository(databaseHandle)
	params := deletionRequestTestParams()

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT status FROM clovery_accounts").
		WithArgs(params.AccountID).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("deletion_requested"))
	mock.ExpectQuery("SELECT id, account_id, status, requested_at, scheduled_for").
		WithArgs(params.AccountID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "account_id", "status", "requested_at", "scheduled_for"}).
			AddRow("existing-request", params.AccountID, "pending", params.RequestedAt, params.ScheduledFor))
	mock.ExpectCommit()

	request, err := repository.CreateDeletionRequest(context.Background(), params)
	if err != nil {
		t.Fatalf("CreateDeletionRequest() error = %v", err)
	}
	if request.ID != "existing-request" {
		t.Fatalf("deletion request = %#v", request)
	}
}

func deletionRequestTestParams() CreateDeletionRequestParams {
	requestedAt := time.Date(2026, time.July, 14, 16, 0, 0, 0, time.UTC)
	return CreateDeletionRequestParams{
		ID:           "22222222-2222-4222-8222-222222222222",
		AccountID:    "11111111-1111-4111-8111-111111111111",
		RequestedAt:  requestedAt,
		ScheduledFor: requestedAt.Add(30 * 24 * time.Hour),
	}
}
