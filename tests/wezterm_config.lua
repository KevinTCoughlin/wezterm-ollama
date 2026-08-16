local wezterm = require("wezterm")
local plugin = dofile("plugin/init.lua")
local config = wezterm.config_builder()

plugin.apply_to_config(config)

return config
