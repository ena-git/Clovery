package bootstrapjob

import (
	"context"
	"errors"
	"testing"
)

func TestResumeValidatesVaultCheckpointAgainstServerCursor(t *testing.T) {
	for _, test := range []struct {
		name       string
		checkpoint VaultCheckpoint
		wantState  StageState
	}{
		{name: "cursor behind", checkpoint: VaultCheckpoint{Cursor: 41}, wantState: StagePending},
		{name: "more pages", checkpoint: VaultCheckpoint{Cursor: 42, HasMore: true}, wantState: StagePending},
		{name: "caught up", checkpoint: VaultCheckpoint{Cursor: 42}, wantState: StageComplete},
		{name: "client ahead", checkpoint: VaultCheckpoint{Cursor: 43}, wantState: StageComplete},
	} {
		t.Run(test.name, func(t *testing.T) {
			repository := newCheckpointRepository()
			cursors := &stubVaultCursors{latest: 42}
			service, err := NewService(repository, cursors)
			if err != nil {
				t.Fatalf("NewService() error = %v", err)
			}

			job, err := service.Resume(
				context.Background(), "account", "vault", SourceLegacyLocal, &test.checkpoint,
			)
			if err != nil || job.VaultState != test.wantState || cursors.vaultID != "vault" {
				t.Fatalf("Resume() job = %#v, cursor vault = %q, error = %v", job, cursors.vaultID, err)
			}
		})
	}
}

func TestVaultCheckpointCompletesJobOnlyAfterAllStagesComplete(t *testing.T) {
	repository := newCheckpointRepository()
	repository.job.MigrationState = StageComplete
	repository.job.EntitlementState = StageComplete
	service, _ := NewService(repository, &stubVaultCursors{latest: 42})

	job, err := service.Resume(
		context.Background(), "account", "vault", SourceLegacyLocal,
		&VaultCheckpoint{Cursor: 42, HasMore: false},
	)
	if err != nil || job.Status != StatusComplete || job.VaultState != StageComplete {
		t.Fatalf("Resume() job = %#v, error = %v", job, err)
	}
}

func TestCompletedVaultCheckpointIsNotReopenedByLaterChanges(t *testing.T) {
	repository := newCheckpointRepository()
	cursors := &stubVaultCursors{latest: 42}
	service, _ := NewService(repository, cursors)
	if _, err := service.Resume(
		context.Background(), "account", "vault", SourceLegacyLocal, &VaultCheckpoint{Cursor: 42},
	); err != nil {
		t.Fatalf("first Resume() error = %v", err)
	}
	cursors.latest = 100

	job, err := service.Resume(
		context.Background(), "account", "vault", SourceLegacyLocal, &VaultCheckpoint{Cursor: 42},
	)
	if err != nil || job.VaultState != StageComplete || cursors.calls != 1 {
		t.Fatalf("second Resume() job = %#v, cursor calls = %d, error = %v", job, cursors.calls, err)
	}
}

func TestVaultCheckpointNeverQueriesUnownedVault(t *testing.T) {
	repository := newCheckpointRepository()
	repository.resumeError = ErrNotFound
	cursors := &stubVaultCursors{latest: 42}
	service, _ := NewService(repository, cursors)

	_, err := service.Resume(
		context.Background(), "other-account", "foreign-vault", SourceLegacyLocal,
		&VaultCheckpoint{Cursor: 42},
	)
	if !errors.Is(err, ErrNotFound) || cursors.calls != 0 {
		t.Fatalf("Resume() cursor calls = %d, error = %v", cursors.calls, err)
	}
}

type stubVaultCursors struct {
	latest  int64
	vaultID string
	calls   int
}

func (cursors *stubVaultCursors) LatestCursor(_ context.Context, vaultID string) (int64, error) {
	cursors.calls++
	cursors.vaultID = vaultID
	return cursors.latest, nil
}

type checkpointRepository struct {
	job         Job
	resumeError error
}

func newCheckpointRepository() *checkpointRepository {
	return &checkpointRepository{job: Job{
		AccountID: "account", VaultID: "vault", SourceKind: SourceLegacyLocal,
		IdentityState: StageComplete, MigrationState: StagePending,
		EntitlementState: StagePending, VaultState: StagePending, Status: StatusPending,
	}}
}

func (repository *checkpointRepository) GetByAccountID(context.Context, string) (Job, error) {
	return repository.job, nil
}

func (repository *checkpointRepository) ResumeByAccountID(context.Context, string, string, SourceKind) (Job, error) {
	return repository.job, repository.resumeError
}

func (repository *checkpointRepository) MarkMigrationByAccountID(context.Context, string, string, StageState, *string) error {
	return nil
}

func (repository *checkpointRepository) MarkEntitlementByAccountID(context.Context, string, StageState, *string) error {
	return nil
}

func (repository *checkpointRepository) MarkVaultByAccountID(
	_ context.Context,
	_ string,
	state StageState,
	errorCode *string,
) error {
	return markStage(&repository.job, &repository.job.VaultState, state, errorCode)
}

func (repository *checkpointRepository) RecordRetryableErrorByAccountID(context.Context, string, string) error {
	return nil
}
