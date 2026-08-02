ALTER TABLE migration_entries
    ADD COLUMN resolved_entry_id UUID,
    ADD COLUMN dedup_sha256 TEXT,
    ADD COLUMN resolution TEXT NOT NULL DEFAULT 'pending',
    ADD CONSTRAINT migration_entries_resolution_check CHECK (
        resolution IN (
            'pending',
            'insert',
            'exact_duplicate',
            'content_duplicate',
            'id_conflict_copy'
        )
    ),
    ADD CONSTRAINT migration_entries_dedup_sha256_format CHECK (
        dedup_sha256 IS NULL OR dedup_sha256 ~ '^[a-f0-9]{64}$'
    ),
    ADD CONSTRAINT migration_entries_resolution_target_check CHECK (
        (resolution = 'pending' AND resolved_entry_id IS NULL)
        OR (resolution <> 'pending' AND resolved_entry_id IS NOT NULL)
    );

ALTER TABLE journal_entries
    ADD COLUMN content_sha256 TEXT,
    ADD COLUMN dedup_sha256 TEXT,
    ADD CONSTRAINT journal_entries_content_sha256_format CHECK (
        content_sha256 IS NULL OR content_sha256 ~ '^[a-f0-9]{64}$'
    ),
    ADD CONSTRAINT journal_entries_dedup_sha256_format CHECK (
        dedup_sha256 IS NULL OR dedup_sha256 ~ '^[a-f0-9]{64}$'
    );

CREATE INDEX journal_entries_vault_dedup_sha_idx
    ON journal_entries (vault_id, dedup_sha256, updated_at, id)
    WHERE deleted_at IS NULL AND dedup_sha256 IS NOT NULL;
