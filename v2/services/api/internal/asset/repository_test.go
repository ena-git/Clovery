package asset

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestCreatePendingRejectsAssetIDReusedWithDifferentMetadata(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	asset := Asset{ID: "asset", VaultID: "vault", ObjectKey: "vault/asset", ContentType: "image/jpeg", ByteSize: 20, SHA256: "hash", Status: StatusPending, CreatedAt: time.Now()}

	mock.ExpectQuery("INSERT INTO vault_assets").
		WithArgs(asset.ID, asset.VaultID, asset.ObjectKey, asset.ContentType, asset.ByteSize, asset.SHA256, asset.CreatedAt).
		WillReturnRows(sqlmock.NewRows(assetColumns()))
	mock.ExpectQuery("SELECT id, vault_id, object_key, content_type, byte_size, sha256, status, created_at, completed_at").
		WithArgs(asset.ID, asset.VaultID, asset.ObjectKey, asset.ContentType, asset.ByteSize, asset.SHA256).
		WillReturnError(sql.ErrNoRows)

	_, err = repository.CreatePending(context.Background(), asset)
	if !errors.Is(err, ErrAssetMetadataMismatch) {
		t.Fatalf("CreatePending() error = %v", err)
	}
}

func TestCreatePendingReturnsNewAsset(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	createdAt := time.Date(2026, time.July, 14, 18, 0, 0, 0, time.UTC)
	want := Asset{
		ID: "asset", VaultID: "vault", ObjectKey: "vault/asset", ContentType: "image/jpeg",
		ByteSize: 20, SHA256: "hash", Status: StatusPending, CreatedAt: createdAt,
	}

	mock.ExpectQuery("INSERT INTO vault_assets").
		WithArgs(want.ID, want.VaultID, want.ObjectKey, want.ContentType, want.ByteSize, want.SHA256, want.CreatedAt).
		WillReturnRows(sqlmock.NewRows(assetColumns()).AddRow(
			want.ID, want.VaultID, want.ObjectKey, want.ContentType, want.ByteSize,
			want.SHA256, want.Status, want.CreatedAt, nil,
		))

	got, err := repository.CreatePending(context.Background(), want)
	if err != nil || got.ID != want.ID {
		t.Fatalf("CreatePending() asset = %#v, error = %v", got, err)
	}
}

func TestGetRequiresMatchingVaultAndAsset(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)

	mock.ExpectQuery("SELECT id, vault_id, object_key, content_type, byte_size, sha256, status, created_at, completed_at").
		WithArgs("vault", "asset").
		WillReturnError(sql.ErrNoRows)

	_, err = repository.Get(context.Background(), "vault", "asset")
	if !errors.Is(err, ErrAssetNotFound) {
		t.Fatalf("Get() error = %v", err)
	}
}

func assetColumns() []string {
	return []string{"id", "vault_id", "object_key", "content_type", "byte_size", "sha256", "status", "created_at", "completed_at"}
}
