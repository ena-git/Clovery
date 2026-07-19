package identityclaim

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
)

const tokenByteLength = 32

func newToken(randomSource io.Reader) (string, string, error) {
	randomBytes := make([]byte, tokenByteLength)
	if _, err := io.ReadFull(randomSource, randomBytes); err != nil {
		return "", "", fmt.Errorf("generate identity claim token: %w", err)
	}
	rawToken := base64.RawURLEncoding.EncodeToString(randomBytes)
	return rawToken, tokenSHA256(rawToken), nil
}

func tokenSHA256(rawToken string) string {
	digest := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(digest[:])
}

func parseTokenDigest(rawToken string) (string, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(rawToken)
	if err != nil || len(decoded) != tokenByteLength ||
		base64.RawURLEncoding.EncodeToString(decoded) != rawToken {
		return "", ErrInvalidClaim
	}
	return tokenSHA256(rawToken), nil
}
