#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_cli_hint() {
  disk_say 0 "${DISK_PROG}: $1. run '${DISK_PROG} help' for usage." >&2
}

disk_cli_version() {
  disk_version "${DISK_PROG}"
  disk_cv_platform="$(uname -sr)" || disk_cv_platform="unknown"
  printf 'platform: %s\n' "${disk_cv_platform}"
}

disk_doctor_row() {
  printf '%-18s %-8s %s\n' "$1" "$2" "$3"
}

disk_flavor_version() {
  printf '%s\n' "$1" | awk '{
    for (i = 1; i <= NF; i++) {
      t = $i
      gsub(/[,;()]/, "", t)
      sub(/^v/, "", t)
      if (t ~ /^[0-9]+(\.[0-9]+)+[a-z0-9]*$/ || t ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) { print t; exit }
    }
  }'
}

disk_tool_line() {
  disk_tl_line="$(printf '%s\n' "$1" | awk '/BusyBox|This is not GNU/ { print; exit }')"
  if [ -z "${disk_tl_line}" ]; then
    disk_tl_line="$(printf '%s\n' "$1" | sed -n '1p')"
  fi
  printf '%s\n' "${disk_tl_line}"
}

disk_tool_flavor() {
  disk_tf_raw="$("$1" --version 2>&1 </dev/null)" || true
  disk_tf_text="$(disk_tool_line "${disk_tf_raw}")"
  disk_tf_version="$(disk_flavor_version "${disk_tf_text}")"
  disk_tf_os="$(disk_os)"
  case "${disk_tf_text}" in
  *uutils*) disk_tf_name=uutils ;;
  *BusyBox*) disk_tf_name=busybox ;;
  *"This is not GNU"*)
    disk_tf_name=busybox
    disk_tf_version=""
    ;;
  *GNU* | *GLIBC* | *"(findutils)"*) disk_tf_name=gnu ;;
  *mawk*) disk_tf_name=mawk ;;
  *"awk version"* | *"(Darwin)"*) disk_tf_name=bsd ;;
  *)
    disk_tf_version=""
    case "$1:${disk_tf_os}" in
    *uutils*:* | */cargo/*:*) disk_tf_name=uutils ;;
    *:Darwin | *:*BSD) disk_tf_name=bsd ;;
    *) disk_tf_name=unknown ;;
    esac
    ;;
  esac
  printf '%s%s\n' "${disk_tf_name}" "${disk_tf_version:+ ${disk_tf_version}}"
}

disk_doctor_found() {
  disk_df_note=""
  case "${1##*/}" in
  awk | sed | find) disk_df_note="$(disk_tool_flavor "$1")" ;;
  *) ;;
  esac
  printf '%s%s\n' "$1" "${disk_df_note:+, ${disk_df_note}}"
}

disk_doctor_tool() {
  disk_dt_found="$(command -v "$1" 2>/dev/null || true)"
  if [ -n "${disk_dt_found}" ]; then
    disk_dt_detail="$(disk_doctor_found "${disk_dt_found}")"
    disk_doctor_row "$1" ok "${disk_dt_detail}"
    return 0
  fi
  disk_doctor_row "$1" missing "$2"
  return 1
}

disk_doctor_platform() {
  disk_dp_status=0
  disk_dp_os="$(disk_os)"
  case "${disk_dp_os}" in
  Darwin)
    disk_doctor_tool diskutil "lists, mounts and ejects disks" || disk_dp_status=1
    disk_doctor_tool plutil "reads disk details" || disk_dp_status=1
    disk_doctor_tool fsck_msdos "checks FAT volumes before any change" || disk_dp_status=1
    disk_doctor_tool fsck_exfat "checks exFAT volumes before any change" || disk_dp_status=1
    ;;
  *)
    for disk_dp_tool in lsblk blkid findmnt mount umount; do
      disk_doctor_tool "${disk_dp_tool}" "util-linux, required" || disk_dp_status=1
    done
    disk_doctor_tool fsck.vfat "dosfstools, checks FAT volumes before any change" || disk_dp_status=1
    disk_doctor_tool fsck.exfat "exfatprogs, needed for exFAT volumes" || true
    disk_doctor_tool eject "ejects the disk when done" || true
    ;;
  esac
  return "${disk_dp_status}"
}

disk_doctor_fatsort() {
  disk_dfs_found="$(command -v fatsort 2>/dev/null || true)"
  if [ -z "${disk_dfs_found}" ]; then
    disk_doctor_row fatsort missing required
    return 1
  fi
  disk_dfs_version="$(disk_fatsort_version)"
  if disk_fatsort_dated; then
    disk_doctor_row fatsort warn "${disk_dfs_found}, ${disk_dfs_version}, 1.7 or later sorts every exFAT volume"
  else
    disk_doctor_row fatsort ok "${disk_dfs_found}, ${disk_dfs_version}"
  fi
  return 0
}

disk_doctor() {
  disk_dr_status=0
  disk_doctor_fatsort || disk_dr_status=1
  for disk_dr_tool in awk sed find sudo; do
    disk_doctor_tool "${disk_dr_tool}" "required" || disk_dr_status=1
  done
  disk_doctor_platform || disk_dr_status=1
  return "${disk_dr_status}"
}

disk_cli_interactive() {
  [ "${KATAZUKE_INTERACTIVE:-}" = 1 ] && return 0
  [ -t 0 ]
}

disk_cli_is_option() {
  case "$1" in
  --* | -?*) return 0 ;;
  *) return 1 ;;
  esac
}

disk_cli_takes_value() {
  case " ${DISK_VALUE_OPTIONS} " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

disk_cli_assign() {
  if ! disk_cli_takes_value "${1%%=*}"; then
    if disk_option_flag "${1%%=*}"; then
      disk_cli_hint "option '${1%%=*}' takes no value"
    else
      disk_cli_hint "unknown option '${1%%=*}'"
    fi
    return 1
  fi
  disk_option_value "${1%%=*}" "${1#*=}"
}

disk_cli_option() {
  DISK_CLI_USED=0
  case "$1" in
  --*=*) disk_cli_assign "$1" ;;
  --?*)
    disk_option_flag "$1" && return 0
    if ! disk_cli_takes_value "$1"; then
      disk_cli_hint "unknown option '$1'"
      return 1
    fi
    if [ "$2" -lt 1 ]; then
      disk_cli_hint "option '$1' needs a value"
      return 1
    fi
    DISK_CLI_USED=1
    disk_option_value "$1" "$3"
    ;;
  *)
    disk_cli_hint "unknown option '$1'"
    return 1
    ;;
  esac
}

disk_cli_parse() {
  disk_cp_left="$#"
  disk_cp_literal=0
  while [ "${disk_cp_left}" -gt 0 ]; do
    disk_cp_arg="$1"
    shift
    disk_cp_left=$((disk_cp_left - 1))
    if [ "${disk_cp_literal}" -eq 1 ] || ! disk_cli_is_option "${disk_cp_arg}"; then
      set -- "$@" "${disk_cp_arg}"
    elif [ "${disk_cp_arg}" = "--" ]; then
      disk_cp_literal=1
    else
      disk_cli_option "${disk_cp_arg}" "${disk_cp_left}" "${1:-}" || return 1
      if [ "${DISK_CLI_USED}" -eq 1 ]; then
        shift
        disk_cp_left=$((disk_cp_left - 1))
      fi
    fi
  done
  disk_cli_start "$@"
}
