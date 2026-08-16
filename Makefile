LUA ?= lua
LUAC ?= luac

.PHONY: check integration syntax test

check: syntax test

syntax:
	$(LUAC) -p plugin/init.lua tests/test_plugin.lua tests/wezterm_config.lua

test:
	$(LUA) tests/test_plugin.lua

integration:
	wezterm --config-file tests/wezterm_config.lua show-keys --lua >/dev/null
