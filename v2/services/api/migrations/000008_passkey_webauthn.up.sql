CREATE TABLE webauthn_users (
    account_id UUID PRIMARY KEY REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    user_handle BYTEA NOT NULL UNIQUE CHECK (
        octet_length(user_handle) BETWEEN 32 AND 64
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE passkeys
    ADD COLUMN credential_key_version INTEGER,
    ADD COLUMN credential_record_nonce BYTEA,
    ADD COLUMN credential_record_ciphertext BYTEA;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM passkeys) THEN
        RAISE EXCEPTION 'existing passkeys require encrypted credential-record backfill';
    END IF;
END
$$;

ALTER TABLE passkeys
    ALTER COLUMN credential_key_version SET NOT NULL,
    ALTER COLUMN credential_record_nonce SET NOT NULL,
    ALTER COLUMN credential_record_ciphertext SET NOT NULL,
    ADD CONSTRAINT passkeys_credential_key_version_check CHECK (credential_key_version > 0),
    ADD CONSTRAINT passkeys_credential_record_nonce_check CHECK (
        octet_length(credential_record_nonce) = 12
    ),
    ADD CONSTRAINT passkeys_credential_record_ciphertext_check CHECK (
        octet_length(credential_record_ciphertext) > 16
    );

CREATE TABLE passkey_challenges (
    id UUID PRIMARY KEY,
    purpose TEXT NOT NULL CHECK (purpose IN ('registration', 'login')),
    account_id UUID REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
    session_data BYTEA NOT NULL CHECK (octet_length(session_data) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    CONSTRAINT passkey_challenges_owner_check CHECK (
        (purpose = 'login' AND account_id IS NULL AND session_id IS NULL)
        OR (purpose = 'registration' AND account_id IS NOT NULL AND session_id IS NOT NULL)
    ),
    CONSTRAINT passkey_challenges_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT passkey_challenges_used_at_check CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE INDEX passkey_challenges_active_expiry_idx
    ON passkey_challenges(expires_at)
    WHERE used_at IS NULL;
