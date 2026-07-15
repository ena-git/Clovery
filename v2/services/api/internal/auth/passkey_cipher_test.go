package auth

import (
	"bytes"
	"testing"
)

func TestPasskeyCredentialCipherBindsCiphertextToAccountAndCredential(t *testing.T) {
	cipher, err := NewPasskeyCredentialCipher([]byte("0123456789abcdef0123456789abcdef"))
	if err != nil {
		t.Fatalf("create passkey credential cipher: %v", err)
	}
	plaintext := []byte(`{"id":"credential-record"}`)
	accountID := "11111111-1111-4111-8111-111111111111"
	credentialID := []byte("credential-id")

	encrypted, err := cipher.Encrypt(accountID, credentialID, plaintext)
	if err != nil {
		t.Fatalf("encrypt passkey credential: %v", err)
	}
	if bytes.Contains(encrypted.Ciphertext, plaintext) {
		t.Fatal("passkey credential remained visible in ciphertext")
	}
	decrypted, err := cipher.Decrypt(accountID, credentialID, encrypted)
	if err != nil {
		t.Fatalf("decrypt passkey credential: %v", err)
	}
	if !bytes.Equal(decrypted, plaintext) {
		t.Fatalf("decrypted credential = %q", decrypted)
	}
	if _, err := cipher.Decrypt("22222222-2222-4222-8222-222222222222", credentialID, encrypted); err == nil {
		t.Fatal("cipher accepted passkey credential under another account")
	}
}
