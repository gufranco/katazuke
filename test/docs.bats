#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

help_options() {
  local page found
  page="$(disk_test_run help)"
  found="$(grep -oE -- '--[a-z][a-z-]+' <<<"${page}")" || return 1
  printf '%s\n' "${found}" | LC_ALL=C sort -u
}

missing_from() {
  local text="$1"
  local options option
  options="$(help_options)" || return 1
  while IFS= read -r option; do
    [[ "${text}" == *"${option}"* ]] || printf '%s\n' "${option}"
  done <<<"${options}"
}

@test "the man page names every option the help page lists" {
  # Arrange
  local page
  page="$(sed 's/\\//g' "${REPO_DIR}/man/katazuke.1")"

  # Act
  run missing_from "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "the zsh completion names every option the help page lists" {
  # Arrange
  local page
  page="$(<"${REPO_DIR}/completions/_katazuke")"

  # Act
  run missing_from "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "the bash completion names every option the help page lists" {
  # Arrange
  local page
  page="$(<"${REPO_DIR}/completions/katazuke.bash")"

  # Act
  run missing_from "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "the fish completion names every option the help page lists" {
  # Arrange
  local page
  page="$(sed -E 's/-l ([a-z-]+)/--\1/g' "${REPO_DIR}/completions/katazuke.fish")"

  # Act
  run missing_from "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

commands_without_completion() {
  local page zsh_page bash_page fish_page command
  page="$(disk_test_run help)"
  zsh_page="$(<"${REPO_DIR}/completions/_katazuke")"
  bash_page="$(<"${REPO_DIR}/completions/katazuke.bash")"
  fish_page="$(<"${REPO_DIR}/completions/katazuke.fish")"
  for command in check doctor version help; do
    [[ "${page}" == *"katazuke ${command}"* ]] || printf 'help lacks %s\n' "${command}"
    [[ "${zsh_page}" == *"'${command}:"* ]] || printf 'zsh lacks %s\n' "${command}"
    [[ "${bash_page}" == *"${command} "* ]] || printf 'bash lacks %s\n' "${command}"
    [[ "${fish_page}" == *"-a ${command} "* ]] || printf 'fish lacks %s\n' "${command}"
  done
}

@test "every command the help page lists has a completion" {
  # Arrange
  local expected=""

  # Act
  run commands_without_completion

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
}
