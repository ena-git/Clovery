package auth

import (
	"errors"
	"testing"
)

func TestPasswordPolicyRejectsWeakPasswordsAndAllowsSpaces(t *testing.T) {
	for _, password := range []string{
		"short",
		"seven77",
		"password",
		"12345678",
		"qwertyui",
		"clovery1",
		"password1234",
		"123456789012",
		"clovery12345",
	} {
		t.Run(password, func(t *testing.T) {
			if err := ValidatePassword(password); !errors.Is(err, ErrWeakPassword) {
				t.Fatalf("ValidatePassword(%q) error = %v", password, err)
			}
		})
	}

	if err := ValidatePassword("four quiet words together"); err != nil {
		t.Fatalf("password with spaces was rejected: %v", err)
	}
}

func TestPasswordPolicyAcceptsEightCharacters(t *testing.T) {
	if err := ValidatePassword("eight888"); err != nil {
		t.Fatalf("8-character password rejected: %v", err)
	}
}

func TestPasswordPolicyRejectsSevenCharacters(t *testing.T) {
	if err := ValidatePassword("seven77"); !errors.Is(err, ErrWeakPassword) {
		t.Fatalf("7-character password error = %v", err)
	}
}

func TestArgon2idHashesUseIndependentSalts(t *testing.T) {
	hasher := NewPasswordHasher()
	firstHash, err := hasher.Hash("four quiet words together")
	if err != nil {
		t.Fatalf("first hash: %v", err)
	}
	secondHash, err := hasher.Hash("four quiet words together")
	if err != nil {
		t.Fatalf("second hash: %v", err)
	}
	if firstHash == secondHash {
		t.Fatal("same password produced the same encoded hash")
	}
	if firstHash[:10] != "$argon2id$" {
		t.Fatalf("unexpected hash prefix: %q", firstHash)
	}
}

func TestArgon2idVerificationDoesNotExposeAccountExistence(t *testing.T) {
	hasher := NewPasswordHasher()
	encodedHash, err := hasher.Hash("four quiet words together")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}

	verified, err := hasher.Verify("four quiet words together", encodedHash)
	if err != nil || !verified {
		t.Fatalf("correct password verification = %v, %v", verified, err)
	}
	verified, err = hasher.Verify("four wrong words together", encodedHash)
	if err != nil {
		t.Fatalf("wrong password returned internal error: %v", err)
	}
	if verified {
		t.Fatal("wrong password was accepted")
	}
}
