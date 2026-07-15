package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
)

func newPasswordResetProof(randomSource io.Reader) (string, [sha256.Size]byte, error) {
	randomBytes := make([]byte, 32)
	if _, err := io.ReadFull(randomSource, randomBytes); err != nil {
		return "", [sha256.Size]byte{}, fmt.Errorf("generate password reset proof: %w", err)
	}
	proof := base64.RawURLEncoding.EncodeToString(randomBytes)
	return proof, hashPasswordResetProof(proof), nil
}

func hashPasswordResetProof(proof string) [sha256.Size]byte {
	return sha256.Sum256([]byte(proof))
}

var passwordResetRandomSource io.Reader = rand.Reader
