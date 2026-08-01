smoke_configuration_fail() {
  echo "configuration: FAIL"
  exit 1
}

smoke_initialize() {
  smoke_api_base_url=${CLOVERY_API_BASE_URL%/}
  case "$smoke_api_base_url" in
    https://*) ;;
    *) smoke_configuration_fail ;;
  esac

  [ -n "${SECURE_EVIDENCE_DIR:-}" ] || smoke_configuration_fail
  smoke_repository_root=$(CDPATH= cd -- "$smoke_v2_root/.." && pwd -P)
  smoke_evidence_root=$(staging_external_directory "$SECURE_EVIDENCE_DIR" "$smoke_repository_root" 2>/dev/null) || \
    smoke_configuration_fail

  smoke_curl_bin=${CURL_BIN:-curl}
  smoke_jq_bin=${JQ_BIN:-jq}
  command -v "$smoke_curl_bin" >/dev/null 2>&1 || smoke_configuration_fail
  command -v "$smoke_jq_bin" >/dev/null 2>&1 || smoke_configuration_fail

  chmod 700 "$smoke_evidence_root"
  smoke_work_directory=$(mktemp -d "$smoke_evidence_root/.ios-1.1.0-smoke.XXXXXX")
  chmod 700 "$smoke_work_directory"
  printf '%s\n' 'Content-Type: application/json' >"$smoke_work_directory/content-type.header"
  chmod 600 "$smoke_work_directory/content-type.header"
}

smoke_cleanup() {
  [ -z "${smoke_work_directory:-}" ] || rm -rf -- "$smoke_work_directory"
}

smoke_secure_file() {
  candidate=${1:-}
  [ -n "$candidate" ] && [ -f "$candidate" ] && [ ! -L "$candidate" ] || return 1
  candidate_directory=$(CDPATH= cd -- "$(dirname "$candidate")" && pwd -P) || return 1
  case "$candidate_directory" in
    "$smoke_evidence_root"|"$smoke_evidence_root"/*) ;;
    *) return 1 ;;
  esac
  printf '%s/%s\n' "$candidate_directory" "$(basename "$candidate")"
}

smoke_secure_directory() {
  candidate=${1:-}
  [ -n "$candidate" ] && [ -d "$candidate" ] && [ ! -L "$candidate" ] || return 1
  candidate=$(CDPATH= cd -- "$candidate" && pwd -P) || return 1
  case "$candidate" in
    "$smoke_evidence_root"|"$smoke_evidence_root"/*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$candidate"
}

smoke_request() {
  method=$1
  route=$2
  payload_file=$3
  token_file=$4
  response_file=$5
  expected_status=$6
  authorization_header=

  if [ "$token_file" != "-" ]; then
    token=$(cat "$token_file")
    [ -n "$token" ] || return 1
    case "$token" in
      *[!A-Za-z0-9._~-]*) return 1 ;;
    esac
    authorization_header="$smoke_work_directory/authorization.header"
    printf 'Authorization: Bearer %s\n' "$token" >"$authorization_header"
    chmod 600 "$authorization_header"
  fi

  curl_error="$smoke_work_directory/curl.error"
  : >"$curl_error"
  chmod 600 "$curl_error"
  if [ "$payload_file" = "-" ] && [ -z "$authorization_header" ]; then
    status=$("$smoke_curl_bin" -sS -X "$method" -o "$response_file" -w '%{http_code}' \
      --connect-timeout 5 --max-time 30 -H "@$smoke_work_directory/content-type.header" \
      "$smoke_api_base_url$route" 2>"$curl_error") || return 1
  elif [ "$payload_file" = "-" ]; then
    status=$("$smoke_curl_bin" -sS -X "$method" -o "$response_file" -w '%{http_code}' \
      --connect-timeout 5 --max-time 30 -H "@$smoke_work_directory/content-type.header" \
      -H "@$authorization_header" "$smoke_api_base_url$route" 2>"$curl_error") || return 1
  elif [ -z "$authorization_header" ]; then
    status=$("$smoke_curl_bin" -sS -X "$method" -o "$response_file" -w '%{http_code}' \
      --connect-timeout 5 --max-time 30 -H "@$smoke_work_directory/content-type.header" \
      --data-binary "@$payload_file" "$smoke_api_base_url$route" 2>"$curl_error") || return 1
  else
    status=$("$smoke_curl_bin" -sS -X "$method" -o "$response_file" -w '%{http_code}' \
      --connect-timeout 5 --max-time 30 -H "@$smoke_work_directory/content-type.header" \
      -H "@$authorization_header" --data-binary "@$payload_file" \
      "$smoke_api_base_url$route" 2>"$curl_error") || return 1
  fi
  chmod 600 "$response_file"
  [ "$status" = "$expected_status" ]
}

smoke_assert_json() {
  response_file=$1
  expression=$2
  "$smoke_jq_bin" -e "$expression" "$response_file" >/dev/null 2>&1
}

smoke_extract_json() {
  response_file=$1
  expression=$2
  output_file=$3
  "$smoke_jq_bin" -er "$expression" "$response_file" >"$output_file" 2>/dev/null || return 1
  chmod 600 "$output_file"
  [ -s "$output_file" ]
}

smoke_compare_roots() {
  first=$1
  second=$2
  first_root=$(mktemp "$smoke_work_directory/root-a.XXXXXX")
  second_root=$(mktemp "$smoke_work_directory/root-b.XXXXXX")
  "$smoke_jq_bin" -S '{account_id, vault_id}' "$first" >"$first_root" 2>/dev/null || return 1
  "$smoke_jq_bin" -S '{account_id, vault_id}' "$second" >"$second_root" 2>/dev/null || return 1
  cmp -s "$first_root" "$second_root"
}

smoke_run_scenario() {
  scenario_name=$1
  shift
  if "$@"; then
    echo "$scenario_name: PASS"
  else
    echo "$scenario_name: FAIL"
    exit 1
  fi
}
