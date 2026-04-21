SHELL := /bin/sh

.PHONY: test shellcheck

test: shellcheck
	./tests/test_cli.sh
	./tests/test_render.sh

shellcheck:
	shellcheck -s sh agentbar.tmux bin/* lib/* tests/*.sh
