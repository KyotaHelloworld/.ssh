#!/usr/bin/env bash
set -Eeuo pipefail

help() {
  cat <<'EOF'
Purpose: Test reusable SSH connection routes for an existing machine key.
Inputs: The repository Makefile, new-key generator, and add-connection script.
Changes: Creates and removes an isolated temporary fixture below TMPDIR. The
         repository is read-only during the test.
Example: ./tests/test-add-connection.sh

Usage: test-add-connection.sh [options]

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
SSH_HOME_TOKEN="$(printf '\176')"
readonly SSH_HOME_TOKEN

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
  [[ -f "${path}" && ! -L "${path}" ]] || die "expected regular file: ${path}"
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
  cp -- "${PROJECT_ROOT}/shells/add-connection.sh" \
    "${fixture_path}/shells/add-connection.sh"
  chmod 755 -- "${fixture_path}/shells/new-key.sh" \
    "${fixture_path}/shells/add-connection.sh"
}

create_fixture() {
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ssh-add-connection-test.XXXXXXXX")"
  FIXTURE_ROOT="${TEMP_ROOT}/repo"
  create_fixture_at "${FIXTURE_ROOT}"
}

create_base() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local key_file="${5:-id}"
  local -a args=(
    --no-print-directory
    "new-key-${name}"
    NO_PASSPHRASE=1
    "HOST_NAME=${host}"
    "REMOTE_USER=${user}"
    "KEY_FILE=${key_file}"
  )
  if [[ -n "${port}" ]]; then
    args+=("SSH_PORT=${port}")
  fi
  make -C "${FIXTURE_ROOT}" "${args[@]}" >/dev/null
}

copy_base_key() {
  local source_name="$1"
  local target_name="$2"
  mkdir -- "${FIXTURE_ROOT}/keys/${target_name}"
  cp -- "${FIXTURE_ROOT}/keys/${source_name}/id" \
    "${FIXTURE_ROOT}/keys/${target_name}/id"
  cp -- "${FIXTURE_ROOT}/keys/${source_name}/id.pub" \
    "${FIXTURE_ROOT}/keys/${target_name}/id.pub"
}

assert_resolved_route() {
  local fragment="$1"
  local alias="$2"
  local host="$3"
  local user="$4"
  local port="$5"
  local identity="$6"
  local resolved

  resolved="$(ssh -G -F "${fragment}" "${alias}" 2>/dev/null)"
  grep -Fqx "hostname ${host}" <<<"${resolved}" || die "HostName was not applied"
  grep -Fqx "user ${user}" <<<"${resolved}" || die "User was not applied"
  grep -Fqx "port ${port}" <<<"${resolved}" || die "Port was not applied"
  grep -Fqx "identityfile ${identity}" <<<"${resolved}" ||
    die "IdentityFile was not applied"
  grep -Fqx 'identitiesonly yes' <<<"${resolved}" ||
    die "IdentitiesOnly was not applied"
}

assert_no_staging_files() {
  [[ -z "$(find "${FIXTURE_ROOT}/config.d" -maxdepth 1 \
    -name '.add-connection.*.tmp' -print -quit)" ]] ||
    die "add-connection staging file was left behind"
}

