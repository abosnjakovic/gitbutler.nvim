.PHONY: help ci test lint fmt fmt-check test-release check-env clean

help: ## List available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ci: fmt-check lint test ## Run everything CI runs (stylua --check, luacheck, tests)

test: ## Run nvim --headless test suite
	nvim --clean --headless -u tests/minimal_init.lua -l tests/run.lua

lint: ## Run luacheck
	luacheck lua/ tests/

fmt: ## Format Lua sources with stylua
	stylua lua/ tests/

fmt-check: ## Check formatting without modifying files
	stylua --check lua/ tests/

test-release: ## Dry-run the release-please bump locally (no push, no tag)
	./scripts/test_release.sh

check-env: ## Verify GH CLI is authenticated
	@gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated. Run: gh auth login"; exit 1; }
	@echo "gh CLI authenticated."

clean: ## Remove cache directories
	rm -rf .stylua-cache
