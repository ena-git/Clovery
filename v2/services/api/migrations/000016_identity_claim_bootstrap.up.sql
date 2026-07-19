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
    CHECK ((consumed_at IS NULL) = (consumed_by_account_id IS NULL)),
    CHECK ((consumed_at IS NULL) = (registration_request_id IS NULL))
);

CREATE INDEX identity_claims_expires_at_idx
    ON identity_claims (expires_at)
    WHERE consumed_at IS NULL;

CREATE INDEX identity_claims_identity_idx
    ON identity_claims (provider, issuer, subject);

CREATE TABLE account_bootstrap_jobs (
    account_id UUID PRIMARY KEY REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    vault_id UUID NOT NULL UNIQUE REFERENCES vaults(id) ON DELETE CASCADE,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('legacy_local', 'legacy_cloudkit', 'new_install')),
    migration_id UUID REFERENCES vault_migrations(id) ON DELETE SET NULL,
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
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
