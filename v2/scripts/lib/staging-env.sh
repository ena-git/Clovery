staging_env_value() {
  environment_file=$1
  key=$2
  count=$(awk -v key="$key" 'index($0, key "=") == 1 { count++ } END { print count + 0 }' "$environment_file")
  if [ "$count" -ne 1 ]; then
    echo "$key must appear exactly once in $environment_file" >&2
    return 1
  fi
  awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2) }' "$environment_file"
}

staging_env_require() {
  environment_file=$1
  key=$2
  value=$(staging_env_value "$environment_file" "$key") || return 1
  if [ -z "$value" ]; then
    echo "$key is required in $environment_file" >&2
    return 1
  fi
  printf '%s' "$value"
}

staging_database_name() {
  database_url=$1
  database_path=${database_url%%\?*}
  database_name=${database_path##*/}
  [ -n "$database_name" ] || return 1
  printf '%s' "$database_name"
}

staging_database_requires_tls() {
  database_url=$1
  database_query=${database_url#*\?}
  [ "$database_query" != "$database_url" ] || return 1
  case "&$database_query&" in
    *'&sslmode=require&'*|*'&sslmode=verify-ca&'*|*'&sslmode=verify-full&'*) return 0 ;;
    *) return 1 ;;
  esac
}
