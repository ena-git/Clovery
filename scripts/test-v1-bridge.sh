#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_binary="/private/tmp/clovery-v1-bridge-tests"
module_cache="/private/tmp/clovery-swift-module-cache"

swiftc \
  -module-cache-path "$module_cache" \
  "$repository_root/Clovery/NativeBridgeModels.swift" \
  "$repository_root/Clovery/BridgeJavaScript.swift" \
  "$repository_root/Tests/V1BridgeRegressionTests.swift" \
  -o "$test_binary"

"$test_binary"
