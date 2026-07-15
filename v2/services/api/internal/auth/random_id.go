package auth

import (
	"fmt"
	"io"
)

func randomUUID(randomSource io.Reader) (string, error) {
	randomBytes := make([]byte, 16)
	if _, err := io.ReadFull(randomSource, randomBytes); err != nil {
		return "", err
	}
	randomBytes[6] = (randomBytes[6] & 0x0f) | 0x40
	randomBytes[8] = (randomBytes[8] & 0x3f) | 0x80
	return fmt.Sprintf(
		"%x-%x-%x-%x-%x",
		randomBytes[0:4],
		randomBytes[4:6],
		randomBytes[6:8],
		randomBytes[8:10],
		randomBytes[10:16],
	), nil
}
