package migration

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"testing"

	"github.com/clovery/clovery/services/api/internal/asset"
	"github.com/clovery/clovery/services/api/internal/vault"
	"github.com/google/uuid"
)

func TestCreateRejectsUnknownFormatWithoutWritingVault(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}

	_, err = service.Create(context.Background(), "account", "vault", CreateRequest{
		MigrationID: "11111111-1111-4111-8111-111111111111", FormatVersion: 99,
	})
	if !errors.Is(err, ErrUnsupportedFormat) || store.created {
		t.Fatalf("Create() error = %v, created = %v", err, store.created)
	}
}

func TestCreateRejectsManifestHashMismatchWithoutWritingVault(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	request := validManifestRequest(t)
	request.ManifestSHA256 = stringsOf("0", 64)

	_, err = service.Create(context.Background(), "account", "vault", request)
	if !errors.Is(err, ErrIntegrityMismatch) || store.created {
		t.Fatalf("Create() error = %v, created = %v", err, store.created)
	}
}

func TestCreateAcceptsExistingV1ManifestBytes(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}

	_, err = service.Create(context.Background(), "account", "vault", validManifestRequest(t))
	if err != nil || !store.created {
		t.Fatalf("Create() error = %v, created = %v", err, store.created)
	}
}

func TestCreatePreservesDeletedEntryCountFromV1Manifest(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	entryPayload := []byte(`{"id":"entry-1","text":"journal"}`)
	entryDigest := sha256.Sum256(entryPayload)
	entriesFileDigest := sha256.Sum256([]byte(`[{"id":"entry-1","text":"journal"}]`))
	deletedFileDigest := sha256.Sum256([]byte(`["deleted-1","deleted-2"]`))
	manifest := []byte(fmt.Sprintf(
		`{"format_version":1,"exported_at":"2026-07-14T00:00:00Z","entries_file":"entries.json","entries_sha256":%q,"entry_count":1,"entries":[{"entry_id":"entry-1","sha256":%q,"bytes":%d}],"deleted_ids_file":"deleted_ids.json","deleted_ids_sha256":%q,"deleted_count":2,"deleted_ids":["deleted-1","deleted-2"],"photos":[],"sources":["localStorage"]}`,
		hex.EncodeToString(entriesFileDigest[:]), hex.EncodeToString(entryDigest[:]), len(entryPayload),
		hex.EncodeToString(deletedFileDigest[:]),
	))
	digest := sha256.Sum256(manifest)
	request := CreateRequest{
		MigrationID: "11111111-1111-4111-8111-111111111111", FormatVersion: 1,
		Source: "v1_bundle", EntryCount: 1, AssetCount: 0, TotalBytes: int64(len(entryPayload) + 4),
		ManifestSHA256: hex.EncodeToString(digest[:]),
		ManifestBase64: base64.StdEncoding.EncodeToString(manifest),
	}

	_, err = service.Create(context.Background(), "account", "vault", request)
	if err != nil || store.createdMigration.DeletedCount != 2 {
		t.Fatalf("Create() error = %v, migration = %#v", err, store.createdMigration)
	}
}

func TestAddEntryRejectsWrongSHAWithoutPersisting(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}

	err = service.AddEntry(context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111", EntryInput{
		EntryID: "22222222-2222-4222-8222-222222222222", Payload: json.RawMessage(`{"text":"journal"}`), SHA256: stringsOf("a", 64),
	})
	if !errors.Is(err, ErrIntegrityMismatch) || store.entryAdded || store.errorCode != "entry_sha256_mismatch" {
		t.Fatalf("AddEntry() error = %v, entryAdded = %v, errorCode = %q", err, store.entryAdded, store.errorCode)
	}
}

