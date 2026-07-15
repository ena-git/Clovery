package migration

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestAddAssetRequiresMatchingManifestPhoto(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT status FROM vault_migrations.*FOR UPDATE").
		WithArgs("migration", "vault").
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))
	mock.ExpectQuery("jsonb_array_elements.*manifest.*photos").
		WithArgs("migration", "vault", "asset", "photo-1.jpg", int64(20), stringsOf("a", 64)).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectRollback()

	err = repository.AddAsset(
		context.Background(), "vault", "migration", "asset", "photo-1.jpg", 20, stringsOf("a", 64),
	)
	if !errors.Is(err, ErrMigrationMismatch) {
		t.Fatalf("AddAsset() error = %v", err)
	}
}

func TestAddEntryLocksUploadingMigrationBeforeStaging(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT status FROM vault_migrations.*FOR UPDATE").
		WithArgs("migration", "vault").
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))
	mock.ExpectQuery("INSERT INTO migration_entries").WillReturnError(sql.ErrNoRows)
	mock.ExpectRollback()

	err = repository.AddEntry(context.Background(), "vault", "migration", EntryInput{
		EntryID: "entry", Payload: []byte(`{}`), SHA256: stringsOf("a", 64),
	})
	if !errors.Is(err, ErrMigrationMismatch) {
		t.Fatalf("AddEntry() error = %v", err)
	}
}

func TestCreateRejectsMigrationIDReusedWithDifferentContent(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	migration := Migration{ID: "migration", VaultID: "vault"}

	mock.ExpectQuery("INSERT INTO vault_migrations").WillReturnError(sql.ErrNoRows)
	_, err = repository.Create(context.Background(), migration)
	if !errors.Is(err, ErrMigrationMismatch) {
		t.Fatalf("Create() error = %v", err)
	}
}
