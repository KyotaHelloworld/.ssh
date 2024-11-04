#!/bin/zsh
SHELLS_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
source $SHELLS_DIR/common_settings.sh



function detail_usage () {
    echo "- you can specify crypto type"
	echo "    $ make new-key-github CT=rsa"
	echo ""
	echo "- you can use passphrase"
	echo "    $ make new-key-github PP=mypassphrase"
	echo "- !countion. next command generate some keys with same PP"
	echo "    $ make new-key-default PP=mypassphrase"
	echo ""
}

function usage () {
    echo usage for new-key
	echo "  - add dash(-) and title."
	echo "  - ex) if you want to generate a new key for github"
	echo "             $ make new-key-github"
	echo "        then, keys/github has id and id.pub will be created."
	echo ""
	echo "more detail usage?"
	echo "  make new-key-usage-detail"
	echo ""
}



