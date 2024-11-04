#!/bin/zsh
gen_file=$(basename $0)
gen_dir=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
echo "gen_file = $gen_file"
echo "gen_dir = $gen_dir"
# arguments
# 0:鍵の名前

# HINT: 相対パスは、実行場所からのパス
# make コマンドでもそう。
function newkey() {
    TITLE=$1
    if [[ -z $TITLE ]]; then
        echo "specify title"
        return
    fi
    echo "title is $TITLE"
    

    if [[ ! -e ./gen.sh ]]; then
        echo "none"
    fi


}

newkey $1


echo "0 = $0"
