ALTER TABLE sessions ADD COLUMN token_family_id UUID;
UPDATE sessions SET token_family_id = id WHERE token_family_id IS NULL;
ALTER TABLE sessions ALTER COLUMN token_family_id SET NOT NULL;

ALTER TABLE sessions ADD COLUMN rotated_at TIMESTAMPTZ;
ALTER TABLE sessions ADD COLUMN replaced_by_session_id UUID REFERENCES sessions(id);

CREATE UNIQUE INDEX sessions_refresh_token_hash_key ON sessions(refresh_token_hash);
CREATE INDEX sessions_token_family_id_idx ON sessions(token_family_id);
