package contract_test

import (
	"reflect"
	"testing"
)

func TestAccountBootstrapRoutesExposeResumableStateContract(t *testing.T) {
	document := loadIdentityClaimOpenAPI(t)
	getPath := document.Paths.Find("/v1/account/bootstrap")
	resumePath := document.Paths.Find("/v1/account/bootstrap/resume")
	if getPath == nil || getPath.Get == nil || resumePath == nil || resumePath.Post == nil {
		t.Fatal("missing account bootstrap GET or resume POST contract")
	}
	for name, operation := range map[string]struct {
		responseRef string
		actualRef   string
	}{
		"get": {
			responseRef: "#/components/schemas/AccountBootstrapResponse",
			actualRef:   getPath.Get.Responses.Value("200").Value.Content["application/json"].Schema.Ref,
		},
		"resume": {
			responseRef: "#/components/schemas/AccountBootstrapResponse",
			actualRef:   resumePath.Post.Responses.Value("200").Value.Content["application/json"].Schema.Ref,
		},
	} {
		if operation.actualRef != operation.responseRef {
			t.Errorf("%s bootstrap response schema = %q", name, operation.actualRef)
		}
	}
	if resumePath.Post.RequestBody == nil || resumePath.Post.RequestBody.Value == nil ||
		resumePath.Post.RequestBody.Value.Content["application/json"].Schema.Ref !=
			"#/components/schemas/AccountBootstrapResumeRequest" {
		t.Fatal("resume request must use AccountBootstrapResumeRequest")
	}
	if conflict := resumePath.Post.Responses.Value("409"); conflict == nil || conflict.Value == nil {
		t.Fatal("resume must document bootstrap_conflict 409 responses")
	}

	response := document.Components.Schemas["AccountBootstrapResponse"].Value
	for _, required := range []string{
		"status", "source_kind", "migration_id", "stages", "last_error_code", "retry_count", "updated_at",
	} {
		if !containsString(response.Required, required) {
			t.Errorf("bootstrap response must require %s", required)
		}
	}
	for _, forbidden := range []string{"account_id", "vault_id", "identity_state"} {
		if _, found := response.Properties[forbidden]; found {
			t.Errorf("bootstrap response must not expose %s", forbidden)
		}
	}
	stages := requireSchemaProperty(t, response, "stages")
	for _, stage := range []string{"identity", "migration", "entitlement", "vault"} {
		property := requireSchemaProperty(t, stages, stage)
		if !reflect.DeepEqual(property.Enum, []any{"pending", "complete", "needs_attention"}) {
			t.Errorf("%s stage enum = %#v", stage, property.Enum)
		}
	}
}
