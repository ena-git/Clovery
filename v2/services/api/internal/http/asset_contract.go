package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/asset"
)

type AssetHTTPApplication interface {
	StartUpload(
		ctx context.Context,
		accountID string,
		vaultID string,
		request asset.UploadRequest,
	) (asset.UploadTicket, error)
	Complete(ctx context.Context, accountID string, vaultID string, assetID string) error
	Download(
		ctx context.Context,
		accountID string,
		vaultID string,
		assetID string,
	) (asset.DownloadTicket, error)
}
