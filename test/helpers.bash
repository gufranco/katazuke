#!/usr/bin/env bash

KATAZUKE_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${KATAZUKE_TESTS_DIR}/.." && pwd)"
KATAZUKE_TEST_OS="$(uname -s)"
export KATAZUKE_TESTS_DIR REPO_DIR KATAZUKE_TEST_OS

disk_test_path() {
  local base="${PATH}"
  if [[ "${KATAZUKE_TEST_OS}" == "Darwin" ]]; then
    base="${KATAZUKE_TESTS_DIR}/shim:${PATH}"
  fi
  if [[ -n "${SHIMS:-}" && -d "${SHIMS}" ]]; then
    printf '%s:%s\n' "${SHIMS}" "${base}"
  else
    printf '%s\n' "${base}"
  fi
}

disk_test_shim() {
  local name="$1"
  local body="$2"
  local real
  SHIMS="${SHIMS:-${WORK:?}/shims}"
  mkdir -p "${SHIMS}"
  real="$(PATH="$(disk_test_path_without_shims)" command -v "${name}" || true)"
  printf '#!/bin/sh\n{ set +x; } 2>/dev/null\nREAL=%q\n%s\n' "${real}" "${body}" >"${SHIMS}/${name}.tmp"
  chmod +x "${SHIMS}/${name}.tmp"
  mv -f "${SHIMS}/${name}.tmp" "${SHIMS}/${name}"
  if [[ "${KATAZUKE_TEST_OS}" == "Linux" && ! -e "${SHIMS}/sudo" ]]; then
    disk_test_sudo_passthrough
  fi
  export SHIMS
}

disk_test_path_without_shims() {
  if [[ "${KATAZUKE_TEST_OS}" == "Darwin" ]]; then
    printf '%s:%s\n' "${KATAZUKE_TESTS_DIR}/shim" "${PATH}"
  else
    printf '%s\n' "${PATH}"
  fi
}

disk_test_sudo_passthrough() {
  local real
  real="$(command -v sudo)"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\n{ set +x; } 2>/dev/null\ncase "${1:-}" in\n  -*) exec %q "$@" ;;\nesac\nexec %q env "PATH=$PATH" "$@"\n' "${real}" "${real}" >"${SHIMS}/sudo"
  chmod +x "${SHIMS}/sudo"
}

disk_test_run() {
  local search_path
  local -a shell_words
  search_path="$(disk_test_path)"
  read -r -a shell_words <<<"${KATAZUKE_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${REPO_DIR}/bin/katazuke" "$@"
}

disk_test_run_path() {
  local search_path="$1"
  local -a shell_words
  shift
  read -r -a shell_words <<<"${KATAZUKE_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${REPO_DIR}/bin/katazuke" "$@"
}

disk_test_call() {
  local search_path
  local -a shell_words
  search_path="$(disk_test_path)"
  read -r -a shell_words <<<"${KATAZUKE_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${KATAZUKE_TESTS_DIR}/call.sh" "$@"
}

disk_test_call_path() {
  local search_path="$1"
  local -a shell_words
  shift
  read -r -a shell_words <<<"${KATAZUKE_TEST_SHELL:-sh}"
  PATH="${search_path}" "${shell_words[@]}" "${KATAZUKE_TESTS_DIR}/call.sh" "$@"
}

disk_test_farm_wanted() {
  local farm="$1"
  local tool="$2"
  local name="${2##*/}"
  local excluded
  shift 2
  [[ -x "${tool}" && ! -e "${farm}/${name}" ]] || return 1
  for excluded in "$@"; do
    [[ "${name}" == "${excluded}" ]] && return 1
  done
  return 0
}

