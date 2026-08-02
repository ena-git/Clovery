CREATE TABLE identity_claims (
    id UUID PRIMARY KEY,
    token_sha256 CHAR(64) NOT NULL UNIQUE,
    provider TEXT NOT NULL CHECK (provider IN ('apple', 'google', 'huawei')),
    issuer TEXT NOT NULL,
    subject TEXT NOT NULL,
    login_intent_id UUID NOT NULL UNIQUE REFERENCES federation_intents(id) ON DELETE RESTRICT,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    consumed_by_account_id UUID REFERENCES clovery_accounts(id) ON DELETE RESTRICT,
    registration_request_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT identity_claims_token_sha256_format_check
        CHECK (token_sha256 ~ '^[a-f0-9]{64}$'),
    CHECK ((consumed_at IS NULL) = (consumed_by_account_id IS NULL)),
    CHECK ((consumed_at IS NULL) = (registration_request_id IS NULL))
);

CREATE INDEX identity_claims_expires_at_idx
    ON identity_claims (expires_at)
    WHERE consumed_at IS NULL;

CREATE INDEX identity_claims_identity_idx
    ON identity_claims (provider, issuer, subject);

ALTER TABLE vaults
    ADD CONSTRAINT vaults_id_owner_account_id_key UNIQUE (id, owner_account_id);

ALTER TABLE vault_migrations
    ADD CONSTRAINT vault_migrations_id_vault_id_key UNIQUE (id, vault_id);

CREATE TABLE account_bootstrap_jobs (
    account_id UUID PRIMARY KEY REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    vault_id UUID NOT NULL UNIQUE REFERENCES vaults(id) ON DELETE CASCADE,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('legacy_local', 'legacy_cloudkit', 'new_install')),
    migration_id UUID,
    identity_state TEXT NOT NULL DEFAULT 'complete'
        CHECK (identity_state IN ('pending', 'complete', 'needs_attention')),
    migration_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (migration_state IN ('pending', 'complete', 'needs_attention')),
    entitlement_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (entitlement_state IN ('pending', 'complete', 'needs_attention')),
    vault_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (vault_state IN ('pending', 'complete', 'needs_attention')),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'running', 'needs_attention', 'complete')),
    last_error_code TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT account_bootstrap_jobs_vault_owner_fkey
        FOREIGN KEY (vault_id, account_id)
        REFERENCES vaults(id, owner_account_id) ON DELETE CASCADE,
    CONSTRAINT account_bootstrap_jobs_migration_vault_fkey
        FOREIGN KEY (migration_id, vault_id)
        REFERENCES vault_migrations(id, vault_id) ON DELETE SET NULL (migration_id),
    CONSTRAINT account_bootstrap_jobs_complete_state_check CHECK (
        status <> 'complete'
        OR (
            identity_state = 'complete'
            AND migration_state = 'complete'
            AND entitlement_state = 'complete'
            AND vault_state = 'complete'
        )
    ),
    CONSTRAINT account_bootstrap_jobs_attention_state_check CHECK (
        (
            status <> 'needs_attention'
            OR identity_state = 'needs_attention'
            OR migration_state = 'needs_attention'
            OR entitlement_state = 'needs_attention'
            OR vault_state = 'needs_attention'
        )
        AND (
            status IN ('needs_attention', 'running')
            OR NOT (
                identity_state = 'needs_attention'
                OR migration_state = 'needs_attention'
                OR entitlement_state = 'needs_attention'
                OR vault_state = 'needs_attention'
            )
        )
    ),
    CONSTRAINT account_bootstrap_jobs_attention_error_check CHECK (
        status <> 'needs_attention'
        OR (
            last_error_code IS NOT NULL
            AND last_error_code ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$'
        )
    )
);