func TestAddEntryAcceptsCanonicalPayloadSHA(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	payload := json.RawMessage(`{"text":"journal"}`)
	canonical, _ := canonicalJSON(payload)
	digest := sha256.Sum256(canonical)

	err = service.AddEntry(context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111", EntryInput{
		EntryID: "22222222-2222-4222-8222-222222222222", Payload: payload, SHA256: hex.EncodeToString(digest[:]),
	})
	if err != nil || !store.entryAdded {
		t.Fatalf("AddEntry() error = %v, entryAdded = %v", err, store.entryAdded)
	}
}

func TestAddEntryMapsLegacySourceIDDeterministically(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	payload := json.RawMessage(`{"id":"new-1720000000000","text":"journal"}`)
	canonical, _ := canonicalJSON(payload)
	digest := sha256.Sum256(canonical)
	input := EntryInput{
		EntryID: "new-1720000000000", Payload: payload, SHA256: hex.EncodeToString(digest[:]),
	}

	if err := service.AddEntry(
		context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111", input,
	); err != nil {
		t.Fatalf("first AddEntry() error = %v", err)
	}
	first := store.addedEntry
	if err := service.AddEntry(
		context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111", input,
	); err != nil {
		t.Fatalf("second AddEntry() error = %v", err)
	}
	if first.SourceEntryID != input.EntryID || first.EntryID != store.addedEntry.EntryID ||
		uuid.Validate(first.EntryID) != nil {
		t.Fatalf("mapped entries = %#v then %#v", first, store.addedEntry)
	}
}

func TestAddEntryPreservesUUIDSourceID(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	payload := json.RawMessage(`{"text":"journal"}`)
	canonical, _ := canonicalJSON(payload)
	digest := sha256.Sum256(canonical)
	const entryID = "22222222-2222-4222-8222-222222222222"

	err = service.AddEntry(context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111", EntryInput{
		EntryID: entryID, Payload: payload, SHA256: hex.EncodeToString(digest[:]),
	})
	if err != nil || store.addedEntry.SourceEntryID != entryID || store.addedEntry.EntryID != entryID {
		t.Fatalf("AddEntry() error = %v, entry = %#v", err, store.addedEntry)
	}
}

func TestAddEntryRejectsCrossAccountVaultWithoutPersisting(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(deniedMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	payload := json.RawMessage(`{"text":"journal"}`)
	canonical, _ := canonicalJSON(payload)
	digest := sha256.Sum256(canonical)

	err = service.AddEntry(context.Background(), "other-account", "vault", "11111111-1111-4111-8111-111111111111", EntryInput{
		EntryID: "22222222-2222-4222-8222-222222222222", Payload: payload, SHA256: hex.EncodeToString(digest[:]),
	})
	if !errors.Is(err, vault.ErrForbidden) || store.entryAdded {
		t.Fatalf("AddEntry() error = %v, entryAdded = %v", err, store.entryAdded)
	}
}

func TestAddAssetPreservesNewPendingUploadWhenMigrationRejectsIt(t *testing.T) {
	store := &stubMigrationStore{assetError: ErrMigrationMismatch}
	uploader := &stubMigrationAssets{}
	service, err := NewService(&stubMigrationVaults{}, store, uploader)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	request := AssetInput{
		AssetID:        "22222222-2222-4222-8222-222222222222",
		SourceFilename: "photo-1.jpg",
		ContentType:    "image/jpeg",
		ByteSize:       20,
		SHA256:         stringsOf("a", 64),
	}

	_, err = service.AddAsset(
		context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111", request,
	)
	if !errors.Is(err, ErrMigrationMismatch) || uploader.discarded {
		t.Fatalf("AddAsset() error = %v, discarded = %v", err, uploader.discarded)
	}
}

func TestAddAssetPreservesExistingPendingUploadWhenMigrationRejectsIt(t *testing.T) {
	store := &stubMigrationStore{assetError: ErrMigrationMismatch}
	uploader := &stubMigrationAssets{}
	service, err := NewService(&stubMigrationVaults{}, store, uploader)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}

	_, err = service.AddAsset(
		context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111",
		AssetInput{
			AssetID: "22222222-2222-4222-8222-222222222222", SourceFilename: "photo-1.jpg",
			ContentType: "image/jpeg", ByteSize: 20, SHA256: stringsOf("a", 64),
		},
	)
	if !errors.Is(err, ErrMigrationMismatch) || uploader.discarded {
		t.Fatalf("AddAsset() error = %v, discarded = %v", err, uploader.discarded)
	}
}

