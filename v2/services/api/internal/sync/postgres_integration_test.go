package sync

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"

	cloverydatabase "github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresConcurrentFirstWritesProduceOneConflict(t *testing.T) {
	databaseHandle := openSyncIntegrationDatabase(t)
	const accountID = "11111111-1111-4111-8111-111111111111"
	const vaultID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	if _, err := databaseHandle.Exec("INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
		t.Fatalf("seed sync account: %v", err)
	}
	if _, err := databaseHandle.Exec(
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')", vaultID, accountID,
	); err != nil {
		t.Fatalf("seed sync Vault: %v", err)
	}
	repository := NewPostgresRepository(databaseHandle)
	operations := []Operation{
		{OperationID: "22222222-2222-4222-8222-222222222222", EntryID: "44444444-4444-4444-8444-444444444444", Payload: json.RawMessage(`{"text":"first"}`)},
		{OperationID: "33333333-3333-4333-8333-333333333333", EntryID: "44444444-4444-4444-8444-444444444444", Payload: json.RawMessage(`{"text":"second"}`)},
	}
	start := make(chan struct{})
	decisions := make(chan Decision, len(operations))
	errorsChannel := make(chan error, len(operations))
	var waitGroup sync.WaitGroup
	for _, operation := range operations {
		waitGroup.Add(1)
		go func(operation Operation) {
			defer waitGroup.Done()
			<-start
			decision, err := repository.Apply(context.Background(), vaultID, operation, time.Now().UTC())
			decisions <- decision
			errorsChannel <- err
		}(operation)
	}
	close(start)
	waitGroup.Wait()
	close(decisions)
	close(errorsChannel)

	for err := range errorsChannel {
		if err != nil {
			t.Fatalf("concurrent Apply() error = %v", err)
		}
	}
	statuses := map[string]int{}
	for decision := range decisions {
		statuses[decision.Status]++
	}
	if statuses[StatusApplied] != 1 || statuses[StatusConflict] != 1 {
		t.Fatalf("concurrent statuses = %#v", statuses)
	}
}

func openSyncIntegrationDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for sync integration tests")
	}
	const schemaName = "clovery_sync_concurrency_test"
	admin, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open sync integration database: %v", err)
	}
	t.Cleanup(func() { _ = admin.Close() })
	_, _ = admin.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	if _, err := admin.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create sync integration schema: %v", err)
	}
	t.Cleanup(func() { _, _ = admin.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)) })

	schemaURL := syncIntegrationDatabaseURL(t, databaseURL, schemaName)
	if err := cloverydatabase.Apply(schemaURL, syncMigrationsPath(t), cloverydatabase.Up); err != nil {
		t.Fatalf("apply sync integration migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open migrated sync database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	return databaseHandle
}

func syncIntegrationDatabaseURL(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse sync integration database URL: %v", err)
	}
	query := parsed.Query()
	query.Set("search_path", schemaName)
	parsed.RawQuery = query.Encode()
	return parsed.String()
}

func syncMigrationsPath(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve sync integration test path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
