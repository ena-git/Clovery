package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/clovery/clovery/services/api/internal/asset"
	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
)

func TestMigrationCreateUsesAuthenticatedVault(t *testing.T) {
	application := &stubMigrationHTTPApplication{migration: cloverymigration.Migration{ID: "migration", Status: "uploading"}}
	router := NewRouter(RouterDependencies{
		Sessions: managementSessions(), Migrations: application, MigrationWritesEnabled: true,
	})
	manifest := []byte(`{"format_version":1,"exported_at":"2026-07-14T00:00:00Z","entries_file":"entries.json","entries_sha256":"4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945","entry_count":0,"entries":[],"deleted_ids_file":"deleted_ids.json","deleted_ids_sha256":"4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945","deleted_count":0,"deleted_ids":[],"photos":[],"sources":["localStorage"]}`)
	digest := sha256.Sum256(manifest)
	payload := fmt.Sprintf(
		`{"migration_id":"11111111-1111-4111-8111-111111111111","format_version":1,"source":"v1_bundle","entry_count":0,"asset_count":0,"total_bytes":0,"manifest_sha256":%q,"manifest_base64":%q}`,
		hex.EncodeToString(digest[:]), base64.StdEncoding.EncodeToString(manifest),
	)
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/vault/migrations",
		strings.NewReader(payload),
	)
	request.Header.Set("Authorization", "Bearer access-token")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated || application.vaultID != managementSessions().claims.VaultID {
		t.Fatalf("status = %d, vault = %q, body = %s", response.Code, application.vaultID, response.Body.String())
	}
}

func TestMigrationEntryAcceptsLegacyPayloadAboveDefaultJSONLimit(t *testing.T) {
	application := &stubMigrationHTTPApplication{}
	router := NewRouter(RouterDependencies{
		Sessions: managementSessions(), Migrations: application, MigrationWritesEnabled: true,
	})
	body := `{"entry_id":"new-1720000000000","payload":{"text":"` +
		strings.Repeat("a", 70*1024) + `"},"sha256":"` + strings.Repeat("a", 64) + `"}`
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/vault/migrations/11111111-1111-4111-8111-111111111111/entries",
		strings.NewReader(body),
	)
	request.Header.Set("Authorization", "Bearer access-token")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("large migration entry status = %d, body = %s", response.Code, response.Body.String())
	}
}

type stubMigrationHTTPApplication struct {
	vaultID   string
	migration cloverymigration.Migration
}

func (stub *stubMigrationHTTPApplication) Create(
	_ context.Context, _ string, vaultID string, _ cloverymigration.CreateRequest,
) (cloverymigration.Migration, error) {
	stub.vaultID = vaultID
	return stub.migration, nil
}

func (*stubMigrationHTTPApplication) AddEntry(context.Context, string, string, string, cloverymigration.EntryInput) error {
	return nil
}

func (*stubMigrationHTTPApplication) AddAsset(context.Context, string, string, string, cloverymigration.AssetInput) (asset.UploadTicket, error) {
	return asset.UploadTicket{}, nil
}

func (*stubMigrationHTTPApplication) Verify(context.Context, string, string, string) (cloverymigration.Report, error) {
	return cloverymigration.Report{}, nil
}

func (*stubMigrationHTTPApplication) Report(context.Context, string, string, string) (cloverymigration.Report, error) {
	return cloverymigration.Report{}, nil
}
