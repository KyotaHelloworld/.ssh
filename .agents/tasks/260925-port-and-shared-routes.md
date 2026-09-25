# Task: Port prompt and shared machine config

- Branch: `codex/port-and-shared-routes`
- Worktree: external task worktree `260925-port-and-shared-routes`
- Status: implemented and validated; awaiting user acceptance for local master integration

## Acceptance

- `make new-key-<machine>` asks for a port when none is supplied. Blank uses SSH's default port 22; `SSH_PORT` skips the prompt.
- `make add-connection-<machine>` appends route aliases to `config.d/<machine>.conf` without creating another key or route config file.
- Base and route aliases resolve to the expected host, user, port, and same machine identity; different machines keep distinct keys.
- Invalid ports, duplicate aliases, unsafe base configs, symlinked inputs, and incomplete prompts leave existing files unchanged.
- Concurrent additions preserve distinct routes and reject duplicate routes.

## Work and validation

- Added the port prompt to the existing key generator and changed route publication to an atomic replacement of the base config under a directory lock.
- Preserved the generated base Host block and existing route blocks. Route values remain snapshots of the base block at creation time.
- Updated the README and focused fixture tests. Replaced the test's unavailable `hostname` dependency with `uname -n`.
- `bash -n` passed for both scripts and both tests.
- `./tests/test-new-key.sh` and `./tests/test-add-connection.sh` passed.
- `git diff --check` and both Make help commands passed. ShellCheck was unavailable on this host.

## Intended commit

- `Prompt for SSH ports and group machine routes`
