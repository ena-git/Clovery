package billingflow

import (
	"context"
	"errors"
	"testing"

	"github.com/clovery/clovery/services/api/internal/billing"
	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
)

func TestRestoreCompletesEntitlementBootstrapForActiveAndEmptyInventory(t *testing.T) {
	for _, test := range []struct {
		name         string
		entitlements []billing.Entitlement
	}{
		{name: "active purchase", entitlements: []billing.Entitlement{{ProductID: "com.clovery.pro.monthly", State: billing.StateActive}}},
		{name: "empty inventory", entitlements: []billing.Entitlement{}},
	} {
		t.Run(test.name, func(t *testing.T) {
			domain := &stubBillingApplication{entitlements: test.entitlements}
			tracker := &spyEntitlementTracker{}
			service := mustBillingFlow(t, domain, tracker)

			got, err := service.Restore(
				context.Background(), "account", []string{}, billing.EnvironmentSandbox,
			)
			if err != nil || len(got) != len(test.entitlements) || len(tracker.marks) != 1 ||
				tracker.marks[0].state != bootstrapjob.StageComplete {
				t.Fatalf("Restore() = %#v, marks = %#v, error = %v", got, tracker.marks, err)
			}
		})
	}
}

func TestLegacyClaimAndListDoNotCompleteEntitlementBootstrap(t *testing.T) {
	domain := &stubBillingApplication{}
	tracker := &spyEntitlementTracker{}
	service := mustBillingFlow(t, domain, tracker)

	if _, err := service.ClaimLegacy(
		context.Background(), "account", "proof", billing.EnvironmentSandbox,
	); err != nil {
		t.Fatalf("ClaimLegacy() error = %v", err)
	}
	if _, err := service.List(context.Background(), "account"); err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(tracker.marks) != 0 || len(tracker.retryableErrors) != 0 {
		t.Fatalf("marks = %#v, retryable = %#v", tracker.marks, tracker.retryableErrors)
	}
}

func TestRestoreTracksAccountConflictAndAppleOutage(t *testing.T) {
	for _, test := range []struct {
		name          string
		restoreError  error
		wantState     bootstrapjob.StageState
		wantErrorCode string
		wantRetryable bool
	}{
		{name: "claimed", restoreError: billing.ErrTransactionClaimed, wantState: bootstrapjob.StageNeedsAttention, wantErrorCode: "entitlement_account_conflict"},
		{name: "account mismatch", restoreError: billing.ErrAccountMismatch, wantState: bootstrapjob.StageNeedsAttention, wantErrorCode: "entitlement_account_conflict"},
		{name: "Apple unavailable", restoreError: billing.ErrVerificationUnavailable, wantRetryable: true, wantErrorCode: "apple_verification_temporarily_unavailable"},
	} {
		t.Run(test.name, func(t *testing.T) {
			domain := &stubBillingApplication{restoreError: test.restoreError}
			tracker := &spyEntitlementTracker{}
			service := mustBillingFlow(t, domain, tracker)

			_, err := service.Restore(
				context.Background(), "account", []string{"tx"}, billing.EnvironmentSandbox,
			)
			if !errors.Is(err, test.restoreError) {
				t.Fatalf("Restore() error = %v", err)
			}
			if test.wantRetryable {
				if len(tracker.retryableErrors) != 1 || tracker.retryableErrors[0] != test.wantErrorCode || len(tracker.marks) != 0 {
					t.Fatalf("retryable = %#v, marks = %#v", tracker.retryableErrors, tracker.marks)
				}
				return
			}
			if len(tracker.marks) != 1 || tracker.marks[0].state != test.wantState ||
				tracker.marks[0].errorCode == nil || *tracker.marks[0].errorCode != test.wantErrorCode {
				t.Fatalf("marks = %#v", tracker.marks)
			}
		})
	}
}

func mustBillingFlow(t *testing.T, domain billingApplication, tracker entitlementTracker) *Service {
	t.Helper()
	service, err := NewService(domain, tracker)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}
	return service
}

type stubBillingApplication struct {
	entitlements []billing.Entitlement
	restoreError error
}

func (*stubBillingApplication) ProcessAppleNotification(context.Context, string) error {
	return nil
}

func (*stubBillingApplication) ClaimLegacy(context.Context, string, string, billing.Environment) (billing.Entitlement, error) {
	return billing.Entitlement{}, nil
}

func (*stubBillingApplication) Verify(context.Context, string, string, billing.Environment) (billing.Entitlement, error) {
	return billing.Entitlement{}, nil
}

func (stub *stubBillingApplication) Restore(context.Context, string, []string, billing.Environment) ([]billing.Entitlement, error) {
	return stub.entitlements, stub.restoreError
}

func (stub *stubBillingApplication) List(context.Context, string) ([]billing.Entitlement, error) {
	return stub.entitlements, nil
}

type entitlementMark struct {
	state     bootstrapjob.StageState
	errorCode *string
}

type spyEntitlementTracker struct {
	marks           []entitlementMark
	retryableErrors []string
}

func (tracker *spyEntitlementTracker) MarkEntitlement(
	_ context.Context,
	_ string,
	state bootstrapjob.StageState,
	errorCode *string,
) error {
	tracker.marks = append(tracker.marks, entitlementMark{state: state, errorCode: errorCode})
	return nil
}

func (tracker *spyEntitlementTracker) RecordRetryableError(
	_ context.Context,
	_ string,
	errorCode string,
) error {
	tracker.retryableErrors = append(tracker.retryableErrors, errorCode)
	return nil
}
