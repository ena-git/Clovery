package billing

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func (verifier *AppleVerifier) bearerToken() (string, error) {
	now := verifier.now().UTC()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss": verifier.issuerID,
		"iat": now.Unix(),
		"exp": now.Add(5 * time.Minute).Unix(),
		"aud": "appstoreconnect-v1",
		"bid": verifier.bundleID,
	})
	token.Header["kid"] = verifier.keyID
	token.Header["typ"] = "JWT"
	encoded, err := token.SignedString(verifier.privateKey)
	if err != nil {
		return "", fmt.Errorf("sign Apple API bearer token: %w", err)
	}
	return encoded, nil
}
