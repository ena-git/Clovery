# Clovery iOS 1.0.3 Acceptance Evidence

**Commit:** `NOT_RUN`
**Archive:** `NOT_RUN`
**TestFlight build:** `NOT_RUN`

## Automated
- [ ] Native verification script — `NOT_RUN`
- [ ] Signed Release archive — `NOT_RUN`
- [ ] App and widget identity inspection — `NOT_RUN`

## Upgrade And Migration
- [ ] `1.0.2 (13)` to `1.0.3 (14)` data retention — `NOT_RUN`
- [ ] Migration counts and SHA-256 — `NOT_RUN`
- [ ] Repeated export retains both bundles — `NOT_RUN`

## Photo Library
- [ ] First authorization save — `NOT_RUN`
- [ ] Repeated save — `NOT_RUN`
- [ ] Denial and Settings recovery — `NOT_RUN`
- [ ] Share remains independent — `NOT_RUN`

## StoreKit And TestFlight
- [ ] Real App Store Connect price — `NOT_RUN`
- [ ] Cancellation — `NOT_RUN`
- [ ] Pending approval — `NOT_RUN`
- [ ] Successful purchase — `NOT_RUN`
- [ ] Relaunch and reinstall restore — `NOT_RUN`
- [ ] Second-device restore — `NOT_RUN`
- [ ] TestFlight smoke — `NOT_RUN`

## Privacy

Git must never contain email addresses or other stable account identifiers for
Apple, Sandbox, or Clovery accounts; passwords, verification codes, or recovery
codes; receipts, tokens, transaction payloads, transaction IDs, or original
transaction IDs; diary content, photos, tombstones, raw entitlement state,
migration ZIPs or manifests, content SHA-256 hashes, device UDIDs, or other
stable device identifiers.

For each checklist item, Git records only the aggregate `PASS`, test time, device
model, OS version, and non-sensitive evidence filename. Evidence filenames must
be safe relative paths containing only letters, numbers, dots, underscores,
hyphens, and slashes; absolute paths and `..` are forbidden. Raw counts, hashes,
screenshots, logs, and archives must remain outside Git and be stored only under
the gitignored `build/release-evidence/ios-1.0.3/` directory.

The release checker trusts only the committed
`HEAD:docs/release/ios-1.0.3-acceptance.md`. Uncommitted working-tree edits are
never release evidence.
