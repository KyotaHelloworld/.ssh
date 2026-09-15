# Task: Interactive SSH key setup

- Branch: `feature/interactive-key-prompt`
- Worktree: external task worktree `interactive-key-prompt`
- Status: validated; awaiting user acceptance for local master integration

## Acceptance

- Every `make new-key-<name>` asks for `Login user name` and then
  `IP address or domain` when those values were not supplied.
- The answers become `User` and `HostName` in the generated config fragment.
- The connection input accepts IPv4, IPv6, and domain-name forms.
- Pre-supplied `REMOTE_USER` and `HOST_NAME` values skip their questions.
- EOF or invalid input fails before any key or config output is created.
- Direct script usage remains non-interactive unless explicitly requested.

## Work

- Enabled connection prompts on the shared `new-key-%` Make target rather than
  adding a ConoHa-only branch.
- Added ordered prompts for missing login user and IP/domain values after output
  preflight and before key generation.
- Kept supplied values non-interactive and retained optional connection fields
  for direct script usage.
- Updated the README with the interactive command flow.

## Validation

- `bash -n shells/new-key.sh tests/test-new-key.sh`
- `shellcheck -x shells/new-key.sh tests/test-new-key.sh`
- `./tests/test-new-key.sh`: domain prompt, IPv4/IPv6 values, per-field prompt
  skipping, EOF/invalid-input rollback, default generation, and all existing
  key/config regression cases passed.
- `git diff --check` and Make help checks passed.
- `keys/sample/id` and `keys/sample/id.pub` are unchanged.

## Intended commit

- `Prompt for SSH connection details`
