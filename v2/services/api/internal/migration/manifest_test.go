package migration

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"testing"
)

func TestCreateRejectsManifestWithoutContentBindings(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	manifest := []byte(`{"format_version":1,"exported_at":"2026-07-14T00:00:00Z","entries_file":"entries.json","entry_count":0,"deleted_ids_file":"deleted_ids.json","deleted_count":0,"photos":[],"sources":["localStorage"]}`)
	digest := sha256.Sum256(manifest)

	_, err = service.Create(context.Background(), "account", "vault", CreateRequest{
		MigrationID: "11111111-1111-4111-8111-111111111111", FormatVersion: 1,
		Source: "v1_bundle", EntryCount: 0, AssetCount: 0, TotalBytes: 0,
		ManifestSHA256: hex.EncodeToString(digest[:]),
		ManifestBase64: base64.StdEncoding.EncodeToString(manifest),
	})
	if !errors.Is(err, ErrInvalidBundle) || store.created {
		t.Fatalf("Create() error = %v, created = %v", err, store.created)
	}
}

func TestCreateRejectsManifestWhoseItemBytesDoNotMatchTotal(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	request := validManifestRequest(t)
	request.TotalBytes++

	_, err = service.Create(context.Background(), "account", "vault", request)
	if !errors.Is(err, ErrInvalidBundle) || store.created {
		t.Fatalf("Create() error = %v, created = %v", err, store.created)
	}
}
