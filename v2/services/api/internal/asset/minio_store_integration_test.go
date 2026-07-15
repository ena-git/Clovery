package asset

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

func TestMinIOPresignedUploadCannotOverwriteObject(t *testing.T) {
	endpoint := os.Getenv("MINIO_INTEGRATION_ENDPOINT")
	if endpoint == "" {
		t.Skip("MINIO_INTEGRATION_ENDPOINT is required for MinIO integration tests")
	}
	accessKey := os.Getenv("MINIO_INTEGRATION_ACCESS_KEY")
	secretKey := os.Getenv("MINIO_INTEGRATION_SECRET_KEY")
	if accessKey == "" || secretKey == "" {
		t.Skip("MINIO integration credentials are required")
	}
	parsedEndpoint, err := url.Parse(endpoint)
	if err != nil || parsedEndpoint.Host == "" {
		t.Fatalf("parse MinIO integration endpoint: %v", err)
	}
	bucket := fmt.Sprintf("clovery-test-%d", time.Now().UnixNano())
	client, err := minio.New(parsedEndpoint.Host, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: parsedEndpoint.Scheme == "https",
	})
	if err != nil {
		t.Fatalf("create MinIO integration client: %v", err)
	}
	ctx := context.Background()
	if err := client.MakeBucket(ctx, bucket, minio.MakeBucketOptions{Region: s3SigningRegion}); err != nil {
		t.Fatalf("create MinIO integration bucket: %v", err)
	}
	t.Cleanup(func() {
		_ = client.RemoveObject(ctx, bucket, "vault/asset", minio.RemoveObjectOptions{})
		_ = client.RemoveBucket(ctx, bucket)
	})

	store, err := NewMinIOObjectStore(endpoint, bucket, accessKey, secretKey, true)
	if err != nil {
		t.Fatalf("create object store: %v", err)
	}
	objectBytes := []byte("first-private-photo")
	digest := sha256.Sum256(objectBytes)
	asset := Asset{
		ObjectKey: "vault/asset", ContentType: "image/jpeg",
		SHA256: hex.EncodeToString(digest[:]),
	}
	uploadURL, err := store.PresignUpload(ctx, asset, time.Minute)
	if err != nil {
		t.Fatalf("presign upload: %v", err)
	}
	if status := putPresignedObject(t, uploadURL, asset, objectBytes); status != http.StatusOK {
		t.Fatalf("first upload status = %d", status)
	}
	if status := putPresignedObject(t, uploadURL, asset, []byte("replacement")); status != http.StatusPreconditionFailed {
		t.Fatalf("replacement upload status = %d", status)
	}
	metadata, err := store.Stat(ctx, asset.ObjectKey)
	if err != nil {
		t.Fatalf("stat original object: %v", err)
	}
	if metadata.ByteSize != int64(len(objectBytes)) || metadata.SHA256 != asset.SHA256 {
		t.Fatalf("stored metadata = %#v", metadata)
	}
}

func putPresignedObject(t *testing.T, uploadURL string, asset Asset, contents []byte) int {
	t.Helper()
	request, err := http.NewRequest(http.MethodPut, uploadURL, bytes.NewReader(contents))
	if err != nil {
		t.Fatalf("create presigned PUT: %v", err)
	}
	request.Header.Set("Content-Type", asset.ContentType)
	request.Header.Set("X-Amz-Meta-Sha256", asset.SHA256)
	request.Header.Set(noOverwriteHeader, noOverwriteValue)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("execute presigned PUT: %v", err)
	}
	defer response.Body.Close()
	return response.StatusCode
}