test_route_variants_reuse_base() {
  local private_key="${FIXTURE_ROOT}/keys/github/id"
  local public_key="${private_key}.pub"
  local base_fragment="${FIXTURE_ROOT}/config.d/github.conf"
  local private_hash_before
  local public_hash_before
  local config_hash_before
  local prompt_output

  create_base github github.example git 2222
  private_hash_before="$(sha256sum -- "${private_key}")"
  public_hash_before="$(sha256sum -- "${public_key}")"
  config_hash_before="$(sha256sum -- "${base_fragment}")"

  prompt_output="$(
    printf '%s\n' v6 2001:db8::10 |
      make -C "${FIXTURE_ROOT}" --no-print-directory \
        add-connection-github 2>&1 >/dev/null
  )"
  assert_equals \
    "Connection suffix (for example v6, v4, or vpn): IP address or domain: " \
    "${prompt_output}"

  local v6_fragment="${FIXTURE_ROOT}/config.d/github-v6.conf"
  assert_file "${v6_fragment}"
  assert_mode 600 "${v6_fragment}"
  assert_contains 'Host github-v6' "${v6_fragment}"
  assert_contains '    HostName 2001:db8::10' "${v6_fragment}"
  assert_contains '    User git' "${v6_fragment}"
  assert_contains '    Port 2222' "${v6_fragment}"
  assert_contains '    IdentityFile ~/.ssh/keys/github/id' "${v6_fragment}"
  assert_contains '    IdentitiesOnly yes' "${v6_fragment}"
  assert_resolved_route \
    "${v6_fragment}" github-v6 2001:db8::10 git 2222 \
    "${SSH_HOME_TOKEN}/.ssh/keys/github/id"

  make -C "${FIXTURE_ROOT}" --no-print-directory \
    add-connection-github \
    CONNECTION_NAME=v4 \
    HOST_NAME=198.51.100.20 \
    SSH_PORT=22 >/dev/null
  assert_resolved_route \
    "${FIXTURE_ROOT}/config.d/github-v4.conf" \
    github-v4 198.51.100.20 git 22 "${SSH_HOME_TOKEN}/.ssh/keys/github/id"

  make -C "${FIXTURE_ROOT}" --no-print-directory \
    add-connection-github \
    CONNECTION_NAME=vpn \
    HOST_NAME=github.vpn.example >/dev/null
  assert_resolved_route \
    "${FIXTURE_ROOT}/config.d/github-vpn.conf" \
    github-vpn github.vpn.example git 2222 "${SSH_HOME_TOKEN}/.ssh/keys/github/id"

  [[ "$(sha256sum -- "${private_key}")" == "${private_hash_before}" ]] ||
    die "base private key changed"
  [[ "$(sha256sum -- "${public_key}")" == "${public_hash_before}" ]] ||
    die "base public key changed"
  [[ "$(sha256sum -- "${base_fragment}")" == "${config_hash_before}" ]] ||
    die "base config changed"
  [[ ! -e "${FIXTURE_ROOT}/keys/github-v6" ]] || die "route created another key directory"
}

test_direct_custom_key_and_default_port() {
  create_base custom custom.example deploy "" custom.id

  "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection lan \
    --host 192.0.2.15 \
    custom >/dev/null

  local fragment="${FIXTURE_ROOT}/config.d/custom-lan.conf"
  assert_file "${fragment}"
  assert_contains '    IdentityFile ~/.ssh/keys/custom/custom.id' "${fragment}"
  assert_not_contains '    Port ' "${fragment}"
  assert_resolved_route \
    "${fragment}" custom-lan 192.0.2.15 deploy 22 \
    "${SSH_HOME_TOKEN}/.ssh/keys/custom/custom.id"
}

test_rejects_invalid_or_incomplete_input() {
  local marker="${TEMP_ROOT}/injected"
  local long_suffix
  printf -v long_suffix '%*s' 250 ''
  long_suffix="${long_suffix// /a}"

  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::11 missing
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection '../v6' --host 2001:db8::11 github
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection $'v6\nHost injected' --host 2001:db8::11 github
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection shell --host "\$(touch ${marker})" github
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection "${long_suffix}" --host 192.0.2.18 github
  [[ ! -e "${marker}" ]] || die "invalid HostName executed shell content"

  if printf '%s\n' eof-route |
    make -C "${FIXTURE_ROOT}" --no-print-directory \
      add-connection-github >/dev/null 2>&1; then
    die "incomplete prompt input unexpectedly succeeded"
  fi
  [[ ! -e "${FIXTURE_ROOT}/config.d/github-eof-route.conf" ]] ||
    die "incomplete prompt input created output"
}

test_rejects_unsupported_base_configs() {
  local marker="${TEMP_ROOT}/proxy-command-ran"

  copy_base_key github unsafe
  {
    printf 'Host unsafe\n'
    printf '    HostName unsafe.example\n'
    printf '    User deploy\n'
    printf '    ProxyCommand touch %s\n' "${marker}"
    printf '    IdentityFile ~/.ssh/keys/unsafe/id\n'
    printf '    IdentitiesOnly yes\n'
  } >"${FIXTURE_ROOT}/config.d/unsafe.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::12 unsafe
  [[ ! -e "${marker}" ]] || die "unsupported base directive was executed"

  copy_base_key github ambiguous
  {
    printf 'Host ambiguous other\n'
    printf '    HostName ambiguous.example\n'
    printf '    User deploy\n'
    printf '    IdentityFile ~/.ssh/keys/ambiguous/id\n'
    printf '    IdentityFile ~/.ssh/keys/ambiguous/id\n'
    printf '    IdentitiesOnly yes\n'
  } >"${FIXTURE_ROOT}/config.d/ambiguous.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::13 ambiguous

  copy_base_key github outside
  {
    printf 'Host outside\n'
    printf '    HostName outside.example\n'
    printf '    User deploy\n'
    printf '    IdentityFile /tmp/outside\n'
    printf '    IdentitiesOnly yes\n'
  } >"${FIXTURE_ROOT}/config.d/outside.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::14 outside

  copy_base_key github carriage
  printf 'Host carriage\r\n' >"${FIXTURE_ROOT}/config.d/carriage.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::15 carriage
}

