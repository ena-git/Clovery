package asset

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/clovery/clovery/services/api/internal/vault"
	"github.com/google/uuid"
)

var (
	ErrInvalidAsset          = errors.New("invalid asset")
	ErrAssetNotReady         = errors.New("asset is not ready")
	ErrIntegrityMismatch     = errors.New("asset integrity mismatch")
	ErrAssetMetadataMismatch = errors.New("asset ID metadata mismatch")
	ErrAssetNotFound         = errors.New("asset not found")
)

const (
	assetURLLifetime  = 15 * time.Minute
	maximumAssetSize  = 50 * 1024 * 1024
	noOverwriteHeader = "If-None-Match"
	noOverwriteValue  = "*"
)

var sha256Pattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type repository interface {
	CreatePending(ctx context.Context, asset Asset) (Asset, error)
	Get(ctx context.Context, vaultID string, assetID string) (Asset, error)
	MarkComplete(ctx context.Context, vaultID string, assetID string, completedAt time.Time) error
	DeletePending(ctx context.Context, vaultID string, assetID string) error
}

type objectStore interface {
	PresignUpload(ctx context.Context, asset Asset, lifetime time.Duration) (string, error)
	Stat(ctx context.Context, objectKey string) (ObjectMetadata, error)
	PresignDownload(ctx context.Context, asset Asset, lifetime time.Duration) (string, error)
}

type vaultAuthorizer interface {
	Get(ctx context.Context, accountID string, vaultID string) (vault.Metadata, error)
}

type Service struct {
	vaults     vaultAuthorizer
	repository repository
	objects    objectStore
	now        func() time.Time
}

func NewService(vaults vaultAuthorizer, repository repository, objects objectStore) (*Service, error) {
	if vaults == nil || repository == nil || objects == nil {
		return nil, fmt.Errorf("asset service dependencies are required")
	}
	return &Service{
		vaults: vaults, repository: repository, objects: objects,
		now: func() time.Time { return time.Now().UTC() },
	}, nil
}

func (service *Service) StartUpload(
	ctx context.Context,
	accountID string,
	vaultID string,
	request UploadRequest,
) (UploadTicket, error) {
	request.ContentType = strings.ToLower(strings.TrimSpace(request.ContentType))
	request.SHA256 = strings.ToLower(strings.TrimSpace(request.SHA256))
	if uuid.Validate(request.AssetID) != nil || request.ByteSize < 1 || request.ByteSize > maximumAssetSize ||
		!sha256Pattern.MatchString(request.SHA256) || !allowedImageType(request.ContentType) {
		return UploadTicket{}, ErrInvalidAsset
	}
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return UploadTicket{}, err
	}
	asset, err := service.repository.CreatePending(ctx, Asset{
		ID: request.AssetID, VaultID: vaultID, ObjectKey: vaultID + "/" + request.AssetID,
		ContentType: request.ContentType, ByteSize: request.ByteSize, SHA256: request.SHA256,
		Status: StatusPending, CreatedAt: service.now(),
	})
	if err != nil {
		return UploadTicket{}, err
	}
	if asset.Status == StatusComplete {
		return UploadTicket{AssetID: asset.ID, Status: UploadStatusComplete}, nil
	}
	url, err := service.objects.PresignUpload(ctx, asset, assetURLLifetime)
	if err != nil {
		return UploadTicket{}, err
	}
	expiresAt := service.now().Add(assetURLLifetime)
	return UploadTicket{
		AssetID: asset.ID,
		Status:  UploadStatusRequired,
		URL:     url,
		Headers: map[string]string{
			"Content-Type": asset.ContentType, "X-Amz-Meta-Sha256": asset.SHA256,
			noOverwriteHeader: noOverwriteValue,
		},
		ExpiresAt: &expiresAt,
	}, nil
}

func (service *Service) Complete(ctx context.Context, accountID string, vaultID string, assetID string) error {
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return err
	}
	asset, err := service.repository.Get(ctx, vaultID, assetID)
	if err != nil {
		return err
	}
	metadata, err := service.objects.Stat(ctx, asset.ObjectKey)
	if err != nil {
		return err
	}
	if metadata.ByteSize != asset.ByteSize || !strings.EqualFold(metadata.SHA256, asset.SHA256) {
		return ErrIntegrityMismatch
	}
	return service.repository.MarkComplete(ctx, vaultID, assetID, service.now())
}

func (service *Service) Download(
	ctx context.Context,
	accountID string,
	vaultID string,
	assetID string,
) (DownloadTicket, error) {
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return DownloadTicket{}, err
	}
	asset, err := service.repository.Get(ctx, vaultID, assetID)
	if err != nil {
		return DownloadTicket{}, err
	}
	if asset.Status != StatusComplete {
		return DownloadTicket{}, ErrAssetNotReady
	}
	url, err := service.objects.PresignDownload(ctx, asset, assetURLLifetime)
	if err != nil {
		return DownloadTicket{}, err
	}
	return DownloadTicket{AssetID: asset.ID, URL: url, ExpiresAt: service.now().Add(assetURLLifetime)}, nil
}

func allowedImageType(contentType string) bool {
	switch contentType {
	case "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp":
		return true
	default:
		return false
	}
}
