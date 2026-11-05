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
  page="$(disk_test_run help)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "version never prints a line wider than 80 columns" {
  # Arrange
  local page widest

  # Act
  page="$(disk_test_run version)"

  # Assert
  widest="$(printf '%s\n' "${page}" | widest_line)"
  [[ "${widest}" -le 80 ]]
}

@test "an error stays on one line, however long" {
  # Arrange
  local message="could not unmount /dev/disk4s1. close anything using /Volumes/EZFLASH and try again."

  # Act
  run disk_test_call disk_error "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "katazuke: ${message}" ]]
}

@test "a doctor row stays on one line, however long" {
  # Arrange
  local note="/opt/homebrew/opt/uutils-findutils/libexec/uubin/find, uutils 0.8.0 and a long note"

  # Act
  run disk_test_call disk_doctor_row find ok "${note}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "find               ok       ${note}" ]]
}
