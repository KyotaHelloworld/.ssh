# Task: SSH key and config generator

- Branch: `feature/key-config-generator`
- Worktree: external task worktree `key-config-generator`
- Status: validated; awaiting user acceptance for local master integration

## Acceptance

- `make new-key-<name>` creates a key pair and `config.d/<name>.conf` together.
- Host alias and identity path are derived automatically; hostname, remote user,
  and port are included when supplied.
- Existing keys and config fragments are never overwritten.
- Passphrases are not accepted through process-visible arguments or variables.
- Unsafe names and unsupported key settings fail without partial output.
- The intentional unused sample key remains unchanged.

## Work

- Replaced the Makefile's inline shell expansion with a dedicated Bash generator.
- Added automatic ignored `config.d/<name>.conf` generation with optional host,
  remote-user, and port fields.
- Preserved `CT` and `FN` as legacy aliases; rejected legacy `PP` so a passphrase
  cannot be placed in process-visible input.
- Replaced the unused prototype zsh scripts with the maintained generator and an
  isolated regression suite.
- Made default generation resumable by skipping only complete existing pairs.

## Validation

- `bash -n shells/new-key.sh tests/test-new-key.sh`
- `shellcheck -x shells/new-key.sh tests/test-new-key.sh`
- `./tests/test-new-key.sh`: normal, minimal, direct CLI, resumable defaults,
  overwrite protection, injection rejection, invalid key/port rejection, legacy
  variables, config collision, and symlink-root rejection all passed.
- `git diff --check`, Make help, and ignored generated-fragment checks passed.
- `keys/sample/id` and `keys/sample/id.pub` are unchanged.

## Intended commit

- `Improve SSH key and config generation`
