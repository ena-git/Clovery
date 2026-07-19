package contract_test

import (
	"path/filepath"
	"reflect"
	"runtime"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
)

func TestIdentityClaimTokenVisibilityContract(t *testing.T) {
	document := loadIdentityClaimOpenAPI(t)

	completePath := document.Paths.Find("/v1/auth/federated/{provider}/complete")
	if completePath == nil || completePath.Post == nil {
		t.Fatal("missing federated completion POST contract")
	}
	accepted := completePath.Post.Responses.Value("202")
	if accepted == nil || accepted.Value == nil {
		t.Fatal("missing federated completion 202 response")
	}
	responseRef := accepted.Value.Content["application/json"].Schema
	if responseRef == nil || responseRef.Ref != "#/components/schemas/IdentityClaimRequiredResponse" {
		t.Fatalf("federated completion 202 schema = %#v", responseRef)
	}
	responseToken := requireSchemaProperty(t, responseRef.Value, "identity_claim_token")
	if responseToken.WriteOnly {
		t.Fatal("federated completion identity_claim_token must be output-visible")
	}
	provider := requireSchemaProperty(t, responseRef.Value, "provider")
	if !reflect.DeepEqual(provider.Enum, []any{"apple", "google", "huawei"}) {
		t.Errorf("identity claim providers = %#v", provider.Enum)
	}

	accountsPath := document.Paths.Find("/v1/auth/accounts")
	if accountsPath == nil || accountsPath.Post == nil || accountsPath.Post.RequestBody == nil ||
		accountsPath.Post.RequestBody.Value == nil {
		t.Fatal("missing account registration POST request contract")
	}
	requestRef := accountsPath.Post.RequestBody.Value.Content["application/json"].Schema
	if requestRef == nil || requestRef.Ref != "#/components/schemas/CreateAccountRequest" {
		t.Fatalf("account registration request schema = %#v", requestRef)
	}
	if len(requestRef.Value.OneOf) != 2 {
		t.Fatalf("CreateAccountRequest oneOf alternatives = %d", len(requestRef.Value.OneOf))
	}

	alternatives := make(map[string]*openapi3.Schema, len(requestRef.Value.OneOf))
	for _, alternative := range requestRef.Value.OneOf {
		alternatives[alternative.Ref] = alternative.Value
	}
	plain := alternatives["#/components/schemas/PlainCreateAccountRequest"]
	claim := alternatives["#/components/schemas/ClaimCreateAccountRequest"]
	if plain == nil || claim == nil {
		t.Fatalf("CreateAccountRequest alternatives = %#v", alternatives)
	}
	assertClosedRegistrationSchema(t, plain)
	assertClosedRegistrationSchema(t, claim)
	if !reflect.DeepEqual(requireSchemaProperty(t, plain, "recovery_method").Enum,
		[]any{"passkey", "recovery_email", "recovery_codes"}) {
		t.Fatal("plain registration must exclude bound_identity")
	}
	if recoveryMethod := requireSchemaProperty(t, claim, "recovery_method"); recoveryMethod.Const != "bound_identity" {
		t.Fatalf("claim recovery_method const = %#v", recoveryMethod.Const)
	}
	claimToken := requireSchemaProperty(t, claim, "identity_claim_token")
	if !claimToken.WriteOnly {
		t.Fatal("claim registration identity_claim_token must remain write-only")
	}
	for _, property := range []string{
		"login_id", "password", "recovery_method", "device",
		"identity_claim_token", "registration_request_id", "source_kind",
	} {
		if !containsString(claim.Required, property) {
			t.Errorf("ClaimCreateAccountRequest must require %s", property)
		}
	}
}

func assertClosedRegistrationSchema(t *testing.T, schema *openapi3.Schema) {
	t.Helper()
	if schema.AdditionalProperties.Has == nil || *schema.AdditionalProperties.Has {
		t.Fatal("registration alternative must set additionalProperties to false")
	}
	password := requireSchemaProperty(t, schema, "password")
	if password.MinLength != 8 || password.MaxLength == nil || *password.MaxLength != 256 {
		t.Fatalf("password length contract = %d..%v", password.MinLength, password.MaxLength)
	}
	device := schema.Properties["device"]
	if device == nil || device.Ref != "#/components/schemas/DeviceRegistration" {
		t.Fatal("registration alternative must preserve DeviceRegistration")
	}
}

func requireSchemaProperty(t *testing.T, schema *openapi3.Schema, name string) *openapi3.Schema {
	t.Helper()
	if schema == nil || schema.Properties[name] == nil || schema.Properties[name].Value == nil {
		t.Fatalf("missing schema property %s", name)
	}
	return schema.Properties[name].Value
}

func containsString(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
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
