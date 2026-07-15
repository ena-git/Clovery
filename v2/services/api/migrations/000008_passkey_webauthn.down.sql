DROP TABLE passkey_challenges;

ALTER TABLE passkeys
    DROP CONSTRAINT passkeys_credential_record_ciphertext_check,
    DROP CONSTRAINT passkeys_credential_record_nonce_check,
    DROP CONSTRAINT passkeys_credential_key_version_check,
    DROP COLUMN credential_record_ciphertext,
    DROP COLUMN credential_record_nonce,
    DROP COLUMN credential_key_version;

DROP TABLE webauthn_users;
