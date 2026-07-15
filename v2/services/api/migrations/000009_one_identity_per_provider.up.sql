ALTER TABLE external_identities
    ADD CONSTRAINT external_identities_account_provider_key UNIQUE (account_id, provider);
