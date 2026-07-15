ALTER TABLE clovery_accounts
    ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'deletion_requested', 'deleting', 'deleted')),
    ADD COLUMN deletion_requested_at TIMESTAMPTZ;

ALTER TABLE clovery_accounts
    ADD CONSTRAINT clovery_accounts_deletion_state_check CHECK (
        (status = 'active' AND deletion_requested_at IS NULL)
        OR (status <> 'active' AND deletion_requested_at IS NOT NULL)
    );

CREATE TABLE account_deletion_requests (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'cancelled')),
    requested_at TIMESTAMPTZ NOT NULL,
    scheduled_for TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    CONSTRAINT account_deletion_requests_schedule_check CHECK (scheduled_for > requested_at),
    CONSTRAINT account_deletion_requests_completion_check CHECK (
        (status = 'completed' AND completed_at IS NOT NULL)
        OR (status <> 'completed' AND completed_at IS NULL)
    )
);

CREATE UNIQUE INDEX account_deletion_requests_one_pending_per_account
    ON account_deletion_requests(account_id)
    WHERE status = 'pending';

CREATE INDEX account_deletion_requests_pending_schedule_idx
    ON account_deletion_requests(scheduled_for)
    WHERE status = 'pending';
