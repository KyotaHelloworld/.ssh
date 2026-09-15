# Chat: Interactive ConoHa key setup

- kyota initially requested interactive login and IP questions for
  `make new-key-conoha`, then expanded the requirement to every
  `make new-key-<name>` command.
- The questions should appear in login-user then connection-address order and
  populate the generated SSH config fragment.
- The connection address accepts either an IP address or a domain name.
