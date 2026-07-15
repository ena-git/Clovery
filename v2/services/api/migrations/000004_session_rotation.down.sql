DROP INDEX sessions_token_family_id_idx;
DROP INDEX sessions_refresh_token_hash_key;
ALTER TABLE sessions DROP COLUMN replaced_by_session_id;
ALTER TABLE sessions DROP COLUMN rotated_at;
ALTER TABLE sessions DROP COLUMN token_family_id;
