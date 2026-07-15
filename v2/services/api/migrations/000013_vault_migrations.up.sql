CREATE TABLE vault_migrations (
    id UUID PRIMARY KEY,
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    format_version INTEGER NOT NULL CHECK (format_version = 1),
    source TEXT NOT NULL CHECK (source IN ('v1_bundle', 'legacy_cloudkit')),
	expected_entry_count INTEGER NOT NULL CHECK (expected_entry_count >= 0),
	expected_deleted_count INTEGER NOT NULL CHECK (expected_deleted_count >= 0),
    expected_asset_count INTEGER NOT NULL CHECK (expected_asset_count >= 0),
    expected_total_bytes BIGINT NOT NULL CHECK (expected_total_bytes >= 0),
	manifest_sha256 TEXT NOT NULL CHECK (manifest_sha256 ~ '^[a-f0-9]{64}$'),
	manifest JSONB NOT NULL CHECK (jsonb_typeof(manifest) = 'object'),
	manifest_bytes BYTEA NOT NULL CHECK (octet_length(manifest_bytes) > 0),
    status TEXT NOT NULL CHECK (status IN ('uploading', 'verified', 'failed')),
    last_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ
);

CREATE INDEX vault_migrations_vault_created_idx ON vault_migrations(vault_id, created_at DESC);

CREATE TABLE migration_entries (
    migration_id UUID NOT NULL REFERENCES vault_migrations(id) ON DELETE CASCADE,
    entry_id UUID NOT NULL,
    operation_id UUID NOT NULL UNIQUE,
    payload JSONB NOT NULL,
    deleted_at TIMESTAMPTZ,
    sha256 TEXT NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
    byte_size BIGINT NOT NULL CHECK (byte_size > 0),
    PRIMARY KEY (migration_id, entry_id)
);

CREATE TABLE migration_assets (
	migration_id UUID NOT NULL REFERENCES vault_migrations(id) ON DELETE CASCADE,
	asset_id UUID NOT NULL REFERENCES vault_assets(id) ON DELETE RESTRICT,
	source_filename TEXT NOT NULL,
    byte_size BIGINT NOT NULL CHECK (byte_size > 0),
    sha256 TEXT NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
	PRIMARY KEY (migration_id, source_filename),
	UNIQUE (migration_id, asset_id)
);

ALTER TABLE journal_entries
    ADD COLUMN imported_by_migration_id UUID REFERENCES vault_migrations(id) ON DELETE SET NULL;
