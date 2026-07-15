package migration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/clovery/clovery/services/api/internal/asset"
	"github.com/clovery/clovery/services/api/internal/vault"
	"github.com/google/uuid"
)

var (
	ErrUnsupportedFormat  = errors.New("unsupported migration format")
	ErrInvalidBundle      = errors.New("invalid migration bundle")
	ErrIntegrityMismatch  = errors.New("migration item integrity mismatch")
	ErrMigrationMismatch  = errors.New("migration ID content mismatch")
	ErrVerificationFailed = errors.New("migration verification failed")
	ErrEntryCollision     = errors.New("migration entry collides with existing Vault data")
)

type repository interface {
	Create(ctx context.Context, migration Migration) (Migration, error)
	AddEntry(ctx context.Context, vaultID string, migrationID string, entry EntryInput) error
	AddAsset(ctx context.Context, vaultID string, migrationID string, assetID string, sourceFilename string, byteSize int64, sha256 string) error
	Verify(ctx context.Context, vaultID string, migrationID string) (Report, error)
	GetReport(ctx context.Context, vaultID string, migrationID string) (Report, error)
	RecordError(ctx context.Context, vaultID string, migrationID string, code string) error
}

type vaultAuthorizer interface {
	Get(ctx context.Context, accountID string, vaultID string) (vault.Metadata, error)
}

type Service struct {
	vaults     vaultAuthorizer
	repository repository
	now        func() time.Time
	assets     assetUploader
}

type assetUploader interface {
	StartUpload(ctx context.Context, accountID string, vaultID string, request asset.UploadRequest) (asset.UploadTicket, error)
}

func NewService(vaults vaultAuthorizer, repository repository, assets ...assetUploader) (*Service, error) {
	if vaults == nil || repository == nil {
		return nil, fmt.Errorf("migration service dependencies are required")
	}
	service := &Service{vaults: vaults, repository: repository, now: func() time.Time { return time.Now().UTC() }}
	if len(assets) > 0 {
		service.assets = assets[0]
	}
	return service, nil
}

func (service *Service) AddAsset(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
	request AssetInput,
) (asset.UploadTicket, error) {
	request.SourceFilename = strings.TrimSpace(request.SourceFilename)
	if service.assets == nil || uuid.Validate(migrationID) != nil ||
		!migrationPhotoNamePattern.MatchString(request.SourceFilename) {
		return asset.UploadTicket{}, ErrInvalidBundle
	}
	uploadRequest := request.uploadRequest()
	ticket, err := service.assets.StartUpload(ctx, accountID, vaultID, uploadRequest)
	if err != nil {
		return asset.UploadTicket{}, err
	}
	if err := service.repository.AddAsset(
		ctx, vaultID, migrationID, request.AssetID, request.SourceFilename,
		request.ByteSize, strings.ToLower(request.SHA256),
	); err != nil {
		_ = service.repository.RecordError(ctx, vaultID, migrationID, "asset_manifest_mismatch")
		return asset.UploadTicket{}, err
	}
	return ticket, nil
}

func (service *Service) Create(
	ctx context.Context,
	accountID string,
	vaultID string,
	request CreateRequest,
) (Migration, error) {
	if request.FormatVersion != 1 {
		return Migration{}, ErrUnsupportedFormat
	}
	if request.Source != "v1_bundle" && request.Source != "legacy_cloudkit" {
		return Migration{}, ErrInvalidBundle
	}
	request.ManifestSHA256 = strings.ToLower(strings.TrimSpace(request.ManifestSHA256))
	if uuid.Validate(request.MigrationID) != nil || request.EntryCount < 0 || request.AssetCount < 0 ||
		request.TotalBytes < 0 || !migrationSHA256Pattern.MatchString(request.ManifestSHA256) {
		return Migration{}, ErrInvalidBundle
	}
	manifest, manifestBytes, decodedManifest, err := decodeBundleManifest(request)
	if err != nil {
		return Migration{}, err
	}
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return Migration{}, err
	}
	created, err := service.repository.Create(ctx, Migration{
		ID: request.MigrationID, VaultID: vaultID, FormatVersion: request.FormatVersion,
		Source: request.Source, EntryCount: request.EntryCount, DeletedCount: decodedManifest.DeletedCount,
		AssetCount: request.AssetCount,
		TotalBytes: request.TotalBytes, ManifestSHA256: request.ManifestSHA256,
		Manifest: manifest, ManifestBytes: manifestBytes,
		Status: "uploading", CreatedAt: service.now(),
	})
	if errors.Is(err, ErrMigrationMismatch) {
		_ = service.repository.RecordError(ctx, vaultID, request.MigrationID, "migration_id_content_mismatch")
	}
	return created, err
}

func (service *Service) AddEntry(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
	entry EntryInput,
) error {
	if uuid.Validate(migrationID) != nil {
		return ErrInvalidBundle
	}
	sourceEntryID, internalEntryID, err := normalizeEntryIdentity(vaultID, entry.EntryID)
	if err != nil {
		return err
	}
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return err
	}
	canonical, err := canonicalJSON(entry.Payload)
	if err != nil {
		_ = service.repository.RecordError(ctx, vaultID, migrationID, "entry_payload_invalid")
		return ErrInvalidBundle
	}
	if entry.DeletedAt != nil && string(canonical) != "{}" {
		_ = service.repository.RecordError(ctx, vaultID, migrationID, "deleted_entry_payload_invalid")
		return ErrInvalidBundle
	}
	digest := sha256.Sum256(canonical)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), strings.TrimSpace(entry.SHA256)) {
		_ = service.repository.RecordError(ctx, vaultID, migrationID, "entry_sha256_mismatch")
		return ErrIntegrityMismatch
	}
	entry.Payload = canonical
	entry.SHA256 = hex.EncodeToString(digest[:])
	entry.SourceEntryID = sourceEntryID
	entry.EntryID = internalEntryID
	err = service.repository.AddEntry(ctx, vaultID, migrationID, entry)
	if errors.Is(err, ErrMigrationMismatch) {
		_ = service.repository.RecordError(ctx, vaultID, migrationID, "entry_manifest_mismatch")
	}
	return err
}

func (service *Service) Verify(ctx context.Context, accountID string, vaultID string, migrationID string) (Report, error) {
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return Report{}, err
	}
	return service.repository.Verify(ctx, vaultID, migrationID)
}

func (service *Service) Report(ctx context.Context, accountID string, vaultID string, migrationID string) (Report, error) {
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return Report{}, err
	}
	return service.repository.GetReport(ctx, vaultID, migrationID)
}

func canonicalJSON(payload json.RawMessage) (json.RawMessage, error) {
	var value any
	if len(payload) == 0 || json.Unmarshal(payload, &value) != nil {
		return nil, ErrInvalidBundle
	}
	return json.Marshal(value)
}
