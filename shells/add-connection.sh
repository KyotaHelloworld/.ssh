#!/usr/bin/env bash
set -Eeuo pipefail

help() {
  cat <<'EOF'
Purpose: Add another SSH route for an existing machine key and connection.
Inputs: An existing base alias, a route suffix, and an IP address or domain.
Changes: Adds one Host block to config.d/<base>.conf. The existing key and
         Host blocks are preserved.
Example: ./shells/add-connection.sh --connection v6 --host 2001:db8::10 bakery
Prerequisites: flock and standard GNU file utilities on the local machine.

Usage: add-connection.sh [options] [base-name]

Arguments:
  base-name                 Existing SSH Host alias and keys/<name> directory.
                            May also be supplied through the environment.

Options:
  --connection <name>       Route suffix appended to the base alias, such as
                            v6, v4, or vpn.
  --host <hostname>         IP address or domain for the additional route.
  --port <1-65535>          Override the base connection's port.
  --prompt-connection       Prompt for a missing route suffix and IP/domain.
  -h, --help                Show this help.

Environment:
  SSH_ADD_CONNECTION_BASE_NAME, SSH_ADD_CONNECTION_NAME,
  SSH_ADD_CONNECTION_HOST, and SSH_ADD_CONNECTION_PORT provide the same
  values for Makefile integration. SSH_ADD_CONNECTION_PROMPT enables prompts.

Reuse behavior:
  HostName is set for the route. User, IdentityFile, IdentitiesOnly, and the
  port (unless overridden) are copied from the base Host block. This is a
  snapshot: later base-block edits do not update existing route blocks.
  The private key is only checked for existence and is never read or changed.

Exit behavior:
  Returns non-zero without creating output when the base entry is unsupported,
  input is invalid, or the new alias already exists. The config is replaced
  atomically only after a complete updated copy has been prepared.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly PROJECT_ROOT
readonly CONFIG_EXTENSION=".conf"
readonly MAX_HOST_ALIAS_LENGTH=255

BASE_NAME="${SSH_ADD_CONNECTION_BASE_NAME:-}"
CONNECTION_NAME="${SSH_ADD_CONNECTION_NAME:-}"
HOST_NAME="${SSH_ADD_CONNECTION_HOST:-}"
PORT_OVERRIDE="${SSH_ADD_CONNECTION_PORT:-}"
PROMPT_CONNECTION="${SSH_ADD_CONNECTION_PROMPT:-0}"
SHOW_HELP=0

BASE_CONFIG_PATH=""
BASE_KEY_DIRECTORY=""
BASE_PRIVATE_KEY_PATH=""
BASE_PUBLIC_KEY_PATH=""
BASE_USER=""
BASE_PORT=""
BASE_IDENTITY=""
BASE_KEY_FILE=""
NEW_ALIAS=""
FINAL_PORT=""
STAGING_FILE=""
CONFIG_LOCK_FD=""

die() {
  printf 'Error: %s\n' "$*" >&2
  return 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command not found: ${command_name}"
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"
  [[ -n "${option_value}" ]] || die "${option_name} requires a value"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        SHOW_HELP=1
        shift
        ;;
      --connection | --host | --port)
        require_option_value "$1" "${2:-}" || return 1
        case "$1" in
          --connection) CONNECTION_NAME="$2" ;;
          --host) HOST_NAME="$2" ;;
          --port) PORT_OVERRIDE="$2" ;;
        esac
        shift 2
        ;;
      --prompt-connection)
        PROMPT_CONNECTION=1
        shift
        ;;
      --)
        shift
        if (($# > 1)); then
          die "only one base name may be supplied" || return 1
        fi
        if (($# == 1)); then
          [[ -z "${BASE_NAME}" ]] ||
            die "base name was supplied through both the environment and arguments" || return 1
          BASE_NAME="$1"
          shift
        fi
        ;;
      -*)
        die "unknown option: $1" || return 1
        ;;
      *)
        [[ -z "${BASE_NAME}" ]] ||
          die "base name was supplied through both the environment and arguments" || return 1
        BASE_NAME="$1"
        shift
        ;;
    esac
  done
}

validate_path_component() {
  local label="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    [[ "${value}" == "." || "${value}" == ".." ]]; then
    die "${label} must use only letters, digits, dot, underscore, and hyphen"
  fi
}

validate_host_name() {
  local value="$1"

  if [[ ! "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ &&
    ! "${value}" =~ ^:[0-9A-Fa-f:]+$ ]]; then
    die "IP address or domain contains unsupported characters"
  fi
}

validate_port() {
  local value="$1"

  [[ "${value}" =~ ^[0-9]+$ ]] || die "port must be numeric" || return 1
  ((${#value} <= 5)) || die "port must be between 1 and 65535" || return 1
  if ((10#${value} < 1 || 10#${value} > 65535)); then
    die "port must be between 1 and 65535" || return 1
  fi
}

validate_initial_inputs() {
  [[ -n "${BASE_NAME}" ]] || die "base name is required" || return 1
  validate_path_component "base name" "${BASE_NAME}" || return 1
  case "${PROMPT_CONNECTION}" in
    0 | 1) ;;
    *) die "SSH_ADD_CONNECTION_PROMPT must be 0 or 1" || return 1 ;;
  esac
  if [[ -n "${PORT_OVERRIDE}" ]]; then
    validate_port "${PORT_OVERRIDE}" || return 1
  fi
}

resolve_base_paths() {
  BASE_CONFIG_PATH="${PROJECT_ROOT}/config.d/${BASE_NAME}${CONFIG_EXTENSION}"
  BASE_KEY_DIRECTORY="${PROJECT_ROOT}/keys/${BASE_NAME}"
}

preflight_base_paths() {
  [[ ! -L "${PROJECT_ROOT}/keys" ]] ||
    die "project directory must not be a symlink: keys" || return 1
  [[ ! -L "${PROJECT_ROOT}/config.d" ]] ||
    die "project directory must not be a symlink: config.d" || return 1
  [[ -d "${PROJECT_ROOT}/keys" ]] || die "missing project directory: keys" || return 1
  [[ -d "${PROJECT_ROOT}/config.d" ]] ||
    die "missing project directory: config.d" || return 1
  [[ -d "${BASE_KEY_DIRECTORY}" && ! -L "${BASE_KEY_DIRECTORY}" ]] ||
    die "base key directory is missing or unsupported: keys/${BASE_NAME}" || return 1
  [[ -f "${BASE_CONFIG_PATH}" && ! -L "${BASE_CONFIG_PATH}" ]] ||
    die "base config is missing or unsupported: config.d/${BASE_NAME}${CONFIG_EXTENSION}" ||
    return 1
}

parse_base_config() {
  local line
  local directive
  local value
  local extra
  local config_fd
  local host_seen=0
  local hostname_seen=0
  local user_seen=0
  local port_seen=0
  local identity_seen=0
  local identities_only_seen=0
  local in_base=0

  exec {config_fd}<"${BASE_CONFIG_PATH}" || die "cannot read base config" || return 1
  while IFS= read -r -u "${config_fd}" line || [[ -n "${line}" ]]; do
    [[ "${line}" != *$'\r'* ]] || die "base config contains a carriage return" || return 1
    directive=""
    value=""
    extra=""
    read -r directive value extra <<<"${line}"
    [[ -n "${directive}" ]] || continue
    [[ "${directive}" != \#* ]] || continue

    case "${directive,,}" in
      host)
        in_base=0
        if [[ " ${value} ${extra} " == *" ${BASE_NAME} "* ]]; then
          [[ "${host_seen}" == "0" && "${value}" == "${BASE_NAME}" && -z "${extra}" ]] ||
            die "base config must contain exactly one literal Host ${BASE_NAME} block" || return 1
          host_seen=1
          in_base=1
        fi
        ;;
      hostname)
        [[ "${in_base}" == "1" ]] || continue
        [[ "${hostname_seen}" == "0" && -n "${value}" && -z "${extra}" ]] ||
          die "base HostName must contain exactly one value" || return 1
        validate_host_name "${value}" || return 1
        hostname_seen=1
        ;;
      user)
        [[ "${in_base}" == "1" ]] || continue
        [[ "${user_seen}" == "0" && -n "${value}" && -z "${extra}" ]] ||
          die "base User must contain exactly one value" || return 1
        [[ "${value}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] ||
          die "base User contains unsupported characters" || return 1
        BASE_USER="${value}"
        user_seen=1
        ;;
      port)
        [[ "${in_base}" == "1" ]] || continue
        [[ "${port_seen}" == "0" && -n "${value}" && -z "${extra}" ]] ||
          die "base Port must contain one value" || return 1
        validate_port "${value}" || return 1
        BASE_PORT="${value}"
        port_seen=1
        ;;
      identityfile)
        [[ "${in_base}" == "1" ]] || continue
        [[ "${identity_seen}" == "0" && -n "${value}" && -z "${extra}" ]] ||
          die "base IdentityFile must contain exactly one value" || return 1
        BASE_IDENTITY="${value}"
        identity_seen=1
        ;;
      identitiesonly)
        [[ "${in_base}" == "1" ]] || continue
        [[ "${identities_only_seen}" == "0" && "${value,,}" == "yes" && -z "${extra}" ]] ||
          die "base IdentitiesOnly must be exactly yes" || return 1
        identities_only_seen=1
        ;;
      *)
        [[ "${in_base}" == "1" ]] || continue
        die "unsupported directive in base config: ${directive}" || return 1
        ;;
    esac
  done
  exec {config_fd}<&-

  [[ "${host_seen}" == "1" ]] || die "base Host entry is missing" || return 1
  [[ "${hostname_seen}" == "1" ]] || die "base HostName is missing" || return 1
  [[ "${user_seen}" == "1" ]] || die "base User is missing" || return 1
  [[ "${identity_seen}" == "1" ]] || die "base IdentityFile is missing" || return 1
  [[ "${identities_only_seen}" == "1" ]] || die "base IdentitiesOnly is missing" || return 1
}

resolve_and_verify_base_key() {
  local expected_prefix
  printf -v expected_prefix '\176/.ssh/keys/%s/' "${BASE_NAME}"

  [[ "${BASE_IDENTITY}" == "${expected_prefix}"* ]] ||
    die "base IdentityFile must point below keys/${BASE_NAME}" || return 1
  BASE_KEY_FILE="${BASE_IDENTITY#"${expected_prefix}"}"
  validate_path_component "base key filename" "${BASE_KEY_FILE}" || return 1
  BASE_PRIVATE_KEY_PATH="${BASE_KEY_DIRECTORY}/${BASE_KEY_FILE}"
  BASE_PUBLIC_KEY_PATH="${BASE_PRIVATE_KEY_PATH}.pub"
  [[ -f "${BASE_PRIVATE_KEY_PATH}" && ! -L "${BASE_PRIVATE_KEY_PATH}" ]] ||
    die "base private key is missing or unsupported" || return 1
  [[ -f "${BASE_PUBLIC_KEY_PATH}" && ! -L "${BASE_PUBLIC_KEY_PATH}" ]] ||
    die "base public key is missing or unsupported" || return 1
}

prompt_for_connection() {
  [[ "${PROMPT_CONNECTION}" == "1" ]] || return 0

  if [[ -z "${CONNECTION_NAME}" ]]; then
    printf 'Connection suffix (for example v6, v4, or vpn): ' >&2
    IFS= read -r CONNECTION_NAME ||
      die "connection suffix input ended unexpectedly" || return 1
  fi
  if [[ -z "${HOST_NAME}" ]]; then
    printf 'IP address or domain: ' >&2
    IFS= read -r HOST_NAME || die "IP address or domain input ended unexpectedly" || return 1
  fi
}

validate_connection_inputs() {
  [[ -n "${CONNECTION_NAME}" ]] || die "connection suffix is required" || return 1
  [[ -n "${HOST_NAME}" ]] || die "IP address or domain is required" || return 1
  validate_path_component "connection suffix" "${CONNECTION_NAME}" || return 1
  validate_host_name "${HOST_NAME}" || return 1

  NEW_ALIAS="${BASE_NAME}-${CONNECTION_NAME}"
  validate_path_component "generated alias" "${NEW_ALIAS}" || return 1
  ((${#NEW_ALIAS} <= MAX_HOST_ALIAS_LENGTH)) ||
    die "generated alias is too long" || return 1
  if [[ -n "${PORT_OVERRIDE}" ]]; then
    FINAL_PORT="${PORT_OVERRIDE}"
  else
    FINAL_PORT="${BASE_PORT}"
  fi
}

alias_is_already_defined() {
  local config_file
  local line
  local -a fields
  local token

  for config_file in "${PROJECT_ROOT}"/config.d/*"${CONFIG_EXTENSION}"; do
    if [[ -L "${config_file}" ]]; then
      return 2
    fi
    [[ -e "${config_file}" ]] || continue
    [[ -f "${config_file}" ]] || continue
    while IFS= read -r line || [[ -n "${line}" ]]; do
      fields=()
      read -r -a fields <<<"${line}"
      ((${#fields[@]} > 1)) || continue
      [[ "${fields[0],,}" == "host" ]] || continue
      for token in "${fields[@]:1}"; do
        if [[ "${token,,}" == "${NEW_ALIAS,,}" ]]; then
          return 0
        fi
      done
    done <"${config_file}"
  done
  return 1
}

preflight_output() {
  local alias_check_status

  if alias_is_already_defined; then
    die "SSH Host alias is already defined: ${NEW_ALIAS}" || return 1
  else
    alias_check_status=$?
    if [[ "${alias_check_status}" == "2" ]]; then
      die "cannot safely check aliases while config.d contains a symlinked fragment" || return 1
    fi
  fi
}

write_staged_fragment() {
  STAGING_FILE="$(mktemp "${PROJECT_ROOT}/config.d/.add-connection.XXXXXXXX.tmp")"
  cat -- "${BASE_CONFIG_PATH}" >"${STAGING_FILE}"
  {
    printf '\nHost %s\n' "${NEW_ALIAS}"
    printf '    HostName %s\n' "${HOST_NAME}"
    printf '    User %s\n' "${BASE_USER}"
    if [[ -n "${FINAL_PORT}" ]]; then
      printf '    Port %s\n' "${FINAL_PORT}"
    fi
    printf '    IdentityFile %s\n' "${BASE_IDENTITY}"
    printf '    IdentitiesOnly yes\n'
  } >>"${STAGING_FILE}"
  chmod 600 -- "${STAGING_FILE}"
}

publish_fragment() {
  [[ -f "${BASE_CONFIG_PATH}" && ! -L "${BASE_CONFIG_PATH}" ]] ||
    die "base config changed while adding connection" || return 1
  mv -- "${STAGING_FILE}" "${BASE_CONFIG_PATH}"
  STAGING_FILE=""
}

lock_config_directory() {
  exec {CONFIG_LOCK_FD}<"${PROJECT_ROOT}/config.d" ||
    die "cannot open config directory for locking" || return 1
  flock -x "${CONFIG_LOCK_FD}" || die "cannot lock config directory" || return 1
}

cleanup() {
  local exit_code=$?

  set +e
  if [[ -n "${STAGING_FILE}" && -f "${STAGING_FILE}" ]]; then
    rm -f -- "${STAGING_FILE}" || true
  fi
  return "${exit_code}"
}

run() {
  umask 077
  require_command chmod || return 1
  require_command cat || return 1
  require_command flock || return 1
  require_command mktemp || return 1
  require_command mv || return 1
  validate_initial_inputs || return 1
  resolve_base_paths
  preflight_base_paths || return 1
  prompt_for_connection || return 1
  lock_config_directory || return 1
  preflight_base_paths || return 1
  parse_base_config || return 1
  resolve_and_verify_base_key || return 1
  validate_connection_inputs || return 1
  preflight_output || return 1
  write_staged_fragment
  publish_fragment

  printf 'Added %s to config.d/%s%s using keys/%s/%s\n' \
    "${NEW_ALIAS}" "${BASE_NAME}" "${CONFIG_EXTENSION}" "${BASE_NAME}" "${BASE_KEY_FILE}"
  printf 'Connect with: ssh %s\n' "${NEW_ALIAS}"
}

main() {
  parse_args "$@" || return 1
  if [[ "${SHOW_HELP}" == "1" ]]; then
    help
    return 0
  fi

  run
}

trap cleanup EXIT
main "$@"
