package bootstrapjob

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	cloverydatabase "github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestBootstrapJobTransitionsRemainResumable(t *testing.T) {
	databaseHandle, service := openBootstrapJobDatabase(t)
	accountID, vaultID := seedBootstrapAccount(t, databaseHandle, "10000000-0000-4000-8000-000000000001", "10000000-0000-4000-8000-000000000002")

	job, err := service.Resume(context.Background(), accountID, vaultID, SourceNewInstall)
	if err != nil {
		t.Fatalf("Resume() create error = %v", err)
	}
	if job.Status != StatusPending || job.MigrationState != StageComplete || job.SourceKind != SourceNewInstall {
		t.Fatalf("created job = %#v", job)
	}

	if err := service.MarkEntitlement(context.Background(), accountID, StagePending, nil); err != nil {
		t.Fatalf("MarkEntitlement(pending) error = %v", err)
	}
	job = getBootstrapJob(t, service, accountID)
	if job.Status != StatusRunning {
		t.Fatalf("pending progress status = %q, want running", job.Status)
	}

	if err := service.MarkEntitlement(context.Background(), accountID, StageComplete, nil); err != nil {
		t.Fatalf("MarkEntitlement(complete) error = %v", err)
	}
	if err := service.MarkVault(context.Background(), accountID, StageComplete, nil); err != nil {
		t.Fatalf("MarkVault(complete) error = %v", err)
	}
	job = getBootstrapJob(t, service, accountID)
	if job.Status != StatusComplete || job.IdentityState != StageComplete || job.MigrationState != StageComplete ||
		job.EntitlementState != StageComplete || job.VaultState != StageComplete {
		t.Fatalf("completed job = %#v", job)
	}

	if err := service.MarkVault(context.Background(), accountID, StagePending, nil); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("complete -> pending error = %v, want ErrInvalidTransition", err)
	}
	if after := getBootstrapJob(t, service, accountID); after.Status != StatusComplete || after.VaultState != StageComplete {
		t.Fatalf("invalid transition changed job = %#v", after)
	}
}

func TestBootstrapJobAttentionResumePreservesProgressAndMigration(t *testing.T) {
	databaseHandle, service := openBootstrapJobDatabase(t)
	accountID, vaultID := seedBootstrapAccount(t, databaseHandle, "20000000-0000-4000-8000-000000000001", "20000000-0000-4000-8000-000000000002")
	migrationID := "20000000-0000-4000-8000-000000000003"
	seedBootstrapMigration(t, databaseHandle, migrationID, vaultID)
	if _, err := service.Resume(context.Background(), accountID, vaultID, SourceLegacyLocal); err != nil {
		t.Fatalf("Resume() create error = %v", err)
	}
	errorCode := "migration_upload_failed"
	if err := service.MarkMigration(context.Background(), accountID, migrationID, StageNeedsAttention, &errorCode); err != nil {
		t.Fatalf("MarkMigration(needs_attention) error = %v", err)
	}
	job := getBootstrapJob(t, service, accountID)
	if job.Status != StatusNeedsAttention || job.LastErrorCode == nil || *job.LastErrorCode != errorCode {
		t.Fatalf("attention job = %#v", job)
	}

	resumed, err := service.Resume(context.Background(), accountID, vaultID, SourceNewInstall)
	if err != nil {
		t.Fatalf("Resume() retry error = %v", err)
	}
	if resumed.Status != StatusRunning || resumed.RetryCount != 1 || resumed.LastErrorCode != nil ||
		resumed.MigrationID == nil || *resumed.MigrationID != migrationID ||
		resumed.MigrationState != StageNeedsAttention || resumed.IdentityState != StageComplete ||
		resumed.SourceKind != SourceLegacyLocal {
		t.Fatalf("resumed job = %#v", resumed)
	}

	if err := service.MarkMigration(context.Background(), accountID, migrationID, StageComplete, nil); err != nil {
		t.Fatalf("MarkMigration(complete) error = %v", err)
	}
	job = getBootstrapJob(t, service, accountID)
	if job.Status != StatusRunning || job.MigrationState != StageComplete || job.RetryCount != 1 {
		t.Fatalf("recovered migration job = %#v", job)
	}
}

func TestBootstrapJobRejectsCrossAccountAccessAndInvalidErrors(t *testing.T) {
	databaseHandle, service := openBootstrapJobDatabase(t)
	accountA, vaultA := seedBootstrapAccount(t, databaseHandle, "30000000-0000-4000-8000-000000000001", "30000000-0000-4000-8000-000000000002")
	accountB, vaultB := seedBootstrapAccount(t, databaseHandle, "30000000-0000-4000-8000-000000000003", "30000000-0000-4000-8000-000000000004")
	if _, err := service.Resume(context.Background(), accountA, vaultA, SourceNewInstall); err != nil {
		t.Fatalf("Resume(account A) error = %v", err)
	}
	if _, err := service.Get(context.Background(), accountB); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Get(account B) error = %v, want ErrNotFound", err)
	}
	if err := service.MarkVault(context.Background(), accountB, StageComplete, nil); !errors.Is(err, ErrNotFound) {
		t.Fatalf("MarkVault(account B) error = %v, want ErrNotFound", err)
	}
	if _, err := service.Resume(context.Background(), accountA, vaultA, SourceLegacyCloudKit); err != nil {
		t.Fatalf("Resume(existing with conflicting source) error = %v", err)
	}
	job := getBootstrapJob(t, service, accountA)
	if job.VaultID != vaultA || job.SourceKind != SourceNewInstall {
		t.Fatalf("existing job was reclassified = %#v", job)
	}
	if _, err := service.Resume(context.Background(), accountA, vaultB, SourceNewInstall); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Resume(existing with foreign vault) error = %v, want ErrNotFound", err)
	}

	invalidCode := "Migration Failed"
	if err := service.MarkVault(context.Background(), accountA, StageNeedsAttention, &invalidCode); !errors.Is(err, ErrInvalidErrorCode) {
		t.Fatalf("MarkVault(invalid code) error = %v, want ErrInvalidErrorCode", err)
	}
	if after := getBootstrapJob(t, service, accountA); after.Status != StatusPending || after.LastErrorCode != nil {
		t.Fatalf("invalid code changed job = %#v", after)
	}

	if _, err := service.Resume(context.Background(), accountB, vaultA, SourceNewInstall); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Resume(cross-account vault) error = %v, want ErrNotFound", err)
	}
}

