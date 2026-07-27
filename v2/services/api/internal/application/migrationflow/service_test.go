package migrationflow

import (
	"context"
	"errors"
	"testing"

	"github.com/clovery/clovery/services/api/internal/asset"
	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
	"github.com/clovery/clovery/services/api/internal/vault"
)

const flowMigrationID = "11111111-1111-4111-8111-111111111111"

func TestCreateAttachesMigrationToAuthenticatedBootstrapJob(t *testing.T) {
	domain := &stubMigrationApplication{migration: cloverymigration.Migration{ID: flowMigrationID}}
	tracker := &spyBootstrapTracker{}
	service := mustMigrationFlow(t, domain, tracker)

	_, err := service.Create(context.Background(), "account", "vault", cloverymigration.CreateRequest{})
	if err != nil || len(tracker.marks) != 1 || tracker.marks[0].accountID != "account" ||
		tracker.marks[0].migrationID != flowMigrationID || tracker.marks[0].state != bootstrapjob.StagePending {
		t.Fatalf("Create() marks = %#v, error = %v", tracker.marks, err)
	}
}

func TestVerifyTracksStableBootstrapOutcome(t *testing.T) {
	for _, test := range []struct {
		name          string
		verifyError   error
		wantState     bootstrapjob.StageState
		wantErrorCode string
		wantRetryable bool
	}{
		{name: "success", wantState: bootstrapjob.StageComplete},
		{name: "integrity failure", verifyError: cloverymigration.ErrIntegrityMismatch, wantState: bootstrapjob.StageNeedsAttention, wantErrorCode: "migration_integrity_failed"},
		{name: "count failure", verifyError: cloverymigration.ErrVerificationFailed, wantState: bootstrapjob.StageNeedsAttention, wantErrorCode: "migration_integrity_failed"},
		{name: "database unavailable", verifyError: errors.New("database unavailable"), wantRetryable: true, wantErrorCode: "migration_temporarily_unavailable"},
	} {
		t.Run(test.name, func(t *testing.T) {
			domain := &stubMigrationApplication{verifyError: test.verifyError}
			tracker := &spyBootstrapTracker{}
			service := mustMigrationFlow(t, domain, tracker)

			_, err := service.Verify(context.Background(), "account", "vault", flowMigrationID)
			if !errors.Is(err, test.verifyError) {
				t.Fatalf("Verify() error = %v", err)
			}
			if test.wantRetryable {
				if len(tracker.retryableErrors) != 1 || tracker.retryableErrors[0] != test.wantErrorCode || len(tracker.marks) != 0 {
					t.Fatalf("retryable = %#v, marks = %#v", tracker.retryableErrors, tracker.marks)
				}
				return
			}
			if len(tracker.marks) != 1 || tracker.marks[0].state != test.wantState {
				t.Fatalf("marks = %#v", tracker.marks)
			}
			if test.wantErrorCode == "" {
				if tracker.marks[0].errorCode != nil {
					t.Fatalf("error code = %v", tracker.marks[0].errorCode)
				}
			} else if tracker.marks[0].errorCode == nil || *tracker.marks[0].errorCode != test.wantErrorCode {
				t.Fatalf("error code = %v", tracker.marks[0].errorCode)
			}
		})
	}
}

func TestRepeatedSuccessfulVerifyRemainsComplete(t *testing.T) {
	domain := &stubMigrationApplication{}
	tracker := &spyBootstrapTracker{}
	service := mustMigrationFlow(t, domain, tracker)

	for range 2 {
		if _, err := service.Verify(context.Background(), "account", "vault", flowMigrationID); err != nil {
			t.Fatalf("Verify() error = %v", err)
		}
	}
	if len(tracker.marks) != 2 || tracker.marks[0].state != bootstrapjob.StageComplete ||
		tracker.marks[1].state != bootstrapjob.StageComplete {
		t.Fatalf("marks = %#v", tracker.marks)
	}
}

func TestAnotherAccountsMigrationCannotUpdateBootstrapJob(t *testing.T) {
	domain := &stubMigrationApplication{verifyError: vault.ErrForbidden}
	tracker := &spyBootstrapTracker{}
	service := mustMigrationFlow(t, domain, tracker)

	_, err := service.Verify(context.Background(), "other-account", "vault", flowMigrationID)
	if !errors.Is(err, vault.ErrForbidden) || len(tracker.marks) != 0 || len(tracker.retryableErrors) != 0 {
		t.Fatalf("Verify() marks = %#v, retryable = %#v, error = %v", tracker.marks, tracker.retryableErrors, err)
	}
}

func mustMigrationFlow(
	t *testing.T,
	domain migrationApplication,
	tracker bootstrapTracker,
) *Service {
	t.Helper()
	service, err := NewService(domain, tracker)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}
	return service
}

type stubMigrationApplication struct {
	migration   cloverymigration.Migration
	verifyError error
}

func (stub *stubMigrationApplication) Create(context.Context, string, string, cloverymigration.CreateRequest) (cloverymigration.Migration, error) {
	return stub.migration, nil
}

func (*stubMigrationApplication) AddEntry(context.Context, string, string, string, cloverymigration.EntryInput) error {
	return nil
}

func (*stubMigrationApplication) AddAsset(context.Context, string, string, string, cloverymigration.AssetInput) (asset.UploadTicket, error) {
	return asset.UploadTicket{}, nil
}

func (*stubMigrationApplication) Assets(context.Context, string, string, string) ([]cloverymigration.AssetMapping, error) {
	return nil, nil
}

func (stub *stubMigrationApplication) Verify(context.Context, string, string, string) (cloverymigration.Report, error) {
	return cloverymigration.Report{}, stub.verifyError
}

func (*stubMigrationApplication) Report(context.Context, string, string, string) (cloverymigration.Report, error) {
	return cloverymigration.Report{}, nil
}

type bootstrapMark struct {
	accountID   string
	migrationID string
	state       bootstrapjob.StageState
	errorCode   *string
}

type spyBootstrapTracker struct {
	marks           []bootstrapMark
	retryableErrors []string
}

func (tracker *spyBootstrapTracker) MarkMigration(
	_ context.Context,
	accountID string,
	migrationID string,
	state bootstrapjob.StageState,
	errorCode *string,
) error {
	tracker.marks = append(tracker.marks, bootstrapMark{
		accountID: accountID, migrationID: migrationID, state: state, errorCode: errorCode,
	})
	return nil
}

func (tracker *spyBootstrapTracker) RecordRetryableError(
	_ context.Context,
	_ string,
	errorCode string,
) error {
	tracker.retryableErrors = append(tracker.retryableErrors, errorCode)
	return nil
}
