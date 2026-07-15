package account

import (
	"context"
	"fmt"
)

func (repository *Repository) DeleteFailedRegistration(ctx context.Context, accountID string) error {
	_, err := repository.database.ExecContext(
		ctx,
		"DELETE FROM clovery_accounts WHERE id = $1",
		accountID,
	)
	if err != nil {
		return fmt.Errorf("delete failed account registration: %w", err)
	}
	return nil
}
