package httpapi

import (
	"context"
	"time"
)

type VaultSummary struct {
	ID        string    `json:"vault_id"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type VaultHTTPApplication interface {
	GetVault(ctx context.Context, accountID string, vaultID string) (VaultSummary, error)
}
