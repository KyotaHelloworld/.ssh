# Task: Add authorized_keys placeholder

- Branch: `feature/authorized-keys-placeholder`
- Worktree: external task worktree `authorized-keys-placeholder`
- Status: implemented and validated; awaiting user acceptance for local master integration

## Acceptance

- A fresh checkout contains a tracked `authorized_keys` file.
- The tracked file is empty and contains no account-specific key material.
- The installation procedure sets `authorized_keys` to mode 600.
- Existing private keys and local SSH data remain untouched.

## Intended commit

- `Add authorized_keys placeholder`

## Work

- Removed `authorized_keys` from the repository ignore rules.
- Added a zero-byte tracked placeholder.
- Updated the installation procedure to apply mode 600 and explain how the
  placeholder is used.

## Validation

- The staged tree contains `authorized_keys` as a regular tracked file.
- Its staged object is Git's zero-byte blob
  `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391`.
- `authorized_keys` is no longer ignored.
- Applying the documented `chmod 600` produced mode 600.
- Both staged and unstaged `git diff --check` passed.
