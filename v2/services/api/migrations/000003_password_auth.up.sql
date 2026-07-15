CREATE TABLE password_credentials (
    account_id UUID PRIMARY KEY REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    password_hash TEXT NOT NULL CHECK (password_hash LIKE '$argon2id$%'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE auth_rate_limits (
    scope TEXT NOT NULL CHECK (length(scope) > 0),
    key_hash BYTEA NOT NULL CHECK (octet_length(key_hash) = 32),
    failed_count INTEGER NOT NULL DEFAULT 0 CHECK (failed_count >= 0),
    window_started_at TIMESTAMPTZ NOT NULL,
    blocked_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (scope, key_hash)
);

CREATE INDEX auth_rate_limits_blocked_until_idx
    ON auth_rate_limits(blocked_until)
    WHERE blocked_until IS NOT NULL;
