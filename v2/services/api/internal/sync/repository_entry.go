package sync

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

func loadCurrentEntry(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	entryID string,
) (*Entry, error) {
	var entry Entry
	err := transaction.QueryRowContext(
		ctx,
		`SELECT id, revision, payload, deleted_at FROM journal_entries
		 WHERE id = $1 AND vault_id = $2 FOR UPDATE`,
		entryID,
		vaultID,
	).Scan(&entry.ID, &entry.Revision, &entry.Payload, &entry.DeletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("load journal entry for sync: %w", err)
	}
	return &entry, nil
}

func persistAppliedOperation(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	operation Operation,
	decision *Decision,
	now time.Time,
) error {
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO journal_entries (id, vault_id, revision, payload, deleted_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 ON CONFLICT (id, vault_id) DO UPDATE SET
		 revision = EXCLUDED.revision, payload = EXCLUDED.payload,
		 deleted_at = EXCLUDED.deleted_at, updated_at = EXCLUDED.updated_at`,
		decision.Entry.ID,
		vaultID,
		decision.Entry.Revision,
		decision.Entry.Payload,
		decision.Entry.DeletedAt,
		now,
	); err != nil {
		return fmt.Errorf("persist journal entry: %w", err)
	}
	changePayload := decision.Entry.Payload
	if operation.Deleted {
		changePayload = json.RawMessage(`{}`)
	}
	if err := transaction.QueryRowContext(
		ctx,
		`INSERT INTO sync_changes (
		 vault_id, entity_type, entity_id, revision, operation_id, payload, deleted, changed_at
		 ) VALUES ($1, 'journal_entry', $2, $3, $4, $5, $6, $7) RETURNING cursor`,
		vaultID,
		operation.EntryID,
		decision.Entry.Revision,
		operation.OperationID,
		changePayload,
		operation.Deleted,
		now,
	).Scan(&decision.Cursor); err != nil {
		return fmt.Errorf("append sync change: %w", err)
	}
	return nil
}

func persistConflict(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	operation Operation,
	decision Decision,
	now time.Time,
) error {
	clientPayload := json.RawMessage(`{}`)
	if !operation.Deleted {
		var err error
		clientPayload, err = canonicalJSON(operation.Payload)
		if err != nil {
			return err
		}
	}
	serverPayload, err := json.Marshal(decision.ServerSnapshot)
	if err != nil {
		return fmt.Errorf("encode conflict server snapshot: %w", err)
	}
	if decision.ServerSnapshot == nil {
		serverPayload = []byte(`{}`)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO journal_conflicts (
		 id, vault_id, entry_id, operation_id, base_revision,
		 client_payload, server_payload, created_at
		 ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		uuid.NewString(),
		vaultID,
		operation.EntryID,
		operation.OperationID,
		operation.BaseRevision,
		clientPayload,
		serverPayload,
		now,
	); err != nil {
		return fmt.Errorf("persist journal conflict: %w", err)
	}
	return nil
}