func TestBootstrapJobConcurrentResumeCreatesOneStoredJob(t *testing.T) {
	databaseHandle, service := openBootstrapJobDatabase(t)
	accountID, vaultID := seedBootstrapAccount(t, databaseHandle, "40000000-0000-4000-8000-000000000001", "40000000-0000-4000-8000-000000000002")
	start := make(chan struct{})
	type resumeOutcome struct {
		job Job
		err error
	}
	outcomes := make(chan resumeOutcome, 2)
	var waitGroup sync.WaitGroup
	for _, source := range []SourceKind{SourceLegacyLocal, SourceLegacyCloudKit} {
		waitGroup.Add(1)
		go func(source SourceKind) {
			defer waitGroup.Done()
			<-start
			job, err := service.Resume(context.Background(), accountID, vaultID, source)
			outcomes <- resumeOutcome{job: job, err: err}
		}(source)
	}
	close(start)
	waitGroup.Wait()
	close(outcomes)
	var storedSource SourceKind
	for outcome := range outcomes {
		if outcome.err != nil {
			t.Errorf("concurrent Resume() error = %v", outcome.err)
		}
		if storedSource == "" {
			storedSource = outcome.job.SourceKind
		} else if outcome.job.SourceKind != storedSource {
			t.Errorf("concurrent Resume() returned sources %q and %q", storedSource, outcome.job.SourceKind)
		}
	}
	var count int
	if err := databaseHandle.QueryRow("SELECT COUNT(*) FROM account_bootstrap_jobs WHERE account_id = $1", accountID).Scan(&count); err != nil {
		t.Fatalf("count bootstrap jobs: %v", err)
	}
	if count != 1 {
		t.Fatalf("bootstrap job count = %d, want 1", count)
	}
	if stored := getBootstrapJob(t, service, accountID); stored.SourceKind != storedSource {
		t.Fatalf("stored source = %q, returned source = %q", stored.SourceKind, storedSource)
	}
}

func getBootstrapJob(t *testing.T, service *Service, accountID string) Job {
	t.Helper()
	job, err := service.Get(context.Background(), accountID)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	return job
}

var bootstrapJobSchemaSequence atomic.Uint64

func openBootstrapJobDatabase(t *testing.T) (*sql.DB, *Service) {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is required for bootstrap job PostgreSQL tests")
	}
	schemaName := fmt.Sprintf("clovery_w7_bootstrap_%d_%d", os.Getpid(), bootstrapJobSchemaSequence.Add(1))
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open bootstrap admin database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	if _, err := adminDatabase.Exec("CREATE SCHEMA " + schemaName); err != nil {
		t.Fatalf("create bootstrap schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec("DROP SCHEMA IF EXISTS " + schemaName + " CASCADE") })

	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse bootstrap database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve bootstrap test path")
	}
	migrationsPath := filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
	if err := cloverydatabase.Apply(parsedURL.String(), migrationsPath, cloverydatabase.Up); err != nil {
		t.Fatalf("apply bootstrap migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", parsedURL.String())
	if err != nil {
		t.Fatalf("open bootstrap database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	service, err := NewService(NewPostgresRepository(databaseHandle))
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}
	return databaseHandle, service
}

func seedBootstrapAccount(t *testing.T, databaseHandle *sql.DB, accountID string, vaultID string) (string, string) {
	t.Helper()
	if _, err := databaseHandle.Exec("INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
		t.Fatalf("seed bootstrap account: %v", err)
	}
	if _, err := databaseHandle.Exec("INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')", vaultID, accountID); err != nil {
		t.Fatalf("seed bootstrap vault: %v", err)
	}
	return accountID, vaultID
}

func seedBootstrapMigration(t *testing.T, databaseHandle *sql.DB, migrationID string, vaultID string) {
	t.Helper()
	if _, err := databaseHandle.Exec(`
		INSERT INTO vault_migrations (
			id, vault_id, format_version, source,
			expected_entry_count, expected_deleted_count, expected_asset_count, expected_total_bytes,
			manifest_sha256, manifest, manifest_bytes, status, created_at
		) VALUES ($1, $2, 1, 'v1_bundle', 0, 0, 0, 0, $3, '{}'::jsonb, $4, 'uploading', $5)
	`, migrationID, vaultID, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", []byte("{}"), time.Now().UTC()); err != nil {
		t.Fatalf("seed bootstrap migration: %v", err)
	}
}
