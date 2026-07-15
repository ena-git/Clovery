#!/bin/sh
set -eu

source_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
cd "$fixture"
git init -q
git config user.name Test
git config user.email test@example.com
git config commit.gpgsign false
mkdir -p scripts/release-evidence docs/release tools
cp "$source_root/scripts/verify-ios-release-evidence.sh" scripts/verify-ios-release-evidence.sh
cp "$source_root/scripts/release-evidence/validate-ios-1.0.3-evidence.awk" \
  scripts/release-evidence/validate-ios-1.0.3-evidence.awk
sed \
  -e "s#/usr/bin/codesign#$fixture/tools/codesign#g" \
  -e "s#/usr/bin/lipo#$fixture/tools/lipo#g" \
  "$source_root/scripts/release-evidence/verify-ios-1.0.3-archive.sh" > \
  scripts/release-evidence/verify-ios-1.0.3-archive.sh
chmod +x scripts/verify-ios-release-evidence.sh
cp "$source_root/docs/release/ios-1.0.3-acceptance.md" docs/release/ios-1.0.3-acceptance.md
cat > tools/codesign <<'CODESIGN'
#!/bin/sh
set -eu
last=
for argument in "$@"; do
  last=$argument
done
case " $* " in
  *" --verify "*) exit 0 ;;
  *" -dv "*) printf 'TeamIdentifier=%s\n' "${FAKE_TEAM:-M92TBSSR2R}" >&2; exit 0 ;;
  *" --entitlements "*)
    if printf '%s' "$last" | grep -Fq 'CloveryWidgetExtension.appex'; then
      cloud=
    else
      cloud='<key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.com.clovery.app</string></array>'
    fi
    extra=
    if [ "${FAKE_EXTRA:-0}" = 1 ]; then
      extra='<string>group.example.extra</string>'
    fi
    printf '%s\n' "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>com.apple.security.application-groups</key><array><string>group.com.clovery.app</string>$extra</array>$cloud</dict></plist>"
    exit 0
    ;;
esac
exit 1
CODESIGN
chmod +x tools/codesign
cat > tools/lipo <<'LIPO'
#!/bin/sh
printf 'arm64\n'
LIPO
chmod +x tools/lipo
git add scripts docs
git commit -qm source
candidate=$(git rev-parse HEAD)

