#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/katazuke-width.XXXXXX")"
}

teardown() {
  rm -rf "${WORK}"
}

widest_line() {
  awk '{ if (length($0) > widest) { widest = length($0) } } END { print widest + 0 }'
}

@test "help never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(KATAZUKE_TERMINAL=1 disk_test_run help)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "version never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(KATAZUKE_TERMINAL=1 disk_test_run version)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "an error longer than 80 columns wraps between words on a terminal" {
  # Arrange
  local message="could not unmount /dev/disk4s1. close anything using /Volumes/EZFLASH and try again."

  # Act
  KATAZUKE_TERMINAL=1 run disk_test_call disk_error "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${#lines[@]}" -eq 2 ]]
  [[ "${lines[0]}" == "katazuke: could not unmount /dev/disk4s1. close anything using /Volumes/EZFLASH" ]]
  [[ "${lines[1]}" == "and try again." ]]
}

@test "an error sent to a pipe stays on one line, however long" {
  # Arrange
  local message="could not unmount /dev/disk4s1. close anything using /Volumes/EZFLASH and try again."

  # Act
  run disk_test_call disk_error "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "katazuke: ${message}" ]]
}

@test "a summary value wider than 80 columns continues under its label" {
  # Arrange
  local volume="/Volumes/The-Family-Archive-Of-Every-Scanned-Letter-And-Photograph-1968-To-1985"

  # Act
  KATAZUKE_TERMINAL=1 run disk_test_call disk_info "Volume: ${volume}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "Volume:" ]]
  [[ "${lines[1]}" == "        ${volume}" ]]
}

@test "a doctor row stays on one line on a terminal, however long" {
  # Arrange
  local note="/opt/homebrew/opt/uutils-findutils/libexec/uubin/find, uutils 0.8.0 and a long note"

  # Act
  KATAZUKE_TERMINAL=1 run disk_test_call disk_doctor_row find ok "${note}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "find               ok       ${note}" ]]
}
