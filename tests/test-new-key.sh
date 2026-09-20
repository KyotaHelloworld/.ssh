#!/usr/bin/env bash
set -Eeuo pipefail

help() {
  cat <<'EOF'
Purpose: Run isolated regression tests for the SSH key/config generator.
Inputs: The repository's Makefile and shells/new-key.sh.
Changes: Creates and removes a temporary fixture below TMPDIR. The repository is
         read-only during the test.
Example: ./tests/test-new-key.sh

Usage: test-new-key.sh [options]

Options:
  -h, --help  Show this help.

Exit behavior:
  Returns zero when all assertions pass and non-zero on the first failure.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly PROJECT_ROOT

TEMP_ROOT=""
FIXTURE_ROOT=""

die() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command not found: ${command_name}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || die "expected file: ${path}"
}

assert_contains() {
  local expected="$1"
  local path="$2"
  grep -Fqx -- "${expected}" "${path}" ||
    die "missing line '${expected}' in ${path}"
}

assert_not_contains() {
  local unexpected="$1"
  local path="$2"
  if grep -Fq -- "${unexpected}" "${path}"; then
    die "unexpected text '${unexpected}' in ${path}"
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  [[ "${actual}" == "${expected}" ]] ||
    die "expected '${expected}', got '${actual}'"
}

assert_public_key_comment() {
  local expected="$1"
  local path="$2"
  local key_type
  local key_data
  local actual

  IFS=' ' read -r key_type key_data actual <"${path}" ||
    die "could not read public key: ${path}" || return 1
  [[ -n "${key_type}" && -n "${key_data}" ]] ||
    die "malformed public key: ${path}" || return 1
  assert_equals "${expected}" "${actual}"
}

assert_mode() {
  local expected="$1"
  local path="$2"
  local actual
  actual="$(stat -c '%a' -- "${path}")"
  [[ "${actual}" == "${expected}" ]] ||
    die "expected mode ${expected}, got ${actual}: ${path}"
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    die "command unexpectedly succeeded: $*"
  fi
}

create_fixture_at() {
  local fixture_path="$1"
  mkdir -p -- "${fixture_path}/shells" "${fixture_path}/keys" "${fixture_path}/config.d"
  cp -- "${PROJECT_ROOT}/Makefile" "${fixture_path}/Makefile"
  cp -- "${PROJECT_ROOT}/shells/new-key.sh" "${fixture_path}/shells/new-key.sh"
  chmod 755 -- "${fixture_path}/shells/new-key.sh"
}

create_fixture() {
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ssh-new-key-test.XXXXXXXX")"
  FIXTURE_ROOT="${TEMP_ROOT}/repo"
  create_fixture_at "${FIXTURE_ROOT}"
}

test_complete_generation() {
  (
    cd -- "${FIXTURE_ROOT}"
    make --no-print-directory new-key-github \
      NO_PASSPHRASE=1 \
      HOST_NAME=github.com \
      REMOTE_USER=git \
      SSH_PORT=2222 >/dev/null
  )

  local private_key="${FIXTURE_ROOT}/keys/github/id"
  local public_key="${private_key}.pub"
  local fragment="${FIXTURE_ROOT}/config.d/github.conf"
  assert_file "${private_key}"
  assert_file "${public_key}"
  assert_file "${fragment}"
  assert_mode 600 "${private_key}"
  assert_mode 644 "${public_key}"
  assert_mode 600 "${fragment}"
  ssh-keygen -lf "${public_key}" >/dev/null
  assert_public_key_comment "$(id -un)@$(hostname)" "${public_key}"
  assert_contains "Host github" "${fragment}"
  assert_contains "    HostName github.com" "${fragment}"
  assert_contains "    User git" "${fragment}"
  assert_contains "    Port 2222" "${fragment}"
  assert_contains "    IdentityFile ~/.ssh/keys/github/id" "${fragment}"
  assert_contains "    IdentitiesOnly yes" "${fragment}"

  local resolved_config
  resolved_config="$(ssh -G -F "${fragment}" github 2>/dev/null)"
  grep -Fqx 'hostname github.com' <<<"${resolved_config}" || die "HostName was not applied"
  grep -Fqx 'user git' <<<"${resolved_config}" || die "User was not applied"
  grep -Fqx 'port 2222' <<<"${resolved_config}" || die "Port was not applied"
  grep -Fqx 'identitiesonly yes' <<<"${resolved_config}" || die "IdentitiesOnly was not applied"
}

