#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_resolve() {
  disk_rs_input="$1"
  disk_rs_disk=""
  disk_rs_os="$(disk_os)"
  if [ -b "${disk_rs_input}" ] || [ -c "${disk_rs_input}" ]; then
    disk_rs_disk="${disk_rs_input}"
  elif [ -d "${disk_rs_input}" ]; then
    case "${disk_rs_os}" in
    Darwin) disk_rs_disk="$(disk_plist_value "${disk_rs_input}" DeviceNode)" ;;
    *) disk_rs_disk="$(findmnt -n -o SOURCE --target "${disk_rs_input}" 2>/dev/null)" ;;
    esac
    case "${disk_rs_disk}" in
    /dev/*) ;;
    *)
      disk_error "no disk found behind ${disk_rs_input}."
      return 1
      ;;
    esac
  else
    disk_error "not a device or a mounted volume: ${disk_rs_input}"
    return 1
  fi
  disk_whole "${disk_rs_disk}"
}

disk_whole() {
  disk_wh_os="$(disk_os)"
  case "${disk_wh_os}" in
  Darwin)
    disk_wh_parent="$(disk_plist_value "$1" ParentWholeDisk)"
    printf '/dev/%s\n' "${disk_wh_parent:-${1##*/}}"
    ;;
  *)
    disk_wh_parent="$(lsblk -dnro PKNAME "$1" 2>/dev/null)"
    if [ -n "${disk_wh_parent}" ]; then
      printf '/dev/%s\n' "${disk_wh_parent}"
    else
      printf '%s\n' "$1"
    fi
    ;;
  esac
}

disk_boot_disks() {
  disk_bd_os="$(disk_os)"
  case "${disk_bd_os}" in
  Darwin)
    for disk_bd_path in / /System/Volumes/Data; do
      disk_bd_whole="$(disk_plist_value "${disk_bd_path}" ParentWholeDisk)"
      [ -n "${disk_bd_whole}" ] || continue
      printf '/dev/%s\n' "${disk_bd_whole}"
      disk_bd_store="$(disk_plist_value "${disk_bd_whole}" APFSPhysicalStores.0.APFSPhysicalStore)"
      [ -n "${disk_bd_store}" ] || continue
      disk_bd_parent="$(disk_plist_value "${disk_bd_store}" ParentWholeDisk)"
      printf '/dev/%s\n' "${disk_bd_parent}"
    done
    ;;
  *)
    disk_bd_root="$(findmnt -n -o SOURCE / 2>/dev/null)"
    lsblk -nrso NAME,TYPE "${disk_bd_root}" 2>/dev/null | awk '$2 == "disk" { print "/dev/" $1 }'
    ;;
  esac
  return 0
}

disk_listed() {
  printf '%s\n' "$2" | grep -qx -- "$1"
}

disk_is_internal() {
  [ "${KATAZUKE_ALLOW_INTERNAL:-}" = y ] && return 1
  disk_ii_os="$(disk_os)"
  case "${disk_ii_os}" in
  Darwin)
    disk_ii_internal="$(disk_plist_value "$1" Internal)"
    disk_ii_eject="$(disk_plist_value "$1" Ejectable)"
    [ "${disk_ii_internal}" = "true" ] && [ "${disk_ii_eject}" != "true" ]
    ;;
  *)
    disk_ii_flags="$(lsblk -dnro RM,HOTPLUG,TRAN,TYPE "$1" 2>/dev/null)"
    case "${disk_ii_flags}" in
    1\ * | ?\ 1* | *usb* | *mmc* | *loop) return 1 ;;
    *) return 0 ;;
    esac
    ;;
  esac
}

disk_refuse_target() {
  disk_rt_boot="$(disk_boot_disks)"
  if disk_listed "$1" "${disk_rt_boot}"; then
    disk_error "stopped: $1 holds the running system, so it is never changed."
    return 1
  fi
  if disk_is_internal "$1"; then
    disk_error "stopped: $1 is an internal disk. use --allow-internal to tidy it on purpose."
    return 1
  fi
  return 0
}

disk_identity() {
  disk_id_os="$(disk_os)"
  case "${disk_id_os}" in
  Darwin) disk_id_text="$(disk_plist_value "$1" MediaName)" ;;
  *) disk_id_text="$(lsblk -dno VENDOR,MODEL "$1" 2>/dev/null)" ;;
  esac
  printf '%s\n' "${disk_id_text}" | awk '{ $0 = toupper($0); $1 = $1; print }'
}

