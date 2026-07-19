package bootstrapjob

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"regexp"

	"github.com/google/uuid"
)

var stableErrorCodePattern = regexp.MustCompile(`^[a-z][a-z0-9]*(_[a-z0-9]+)*$`)

type repository interface {
	GetByAccountID(ctx context.Context, accountID string) (Job, error)
	ResumeByAccountID(
		ctx context.Context,
		accountID string,
		vaultID string,
		source SourceKind,
	) (Job, error)
	MarkMigrationByAccountID(
		ctx context.Context,
		accountID string,
		migrationID string,
		state StageState,
		errorCode *string,
	) error
	MarkEntitlementByAccountID(
		ctx context.Context,
		accountID string,
		state StageState,
		errorCode *string,
	) error
	MarkVaultByAccountID(
		ctx context.Context,
		accountID string,
		state StageState,
		errorCode *string,
	) error
}

type Service struct {
	repository repository
}

func NewService(repository repository) (*Service, error) {
	if nilRepository(repository) {
		return nil, fmt.Errorf("bootstrap repository is required")
	}
	return &Service{repository: repository}, nil
}

func (service *Service) Get(ctx context.Context, accountID string) (Job, error) {
	if accountID == "" {
		return Job{}, ErrInvalidRequest
	}
	return service.repository.GetByAccountID(ctx, accountID)
}

func (service *Service) Resume(
	ctx context.Context,
	accountID string,
	vaultID string,
	source SourceKind,
) (Job, error) {
	if accountID == "" || vaultID == "" || !source.Valid() {
		if !source.Valid() {
			return Job{}, errors.Join(ErrInvalidRequest, ErrInvalidSourceKind)
		}
		return Job{}, ErrInvalidRequest
	}
	return service.repository.ResumeByAccountID(ctx, accountID, vaultID, source)
}

func (service *Service) MarkMigration(
	ctx context.Context,
	accountID string,
	migrationID string,
	state StageState,
	errorCode *string,
) error {
	parsedMigrationID, parseError := uuid.Parse(migrationID)
	if accountID == "" || parseError != nil || parsedMigrationID == uuid.Nil || parsedMigrationID.String() != migrationID {
		if accountID != "" {
			return errors.Join(ErrInvalidRequest, ErrInvalidMigrationID)
		}
		return ErrInvalidRequest
	}
	if err := validateStageEvent(state, errorCode); err != nil {
		return err
	}
	return service.repository.MarkMigrationByAccountID(ctx, accountID, migrationID, state, errorCode)
}

func (service *Service) MarkEntitlement(
	ctx context.Context,
	accountID string,
	state StageState,
	errorCode *string,
) error {
	if accountID == "" {
		return ErrInvalidRequest
	}
	if err := validateStageEvent(state, errorCode); err != nil {
		return err
	}
	return service.repository.MarkEntitlementByAccountID(ctx, accountID, state, errorCode)
}

func (service *Service) MarkVault(
	ctx context.Context,
	accountID string,
	state StageState,
	errorCode *string,
) error {
	if accountID == "" {
		return ErrInvalidRequest
	}
	if err := validateStageEvent(state, errorCode); err != nil {
		return err
	}
	return service.repository.MarkVaultByAccountID(ctx, accountID, state, errorCode)
}

func validateStageEvent(state StageState, errorCode *string) error {
	if !state.Valid() {
		return errors.Join(ErrInvalidRequest, ErrInvalidStageState)
	}
	if state == StageNeedsAttention {
		if errorCode == nil || !stableErrorCodePattern.MatchString(*errorCode) {
			return errors.Join(ErrInvalidRequest, ErrInvalidErrorCode)
		}
		return nil
	}
	if errorCode != nil {
		return errors.Join(ErrInvalidRequest, ErrInvalidErrorCode)
	}
	return nil
}

func nilRepository(repository repository) bool {
	if repository == nil {
		return true
	}
	value := reflect.ValueOf(repository)
	return value.Kind() == reflect.Pointer && value.IsNil()
}

func newJob(accountID string, vaultID string, source SourceKind) Job {
	migrationState := StagePending
	if source == SourceNewInstall {
		migrationState = StageComplete
	}
	return Job{
		AccountID:        accountID,
		VaultID:          vaultID,
		SourceKind:       source,
		IdentityState:    StageComplete,
		MigrationState:   migrationState,
		EntitlementState: StagePending,
		VaultState:       StagePending,
		Status:           StatusPending,
	}
}

func resumeExisting(job Job) Job {
	if job.Status == StatusNeedsAttention {
		job.Status = StatusRunning
		job.LastErrorCode = nil
		job.RetryCount++
	}
	return job
}

func markMigration(job *Job, migrationID string, state StageState, errorCode *string) error {
	if job.MigrationID != nil && *job.MigrationID != migrationID {
		return ErrConflict
	}
	if err := markStage(job, &job.MigrationState, state, errorCode); err != nil {
		return err
	}
	if job.MigrationID == nil {
		job.MigrationID = &migrationID
	}
	return nil
}

func markStage(job *Job, current *StageState, next StageState, errorCode *string) error {
	if err := validateStageEvent(next, errorCode); err != nil {
		return err
	}
	if *current == StageComplete && next != StageComplete {
		return ErrInvalidTransition
	}
	if *current == StageNeedsAttention && next == StagePending {
		return ErrInvalidTransition
	}
	*current = next
	return recalculate(job, errorCode)
}

func recalculate(job *Job, eventErrorCode *string) error {
	states := []StageState{
		job.IdentityState,
		job.MigrationState,
		job.EntitlementState,
		job.VaultState,
	}
	allComplete := true
	needsAttention := false
	for _, state := range states {
		allComplete = allComplete && state == StageComplete
		needsAttention = needsAttention || state == StageNeedsAttention
	}
	if needsAttention {
		lastErrorCode := eventErrorCode
		if lastErrorCode == nil {
			lastErrorCode = job.LastErrorCode
		}
		if lastErrorCode == nil || !stableErrorCodePattern.MatchString(*lastErrorCode) {
			return ErrInvalidRequest
		}
		job.Status = StatusNeedsAttention
		job.LastErrorCode = lastErrorCode
		return nil
	}
	job.LastErrorCode = nil
	if allComplete {
		job.Status = StatusComplete
	} else {
		job.Status = StatusRunning
	}
	return nil
}
