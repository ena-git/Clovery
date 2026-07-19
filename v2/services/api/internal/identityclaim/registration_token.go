package identityclaim

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"strconv"
)

type RegistrationToken struct {
	raw string
}

func ParseRegistrationToken(rawToken string) (RegistrationToken, error) {
	if !canonicalRegistrationToken(rawToken) {
		return RegistrationToken{}, ErrInvalidClaim
	}
	return RegistrationToken{raw: rawToken}, nil
}

func (token RegistrationToken) Valid() bool {
	return canonicalRegistrationToken(token.raw)
}

func (token RegistrationToken) Format(state fmt.State, verb rune) {
	formatted := "RegistrationToken(<redacted>)"
	if verb == 'q' {
		formatted = strconv.Quote(formatted)
	}
	_, _ = io.WriteString(state, formatted)
}

func (token RegistrationToken) GoString() string {
	return "identityclaim.RegistrationToken(<redacted>)"
}

func (token RegistrationToken) LogValue() slog.Value {
	return slog.StringValue("<redacted>")
}

func (token RegistrationToken) MarshalJSON() ([]byte, error) {
	return json.Marshal("<redacted>")
}

func (token *RegistrationToken) UnmarshalJSON(data []byte) error {
	if token == nil {
		return ErrInvalidClaim
	}
	var rawToken string
	if err := json.Unmarshal(data, &rawToken); err != nil {
		return ErrInvalidClaim
	}
	parsed, err := ParseRegistrationToken(rawToken)
	if err != nil {
		return err
	}
	*token = parsed
	return nil
}

func (token RegistrationToken) digest() (string, error) {
	return parseTokenDigest(token.raw)
}

func canonicalRegistrationToken(rawToken string) bool {
	decoded, err := base64.RawURLEncoding.DecodeString(rawToken)
	return err == nil && len(decoded) == tokenByteLength &&
		base64.RawURLEncoding.EncodeToString(decoded) == rawToken
}
