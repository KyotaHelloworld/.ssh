# SSH project audit requirements

- Status: Complete
- Baseline: local `master` at `ca4b9b8`
- Branch: `codex/ssh-project-polish`
- Scope: the repository's tracked SSH configuration, key and route generators, Make interface, ignore rules, tests, and user documentation
- Audit workflow: `audit-project-thoroughly` and its audit document schema, as available on 2026-09-25
- Host baseline: Linux, GNU Bash 5.3.20, GNU Make 4.4.1, OpenSSH 10.5p1; ShellCheck unavailable

## Goals

- Find and repair evidence-backed correctness, data integrity, security, and maintainability problems in the supported SSH workflows.
- Preserve the public command behavior and private key ownership established by existing tests and README instructions.

## Out of scope

- Real SSH connections, remote hosts, live private keys, deployment, or network changes.
- New key formats, new connection features, and unrequested changes to user-specific ignored files.
- UI and device matrices; this repository provides command-line tooling only.

## Baseline and existing failures

- Baseline test result: both fixture test scripts, `bash -n`, and Make help passed.
- No tracked source changes in the new task worktree at audit start.

## Coverage matrix

| ID | Lane / scenario | Method / expected result | State |
| --- | --- | --- | --- |
| C001 | Make and direct-script inputs, help, README | Trace arguments and environment to generated output; commands and documentation agree | PASS |
| C002 | New key lifecycle | Check prompting, defaults, validation, no overwrite, permissions, and failure cleanup | PASS |
| C003 | Route lifecycle | Check base parsing, alias collisions, inherited values, atomic update, repeated and concurrent additions | PASS |
| C004 | Secret and repository hygiene | Inspect tracked/ignored paths, permissions, injection boundaries, and temporary-file handling without reading live secrets | PASS |
| C005 | Test trust and maintainability | Run fixture tests, inspect assertions and unused or duplicate code, then validate affected regressions | PASS |
| C006 | Isolated SSH system behavior | Use fixture configs with `ssh -G` for representative base, v4, v6, VPN, custom port, and separate-machine identities | PASS |

## Host and isolated-system gates

- `bash -n` on each shell script.
- `./tests/test-new-key.sh` and `./tests/test-add-connection.sh` on temporary fixtures.
- `ssh -G` only against fixture configs. No network connection is authorized or needed.
- `git diff --check` and review of final staged paths and contents.

## Severity and acceptance

- P1: core SSH correctness, private-key exposure, or data loss.
- P2: material reliability, security boundary, or maintainability issue with a plausible user path.
- P3: bounded cleanup or documentation drift.
- The audit closes when the complete matrix has terminal states, actionable findings are resolved and retested, and one final full pass finds no new actionable issue.
