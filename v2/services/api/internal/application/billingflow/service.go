package billingflow

import (
	"context"
	"errors"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/billing"
	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
)

type billingApplication interface {
	ProcessAppleNotification(context.Context, string) error
	ClaimLegacy(context.Context, string, string, billing.Environment) (billing.Entitlement, error)
	Verify(context.Context, string, string, billing.Environment) (billing.Entitlement, error)
	Restore(context.Context, string, []string, billing.Environment) ([]billing.Entitlement, error)
	List(context.Context, string) ([]billing.Entitlement, error)
}

type entitlementTracker interface {
	MarkEntitlement(context.Context, string, bootstrapjob.StageState, *string) error
	RecordRetryableError(context.Context, string, string) error
}

type Service struct {
	billing billingApplication
	tracker entitlementTracker
}

func NewService(application billingApplication, tracker entitlementTracker) (*Service, error) {
	if application == nil || tracker == nil {
		return nil, fmt.Errorf("billing flow dependencies are required")
	}
	return &Service{billing: application, tracker: tracker}, nil
}

func (service *Service) ProcessAppleNotification(ctx context.Context, signedPayload string) error {
	return service.billing.ProcessAppleNotification(ctx, signedPayload)
}

func (service *Service) ClaimLegacy(
	ctx context.Context,
	accountID string,
	signedTransactionInfo string,
	environment billing.Environment,
) (billing.Entitlement, error) {
	return service.billing.ClaimLegacy(ctx, accountID, signedTransactionInfo, environment)
}

func (service *Service) Verify(
	ctx context.Context,
	accountID string,
	transactionID string,
	environment billing.Environment,
) (billing.Entitlement, error) {
	return service.billing.Verify(ctx, accountID, transactionID, environment)
}

func (service *Service) Restore(
	ctx context.Context,
	accountID string,
	transactionIDs []string,
	environment billing.Environment,
) ([]billing.Entitlement, error) {
	entitlements, restoreError := service.billing.Restore(
		ctx, accountID, transactionIDs, environment,
	)
	switch {
	case restoreError == nil:
		if err := service.tracker.MarkEntitlement(
			ctx, accountID, bootstrapjob.StageComplete, nil,
		); err != nil {
			return entitlements, fmt.Errorf("complete entitlement bootstrap job: %w", err)
		}
	case errors.Is(restoreError, billing.ErrTransactionClaimed),
		errors.Is(restoreError, billing.ErrAccountMismatch):
		errorCode := "entitlement_account_conflict"
		if err := service.tracker.MarkEntitlement(
			ctx, accountID, bootstrapjob.StageNeedsAttention, &errorCode,
		); err != nil {
			return entitlements, errors.Join(restoreError, fmt.Errorf("flag entitlement bootstrap job: %w", err))
		}
	case errors.Is(restoreError, billing.ErrVerificationUnavailable):
		if err := service.tracker.RecordRetryableError(
			ctx, accountID, "apple_verification_temporarily_unavailable",
		); err != nil {
			return entitlements, errors.Join(restoreError, fmt.Errorf("record entitlement retry: %w", err))
		}
	}
	return entitlements, restoreError
}

func (service *Service) List(ctx context.Context, accountID string) ([]billing.Entitlement, error) {
	return service.billing.List(ctx, accountID)
}
