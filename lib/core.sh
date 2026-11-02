#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

KATAZUKE_VERSION="1.0.1"

disk_version() {
  printf '%s %s\n' "$1" "${KATAZUKE_VERSION}"
}

disk_wrap() {
  awk -v width="${DISK_WIDTH}" -v indent="$1" '
    function pad(n,   s) {
      s = ""
      while (n-- > 0) { s = s " " }
      return s
    }
    length($0) <= width { print; next }
    {
      match($0, /^ */)
      n = split($0, word, " ")
      out = substr($0, 1, RLENGTH) word[1]
      for (i = 2; i <= n; i++) {
        if (length(out) + 1 + length(word[i]) > width) {
          print out
          out = pad(indent) word[i]
        } else {
          out = out " " word[i]
        }
      }
      print out
    }'
}

disk_terminal() {
  [ "${KATAZUKE_TERMINAL:-}" = 1 ] || [ -t 1 ]
}

disk_say() {
  disk_sy_text="$2"
  if [ "${#disk_sy_text}" -le "${DISK_WIDTH}" ] || ! disk_terminal; then
    printf '%s\n' "${disk_sy_text}"
    return 0
  fi
  printf '%s\n' "${disk_sy_text}" | disk_wrap "$1"
}

disk_log() {
  disk_say 0 "$1$2"
}

disk_info() {
  [ "${KATAZUKE_JSON:-n}" != y ] || return 0
  disk_say 8 "$*"
}

disk_success() {
  [ "${KATAZUKE_JSON:-n}" != y ] || return 0
  disk_log "" "$*"
}

disk_json_string() {
  printf '%s' "$1" | awk '
    BEGIN { for (i = 1; i < 32; i++) code[sprintf("%c", i)] = sprintf("\\u%04x", i) }
    function escape(s,   r, c, i) {
      r = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") r = r "\\\\"
        else if (c == "\"") r = r "\\\""
        else if (c in code) r = r code[c]
        else r = r c
      }
      return r
    }
    { out = out (NR > 1 ? "\\n" : "") escape($0) }
    END { printf "\"%s\"", out }'
}

disk_warning() {
  disk_log "${DISK_PROG}: warning: " "$*" >&2
}

disk_error() {
  disk_log "${DISK_PROG}: " "$*" >&2
}

disk_cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

disk_is_uint() {
  case "$1" in
  '' | *[!0-9]*) return 1 ;;
  *) return 0 ;;
  esac
}

disk_os() {
  if [ -z "${DISK_OS:-}" ]; then
    DISK_OS="$(uname -s)"
  fi
  printf '%s\n' "${DISK_OS}"
}

disk_plist_value() {
  disk_pv_plist="$(diskutil info -plist "$1" 2>/dev/null)"
  printf '%s' "${disk_pv_plist}" | plutil -extract "$2" raw - 2>/dev/null
}

disk_human() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i]
  }'
}

disk_make_tmpdir() {
  DISK_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/katazuke.XXXXXX")" || {
    disk_error "unable to create a working directory."
    return 1
  }
  return 0
}

disk_drop_tmpdir() {
  [ -n "${DISK_TMPDIR:-}" ] && rm -rf "${DISK_TMPDIR}"
  DISK_TMPDIR=""
  return 0
}
