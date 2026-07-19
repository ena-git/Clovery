package bootstrapjob

import (
	"context"
	"errors"
	"testing"
)

func TestServiceValidatesBootstrapCommandsBeforeRepositoryAccess(t *testing.T) {
	store := &stubRepository{}
	service, err := NewService(store)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}

	if _, err := service.Resume(context.Background(), "account", "vault", SourceKind("other")); !errors.Is(err, ErrInvalidSourceKind) {
		t.Fatalf("Resume() error = %v, want ErrInvalidSourceKind", err)
	}
	if err := service.MarkVault(context.Background(), "account", StageState("running"), nil); !errors.Is(err, ErrInvalidStageState) {
		t.Fatalf("MarkVault() error = %v, want ErrInvalidStageState", err)
	}
	invalidCode := "Contains Spaces"
	if err := service.MarkEntitlement(context.Background(), "account", StageNeedsAttention, &invalidCode); !errors.Is(err, ErrInvalidErrorCode) {
		t.Fatalf("MarkEntitlement() error = %v, want ErrInvalidErrorCode", err)
	}
	if err := service.MarkMigration(context.Background(), "account", "not-a-uuid", StageComplete, nil); !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("MarkMigration() error = %v, want ErrInvalidRequest", err)
	}
	if store.calls != 0 {
		t.Fatalf("repository calls = %d, want 0", store.calls)
	}
}

func TestStageFailuresMoveOverallJobToNeedsAttention(t *testing.T) {
	errorCode := "bootstrap_stage_failed"
	tests := []struct {
		name string
		mark func(*Job) error
	}{
		{
			name: "migration",
			mark: func(job *Job) error {
				return markMigration(job, "11111111-1111-4111-8111-111111111111", StageNeedsAttention, &errorCode)
			},
		},
		{
			name: "entitlement",
			mark: func(job *Job) error {
				return markStage(job, &job.EntitlementState, StageNeedsAttention, &errorCode)
			},
		},
		{
			name: "vault",
			mark: func(job *Job) error {
				return markStage(job, &job.VaultState, StageNeedsAttention, &errorCode)
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			job := newJob("account", "vault", SourceLegacyLocal)
			if err := test.mark(&job); err != nil {
				t.Fatalf("mark stage error = %v", err)
			}
			if job.Status != StatusNeedsAttention || job.LastErrorCode == nil || *job.LastErrorCode != errorCode {
				t.Fatalf("attention job = %#v", job)
			}
		})
	}
}

func TestNewServiceRejectsNilRepository(t *testing.T) {
	if _, err := NewService(nil); err == nil {
		t.Fatal("NewService(nil) error = nil")
	}
	var typedNil *stubRepository
	if _, err := NewService(typedNil); err == nil {
		t.Fatal("NewService(typed nil) error = nil")
	}
}

type stubRepository struct {
	calls int
	job   Job
	err   error
}

func (repository *stubRepository) GetByAccountID(context.Context, string) (Job, error) {
	repository.calls++
	return repository.job, repository.err
}

func (repository *stubRepository) ResumeByAccountID(context.Context, string, string, SourceKind) (Job, error) {
	repository.calls++
	return repository.job, repository.err
}

func (repository *stubRepository) MarkMigrationByAccountID(context.Context, string, string, StageState, *string) error {
	repository.calls++
	return repository.err
}

func (repository *stubRepository) MarkEntitlementByAccountID(context.Context, string, StageState, *string) error {
	repository.calls++
	return repository.err
}

func (repository *stubRepository) MarkVaultByAccountID(context.Context, string, StageState, *string) error {
	repository.calls++
	return repository.err
}
