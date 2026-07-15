package database

import (
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestMigrationsSupportRepeatableDeploymentAndRollback(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for migration integration tests")
	}

	const schemaName = "clovery_w0_migration_test"
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open migration test database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })

	if _, err := adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)); err != nil {
		t.Fatalf("reset migration test schema: %v", err)
	}
	if _, err := adminDatabase.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create migration test schema: %v", err)
	}
	t.Cleanup(func() {
		_, _ = adminDatabase.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	})

	schemaDatabaseURL := withSearchPath(t, databaseURL, schemaName)
	migrationsPath := migrationDirectory(t)

	if err := Apply(schemaDatabaseURL, migrationsPath, Up); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	if _, err := adminDatabase.Exec(
		fmt.Sprintf("INSERT INTO %s.clovery_system_metadata (key, value) VALUES ('probe', '{\"status\":\"ok\"}')", schemaName),
	); err != nil {
		t.Fatalf("insert migration probe: %v", err)
	}

	if err := Apply(schemaDatabaseURL, migrationsPath, Up); err != nil {
		t.Fatalf("repeat migrations: %v", err)
	}
	var rowCount int
	if err := adminDatabase.QueryRow(
		fmt.Sprintf("SELECT COUNT(*) FROM %s.clovery_system_metadata", schemaName),
	).Scan(&rowCount); err != nil {
		t.Fatalf("count preserved rows: %v", err)
	}
	if rowCount != 1 {
		t.Fatalf("row count after repeated migration = %d", rowCount)
	}

	if err := Apply(schemaDatabaseURL, migrationsPath, Down); err != nil {
		t.Fatalf("roll back latest migration: %v", err)
	}
	if err := adminDatabase.QueryRow(
		fmt.Sprintf("SELECT COUNT(*) FROM %s.clovery_system_metadata", schemaName),
	).Scan(&rowCount); err != nil {
		t.Fatalf("count rows after one-step rollback: %v", err)
	}
	if rowCount != 1 {
		t.Fatalf("row count after one-step rollback = %d", rowCount)
	}
	if err := Apply(schemaDatabaseURL, migrationsPath, Up); err != nil {
		t.Fatalf("reapply migrations: %v", err)
	}

	var tableName *string
	if err := adminDatabase.QueryRow(
		"SELECT to_regclass($1)",
		schemaName+".clovery_system_metadata",
	).Scan(&tableName); err != nil {
		t.Fatalf("verify migrated table: %v", err)
	}
	if tableName == nil {
		t.Fatal("migrated table does not exist after reapply")
	}
}

func withSearchPath(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsedURL, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse migration database URL: %v", err)
	}
	query := parsedURL.Query()
	query.Set("search_path", schemaName)
	parsedURL.RawQuery = query.Encode()
	return parsedURL.String()
}

func migrationDirectory(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve migration test file path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
