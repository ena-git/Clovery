package auth

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"fmt"
	"io"
)

const passkeyCredentialKeyVersion = 1

type EncryptedPasskeyCredential struct {
	KeyVersion int
	Nonce      []byte
	Ciphertext []byte
}

type PasskeyCredentialCipher struct {
	aead   cipher.AEAD
	random io.Reader
}

func NewPasskeyCredentialCipher(key []byte) (*PasskeyCredentialCipher, error) {
	if len(key) != 32 {
		return nil, fmt.Errorf("passkey credential encryption key must contain exactly 32 bytes")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create passkey credential cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create passkey credential AEAD: %w", err)
	}
	return &PasskeyCredentialCipher{aead: aead, random: rand.Reader}, nil
}

func (credentialCipher *PasskeyCredentialCipher) Encrypt(
	accountID string,
	credentialID []byte,
	plaintext []byte,
) (EncryptedPasskeyCredential, error) {
	nonce := make([]byte, credentialCipher.aead.NonceSize())
	if _, err := io.ReadFull(credentialCipher.random, nonce); err != nil {
		return EncryptedPasskeyCredential{}, fmt.Errorf("generate passkey credential nonce: %w", err)
	}
	ciphertext := credentialCipher.aead.Seal(
		nil,
		nonce,
		plaintext,
		passkeyCredentialAdditionalData(accountID, credentialID),
	)
	return EncryptedPasskeyCredential{
		KeyVersion: passkeyCredentialKeyVersion,
		Nonce:      nonce,
		Ciphertext: ciphertext,
	}, nil
}

func (credentialCipher *PasskeyCredentialCipher) Decrypt(
	accountID string,
	credentialID []byte,
	encrypted EncryptedPasskeyCredential,
) ([]byte, error) {
	if encrypted.KeyVersion != passkeyCredentialKeyVersion {
		return nil, fmt.Errorf("unsupported passkey credential key version")
	}
	plaintext, err := credentialCipher.aead.Open(
		nil,
		encrypted.Nonce,
		encrypted.Ciphertext,
		passkeyCredentialAdditionalData(accountID, credentialID),
	)
	if err != nil {
		return nil, fmt.Errorf("decrypt passkey credential: %w", err)
	}
	return plaintext, nil
}

func passkeyCredentialAdditionalData(accountID string, credentialID []byte) []byte {
	additionalData := make([]byte, 0, len(accountID)+1+len(credentialID))
	additionalData = append(additionalData, accountID...)
	additionalData = append(additionalData, 0)
	return append(additionalData, credentialID...)
}
