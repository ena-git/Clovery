package asset

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestNewMinIOObjectStoreRequiresExplicitHTTPSEndpointAndCredentials(t *testing.T) {
	for _, endpoint := range []string{"localhost:9000", "ftp://localhost:9000", "https://localhost:9000/path"} {
		if _, err := NewMinIOObjectStore(endpoint, "bucket", "access", "secret", false); err == nil {
			t.Fatalf("NewMinIOObjectStore() accepted endpoint %q", endpoint)
		}
	}
	if _, err := NewMinIOObjectStore("https://objects.clovery.example", "bucket", "access", "secret", false); err != nil {
		t.Fatalf("NewMinIOObjectStore() error = %v", err)
	}
	if _, err := NewMinIOObjectStore("http://objects.clovery.example", "bucket", "access", "secret", false); err == nil {
		t.Fatal("NewMinIOObjectStore() accepted plaintext production endpoint")
	}
}

func TestPresignUploadSignsNoOverwritePrecondition(t *testing.T) {
	store, err := NewMinIOObjectStore("https://objects.clovery.example", "private", "access", "secret", false)
	if err != nil {
		t.Fatalf("NewMinIOObjectStore() error = %v", err)
	}
	uploadURL, err := store.PresignUpload(context.Background(), Asset{
		ObjectKey: "vault/asset", ContentType: "image/jpeg", SHA256: stringsOf("a", 64),
	}, time.Minute)
	if err != nil {
		t.Fatalf("PresignUpload() error = %v", err)
	}
	parsed, err := url.Parse(uploadURL)
	if err != nil {
		t.Fatalf("parse upload URL: %v", err)
	}
	if !strings.Contains(parsed.Query().Get("X-Amz-SignedHeaders"), "if-none-match") {
		t.Fatalf("signed headers = %q", parsed.Query().Get("X-Amz-SignedHeaders"))
	}
}

func TestStatHashesObjectBytesInsteadOfTrustingMetadata(t *testing.T) {
	objectBytes := []byte("actual-private-photo")
	server := httptest.NewServer(http.HandlerFunc(func(responseWriter http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet {
			t.Fatalf("method = %s", request.Method)
		}
		responseWriter.Header().Set("X-Amz-Meta-Sha256", stringsOf("0", 64))
		_, _ = responseWriter.Write(objectBytes)
	}))
	t.Cleanup(server.Close)
	store, err := NewMinIOObjectStore(server.URL, "private", "access", "secret", true)
	if err != nil {
		t.Fatalf("NewMinIOObjectStore() error = %v", err)
	}

	metadata, err := store.Stat(context.Background(), "vault/asset")
	if err != nil {
		t.Fatalf("Stat() error = %v", err)
	}
	digest := sha256.Sum256(objectBytes)
	if metadata.ByteSize != int64(len(objectBytes)) || metadata.SHA256 != hex.EncodeToString(digest[:]) {
		t.Fatalf("metadata = %#v", metadata)
	}
}

func stringsOf(value string, count int) string {
	result := ""
	for len(result) < count {
		result += value
	}
	return result[:count]
}
