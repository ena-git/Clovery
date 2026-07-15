package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/vault"
)

type vaultService interface {
	Get(ctx context.Context, accountID string, vaultID string) (vault.Metadata, error)
}

type vaultApplicationAdapter struct {
	service vaultService
}

func NewVaultApplication(service vaultService) VaultHTTPApplication {
	return &vaultApplicationAdapter{service: service}
}

func (adapter *vaultApplicationAdapter) GetVault(
	ctx context.Context,
	accountID string,
	vaultID string,
) (VaultSummary, error) {
	metadata, err := adapter.service.Get(ctx, accountID, vaultID)
	return VaultSummary{
		ID: metadata.ID, Status: metadata.Status, CreatedAt: metadata.CreatedAt,
	}, err
}
