#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_junk_root() {
  cat <<'NAMES'
System Volume Information
RECYCLER
RECYCLED
.Trashes
.Spotlight-V100
.fseventsd
.TemporaryItems
.DocumentRevisions-V100
.MobileBackups
.apdisk
.VolumeIcon.icns
.metadata_never_index
.com.apple.timemachine.*
Network Trash Folder
Temporary Items
TheFindByContentFolder
TheVolumeSettingsFolder
IndexerVolumeGuid
WPSettings.dat
FSCK*.REC
FOUND.[0-9][0-9][0-9]
.Trash-*
@eaDir
#recycle
@Recycle
.hotfiles.btree
.journal
.journal_info_block
NAMES
  printf '\044RECYCLE.BIN\n'
}

disk_junk_any() {
  cat <<'NAMES'
._*
.DS_Store
.AppleDouble
.AppleDB
.AppleDesktop
__MACOSX
Thumbs.db
ehthumbs.db
ehthumbs_vista.db
Desktop.ini
.directory
.~lock.*
~$*
.@__thumb
.dropbox
.dropbox.attr
NAMES
  printf 'Icon\r\n'
}

disk_junk_find() (
  disk_jf_dir="$1"
  disk_jf_mode="$2"
  disk_jf_printer="$(disk_junk_printer)"
  disk_jf_root="$(disk_junk_root)"
  disk_jf_any="$(disk_junk_any)"
  set -f
  disk_jf_newline="$(printf '\nx')"
  IFS="${disk_jf_newline%x}"
  set --
  for disk_jf_name in ${disk_jf_root}; do
    [ "$#" -eq 0 ] || set -- "$@" -o
    set -- "$@" -iname "${disk_jf_name}"
  done
  set -- '(' ! -path './*/*' '(' "$@" ')' ')'
  for disk_jf_name in ${disk_jf_any}; do
    set -- "$@" -o -iname "${disk_jf_name}"
  done
  cd "${disk_jf_dir}" || exit 1
  case "${disk_jf_mode}" in
  remove) disk_as_owner . find . -mindepth 1 '(' "$@" ')' -prune -exec rm -rf '{}' + ;;
  *) find . -mindepth 1 '(' "$@" ')' -prune -exec awk -v mode="${disk_jf_mode}" "${disk_jf_printer}" '{}' + ;;
  esac
)

disk_junk_count() {
  if [ "$1" -eq 1 ]; then
    printf '1 junk file\n'
  else
    printf '%s junk files\n' "$1"
  fi
}

disk_junk_printer() {
  cat <<'AWK'
BEGIN {
  for (i = 1; i < 32; i++) code[sprintf("%c", i)] = sprintf("\\u%04x", i)
  for (n = 1; n < ARGC; n++) {
    path = substr(ARGV[n], 2)
    out = ""
    for (i = 1; i <= length(path); i++) {
      c = substr(path, i, 1)
      if (mode == "json" && c == "\\") c = "\\\\"
      else if (mode == "json" && c == "\"") c = "\\\""
      else if (c in code) c = (mode == "json" ? code[c] : "?")
      out = out c
    }
    print out
  }
  exit
}
AWK
}

disk_as_owner() {
  if [ -w "$1" ]; then
    shift
    "$@"
    return "$?"
  fi
  shift
  sudo "$@"
}

disk_fat_partitions() {
  disk_fp_os="$(disk_os)"
  case "${disk_fp_os}" in
  Darwin)
    disk_fp_list="$(diskutil list "$1" 2>/dev/null)"
    disk_fp_ids="$(printf '%s\n' "${disk_fp_list}" | awk '$NF ~ /^disk[0-9]+s[0-9]+$/ { print "/dev/" $NF }')"
    for disk_fp_dev in "$1" ${disk_fp_ids}; do
      disk_fp_type="$(disk_plist_value "${disk_fp_dev}" FilesystemType)"
      case "${disk_fp_type}" in
      msdos) printf '%s fat\n' "${disk_fp_dev}" ;;
      exfat) printf '%s exfat\n' "${disk_fp_dev}" ;;
      *) ;;
      esac
    done
    ;;
  *)
    disk_fp_names="$(lsblk -nrpo NAME "$1" 2>/dev/null)"
    # shellcheck disable=SC2086
    disk_fp_order="$(printf '%s ' ${disk_fp_names})"
    # shellcheck disable=SC2086
    disk_fp_probe="$(disk_as_root "$1" blkid -p -o export ${disk_fp_names} 2>/dev/null)"
    printf '%s\n' "${disk_fp_probe}" | awk -F= -v names="${disk_fp_order}" '
      $1 == "DEVNAME" { dev = $2 }
      $1 == "TYPE" && ($2 == "vfat" || $2 == "msdos") { kind[dev] = "fat" }
      $1 == "TYPE" && $2 == "exfat" { kind[dev] = "exfat" }
      END {
        n = split(names, order, " ")
        for (i = 1; i <= n; i++) if (order[i] in kind) print order[i] " " kind[order[i]]
      }'
    ;;
  esac
  return 0
}

disk_blkid_value() {
  disk_bv_text="$(disk_as_root "$1" blkid -p -o value -s "$2" "$1" 2>/dev/null)"
  printf '%s\n' "${disk_bv_text}"
}

