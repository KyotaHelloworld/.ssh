# Port prompt and shared machine config

- kyota requested a port prompt for `make new-key-<machine>` and multiple SSH aliases in one machine config file.
- The base alias and route aliases (`-v4`, `-v6`, `-vpn`) share one machine key. A different machine gets a separate key.
- Implemented on branch `codex/port-and-shared-routes`; see the task record for validation and handoff.
