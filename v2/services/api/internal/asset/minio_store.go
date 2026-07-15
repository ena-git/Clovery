package asset

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/minio/minio-go/v7/pkg/signer"
)

const s3SigningRegion = "us-east-1"

type MinIOObjectStore struct {
	endpoint  *url.URL
	bucket    string
	accessKey string
	secretKey string
	client    *http.Client
}

func NewMinIOObjectStore(
	endpoint string,
	bucket string,
	accessKey string,
	secretKey string,
	allowInsecure bool,
) (*MinIOObjectStore, error) {
	parsed, err := url.Parse(strings.TrimSpace(endpoint))
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" ||
		(parsed.Path != "" && parsed.Path != "/") || parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, fmt.Errorf("S3 endpoint must be an HTTP(S) origin")
	}
	if parsed.Scheme == "http" && !allowInsecure {
		return nil, fmt.Errorf("plaintext S3 endpoint requires an explicit development override")
	}
	bucket = strings.TrimSpace(bucket)
	accessKey = strings.TrimSpace(accessKey)
	secretKey = strings.TrimSpace(secretKey)
	if bucket == "" || accessKey == "" || secretKey == "" {
		return nil, fmt.Errorf("S3 bucket and credentials are required")
	}
	return &MinIOObjectStore{
		endpoint: parsed, bucket: bucket, accessKey: accessKey, secretKey: secretKey,
		client: &http.Client{Timeout: 15 * time.Second},
	}, nil
}

func (store *MinIOObjectStore) PresignUpload(
	ctx context.Context,
	asset Asset,
	lifetime time.Duration,
) (string, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodPut, store.objectURL(asset.ObjectKey), nil)
	if err != nil {
		return "", fmt.Errorf("create asset upload request: %w", err)
	}
	request.Header.Set("Content-Type", asset.ContentType)
	request.Header.Set("X-Amz-Meta-Sha256", asset.SHA256)
	request.Header.Set(noOverwriteHeader, noOverwriteValue)
	signed := signer.PreSignV4(
		*request, store.accessKey, store.secretKey, "", s3SigningRegion, int64(lifetime.Seconds()),
	)
	return signed.URL.String(), nil
}

func (store *MinIOObjectStore) Stat(ctx context.Context, objectKey string) (ObjectMetadata, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, store.objectURL(objectKey), nil)
	if err != nil {
		return ObjectMetadata{}, fmt.Errorf("create asset stat request: %w", err)
	}
	signed := signer.SignV4(*request, store.accessKey, store.secretKey, "", s3SigningRegion)
	response, err := store.client.Do(signed)
	if err != nil {
		return ObjectMetadata{}, fmt.Errorf("stat uploaded asset: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return ObjectMetadata{}, fmt.Errorf("stat uploaded asset: object store returned %d", response.StatusCode)
	}
	hasher := sha256.New()
	byteSize, err := io.Copy(hasher, io.LimitReader(response.Body, maximumAssetSize+1))
	if err != nil {
		return ObjectMetadata{}, fmt.Errorf("hash uploaded asset: %w", err)
	}
	if byteSize > maximumAssetSize {
		return ObjectMetadata{}, fmt.Errorf("hash uploaded asset: object exceeds maximum size")
	}
	return ObjectMetadata{ByteSize: byteSize, SHA256: hex.EncodeToString(hasher.Sum(nil))}, nil
}

func (store *MinIOObjectStore) PresignDownload(
	ctx context.Context,
	asset Asset,
	lifetime time.Duration,
) (string, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, store.objectURL(asset.ObjectKey), nil)
	if err != nil {
		return "", fmt.Errorf("create asset download request: %w", err)
	}
	signed := signer.PreSignV4(
		*request, store.accessKey, store.secretKey, "", s3SigningRegion, int64(lifetime.Seconds()),
	)
	return signed.URL.String(), nil
}

func (store *MinIOObjectStore) objectURL(objectKey string) string {
	objectURL := *store.endpoint
	objectURL.Path = "/" + store.bucket + "/" + strings.TrimPrefix(objectKey, "/")
	return objectURL.String()
}
