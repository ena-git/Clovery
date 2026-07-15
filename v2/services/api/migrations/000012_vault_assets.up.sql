CREATE TABLE vault_assets (
    id UUID PRIMARY KEY,
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL UNIQUE CHECK (length(object_key) > 0),
    content_type TEXT NOT NULL CHECK (
        content_type IN ('image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp')
    ),
    byte_size BIGINT NOT NULL CHECK (byte_size > 0 AND byte_size <= 52428800),
    sha256 TEXT NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
    status TEXT NOT NULL CHECK (status IN ('pending', 'complete')),
    created_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    CONSTRAINT vault_assets_completion_check CHECK (
        (status = 'pending' AND completed_at IS NULL)
        OR (status = 'complete' AND completed_at IS NOT NULL)
    )
);

CREATE INDEX vault_assets_vault_created_idx ON vault_assets(vault_id, created_at DESC);
