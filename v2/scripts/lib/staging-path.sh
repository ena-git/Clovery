staging_external_directory() {
  candidate=$1
  repository_root=$2

  [ -d "$candidate" ] || {
    echo "staging path error: directory must already exist" >&2
    return 1
  }

  candidate_absolute=$(CDPATH= cd -- "$candidate" && pwd -P) || return 1
  repository_absolute=$(CDPATH= cd -- "$repository_root" && pwd -P) || return 1
  case "$candidate_absolute" in
    "$repository_absolute"|"$repository_absolute"/*)
      echo "staging path error: directory must be outside the Git repository" >&2
      return 1
      ;;
  esac

  printf '%s\n' "$candidate_absolute"
}