disk_fs_name() {
  if [ "$2" = exfat ]; then
    printf 'exFAT\n'
    return 0
  fi
  disk_fn_os="$(disk_os)"
  case "${disk_fn_os}" in
  Darwin)
    disk_fn_text="$(disk_plist_value "$1" FilesystemUserVisibleName)"
    disk_fn_name="$(printf '%s\n' "${disk_fn_text}" | sed -n 's/.*(\(FAT[0-9]*\)).*/\1/p')"
    ;;
  *) disk_fn_name="$(disk_blkid_value "$1" VERSION)" ;;
  esac
  printf '%s\n' "${disk_fn_name:-FAT}"
}

disk_volume_label() {
  disk_vl_os="$(disk_os)"
  case "${disk_vl_os}" in
  Darwin) disk_plist_value "$1" VolumeName ;;
  *) disk_blkid_value "$1" LABEL ;;
  esac
  return 0
}

disk_mount_point() {
  disk_mp_os="$(disk_os)"
  case "${disk_mp_os}" in
  Darwin) disk_plist_value "$1" MountPoint ;;
  *) findmnt -nro TARGET --source "$1" 2>/dev/null | sed -n '1p' ;;
  esac
  return 0
}

disk_mount() {
  disk_mn_os="$(disk_os)"
  case "${disk_mn_os}" in
  Darwin)
    if [ "$2" = ro ]; then
      diskutil mount readOnly "$1" >/dev/null 2>&1 || return 1
    else
      diskutil mount "$1" >/dev/null 2>&1 || return 1
    fi
    ;;
  *)
    disk_mn_dir="${DISK_TMPDIR}/${1##*/}"
    mkdir -p "${disk_mn_dir}" || return 1
    disk_mn_uid="$(id -u)"
    disk_mn_gid="$(id -g)"
    sudo mount -o "$2,uid=${disk_mn_uid},gid=${disk_mn_gid}" "$1" "${disk_mn_dir}" 2>/dev/null || return 1
    ;;
  esac
  DISK_MOUNTED_HERE="${DISK_MOUNTED_HERE} $1"
  DISK_POINT="$(disk_mount_point "$1")"
  return 0
}

disk_mounted_at() {
  DISK_POINT="$(disk_mount_point "$1")"
  [ -n "${DISK_POINT}" ] || disk_mount "$1" "$2" || DISK_POINT=""
  if [ -z "${DISK_POINT}" ]; then
    disk_error "could not mount $1."
    return 1
  fi
  return 0
}

disk_unmount() {
  disk_um_point="$(disk_mount_point "$1")"
  [ -n "${disk_um_point}" ] || return 0
  disk_um_os="$(disk_os)"
  disk_um_status=0
  case "${disk_um_os}" in
  Darwin) diskutil unmount "$1" >/dev/null 2>&1 || disk_um_status=1 ;;
  *) sudo umount "$1" 2>/dev/null || disk_um_status=1 ;;
  esac
  if [ "${disk_um_status}" -ne 0 ]; then
    disk_error "could not unmount $1. close anything using ${disk_um_point} and try again."
    return 1
  fi
  DISK_MOUNTED_HERE="$(printf '%s\n' "${DISK_MOUNTED_HERE}" | sed "s| $1\$||; s| $1 | |")"
  return 0
}

disk_release_mounts() {
  for disk_rm_dev in ${DISK_MOUNTED_HERE}; do
    disk_unmount "${disk_rm_dev}" || true
  done
  return 0
}

disk_fsck() {
  disk_fk_os="$(disk_os)"
  case "${disk_fk_os}:$2" in
  Darwin:fat) set -- "$1" fsck_msdos -n "$1" ;;
  Darwin:exfat) set -- "$1" fsck_exfat -n "$1" ;;
  *:fat) set -- "$1" fsck.vfat -n "$1" ;;
  *) set -- "$1" fsck.exfat -n "$1" ;;
  esac
  if ! disk_cmd_exists "$2"; then
    disk_error "stopped: $2 is needed to check $1 before changing it. run 'katazuke doctor'."
    return 1
  fi
  disk_fk_log="${DISK_TMPDIR}/fsck.log"
  disk_as_root "$@" >"${disk_fk_log}" 2>&1 && return 0
  disk_error "stopped: $1 has filesystem errors, so it was not changed. repair it first."
  disk_fk_text="$(sed -n '1,20p' "${disk_fk_log}")"
  printf '%s\n' "${disk_fk_text}" >&2
  return 1
}

disk_sort_flags() {
  case "${KATAZUKE_ORDER:-dirs}" in
  files) disk_sf_order=f ;;
  mixed) disk_sf_order=a ;;
  *) disk_sf_order=d ;;
  esac
  if [ "${KATAZUKE_NATURAL:-y}" = n ]; then
    printf -- '-c -o %s\n' "${disk_sf_order}"
  else
    printf -- '-c -n -o %s\n' "${disk_sf_order}"
  fi
}

disk_sort() {
  disk_so_flags="$(disk_sort_flags)"
  disk_so_log="${DISK_TMPDIR}/fatsort.log"
  # shellcheck disable=SC2086
  disk_as_root "$1" env LC_ALL=C.UTF-8 fatsort ${disk_so_flags} "$1" >"${disk_so_log}" 2>&1 && return 0
  disk_error "fatsort could not sort $1."
  disk_so_text="$(sed -n '1,20p' "${disk_so_log}")"
  printf '%s\n' "${disk_so_text}" >&2
  return 1
}
