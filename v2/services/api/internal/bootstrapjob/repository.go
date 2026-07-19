package bootstrapjob

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgconn"
)

type PostgresRepository struct {
	database *sql.DB
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{database: database}
}

func (repository *PostgresRepository) GetByAccountID(ctx context.Context, accountID string) (Job, error) {
	job, err := scanJob(repository.database.QueryRowContext(ctx, selectJobSQL, accountID))
	if errors.Is(err, sql.ErrNoRows) {
		return Job{}, ErrNotFound
	}
	if err != nil {
		return Job{}, fmt.Errorf("get bootstrap job: %w", err)
	}
	return job, nil
}

func (repository *PostgresRepository) ResumeByAccountID(
	ctx context.Context,
	accountID string,
	vaultID string,
	source SourceKind,
) (Job, error) {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return Job{}, fmt.Errorf("begin bootstrap resume: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	var accountExists bool
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT EXISTS (SELECT 1 FROM clovery_accounts WHERE id = $1 FOR UPDATE)",
		accountID,
	).Scan(&accountExists); err != nil {
		return Job{}, fmt.Errorf("lock bootstrap account: %w", err)
	}
	if !accountExists {
		return Job{}, ErrNotFound
	}

	job, err := scanJob(transaction.QueryRowContext(ctx, selectJobForUpdateSQL, accountID))
	switch {
	case err == nil:
		if job.VaultID != vaultID {
			return Job{}, ErrNotFound
		}
		resumed := resumeExisting(job)
		if resumed.RetryCount != job.RetryCount {
			if _, err := transaction.ExecContext(
				ctx,
				`UPDATE account_bootstrap_jobs
				 SET status = $2, last_error_code = NULL, retry_count = $3, updated_at = NOW()
				 WHERE account_id = $1`,
				accountID,
				resumed.Status,
				resumed.RetryCount,
			); err != nil {
				return Job{}, fmt.Errorf("resume bootstrap job: %w", err)
			}
			job, err = scanJob(transaction.QueryRowContext(ctx, selectJobSQL, accountID))
			if err != nil {
				return Job{}, fmt.Errorf("reload resumed bootstrap job: %w", err)
			}
		}
		if err := transaction.Commit(); err != nil {
			return Job{}, fmt.Errorf("commit bootstrap resume: %w", err)
		}
		return job, nil
	case !errors.Is(err, sql.ErrNoRows):
		return Job{}, fmt.Errorf("lock bootstrap job: %w", err)
	}

	var ownsVault bool
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT EXISTS (SELECT 1 FROM vaults WHERE id = $1 AND owner_account_id = $2)",
		vaultID,
		accountID,
	).Scan(&ownsVault); err != nil {
		return Job{}, fmt.Errorf("verify bootstrap vault ownership: %w", err)
	}
	if !ownsVault {
		return Job{}, ErrNotFound
	}
	created := newJob(accountID, vaultID, source)
	job, err = scanJob(transaction.QueryRowContext(
		ctx,
		`INSERT INTO account_bootstrap_jobs (
			account_id, vault_id, source_kind, identity_state, migration_state,
			entitlement_state, vault_state, status
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING account_id, vault_id, source_kind, migration_id, identity_state,
			migration_state, entitlement_state, vault_state, status, last_error_code,
			retry_count, updated_at`,
		created.AccountID,
		created.VaultID,
		created.SourceKind,
		created.IdentityState,
		created.MigrationState,
		created.EntitlementState,
		created.VaultState,
		created.Status,
	))
	if err != nil {
		if isBootstrapConflict(err) {
			return Job{}, ErrConflict
		}
		return Job{}, fmt.Errorf("create bootstrap job: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return Job{}, fmt.Errorf("commit bootstrap creation: %w", err)
	}
	return job, nil
}

func (repository *PostgresRepository) MarkMigrationByAccountID(
	ctx context.Context,
	accountID string,
	migrationID string,
	state StageState,
	errorCode *string,
) error {
	return repository.updateByAccountID(ctx, accountID, func(job *Job) error {
		return markMigration(job, migrationID, state, errorCode)
	})
}

func (repository *PostgresRepository) MarkEntitlementByAccountID(
	ctx context.Context,
	accountID string,
	state StageState,
	errorCode *string,
) error {
	return repository.updateByAccountID(ctx, accountID, func(job *Job) error {
		return markStage(job, &job.EntitlementState, state, errorCode)
	})
}

func (repository *PostgresRepository) MarkVaultByAccountID(
	ctx context.Context,
	accountID string,
	state StageState,
	errorCode *string,
) error {
	return repository.updateByAccountID(ctx, accountID, func(job *Job) error {
		return markStage(job, &job.VaultState, state, errorCode)
	})
}

func (repository *PostgresRepository) updateByAccountID(
	ctx context.Context,
	accountID string,
	update func(*Job) error,
) error {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin bootstrap update: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()
	job, err := scanJob(transaction.QueryRowContext(ctx, selectJobForUpdateSQL, accountID))
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("lock bootstrap job: %w", err)
	}
	if err := update(&job); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(
		ctx,
		`UPDATE account_bootstrap_jobs SET
			migration_id = $2, identity_state = $3, migration_state = $4,
			entitlement_state = $5, vault_state = $6, status = $7,
			last_error_code = $8, retry_count = $9, updated_at = NOW()
		 WHERE account_id = $1`,
		accountID,
		job.MigrationID,
		job.IdentityState,
		job.MigrationState,
		job.EntitlementState,
		job.VaultState,
		job.Status,
		job.LastErrorCode,
		job.RetryCount,
	); err != nil {
		if isBootstrapConflict(err) {
			return ErrConflict
		}
		return fmt.Errorf("update bootstrap job: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit bootstrap update: %w", err)
	}
	return nil
}

const selectJobSQL = `SELECT account_id, vault_id, source_kind, migration_id, identity_state,
	migration_state, entitlement_state, vault_state, status, last_error_code,
	retry_count, updated_at
	FROM account_bootstrap_jobs WHERE account_id = $1`

const selectJobForUpdateSQL = selectJobSQL + " FOR UPDATE"

type rowScanner interface {
	Scan(destinations ...any) error
}

func scanJob(row rowScanner) (Job, error) {
	var job Job
	err := row.Scan(
		&job.AccountID,
		&job.VaultID,
		&job.SourceKind,
		&job.MigrationID,
		&job.IdentityState,
		&job.MigrationState,
		&job.EntitlementState,
		&job.VaultState,
		&job.Status,
		&job.LastErrorCode,
		&job.RetryCount,
		&job.UpdatedAt,
	)
	return job, err
}

func isBootstrapConflict(err error) bool {
	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) {
		return false
	}
	return postgresError.Code == "23503" || postgresError.Code == "23505" || postgresError.Code == "23514"
}
