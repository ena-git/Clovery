CREATE TABLE clovery_accounts (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE account_login_ids (
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    normalized_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'retired')),
    reserved_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    retired_at TIMESTAMPTZ,
    CONSTRAINT account_login_ids_normalized_id_key UNIQUE (normalized_id),
    CONSTRAINT account_login_ids_normalized_format_check CHECK (
        normalized_id = lower(normalized_id)
        AND normalized_id ~ '^[a-z][a-z0-9_]{3,23}$'
    ),
    CONSTRAINT account_login_ids_reserved_word_check CHECK (
        normalized_id NOT IN (
            'admin', 'administrator', 'api', 'clovery', 'help', 'root',
            'security', 'support', 'system'
        )
    ),
    CONSTRAINT account_login_ids_status_timestamps_check CHECK (
        (status = 'active' AND retired_at IS NULL)
        OR (status = 'retired' AND retired_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX account_login_ids_one_active_per_account
    ON account_login_ids(account_id)
    WHERE status = 'active';

CREATE TABLE vaults (
    id UUID PRIMARY KEY,
    owner_account_id UUID NOT NULL UNIQUE REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('active', 'locked', 'deleting', 'deleted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE external_identities (
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (length(provider) > 0),
    issuer TEXT NOT NULL CHECK (length(issuer) > 0),
    subject TEXT NOT NULL CHECK (length(subject) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT external_identities_provider_subject_key UNIQUE (provider, issuer, subject)
);

CREATE INDEX external_identities_account_id_idx ON external_identities(account_id);

CREATE TABLE devices (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL DEFAULT '',
    platform TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX devices_account_id_idx ON devices(account_id);

CREATE TABLE sessions (
    id UUID PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    refresh_token_hash BYTEA NOT NULL CHECK (octet_length(refresh_token_hash) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX sessions_device_id_idx ON sessions(device_id);

CREATE TABLE passkeys (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    credential_id BYTEA NOT NULL UNIQUE,
    public_key BYTEA NOT NULL,
    sign_counter BIGINT NOT NULL DEFAULT 0 CHECK (sign_counter >= 0),
    device_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX passkeys_account_id_idx ON passkeys(account_id);

CREATE TABLE recovery_codes (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    code_hash BYTEA NOT NULL CHECK (octet_length(code_hash) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used_at TIMESTAMPTZ,
    CONSTRAINT recovery_codes_account_hash_key UNIQUE (account_id, code_hash)
);

CREATE INDEX recovery_codes_account_id_idx ON recovery_codes(account_id);

CREATE TABLE audit_events (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (length(event_type) > 0),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX audit_events_account_created_at_idx ON audit_events(account_id, created_at DESC);