disk_test_farm() {
  local farm="${WORK:?}/farm"
  local dir tool search_path
  local -a dirs batch
  mkdir -p "${farm}"
  search_path="$(disk_test_path)"
  IFS=: read -r -a dirs <<<"${search_path}"
  for dir in "${dirs[@]}"; do
    batch=()
    for tool in "${dir}"/*; do
      disk_test_farm_wanted "${farm}" "${tool}" "$@" && batch+=("${tool}")
    done
    [[ ${#batch[@]} -eq 0 ]] || ln -s "${batch[@]}" "${farm}/"
  done
  printf '%s\n' "${farm}"
}

disk_test_answering() {
  local answer="$1"
  shift
  printf '%s\n' "${answer}" | disk_test_run "$@"
}

disk_test_dev_is_devtmpfs() {
  local fs_type
  fs_type="$(findmnt -n -o FSTYPE /dev 2>/dev/null)" || return 1
  [[ "${fs_type}" == "devtmpfs" ]]
}

disk_test_partition_nodes_start() {
  [[ "${KATAZUKE_TEST_OS}" == "Linux" ]] || return 0
  disk_test_dev_is_devtmpfs && return 0
  (
    tries=0
    while [[ "${tries}" -lt 3000 ]]; do
      for part in /sys/block/loop*/loop*p*; do
        [[ -e "${part}/dev" ]] || continue
        node="/dev/${part##*/}"
        IFS=: read -r major minor <"${part}/dev"
        current="$(stat -c '%t:%T' "${node}" 2>/dev/null || true)"
        wanted="$(printf '%x:%x' "${major}" "${minor}")"
        [[ "${current}" == "${wanted}" ]] && continue
        sudo rm -f "${node}.new"
        if sudo mknod -m 660 "${node}.new" b "${major}" "${minor}" 2>/dev/null; then
          sudo mv -f "${node}.new" "${node}" || true
        fi
      done
      sleep 0.2
      tries=$((tries + 1))
    done
  ) &
  PARTITION_NODES_PID="$!"
}

disk_test_partition_nodes_stop() {
  [[ -n "${PARTITION_NODES_PID:-}" ]] || return 0
  kill "${PARTITION_NODES_PID}" 2>/dev/null || true
  wait "${PARTITION_NODES_PID}" 2>/dev/null || true
  PARTITION_NODES_PID=""
}

disk_test_partition_ready() {
  local node="$1"
  local sysfs="/sys/class/block/${node##*/}/dev"
  local major minor current wanted
  [[ -b "${node}" ]] || return 1
  [[ "${KATAZUKE_TEST_OS}" == "Linux" ]] || return 0
  [[ -r "${sysfs}" ]] || return 1
  IFS=: read -r major minor <"${sysfs}"
  current="$(stat -c '%t:%T' "${node}" 2>/dev/null)" || return 1
  wanted="$(printf '%x:%x' "${major}" "${minor}")"
  [[ "${current}" == "${wanted}" ]]
}

disk_test_wait_node() {
  local node="$1"
  local delay
  for delay in 0.01 0.02 0.05 0.1 0.2 0.4 0.8 1.6 3.2 3.2 3.2; do
    disk_test_partition_ready "${node}" && return 0
    sleep "${delay}"
  done
  disk_test_partition_ready "${node}"
}

disk_test_format_linux() {
  local kind="$1"
  local target="$2"
  local label="$3"
  case "${kind}" in
  fat12) sudo mkfs.fat -F 12 -n "${label}" "${target}" >/dev/null ;;
  fat16) sudo mkfs.fat -F 16 -n "${label}" "${target}" >/dev/null ;;
  fat32) sudo mkfs.fat -F 32 -n "${label}" "${target}" >/dev/null ;;
  exfat) sudo mkfs.exfat -L "${label}" "${target}" >/dev/null ;;
  *) sudo mkfs.ext4 -q -L "${label}" "${target}" >/dev/null ;;
  esac
}

disk_test_darwin_fs() {
  case "$1" in
  fat12) printf 'MS-DOS FAT12\n' ;;
  fat16) printf 'MS-DOS FAT16\n' ;;
  fat32) printf 'MS-DOS FAT32\n' ;;
  exfat) printf 'ExFAT\n' ;;
  *) printf 'JHFS+\n' ;;
  esac
}

disk_test_size() {
  case "$1" in
  fat32) printf '64\n' ;;
  fat12) printf '4\n' ;;
  *) printf '32\n' ;;
  esac
}

disk_test_attach_darwin() {
  local listing
  listing="$(hdiutil attach -nomount "$1")" || return 1
  printf '%s\n' "${listing%%[[:space:]]*}"
}

