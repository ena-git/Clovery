CREATE TABLE journal_entries (
    id UUID NOT NULL,
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    revision BIGINT NOT NULL CHECK (revision > 0),
    payload JSONB NOT NULL,
    deleted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, vault_id)
);

CREATE TABLE sync_changes (
    cursor BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('journal_entry')),
    entity_id UUID NOT NULL,
    revision BIGINT NOT NULL CHECK (revision > 0),
    operation_id UUID NOT NULL UNIQUE,
    payload JSONB NOT NULL,
    deleted BOOLEAN NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX sync_changes_vault_cursor_idx ON sync_changes(vault_id, cursor);

CREATE TABLE sync_operations (
    operation_id UUID PRIMARY KEY,
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    request_hash BYTEA NOT NULL CHECK (octet_length(request_hash) = 32),
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX sync_operations_vault_created_idx ON sync_operations(vault_id, created_at DESC);

CREATE TABLE journal_conflicts (
    id UUID PRIMARY KEY,
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    entry_id UUID NOT NULL,
    operation_id UUID NOT NULL UNIQUE,
    base_revision BIGINT NOT NULL CHECK (base_revision >= 0),
    client_payload JSONB NOT NULL,
    server_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX journal_conflicts_vault_created_idx ON journal_conflicts(vault_id, created_at DESC);
