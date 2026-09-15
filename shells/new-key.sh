#!/usr/bin/env bash
set -Eeuo pipefail

help() {
  cat <<'EOF'
Purpose: Create one SSH key pair and its matching config.d fragment.
Inputs: A safe host alias plus optional hostname, remote user, port, key type,
        key filename, and public-key comment.
Changes: Creates keys/<name>/<key-file>, its .pub file, and
         config.d/<name>.conf. Existing keys and config files are never replaced.
Example: ./shells/new-key.sh --host github.com --user git github

Usage: new-key.sh [options] [name]

Arguments:
  name                    SSH Host alias and output directory name. May also be
                          supplied through SSH_NEW_KEY_NAME by the Makefile.

Options:
  --host <hostname>       Add HostName to the generated fragment.
  --user <remote-user>    Add User to the generated fragment.
  --port <1-65535>        Add Port to the generated fragment.
  --key-type <type>       Key type: ed25519 (default) or rsa.
  --key-file <filename>   Private-key filename (default: id).
  --comment <comment>     Public-key comment (default: ssh-key:<name>).
  --no-passphrase         Explicitly create the key without a passphrase.
  --prompt-connection     Prompt for a missing login user and IP/domain.
  --skip-existing         Succeed without changes when both outputs already exist.
  -h, --help              Show this help.

Environment:
  SSH_NEW_KEY_NAME, SSH_NEW_KEY_HOST, SSH_NEW_KEY_USER, SSH_NEW_KEY_PORT,
  SSH_NEW_KEY_TYPE, SSH_NEW_KEY_FILE, SSH_NEW_KEY_COMMENT, and
  SSH_NEW_KEY_NO_PASSPHRASE provide the same values for Makefile integration.
  SSH_NEW_KEY_PROMPT_CONNECTION enables connection prompts, and
  SSH_NEW_KEY_SKIP_EXISTING controls idempotent batch generation.

Passphrase handling:
  By default ssh-keygen prompts securely. Passphrases are intentionally not
  accepted through arguments or environment variables.

Exit behavior:
  Returns non-zero before publishing output when input is invalid or an output
  path already exists. If publishing fails, only files created by this run are
  removed.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly PROJECT_ROOT
readonly DEFAULT_KEY_TYPE="ed25519"
readonly DEFAULT_KEY_FILE="id"
readonly CONFIG_EXTENSION=".conf"

NEW_KEY_NAME="${SSH_NEW_KEY_NAME:-}"
HOST_NAME="${SSH_NEW_KEY_HOST:-}"
REMOTE_USER="${SSH_NEW_KEY_USER:-}"
SSH_PORT_VALUE="${SSH_NEW_KEY_PORT:-}"
KEY_TYPE="${SSH_NEW_KEY_TYPE:-${DEFAULT_KEY_TYPE}}"
KEY_FILE="${SSH_NEW_KEY_FILE:-${DEFAULT_KEY_FILE}}"
KEY_COMMENT="${SSH_NEW_KEY_COMMENT:-}"
NO_PASSPHRASE="${SSH_NEW_KEY_NO_PASSPHRASE:-0}"
PROMPT_CONNECTION="${SSH_NEW_KEY_PROMPT_CONNECTION:-0}"
SKIP_EXISTING="${SSH_NEW_KEY_SKIP_EXISTING:-0}"
SHOW_HELP=0
SKIPPED=0

STAGING_DIR=""
PRIVATE_KEY_PATH=""
PUBLIC_KEY_PATH=""
CONFIG_PATH=""
KEY_DIRECTORY=""
KEY_DIRECTORY_CREATED=0
CONFIG_CREATED=0
PUBLISHED=0

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
      --host | --user | --port | --key-type | --key-file | --comment)
        require_option_value "$1" "${2:-}" || return 1
        case "$1" in
          --host) HOST_NAME="$2" ;;
          --user) REMOTE_USER="$2" ;;
          --port) SSH_PORT_VALUE="$2" ;;
          --key-type) KEY_TYPE="$2" ;;
          --key-file) KEY_FILE="$2" ;;
          --comment) KEY_COMMENT="$2" ;;
        esac
        shift 2
        ;;
      --no-passphrase)
        NO_PASSPHRASE=1
        shift
        ;;
      --prompt-connection)
        PROMPT_CONNECTION=1
        shift
        ;;
      --skip-existing)
        SKIP_EXISTING=1
        shift
        ;;
      --)
        shift
        if (($# > 1)); then
          die "only one name may be supplied" || return 1
        fi
        if (($# == 1)); then
          [[ -z "${NEW_KEY_NAME}" ]] ||
            die "name was supplied through both the environment and arguments" || return 1
          NEW_KEY_NAME="$1"
          shift
        fi
        ;;
      -*)
        die "unknown option: $1" || return 1
        ;;
      *)
        [[ -z "${NEW_KEY_NAME}" ]] ||
          die "name was supplied through both the environment and arguments" || return 1
        NEW_KEY_NAME="$1"
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

validate_inputs() {
  [[ -n "${NEW_KEY_NAME}" ]] || die "name is required" || return 1
  validate_path_component "name" "${NEW_KEY_NAME}" || return 1
  validate_path_component "key filename" "${KEY_FILE}" || return 1

  case "${KEY_TYPE}" in
    ed25519 | rsa) ;;
    *) die "key type must be ed25519 or rsa" || return 1 ;;
  esac

  case "${NO_PASSPHRASE}" in
    0 | 1) ;;
    *) die "SSH_NEW_KEY_NO_PASSPHRASE must be 0 or 1" || return 1 ;;
  esac
  case "${PROMPT_CONNECTION}" in
    0 | 1) ;;
    *) die "SSH_NEW_KEY_PROMPT_CONNECTION must be 0 or 1" || return 1 ;;
  esac
  case "${SKIP_EXISTING}" in
    0 | 1) ;;
    *) die "SSH_NEW_KEY_SKIP_EXISTING must be 0 or 1" || return 1 ;;
  esac

  if [[ -n "${HOST_NAME}" &&
    ! "${HOST_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ &&
    ! "${HOST_NAME}" =~ ^:[0-9A-Fa-f:]+$ ]]; then
    die "IP address or domain contains unsupported characters" || return 1
  fi
  if [[ -n "${REMOTE_USER}" && ! "${REMOTE_USER}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
    die "remote user contains unsupported characters" || return 1
  fi
  if [[ -n "${SSH_PORT_VALUE}" ]]; then
    [[ "${SSH_PORT_VALUE}" =~ ^[0-9]+$ ]] || die "port must be numeric" || return 1
    ((${#SSH_PORT_VALUE} <= 5)) || die "port must be between 1 and 65535" || return 1
    if ((10#${SSH_PORT_VALUE} < 1 || 10#${SSH_PORT_VALUE} > 65535)); then
      die "port must be between 1 and 65535" || return 1
    fi
  fi
  if [[ "${KEY_COMMENT}" == *$'\n'* || "${KEY_COMMENT}" == *$'\r'* ]]; then
    die "comment must fit on one line" || return 1
  fi

  [[ -n "${KEY_COMMENT}" ]] || KEY_COMMENT="ssh-key:${NEW_KEY_NAME}"
}

prompt_for_connection() {
  [[ "${PROMPT_CONNECTION}" == "1" ]] || return 0

  if [[ -z "${REMOTE_USER}" ]]; then
    printf 'Login user name: ' >&2
    IFS= read -r REMOTE_USER || die "login user name input ended unexpectedly" || return 1
  fi
  if [[ -z "${HOST_NAME}" ]]; then
    printf 'IP address or domain: ' >&2
    IFS= read -r HOST_NAME || die "IP address or domain input ended unexpectedly" || return 1
  fi

  [[ -n "${REMOTE_USER}" ]] || die "login user name is required" || return 1
  [[ -n "${HOST_NAME}" ]] || die "IP address or domain is required" || return 1
}

resolve_output_paths() {
  KEY_DIRECTORY="${PROJECT_ROOT}/keys/${NEW_KEY_NAME}"
  PRIVATE_KEY_PATH="${KEY_DIRECTORY}/${KEY_FILE}"
  PUBLIC_KEY_PATH="${PRIVATE_KEY_PATH}.pub"
  CONFIG_PATH="${PROJECT_ROOT}/config.d/${NEW_KEY_NAME}${CONFIG_EXTENSION}"
}

preflight_outputs() {
  local key_exists=0
  local config_exists=0

  [[ ! -L "${PROJECT_ROOT}/keys" ]] || die "project directory must not be a symlink: keys" || return 1
  [[ ! -L "${PROJECT_ROOT}/config.d" ]] ||
    die "project directory must not be a symlink: config.d" || return 1
  [[ -d "${PROJECT_ROOT}/keys" ]] || die "missing project directory: keys" || return 1
  [[ -d "${PROJECT_ROOT}/config.d" ]] || die "missing project directory: config.d" || return 1

  if [[ -e "${KEY_DIRECTORY}" || -L "${KEY_DIRECTORY}" ]]; then
    key_exists=1
  fi
  if [[ -e "${CONFIG_PATH}" || -L "${CONFIG_PATH}" ]]; then
    config_exists=1
  fi

  if [[ "${key_exists}" == "1" && "${config_exists}" == "1" && "${SKIP_EXISTING}" == "1" ]]; then
    if [[ -d "${KEY_DIRECTORY}" && ! -L "${KEY_DIRECTORY}" &&
      -f "${PRIVATE_KEY_PATH}" && ! -L "${PRIVATE_KEY_PATH}" &&
      -f "${PUBLIC_KEY_PATH}" && ! -L "${PUBLIC_KEY_PATH}" &&
      -f "${CONFIG_PATH}" && ! -L "${CONFIG_PATH}" ]]; then
      SKIPPED=1
      return 0
    fi
    die "existing outputs are incomplete or use unsupported file types: ${NEW_KEY_NAME}" ||
      return 1
  fi
  if [[ "${key_exists}" == "1" ]]; then
    die "key directory already exists: keys/${NEW_KEY_NAME}" || return 1
  fi
  if [[ "${config_exists}" == "1" ]]; then
    die "config file already exists: config.d/${NEW_KEY_NAME}${CONFIG_EXTENSION}" || return 1
  fi
}

write_config_fragment() {
  local output_path="$1"

  {
    printf 'Host %s\n' "${NEW_KEY_NAME}"
    if [[ -n "${HOST_NAME}" ]]; then
      printf '    HostName %s\n' "${HOST_NAME}"
    fi
    if [[ -n "${REMOTE_USER}" ]]; then
      printf '    User %s\n' "${REMOTE_USER}"
    fi
    if [[ -n "${SSH_PORT_VALUE}" ]]; then
      printf '    Port %s\n' "${SSH_PORT_VALUE}"
    fi
    printf '    IdentityFile ~/.ssh/keys/%s/%s\n' "${NEW_KEY_NAME}" "${KEY_FILE}"
    printf '    IdentitiesOnly yes\n'
  } >"${output_path}"
}

generate_staged_outputs() {
  local -a keygen_args

  STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssh-new-key.XXXXXXXX")"
  keygen_args=(
    -q
    -t "${KEY_TYPE}"
    -f "${STAGING_DIR}/${KEY_FILE}"
    -a 100
    -C "${KEY_COMMENT}"
  )
  if [[ "${KEY_TYPE}" == "rsa" ]]; then
    keygen_args+=(-b 4096)
  fi
  if [[ "${NO_PASSPHRASE}" == "1" ]]; then
    keygen_args+=(-N "")
  fi

  ssh-keygen "${keygen_args[@]}"
  write_config_fragment "${STAGING_DIR}/${NEW_KEY_NAME}${CONFIG_EXTENSION}"
}

publish_outputs() {
  mkdir -- "${KEY_DIRECTORY}"
  KEY_DIRECTORY_CREATED=1
  chmod 700 -- "${KEY_DIRECTORY}"
  install -m 600 -- "${STAGING_DIR}/${KEY_FILE}" "${PRIVATE_KEY_PATH}"
  install -m 644 -- "${STAGING_DIR}/${KEY_FILE}.pub" "${PUBLIC_KEY_PATH}"

  if ! (set -o noclobber; : >"${CONFIG_PATH}") 2>/dev/null; then
    die "config file appeared during generation: config.d/${NEW_KEY_NAME}${CONFIG_EXTENSION}" ||
      return 1
  fi
  CONFIG_CREATED=1
  install -m 600 -- "${STAGING_DIR}/${NEW_KEY_NAME}${CONFIG_EXTENSION}" "${CONFIG_PATH}"
  PUBLISHED=1
}

cleanup() {
  local exit_code=$?

  set +e
  if [[ "${PUBLISHED}" != "1" ]]; then
    if [[ "${CONFIG_CREATED}" == "1" ]]; then
      rm -f -- "${CONFIG_PATH}" || true
    fi
    if [[ "${KEY_DIRECTORY_CREATED}" == "1" ]]; then
      rm -f -- "${PRIVATE_KEY_PATH}" "${PUBLIC_KEY_PATH}" || true
      rmdir -- "${KEY_DIRECTORY}" 2>/dev/null || true
    fi
  fi

  if [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]]; then
    rm -f -- \
      "${STAGING_DIR}/${KEY_FILE}" \
      "${STAGING_DIR}/${KEY_FILE}.pub" \
      "${STAGING_DIR}/${NEW_KEY_NAME}${CONFIG_EXTENSION}" || true
    rmdir -- "${STAGING_DIR}" 2>/dev/null || true
  fi

  return "${exit_code}"
}

run() {
  umask 077
  require_command ssh-keygen || return 1
  require_command install || return 1
  require_command mktemp || return 1
  validate_inputs || return 1
  resolve_output_paths
  preflight_outputs || return 1
  if [[ "${SKIPPED}" == "1" ]]; then
    printf 'Skipped existing keys/%s and config.d/%s%s\n' \
      "${NEW_KEY_NAME}" "${NEW_KEY_NAME}" "${CONFIG_EXTENSION}"
    return 0
  fi
  prompt_for_connection || return 1
  validate_inputs || return 1
  generate_staged_outputs
  publish_outputs

  printf 'Created keys/%s/%s and config.d/%s%s\n' \
    "${NEW_KEY_NAME}" "${KEY_FILE}" "${NEW_KEY_NAME}" "${CONFIG_EXTENSION}"
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
