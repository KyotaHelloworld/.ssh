# SSH project audit status

- Updated: 2026-09-25
- Baseline / candidate: `ca4b9b8` / validated task branch state
- Phase: Final
- Overall: Complete

## Coverage summary

- C001–C006: PASS after a second complete source and fixture pass.

## Findings

| ID | Severity | Confidence | Summary | Evidence | State |
| --- | --- | --- | --- | --- | --- |
| AUD-20260925-01-F001 | P1 | Confirmed | An earlier wildcard `Host machine-*` in the machine config shadows a newly appended exact route. | Isolated fixture: adding `machine-vpn` with `HostName vpn.example` reported success, but `ssh -G` resolved `wildcard.example`. | RESOLVED |
| AUD-20260925-01-F002 | P3 | Confirmed | The unused `!temp` exception makes `config.d/temp` eligible for tracking despite the directory's private-config ignore policy. | `git check-ignore -v config.d/temp` selected the exception; no code or documentation uses this path. | RESOLVED |

F001 violated the requirement that a successful route command reach the requested destination. The command now refuses a matching earlier wildcard before writing. The regression test covers a wildcard in the same file, one in an earlier fragment, and a negated exception; `ssh -G` confirms the permitted route.

F002 violated the repository's private-fragment default. The exception was removed and `git check-ignore -v config.d/temp` now selects the general ignore rule.

## Remediation batches

- F001: added a conservative Host-pattern guard, a failure message with a recovery path, README guidance, and focused regression cases.
- F002: removed the unused `!temp` exception from `config.d/.gitignore`.

## Validation runs

- Baseline: both fixture test scripts passed; `bash -n` and Make help passed.
- Isolated SSH baseline: the existing tests cover base, v4, v6, VPN, port, and separate-machine identity resolution; the wildcard counterexample failed as documented above.
- Final: `bash -n` passed for all four shell scripts; both fixture tests passed. The route test now checks wildcard failure and a negated pattern's successful `ssh -G` resolution.
- Final: Make help and both command-help targets passed; `git check-ignore` selected the intended rules for private config and key paths; `git diff --check` passed.
- Second static pass covered Make, scripts, tests, root SSH config, ignore rules, and README. No new actionable finding was found.

## External boundaries

- Real SSH hosts, live private keys, and network connections were not touched.
- ShellCheck is unavailable; Bash syntax and behavioral fixture tests are the available gates.

## Exact next action

Await user acceptance before local `master` integration.
