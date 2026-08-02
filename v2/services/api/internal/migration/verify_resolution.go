package migration

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"
)

func loadResolutionCandidates(
	ctx context.Context,
	transaction *sql.Tx,
	migrationID string,
) ([]ResolutionCandidate, error) {
	rows, err := transaction.QueryContext(
		ctx,
		`SELECT source_entry_id, entry_id, payload, sha256, dedup_sha256, deleted_at
		 FROM migration_entries WHERE migration_id = $1 ORDER BY source_entry_id, entry_id`,
		migrationID,
	)
	if err != nil {
		return nil, fmt.Errorf("load migration resolution candidates: %w", err)
	}
	defer rows.Close()

	var candidates []ResolutionCandidate
	for rows.Next() {
		var sourceEntryID, entryID, storedSHA256 string
		var payload []byte
		var storedDedupSHA256 sql.NullString
		var deletedAt *time.Time
		if err := rows.Scan(
			&sourceEntryID, &entryID, &payload, &storedSHA256, &storedDedupSHA256, &deletedAt,
		); err != nil {
			return nil, fmt.Errorf("scan migration resolution candidate: %w", err)
		}
		candidate, err := newResolutionCandidate(sourceEntryID, entryID, payload, deletedAt)
		if err != nil {
			return nil, err
		}
		if candidate.ContentSHA256 != storedSHA256 ||
			(storedDedupSHA256.Valid && candidate.DedupSHA256 != storedDedupSHA256.String) {
			return nil, ErrIntegrityMismatch
		}
		if deletedAt != nil {
			candidate.DedupPayload = nil
			candidate.DedupSHA256 = ""
		}
		candidates = append(candidates, candidate)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate migration resolution candidates: %w", err)
	}
	return candidates, nil
}

