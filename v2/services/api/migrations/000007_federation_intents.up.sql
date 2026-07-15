CREATE TABLE federation_intents (
    id UUID PRIMARY KEY,
    purpose TEXT NOT NULL CHECK (purpose IN ('login', 'binding')),
    account_id UUID REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('apple', 'google', 'huawei', 'wechat', 'qq')),
    nonce_hash BYTEA NOT NULL CHECK (octet_length(nonce_hash) = 32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    CONSTRAINT federation_intents_owner_check CHECK (
        (purpose = 'login' AND account_id IS NULL AND session_id IS NULL)
        OR (purpose = 'binding' AND account_id IS NOT NULL AND session_id IS NOT NULL)
    ),
    CONSTRAINT federation_intents_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT federation_intents_used_at_check CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE INDEX federation_intents_active_expiry_idx
    ON federation_intents(expires_at)
    WHERE used_at IS NULL;
