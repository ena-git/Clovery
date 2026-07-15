ALTER TABLE migration_entries
    DROP CONSTRAINT migration_entries_migration_source_key,
    DROP CONSTRAINT migration_entries_source_entry_id_format,
    DROP COLUMN source_entry_id;