disk_test_disk() {
  local kind="$1"
  local layout="$2"
  local label="${3:-KTZ}"
  local image="${WORK:?}/disk.dmg"
  local size
  size="$(disk_test_size "${kind}")"
  case "${KATAZUKE_TEST_OS}" in
  Darwin)
    local fs
    fs="$(disk_test_darwin_fs "${kind}")"
    if [[ "${layout}" == none ]]; then
      hdiutil create -quiet -size "${size}m" -fs "${fs}" -volname "${label}" -layout NONE "${image}" || return 1
    else
      hdiutil create -quiet -size "${size}m" -fs "${fs}" -volname "${label}" -layout MBRSPUD "${image}" || return 1
    fi
    DEVICE="$(disk_test_attach_darwin "${image}")" || return 1
    if [[ "${layout}" == none ]]; then
      PART="${DEVICE}"
    else
      PART="${DEVICE}s1"
    fi
    ;;
  Linux)
    image="${WORK}/disk.img"
    dd if=/dev/zero of="${image}" bs=1048576 count="${size}" 2>/dev/null || return 1
    if [[ "${layout}" == none ]]; then
      DEVICE="$(sudo losetup -f --show "${image}")" || return 1
      PART="${DEVICE}"
    else
      printf 'start=2048, type=c\n' | sfdisk -q "${image}" >/dev/null || return 1
      DEVICE="$(sudo losetup -f -P --show "${image}")" || return 1
      PART="${DEVICE}p1"
      disk_test_wait_node "${PART}" || return 1
    fi
    disk_test_format_linux "${kind}" "${PART}" "${label}" || return 1
    ;;
  *) return 1 ;;
  esac
  export DEVICE PART
}

disk_test_need_exfat() {
  [[ "${KATAZUKE_TEST_OS}" == "Linux" ]] || return 0
  grep -qw exfat /proc/filesystems && return 0
  sudo modprobe exfat >/dev/null 2>&1 || true
  grep -qw exfat /proc/filesystems || skip "this kernel cannot mount exFAT"
}

disk_test_two_volumes() {
  local image="${WORK:?}/two.dmg"
  case "${KATAZUKE_TEST_OS}" in
  Darwin)
    hdiutil create -quiet -size 128m -layout NONE "${image}" || return 1
    DEVICE="$(disk_test_attach_darwin "${image}")" || return 1
    diskutil partitionDisk "${DEVICE}" MBR "MS-DOS FAT32" ONE 64M ExFAT TWO R >/dev/null || return 1
    diskutil unmountDisk "${DEVICE}" >/dev/null || return 1
    PART="${DEVICE}s1"
    PART2="${DEVICE}s2"
    ;;
  Linux)
    image="${WORK}/two.img"
    dd if=/dev/zero of="${image}" bs=1048576 count=128 2>/dev/null || return 1
    printf 'start=2048, size=131072, type=c\nstart=133120, type=7\n' | sfdisk -q "${image}" >/dev/null || return 1
    DEVICE="$(sudo losetup -f -P --show "${image}")" || return 1
    PART="${DEVICE}p1"
    PART2="${DEVICE}p2"
    disk_test_wait_node "${PART}" || return 1
    disk_test_wait_node "${PART2}" || return 1
    disk_test_format_linux fat32 "${PART}" ONE || return 1
    disk_test_format_linux exfat "${PART2}" TWO || return 1
    ;;
  *) return 1 ;;
  esac
  export DEVICE PART PART2
}

disk_test_mount() {
  local part="$1"
  local mode="$2"
  local point plist uid gid
  case "${KATAZUKE_TEST_OS}" in
  Darwin)
    if [[ "${mode}" == ro ]]; then
      diskutil mount readOnly "${part}" >/dev/null || return 1
    else
      diskutil mount "${part}" >/dev/null || return 1
    fi
    plist="$(diskutil info -plist "${part}")" || return 1
    point="$(plutil -extract MountPoint raw - <<<"${plist}")" || return 1
    ;;
  *)
    point="${WORK:?}/mnt-${part##*/}"
    uid="$(id -u)"
    gid="$(id -g)"
    mkdir -p "${point}"
    sudo mount -o "${mode},uid=${uid},gid=${gid}" "${part}" "${point}" || return 1
    ;;
  esac
  printf '%s\n' "${point}"
}

