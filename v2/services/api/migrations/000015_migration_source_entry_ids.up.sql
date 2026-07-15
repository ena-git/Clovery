ALTER TABLE migration_entries
    ADD COLUMN source_entry_id TEXT;

UPDATE migration_entries
SET source_entry_id = entry_id::text;

ALTER TABLE migration_entries
    ALTER COLUMN source_entry_id SET NOT NULL,
    ADD CONSTRAINT migration_entries_source_entry_id_format CHECK (
        source_entry_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$'
    ),
    ADD CONSTRAINT migration_entries_migration_source_key UNIQUE (
        migration_id,
        source_entry_id
    );