func loadExistingResolutionEntries(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
) ([]ExistingEntry, error) {
	rows, err := transaction.QueryContext(
		ctx,
		`SELECT id, payload, content_sha256, dedup_sha256, deleted_at, updated_at
		 FROM journal_entries WHERE vault_id = $1 ORDER BY updated_at, id FOR UPDATE`,
		vaultID,
	)
	if err != nil {
		return nil, fmt.Errorf("load existing migration entries: %w", err)
	}
	defer rows.Close()

	var entries []ExistingEntry
	for rows.Next() {
		var entryID string
		var payload []byte
		var storedContentSHA256, storedDedupSHA256 sql.NullString
		var deletedAt *time.Time
		var updatedAt time.Time
		if err := rows.Scan(
			&entryID, &payload, &storedContentSHA256, &storedDedupSHA256, &deletedAt, &updatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan existing migration entry: %w", err)
		}
		entry, err := newExistingEntry(entryID, payload, deletedAt, updatedAt)
		if err != nil {
			return nil, err
		}
		if storedContentSHA256.Valid && storedContentSHA256.String != entry.ContentSHA256 {
			return nil, ErrIntegrityMismatch
		}
		if deletedAt != nil {
			entry.DedupPayload = nil
			entry.DedupSHA256 = ""
		} else if storedDedupSHA256.Valid && storedDedupSHA256.String != entry.DedupSHA256 {
			return nil, ErrIntegrityMismatch
		}
		entries = append(entries, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate existing migration entries: %w", err)
	}

	for _, entry := range entries {
		var dedupSHA256 any
		if entry.DeletedAt == nil {
			dedupSHA256 = entry.DedupSHA256
		}
		if _, err := transaction.ExecContext(
			ctx,
			`UPDATE journal_entries SET content_sha256 = $3, dedup_sha256 = $4
			 WHERE id = $1 AND vault_id = $2
			   AND (content_sha256 IS NULL OR dedup_sha256 IS NULL)`,
			entry.EntryID, vaultID, entry.ContentSHA256, dedupSHA256,
		); err != nil {
			return nil, fmt.Errorf("backfill migration entry hashes: %w", err)
		}
	}
	return entries, nil
}

func resolveMigrationEntries(
	vaultID string,
	candidates []ResolutionCandidate,
	existing []ExistingEntry,
) ([]EntryResolution, error) {
	return resolveEntries(vaultID, candidates, existing)
}

func persistMigrationResolutions(
	ctx context.Context,
	transaction *sql.Tx,
	migrationID string,
	resolutions []EntryResolution,
) error {
	for _, resolution := range resolutions {
		var dedupSHA256 any
		if resolution.Candidate.DeletedAt == nil {
			dedupSHA256 = resolution.Candidate.DedupSHA256
		}
		result, err := transaction.ExecContext(
			ctx,
			`UPDATE migration_entries
			 SET resolved_entry_id = $3, resolution = $4, dedup_sha256 = $5
			 WHERE migration_id = $1 AND source_entry_id = $2 AND resolution = 'pending'`,
			migrationID, resolution.Candidate.SourceEntryID, resolution.ResolvedEntryID,
			resolution.Resolution, dedupSHA256,
		)
		if err != nil {
			return fmt.Errorf("persist migration resolution: %w", err)
		}
		rowsAffected, err := result.RowsAffected()
		if err != nil || rowsAffected != 1 {
			return ErrResolutionRace
		}
	}
	return nil
}

func insertResolvedEntries(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
	now time.Time,
	resolutions []EntryResolution,
) error {
	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO journal_entries (
		 id, vault_id, revision, payload, deleted_at, updated_at,
		 imported_by_migration_id, content_sha256, dedup_sha256
		 ) SELECT resolved_entry_id, $2, 1, payload, deleted_at, $3,
		 $1, sha256, dedup_sha256
		 FROM migration_entries
		 WHERE migration_id = $1 AND resolution IN ('insert', 'id_conflict_copy')`,
		migrationID, vaultID, now,
	)
	if err != nil {
		return fmt.Errorf("insert resolved migration entries: %w: %w", ErrResolutionRace, err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("count resolved migration entries: %w", err)
	}
	wantRows := int64(0)
	for _, resolution := range resolutions {
		if resolution.Resolution == resolutionInsert || resolution.Resolution == resolutionIDConflictCopy {
			wantRows++
		}
	}
	if rowsAffected != wantRows {
		return ErrResolutionRace
	}
	return nil
}

func publishResolvedChanges(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
	now time.Time,
	resolutions []EntryResolution,
) error {
	result, err := transaction.ExecContext(
		ctx,
		`INSERT INTO sync_changes (
		 vault_id, entity_type, entity_id, revision, operation_id, payload, deleted, changed_at
		 ) SELECT $2, 'journal_entry', resolved_entry_id, 1, operation_id,
		 CASE WHEN deleted_at IS NULL THEN payload ELSE '{}'::jsonb END,
		 deleted_at IS NOT NULL, $3
		 FROM migration_entries
		 WHERE migration_id = $1 AND resolution IN ('insert', 'id_conflict_copy')`,
		migrationID, vaultID, now,
	)
	if err != nil {
		return fmt.Errorf("publish resolved migration entries: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("count resolved migration changes: %w", err)
	}
	wantRows := int64(0)
	for _, resolution := range resolutions {
		if resolution.Resolution == resolutionInsert || resolution.Resolution == resolutionIDConflictCopy {
			wantRows++
		}
	}
	if rowsAffected != wantRows {
		return ErrResolutionRace
	}
	return nil
}

func completeMigration(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
	now time.Time,
) error {
	result, err := transaction.ExecContext(
		ctx,
		`UPDATE vault_migrations
		 SET status = 'verified', verified_at = $2, last_errors = '[]'::jsonb
		 WHERE id = $1 AND status = 'uploading'`,
		migrationID, now,
	)
	if err != nil {
		return fmt.Errorf("complete migration verification: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil || rowsAffected != 1 {
		return ErrResolutionRace
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload, created_at)
		 SELECT $1, owner_account_id, 'vault_migration_verified',
		 jsonb_build_object('migration_id', $2::uuid), $3
		 FROM vaults WHERE id = $4`,
		uuid.NewString(), migrationID, now, vaultID,
	); err != nil {
		return fmt.Errorf("audit verified migration: %w", err)
	}
	return nil
}
