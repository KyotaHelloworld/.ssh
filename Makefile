:# Self-Documented Makefile
.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

###################### settings #####################

CT = ed25519 # crypto type
PP = "" # passphrase
FN = id # key file name

# new-key-default creates  
DEFAULT_TITLE = github bitbucket mynote mydesktop

#####################################################

new-key-usage: ## print USAGE
new-key-usage-detail: ## print more detail usage

check-default: ## new-key-default で作成される鍵一覧
new-key-default: ## 基本的に必要そうな鍵を作る。check-default で確認してください。


new-key-default: $(addprefix directory, $(DEFAULT_TITLE)) $(addprefix key, $(DEFAULT_TITLE)) 
new-key-%:
	@$(eval TITLE := ${@:new-key-%=%}) 
	@# title が指定されなかったら終了させる。TITLEには、.o が入る。
	@if test "$(TITLE)" = ".o"; then exit 1; fi 
	@# new-key-default を実行したときに、TITLE=default で実行される処理を無視
	@if test "$(TITLE)" = "default"; then exit 1 ; fi 
	
	@mkdir -p keys/$(TITLE)
	@-( ssh-keygen -t $(CT) -fkeys/$(TITLE)/$(FN) -a 100 -N $(PP) -q && echo "new $(CT) type key is correctly generated in keys/$(TITLE)") || \
		echo skip generate key of $(TITLE)

directory%:
	@mkdir -p keys/${@:directory%=%}

key%:
	@$(eval TITLE := ${@:key%=%}) 
	@-( ssh-keygen -t $(CT) -fkeys/$(TITLE)/$(FN) -a 100 -N $(PP) -q \
	&& echo "new $(CT) type key is correctly generated in keys/$(TITLE)") \
	|| echo skip generate key of $(TITLE)

.PHONY: default
check-default:
	@echo "'make new-key-default' creates..."  
	@echo "    $(DEFAULT_TITLE)"
	@echo ""

.PHONY: new-key new-key- new-key-usage
new-key new-key- new-key-usage:
	@echo usage for new-key
	@echo "  - add dash(-) and title."
	@echo "  - ex) if you want to generate a new key for github"
	@echo "             \$$ make new-key-github"
	@echo "        then, keys/github has id and id.pub will be created."
	@echo ""
	@echo "more detail usage?"
	@echo "  make new-key-usage-detail"
	@echo ""

.PHONY: new-key-usage-detail
new-key-usage-detail:
	@echo "- you can specify crypto type"
	@echo "    \$$ make new-key-github CT=rsa"
	@echo ""
	@echo "- you can use passphrase"
	@echo "    \$$ make new-key-github PP=mypassphrase"
	@echo "- !countion. next command generate some keys with same PP"
	@echo "    \$$ make new-key-default PP=mypassphrase"
	@echo ""
