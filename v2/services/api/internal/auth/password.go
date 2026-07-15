package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
)

var (
	ErrInvalidPasswordHash = errors.New("invalid password hash")
	ErrWeakPassword        = errors.New("password does not meet the security policy")
)

type argon2Parameters struct {
	memory      uint32
	iterations  uint32
	parallelism uint8
	saltLength  uint32
	keyLength   uint32
}

type PasswordHasher struct {
	random io.Reader
	params argon2Parameters
}

var weakPasswords = map[string]struct{}{
	"123456789012": {},
	"clovery12345": {},
	"password1234": {},
	"qwertyuiop12": {},
}

func NewPasswordHasher() PasswordHasher {
	return PasswordHasher{
		random: rand.Reader,
		params: argon2Parameters{
			memory:      64 * 1024,
			iterations:  3,
			parallelism: 4,
			saltLength:  16,
			keyLength:   32,
		},
	}
}

func ValidatePassword(password string) error {
	passwordLength := utf8.RuneCountInString(password)
	if passwordLength < 12 || passwordLength > 256 {
		return ErrWeakPassword
	}
	if _, weak := weakPasswords[strings.ToLower(strings.TrimSpace(password))]; weak {
		return ErrWeakPassword
	}
	return nil
}

func (hasher PasswordHasher) Hash(password string) (string, error) {
	if err := ValidatePassword(password); err != nil {
		return "", err
	}

	salt := make([]byte, hasher.params.saltLength)
	if _, err := io.ReadFull(hasher.random, salt); err != nil {
		return "", fmt.Errorf("generate password salt: %w", err)
	}
	key := argon2.IDKey(
		[]byte(password),
		salt,
		hasher.params.iterations,
		hasher.params.memory,
		hasher.params.parallelism,
		hasher.params.keyLength,
	)

	return fmt.Sprintf(
		"$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version,
		hasher.params.memory,
		hasher.params.iterations,
		hasher.params.parallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

func (hasher PasswordHasher) Verify(password string, encodedHash string) (bool, error) {
	params, salt, expectedKey, err := parsePasswordHash(encodedHash)
	if err != nil {
		return false, err
	}
	actualKey := argon2.IDKey(
		[]byte(password),
		salt,
		params.iterations,
		params.memory,
		params.parallelism,
		uint32(len(expectedKey)),
	)
	return subtle.ConstantTimeCompare(actualKey, expectedKey) == 1, nil
}

func parsePasswordHash(encodedHash string) (argon2Parameters, []byte, []byte, error) {
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" {
		return argon2Parameters{}, nil, nil, ErrInvalidPasswordHash
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return argon2Parameters{}, nil, nil, ErrInvalidPasswordHash
	}
	params := argon2Parameters{}
	if _, err := fmt.Sscanf(
		parts[3],
		"m=%d,t=%d,p=%d",
		&params.memory,
		&params.iterations,
		&params.parallelism,
	); err != nil {
		return argon2Parameters{}, nil, nil, ErrInvalidPasswordHash
	}
	if params.memory < 8*1024 || params.memory > 256*1024 ||
		params.iterations == 0 || params.iterations > 10 ||
		params.parallelism == 0 || params.parallelism > 16 {
		return argon2Parameters{}, nil, nil, ErrInvalidPasswordHash
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil || len(salt) < 16 || len(salt) > 64 {
		return argon2Parameters{}, nil, nil, ErrInvalidPasswordHash
	}
	expectedKey, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil || len(expectedKey) < 16 || len(expectedKey) > 64 {
		return argon2Parameters{}, nil, nil, ErrInvalidPasswordHash
	}
	return params, salt, expectedKey, nil
}
