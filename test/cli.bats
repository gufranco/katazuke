#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/katazuke-cli.XXXXXX")"
}

teardown() {
  rm -rf "${WORK}"
}

@test "help prints the usage page on stdout" {
  # Arrange
  local first="katazuke - remove junk files from a FAT or exFAT disk, then sort its folders"

  # Act
  run disk_test_run help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "${first}" ]]
}

@test "-h and --help print the same page as help" {
  # Arrange
  local page long
  page="$(disk_test_run help)"
  long="$(disk_test_run --help)"

  # Act
  run disk_test_run -h

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${page}" ]]
  [[ "${long}" == "${page}" ]]
}

@test "version names the program, its version and the platform" {
  # Arrange
  local version platform
  platform="$(uname -sr)"
  version="$(sed -n 's/^KATAZUKE_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run --version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "katazuke ${version}" ]]
  [[ "${lines[1]}" == "platform: ${platform}" ]]
}

@test "version says unknown when uname cannot name the platform" {
  # Arrange
  disk_test_shim uname 'case "$1" in -sr) exit 1 ;; esac; exec "$REAL" "$@"'

  # Act
  run disk_test_run -V

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[1]}" == "platform: unknown" ]]
}

@test "doctor lists every dependency and passes when all are present" {
  # Arrange
  local state=ok
  disk_test_call disk_fatsort_dated && state=warn

  # Act
  run disk_test_run doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[1]}" == "fatsort            ${state}"* ]]
  [[ "${output}" == *"sudo               ok"* ]]
}

@test "doctor fails and names fatsort when it is missing" {
  # Arrange
  local farm
  farm="$(disk_test_farm fatsort)"

  # Act
  run disk_test_run_path "${farm}" doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${lines[1]}" == "fatsort            missing  required" ]]
}

@test "doctor fails when a platform tool is missing" {
  # Arrange
  local farm tool=diskutil
  [[ "${KATAZUKE_TEST_OS}" == "Darwin" ]] || tool=fsck.vfat
  farm="$(disk_test_farm "${tool}")"

  # Act
  run disk_test_run_path "${farm}" doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"${tool}"*"missing"* ]]
}

@test "doctor still passes without the optional Linux tools" {
  # Arrange
  [[ "${KATAZUKE_TEST_OS}" == "Linux" ]] || skip "the optional rows are Linux only"
  local farm
  farm="$(disk_test_farm fsck.exfat eject)"

  # Act
  run disk_test_run_path "${farm}" doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"fsck.exfat         missing  exfatprogs, needed for exFAT volumes"* ]]
  [[ "${output}" == *"eject              missing  ejects the disk when done"* ]]
}

@test "an unknown option stops with the usage hint" {
  # Arrange
  local expected="katazuke: unknown option '--nope'. run 'katazuke help' for usage."

  # Act
  run disk_test_run --nope /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "an unknown option given a value stops with the usage hint" {
  # Arrange
  local expected="katazuke: unknown option '--nope'. run 'katazuke help' for usage."

  # Act
  run disk_test_run --nope=3 /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "a single-dash option stops with the usage hint" {
  # Arrange
  local expected="katazuke: unknown option '-x'. run 'katazuke help' for usage."

  # Act
  run disk_test_run -x /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "a flag given a value stops with the usage hint" {
  # Arrange
  local expected="katazuke: option '--json' takes no value. run 'katazuke help' for usage."

  # Act
  run disk_test_run --json=y /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "--order without its value stops with the usage hint" {
  # Arrange
  local expected="katazuke: option '--order' needs a value. run 'katazuke help' for usage."

  # Act
  run disk_test_run --order

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "--order with a value it does not know is refused" {
  # Arrange
  local expected="katazuke: --order must be dirs, files or mixed, got: size"

  # Act
  run disk_test_run --order=size /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "an extra argument stops with the usage hint" {
  # Arrange
  local expected="katazuke: unexpected extra argument '/dev/two'. run 'katazuke help' for usage."

  # Act
  run disk_test_run /dev/one /dev/two

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "no disk and no terminal stops with the usage hint" {
  # Arrange
  local expected="katazuke: no disk given. run 'katazuke help' for usage."

  # Act
  run disk_test_run </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "check without a disk and no terminal stops with the usage hint" {
  # Arrange
  local expected="katazuke: no disk given. run 'katazuke help' for usage."

  # Act
  run disk_test_run check --json </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "a path that is neither a device nor a volume is refused" {
  # Arrange
  local expected="katazuke: not a device or a mounted volume: ${WORK}/missing"

  # Act
  run disk_test_run check "${WORK}/missing"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "a folder with no disk behind it is refused" {
  # Arrange
  disk_test_shim diskutil 'exit 1'
  disk_test_shim findmnt 'exit 1'

  # Act
  run disk_test_run check "${WORK}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: no disk found behind ${WORK}." ]]
}

@test "-- lets a disk named like an option through" {
  # Arrange
  local expected="katazuke: not a device or a mounted volume: --json"

  # Act
  run disk_test_run check -- --json

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "the run stops before anything when fatsort is missing" {
  # Arrange
  local farm
  farm="$(disk_test_farm fatsort)"

  # Act
  run disk_test_run_path "${farm}" /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: stopped: fatsort is not installed. run 'katazuke doctor'." ]]
}

@test "an inherited DISK_ variable changes nothing" {
  # Arrange
  local expected="katazuke: unknown option '--nope'. run 'katazuke help' for usage."

  # Act
  DISK_PROG=other run disk_test_run --nope

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "${expected}" ]]
}

called_by_name() {
  local -a shell_words
  read -r -a shell_words <<<"${KATAZUKE_TEST_SHELL:-sh}"
  cd "${REPO_DIR}/bin" && PATH="${REPO_DIR}/bin:${PATH}" "${shell_words[@]}" katazuke version
}

@test "the program runs when called by name from PATH" {
  # Arrange
  local expected="katazuke "

  # Act
  run called_by_name

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "${expected}"* ]]
}
