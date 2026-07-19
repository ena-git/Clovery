# Swift Auth Foundation Verification

Date: 2026-07-19

## Implementation

- Branch: `codex/swift-auth-foundation`
- Implementation commits: `3508bf8`, `badd688`, `3342105`, `8a8afb6`, `9d59fa7`, `79fbe7e`
- Reference screen size: 402 × 874

## Verification

- `GOCACHE=/private/tmp/clovery-go-build go test ./...`: passed with temporary local-listener permission.
- `./scripts/test-v1-p0-contract.sh`: passed.
- iOS production Swift `swiftc -typecheck` against the iOS 16 SDK: passed.
- `plutil -lint Clovery/Info.plist`: passed.
- `xcodebuild -list -project Clovery.xcodeproj`: passed.
- `git diff --check`: passed.

## Environment

- Debug API category: local development URL `http://127.0.0.1:8080`.
- Release API category: environment-injected `CLOVERY_RELEASE_API_BASE_URL`; it must be HTTPS and must not use the staging host.
- Provider client IDs, redirect URLs, scopes, and authorization endpoints are build settings; no provider secret is committed.

## Deferred Device Checks

- `xcodebuild build` and `xcodebuild test` could not finish in this environment because `CoreSimulatorService` has no available iOS Simulator runtime; `actool` stopped at asset thinning before a runnable app/test bundle was produced.
- Visual acceptance remains a real-device or supported-simulator step at 402 × 874. No visual pass is claimed here.
