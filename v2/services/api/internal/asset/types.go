package asset

import "time"

const (
	StatusPending        = "pending"
	StatusComplete       = "complete"
	UploadStatusRequired = "upload_required"
	UploadStatusComplete = "complete"
)

type Asset struct {
	ID          string
	VaultID     string
	ObjectKey   string
	ContentType string
	ByteSize    int64
	SHA256      string
	Status      string
	CreatedAt   time.Time
	CompletedAt *time.Time
}

type UploadRequest struct {
	AssetID     string `json:"asset_id"`
	ContentType string `json:"content_type"`
	ByteSize    int64  `json:"byte_size"`
	SHA256      string `json:"sha256"`
}

type UploadTicket struct {
	AssetID   string            `json:"asset_id"`
	Status    string            `json:"status"`
	URL       string            `json:"upload_url,omitempty"`
	Headers   map[string]string `json:"required_headers,omitempty"`
	ExpiresAt *time.Time        `json:"expires_at,omitempty"`
}

type DownloadTicket struct {
	AssetID   string    `json:"asset_id"`
	URL       string    `json:"download_url"`
	ExpiresAt time.Time `json:"expires_at"`
}

type ObjectMetadata struct {
	ByteSize int64
	SHA256   string
}
