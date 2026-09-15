.DEFAULT_GOAL := help

KEY_TYPE ?= ed25519
KEY_FILE ?= id
HOST_NAME ?=
REMOTE_USER ?=
SSH_PORT ?=
KEY_COMMENT ?=
NO_PASSPHRASE ?= 0
SKIP_EXISTING ?= 0

ifneq ($(origin CT), undefined)
ifneq ($(origin KEY_TYPE), file)
$(error use only one of CT and KEY_TYPE)
endif
KEY_TYPE := $(value CT)
endif

ifneq ($(origin FN), undefined)
ifneq ($(origin KEY_FILE), file)
$(error use only one of FN and KEY_FILE)
endif
KEY_FILE := $(value FN)
endif

ifneq ($(origin PP), undefined)
$(error PP is no longer supported; let ssh-keygen prompt or set NO_PASSPHRASE=1)
endif

export SSH_NEW_KEY_TYPE := $(value KEY_TYPE)
export SSH_NEW_KEY_FILE := $(value KEY_FILE)
export SSH_NEW_KEY_HOST := $(value HOST_NAME)
export SSH_NEW_KEY_USER := $(value REMOTE_USER)
export SSH_NEW_KEY_PORT := $(value SSH_PORT)
export SSH_NEW_KEY_COMMENT := $(value KEY_COMMENT)
export SSH_NEW_KEY_NO_PASSPHRASE := $(value NO_PASSPHRASE)
export SSH_NEW_KEY_SKIP_EXISTING := $(value SKIP_EXISTING)

.PHONY: help new-key new-key-usage new-key-usage-detail check-default new-key-default FORCE

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}' Makefile

new-key: ## Show key-generation usage
	@./shells/new-key.sh --help

new-key-%: export SSH_NEW_KEY_NAME = $*
new-key-%: export SSH_NEW_KEY_PROMPT_CONNECTION = 1
new-key-%: FORCE
	@./shells/new-key.sh

new-key-default: ## Create the default key/config set sequentially
	@$(MAKE) --no-print-directory new-key-github SKIP_EXISTING=1
	@$(MAKE) --no-print-directory new-key-forgejo SKIP_EXISTING=1

check-default: ## Show names created by new-key-default
	@printf '%s\n' "'make new-key-default' creates:" "    github forgejo"

new-key-usage: new-key ## Alias for new-key help

new-key-usage-detail: new-key ## Legacy alias for new-key help

FORCE:
