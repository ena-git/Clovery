package migration

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"testing"
	"time"
)

func TestResolutionClassifiesExistingEntriesWithoutDataLoss(t *testing.T) {
	vaultID := "11111111-1111-4111-8111-111111111111"
	now := time.Date(2026, 7, 19, 8, 0, 0, 0, time.UTC)
	deletedAt := now.Add(-time.Hour)

	tests := []struct {
		name       string
		candidate  ResolutionCandidate
		existing   []ExistingEntry
		resolution string
		resolvedID string
	}{
		{
			name:       "same ID and same active JSON with different key ordering",
			candidate:  mustResolutionCandidate(t, "legacy-a", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"hello","tags":["a"]}`, nil),
			existing:   []ExistingEntry{mustExistingEntry(t, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"tags":["a"],"text":"hello","id":"legacy-a"}`, nil, now)},
			resolution: resolutionExactDuplicate,
			resolvedID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		},
		{
			name:       "same ID and different JSON",
			candidate:  mustResolutionCandidate(t, "legacy-a", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"new"}`, nil),
			existing:   []ExistingEntry{mustExistingEntry(t, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"old"}`, nil, now)},
			resolution: resolutionIDConflictCopy,
		},
		{
			name:       "different ID and same active JSON",
			candidate:  mustResolutionCandidate(t, "legacy-b", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", `{"id":"legacy-b","text":"same"}`, nil),
			existing:   []ExistingEntry{mustExistingEntry(t, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"same"}`, nil, now)},
			resolution: resolutionContentDuplicate,
			resolvedID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		},
		{
			name:       "same tombstone ID and deleted state",
			candidate:  mustResolutionCandidate(t, "legacy-a", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{}`, &deletedAt),
			existing:   []ExistingEntry{mustExistingEntry(t, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{}`, &deletedAt, now)},
			resolution: resolutionExactDuplicate,
			resolvedID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := resolveEntries(vaultID, []ResolutionCandidate{test.candidate}, test.existing)
			if err != nil {
				t.Fatalf("resolveEntries() error = %v", err)
			}
			if len(got) != 1 || got[0].Resolution != test.resolution {
				t.Fatalf("resolveEntries() = %#v, want resolution %q", got, test.resolution)
			}
			if test.resolvedID != "" && got[0].ResolvedEntryID != test.resolvedID {
				t.Fatalf("resolved ID = %q, want %q", got[0].ResolvedEntryID, test.resolvedID)
			}
			if test.resolution == resolutionIDConflictCopy && got[0].ResolvedEntryID == test.candidate.EntryID {
				t.Fatal("ID conflict reused the colliding entry ID")
			}
		})
	}
}

func TestResolutionRequiresCanonicalBytesAfterDedupHashMatch(t *testing.T) {
	const forcedDigest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	candidate := mustResolutionCandidate(
		t, "legacy-b", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", `{"id":"legacy-b","text":"left"}`, nil,
	)
	candidate.DedupSHA256 = forcedDigest
	existing := mustExistingEntry(
		t, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"right"}`, nil, time.Now().UTC(),
	)
	existing.DedupSHA256 = forcedDigest

	got, err := resolveEntries(
		"11111111-1111-4111-8111-111111111111",
		[]ResolutionCandidate{candidate},
		[]ExistingEntry{existing},
	)
	if err != nil {
		t.Fatalf("resolveEntries() error = %v", err)
	}
	if len(got) != 1 || got[0].Resolution != resolutionInsert {
		t.Fatalf("resolveEntries() = %#v, want insert", got)
	}
}

func TestResolutionPreservesDifferentTombstoneIDs(t *testing.T) {
	deletedAt := time.Date(2026, 7, 19, 8, 0, 0, 0, time.UTC)
	candidates := []ResolutionCandidate{
		mustResolutionCandidate(t, "legacy-b", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", `{}`, &deletedAt),
		mustResolutionCandidate(t, "legacy-a", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{}`, &deletedAt),
	}

	got, err := resolveEntries("11111111-1111-4111-8111-111111111111", candidates, nil)
	if err != nil {
		t.Fatalf("resolveEntries() error = %v", err)
	}
	if len(got) != 2 || got[0].Resolution != resolutionInsert || got[1].Resolution != resolutionInsert {
		t.Fatalf("resolveEntries() = %#v, want two inserts", got)
	}
	if got[0].ResolvedEntryID == got[1].ResolvedEntryID {
		t.Fatal("different tombstones collapsed to one entry")
	}
}

func TestResolutionUsesFirstSourceIDForStagedContentDuplicates(t *testing.T) {
	candidates := []ResolutionCandidate{
		mustResolutionCandidate(t, "legacy-z", "cccccccc-cccc-4ccc-8ccc-cccccccccccc", `{"id":"legacy-z","text":"same"}`, nil),
		mustResolutionCandidate(t, "legacy-a", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"same"}`, nil),
	}

	got, err := resolveEntries("11111111-1111-4111-8111-111111111111", candidates, nil)
	if err != nil {
		t.Fatalf("resolveEntries() error = %v", err)
	}
	if len(got) != 2 || got[0].Candidate.SourceEntryID != "legacy-a" || got[0].Resolution != resolutionInsert {
		t.Fatalf("first resolution = %#v, want legacy-a insert", got)
	}
	if got[1].Candidate.SourceEntryID != "legacy-z" || got[1].Resolution != resolutionContentDuplicate ||
		got[1].ResolvedEntryID != got[0].ResolvedEntryID {
		t.Fatalf("second resolution = %#v, want alias to first", got[1])
	}
}

func TestConflictEntryIDIsStableAcrossMigrationIDs(t *testing.T) {
	vaultID := "11111111-1111-4111-8111-111111111111"
	first := conflictEntryID(vaultID, "legacy-a", "abcd", 0)
	second := conflictEntryID(vaultID, "legacy-a", "abcd", 0)
	if first != second {
		t.Fatalf("conflict IDs differ: %s != %s", first, second)
	}
	if first == conflictEntryID(vaultID, "legacy-a", "abcd", 1) {
		t.Fatal("salted conflict ID did not change")
	}
}

func TestResolutionSaltsOccupiedConflictIDDeterministically(t *testing.T) {
	vaultID := "11111111-1111-4111-8111-111111111111"
	candidate := mustResolutionCandidate(
		t, "legacy-a", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", `{"id":"legacy-a","text":"new"}`, nil,
	)
	baseConflictID := conflictEntryID(vaultID, candidate.SourceEntryID, candidate.ContentSHA256, 0).String()
	existing := []ExistingEntry{
		mustExistingEntry(t, candidate.EntryID, `{"id":"legacy-a","text":"old"}`, nil, time.Now().UTC()),
		mustExistingEntry(t, baseConflictID, `{"id":"other","text":"occupied"}`, nil, time.Now().UTC()),
	}

	got, err := resolveEntries(vaultID, []ResolutionCandidate{candidate}, existing)
	if err != nil {
		t.Fatalf("resolveEntries() error = %v", err)
	}
	want := conflictEntryID(vaultID, candidate.SourceEntryID, candidate.ContentSHA256, 1).String()
	if len(got) != 1 || got[0].Resolution != resolutionIDConflictCopy || got[0].ResolvedEntryID != want {
		t.Fatalf("resolveEntries() = %#v, want conflict ID %s", got, want)
	}
}

func mustResolutionCandidate(
	t *testing.T,
	sourceEntryID string,
	entryID string,
	payload string,
	deletedAt *time.Time,
) ResolutionCandidate {
	t.Helper()
	canonical, err := canonicalJSON(json.RawMessage(payload))
	if err != nil {
		t.Fatalf("canonicalJSON() error = %v", err)
	}
	dedup, err := canonicalDedupJSON(canonical)
	if err != nil {
		t.Fatalf("canonicalDedupJSON() error = %v", err)
	}
	return ResolutionCandidate{
		SourceEntryID: sourceEntryID,
		EntryID:       entryID,
		Payload:       canonical,
		DedupPayload:  dedup,
		ContentSHA256: digestJSON(canonical),
		DedupSHA256:   digestJSON(dedup),
		DeletedAt:     deletedAt,
	}
}

func mustExistingEntry(
	t *testing.T,
	entryID string,
	payload string,
	deletedAt *time.Time,
	updatedAt time.Time,
) ExistingEntry {
	t.Helper()
	candidate := mustResolutionCandidate(t, entryID, entryID, payload, deletedAt)
	return ExistingEntry{
		EntryID:       entryID,
		Payload:       candidate.Payload,
		DedupPayload:  candidate.DedupPayload,
		ContentSHA256: candidate.ContentSHA256,
		DedupSHA256:   candidate.DedupSHA256,
		DeletedAt:     deletedAt,
		UpdatedAt:     updatedAt,
	}
}

func digestJSON(payload json.RawMessage) string {
	digest := sha256.Sum256(payload)
	return hex.EncodeToString(digest[:])
}
