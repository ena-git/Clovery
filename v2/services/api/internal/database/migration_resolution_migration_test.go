package database

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestMigrationResolutionMigrationDefinesDeterministicMetadata(t *testing.T) {
	migrations := migrationDirectory(t)
	up := readMigration(t, filepath.Join(migrations, "000017_migration_resolution.up.sql"))
	down := readMigration(t, filepath.Join(migrations, "000017_migration_resolution.down.sql"))

	for _, fragment := range []string{
		"ADD COLUMN resolved_entry_id UUID",
		"ADD COLUMN resolution TEXT NOT NULL DEFAULT 'pending'",
		"migration_entries_resolution_check",
		"ADD COLUMN dedup_sha256 TEXT",
		"ADD COLUMN content_sha256 TEXT",
		"journal_entries_vault_dedup_sha_idx",
	} {
		if !strings.Contains(up, fragment) {
			t.Fatalf("up migration is missing %q", fragment)
		}
	}

	for _, fragment := range []string{
		"DROP INDEX journal_entries_vault_dedup_sha_idx",
		"DROP COLUMN content_sha256",
		"DROP COLUMN dedup_sha256",
		"DROP COLUMN resolution",
		"DROP COLUMN resolved_entry_id",
	} {
		if !strings.Contains(down, fragment) {
			t.Fatalf("down migration is missing %q", fragment)
		}
	}
}
