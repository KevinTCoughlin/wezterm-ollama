# wezterm-ollama

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/KevinTCoughlin/wezterm-ollama)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Wezterm plugin for [Ollama](https://ollama.ai) integration with model selection, status bar display, and quick chat.

## Features

- **Model Selector** - InputSelector dropdown with fuzzy search
- **Status Bar** - Shows Ollama server status and currently loaded model
- **Quick Chat** - One-key launch of your preferred model
- **Smart DateTime** - Compact date/time display for status bar
- **Auto-Detection** - Automatically finds ollama binary path
- **Cross-Platform** - Works on macOS (Intel/Apple Silicon) and Linux

## Installation

### From GitHub (Recommended)

```lua
local ollama = wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-ollama")
```

### Local Development

```lua
local ollama = dofile(wezterm.config_dir .. "/plugins/wezterm-ollama/plugin/init.lua")
```

## Quick Start

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Load plugin
local ollama = wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-ollama")

-- Apply with defaults
ollama.apply_to_config(config)

return config
```

## Configuration

```lua
ollama.apply_to_config(config, {
  -- Ollama API
  host = "http://127.0.0.1:11434",  -- Ollama API URL
  ollama_path = nil,                 -- Auto-detected if nil

  -- Default model for quick chat (nil = opens model selector)
  default_model = "llama3.2",

  -- Caching
  cache_ttl = 30,  -- Seconds to cache model list

  -- Features
  show_status = true,
  save_sessions = false,
  sessions_dir = "~/.ollama/sessions",

  -- Keybindings (LEADER + key, set to false to disable)
  keys = {
    select_model = "i",      -- Model selector
    quick_chat = "o",        -- Quick chat with default model
    resume_session = "O",    -- Session picker (requires save_sessions)
  },

  -- Colors (Tokyo Night defaults)
  colors = {
    running = "#9ece6a",     -- Server running (green)
    stopped = "#f7768e",     -- Server stopped (red)
    model = "#7aa2f7",       -- Model name (blue)
    loading = "#e0af68",     -- Loading state (orange)
    separator = "#565f89",   -- Separators (gray)
    datetime = "#565f89",    -- Date/time (gray)
  },

  -- Status bar icon
  icon = "🔨",
})
```

## Status Bar Integration

The plugin exports functions for composing status bar elements:

```lua
wezterm.on("update-status", function(window, pane)
  local elements = {}

  -- Add Ollama status
  for _, e in ipairs(ollama.get_status_elements()) do
    table.insert(elements, e)
  end

  -- Add smart datetime
  for _, e in ipairs(ollama.get_datetime_elements()) do
    table.insert(elements, e)
  end

  window:set_right_status(wezterm.format(elements))
end)
```

### Status Display

| Display | Meaning |
|---------|---------|
| `🔨 ● llama3.2` | Server running, model loaded |
| `🔨 ● idle` | Server running, no model loaded |
| `🔨 ○ off` | Server not running |

## Custom Keybindings

If you prefer custom keybindings instead of LEADER-based ones:

```lua
-- Disable default keybindings
ollama.apply_to_config(config, {
  keys = {
    select_model = false,
    quick_chat = false,
  },
})

-- Add custom keybindings
table.insert(config.keys, {
  key = "i",
  mods = "OPT|SHIFT",
  action = ollama.create_model_selector_action(),
})

table.insert(config.keys, {
  key = "o",
  mods = "OPT|SHIFT",
  action = ollama.create_quick_chat_action({ default_model = "deepseek-r1:7b" }),
})
```

## API Reference

### Functions

| Function | Description |
|----------|-------------|
| `apply_to_config(config, opts)` | Apply plugin to config with options |
| `get_status_elements(opts)` | Get status bar elements for Ollama |
| `get_datetime_elements(opts)` | Get smart datetime elements |
| `create_model_selector_action(opts)` | Create model selector action |
| `create_quick_chat_action(opts)` | Create quick chat action |
| `check_status(opts)` | Check Ollama server status |
| `fetch_models(opts)` | Fetch available models |
| `smart_datetime()` | Get formatted date/time string |

### Properties

| Property | Description |
|----------|-------------|
| `M._VERSION` | Plugin version (semver) |
| `M._LICENSE` | License (MIT) |
| `M._URL` | GitHub repository URL |
| `M.defaults` | Default configuration values |

## Requirements

- [Wezterm](https://wezterm.org) with plugin support
- [Ollama](https://ollama.ai) installed and running
- `curl` for API requests

## Troubleshooting

### Status shows "off" but Ollama is running

The plugin uses `127.0.0.1` instead of `localhost` because macOS may resolve `localhost` to IPv6, which Ollama doesn't support for the `/api/ps` endpoint.

### Model selector shows no models

1. Check Ollama is running: `ollama list`
2. Check API is accessible: `curl http://127.0.0.1:11434/api/tags`

### Ollama binary not found

The plugin auto-detects common paths. If yours is different, specify it:

```lua
ollama.apply_to_config(config, {
  ollama_path = "/path/to/ollama",
})
```

## License

MIT

## Contributing

Issues and PRs welcome at [GitHub](https://github.com/KevinTCoughlin/wezterm-ollama).
