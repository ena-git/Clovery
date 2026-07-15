package sync

import (
	"context"
	"database/sql"
	"encoding/json"
	"testing"
	"time"
)

func TestPostgresPaginationConflictAndTombstoneAcceptance(t *testing.T) {
	databaseHandle := openSyncIntegrationDatabase(t)
	const (
		accountA = "11111111-1111-4111-8111-111111111111"
		accountB = "22222222-2222-4222-8222-222222222222"
		vaultA   = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
		vaultB   = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
		entryA   = "aaaaaaaa-1111-4111-8111-111111111111"
		entryB   = "aaaaaaaa-2222-4222-8222-222222222222"
		entryC   = "bbbbbbbb-1111-4111-8111-111111111111"
	)
	seedSyncIdentity(t, databaseHandle, accountA, vaultA)
	seedSyncIdentity(t, databaseHandle, accountB, vaultB)
	repository := NewPostgresRepository(databaseHandle)
	startedAt := time.Date(2026, time.July, 15, 8, 0, 0, 0, time.UTC)

	createA := applySyncOperation(t, repository, vaultA, Operation{
		OperationID: "10000000-0000-4000-8000-000000000001", EntryID: entryA,
		Payload: json.RawMessage(`{"text":"device a"}`),
	}, startedAt)
	applySyncOperation(t, repository, vaultB, Operation{
		OperationID: "20000000-0000-4000-8000-000000000001", EntryID: entryC,
		Payload: json.RawMessage(`{"text":"other vault"}`),
	}, startedAt.Add(time.Second))
	applySyncOperation(t, repository, vaultA, Operation{
		OperationID: "10000000-0000-4000-8000-000000000002", EntryID: entryB,
		Payload: json.RawMessage(`{"text":"second page"}`),
	}, startedAt.Add(2*time.Second))
	editA := applySyncOperation(t, repository, vaultA, Operation{
		OperationID: "10000000-0000-4000-8000-000000000003", EntryID: entryA,
		BaseRevision: createA.Entry.Revision, Payload: json.RawMessage(`{"text":"device a edited"}`),
	}, startedAt.Add(3*time.Second))
	stale := applySyncOperation(t, repository, vaultA, Operation{
		OperationID: "10000000-0000-4000-8000-000000000004", EntryID: entryA,
		BaseRevision: createA.Entry.Revision, Payload: json.RawMessage(`{"text":"device b stale"}`),
	}, startedAt.Add(4*time.Second))
	if stale.Status != StatusConflict || stale.ServerSnapshot == nil ||
		stale.ServerSnapshot.Revision != editA.Entry.Revision {
		t.Fatalf("stale edit decision = %#v", stale)
	}

	deletion := applySyncOperation(t, repository, vaultA, Operation{
		OperationID: "10000000-0000-4000-8000-000000000005", EntryID: entryA,
		BaseRevision: editA.Entry.Revision, Payload: json.RawMessage(`{}`), Deleted: true,
	}, startedAt.Add(5*time.Second))
	resurrection := applySyncOperation(t, repository, vaultA, Operation{
		OperationID: "10000000-0000-4000-8000-000000000006", EntryID: entryA,
		BaseRevision: deletion.Entry.Revision, Payload: json.RawMessage(`{"text":"must stay deleted"}`),
	}, startedAt.Add(6*time.Second))
	if resurrection.Status != StatusConflict || resurrection.ServerSnapshot == nil ||
		resurrection.ServerSnapshot.DeletedAt == nil || resurrection.Entry != nil {
		t.Fatalf("resurrection decision = %#v", resurrection)
	}

	firstChanges, err := repository.ListChanges(context.Background(), vaultA, 0, 3)
	if err != nil {
		t.Fatalf("list first sync page: %v", err)
	}
	firstPage := BuildPullPage(firstChanges, 2, 0)
	secondChanges, err := repository.ListChanges(context.Background(), vaultA, firstPage.NextCursor, 3)
	if err != nil {
		t.Fatalf("list second sync page: %v", err)
	}
	secondPage := BuildPullPage(secondChanges, 2, firstPage.NextCursor)
	if !firstPage.HasMore || secondPage.HasMore || len(firstPage.Changes) != 2 ||
		len(secondPage.Changes) != 2 || firstPage.NextCursor >= secondPage.NextCursor {
		t.Fatalf("sync pages first=%#v second=%#v", firstPage, secondPage)
	}
	operationIDs := []string{
		firstPage.Changes[0].OperationID,
		firstPage.Changes[1].OperationID,
		secondPage.Changes[0].OperationID,
		secondPage.Changes[1].OperationID,
	}
	expectedOperationIDs := []string{
		"10000000-0000-4000-8000-000000000001",
		"10000000-0000-4000-8000-000000000002",
		"10000000-0000-4000-8000-000000000003",
		"10000000-0000-4000-8000-000000000005",
	}
	for index := range expectedOperationIDs {
		if operationIDs[index] != expectedOperationIDs[index] {
			t.Fatalf("operation IDs = %#v", operationIDs)
		}
	}
	if !secondPage.Changes[1].Deleted || string(secondPage.Changes[1].Payload) != `{}` {
		t.Fatalf("deletion change = %#v", secondPage.Changes[1])
	}

	otherVaultChanges, err := repository.ListChanges(context.Background(), vaultB, 0, 10)
	if err != nil {
		t.Fatalf("list other Vault changes: %v", err)
	}
	if len(otherVaultChanges) != 1 || otherVaultChanges[0].EntityID != entryC {
		t.Fatalf("other Vault changes = %#v", otherVaultChanges)
	}

	var revision int64
	var deletedAt *time.Time
	if err := databaseHandle.QueryRow(
		"SELECT revision, deleted_at FROM journal_entries WHERE id = $1 AND vault_id = $2",
		entryA,
		vaultA,
	).Scan(&revision, &deletedAt); err != nil {
		t.Fatalf("load deleted journal entry: %v", err)
	}
	if revision != deletion.Entry.Revision || deletedAt == nil {
		t.Fatalf("deleted journal entry revision=%d deleted_at=%v", revision, deletedAt)
	}

	var conflictCount int
	if err := databaseHandle.QueryRow(
		"SELECT count(*) FROM journal_conflicts WHERE vault_id = $1 AND entry_id = $2",
		vaultA,
		entryA,
	).Scan(&conflictCount); err != nil {
		t.Fatalf("count journal conflicts: %v", err)
	}
	if conflictCount != 2 {
		t.Fatalf("journal conflict count = %d", conflictCount)
	}
}

func seedSyncIdentity(t *testing.T, databaseHandle *sql.DB, accountID string, vaultID string) {
	t.Helper()
	if _, err := databaseHandle.Exec("INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
		t.Fatalf("seed sync account: %v", err)
	}
	if _, err := databaseHandle.Exec(
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')",
		vaultID,
		accountID,
	); err != nil {
		t.Fatalf("seed sync Vault: %v", err)
	}
}

func applySyncOperation(
	t *testing.T,
	repository *PostgresRepository,
	vaultID string,
	operation Operation,
	now time.Time,
) Decision {
	t.Helper()
	decision, err := repository.Apply(context.Background(), vaultID, operation, now)
	if err != nil {
		t.Fatalf("apply sync operation %s: %v", operation.OperationID, err)
	}
	return decision
}
