# Clovery iOS 1.0.3 Acceptance Evidence

**Commit:** `c73f6ceb1d2ce7c7ea7882975bdfff17f4064835`
**Archive:** `build/Clovery-1.0.3-14.xcarchive`
**TestFlight build:** `NOT_RUN`

## Automated
- [x] Native verification script — PASS — Time: 2026-07-16T02:52:23+08:00; Device: iPhone 17 Pro simulator; OS: iOS 26.0.1; Evidence: automated/verify-ios-v1.log
- [x] Signed Release archive — PASS — Time: 2026-07-16T02:53:31+08:00; Device: Mac; OS: macOS 15.7.4; Evidence: automated/archive.log
- [x] App and widget identity inspection — PASS — Time: 2026-07-16T02:53:54+08:00; Device: Mac; OS: macOS 15.7.4; Evidence: automated/archive-inspection.txt

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
- Git excludes account credentials, email addresses, stable account identifiers, passwords, verification codes, and recovery codes.
- Git excludes receipts, tokens, transaction payloads, transaction IDs, original transaction IDs, and raw entitlement state.
- Git excludes diary content, photos, tombstones, migration ZIPs, manifests, content SHA-256 hashes, device UDIDs, and stable device identifiers.
- Git records only aggregate PASS results, test time, device model, OS version, and non-sensitive evidence filenames.
- Raw counts, hashes, screenshots, logs, archives, and restricted evidence remain under the gitignored `build/release-evidence/ios-1.0.3/` directory.
