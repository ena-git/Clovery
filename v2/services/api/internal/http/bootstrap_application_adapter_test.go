package httpapi

import (
	"context"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
)

func TestBootstrapApplicationAdapterMapsDomainStateAndSource(t *testing.T) {
	migrationID := "11111111-1111-4111-8111-111111111111"
	errorCode := "migration_upload_failed"
	updatedAt := time.Date(2026, time.July, 19, 14, 0, 0, 0, time.UTC)
	service := &stubBootstrapService{job: bootstrapjob.Job{
		SourceKind:       bootstrapjob.SourceLegacyCloudKit,
		MigrationID:      &migrationID,
		IdentityState:    bootstrapjob.StageComplete,
		MigrationState:   bootstrapjob.StageNeedsAttention,
		EntitlementState: bootstrapjob.StageComplete,
		VaultState:       bootstrapjob.StagePending,
		Status:           bootstrapjob.StatusNeedsAttention,
		LastErrorCode:    &errorCode,
		RetryCount:       2,
		UpdatedAt:        updatedAt,
	}}
	application := NewBootstrapApplication(service)

	status, err := application.ResumeBootstrap(
		context.Background(), "account", "vault", "legacy_cloudkit",
	)
	if err != nil {
		t.Fatalf("ResumeBootstrap() error = %v", err)
	}
	if service.accountID != "account" || service.vaultID != "vault" ||
		service.source != bootstrapjob.SourceLegacyCloudKit {
		t.Fatalf("service scope account=%q vault=%q source=%q", service.accountID, service.vaultID, service.source)
	}
	if status.Status != "needs_attention" || status.SourceKind != "legacy_cloudkit" ||
		status.MigrationID == nil || *status.MigrationID != migrationID ||
		status.Stages.Identity != "complete" || status.Stages.Migration != "needs_attention" ||
		status.Stages.Entitlement != "complete" || status.Stages.Vault != "pending" ||
		status.LastErrorCode == nil || *status.LastErrorCode != errorCode ||
		status.RetryCount != 2 || !status.UpdatedAt.Equal(updatedAt) {
		t.Fatalf("ResumeBootstrap() status = %#v", status)
	}
}

type stubBootstrapService struct {
	accountID string
	vaultID   string
	source    bootstrapjob.SourceKind
	job       bootstrapjob.Job
}

func (service *stubBootstrapService) Get(context.Context, string) (bootstrapjob.Job, error) {
	return service.job, nil
}

func (service *stubBootstrapService) Resume(
	_ context.Context,
	accountID string,
	vaultID string,
	source bootstrapjob.SourceKind,
) (bootstrapjob.Job, error) {
	service.accountID = accountID
	service.vaultID = vaultID
	service.source = source
	return service.job, nil
}
