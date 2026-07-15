CREATE TABLE clovery_system_metadata (
    key TEXT PRIMARY KEY CHECK (length(key) > 0),
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