func stringsOf(value string, count int) string {
	result := ""
	for len(result) < count {
		result += value
	}
	return result[:count]
}

func validManifestRequest(t *testing.T) CreateRequest {
	t.Helper()
	entryPayload := []byte(`{"id":"entry-1","text":"journal"}`)
	entryDigest := sha256.Sum256(entryPayload)
	entriesFileDigest := sha256.Sum256([]byte(`[{"id":"entry-1","text":"journal"}]`))
	deletedFileDigest := sha256.Sum256([]byte(`[]`))
	manifest := []byte(fmt.Sprintf(
		`{"format_version":1,"exported_at":"2026-07-14T00:00:00Z","entries_file":"entries.json","entries_sha256":%q,"entry_count":1,"entries":[{"entry_id":"entry-1","sha256":%q,"bytes":%d}],"deleted_ids_file":"deleted_ids.json","deleted_ids_sha256":%q,"deleted_count":0,"deleted_ids":[],"photos":[{"filename":"photo-1.jpg","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes":20}],"sources":["localStorage"]}`,
		hex.EncodeToString(entriesFileDigest[:]), hex.EncodeToString(entryDigest[:]), len(entryPayload),
		hex.EncodeToString(deletedFileDigest[:]),
	))
	digest := sha256.Sum256(manifest)
	return CreateRequest{
		MigrationID:    "11111111-1111-4111-8111-111111111111",
		FormatVersion:  1,
		Source:         "v1_bundle",
		EntryCount:     1,
		AssetCount:     1,
		TotalBytes:     int64(len(entryPayload) + 20),
		ManifestSHA256: hex.EncodeToString(digest[:]),
		ManifestBase64: base64.StdEncoding.EncodeToString(manifest),
	}
}

type stubMigrationVaults struct{}

func (*stubMigrationVaults) Get(context.Context, string, string) (vault.Metadata, error) {
	return vault.Metadata{}, nil
}

type deniedMigrationVaults struct{}

func (deniedMigrationVaults) Get(context.Context, string, string) (vault.Metadata, error) {
	return vault.Metadata{}, vault.ErrForbidden
}

type stubMigrationStore struct {
	created          bool
	entryAdded       bool
	assetError       error
	errorCode        string
	createdMigration Migration
	addedEntry       EntryInput
}

func (store *stubMigrationStore) Create(_ context.Context, migration Migration) (Migration, error) {
	store.created = true
	store.createdMigration = migration
	return Migration{}, nil
}

func (store *stubMigrationStore) AddEntry(_ context.Context, _, _ string, entry EntryInput) error {
	store.entryAdded = true
	store.addedEntry = entry
	return nil
}

func (store *stubMigrationStore) AddAsset(context.Context, string, string, string, string, int64, string) error {
	return store.assetError
}

func (*stubMigrationStore) Verify(context.Context, string, string) (Report, error) {
	return Report{}, nil
}

func (*stubMigrationStore) GetReport(context.Context, string, string) (Report, error) {
	return Report{}, nil
}

func (store *stubMigrationStore) RecordError(_ context.Context, _, _, code string) error {
	store.errorCode = code
	return nil
}

type stubMigrationAssets struct {
	discarded bool
}

func (stub *stubMigrationAssets) StartUpload(
	context.Context,
	string,
	string,
	asset.UploadRequest,
) (asset.UploadTicket, error) {
	return asset.UploadTicket{}, nil
}

func (stub *stubMigrationAssets) DiscardPending(context.Context, string, string, string) error {
	stub.discarded = true
	return nil
}
