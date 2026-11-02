#!/bin/sh
[ -n "${ZSH_VERSION:-}" ] && emulate sh

DISK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)" || exit 1

# shellcheck source=SCRIPTDIR/../lib/core.sh
. "${DISK_LIB}/core.sh"
# shellcheck source=SCRIPTDIR/../lib/cli.sh
. "${DISK_LIB}/cli.sh"
# shellcheck source=SCRIPTDIR/../lib/disk.sh
. "${DISK_LIB}/disk.sh"
# shellcheck source=SCRIPTDIR/../lib/tidy.sh
. "${DISK_LIB}/tidy.sh"

call_first_boot_disk() {
  call_fb_list="$(disk_boot_disks)"
  printf '%s\n' "${call_fb_list}" | sed -n '1p'
}

call_sort_report() {
  disk_make_tmpdir || return 1
  disk_sr_status=0
  disk_sort "$1" "$2" || disk_sr_status=1
  disk_drop_tmpdir
  return "${disk_sr_status}"
}

call_release() {
  disk_make_tmpdir || return 1
  disk_mounted_at "$1" ro || return 1
  disk_release_mounts
  disk_drop_tmpdir
  disk_mount_point "$1"
}

"$@"
