CREATE TABLE password_reset_intents (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    recovery_method TEXT NOT NULL CHECK (recovery_method IN ('recovery_code', 'passkey', 'recovery_email')),
    proof_hash BYTEA NOT NULL CHECK (octet_length(proof_hash) = 32),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    consumed_at TIMESTAMPTZ
);

CREATE INDEX password_reset_intents_account_id_idx ON password_reset_intents(account_id);
CREATE INDEX password_reset_intents_expires_at_idx ON password_reset_intents(expires_at);
