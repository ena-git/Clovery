package migration

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"regexp"
	"strings"
	"time"
)

var migrationPhotoNamePattern = regexp.MustCompile(`^[A-Za-z0-9-]+\.jpg$`)
var migrationSHA256Pattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type bundleManifest struct {
	FormatVersion    int                   `json:"format_version"`
	ExportedAt       string                `json:"exported_at"`
	EntriesFile      string                `json:"entries_file"`
	EntriesSHA256    string                `json:"entries_sha256"`
	EntryCount       int                   `json:"entry_count"`
	Entries          []bundleManifestEntry `json:"entries"`
	DeletedIDsFile   string                `json:"deleted_ids_file"`
	DeletedIDsSHA256 string                `json:"deleted_ids_sha256"`
	DeletedCount     int                   `json:"deleted_count"`
	DeletedIDs       []string              `json:"deleted_ids"`
	Photos           []bundleManifestPhoto `json:"photos"`
	Sources          []string              `json:"sources"`
}

type bundleManifestEntry struct {
	EntryID string `json:"entry_id"`
	SHA256  string `json:"sha256"`
	Bytes   int64  `json:"bytes"`
}

type bundleManifestPhoto struct {
	Filename string `json:"filename"`
	SHA256   string `json:"sha256"`
	Bytes    int64  `json:"bytes"`
}

func decodeBundleManifest(request CreateRequest) (json.RawMessage, []byte, bundleManifest, error) {
	manifestBytes, err := base64.StdEncoding.DecodeString(strings.TrimSpace(request.ManifestBase64))
	if err != nil || len(manifestBytes) == 0 {
		return nil, nil, bundleManifest{}, ErrInvalidBundle
	}
	digest := sha256.Sum256(manifestBytes)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), strings.TrimSpace(request.ManifestSHA256)) {
		return nil, nil, bundleManifest{}, ErrIntegrityMismatch
	}
	var manifest bundleManifest
	if json.Unmarshal(manifestBytes, &manifest) != nil || !validManifest(manifest, request) {
		return nil, nil, bundleManifest{}, ErrInvalidBundle
	}
	return append(json.RawMessage(nil), manifestBytes...), manifestBytes, manifest, nil
}

func validManifest(manifest bundleManifest, request CreateRequest) bool {
	if manifest.FormatVersion != request.FormatVersion || manifest.EntryCount != request.EntryCount ||
		len(manifest.Entries) != request.EntryCount || len(manifest.Photos) != request.AssetCount ||
		manifest.Entries == nil || manifest.DeletedIDs == nil || manifest.Photos == nil ||
		manifest.EntriesFile != "entries.json" || manifest.DeletedIDsFile != "deleted_ids.json" ||
		manifest.DeletedCount < 0 || len(manifest.DeletedIDs) != manifest.DeletedCount ||
		!validManifestSHA256(manifest.EntriesSHA256) ||
		!validManifestSHA256(manifest.DeletedIDsSHA256) || len(manifest.Sources) == 0 {
		return false
	}
	if _, err := time.Parse(time.RFC3339Nano, manifest.ExportedAt); err != nil {
		return false
	}
	seenSources := make(map[string]struct{}, len(manifest.Sources))
	for _, source := range manifest.Sources {
		if strings.TrimSpace(source) != source || source == "" {
			return false
		}
		if _, exists := seenSources[source]; exists {
			return false
		}
		seenSources[source] = struct{}{}
	}
	contentBytes, activeIDs, valid := validManifestEntries(manifest.Entries, request.TotalBytes)
	if !valid {
		return false
	}
	for _, deletedID := range manifest.DeletedIDs {
		if !migrationSourceEntryIDPattern.MatchString(deletedID) {
			return false
		}
		if _, exists := activeIDs[deletedID]; exists {
			return false
		}
		activeIDs[deletedID] = struct{}{}
		if !addManifestBytes(&contentBytes, 2, request.TotalBytes) {
			return false
		}
	}
	seenPhotos := make(map[string]struct{}, len(manifest.Photos))
	for _, photo := range manifest.Photos {
		if !migrationPhotoNamePattern.MatchString(photo.Filename) || photo.Bytes < 1 ||
			!validManifestSHA256(photo.SHA256) {
			return false
		}
		if _, exists := seenPhotos[photo.Filename]; exists {
			return false
		}
		seenPhotos[photo.Filename] = struct{}{}
		if !addManifestBytes(&contentBytes, photo.Bytes, request.TotalBytes) {
			return false
		}
	}
	return contentBytes == request.TotalBytes
}

func validManifestEntries(entries []bundleManifestEntry, maximumBytes int64) (int64, map[string]struct{}, bool) {
	seen := make(map[string]struct{}, len(entries))
	var totalBytes int64
	for _, entry := range entries {
		if !migrationSourceEntryIDPattern.MatchString(entry.EntryID) || entry.Bytes < 1 ||
			!validManifestSHA256(entry.SHA256) {
			return 0, nil, false
		}
		if _, exists := seen[entry.EntryID]; exists {
			return 0, nil, false
		}
		seen[entry.EntryID] = struct{}{}
		if !addManifestBytes(&totalBytes, entry.Bytes, maximumBytes) {
			return 0, nil, false
		}
	}
	return totalBytes, seen, true
}

func validManifestSHA256(value string) bool {
	return migrationSHA256Pattern.MatchString(strings.ToLower(value))
}

func addManifestBytes(total *int64, value int64, maximum int64) bool {
	if value < 0 || *total > maximum-value {
		return false
	}
	*total += value
	return true
}
