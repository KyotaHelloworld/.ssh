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
    if test -e ~/.ssh; then mv ~/.ssh ~/.ssh.bk; fi
    if ! mv ~/.ssh.new ~/.ssh; then
        if test -e ~/.ssh.bk; then mv ~/.ssh.bk ~/.ssh; fi
        exit 1
    fi
)
```

Restore any required keys, private config fragments, `known_hosts`, and
`authorized_keys` from the backup after the clone.

## Create a key and config fragment

The generation command creates both the key pair and a matching ignored
`config.d/<name>.conf` fragment. Existing output is never overwritten.

```sh
make new-key-github HOST_NAME=github.com REMOTE_USER=git
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
    IdentityFile ~/.ssh/keys/github/id
    IdentitiesOnly yes
```

Every `make new-key-<name>` command asks for connection values that were not
supplied on the command line:

```console
$ make new-key-conoha
Login user name: deploy
IP address or domain: 203.0.113.10
```

The connection value may be an IP address or a domain name. The answers are
written as `User` and `HostName`. Supplying `REMOTE_USER` or `HOST_NAME` on the
command line skips the corresponding question. After these questions,
`ssh-keygen` securely asks for the key passphrase as usual.

The direct `shells/new-key.sh` command keeps these values optional unless
`--prompt-connection` is specified.

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
