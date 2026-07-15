package asset

import "context"

func (service *Service) DiscardPending(
	ctx context.Context,
	accountID string,
	vaultID string,
	assetID string,
) error {
	if _, err := service.vaults.Get(ctx, accountID, vaultID); err != nil {
		return err
	}
	return service.repository.DeletePending(ctx, vaultID, assetID)
}