write_evidence() {
  wrapper_open=${1:-}
  wrapper_close=${2:-}
  cat > docs/release/ios-1.0.3-acceptance.md <<EOF
$wrapper_open# Clovery iOS 1.0.3 Acceptance Evidence

**Commit:** \`$candidate\`
**Archive:** \`build/Clovery-1.0.3-14.xcarchive\`
**TestFlight build:** \`14\`

## Automated
- [x] Native verification script — PASS — Time: 2026-07-16T10:00:00+08:00; Device: CI; OS: macOS 15; Evidence: automated/FAILURE-filename-is-safe.txt
- [x] Signed Release archive — PASS — Time: 2026-07-16T10:01:00+08:00; Device: Mac; OS: macOS 15; Evidence: automated/archive.txt
- [x] App and widget identity inspection — PASS — Time: 2026-07-16T10:02:00+08:00; Device: Mac; OS: macOS 15; Evidence: automated/identity.txt

## Upgrade And Migration
- [x] \`1.0.2 (13)\` to \`1.0.3 (14)\` data retention — PASS — Time: 2026-07-16T10:03:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/upgrade.txt
- [x] Migration counts and SHA-256 — PASS — Time: 2026-07-16T10:04:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/migration.txt
- [x] Repeated export retains both bundles — PASS — Time: 2026-07-16T10:05:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/export.txt

## Photo Library
- [x] First authorization save — PASS — Time: 2026-07-16T10:06:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/photo-first.txt
- [x] Repeated save — PASS — Time: 2026-07-16T10:07:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/photo-repeat.txt
- [x] Denial and Settings recovery — PASS — Time: 2026-07-16T10:08:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/photo-denial.txt
- [x] Share remains independent — PASS — Time: 2026-07-16T10:09:00+08:00; Device: iPhone; OS: iOS 18; Evidence: device/share.txt

## StoreKit And TestFlight
- [x] Real App Store Connect price — PASS — Time: 2026-07-16T10:10:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/price.txt
- [x] Cancellation — PASS — Time: 2026-07-16T10:11:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/cancel.txt
- [x] Pending approval — PASS — Time: 2026-07-16T10:12:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/pending.txt
- [x] Successful purchase — PASS — Time: 2026-07-16T10:13:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/purchase.txt
- [x] Relaunch and reinstall restore — PASS — Time: 2026-07-16T10:14:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/reinstall.txt
- [x] Second-device restore — PASS — Time: 2026-07-16T10:15:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/device-two.txt
- [x] TestFlight smoke — PASS — Time: 2026-07-16T10:16:00+08:00; Device: iPhone; OS: iOS 18; Evidence: storekit/testflight.txt

## Privacy
- Git excludes account credentials, email addresses, stable account identifiers, passwords, verification codes, and recovery codes.
- Git excludes receipts, tokens, transaction payloads, transaction IDs, original transaction IDs, and raw entitlement state.
- Git excludes diary content, photos, tombstones, migration ZIPs, manifests, content SHA-256 hashes, device UDIDs, and stable device identifiers.
- Git records only aggregate PASS results, test time, device model, OS version, and non-sensitive evidence filenames.
- Raw counts, hashes, screenshots, logs, archives, and restricted evidence remain under the gitignored \`build/release-evidence/ios-1.0.3/\` directory.$wrapper_close
EOF
}

write_evidence
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm evidence

archive=build/Clovery-1.0.3-14.xcarchive
app=$archive/Products/Applications/Clovery.app
widget=$app/PlugIns/CloveryWidgetExtension.appex
mkdir -p "$widget"
cp /bin/echo "$app/Clovery"
cp /bin/echo "$widget/CloveryWidgetExtension"
cat > "$archive/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>ApplicationProperties</key><dict><key>ApplicationPath</key><string>Applications/Clovery.app</string><key>Architectures</key><array><string>arm64</string></array><key>CFBundleIdentifier</key><string>com.clovery.app</string><key>CFBundleShortVersionString</key><string>1.0.3</string><key>CFBundleVersion</key><string>14</string><key>SigningIdentity</key><string>Apple Distribution</string></dict></dict></plist>
EOF
cat > "$app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Clovery</string><key>CFBundleIdentifier</key><string>com.clovery.app</string><key>CFBundleShortVersionString</key><string>1.0.3</string><key>CFBundleVersion</key><string>14</string><key>DTPlatformName</key><string>iphoneos</string><key>DTSDKName</key><string>iphoneos18.0</string><key>CloverySourceCommit</key><string>$candidate</string></dict></plist>
EOF
cat > "$widget/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>CloveryWidgetExtension</string><key>CFBundleIdentifier</key><string>com.clovery.app.CloveryWidget</string><key>CFBundleShortVersionString</key><string>1.0.3</string><key>CFBundleVersion</key><string>14</string><key>DTPlatformName</key><string>iphoneos</string><key>DTSDKName</key><string>iphoneos18.0</string></dict></plist>
EOF

CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh >/dev/null

expect_failure() {
  label=$1
  shift
  set +e
  "$@" >/dev/null 2>&1
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    echo "expected failure: $label" >&2
    exit 1
  fi
}

expect_failure wrong-team env FAKE_TEAM=WRONG CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh
expect_failure extra-entitlement env FAKE_EXTRA=1 CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh
/usr/bin/plutil -replace DTPlatformName -string macosx "$app/Info.plist"
expect_failure wrong-platform env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh
/usr/bin/plutil -replace DTPlatformName -string iphoneos "$app/Info.plist"
/usr/bin/plutil -replace CloverySourceCommit -string 0000000000000000000000000000000000000000 "$app/Info.plist"
expect_failure wrong-source env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh
/usr/bin/plutil -replace CloverySourceCommit -string "$candidate" "$app/Info.plist"
cp "$app/Clovery" "$fixture/Clovery.backup"
printf '#!/bin/sh\nexit 0\n' > "$app/Clovery"
chmod +x "$app/Clovery"
expect_failure non-macho-app env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh
cp "$fixture/Clovery.backup" "$app/Clovery"

write_evidence '<pre>' '</pre>'
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm html-wrapper
expect_failure html-wrapper env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh

write_evidence
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm restore-schema
/usr/bin/sed -i '' 's/Device: CI/Device: FAILED/' docs/release/ios-1.0.3-acceptance.md
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm failed-metadata
expect_failure failed-metadata env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh

write_evidence
/usr/bin/sed -i '' 's/; Device: CI/;Status: PASS; Device: CI/' docs/release/ios-1.0.3-acceptance.md
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm hidden-metadata
expect_failure hidden-metadata env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh

write_evidence
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm restore-hidden-metadata
/usr/bin/tail -n +2 docs/release/ios-1.0.3-acceptance.md > "$fixture/reordered.md"
printf '\n# Clovery iOS 1.0.3 Acceptance Evidence\n' >> "$fixture/reordered.md"
cp "$fixture/reordered.md" docs/release/ios-1.0.3-acceptance.md
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm reordered-schema
expect_failure reordered-schema env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh

write_evidence
git add docs/release/ios-1.0.3-acceptance.md
git commit -qm restore-order
printf 'temporary source change\n' > source-change.txt
git add source-change.txt
git commit -qm source-change
git rm -q source-change.txt
git commit -qm revert-source-change
expect_failure reverted-source-history env CLOVERY_RELEASE_COMMIT=$candidate scripts/verify-ios-release-evidence.sh

printf 'iOS release evidence gate probes verified\n'
