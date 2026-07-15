#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /private/tmp/clovery-migration-zip.XXXXXX)
binary="$test_root/migration-zip-smoke"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

xcrun swiftc \
  "$repository_root/Clovery/MigrationBundle.swift" \
  "$repository_root/Clovery/MigrationBundleExporter.swift" \
  "$repository_root/Tests/MigrationBundleZipSmoke.swift" \
  -module-cache-path "$test_root/module-cache" \
  -o "$binary"

archive_path=$("$binary" "$test_root/documents")
unzip -t "$archive_path"
