CREATE TABLE store_purchase_chains (
    storefront TEXT NOT NULL CHECK (length(storefront) > 0),
    original_transaction_id TEXT NOT NULL CHECK (length(original_transaction_id) > 0),
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (storefront, original_transaction_id),
    UNIQUE (account_id, storefront, original_transaction_id)
);

CREATE TABLE store_transactions (
    storefront TEXT NOT NULL CHECK (length(storefront) > 0),
    transaction_id TEXT NOT NULL CHECK (length(transaction_id) > 0),
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    original_transaction_id TEXT NOT NULL CHECK (length(original_transaction_id) > 0),
    product_id TEXT NOT NULL CHECK (length(product_id) > 0),
    environment TEXT NOT NULL CHECK (environment IN ('production', 'sandbox')),
    purchase_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    app_account_token UUID NOT NULL,
    verification_metadata JSONB NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'revoked', 'cancelled', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (storefront, transaction_id),
    UNIQUE (account_id, storefront, transaction_id),
    FOREIGN KEY (account_id, storefront, original_transaction_id)
        REFERENCES store_purchase_chains(account_id, storefront, original_transaction_id)
        ON DELETE CASCADE
);

CREATE INDEX store_transactions_account_purchase_idx
    ON store_transactions(account_id, purchase_at DESC);

CREATE TABLE entitlements (
    account_id UUID NOT NULL REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL CHECK (length(product_id) > 0),
    state TEXT NOT NULL CHECK (state IN ('active', 'expired', 'revoked', 'cancelled', 'failed')),
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    source_storefront TEXT NOT NULL,
    source_transaction_id TEXT NOT NULL,
    source_purchase_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, product_id),
    FOREIGN KEY (account_id, source_storefront, source_transaction_id)
        REFERENCES store_transactions(account_id, storefront, transaction_id)
        ON DELETE CASCADE
);

CREATE TABLE apple_store_notifications (
    notification_uuid UUID PRIMARY KEY,
    notification_type TEXT NOT NULL CHECK (length(notification_type) > 0),
    subtype TEXT,
    environment TEXT CHECK (environment IS NULL OR environment IN ('production', 'sandbox')),
    account_id UUID REFERENCES clovery_accounts(id) ON DELETE SET NULL,
    storefront TEXT CHECK (storefront IS NULL OR length(storefront) > 0),
    transaction_id TEXT CHECK (transaction_id IS NULL OR length(transaction_id) > 0),
    signed_at TIMESTAMPTZ NOT NULL,
    payload_sha256 CHAR(64) NOT NULL CHECK (payload_sha256 ~ '^[a-f0-9]{64}$'),
    received_at TIMESTAMPTZ NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL,
    CHECK ((storefront IS NULL) = (transaction_id IS NULL)),
    CHECK (account_id IS NULL OR storefront IS NOT NULL)
);

CREATE INDEX apple_store_notifications_account_signed_idx
    ON apple_store_notifications(account_id, signed_at DESC);

CREATE INDEX apple_store_notifications_transaction_signed_idx
    ON apple_store_notifications(storefront, transaction_id, signed_at DESC)
    WHERE transaction_id IS NOT NULL;