disk_test_unmount() {
  case "${KATAZUKE_TEST_OS}" in
  Darwin) diskutil unmount "$1" >/dev/null 2>&1 || true ;;
  *) sudo umount "$1" 2>/dev/null || true ;;
  esac
}

disk_test_populate() {
  local part="$1"
  local point entry
  shift
  point="$(disk_test_mount "${part}" rw)" || return 1
  for entry in "$@"; do
    if [[ "${entry}" == */ ]]; then
      mkdir -p "${point}/${entry}"
    else
      mkdir -p "$(dirname "${point}/${entry}")"
      printf 'x' >"${point}/${entry}"
    fi
  done
  sync
  disk_test_unmount "${part}"
}

disk_test_names() {
  local part="$1"
  local point listing sorted line
  point="$(disk_test_mount "${part}" ro)" || return 1
  listing="$(cd "${point}" && find . -mindepth 1)" || return 1
  disk_test_unmount "${part}"
  sorted="$(printf '%s\n' "${listing}" | LC_ALL=C sort)"
  while IFS= read -r line; do
    printf '%s\n' "${line#.}"
  done <<<"${sorted}"
}

disk_test_order() {
  local part="$1"
  disk_test_unmount "${part}"
  case "${KATAZUKE_TEST_OS}" in
  Darwin) LC_ALL=C.UTF-8 fatsort -l "${part}" 2>/dev/null ;;
  *) sudo env LC_ALL=C.UTF-8 fatsort -l "${part}" 2>/dev/null ;;
  esac
}

disk_test_root_order() {
  local listing
  listing="$(disk_test_order "$1")" || return 1
  printf '%s\n' "${listing}" | awk 'NR > 3 && NF == 0 { exit } NR > 3 { print }'
}

disk_test_corrupt_fat() {
  local part="$1"
  local root=""
  local sector reserved
  disk_test_unmount "${part}"
  [[ "${KATAZUKE_TEST_OS}" == "Linux" ]] && root=sudo
  sector="$(${root} od -An -tu2 -j11 -N2 "${part}")" || return 1
  reserved="$(${root} od -An -tu2 -j14 -N2 "${part}")" || return 1
  sector="${sector//[[:space:]]/}"
  reserved="${reserved//[[:space:]]/}"
  printf '\377\377\377\377\377\377\377\377' |
    ${root} dd of="${part}" bs=1 seek=$((sector * reserved + 64)) conv=notrunc 2>/dev/null
}

disk_test_detach() {
  [[ -n "${DEVICE:-}" ]] || return 0
  case "${KATAZUKE_TEST_OS}" in
  Darwin) hdiutil detach -force "${DEVICE}" >/dev/null 2>&1 || true ;;
  *)
    sudo umount "${DEVICE}"* >/dev/null 2>&1 || true
    sudo losetup -d "${DEVICE}" >/dev/null 2>&1 || true
    if [[ ! -S /run/udev/control && "${DEVICE}" == /dev/loop* ]]; then
      sudo rm -f "${DEVICE}"p[0-9]*
    fi
    ;;
  esac
  DEVICE=""
}

disk_test_setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/katazuke.XXXXXX")"
  export WORK
  if [[ "${KATAZUKE_TEST_OS}" == "Linux" ]]; then
    export KATAZUKE_ALLOW_INTERNAL=y
  fi
  disk_test_partition_nodes_start
}

disk_test_teardown() {
  disk_test_detach
  disk_test_partition_nodes_stop
  rm -rf "${WORK:?}"
}

disk_test_normalize() {
  sh "${KATAZUKE_TESTS_DIR}/normalize.sh"
}

disk_test_matches_golden() {
  local name="$1"
  local actual="$2"
  local golden="${KATAZUKE_TESTS_DIR}/golden/${name}.${KATAZUKE_TEST_OS}.txt"
  local normalized

  normalized="$(printf '%s\n' "${actual}" | disk_test_normalize)" || return 1
  if [[ "${KATAZUKE_TEST_RECORD:-}" == "1" ]]; then
    printf '%s\n' "${normalized}" >"${golden}.tmp"
    mv -f "${golden}.tmp" "${golden}"
  fi

  diff <(printf '%s\n' "${normalized}") "${golden}"
}
