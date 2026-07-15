package device

import (
	"context"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPostgresRepositoryListsOnlyAccountDevices(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	accountID := "11111111-1111-4111-8111-111111111111"
	createdAt := time.Date(2026, time.July, 14, 14, 0, 0, 0, time.UTC)

	mock.ExpectQuery("SELECT id, display_name, platform, created_at, revoked_at FROM devices").
		WithArgs(accountID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "display_name", "platform", "created_at", "revoked_at"}).
			AddRow("22222222-2222-4222-8222-222222222222", "iPhone", "ios", createdAt, nil))

	devices, err := repository.List(context.Background(), accountID)
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(devices) != 1 || devices[0].Platform != "ios" {
		t.Fatalf("devices = %#v", devices)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("SQL expectations: %v", err)
	}
}
