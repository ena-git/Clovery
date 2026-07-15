package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
)

func newRefreshToken(randomSource io.Reader) (string, [sha256.Size]byte, error) {
	randomBytes := make([]byte, 32)
	if _, err := io.ReadFull(randomSource, randomBytes); err != nil {
		return "", [sha256.Size]byte{}, fmt.Errorf("generate refresh token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(randomBytes)
	return token, hashRefreshToken(token), nil
}

func hashRefreshToken(token string) [sha256.Size]byte {
	return sha256.Sum256([]byte(token))
}

var sessionRandomSource io.Reader = rand.Reader
