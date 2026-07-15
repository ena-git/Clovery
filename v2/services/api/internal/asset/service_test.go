package asset

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/vault"
)

func TestCompleteRejectsObjectIntegrityMismatch(t *testing.T) {
	repository := &stubAssetRepository{asset: Asset{
		ID:        "22222222-2222-4222-8222-222222222222",
		VaultID:   "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		ObjectKey: "vault/asset",
		ByteSize:  20,
		SHA256:    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		Status:    StatusPending,
	}}
	objects := &stubObjectStore{metadata: ObjectMetadata{ByteSize: 19, SHA256: repository.asset.SHA256}}
	service, err := NewService(&stubAssetVaultAuthorizer{}, repository, objects)
	if err != nil {
		t.Fatalf("create asset service: %v", err)
	}

	err = service.Complete(
		context.Background(), "account", repository.asset.VaultID, repository.asset.ID,
	)
	if !errors.Is(err, ErrIntegrityMismatch) || repository.completed {
		t.Fatalf("Complete() error = %v, completed = %v", err, repository.completed)
	}
}

func TestStartUploadAndDownloadRemainVaultScoped(t *testing.T) {
	repository := &stubAssetRepository{asset: Asset{
		ID:        "22222222-2222-4222-8222-222222222222",
		VaultID:   "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		ObjectKey: "vault/asset",
		Status:    StatusPending,
	}}
	objects := &stubObjectStore{uploadURL: "https://upload.example", downloadURL: "https://download.example"}
	authorizer := &stubAssetVaultAuthorizer{}
	service, err := NewService(authorizer, repository, objects)
	if err != nil {
		t.Fatalf("create asset service: %v", err)
	}

	upload, err := service.StartUpload(context.Background(), "account", repository.asset.VaultID, UploadRequest{
		AssetID:     repository.asset.ID,
		ContentType: "image/jpeg",
		ByteSize:    20,
		SHA256:      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	})
	if err != nil {
		t.Fatalf("StartUpload() error = %v", err)
	}
	repository.asset.Status = StatusComplete
	download, err := service.Download(context.Background(), "account", repository.asset.VaultID, repository.asset.ID)
	if err != nil {
		t.Fatalf("Download() error = %v", err)
	}
	if upload.URL != objects.uploadURL || upload.Headers["If-None-Match"] != "*" ||
		download.URL != objects.downloadURL || authorizer.vaultID != repository.asset.VaultID {
		t.Fatalf("upload = %#v, download = %#v, vault = %q", upload, download, authorizer.vaultID)
	}
}

func TestStartUploadDoesNotPresignCompletedAsset(t *testing.T) {
	repository := &stubAssetRepository{asset: Asset{
		ID: "22222222-2222-4222-8222-222222222222", VaultID: "vault", Status: StatusComplete,
	}}
	objects := &stubObjectStore{uploadURL: "https://must-not-be-issued.example"}
	service, err := NewService(&stubAssetVaultAuthorizer{}, repository, objects)
	if err != nil {
		t.Fatalf("create asset service: %v", err)
	}

	ticket, err := service.StartUpload(context.Background(), "account", "vault", UploadRequest{
		AssetID: repository.asset.ID, ContentType: "image/jpeg", ByteSize: 20,
		SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	})
	if err != nil {
		t.Fatalf("StartUpload() error = %v", err)
	}
	if ticket.Status != UploadStatusComplete || ticket.URL != "" || objects.presignUploadCalls != 0 {
		t.Fatalf("ticket = %#v, presign calls = %d", ticket, objects.presignUploadCalls)
	}
}

func TestDiscardPendingRemovesOnlyAuthenticatedVaultAsset(t *testing.T) {
	repository := &stubAssetRepository{}
	authorizer := &stubAssetVaultAuthorizer{}
	service, err := NewService(authorizer, repository, &stubObjectStore{})
	if err != nil {
		t.Fatalf("create asset service: %v", err)
	}

	if err := service.DiscardPending(context.Background(), "account", "vault", "asset"); err != nil {
		t.Fatalf("DiscardPending() error = %v", err)
	}
	if !repository.discarded || authorizer.vaultID != "vault" {
		t.Fatalf("discarded = %v, vault = %q", repository.discarded, authorizer.vaultID)
	}
}

type stubAssetVaultAuthorizer struct {
	vaultID string
}

func (stub *stubAssetVaultAuthorizer) Get(
	_ context.Context,
	_ string,
	vaultID string,
) (vault.Metadata, error) {
	stub.vaultID = vaultID
	return vault.Metadata{}, nil
}

type stubAssetRepository struct {
	asset     Asset
	completed bool
	discarded bool
}

func (stub *stubAssetRepository) CreatePending(context.Context, Asset) (Asset, error) {
	return stub.asset, nil
}

func (stub *stubAssetRepository) Get(context.Context, string, string) (Asset, error) {
	return stub.asset, nil
}

func (stub *stubAssetRepository) MarkComplete(context.Context, string, string, time.Time) error {
	stub.completed = true
	return nil
}

func (stub *stubAssetRepository) DeletePending(context.Context, string, string) error {
	stub.discarded = true
	return nil
}

type stubObjectStore struct {
	metadata           ObjectMetadata
	uploadURL          string
	downloadURL        string
	presignUploadCalls int
}

func (stub *stubObjectStore) PresignUpload(context.Context, Asset, time.Duration) (string, error) {
	stub.presignUploadCalls++
	return stub.uploadURL, nil
}

func (stub *stubObjectStore) Stat(context.Context, string) (ObjectMetadata, error) {
	return stub.metadata, nil
}

func (stub *stubObjectStore) PresignDownload(context.Context, Asset, time.Duration) (string, error) {
	return stub.downloadURL, nil
}
