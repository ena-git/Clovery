#!/bin/sh

hygiene_fail() {
  echo "repository hygiene failed: $1" >&2
  return 1
}

hygiene_file_size() {
  path=$1
  if stat -f '%z' "$path" >/dev/null 2>&1; then
    stat -f '%z' "$path"
  else
    stat -c '%s' "$path"
  fi
}

hygiene_is_reviewed_large_asset() {
  case "$1" in
    'Clovery/Clover Diary.html' | \
    'Clovery/app.compiled.js' | \
    'Clovery/vendor/babel.min.js' | \
    'Clovery/vendor/react.production.min.js' | \
    'Clovery/vendor/react-dom.production.min.js')
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

hygiene_is_forbidden_tracked_path() {
  case "$1" in
    .env | */.env | .env.* | */.env.*)
      case "$1" in
        .env.example | */.env.example) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *.p8 | *.p12 | *.pem | *.der | *.mobileprovision | *.cer | *.key | *.jws | *.ipa | \
    *.xcarchive | *.xcarchive/* | *.xcresult | *.xcresult/* | \
    */DerivedData/* | DerivedData/* | */Documents/CloveryMigration/* | \
    Documents/CloveryMigration/* | *.cloverymigration)
      return 0
      ;;
    build/release-evidence/* | */build/release-evidence/* | \
    */private-evidence/* | */user-photos/* | */user-data/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

hygiene_is_generated_path() {
  case "/$1/" in
    */DerivedData/* | */.dart_tool/* | */node_modules/* | */Pods/* | \
    */.gradle/* | */.build/* | */build/* | */xcuserdata/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

hygiene_is_release_evidence() {
  case "$1" in
    docs/superpowers/verification/*.md | \
    docs/release/*acceptance*.md | \
    docs/release/*monitoring*.md | \
    docs/release/*production-checklist*.md | \
    v2/docs/release/*acceptance*.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

hygiene_check_tracked_paths() {
  limit=${CLOVERY_HYGIENE_TRACKED_LIMIT_BYTES:-26214400}
  git ls-files | while IFS= read -r path; do
    if hygiene_is_forbidden_tracked_path "$path"; then
      hygiene_fail "forbidden tracked path: $path"
      exit 1
    fi
    [ -f "$path" ] || continue
    size=$(hygiene_file_size "$path")
    if [ "$size" -gt "$limit" ] && ! hygiene_is_reviewed_large_asset "$path"; then
      hygiene_fail "unreviewed tracked file exceeds size limit: $path ($size bytes)"
      exit 1
    fi
  done
}

hygiene_check_tracked_secret_content() {
  private_key_prefix='-----BEGIN '
  private_key_suffix='PRIVATE KEY-----'
  if git grep -I -n -F "$private_key_prefix" -- . 2>/dev/null \
    | grep -F "$private_key_suffix" >/dev/null 2>&1; then
    hygiene_fail "tracked private-key material detected"
    return 1
  fi

  jws_pattern='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  if git grep -I -n -E "$jws_pattern" -- . 2>/dev/null >/dev/null; then
    hygiene_fail "tracked signed token or StoreKit JWS detected"
    return 1
  fi

  api_key_pattern='(AKIA|ASIA)[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|ghp_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{30,}|sk-(live|proj)-[0-9A-Za-z_-]{20,}'
  if git grep -I -n -E "$api_key_pattern" -- . 2>/dev/null >/dev/null; then
    hygiene_fail "tracked API credential detected"
    return 1
  fi
}

hygiene_check_generated_directories() {
  repository_root=$1
  limit_kb=${CLOVERY_HYGIENE_GENERATED_LIMIT_KB:-102400}
  find "$repository_root" -type d \( \
      -name DerivedData -o \
      -name .dart_tool -o \
      -name node_modules -o \
      -name Pods -o \
      -name .gradle -o \
      -name .build -o \
      -name build \
    \) -prune | while IFS= read -r directory; do
      relative=${directory#"$repository_root"/}
      if git check-ignore -q -- "$relative" 2>/dev/null; then
        continue
      fi
      size_kb=$(du -sk "$directory" | awk '{ print $1 }')
      if [ "$size_kb" -gt "$limit_kb" ]; then
        hygiene_fail "unignored generated directory exceeds size limit: $relative (${size_kb}KB)"
        exit 1
      fi
    done
}

hygiene_check_dirty_generated_output() {
  git status --porcelain --untracked-files=all | while IFS= read -r status_line; do
    path=${status_line#???}
    if hygiene_is_generated_path "$path"; then
      hygiene_fail "generated output appears in git status: $path"
      exit 1
    fi
  done
}

hygiene_check_release_evidence() {
  git ls-files | while IFS= read -r path; do
    hygiene_is_release_evidence "$path" || continue
    [ -f "$path" ] || continue

    if grep -E -i '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' "$path" \
      | grep -Fv 'support@clovery.cn' >/dev/null 2>&1; then
      hygiene_fail "email address found in release evidence: $path"
      exit 1
    fi
    if grep -E -i '(^|[^0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}([^0-9a-f]|$)' "$path" >/dev/null; then
      hygiene_fail "stable UUID found in release evidence: $path"
      exit 1
    fi
    if grep -E -i '(^|[^0-9a-f])[0-9a-f]{40}([^0-9a-f]|$)' "$path" >/dev/null; then
      hygiene_fail "complete SHA or device identifier found in release evidence: $path"
      exit 1
    fi
    if grep -E -i '(transaction|交易号|订单号)[^0-9]{0,16}[0-9]{10,}' "$path" >/dev/null; then
      hygiene_fail "transaction identifier found in release evidence: $path"
      exit 1
    fi
    if grep -E -i '(recovery code|恢复码)[^A-Z0-9]{0,8}[A-Z0-9]{4}(-[A-Z0-9]{4}){2,}' "$path" >/dev/null; then
      hygiene_fail "recovery code found in release evidence: $path"
      exit 1
    fi
    if grep -E -i '(diary text|日记内容)[[:space:]]*[:：]' "$path" >/dev/null; then
      hygiene_fail "diary content found in release evidence: $path"
      exit 1
    fi
  done
}
