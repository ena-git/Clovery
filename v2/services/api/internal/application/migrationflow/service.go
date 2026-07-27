package migrationflow

import (
	"context"
	"errors"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/asset"
	"github.com/clovery/clovery/services/api/internal/bootstrapjob"
	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
	"github.com/clovery/clovery/services/api/internal/vault"
)

type migrationApplication interface {
	Create(context.Context, string, string, cloverymigration.CreateRequest) (cloverymigration.Migration, error)
	AddEntry(context.Context, string, string, string, cloverymigration.EntryInput) error
	AddAsset(context.Context, string, string, string, cloverymigration.AssetInput) (asset.UploadTicket, error)
	Assets(context.Context, string, string, string) ([]cloverymigration.AssetMapping, error)
	Verify(context.Context, string, string, string) (cloverymigration.Report, error)
	Report(context.Context, string, string, string) (cloverymigration.Report, error)
}

type bootstrapTracker interface {
	MarkMigration(context.Context, string, string, bootstrapjob.StageState, *string) error
	RecordRetryableError(context.Context, string, string) error
}

type Service struct {
	migrations migrationApplication
	tracker    bootstrapTracker
}

func NewService(migrations migrationApplication, tracker bootstrapTracker) (*Service, error) {
	if migrations == nil || tracker == nil {
		return nil, fmt.Errorf("migration flow dependencies are required")
	}
	return &Service{migrations: migrations, tracker: tracker}, nil
}

func (service *Service) Create(
	ctx context.Context,
	accountID string,
	vaultID string,
	request cloverymigration.CreateRequest,
) (cloverymigration.Migration, error) {
	created, err := service.migrations.Create(ctx, accountID, vaultID, request)
	if err != nil {
		return cloverymigration.Migration{}, err
	}
	if err := service.tracker.MarkMigration(
		ctx, accountID, created.ID, bootstrapjob.StagePending, nil,
	); err != nil {
		return created, fmt.Errorf("attach migration bootstrap job: %w", err)
	}
	return created, nil
}

func (service *Service) AddEntry(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
	entry cloverymigration.EntryInput,
) error {
	return service.migrations.AddEntry(ctx, accountID, vaultID, migrationID, entry)
}

func (service *Service) AddAsset(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
	request cloverymigration.AssetInput,
) (asset.UploadTicket, error) {
	return service.migrations.AddAsset(ctx, accountID, vaultID, migrationID, request)
}

func (service *Service) Assets(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
) ([]cloverymigration.AssetMapping, error) {
	return service.migrations.Assets(ctx, accountID, vaultID, migrationID)
}

func (service *Service) Verify(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
) (cloverymigration.Report, error) {
	report, verifyError := service.migrations.Verify(ctx, accountID, vaultID, migrationID)
	switch {
	case verifyError == nil:
		if err := service.tracker.MarkMigration(
			ctx, accountID, migrationID, bootstrapjob.StageComplete, nil,
		); err != nil {
			return report, fmt.Errorf("complete migration bootstrap job: %w", err)
		}
	case errors.Is(verifyError, cloverymigration.ErrIntegrityMismatch),
		errors.Is(verifyError, cloverymigration.ErrVerificationFailed):
		errorCode := "migration_integrity_failed"
		if err := service.tracker.MarkMigration(
			ctx, accountID, migrationID, bootstrapjob.StageNeedsAttention, &errorCode,
		); err != nil {
			return report, errors.Join(verifyError, fmt.Errorf("flag migration bootstrap job: %w", err))
		}
	case shouldIgnoreBootstrapError(verifyError):
		return report, verifyError
	default:
		if err := service.tracker.RecordRetryableError(
			ctx, accountID, "migration_temporarily_unavailable",
		); err != nil {
			return report, errors.Join(verifyError, fmt.Errorf("record migration retry: %w", err))
		}
	}
	return report, verifyError
}

func (service *Service) Report(
	ctx context.Context,
	accountID string,
	vaultID string,
	migrationID string,
) (cloverymigration.Report, error) {
	return service.migrations.Report(ctx, accountID, vaultID, migrationID)
}

func shouldIgnoreBootstrapError(err error) bool {
	return errors.Is(err, vault.ErrForbidden) ||
		errors.Is(err, cloverymigration.ErrInvalidBundle) ||
		errors.Is(err, cloverymigration.ErrUnsupportedFormat) ||
		errors.Is(err, cloverymigration.ErrMigrationMismatch) ||
		errors.Is(err, cloverymigration.ErrMigrationNotFound) ||
		errors.Is(err, cloverymigration.ErrMigrationNotVerified)
}