disk_size_bytes() {
  disk_sz_os="$(disk_os)"
  case "${disk_sz_os}" in
  Darwin) disk_sz_bytes="$(disk_plist_value "$1" TotalSize)" ;;
  *) disk_sz_bytes="$(lsblk -bdno SIZE "$1" 2>/dev/null | tr -d '[:space:]')" ;;
  esac
  disk_is_uint "${disk_sz_bytes}" || disk_sz_bytes=0
  printf '%s\n' "${disk_sz_bytes}"
}

disk_candidates() {
  disk_cn_os="$(disk_os)"
  case "${disk_cn_os}" in
  Darwin)
    disk_cn_list="$(diskutil list 2>/dev/null)"
    printf '%s\n' "${disk_cn_list}" | awk '/^\/dev\/disk[0-9]+ / && !/synthesized/ { print $1 }'
    ;;
  *)
    disk_cn_list="$(lsblk -dnrbo NAME,TYPE,SIZE 2>/dev/null)"
    printf '%s\n' "${disk_cn_list}" | awk '($2 == "disk" || $2 == "loop") && $3 > 0 { print "/dev/" $1 }'
    ;;
  esac
  return 0
}

disk_eligible() {
  disk_el_boot="$(disk_boot_disks)"
  disk_el_all="$(disk_candidates)"
  for disk_el_disk in ${disk_el_all}; do
    disk_listed "${disk_el_disk}" "${disk_el_boot}" && continue
    disk_is_internal "${disk_el_disk}" && continue
    disk_el_parts="$(disk_fat_partitions "${disk_el_disk}")"
    [ -n "${disk_el_parts}" ] && printf '%s\n' "${disk_el_disk}"
  done
  return 0
}

disk_pick() {
  disk_pk_list="$(disk_eligible)"
  if [ -z "${disk_pk_list}" ]; then
    disk_error "no external or removable disk with a FAT or exFAT volume is attached."
    return 1
  fi
  disk_pk_index=0
  disk_pk_lines=""
  for disk_pk_disk in ${disk_pk_list}; do
    disk_pk_index=$((disk_pk_index + 1))
    disk_pk_size="$(disk_size_bytes "${disk_pk_disk}")"
    disk_pk_human="$(disk_human "${disk_pk_size}")"
    disk_pk_id="$(disk_identity "${disk_pk_disk}")"
    disk_pk_lines="${disk_pk_lines:-}$(printf '%-14s %10s  %s|%s' "${disk_pk_disk}" "${disk_pk_human}" "${disk_pk_id}" "${disk_pk_disk}")
"
    disk_ui_prompts || printf '  %d) %-14s %10s  %s\n' "${disk_pk_index}" "${disk_pk_disk}" "${disk_pk_human}" "${disk_pk_id}" >&2
  done
  if disk_ui_prompts; then
    printf '%s' "${disk_pk_lines}" | disk_ui_choose "${1%%\?*}?" --label-delimiter "|"
    return
  fi
  printf '%s' "$1" >&2
  disk_pk_answer=""
  IFS= read -r disk_pk_answer || [ -n "${disk_pk_answer}" ] || return 1
  disk_pick_one "${disk_pk_answer}" "${disk_pk_list}" "${disk_pk_index}"
}

disk_pick_one() {
  if disk_is_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le "$3" ]; then
    printf '%s\n' "$2" | sed -n "$1p"
    return 0
  fi
  for disk_po_disk in $2; do
    if [ "${disk_po_disk}" = "$1" ] || [ "${disk_po_disk##*/}" = "$1" ]; then
      printf '%s\n' "${disk_po_disk}"
      return 0
    fi
  done
  disk_error "not a listed number or disk: $1"
  return 1
}

disk_confirm_names() {
  disk_cf_expected="${1##*/}"
  disk_cf_answer=""
  if disk_ui_prompts; then
    disk_ui_danger "This will $2 everything on ${disk_cf_expected}." "Check the name before you type it."
    disk_cf_answer="$(disk_ui_input "Type ${disk_cf_expected} to $2, or anything else to stop" "${disk_cf_expected}")" || disk_cf_answer=""
  else
    printf 'Type %s to %s, or anything else to stop: ' "${disk_cf_expected}" "$2" >&2
    IFS= read -r disk_cf_answer || true
  fi
  if [ "${disk_cf_answer##*/}" != "${disk_cf_expected}" ]; then
    disk_error "stopped: nothing was changed."
    return 1
  fi
  return 0
}

disk_as_root() {
  if [ -r "$1" ] && [ -w "$1" ]; then
    shift
    "$@"
    return "$?"
  fi
  shift
  sudo "$@"
}

disk_eject() {
  sync
  disk_ej_os="$(disk_os)"
  case "${disk_ej_os}" in
  Darwin) diskutil eject "$1" >/dev/null 2>&1 ;;
  *) disk_as_root "$1" eject "$1" >/dev/null 2>&1 ;;
  esac
}
