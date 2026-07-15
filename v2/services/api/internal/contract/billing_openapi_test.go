package contract_test

import (
	"path/filepath"
	"runtime"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
)

func TestOpenAPIContainsAccountScopedBillingContracts(t *testing.T) {
	document := loadBillingOpenAPI(t)
	verify := document.Paths.Find("/v1/billing/apple/transactions/verify")
	restore := document.Paths.Find("/v1/billing/apple/restore")
	legacyClaim := document.Paths.Find("/v1/billing/apple/legacy-claims")
	notifications := document.Paths.Find("/v1/billing/apple/notifications")
	entitlements := document.Paths.Find("/v1/account/entitlements")
	if verify == nil || verify.Post == nil || restore == nil || restore.Post == nil ||
		legacyClaim == nil || legacyClaim.Post == nil ||
		notifications == nil || notifications.Post == nil ||
		entitlements == nil || entitlements.Get == nil {
		t.Fatal("billing paths are incomplete")
	}
	notificationSchema := notifications.Post.RequestBody.Value.Content["application/json"].Schema.Value
	if len(notificationSchema.Properties) != 1 || notificationSchema.Properties["signedPayload"] == nil {
		t.Fatalf("notification request properties = %#v", notificationSchema.Properties)
	}
	if notifications.Post.Security != nil {
		t.Fatal("Apple server notification endpoint must not require a user bearer token")
	}
	verifySchema := verify.Post.RequestBody.Value.Content["application/json"].Schema.Value
	if len(verifySchema.Properties) != 2 || verifySchema.Properties["transaction_id"] == nil ||
		verifySchema.Properties["environment"] == nil || verifySchema.Properties["account_id"] != nil {
		t.Fatalf("verify request properties = %#v", verifySchema.Properties)
	}
	restoreSchema := restore.Post.RequestBody.Value.Content["application/json"].Schema.Value
	if len(restoreSchema.Properties) != 2 || restoreSchema.Properties["transaction_ids"] == nil ||
		restoreSchema.Properties["environment"] == nil || restoreSchema.Properties["account_id"] != nil {
		t.Fatalf("restore request properties = %#v", restoreSchema.Properties)
	}
	legacySchema := legacyClaim.Post.RequestBody.Value.Content["application/json"].Schema.Value
	if len(legacySchema.Properties) != 2 || legacySchema.Properties["signed_transaction_info"] == nil ||
		legacySchema.Properties["environment"] == nil || legacySchema.Properties["account_id"] != nil {
		t.Fatalf("legacy claim request properties = %#v", legacySchema.Properties)
	}
	for _, status := range []string{"400", "403", "409", "422", "503"} {
		if verify.Post.Responses.Value(status) == nil {
			t.Fatalf("verify response %s is missing", status)
		}
	}
}

func loadBillingOpenAPI(t *testing.T) *openapi3.T {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve billing OpenAPI test path")
	}
	path := filepath.Join(filepath.Dir(currentFile), "..", "..", "..", "..", "contracts", "openapi", "openapi.yaml")
	document, err := openapi3.NewLoader().LoadFromFile(path)
	if err != nil {
		t.Fatalf("load OpenAPI contract: %v", err)
	}
	return document
}