test_interactive_make_generation() {
  local prompt_output
  prompt_output="$(
    printf '%s\n' deploy server.example.com |
      make -C "${FIXTURE_ROOT}" --no-print-directory \
        new-key-conoha NO_PASSPHRASE=1 2>&1 >/dev/null
  )"

  assert_equals "Login user name: IP address or domain: " "${prompt_output}"
  assert_file "${FIXTURE_ROOT}/keys/conoha/id"
  assert_contains "Host conoha" "${FIXTURE_ROOT}/config.d/conoha.conf"
  assert_contains "    HostName server.example.com" "${FIXTURE_ROOT}/config.d/conoha.conf"
  assert_contains "    User deploy" "${FIXTURE_ROOT}/config.d/conoha.conf"
}

test_preseeded_values_skip_prompts() {
  local preset_root="${TEMP_ROOT}/preset-repo"
  local prompt_output
  create_fixture_at "${preset_root}"

  prompt_output="$(
    make -C "${preset_root}" --no-print-directory \
      new-key-conoha \
      NO_PASSPHRASE=1 \
      HOST_NAME=198.51.100.7 \
      REMOTE_USER=root 2>&1 >/dev/null
  )"

  assert_equals "" "${prompt_output}"
  assert_contains "    HostName 198.51.100.7" "${preset_root}/config.d/conoha.conf"
  assert_contains "    User root" "${preset_root}/config.d/conoha.conf"

  make -C "${preset_root}" --no-print-directory \
    new-key-ipv6 \
    NO_PASSPHRASE=1 \
    HOST_NAME=::1 \
    REMOTE_USER=root >/dev/null
  assert_contains "    HostName ::1" "${preset_root}/config.d/ipv6.conf"
}

test_partial_preseed_skips_one_prompt() {
  local partial_root="${TEMP_ROOT}/partial-preset-repo"
  local prompt_output
  create_fixture_at "${partial_root}"

  prompt_output="$(
    printf '%s\n' app-user |
      make -C "${partial_root}" --no-print-directory \
        new-key-partial \
        NO_PASSPHRASE=1 \
        HOST_NAME=partial.example 2>&1 >/dev/null
  )"

  assert_equals "Login user name: " "${prompt_output}"
  assert_contains "    HostName partial.example" "${partial_root}/config.d/partial.conf"
  assert_contains "    User app-user" "${partial_root}/config.d/partial.conf"
}

test_incomplete_interactive_input_leaves_no_output() {
  local failure_root="${TEMP_ROOT}/prompt-failure-repo"
  create_fixture_at "${failure_root}"

  if printf '%s\n' deploy |
    make -C "${failure_root}" --no-print-directory \
      new-key-conoha NO_PASSPHRASE=1 >/dev/null 2>&1; then
    die "ConoHa generation unexpectedly accepted incomplete input"
  fi
  [[ ! -e "${failure_root}/keys/conoha" ]] ||
    die "incomplete input created a key directory"
  [[ ! -e "${failure_root}/config.d/conoha.conf" ]] ||
    die "incomplete input created a config fragment"

  if printf '%s\n' deploy 'invalid domain' |
    make -C "${failure_root}" --no-print-directory \
      new-key-invalid-address NO_PASSPHRASE=1 >/dev/null 2>&1; then
    die "key generation unexpectedly accepted an invalid connection address"
  fi
  [[ ! -e "${failure_root}/keys/invalid-address" ]] ||
    die "invalid connection input created a key directory"
}

test_default_generation_resumes() {
  local github_key="${FIXTURE_ROOT}/keys/github/id"
  local github_hash_before
  github_hash_before="$(sha256sum -- "${github_key}")"

  printf '%s\n' forgejo-user forgejo.example |
    make -C "${FIXTURE_ROOT}" --no-print-directory \
      new-key-default NO_PASSPHRASE=1 >/dev/null 2>&1

  [[ "$(sha256sum -- "${github_key}")" == "${github_hash_before}" ]] ||
    die "default generation replaced an existing key"
  assert_file "${FIXTURE_ROOT}/keys/forgejo/id"
  assert_file "${FIXTURE_ROOT}/config.d/forgejo.conf"
}

test_minimal_generation() {
  "${FIXTURE_ROOT}/shells/new-key.sh" --no-passphrase internal >/dev/null

  local fragment="${FIXTURE_ROOT}/config.d/internal.conf"
  assert_file "${fragment}"
  assert_contains "Host internal" "${fragment}"
  assert_contains "    IdentityFile ~/.ssh/keys/internal/id" "${fragment}"
  assert_contains "    IdentitiesOnly yes" "${fragment}"
  assert_not_contains "HostName" "${fragment}"
  assert_not_contains "User " "${fragment}"
  assert_not_contains "Port " "${fragment}"
}

test_direct_cli_generation() {
  "${FIXTURE_ROOT}/shells/new-key.sh" \
    --no-passphrase \
    --key-file cli.id \
    --comment 'fixture CLI key' \
    cli >/dev/null

  assert_file "${FIXTURE_ROOT}/keys/cli/cli.id"
  assert_file "${FIXTURE_ROOT}/keys/cli/cli.id.pub"
  assert_public_key_comment \
    "fixture CLI key" \
    "${FIXTURE_ROOT}/keys/cli/cli.id.pub"
  assert_contains \
    "    IdentityFile ~/.ssh/keys/cli/cli.id" \
    "${FIXTURE_ROOT}/config.d/cli.conf"
}

