#!/usr/bin/env bash
set -euo pipefail

device="${1:-booted}"
app_path="${2:?usage: capture-w9-ios-fixtures.sh [device] APP_PATH [output-directory]}"
output_directory="${3:-/private/tmp/Clovery-W9-Screenshots}"
bundle_id="com.clovery.app"
delay="${CLOVERY_SCREENSHOT_DELAY:-1}"

routes=(
  authentication
  notice
  provider-login
  identity-claim
  migration
  entitlement
  needs-attention
  diary
  account-security
)
if [[ -n "${CLOVERY_SCREENSHOT_ROUTE:-}" ]]; then
  routes=("$CLOVERY_SCREENSHOT_ROUTE")
fi
fonts=(Gaegu System NotoSerifSC NaiChaTi)
sizes=(default accessibility)

mkdir -p "$output_directory"
xcrun simctl install "$device" "$app_path"
xcrun simctl status_bar "$device" override \
  --time 09:41 \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4

for font in "${fonts[@]}"; do
  for size in "${sizes[@]}"; do
    for route in "${routes[@]}"; do
      launch_arguments=(
        -CloveryVerificationFixture "$route"
        -CloveryVerificationFont "$font"
      )
      if [[ "$size" == "accessibility" ]]; then
        launch_arguments+=(
          -CloveryVerificationDynamicType
          accessibility
        )
      else
        launch_arguments+=(
          -CloveryVerificationDynamicType
          default
        )
      fi

      xcrun simctl launch --terminate-running-process \
        "$device" "$bundle_id" "${launch_arguments[@]}" >/dev/null
      route_delay="$delay"
      if [[ "$route" == "diary" ]]; then
        route_delay="${CLOVERY_DIARY_SCREENSHOT_DELAY:-6}"
      fi
      sleep "$route_delay"
      xcrun simctl io "$device" screenshot \
        "$output_directory/${font}-${size}-${route}.png" >/dev/null
    done
  done
done

printf 'Captured %s screenshots in %s\n' \
  "$(( ${#routes[@]} * ${#fonts[@]} * ${#sizes[@]} ))" \
  "$output_directory"
