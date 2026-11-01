#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  disk_test_setup
}

teardown() {
  disk_test_teardown
}

fake_tool() {
  local path="$1"
  local answer="$2"
  mkdir -p "$(dirname "${path}")"
  printf '#!/bin/sh\n{ set +x; } 2>/dev/null\nprintf "%%s\\n" %q\n' "${answer}" >"${path}"
  chmod +x "${path}"
}

@test "a uutils tool is named uutils with its version" {
  # Arrange
  fake_tool "${WORK}/bin/find" "find (uutils findutils) 0.8.0"

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/bin/find"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "uutils 0.8.0" ]]
}

@test "a BusyBox applet is named busybox with its version" {
  # Arrange
  fake_tool "${WORK}/bin/sed" "BusyBox v1.36.1 (2024-03-22) multi-call binary."

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/bin/sed"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "busybox 1.36.1" ]]
}

@test "a GNU tool is named gnu with its version" {
  # Arrange
  fake_tool "${WORK}/bin/find" "find (GNU findutils) 4.10.0"

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/bin/find"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "gnu 4.10.0" ]]
}

@test "mawk is named mawk with its version" {
  # Arrange
  fake_tool "${WORK}/bin/awk" "mawk 1.3.4 20240123"

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/bin/awk"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "mawk 1.3.4" ]]
}

@test "the one true awk is named bsd with its date version" {
  # Arrange
  fake_tool "${WORK}/bin/awk" "awk version 20200816"

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/bin/awk"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "bsd 20200816" ]]
}

@test "a silent tool installed by cargo is named uutils" {
  # Arrange
  fake_tool "${WORK}/cargo/bin/find" ""

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/cargo/bin/find"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "uutils" ]]
}

@test "a silent tool is named after the system it runs on" {
  # Arrange
  local expected=unknown
  [[ "${KATAZUKE_TEST_OS}" == "Darwin" ]] && expected=bsd
  fake_tool "${WORK}/bin/sed" "sed: illegal option -- -"

  # Act
  run disk_test_call disk_tool_flavor "${WORK}/bin/sed"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "a device the user cannot open is reached through sudo" {
  # Arrange
  disk_test_shim sudo 'printf "sudo %s\n" "$*"'

  # Act
  run disk_test_call disk_as_root "${WORK}/no-device" printf 'ran\n'

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "sudo printf ran\n" ]]
}

@test "a folder the user cannot write is cleaned through sudo" {
  # Arrange
  disk_test_shim sudo 'printf "sudo %s\n" "$*"'

  # Act
  run disk_test_call disk_as_owner "${WORK}/no-folder" printf 'ran\n'

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "sudo printf ran\n" ]]
}

@test "one junk file is counted in the singular" {
  # Arrange
  local count=1

  # Act
  run disk_test_call disk_junk_count "${count}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "1 junk file" ]]
}

@test "several junk files are counted in the plural" {
  # Arrange
  local count=7

  # Act
  run disk_test_call disk_junk_count "${count}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "7 junk files" ]]
}

@test "a JSON string escapes quotes, backslashes, control characters and newlines" {
  # Arrange
  local text
  text="$(printf 'a"b\\c\td\ne')"

  # Act
  run disk_test_call disk_json_string "${text}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == '"a\"b\\c\u0009d\ne"' ]]
}

@test "the disk that holds the running system is refused" {
  # Arrange
  local boot
  boot="$(disk_test_call call_first_boot_disk)"
  [[ -n "${boot}" ]] || skip "this system's root has no disk behind it, such as a container overlay"

  # Act
  run disk_test_run check "${boot}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: stopped: ${boot} holds the running system, so it is never changed." ]]
}

@test "an internal disk is refused without --allow-internal" {
  # Arrange
  disk_test_disk fat12 none
  unset KATAZUKE_ALLOW_INTERNAL
  disk_test_shim plutil 'case "$*" in *"Internal raw"*) echo true; exit 0 ;; *"Ejectable raw"*) echo false; exit 0 ;; esac; exec "$REAL" "$@"'
  disk_test_shim lsblk 'case "$*" in *RM,HOTPLUG*) echo "0 0 sata disk"; exit 0 ;; esac; exec "$REAL" "$@"'

  # Act
  run disk_test_run check "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: stopped: ${DEVICE} is an internal disk. use --allow-internal to tidy it on purpose." ]]
}

@test "--allow-internal lets an internal disk through" {
  # Arrange
  disk_test_disk fat12 none
  unset KATAZUKE_ALLOW_INTERNAL
  disk_test_shim plutil 'case "$*" in *"Internal raw"*) echo true; exit 0 ;; *"Ejectable raw"*) echo false; exit 0 ;; esac; exec "$REAL" "$@"'
  disk_test_shim lsblk 'case "$*" in *RM,HOTPLUG*) echo "0 0 sata disk"; exit 0 ;; esac; exec "$REAL" "$@"'

  # Act
  run disk_test_run check --allow-internal "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${DEVICE} is clean: no junk files found." ]]
}

@test "a removable disk passes the internal check without --allow-internal" {
  # Arrange
  disk_test_disk fat12 none
  unset KATAZUKE_ALLOW_INTERNAL

  # Act
  run disk_test_run check "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${DEVICE} is clean: no junk files found." ]]
}

@test "a partition given by name stands for its whole disk" {
  # Arrange
  disk_test_disk fat16 mbr

  # Act
  run disk_test_run check --json "${PART}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"disk\":\"${DEVICE}\","* ]]
}

@test "a working directory that cannot be made stops the run" {
  # Arrange
  disk_test_disk fat12 none
  disk_test_shim mktemp 'exit 1'

  # Act
  run disk_test_run check "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: unable to create a working directory." ]]
}

@test "releasing leaves no volume katazuke mounted" {
  # Arrange
  disk_test_disk fat12 none

  # Act
  run disk_test_call call_release "${PART}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}