test_rejects_existing_outputs() {
  local private_key="${FIXTURE_ROOT}/keys/github/id"
  local fragment="${FIXTURE_ROOT}/config.d/github.conf"
  local key_hash_before
  local config_hash_before
  key_hash_before="$(sha256sum -- "${private_key}")"
  config_hash_before="$(sha256sum -- "${fragment}")"

  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-github NO_PASSPHRASE=1

  [[ "$(sha256sum -- "${private_key}")" == "${key_hash_before}" ]] ||
    die "existing private key changed"
  [[ "$(sha256sum -- "${fragment}")" == "${config_hash_before}" ]] ||
    die "existing config changed"
}

test_rejects_injection_and_invalid_values() {
  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    'new-key-bad;touch-injected' NO_PASSPHRASE=1
  [[ ! -e "${FIXTURE_ROOT}/touch-injected" ]] || die "target name executed as shell code"
  [[ ! -e "${FIXTURE_ROOT}/keys/bad" ]] || die "invalid target created a key directory"

  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-invalid NO_PASSPHRASE=1 KEY_TYPE=dsa
  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-invalid NO_PASSPHRASE=1 SSH_PORT=70000
  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-invalid NO_PASSPHRASE=1 SSH_PORT=18446744073709551617
}

test_config_collision_leaves_no_key() {
  : >"${FIXTURE_ROOT}/config.d/collision.conf"
  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-collision NO_PASSPHRASE=1
  [[ ! -e "${FIXTURE_ROOT}/keys/collision" ]] ||
    die "config collision left a partial key directory"
}

test_legacy_variables() {
  make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-legacy \
    NO_PASSPHRASE=1 \
    CT=rsa \
    FN=legacy.id \
    HOST_NAME=legacy.example \
    REMOTE_USER=legacy >/dev/null
  assert_file "${FIXTURE_ROOT}/keys/legacy/legacy.id"
  ssh-keygen -lf "${FIXTURE_ROOT}/keys/legacy/legacy.id.pub" |
    grep -Fq '(RSA)' || die "legacy CT variable did not select RSA"

  expect_failure make -C "${FIXTURE_ROOT}" --no-print-directory \
    new-key-legacy-pp NO_PASSPHRASE=1 PP=should-be-rejected
  [[ ! -e "${FIXTURE_ROOT}/keys/legacy-pp" ]] ||
    die "legacy PP variable created output"
}

test_rejects_symlinked_output_root() {
  local symlink_root="${TEMP_ROOT}/symlink-repo"
  local external_keys="${TEMP_ROOT}/external-keys"
  mkdir -p -- "${symlink_root}/shells" "${symlink_root}/config.d" "${external_keys}"
  cp -- "${PROJECT_ROOT}/Makefile" "${symlink_root}/Makefile"
  cp -- "${PROJECT_ROOT}/shells/new-key.sh" "${symlink_root}/shells/new-key.sh"
  chmod 755 -- "${symlink_root}/shells/new-key.sh"
  ln -s -- "${external_keys}" "${symlink_root}/keys"

  expect_failure make -C "${symlink_root}" --no-print-directory \
    new-key-symlink NO_PASSPHRASE=1
  [[ -z "$(find "${external_keys}" -mindepth 1 -print -quit)" ]] ||
    die "symlinked output root received files"
}

cleanup() {
  local exit_code=$?

  if [[ -n "${TEMP_ROOT}" && -d "${TEMP_ROOT}" ]]; then
    rm -rf -- "${TEMP_ROOT}"
  fi
  return "${exit_code}"
}

run() {
  require_command make || return 1
  require_command find || return 1
  require_command grep || return 1
  require_command hostname || return 1
  require_command id || return 1
  require_command ln || return 1
  require_command mktemp || return 1
  require_command ssh || return 1
  require_command ssh-keygen || return 1
  require_command sha256sum || return 1
  require_command stat || return 1
  create_fixture
  test_complete_generation
  test_interactive_make_generation
  test_preseeded_values_skip_prompts
  test_partial_preseed_skips_one_prompt
  test_incomplete_interactive_input_leaves_no_output
  test_default_generation_resumes
  test_minimal_generation
  test_direct_cli_generation
  test_rejects_existing_outputs
  test_rejects_injection_and_invalid_values
  test_config_collision_leaves_no_key
  test_legacy_variables
  test_rejects_symlinked_output_root
  printf 'PASS: SSH key/config generator\n'
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    return 0
  fi
  (($# == 0)) || die "unknown argument: $1" || return 1

  run
}

trap cleanup EXIT
main "$@"
