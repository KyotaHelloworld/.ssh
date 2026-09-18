# Task: Add multiple SSH routes per machine

- Branch: `feature/multi-endpoint-connections`
- Worktree: external task worktree `multi-endpoint-connections`
- Status: implemented and validated; awaiting user acceptance for local master integration

## Acceptance

- `make add-connection-<machine>` prompts for a route suffix and IP/domain.
- The generated alias is `<machine>-<route>` in its own ignored fragment.
- The base `User`, optional `Port`, `IdentityFile`, and `IdentitiesOnly`
  behavior is copied, with an optional per-route port override.
- Existing keys, base fragments, and connection fragments are not modified.
- Missing/unsupported bases, invalid input, collisions, symlinks, and partial
  input fail without leaving output.
- IPv6, IPv4, domain, and VPN-style route suffixes have regression coverage.
- Each alias keeps independent SSH host-key verification; `HostKeyAlias` is not
  introduced implicitly.

## Intended commit

- `Add reusable SSH connection routes`

## Work

- Added `make add-connection-<machine>` and a direct script interface.
- Strictly parses one generator-shaped base fragment without `source`, `eval`,
  or `ssh -G`, then writes only validated values into the route fragment.
- Publishes mode-600 output atomically without replacing existing paths.
- Keeps route host-key verification independent instead of silently adding
  `HostKeyAlias`.
- Independent behavior and security reviews were incorporated before final
  validation.

## Validation

- `bash -n` passed for both production and test scripts.
- ShellCheck passed for both production and test scripts.
- `./tests/test-new-key.sh` passed.
- `./tests/test-add-connection.sh` passed, including v6/v4/VPN routes, custom
  key filenames, inherited/default/overridden ports, immutable base hashes,
  invalid and injected input, unsupported base configs, collision and symlink
  rejection, and concurrent no-replace publication.
- Make help, both command help surfaces, and `git diff --check` passed.
