.PHONY: test lint release

test:
	nvim --clean --headless -u tests/minimal_init.lua -l tests/run.lua

lint:
	luacheck lua/ tests/ --globals vim describe it setup after_each assert

release:
	gh workflow run release.yml
