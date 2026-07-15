package contract_test

import (
	"context"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
)

func TestOpenAPIContractIsValid(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve test file path")
	}

	contractPath := filepath.Join(
		filepath.Dir(currentFile),
		"..", "..", "..", "..", "contracts", "openapi", "openapi.yaml",
	)
	document, err := openapi3.NewLoader().LoadFromFile(contractPath)
	if err != nil {
		t.Fatalf("load OpenAPI contract: %v", err)
	}
	if err := document.Validate(context.Background()); err != nil {
		t.Fatalf("validate OpenAPI contract: %v", err)
	}
	if document.Info.Version != "0.1.0" {
		t.Fatalf("version = %q", document.Info.Version)
	}
	if document.Paths.Find("/v1/health") == nil {
		t.Fatal("missing GET /v1/health contract")
	}

	for _, schemaName := range []string{"CloveryAccountId", "VaultId", "CloveryLoginId"} {
		if document.Components.Schemas[schemaName] == nil {
			t.Fatalf("missing %s schema", schemaName)
		}
	}
	loginIDSchema := document.Components.Schemas["CloveryLoginId"].Value
	if loginIDSchema == nil || loginIDSchema.Pattern != "^[a-z][a-z0-9_]{3,23}$" {
		t.Fatal("CloveryLoginId must preserve the database validation pattern")
	}

	for _, path := range []string{
		"/v1/auth/accounts",
		"/v1/auth/password/login",
		"/v1/auth/password/reset/start",
		"/v1/auth/password/reset/complete",
		"/v1/auth/recovery-codes",
		"/v1/auth/recovery-codes/consume",
		"/v1/auth/sessions/refresh",
	} {
		pathItem := document.Paths.Find(path)
		if pathItem == nil || pathItem.Post == nil {
			t.Fatalf("missing POST %s contract", path)
		}
	}
	for path, methodStatuses := range map[string]map[string][]string{
		"/v1/vault/sync/pull": {
			"get": {"400", "401"},
		},
		"/v1/vault/assets/uploads": {
			"post": {"400", "401", "403", "409"},
		},
		"/v1/vault/assets/{assetId}/complete": {
			"post": {"401", "403", "404", "422"},
		},
		"/v1/vault/assets/{assetId}/download": {
			"get": {"401", "403", "404", "409"},
		},
	} {
		pathItem := document.Paths.Find(path)
		for method, statuses := range methodStatuses {
			operation := pathItem.Get
			if method == "post" {
				operation = pathItem.Post
			}
			for _, status := range statuses {
				if operation.Responses.Value(status) == nil {
					t.Fatalf("missing %s %s response %s", method, path, status)
				}
			}
		}
	}

	for _, path := range []string{"/v1/account", "/v1/account/devices", "/v1/vault"} {
		pathItem := document.Paths.Find(path)
		if pathItem == nil || pathItem.Get == nil {
			t.Fatalf("missing GET %s contract", path)
		}
	}
	for _, path := range []string{"/v1/account/devices/{deviceId}", "/v1/account/bindings/{provider}"} {
		pathItem := document.Paths.Find(path)
		if pathItem == nil || pathItem.Delete == nil {
			t.Fatalf("missing DELETE %s contract", path)
		}
	}
	deletionPath := document.Paths.Find("/v1/account/deletion-requests")
	if deletionPath == nil || deletionPath.Post == nil {
		t.Fatal("missing POST /v1/account/deletion-requests contract")
	}
	for _, path := range []string{
		"/v1/vault/sync/push",
		"/v1/vault/assets/uploads",
		"/v1/vault/assets/{assetId}/complete",
	} {
		pathItem := document.Paths.Find(path)
		if pathItem == nil || pathItem.Post == nil {
			t.Fatalf("missing POST %s contract", path)
		}
	}
	for _, path := range []string{
		"/v1/vault/sync/pull",
		"/v1/vault/assets/{assetId}/download",
	} {
		pathItem := document.Paths.Find(path)
		if pathItem == nil || pathItem.Get == nil {
			t.Fatalf("missing GET %s contract", path)
		}
	}
	for _, path := range []string{
		"/v1/vault/migrations",
		"/v1/vault/migrations/{migrationId}/entries",
		"/v1/vault/migrations/{migrationId}/assets",
		"/v1/vault/migrations/{migrationId}/verify",
	} {
		pathItem := document.Paths.Find(path)
		if pathItem == nil || pathItem.Post == nil {
			t.Fatalf("missing POST %s contract", path)
		}
		for _, status := range []string{"401", "422", "503"} {
			if pathItem.Post.Responses.Value(status) == nil {
				t.Fatalf("missing POST %s response %s", path, status)
			}
		}
	}
	migrationReport := document.Paths.Find("/v1/vault/migrations/{migrationId}/report")
	if migrationReport == nil || migrationReport.Get == nil {
		t.Fatal("missing GET migration report contract")
	}
	for schemaName, properties := range map[string][]string{
		"MigrationResponse":   {"deleted_count"},
		"MigrationReport":     {"expected_deleted_entries", "imported_deleted_entries"},
		"AssetUploadResponse": {"status"},
	} {
		schema := document.Components.Schemas[schemaName].Value
		for _, property := range properties {
			if schema == nil || schema.Properties[property] == nil {
				t.Fatalf("missing %s.%s", schemaName, property)
			}
		}
	}
}
