DROP TABLE IF EXISTS account_bootstrap_jobs;
ALTER TABLE vault_migrations DROP CONSTRAINT IF EXISTS vault_migrations_id_vault_id_key;
ALTER TABLE vaults DROP CONSTRAINT IF EXISTS vaults_id_owner_account_id_key;
DROP TABLE IF EXISTS identity_claims;
