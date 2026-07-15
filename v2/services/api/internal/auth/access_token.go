package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

var ErrInvalidAccessToken = errors.New("invalid access token")

type AccessClaims struct {
	AccountID       string
	VaultID         string
	SessionID       string
	DeviceID        string
	IssuedAt        time.Time
	AuthenticatedAt time.Time
}

type accessTokenPayload struct {
	Issuer          string `json:"iss"`
	Subject         string `json:"sub"`
	VaultID         string `json:"vault_id"`
	SessionID       string `json:"sid"`
	DeviceID        string `json:"device_id"`
	IssuedAt        int64  `json:"iat"`
	AuthenticatedAt int64  `json:"auth_time"`
	ExpiresAt       int64  `json:"exp"`
}

type AccessTokenSigner struct {
	issuer string
	secret []byte
}

func NewAccessTokenSigner(issuer string, secret []byte) (*AccessTokenSigner, error) {
	if strings.TrimSpace(issuer) == "" {
		return nil, fmt.Errorf("access token issuer is required")
	}
	if len(secret) < 32 {
		return nil, fmt.Errorf("access token signing key must contain at least 32 bytes")
	}
	return &AccessTokenSigner{issuer: issuer, secret: append([]byte(nil), secret...)}, nil
}

func (signer *AccessTokenSigner) Sign(claims AccessClaims, now time.Time, lifetime time.Duration) (string, error) {
	header, err := encodeTokenPart(map[string]string{"alg": "HS256", "typ": "JWT"})
	if err != nil {
		return "", err
	}
	payload, err := encodeTokenPart(accessTokenPayload{
		Issuer:          signer.issuer,
		Subject:         claims.AccountID,
		VaultID:         claims.VaultID,
		SessionID:       claims.SessionID,
		DeviceID:        claims.DeviceID,
		IssuedAt:        now.Unix(),
		AuthenticatedAt: claims.AuthenticatedAt.Unix(),
		ExpiresAt:       now.Add(lifetime).Unix(),
	})
	if err != nil {
		return "", err
	}
	unsigned := header + "." + payload
	return unsigned + "." + signer.signature(unsigned), nil
}

func (signer *AccessTokenSigner) Verify(token string, now time.Time) (AccessClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	unsigned := parts[0] + "." + parts[1]
	if !hmac.Equal([]byte(parts[2]), []byte(signer.signature(unsigned))) {
		return AccessClaims{}, ErrInvalidAccessToken
	}

	var header map[string]string
	if err := decodeTokenPart(parts[0], &header); err != nil || header["alg"] != "HS256" || header["typ"] != "JWT" {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	var payload accessTokenPayload
	if err := decodeTokenPart(parts[1], &payload); err != nil {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	if payload.Issuer != signer.issuer || payload.Subject == "" || payload.VaultID == "" ||
		payload.SessionID == "" || payload.DeviceID == "" || payload.ExpiresAt <= now.Unix() ||
		payload.IssuedAt > now.Add(time.Minute).Unix() || payload.AuthenticatedAt <= 0 ||
		payload.AuthenticatedAt > payload.IssuedAt+int64(time.Minute.Seconds()) {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	return AccessClaims{
		AccountID:       payload.Subject,
		VaultID:         payload.VaultID,
		SessionID:       payload.SessionID,
		DeviceID:        payload.DeviceID,
		IssuedAt:        time.Unix(payload.IssuedAt, 0).UTC(),
		AuthenticatedAt: time.Unix(payload.AuthenticatedAt, 0).UTC(),
	}, nil
}

func (signer *AccessTokenSigner) signature(unsigned string) string {
	mac := hmac.New(sha256.New, signer.secret)
	_, _ = mac.Write([]byte(unsigned))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func encodeTokenPart(value any) (string, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return "", fmt.Errorf("encode access token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(encoded), nil
}

func decodeTokenPart(encoded string, destination any) error {
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return err
	}
	return json.Unmarshal(decoded, destination)
}
