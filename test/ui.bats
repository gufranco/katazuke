#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  disk_test_setup
  unset KODOUGU_THEME KODOUGU_ACCENT KATAZUKE_THEME NO_COLOR
  export KATAZUKE_TEST_GUM=1
  export KATAZUKE_TEST_GUM_LOG="${WORK}/gum.log"
  export KATAZUKE_TEST_GUM_ANSWERS="${WORK}/answers"
  export KATAZUKE_INTERACTIVE=1
  : >"${KATAZUKE_TEST_GUM_LOG}"
}

teardown() {
  disk_test_teardown
}

answers() {
  printf '%s\n' "$@" >"${KATAZUKE_TEST_GUM_ANSWERS}"
}

called() {
  grep -q -F -- "$1" "${KATAZUKE_TEST_GUM_LOG}"
}

@test "the disk is picked from a gum list" {
  # Arrange
  disk_test_disk fat32 none
  answers "${DEVICE}"

  # Act
  run disk_test_run check </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${DEVICE} is clean: no junk files found."* ]]
  [[ "${output}" == *"remove junk files from a FAT or exFAT disk"* ]]
  called "choose --header Tidy which disk?"
}

@test "a cancelled disk pick stops the run" {
  # Arrange
  disk_test_disk fat32 none
  answers "<cancel>"

  # Act
  run disk_test_run check </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "a tidy run shows the summary box and asks for the name inside a danger box" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "GAME.TXT" ".DS_Store"
  answers "${DEVICE##*/}"

  # Act
  run disk_test_run --no-eject "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk:"*"${DEVICE}"* ]]
  [[ "${output}" == *"Plan:"*"remove junk files"* ]]
  [[ "${output}" == *"Done. ${DEVICE} is tidy and still attached."* ]]
  called "--border thick"
  called "input --header Type ${DEVICE##*/} to tidy"
}

@test "a disk that will not eject is drawn as a warning" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_shim diskutil 'case "$1" in eject) exit 1 ;; esac; exec "$REAL" "$@"'
  disk_test_shim eject 'exit 1'
  answers "${DEVICE##*/}"

  # Act
  run disk_test_run "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"WARN katazuke: ${DEVICE} did not eject. it is already tidy, so remove it once it is idle."* ]]
}

@test "a wrong name typed into gum changes nothing" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" ".DS_Store"
  answers "disk999"

  # Act
  run disk_test_run --no-eject "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR katazuke: stopped: nothing was changed."* ]]
}

@test "a cancelled typed name changes nothing" {
  # Arrange
  disk_test_disk fat32 none
  answers "<cancel>"

  # Act
  run disk_test_run --no-eject "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: nothing was changed."* ]]
}

@test "doctor draws its rows in a table" {
  # Arrange
  local expected="katazuke"

  # Act
  run disk_test_run doctor </dev/null

  # Assert
  [[ "${output}" == *"Tool"*"State"*"Detail"* ]]
  [[ "${output}" == *"${expected}"* ]]
}

@test "doctor reports a missing tool below the table" {
  # Arrange
  local farm
  farm="$(disk_test_farm fatsort)"

  # Act
  run disk_test_run_path "${farm}" doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR katazuke: a required tool is missing."* ]]
}

@test "doctor fails without gum" {
  # Arrange
  local farm
  farm="$(disk_test_farm gum)"

  # Act
  KATAZUKE_TEST_GUM=0 run disk_test_run_path "${farm}" doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"gum                missing  install with: brew install gum"* ]]
}

@test "version shows the version and platform as badges" {
  # Arrange
  local version
  version="$(sed -n 's/^KATAZUKE_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "katazuke ${version} platform "* ]]
}

@test "help is formatted with gum" {
  # Arrange
  local expected="## Usage"

  # Act
  run disk_test_run help </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
  called "format --theme pink"
}

@test "--theme picks the palette over the environment" {
  # Arrange
  local theme="nord"

  # Act
  KODOUGU_THEME=dracula KATAZUKE_THEME=gruvbox run disk_test_run --theme "${theme}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #88C0D0"
}

@test "--theme= with a value picks the palette" {
  # Arrange
  local option="--theme=tokyo-night"

  # Act
  run disk_test_run "${option}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #7AA2F7"
}

@test "an unknown theme stops before anything runs" {
  # Arrange
  local theme="solarized"

  # Act
  KODOUGU_THEME="${theme}" run disk_test_run check /dev/null </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"got: solarized"* ]]
}

@test "--theme without a value stops with the usage hint" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run version "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"option '--theme' needs a value. run 'katazuke help' for usage."* ]]
}

@test "--theme after -- is left to the command line" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run check -- "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"--theme"* ]]
}
