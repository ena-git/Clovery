# Apple Billing Incident Runbook

## Production setup

1. Configure App Store Server Notifications V2 in App Store Connect with `POST https://<api-host>/v1/billing/apple/notifications` for production and the staging endpoint for sandbox tests.
2. Set `DEPLOYMENT_ENVIRONMENT=production`; production startup rejects missing Apple billing configuration and rejects `APPLE_IAP_ALLOW_SANDBOX=true`.
3. Configure `APPLE_IAP_BUNDLE_ID`, numeric `APPLE_IAP_APP_APPLE_ID`, and `APPLE_IAP_PRODUCT_IDS` from the released App Store record. A product absent from the allowlist cannot create an entitlement.
4. Load the App Store Connect API key and Apple root certificate through the deployment secret manager. Do not commit decoded keys or certificates.
5. Send an App Store test notification before each billing release and require an HTTP `204` plus a successful notification record for a real signed transaction test.

## Trigger and ownership

The backend on-call engineer owns containment; the product owner confirms intended products and App Store Connect state; support owns affected-user communication. Start this runbook for paid users without active entitlement, unexpected revocations, notification retry spikes, duplicate transaction claims, or Apple verification failures.

## Immediate containment

1. Preserve `store_purchase_chains`, `store_transactions`, `entitlements`, and `apple_store_notifications`; never grant production access by editing a device-local purchase flag.
2. Record the Clovery account ID, Apple transaction ID, product ID, environment, notification UUID, and aggregate error code. Do not record receipt bodies, JWS payloads, tokens, emails, or journal data.
3. Confirm the API release SHA, database migration version, configured bundle ID, product allowlist, and sandbox flag.
4. If cross-account entitlement is possible, disable purchase verification routes at the gateway and escalate to security. Keep authenticated entitlement reads available when safe.

## Diagnosis

1. Ask the user to use the existing restore flow while signed in to the correct Clovery root account. The client must send transaction IDs only; it cannot choose an account ID.
2. Check whether the transaction exists in `store_transactions`, whether `app_account_token` matches the Clovery account ID, and whether `entitlements.source_transaction_id` points to the latest eligible transaction.
3. Check `expires_at`, `revoked_at`, and state. Billing grace period remains active only through Apple’s signed `gracePeriodExpiresDate`; expired, billing-retry-only, or revoked transactions must not unlock paid features.
4. Check `apple_store_notifications` for the notification UUID. Duplicate UUIDs are successful idempotent deliveries, not duplicate grants.
5. If a notification is absent, verify App Store Connect endpoint configuration and Apple delivery history. Re-run the official test notification before changing code.

## Recovery

1. Snapshot PostgreSQL before any repair. Restore the snapshot to an isolated database for validation.
2. Prefer re-verifying the Apple transaction through the authenticated verify or restore API. This refreshes the same server ledger atomically.
3. For a V1 purchase without `appAccountToken`, the authenticated client sends its StoreKit-signed transaction to `POST /v1/billing/apple/legacy-claims`. The backend reserves the original transaction chain, calls Apple Set App Account Token, reverifies, and only then writes the entitlement. Never accept a client-supplied Clovery account ID.
4. Replay missed notification history with an explicit bounded interval. The command is idempotent because notification UUIDs and signed dates are enforced:

   ```bash
   cd v2/services/api
   go run ./cmd/apple-notification-replay \
     --environment production \
     --start 2026-07-14T00:00:00Z \
     --end 2026-07-15T00:00:00Z
   ```

5. Never fabricate a signed transaction or manually set an entitlement active without Apple evidence.
6. Test the repair twice and confirm the second execution changes no rows.
7. Confirm a newly logged-in device receives the same server entitlement before closing the incident.

## User communication template

> We are reconciling your App Store purchase with your Clovery account. Please keep the app installed and sign in to the Clovery account used during purchase, then use Restore Purchases once. We will not ask for your password, receipt, or verification code.

## Closure

- Attach backup identifiers, release SHA, notification UUIDs, transaction IDs, aggregate before/after states, and approval records.
- Confirm production rejects sandbox transactions and that App Store test notification delivery succeeds in staging.
- Add a regression test for the root cause and verify purchase, restore, expiry, refund, and refund reversal behavior before the next release.
