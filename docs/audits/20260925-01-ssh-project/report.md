# SSH project audit report

- Status: Complete
- Baseline: local `master` at `ca4b9b8`
- Final candidate: the task branch commit containing this report

## Verdict and evidence boundary

The six planned lanes passed after remediation and a second full source and fixture pass. No real SSH host, live key, or network endpoint was accessed. The isolated fixture tests exercise the observable SSH settings through `ssh -G`.

## Findings resolved

| Finding | Severity | Correction | Closing evidence |
| --- | --- | --- | --- |
| AUD-20260925-01-F001 | P1 | Refuse route creation when an earlier wildcard Host pattern could shadow the new alias; explain how to reorder the pattern. | Same-file and earlier-fragment regressions fail without a config change; a negated pattern permits the route and `ssh -G` resolves the requested host. |
| AUD-20260925-01-F002 | P3 | Remove the unused `config.d/temp` tracking exception. | `git check-ignore -v config.d/temp` selects the directory's general ignore rule. |

## Final gates

- `bash -n` passed for both production scripts and both fixture tests.
- `./tests/test-new-key.sh` and `./tests/test-add-connection.sh` passed.
- Make help and both command-help targets passed.
- `git diff --check` passed.
- The final static pass found no further actionable issue in the declared scope.

ShellCheck was unavailable on this host. Live SSH connections were outside the authorized audit boundary.

## Cleanup and continuation

The isolated reproduction fixture was removed. No tracked or ignored user key and config files were modified. The verified task branch may be integrated into local `master` after user acceptance.
