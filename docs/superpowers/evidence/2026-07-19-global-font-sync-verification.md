# Global Font Sync Verification

## Automated Verification

- App plist validation: PASS
- Widget plist validation: PASS
- Project and scheme discovery: PASS
- Font synchronization test suites: PASS
- App simulator build, install, and launch: PASS (`com.clovery.app`, PID `68698`)
- Widget simulator build: PASS
- App font resource bundle: PASS (7 fonts)
- Widget font resource bundle: PASS (7 fonts)
- New Clovery startup crash reports: NONE

The passing font synchronization suites cover:

- Web-compatible identifiers for handwriting, system, Noto Serif SC, and NaiChaTi
- App Group and standard-default migration and persistence
- Dynamic Type scaling and language-aware handwriting fallbacks
- Missing-primary-font fallback to the system font
- Existing Web `icloud` payload to native `AppFontStore` bridging
- Authentication, registration, recovery, and upgrade presentation contracts
- Widget canonical-key compatibility and all four font mappings

## Full XCTest Suite

- Result: BLOCKED (`90` passed, `14` failed, `0` skipped)
- Font synchronization failures: NONE
- Authentication API fixture failures: existing request-body and response-reset test issues
- Release configuration failure: `CLOVERY_RELEASE_API_BASE_URL` is not configured for the test runner
- Keychain failures: unsigned simulator test host returns OSStatus `-34018`
- Login and registration view-model failures: downstream of the same test Keychain access failure

These failures are outside the global-font change set and remain release-gate work; this document does not mark the full suite as passing.

## Visual Acceptance

- Handwriting Web interface launch: PASS on iPhone 17 Pro simulator
- System font end-to-end Web/native relaunch pass: PENDING manual acceptance
- Noto Serif SC end-to-end Web/native relaunch pass: PENDING manual acceptance
- NaiChaTi end-to-end Web/native relaunch pass: PENDING manual acceptance
- Physical-device acceptance: DEFERRED until the agreed iOS completion checkpoint before Flutter work
