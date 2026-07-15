package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/asset"
)

func TestAssetRoutesUseAuthenticatedVault(t *testing.T) {
	application := &stubAssetHTTPApplication{
		upload:   asset.UploadTicket{AssetID: "asset", URL: "https://upload.example"},
		download: asset.DownloadTicket{AssetID: "asset", URL: "https://download.example"},
	}
	router := NewRouter(RouterDependencies{Sessions: managementSessions(), Assets: application})

	uploadRequest := httptest.NewRequest(
		http.MethodPost,
		"/v1/vault/assets/uploads",
		strings.NewReader(`{"asset_id":"22222222-2222-4222-8222-222222222222","content_type":"image/jpeg","byte_size":20,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`),
	)
	uploadRequest.Header.Set("Authorization", "Bearer access-token")
	uploadRequest.Header.Set("Content-Type", "application/json")
	uploadResponse := httptest.NewRecorder()
	router.ServeHTTP(uploadResponse, uploadRequest)
	if uploadResponse.Code != http.StatusCreated {
		t.Fatalf("upload status = %d, body = %s", uploadResponse.Code, uploadResponse.Body.String())
	}

	completeRequest := httptest.NewRequest(http.MethodPost, "/v1/vault/assets/asset/complete", nil)
	completeRequest.Header.Set("Authorization", "Bearer access-token")
	completeResponse := httptest.NewRecorder()
	router.ServeHTTP(completeResponse, completeRequest)
	if completeResponse.Code != http.StatusNoContent {
		t.Fatalf("complete status = %d, body = %s", completeResponse.Code, completeResponse.Body.String())
	}

	downloadRequest := httptest.NewRequest(http.MethodGet, "/v1/vault/assets/asset/download", nil)
	downloadRequest.Header.Set("Authorization", "Bearer access-token")
	downloadResponse := httptest.NewRecorder()
	router.ServeHTTP(downloadResponse, downloadRequest)
	if downloadResponse.Code != http.StatusOK {
		t.Fatalf("download status = %d, body = %s", downloadResponse.Code, downloadResponse.Body.String())
	}
	claims := managementSessions().claims
	if application.accountID != claims.AccountID || application.vaultID != claims.VaultID || application.assetID != "asset" {
		t.Fatalf("asset scope account = %q, vault = %q, asset = %q", application.accountID, application.vaultID, application.assetID)
	}
}

type stubAssetHTTPApplication struct {
	accountID string
	vaultID   string
	assetID   string
	upload    asset.UploadTicket
	download  asset.DownloadTicket
}

func (stub *stubAssetHTTPApplication) StartUpload(
	_ context.Context,
	accountID string,
	vaultID string,
	_ asset.UploadRequest,
) (asset.UploadTicket, error) {
	stub.accountID = accountID
	stub.vaultID = vaultID
	return stub.upload, nil
}

func (stub *stubAssetHTTPApplication) Complete(
	_ context.Context,
	accountID string,
	vaultID string,
	assetID string,
) error {
	stub.accountID = accountID
	stub.vaultID = vaultID
	stub.assetID = assetID
	return nil
}

func (stub *stubAssetHTTPApplication) Download(
	_ context.Context,
	accountID string,
	vaultID string,
	assetID string,
) (asset.DownloadTicket, error) {
	stub.accountID = accountID
	stub.vaultID = vaultID
	stub.assetID = assetID
	return stub.download, nil
}
