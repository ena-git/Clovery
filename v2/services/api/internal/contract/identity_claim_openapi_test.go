package contract_test

import (
	"path/filepath"
	"runtime"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
)

func TestIdentityClaimTokenVisibilityContract(t *testing.T) {
	document := loadIdentityClaimOpenAPI(t)

	responseSchema := document.Components.Schemas["IdentityClaimRequiredResponse"].Value
	responseToken := responseSchema.Properties["identity_claim_token"].Value
	if responseToken.WriteOnly {
		t.Fatal("IdentityClaimRequiredResponse.identity_claim_token must not be write-only")
	}

	requestSchema := document.Components.Schemas["CreateAccountRequest"].Value
	requestToken := requestSchema.Properties["identity_claim_token"].Value
	if !requestToken.WriteOnly {
		t.Fatal("CreateAccountRequest.identity_claim_token must remain write-only")
	}
}

func loadIdentityClaimOpenAPI(t *testing.T) *openapi3.T {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve identity claim OpenAPI test path")
	}
	path := filepath.Join(filepath.Dir(currentFile), "..", "..", "..", "..", "contracts", "openapi", "openapi.yaml")
	document, err := openapi3.NewLoader().LoadFromFile(path)
	if err != nil {
		t.Fatalf("load OpenAPI contract: %v", err)
	}
	return document
}
