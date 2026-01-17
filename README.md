# wezterm-ollama

Wezterm plugin for Ollama integration with model selection, status bar, and chat sessions.

## Features

- **Model Selector**: InputSelector dropdown with fuzzy search to pick and run models
- **Status Bar**: Shows Ollama server status, loaded model, and smart date/time
- **Quick Chat**: One-key launch of your default model
- **Session Persistence**: Optional session saving and resumption

## Installation

### Local (Development)

```lua
-- In your wezterm.lua
local ollama = require("plugins.wezterm-ollama.plugin")
```

### From GitHub

```lua
local ollama = wezterm.plugin.require("https://github.com/<user>/wezterm-ollama")
```

## Usage

### Basic Setup

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Load plugin
local ollama = require("plugins.wezterm-ollama.plugin")

-- Apply configuration
local ollama_opts = ollama.apply_to_config(config, {
  default_model = "llama3.2",
})

return config
```

### Status Bar Integration

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

## Keybindings

All keybindings use LEADER prefix (default: `Ctrl+a`):

| Key | Action |
|-----|--------|
| `LEADER i` | Open model selector |
| `LEADER o` | Quick chat with default model |
| `LEADER O` | Resume session picker (if enabled) |

## Configuration Options

```lua
ollama.apply_to_config(config, {
  -- API
  host = "http://localhost:11434",  -- Ollama API URL
  cache_ttl = 30,                   -- Seconds to cache model list

  -- Status bar
  show_status = true,               -- Show in status bar
  update_interval = 2000,           -- ms between status checks

  -- Models
  default_model = "llama3.2",       -- Model for quick chat

  -- Keys (all use LEADER prefix)
  keys = {
    select_model = "i",             -- Model selector
    quick_chat = "o",               -- Quick chat
    resume_session = "O",           -- Session picker
  },

  -- Sessions (optional)
  save_sessions = false,            -- Enable session persistence
  sessions_dir = "~/.ollama/sessions",

  -- Colors (Tokyo Night defaults)
  colors = {
    running = "#9ece6a",            -- Server running (green)
    stopped = "#f7768e",            -- Server stopped (red)
    model = "#7aa2f7",              -- Model name (blue)
    loading = "#e0af68",            -- Loading state (orange)
    separator = "#565f89",          -- Separator color
    datetime = "#565f89",           -- Date/time color
  },
})
```

## Status Bar Format

```
󰳆 ● llama3.2  │  Fri 2:30p
```

**Status Indicators:**

| Display | Meaning |
|---------|---------|
| `󰳆 ● model` | Running with model loaded (green) |
| `󰳆 ● idle` | Running, no model loaded (green) |
| `󰳆 ○ off` | Server not running (red) |
| `󰳆 ◐ loading` | Model loading (orange) |

**Smart Date/Time:**

- 12-hour format with lowercase am/pm
- Shows weekday and time: "Fri 2:30p"

## API Functions

```lua
-- Get status bar elements for Ollama
ollama.get_status_elements(opts)  -- Returns table of format elements

-- Get smart datetime elements
ollama.get_datetime_elements(opts)  -- Returns table of format elements

-- Check server status manually
local status, model = ollama.check_status(opts)

-- Fetch available models
local models = ollama.fetch_models(opts)

-- Get smart datetime string
local dt = ollama.smart_datetime()
```

## Requirements

- Wezterm (with plugin support)
- Ollama installed and accessible via `ollama` command
- `curl` for API requests

## License

MIT
