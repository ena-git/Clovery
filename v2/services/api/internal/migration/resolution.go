package migration

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"time"
)

const (
	resolutionInsert           = "insert"
	resolutionExactDuplicate   = "exact_duplicate"
	resolutionContentDuplicate = "content_duplicate"
	resolutionIDConflictCopy   = "id_conflict_copy"
)

type ResolutionCandidate struct {
	SourceEntryID string
	EntryID       string
	Payload       json.RawMessage
	DedupPayload  json.RawMessage
	ContentSHA256 string
	DedupSHA256   string
	DeletedAt     *time.Time
}

type ExistingEntry struct {
	EntryID       string
	Payload       json.RawMessage
	DedupPayload  json.RawMessage
	ContentSHA256 string
	DedupSHA256   string
	DeletedAt     *time.Time
	UpdatedAt     time.Time
}

type EntryResolution struct {
	Candidate       ResolutionCandidate
	ResolvedEntryID string
	Resolution      string
}

func newResolutionCandidate(
	sourceEntryID string,
	entryID string,
	payload json.RawMessage,
	deletedAt *time.Time,
) (ResolutionCandidate, error) {
	canonical, err := canonicalJSON(payload)
	if err != nil {
		return ResolutionCandidate{}, err
	}
	dedup, err := canonicalDedupJSON(canonical)
	if err != nil {
		return ResolutionCandidate{}, err
	}
	return ResolutionCandidate{
		SourceEntryID: sourceEntryID,
		EntryID:       entryID,
		Payload:       canonical,
		DedupPayload:  dedup,
		ContentSHA256: canonicalDigest(canonical),
		DedupSHA256:   canonicalDigest(dedup),
		DeletedAt:     deletedAt,
	}, nil
}

func newExistingEntry(
	entryID string,
	payload json.RawMessage,
	deletedAt *time.Time,
	updatedAt time.Time,
) (ExistingEntry, error) {
	candidate, err := newResolutionCandidate(entryID, entryID, payload, deletedAt)
	if err != nil {
		return ExistingEntry{}, err
	}
	return ExistingEntry{
		EntryID:       entryID,
		Payload:       candidate.Payload,
		DedupPayload:  candidate.DedupPayload,
		ContentSHA256: candidate.ContentSHA256,
		DedupSHA256:   candidate.DedupSHA256,
		DeletedAt:     deletedAt,
		UpdatedAt:     updatedAt,
	}, nil
}

func resolveEntries(
	vaultID string,
	candidates []ResolutionCandidate,
	existing []ExistingEntry,
) ([]EntryResolution, error) {
	preparedCandidates := make([]ResolutionCandidate, len(candidates))
	for index, candidate := range candidates {
		prepared, err := prepareResolutionCandidate(candidate)
		if err != nil {
			return nil, err
		}
		preparedCandidates[index] = prepared
	}
	sort.Slice(preparedCandidates, func(left, right int) bool {
		if preparedCandidates[left].SourceEntryID == preparedCandidates[right].SourceEntryID {
			return preparedCandidates[left].EntryID < preparedCandidates[right].EntryID
		}
		return preparedCandidates[left].SourceEntryID < preparedCandidates[right].SourceEntryID
	})

	preparedExisting := make([]ExistingEntry, len(existing))
	entriesByID := make(map[string]ExistingEntry, len(existing)+len(candidates))
	for index, entry := range existing {
		prepared, err := prepareExistingEntry(entry)
		if err != nil {
			return nil, err
		}
		preparedExisting[index] = prepared
		entriesByID[prepared.EntryID] = prepared
	}
	sort.Slice(preparedExisting, func(left, right int) bool {
		if preparedExisting[left].UpdatedAt.Equal(preparedExisting[right].UpdatedAt) {
			return preparedExisting[left].EntryID < preparedExisting[right].EntryID
		}
		return preparedExisting[left].UpdatedAt.Before(preparedExisting[right].UpdatedAt)
	})

	stagedEntries := make([]ExistingEntry, 0, len(candidates))
	resolutions := make([]EntryResolution, 0, len(candidates))
	for _, candidate := range preparedCandidates {
		if target, exists := entriesByID[candidate.EntryID]; exists {
			if sameExactEntry(candidate, target) {
				resolutions = append(resolutions, EntryResolution{
					Candidate: candidate, ResolvedEntryID: target.EntryID,
					Resolution: resolutionExactDuplicate,
				})
				continue
			}

			resolvedID, duplicate := resolveConflictTarget(vaultID, candidate, entriesByID)
			resolution := resolutionIDConflictCopy
			if duplicate {
				resolution = resolutionExactDuplicate
			} else {
				inserted := existingFromCandidate(candidate, resolvedID)
				entriesByID[resolvedID] = inserted
				stagedEntries = append(stagedEntries, inserted)
			}
			resolutions = append(resolutions, EntryResolution{
				Candidate: candidate, ResolvedEntryID: resolvedID, Resolution: resolution,
			})
			continue
		}

		if candidate.DeletedAt == nil {
			if target, found := findContentDuplicate(candidate, preparedExisting); found {
				resolutions = append(resolutions, EntryResolution{
					Candidate: candidate, ResolvedEntryID: target.EntryID,
					Resolution: resolutionContentDuplicate,
				})
				continue
			}
			if target, found := findContentDuplicate(candidate, stagedEntries); found {
				resolutions = append(resolutions, EntryResolution{
					Candidate: candidate, ResolvedEntryID: target.EntryID,
					Resolution: resolutionContentDuplicate,
				})
				continue
			}
		}

		inserted := existingFromCandidate(candidate, candidate.EntryID)
		entriesByID[candidate.EntryID] = inserted
		stagedEntries = append(stagedEntries, inserted)
		resolutions = append(resolutions, EntryResolution{
			Candidate: candidate, ResolvedEntryID: candidate.EntryID, Resolution: resolutionInsert,
		})
	}
	return resolutions, nil
}

