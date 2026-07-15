staging_sha256() {
  file_path=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{ print $1 }'
  else
    echo "sha256sum or shasum is required" >&2
    return 1
  fi
}
