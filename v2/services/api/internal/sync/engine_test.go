package sync

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func TestDecideOperationCreatesTombstoneAndRejectsStaleRevision(t *testing.T) {
	now := time.Date(2026, time.July, 14, 17, 0, 0, 0, time.UTC)
	current := &Entry{ID: "entry", Revision: 3, Payload: json.RawMessage(`{"text":"server"}`)}
	deletion := Operation{
		OperationID: "delete", EntryID: "entry", BaseRevision: 3,
		Payload: json.RawMessage(`{}`), Deleted: true,
	}

	decision, err := DecideOperation(current, deletion, now)
	if err != nil {
		t.Fatalf("DecideOperation() error = %v", err)
	}
	if decision.Status != StatusApplied || decision.Entry.Revision != 4 || decision.Entry.DeletedAt == nil {
		t.Fatalf("deletion decision = %#v", decision)
	}

	stale := Operation{
		OperationID:  "stale",
		EntryID:      "entry",
		BaseRevision: 3,
		Payload:      json.RawMessage(`{"text":"stale client"}`),
	}
	decision, err = DecideOperation(decision.Entry, stale, now.Add(time.Second))
	if err != nil {
		t.Fatalf("stale DecideOperation() error = %v", err)
	}
	if decision.Status != StatusConflict || decision.ServerSnapshot == nil || decision.ServerSnapshot.Revision != 4 {
		t.Fatalf("stale decision = %#v", decision)
	}
}

func TestDecideOperationRejectsDeleteWithoutPayload(t *testing.T) {
	current := &Entry{ID: "entry", Revision: 1, Payload: json.RawMessage(`{"text":"server"}`)}
	_, err := DecideOperation(current, Operation{
		OperationID: "delete", EntryID: "entry", BaseRevision: 1, Deleted: true,
	}, time.Now())
	if err != ErrInvalidOperation {
		t.Fatalf("DecideOperation() error = %v", err)
	}
}

func TestDecideOperationCreatesFirstRevisionTombstoneWithPayload(t *testing.T) {
	now := time.Date(2026, time.July, 14, 17, 30, 0, 0, time.UTC)
	decision, err := DecideOperation(nil, Operation{
		OperationID: "delete", EntryID: "entry", BaseRevision: 0,
		Payload: json.RawMessage(`{}`), Deleted: true,
	}, now)
	if err != nil {
		t.Fatalf("DecideOperation() error = %v", err)
	}
	if decision.Status != StatusApplied || decision.Entry.DeletedAt == nil ||
		!bytes.Equal(decision.Entry.Payload, json.RawMessage(`{}`)) {
		t.Fatalf("tombstone decision = %#v", decision)
	}
}

func TestOperationFingerprintDetectsChangedReplay(t *testing.T) {
	first := Operation{
		OperationID:  "operation",
		EntryID:      "entry",
		BaseRevision: 0,
		Payload:      json.RawMessage(`{"text":"same"}`),
	}
	sameWithWhitespace := first
	sameWithWhitespace.Payload = json.RawMessage(" { \"text\" : \"same\" } ")
	changed := first
	changed.Payload = json.RawMessage(`{"text":"changed"}`)

	firstHash, err := OperationFingerprint(first)
	if err != nil {
		t.Fatalf("fingerprint first operation: %v", err)
	}
	sameHash, err := OperationFingerprint(sameWithWhitespace)
	if err != nil {
		t.Fatalf("fingerprint equivalent operation: %v", err)
	}
	changedHash, err := OperationFingerprint(changed)
	if err != nil {
		t.Fatalf("fingerprint changed operation: %v", err)
	}
	if !bytes.Equal(firstHash, sameHash) || bytes.Equal(firstHash, changedHash) {
		t.Fatalf("fingerprints first=%x same=%x changed=%x", firstHash, sameHash, changedHash)
	}
}

func TestBuildPullPageReturnsContinuousCursorAcrossPages(t *testing.T) {
	changes := []Change{{Cursor: 11}, {Cursor: 15}, {Cursor: 18}}
	page := BuildPullPage(changes, 2, 7)
	if len(page.Changes) != 2 || page.NextCursor != 15 || !page.HasMore {
		t.Fatalf("first page = %#v", page)
	}
	last := BuildPullPage(changes[2:], 2, page.NextCursor)
	if len(last.Changes) != 1 || last.NextCursor != 18 || last.HasMore {
		t.Fatalf("last page = %#v", last)
	}
}

func TestConflictDecisionOmitsAppliedEntry(t *testing.T) {
	decision, err := DecideOperation(nil, Operation{
		OperationID: "11111111-1111-4111-8111-111111111111",
		EntryID:     "22222222-2222-4222-8222-222222222222", BaseRevision: 3,
		Payload: json.RawMessage(`{"text":"client"}`),
	}, time.Now().UTC())
	if err != nil {
		t.Fatalf("DecideOperation() error = %v", err)
	}
	encoded, err := json.Marshal(decision)
	if err != nil {
		t.Fatalf("marshal conflict decision: %v", err)
	}
	if bytes.Contains(encoded, []byte(`"entry"`)) {
		t.Fatalf("conflict decision contains zero-value entry: %s", encoded)
	}
}
