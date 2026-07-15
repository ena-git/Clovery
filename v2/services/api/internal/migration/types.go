package migration

import (
	"encoding/json"
	"time"

	"github.com/clovery/clovery/services/api/internal/asset"
)

type CreateRequest struct {
	MigrationID    string `json:"migration_id"`
	FormatVersion  int    `json:"format_version"`
	Source         string `json:"source"`
	EntryCount     int    `json:"entry_count"`
	AssetCount     int    `json:"asset_count"`
	TotalBytes     int64  `json:"total_bytes"`
	ManifestSHA256 string `json:"manifest_sha256"`
	ManifestBase64 string `json:"manifest_base64"`
}

type Migration struct {
	ID             string          `json:"migration_id"`
	VaultID        string          `json:"-"`
	FormatVersion  int             `json:"format_version"`
	Source         string          `json:"source"`
	EntryCount     int             `json:"entry_count"`
	DeletedCount   int             `json:"deleted_count"`
	AssetCount     int             `json:"asset_count"`
	TotalBytes     int64           `json:"total_bytes"`
	ManifestSHA256 string          `json:"manifest_sha256"`
	Manifest       json.RawMessage `json:"-"`
	ManifestBytes  []byte          `json:"-"`
	Status         string          `json:"status"`
	CreatedAt      time.Time       `json:"created_at"`
}

type EntryInput struct {
	EntryID       string          `json:"entry_id"`
	SourceEntryID string          `json:"-"`
	Payload       json.RawMessage `json:"payload"`
	DeletedAt     *time.Time      `json:"deleted_at,omitempty"`
	SHA256        string          `json:"sha256"`
}

type AssetInput struct {
	AssetID        string `json:"asset_id"`
	SourceFilename string `json:"source_filename"`
	ContentType    string `json:"content_type"`
	ByteSize       int64  `json:"byte_size"`
	SHA256         string `json:"sha256"`
}

func (input AssetInput) uploadRequest() asset.UploadRequest {
	return asset.UploadRequest{
		AssetID: input.AssetID, ContentType: input.ContentType,
		ByteSize: input.ByteSize, SHA256: input.SHA256,
	}
}

type Report struct {
	MigrationID            string          `json:"migration_id"`
	Status                 string          `json:"status"`
	ExpectedEntries        int             `json:"expected_entries"`
	ImportedEntries        int             `json:"imported_entries"`
	ExpectedDeletedEntries int             `json:"expected_deleted_entries"`
	ImportedDeletedEntries int             `json:"imported_deleted_entries"`
	ExpectedAssets         int             `json:"expected_assets"`
	VerifiedAssets         int             `json:"verified_assets"`
	ExpectedBytes          int64           `json:"expected_bytes"`
	VerifiedBytes          int64           `json:"verified_bytes"`
	Errors                 json.RawMessage `json:"errors"`
	VerifiedAt             *time.Time      `json:"verified_at,omitempty"`
}
