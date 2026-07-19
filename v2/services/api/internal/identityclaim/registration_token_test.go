package identityclaim

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"testing"
)

func TestRegistrationTokenAcceptsOnlyCanonicalBase64URL(t *testing.T) {
	rawToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0x6a}, tokenByteLength))
	token, err := ParseRegistrationToken(rawToken)
	if err != nil {
		t.Fatalf("ParseRegistrationToken() error = %v", err)
	}
	if _, err := json.Marshal(token); err != nil {
		t.Fatalf("marshal registration token: %v", err)
	}

	for _, malformed := range []string{
		"",
		"not-base64url",
		base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0x6a}, tokenByteLength-1)),
		base64.URLEncoding.EncodeToString(bytes.Repeat([]byte{0x6a}, tokenByteLength)),
	} {
		t.Run(fmt.Sprintf("length_%d", len(malformed)), func(t *testing.T) {
			if _, err := ParseRegistrationToken(malformed); !errors.Is(err, ErrInvalidClaim) {
				t.Fatalf("ParseRegistrationToken() error = %v, want ErrInvalidClaim", err)
			}
			var decoded RegistrationToken
			if err := json.Unmarshal([]byte(fmt.Sprintf("%q", malformed)), &decoded); !errors.Is(err, ErrInvalidClaim) {
				t.Fatalf("UnmarshalJSON() error = %v, want ErrInvalidClaim", err)
			}
		})
	}
}

func TestRegistrationTokenRedactsDirectNestedAndPointerRepresentations(t *testing.T) {
	rawToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0x6b}, tokenByteLength))
	token, err := ParseRegistrationToken(rawToken)
	if err != nil {
		t.Fatalf("ParseRegistrationToken() error = %v", err)
	}
	nested := struct {
		Token   RegistrationToken
		Pointer *RegistrationToken
	}{Token: token, Pointer: &token}

	values := []any{token, &token, nested, &nested}
	for _, value := range values {
		for _, format := range []string{"%v", "%+v", "%#v", "%q"} {
			assertRegistrationTokenRedacted(t, rawToken, fmt.Sprintf(format, value))
		}
		encoded, err := json.Marshal(value)
		if err != nil {
			t.Fatalf("marshal %T: %v", value, err)
		}
		assertRegistrationTokenRedacted(t, rawToken, string(encoded))
	}

	var logOutput bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logOutput, nil))
	logger.Info("registration tokens", "value", token, "pointer", &token, "nested", nested)
	assertRegistrationTokenRedacted(t, rawToken, logOutput.String())
	assertRegistrationTokenRedacted(t, rawToken, token.GoString())
	if _, implementsStringer := any(token).(fmt.Stringer); implementsStringer {
		t.Fatal("RegistrationToken implements fmt.Stringer")
	}
	if _, implementsStringer := any(&token).(fmt.Stringer); implementsStringer {
		t.Fatal("*RegistrationToken implements fmt.Stringer")
	}
}

func assertRegistrationTokenRedacted(t *testing.T, rawToken string, value string) {
	t.Helper()
	if strings.Contains(value, rawToken) || !containsRedaction(value) {
		t.Fatalf("registration token representation was not redacted: %q", value)
	}
}

func containsRedaction(value string) bool {
	return strings.Contains(value, "<redacted>") || strings.Contains(value, `\u003credacted\u003e`)
}

func mustParseRegistrationToken(t *testing.T, rawToken string) RegistrationToken {
	t.Helper()
	token, err := ParseRegistrationToken(rawToken)
	if err != nil {
		t.Fatalf("parse registration token: %v", err)
	}
	return token
}
