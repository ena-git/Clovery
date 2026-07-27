DROP INDEX journal_entries_vault_dedup_sha_idx;

ALTER TABLE journal_entries
    DROP COLUMN content_sha256,
    DROP COLUMN dedup_sha256;

ALTER TABLE migration_entries
    DROP COLUMN resolution,
    DROP COLUMN dedup_sha256,
    DROP COLUMN resolved_entry_id;
