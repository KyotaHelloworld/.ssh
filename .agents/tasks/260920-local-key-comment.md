# Task: Restore local public-key comments

- Branch: `feature/local-key-comment`
- Worktree: external task worktree `local-key-comment`
- Status: implemented and validated; authorized for merge and push

## Acceptance

- A newly generated public key uses the generating PC's local
  `user@hostname` comment by default.
- Remote `User` and `HostName` values remain only in the SSH config fragment.
- `KEY_COMMENT` and `--comment` continue to override the default explicitly.
- Existing key files are not changed.
- The accepted change is merged to `master` and pushed to `origin/master`.

## Intended commit

- `Use local identity in public-key comments`

## Work

- Removed the generated `ssh-key:<name>` fallback.
- Passes `-C` to `ssh-keygen` only for an explicit comment.
- Added default and explicit-comment regression assertions.
- Documented the local-versus-remote identity boundary.

## Validation

- `bash -n` passed for the generator and its regression suite.
- ShellCheck passed for both scripts.
- `./tests/test-new-key.sh` passed, including the default local
  `user@hostname` assertion and explicit custom-comment override.
- `./tests/test-add-connection.sh` passed as a route-generation regression.
- Make help surfaces and `git diff --check` passed.
- The branch changes no existing file under `keys/`.
