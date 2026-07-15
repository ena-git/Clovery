package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/asset"
	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
)

type MigrationHTTPApplication interface {
	Create(ctx context.Context, accountID string, vaultID string, request cloverymigration.CreateRequest) (cloverymigration.Migration, error)
	AddEntry(ctx context.Context, accountID string, vaultID string, migrationID string, entry cloverymigration.EntryInput) error
	AddAsset(ctx context.Context, accountID string, vaultID string, migrationID string, request cloverymigration.AssetInput) (asset.UploadTicket, error)
	Verify(ctx context.Context, accountID string, vaultID string, migrationID string) (cloverymigration.Report, error)
	Report(ctx context.Context, accountID string, vaultID string, migrationID string) (cloverymigration.Report, error)
}
