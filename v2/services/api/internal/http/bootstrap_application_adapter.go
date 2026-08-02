package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
)

type bootstrapService interface {
	Get(ctx context.Context, accountID string) (bootstrapjob.Job, error)
	Resume(
		ctx context.Context,
		accountID string,
		vaultID string,
		source bootstrapjob.SourceKind,
		checkpoints ...*bootstrapjob.VaultCheckpoint,
	) (bootstrapjob.Job, error)
}

type bootstrapApplicationAdapter struct {
	service bootstrapService
}

func NewBootstrapApplication(service bootstrapService) BootstrapHTTPApplication {
	return &bootstrapApplicationAdapter{service: service}
}

func (adapter *bootstrapApplicationAdapter) GetBootstrap(
	ctx context.Context,
	accountID string,
) (BootstrapStatus, error) {
	job, err := adapter.service.Get(ctx, accountID)
	return bootstrapStatus(job), err
}

func (adapter *bootstrapApplicationAdapter) ResumeBootstrap(
	ctx context.Context,
	accountID string,
	vaultID string,
	sourceKind string,
	vaultCheckpoint *BootstrapVaultCheckpoint,
) (BootstrapStatus, error) {
	var checkpoint *bootstrapjob.VaultCheckpoint
	if vaultCheckpoint != nil {
		checkpoint = &bootstrapjob.VaultCheckpoint{
			Cursor: vaultCheckpoint.Cursor, HasMore: vaultCheckpoint.HasMore,
		}
	}
	job, err := adapter.service.Resume(
		ctx, accountID, vaultID, bootstrapjob.SourceKind(sourceKind), checkpoint,
	)
	return bootstrapStatus(job), err
}

func bootstrapStatus(job bootstrapjob.Job) BootstrapStatus {
	return BootstrapStatus{
		Status:        string(job.Status),
		SourceKind:    string(job.SourceKind),
		MigrationID:   job.MigrationID,
		LastErrorCode: job.LastErrorCode,
		RetryCount:    job.RetryCount,
		UpdatedAt:     job.UpdatedAt,
		Stages: BootstrapStages{
			Identity:    string(job.IdentityState),
			Migration:   string(job.MigrationState),
			Entitlement: string(job.EntitlementState),
			Vault:       string(job.VaultState),
		},
	}
}
