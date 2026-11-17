.PHONY: check
# Shell tests for the scripts; need git, go and jq.
check:
	bash -n scripts/wt scripts/check-layers.sh
	tests/check_layers_test.sh
