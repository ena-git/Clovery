package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/billing"
)

type BillingHTTPApplication interface {
	ProcessAppleNotification(ctx context.Context, signedPayload string) error
	ClaimLegacy(
		ctx context.Context,
		accountID string,
		signedTransactionInfo string,
		environment billing.Environment,
	) (billing.Entitlement, error)
	Verify(
		ctx context.Context,
		accountID string,
		transactionID string,
		environment billing.Environment,
	) (billing.Entitlement, error)
	Restore(
		ctx context.Context,
		accountID string,
		transactionIDs []string,
		environment billing.Environment,
	) ([]billing.Entitlement, error)
	List(ctx context.Context, accountID string) ([]billing.Entitlement, error)
}

type appleNotificationRequest struct {
	SignedPayload string `json:"signedPayload"`
}

type appleTransactionVerifyRequest struct {
	TransactionID string              `json:"transaction_id"`
	Environment   billing.Environment `json:"environment"`
}

type appleLegacyClaimRequest struct {
	SignedTransactionInfo string              `json:"signed_transaction_info"`
	Environment           billing.Environment `json:"environment"`
}

type appleRestoreRequest struct {
	TransactionIDs []string            `json:"transaction_ids"`
	Environment    billing.Environment `json:"environment"`
}

type entitlementListResponse struct {
	Entitlements []billing.Entitlement `json:"entitlements"`
}