test_rejects_collisions_without_changes() {
  local existing="${FIXTURE_ROOT}/config.d/github-existing.conf"
  local existing_hash

  printf 'keep me\n' >"${existing}"
  existing_hash="$(sha256sum -- "${existing}")"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection existing --host 192.0.2.20 github
  [[ "$(sha256sum -- "${existing}")" == "${existing_hash}" ]] ||
    die "existing route config changed"

  ln -s -- "${TEMP_ROOT}/missing" "${FIXTURE_ROOT}/config.d/github-dangling.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection dangling --host 192.0.2.21 github
  rm -- "${FIXTURE_ROOT}/config.d/github-dangling.conf"

  printf 'Host github-other\n' >"${FIXTURE_ROOT}/config.d/different-name.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection other --host 192.0.2.22 github

  mkdir -- "${FIXTURE_ROOT}/config.d/github-directory.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection directory --host 192.0.2.23 github
}

test_rejects_symlinked_inputs() {
  local saved_config
  local saved_private
  local symlink_root="${TEMP_ROOT}/symlink-root-repo"

  create_base linkconfig linkconfig.example deploy 22
  saved_config="${TEMP_ROOT}/linkconfig.conf"
  mv -- "${FIXTURE_ROOT}/config.d/linkconfig.conf" "${saved_config}"
  ln -s -- "${saved_config}" "${FIXTURE_ROOT}/config.d/linkconfig.conf"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::16 linkconfig
  rm -- "${FIXTURE_ROOT}/config.d/linkconfig.conf"
  mv -- "${saved_config}" "${FIXTURE_ROOT}/config.d/linkconfig.conf"

  create_base linkkey linkkey.example deploy 22
  saved_private="${TEMP_ROOT}/linkkey-private"
  mv -- "${FIXTURE_ROOT}/keys/linkkey/id" "${saved_private}"
  ln -s -- "${saved_private}" "${FIXTURE_ROOT}/keys/linkkey/id"
  expect_failure "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::17 linkkey

  create_fixture_at "${symlink_root}"
  make -C "${symlink_root}" --no-print-directory \
    new-key-base \
    NO_PASSPHRASE=1 \
    HOST_NAME=base.example \
    REMOTE_USER=deploy >/dev/null
  mv -- "${symlink_root}/config.d" "${symlink_root}/real-config.d"
  ln -s -- "${symlink_root}/real-config.d" "${symlink_root}/config.d"
  expect_failure "${symlink_root}/shells/add-connection.sh" \
    --connection v6 --host 2001:db8::18 base
}

test_parallel_publish_is_no_replace() {
  local status_one
  local status_two
  local pid_one
  local pid_two
  local successes=0

  create_base parallel parallel.example deploy 2200
  set +e
  "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection vpn --host parallel.vpn.example parallel >/dev/null 2>&1 &
  pid_one=$!
  "${FIXTURE_ROOT}/shells/add-connection.sh" \
    --connection vpn --host parallel.vpn.example parallel >/dev/null 2>&1 &
  pid_two=$!
  wait "${pid_one}"
  status_one=$?
  wait "${pid_two}"
  status_two=$?
  set -e

  [[ "${status_one}" == "0" ]] && ((successes += 1))
  [[ "${status_two}" == "0" ]] && ((successes += 1))
  assert_equals 1 "${successes}"
  assert_file "${FIXTURE_ROOT}/config.d/parallel-vpn.conf"
  assert_mode 600 "${FIXTURE_ROOT}/config.d/parallel-vpn.conf"
}

cleanup() {
  local exit_code=$?

  if [[ -n "${TEMP_ROOT}" && -d "${TEMP_ROOT}" ]]; then
    rm -rf -- "${TEMP_ROOT}"
  fi
  return "${exit_code}"
}

run() {
  require_command chmod || return 1
  require_command cp || return 1
  require_command find || return 1
  require_command grep || return 1
  require_command ln || return 1
  require_command make || return 1
  require_command mktemp || return 1
  require_command mv || return 1
  require_command rm || return 1
  require_command sha256sum || return 1
  require_command ssh || return 1
  require_command stat || return 1
  create_fixture
  test_route_variants_reuse_base
  test_direct_custom_key_and_default_port
  test_rejects_invalid_or_incomplete_input
  test_rejects_unsupported_base_configs
  test_rejects_collisions_without_changes
  test_rejects_symlinked_inputs
  test_parallel_publish_is_no_replace
  assert_no_staging_files
  printf 'PASS: reusable SSH connection routes\n'
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
