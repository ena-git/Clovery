package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

func (repository *PostgresRepository) Verify(
	ctx context.Context,
	vaultID string,
	migrationID string,
) (Report, error) {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return Report{}, fmt.Errorf("begin migration verification: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	status, err := lockAndLoadMigration(ctx, transaction, vaultID, migrationID)
	if err != nil {
		return Report{}, err
	}
	if status == "verified" {
		return commitStoredReport(ctx, transaction, vaultID, migrationID)
	}

	report, err := loadReport(ctx, transaction, vaultID, migrationID)
	if err != nil {
		return Report{}, err
	}
	if err := validateMigrationIntegrity(ctx, transaction, vaultID, migrationID, report); err != nil {
		if errors.Is(err, ErrIntegrityMismatch) {
			return Report{}, commitVerificationError(
				ctx, transaction, migrationID, "manifest_sha256_mismatch", ErrIntegrityMismatch,
			)
		}
		if errors.Is(err, ErrVerificationFailed) {
			return report, commitVerificationError(
				ctx, transaction, migrationID, "count_or_size_mismatch", ErrVerificationFailed,
			)
		}
		return Report{}, err
	}
	if err := lockMigrationEntries(ctx, transaction, vaultID, migrationID); err != nil {
		return Report{}, err
	}

	candidates, err := loadResolutionCandidates(ctx, transaction, migrationID)
	if err != nil {
		return Report{}, err
	}
	existing, err := loadExistingResolutionEntries(ctx, transaction, vaultID)
	if err != nil {
		return Report{}, err
	}
	resolutions, err := resolveMigrationEntries(vaultID, candidates, existing)
	if err != nil {
		return Report{}, err
	}
	if err := persistMigrationResolutions(ctx, transaction, migrationID, resolutions); err != nil {
		return Report{}, err
	}

	now := time.Now().UTC()
	if err := insertResolvedEntries(ctx, transaction, vaultID, migrationID, now, resolutions); err != nil {
		return Report{}, err
	}
	if err := publishResolvedChanges(ctx, transaction, vaultID, migrationID, now, resolutions); err != nil {
		return Report{}, err
	}
	if err := completeMigration(ctx, transaction, vaultID, migrationID, now); err != nil {
		return Report{}, err
	}

	verifiedReport, err := loadReport(ctx, transaction, vaultID, migrationID)
	if err != nil {
		return Report{}, err
	}
	if err := transaction.Commit(); err != nil {
		return Report{}, fmt.Errorf("commit migration verification: %w", err)
	}
	return verifiedReport, nil
}

func lockAndLoadMigration(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
) (string, error) {
	var status string
	err := transaction.QueryRowContext(
		ctx,
		"SELECT status FROM vault_migrations WHERE id = $1 AND vault_id = $2 FOR UPDATE",
		migrationID,
		vaultID,
	).Scan(&status)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrMigrationNotFound
	}
	if err != nil {
		return "", fmt.Errorf("lock migration: %w", err)
	}
	return status, nil
}

func validateMigrationIntegrity(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
	report Report,
) error {
	if err := verifyStoredManifest(ctx, transaction, vaultID, migrationID); err != nil {
		return err
	}
	if report.ExpectedEntries != report.ImportedEntries ||
		report.ExpectedDeletedEntries != report.ImportedDeletedEntries ||
		report.ExpectedAssets != report.VerifiedAssets ||
		report.ExpectedBytes != report.VerifiedBytes {
		return ErrVerificationFailed
	}
	return nil
}

func commitStoredReport(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
) (Report, error) {
	report, err := loadReport(ctx, transaction, vaultID, migrationID)
	if err != nil {
		return Report{}, err
	}
	if err := transaction.Commit(); err != nil {
		return Report{}, fmt.Errorf("commit stored migration report: %w", err)
	}
	return report, nil
}