func prepareResolutionCandidate(candidate ResolutionCandidate) (ResolutionCandidate, error) {
	prepared, err := newResolutionCandidate(
		candidate.SourceEntryID, candidate.EntryID, candidate.Payload, candidate.DeletedAt,
	)
	if err != nil {
		return ResolutionCandidate{}, err
	}
	if candidate.ContentSHA256 != "" {
		prepared.ContentSHA256 = candidate.ContentSHA256
	}
	if candidate.DedupSHA256 != "" {
		prepared.DedupSHA256 = candidate.DedupSHA256
	}
	if len(candidate.DedupPayload) > 0 {
		prepared.DedupPayload = append(json.RawMessage(nil), candidate.DedupPayload...)
	}
	return prepared, nil
}

func prepareExistingEntry(entry ExistingEntry) (ExistingEntry, error) {
	prepared, err := newExistingEntry(entry.EntryID, entry.Payload, entry.DeletedAt, entry.UpdatedAt)
	if err != nil {
		return ExistingEntry{}, err
	}
	if entry.ContentSHA256 != "" {
		prepared.ContentSHA256 = entry.ContentSHA256
	}
	if entry.DedupSHA256 != "" {
		prepared.DedupSHA256 = entry.DedupSHA256
	}
	if len(entry.DedupPayload) > 0 {
		prepared.DedupPayload = append(json.RawMessage(nil), entry.DedupPayload...)
	}
	return prepared, nil
}

func findContentDuplicate(candidate ResolutionCandidate, entries []ExistingEntry) (ExistingEntry, bool) {
	for _, entry := range entries {
		if sameCanonicalContent(candidate, entry) {
			return entry, true
		}
	}
	return ExistingEntry{}, false
}

func sameCanonicalContent(candidate ResolutionCandidate, existing ExistingEntry) bool {
	return candidate.DeletedAt == nil && existing.DeletedAt == nil &&
		candidate.DedupSHA256 == existing.DedupSHA256 &&
		bytes.Equal(candidate.DedupPayload, existing.DedupPayload)
}

func sameExactEntry(candidate ResolutionCandidate, existing ExistingEntry) bool {
	return (candidate.DeletedAt == nil) == (existing.DeletedAt == nil) &&
		candidate.ContentSHA256 == existing.ContentSHA256 &&
		bytes.Equal(candidate.Payload, existing.Payload)
}

func resolveConflictTarget(
	vaultID string,
	candidate ResolutionCandidate,
	entriesByID map[string]ExistingEntry,
) (string, bool) {
	for counter := 0; ; counter++ {
		candidateID := conflictEntryID(
			vaultID, candidate.SourceEntryID, candidate.ContentSHA256, counter,
		).String()
		existing, occupied := entriesByID[candidateID]
		if !occupied {
			return candidateID, false
		}
		if sameExactEntry(candidate, existing) {
			return candidateID, true
		}
	}
}

func existingFromCandidate(candidate ResolutionCandidate, entryID string) ExistingEntry {
	return ExistingEntry{
		EntryID:       entryID,
		Payload:       append(json.RawMessage(nil), candidate.Payload...),
		DedupPayload:  append(json.RawMessage(nil), candidate.DedupPayload...),
		ContentSHA256: candidate.ContentSHA256,
		DedupSHA256:   candidate.DedupSHA256,
		DeletedAt:     candidate.DeletedAt,
	}
}

func canonicalDigest(payload json.RawMessage) string {
	digest := sha256.Sum256(payload)
	return hex.EncodeToString(digest[:])
}
