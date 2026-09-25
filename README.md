# SSH settings directory

## Installation

Back up an existing SSH directory before cloning:

```sh
(
    set -eu
    test ! -e ~/.ssh.new
    test ! -e ~/.ssh.bk
    git clone https://github.com/KyotaHelloworld/.ssh.git ~/.ssh.new
    chmod 700 ~/.ssh.new
    chmod 600 ~/.ssh.new/authorized_keys
    if test -e ~/.ssh; then mv ~/.ssh ~/.ssh.bk; fi
    if ! mv ~/.ssh.new ~/.ssh; then
        if test -e ~/.ssh.bk; then mv ~/.ssh.bk ~/.ssh; fi
        exit 1
    fi
)
```

The repository includes an empty `authorized_keys` file. Add any required
public keys locally after cloning. Restore private keys, private config
fragments, and `known_hosts` from the backup as needed.

## Create a key and config fragment

The generation command creates both the key pair and a matching ignored
`config.d/<name>.conf` fragment. Existing output is never overwritten.

```sh
make new-key-github HOST_NAME=github.com REMOTE_USER=git SSH_PORT=22
```

This creates:

```text
keys/github/id
keys/github/id.pub
config.d/github.conf
```

The generated fragment contains every supplied connection value plus the values
that can always be derived safely:

```sshconfig
Host github
    HostName github.com
    User git
    Port 22
    IdentityFile ~/.ssh/keys/github/id
    IdentitiesOnly yes
```

Every `make new-key-<name>` command asks for connection values that were not
supplied on the command line:

```console
$ make new-key-conoha
Login user name: deploy
IP address or domain: 203.0.113.10
SSH port (blank for 22): 2202
```

The connection value may be an IP address or a domain name. The answers are
written as `User`, `HostName`, and `Port`. Supplying `REMOTE_USER`, `HOST_NAME`,
or `SSH_PORT` skips the corresponding question. A blank port uses SSH's default
port 22 and omits `Port` from the fragment. After these questions,
`ssh-keygen` securely asks for the key passphrase as usual.

The direct `shells/new-key.sh` command keeps these values optional unless
`--prompt-connection` is specified.

Unless `KEY_COMMENT` is supplied, the public-key comment uses `ssh-keygen`'s
local `user@hostname` default so it identifies the PC that created the key.
The remote login user and destination remain in the generated SSH config. To
set an explicit comment instead:

```sh
make new-key-service KEY_COMMENT='shared deployment key'
```

## Add another route to the same machine

An existing machine can have separate IPv6, IPv4, and VPN addresses while
using the same login user and key. Add a route without generating or copying a
private key:

```console
$ make add-connection-bakery
Connection suffix (for example v6, v4, or vpn): v6
IP address or domain: 2001:db8::10
```

This adds `Host bakery-v6` to `config.d/bakery.conf`. It copies the current
`User`, optional `Port`, `IdentityFile`, and `IdentitiesOnly` values from the
base `Host bakery` block. Existing blocks and `keys/bakery/` are preserved.
Repeat the command with `v4` or `vpn` to add those routes to the same file.

For example, one machine can use `ssh baikin-ufo`, `ssh baikin-ufo-vpn`, and
`ssh baikin-ufo-v4`. All three aliases point to the key in
`keys/baikin-ufo/`; a different machine created with `make new-key-<name>`
gets its own key directory.

Values may be supplied for non-interactive use:

```sh
make add-connection-bakery \
    CONNECTION_NAME=vpn \
    HOST_NAME=bakery.vpn.example

# Override the copied port only when this route needs a different listener.
make add-connection-bakery \
    CONNECTION_NAME=v4 \
    HOST_NAME=198.51.100.20 \
    SSH_PORT=22
```

Route blocks are snapshots: changing the base block later does not update
routes already added. Existing aliases are never overwritten. The updated
config is prepared in a temporary file and then replaced; a failed validation
leaves it unchanged. Direct script usage stays non-interactive unless
`--prompt-connection` is supplied; see `make add-connection` for every option.

Each alias performs its own normal SSH host-key verification because this
command does not add `HostKeyAlias`. That avoids silently trusting that every
address actually reaches the same SSH server.

Additional options:

```sh
# RSA 4096-bit key with a custom filename
make new-key-service KEY_TYPE=rsa KEY_FILE=service.id

# CT and FN remain supported as legacy aliases
make new-key-service CT=rsa FN=service.id

# Explicitly create a key without a passphrase
make new-key-service NO_PASSPHRASE=1

# Show all options
make new-key
```

By default, `ssh-keygen` prompts securely for the passphrase. A passphrase is
never accepted as a Make variable or command-line argument.

`make new-key-default` creates the `github` and `forgejo` entries sequentially.
Complete existing entries are skipped, so an interrupted run can be resumed;
partial entries still fail instead of being overwritten.

## Private keys

Do not track real private keys. Files below `keys/` are ignored except for the
intentional, unused `keys/sample/` fixture.

The default key type is Ed25519. Use RSA only when compatibility requires it.

## SSH config

The root `config` includes `~/.ssh/config.d/*.conf`. Generated fragments are
ignored because they can contain private host and account information.
