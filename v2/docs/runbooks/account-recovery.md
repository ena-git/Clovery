# Account Recovery Runbook

## Trigger and ownership

The security on-call engineer is incident commander. Customer support gathers the request but cannot change account ownership. Start this runbook for lost login methods, suspected takeover, incorrect provider binding, accidental deletion request, or a widespread authentication failure.

## Immediate containment

1. For suspected takeover, revoke the affected device and sessions through the account-scoped device revocation flow.
2. If recovery failures are widespread during migration, set `MIGRATION_WRITES_ENABLED=false` and deploy the configuration before further investigation.
3. Preserve V1 app data, migration Bundles, CloudKit source data, Vault objects, and audit rows. Recovery never requires deleting user content.
4. Do not merge accounts by email, provider display name, device identifier, purchase receipt, or support assertion.
5. Do not unbind the final login or recovery method.

## Identity verification

Accept only an existing strong recovery path:

- a registered Passkey;
- a one-time Clovery recovery code;
- an already-bound provider identity plus recent reauthentication;
- two independently bound provider identities when the policy requires manual review.

The authenticated `clovery_account_id` remains the root. Apple, Google, Huawei, WeChat, and QQ identities are replaceable bindings. Email addresses are not account-merge keys.

If no accepted recovery path remains, escalate to the security owner. Support must not manually assign the Vault based only on personal information or payment screenshots.

## Database recovery

1. Create a managed snapshot before any audited repair. For self-managed validation:

   ```bash
   pg_dump --format=custom --no-owner --file=clovery-account-recovery.dump "$DATABASE_URL"
   ```

2. Restore into an isolated database and inspect only the target account's binding IDs, recovery-method state, device IDs, deletion request, entitlement IDs, and audit events.
3. Never copy password hashes, refresh tokens, Passkey private material, journal payloads, or photo URLs into tickets.
4. Any manual repair must preserve the same `clovery_account_id` and `vault_id`, run in one transaction, revoke existing sessions, and emit an audit event.

## Resolution

1. Ask the user to authenticate with the approved recovery method.
2. Require adding a replacement login method or Passkey before unbinding a lost provider.
3. Revoke unknown devices and rotate all refresh sessions.
4. Confirm the account profile, Vault ID, device list, and entitlements remain account-scoped.
5. If an account deletion request was unauthorized and still inside the retention window, cancel it only through an audited administrative procedure approved by the security owner.

## User communication template

> We secured your Clovery account and preserved the Vault attached to your Clovery root account. Existing devices were signed out as a precaution. Please use your approved recovery method, add a replacement login method, and review the device list after signing in.

## Audit and closure

- Record the recovery method category, approvals, affected account ID, revoked session/device counts, and final binding count.
- Record no passwords, codes, tokens, email addresses, journal text, or images.
- Verify the last-login-method invariant and review the incident for account-enumeration or provider-binding defects.
