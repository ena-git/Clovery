DROP TABLE account_deletion_requests;

ALTER TABLE clovery_accounts
    DROP CONSTRAINT clovery_accounts_deletion_state_check,
    DROP COLUMN deletion_requested_at,
    DROP COLUMN status;
