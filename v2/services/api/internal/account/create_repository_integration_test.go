package account

import (
	"context"
	"testing"
)

func TestCreateAccountCreatesNewInstallBootstrapAtomically(t *testing.T) {
	databaseHandle, repository, _, _ := openClaimedCreateDatabase(t)
	params := CreateAccountParams{
		AccountID:    "91000000-0000-4000-8000-000000000001",
		VaultID:      "92000000-0000-4000-8000-000000000001",
		LoginID:      "plain_bootstrap_user",
		PasswordHash: claimedCreatePasswordHash(t),
	}

	if err := repository.CreateAccount(context.Background(), params); err != nil {
		t.Fatalf("CreateAccount() error = %v", err)
	}

	var sourceKind string
	var identityState string
	var migrationState string
	var entitlementState string
	var vaultState string
	if err := databaseHandle.QueryRow(`
		SELECT source_kind, identity_state, migration_state, entitlement_state, vault_state
		FROM account_bootstrap_jobs
		WHERE account_id = $1 AND vault_id = $2
	`, params.AccountID, params.VaultID).Scan(
		&sourceKind,
		&identityState,
		&migrationState,
		&entitlementState,
		&vaultState,
	); err != nil {
		t.Fatalf("read plain registration bootstrap job: %v", err)
	}
	if sourceKind != "new_install" || identityState != "complete" || migrationState != "complete" ||
		entitlementState != "pending" || vaultState != "pending" {
		t.Fatalf(
			"plain bootstrap state source=%s identity=%s migration=%s entitlement=%s vault=%s",
			sourceKind,
			identityState,
			migrationState,
			entitlementState,
			vaultState,
		)
	}
}

func TestCreateAccountRollsBackWhenBootstrapCreationFails(t *testing.T) {
	databaseHandle, repository, _, _ := openClaimedCreateDatabase(t)
	if _, err := databaseHandle.Exec(`
		CREATE FUNCTION fail_plain_bootstrap() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN
			RAISE EXCEPTION 'injected plain bootstrap failure';
		END
		$$;
		CREATE TRIGGER fail_plain_bootstrap BEFORE INSERT ON account_bootstrap_jobs
		FOR EACH ROW EXECUTE FUNCTION fail_plain_bootstrap();
	`); err != nil {
		t.Fatalf("install plain bootstrap failure trigger: %v", err)
	}

	params := CreateAccountParams{
		AccountID:    "93000000-0000-4000-8000-000000000001",
		VaultID:      "94000000-0000-4000-8000-000000000001",
		LoginID:      "plain_rollback_user",
		PasswordHash: claimedCreatePasswordHash(t),
	}
	if err := repository.CreateAccount(context.Background(), params); err == nil {
		t.Fatal("CreateAccount() error = nil after injected bootstrap failure")
	}

	for table, query := range map[string]string{
		"account":   "SELECT COUNT(*) FROM clovery_accounts WHERE id = $1",
		"login ID":  "SELECT COUNT(*) FROM account_login_ids WHERE account_id = $1",
		"password":  "SELECT COUNT(*) FROM password_credentials WHERE account_id = $1",
		"Vault":     "SELECT COUNT(*) FROM vaults WHERE owner_account_id = $1",
		"bootstrap": "SELECT COUNT(*) FROM account_bootstrap_jobs WHERE account_id = $1",
	} {
		var count int
		if err := databaseHandle.QueryRow(query, params.AccountID).Scan(&count); err != nil {
			t.Fatalf("count rolled-back %s rows: %v", table, err)
		}
		if count != 0 {
			t.Fatalf("rolled-back %s row count = %d, want 0", table, count)
		}
	}
}
