package httpapi

import (
	"context"
	"time"
)

type AccountBindingSummary struct {
	Provider  string    `json:"provider"`
	Issuer    string    `json:"issuer"`
	CreatedAt time.Time `json:"created_at"`
}

type AccountSummary struct {
	AccountID              string                  `json:"account_id"`
	CloveryID              string                  `json:"clovery_id"`
	Status                 string                  `json:"status"`
	CreatedAt              time.Time               `json:"created_at"`
	HasPassword            bool                    `json:"has_password"`
	PasskeyCount           int                     `json:"passkey_count"`
	RecoveryCodesRemaining int                     `json:"recovery_codes_remaining"`
	Bindings               []AccountBindingSummary `json:"bindings"`
}

type DeletionRequestSummary struct {
	ID           string    `json:"request_id"`
	Status       string    `json:"status"`
	RequestedAt  time.Time `json:"requested_at"`
	ScheduledFor time.Time `json:"scheduled_for"`
}

type AccountHTTPApplication interface {
	GetAccount(ctx context.Context, accountID string) (AccountSummary, error)
	RequestDeletion(ctx context.Context, accountID string) (DeletionRequestSummary, error)
}
