-- wezterm-ollama: Ollama integration for Wezterm
-- https://github.com/KevinTCoughlin/wezterm-ollama
--
-- Features:
--   - Model selector with InputSelector
--   - Status bar integration (server status, loaded model)
--   - Quick chat keybinding
--   - Smart datetime display

local wezterm = require("wezterm")

local M = {}

-- ============================================
-- Plugin Metadata
-- ============================================

M._VERSION = "1.0.0"
M._LICENSE = "MIT"
M._URL = "https://github.com/KevinTCoughlin/wezterm-ollama"

-- ============================================
-- Platform Detection & Paths
-- ============================================

local function detect_ollama_path()
  -- Check common installation paths
  local paths = {
    "/opt/homebrew/bin/ollama",  -- macOS Homebrew (Apple Silicon)
    "/usr/local/bin/ollama",     -- macOS Homebrew (Intel) / Linux
    "/usr/bin/ollama",           -- Linux package manager
  }
  for _, path in ipairs(paths) do
    local f = io.open(path, "r")
    if f then
      f:close()
      return path
    end
  end
  -- Fallback to PATH lookup
  return "ollama"
end

-- ============================================
-- Configuration Defaults
-- ============================================

local defaults = {
  -- Ollama API settings
  host = "http://127.0.0.1:11434",
  ollama_path = nil,  -- Auto-detected if nil

  -- Status bar
  update_interval = 2000,  -- ms between status checks
  cache_ttl = 30,          -- seconds to cache model list

  -- Default model for quick chat (nil = first available)
  default_model = nil,

  -- Feature flags
  show_status = true,
  save_sessions = false,
  sessions_dir = (os.getenv("HOME") or "") .. "/.ollama/sessions",

  -- Keybindings (set to false to disable)
  keys = {
    select_model = "i",      -- LEADER + key
    quick_chat = "o",        -- LEADER + key
    resume_session = "O",    -- LEADER + SHIFT + key
  },

  -- Status bar colors (Tokyo Night defaults)
  colors = {
    running = "#9ece6a",     -- Green
    stopped = "#f7768e",     -- Red
    model = "#7aa2f7",       -- Blue
    loading = "#e0af68",     -- Orange
    separator = "#565f89",   -- Gray
    datetime = "#565f89",    -- Gray
  },

  -- Status bar icon
  icon = "🦙",
}

-- ============================================
-- State Management
-- ============================================

local state = {
  models = {},
  models_updated = 0,
  server_status = "unknown",
  loaded_model = nil,
  last_check = 0,
  ollama_path = nil,
}

-- Deep merge user options with defaults
local function merge_opts(user_opts)
  user_opts = user_opts or {}
  local opts = {}

  for k, v in pairs(defaults) do
    if type(v) == "table" then
      opts[k] = {}
      for tk, tv in pairs(v) do
        opts[k][tk] = tv
      end
      if user_opts[k] and type(user_opts[k]) == "table" then
        for tk, tv in pairs(user_opts[k]) do
          opts[k][tk] = tv
        end
      end
    else
      opts[k] = user_opts[k] ~= nil and user_opts[k] or v
    end
  end

  -- Auto-detect ollama path if not specified
  if not opts.ollama_path then
    opts.ollama_path = detect_ollama_path()
  end
  state.ollama_path = opts.ollama_path

  return opts
end

-- Resolved options (set after apply_to_config)
local resolved_opts = nil

-- ============================================
-- JSON Parsing Helpers
-- ============================================

local function parse_model_info(str)
  local models = {}
  local seen = {}

  for name in str:gmatch('"name"%s*:%s*"([^"]+)"') do
    if not seen[name] then
      seen[name] = true
      local escaped = name:gsub("([%.%-%+%:])", "%%%1")
      local size = str:match('"name"%s*:%s*"' .. escaped .. '".-"size"%s*:%s*(%d+)')
      local params = str:match('"name"%s*:%s*"' .. escaped .. '".-"parameter_size"%s*:%s*"([^"]+)"')
      table.insert(models, {
        name = name,
        size = size and tonumber(size) or 0,
        params = params or "",
      })
    end
  end
  return models
end

local function parse_running_models(str)
  local models = {}
  local seen = {}

  for name in str:gmatch('"name"%s*:%s*"([^"]+)"') do
    if not seen[name] then
      seen[name] = true
      table.insert(models, name)
    end
  end
  return models
end

-- ============================================
-- Ollama API
-- ============================================

local function fetch_models(opts)
  local now = os.time()
  if now - state.models_updated < opts.cache_ttl and #state.models > 0 then
    return state.models
  end

  local success, output = wezterm.run_child_process({
    "curl", "-s", "--connect-timeout", "2",
    opts.host .. "/api/tags",
  })

  if success and output and output ~= "" then
    state.models = parse_model_info(output)
    state.models_updated = now
    state.server_status = "running"
  else
    state.server_status = "stopped"
  end

  return state.models
end

local function check_server_status(opts)
  local now = os.time()
  if now - state.last_check < 15 then
    return state.server_status, state.loaded_model
  end

  local success, output = wezterm.run_child_process({
    "curl", "-s", "--connect-timeout", "1",
    opts.host .. "/api/ps",
  })

  state.last_check = now

  if not success or not output or output == "" then
    state.server_status = "stopped"
    state.loaded_model = nil
    return state.server_status, state.loaded_model
  end

  state.server_status = "running"
  local running = parse_running_models(output)
  state.loaded_model = running[1]

  return state.server_status, state.loaded_model
end

-- ============================================
-- Smart Date/Time Formatter
-- ============================================

local function smart_datetime()
  local date = os.date("*t")
  local hour = date.hour % 12
  if hour == 0 then hour = 12 end
  local ampm = date.hour < 12 and "a" or "p"
  local weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  return string.format("%s %d:%02d%s", weekdays[date.wday], hour, date.min, ampm)
end

-- ============================================
-- Status Bar Elements
-- ============================================

function M.get_status_elements(opts)
  opts = opts or resolved_opts or defaults
  local elements = {}
  local status, model = check_server_status(opts)

  -- Icon
  table.insert(elements, { Foreground = { Color = opts.colors.model } })
  table.insert(elements, { Text = opts.icon .. " " })

  if status == "running" then
    table.insert(elements, { Foreground = { Color = opts.colors.running } })
    table.insert(elements, { Text = "● " })

    if model then
      local display_name = model:match("^([^:]+)") or model
      table.insert(elements, { Foreground = { Color = opts.colors.model } })
      table.insert(elements, { Text = display_name })
    else
      table.insert(elements, { Foreground = { Color = opts.colors.separator } })
      table.insert(elements, { Text = "idle" })
    end
  elseif status == "loading" then
    table.insert(elements, { Foreground = { Color = opts.colors.loading } })
    table.insert(elements, { Text = "◐ loading" })
  else
    table.insert(elements, { Foreground = { Color = opts.colors.stopped } })
    table.insert(elements, { Text = "○ off" })
  end

  return elements
end

function M.get_datetime_elements(opts)
  opts = opts or resolved_opts or defaults
  return {
    { Foreground = { Color = opts.colors.separator } },
    { Text = "  │  " },
    { Foreground = { Color = opts.colors.datetime } },
    { Text = smart_datetime() .. "  " },
  }
end

-- ============================================
-- Actions
-- ============================================

local function format_size(bytes)
  if not bytes or bytes == 0 then return "" end
  local gb = bytes / (1024 * 1024 * 1024)
  if gb >= 1 then return string.format("%.1fGB", gb) end
  return string.format("%.0fMB", bytes / (1024 * 1024))
end

local function create_model_selector_action_internal(opts)
  return wezterm.action_callback(function(window, pane)
    local models = fetch_models(opts)

    if #models == 0 then
      window:toast_notification("Ollama", "No models found. Is Ollama running?", nil, 3000)
      return
    end

    local choices = {}
    for _, model in ipairs(models) do
      local label = model.name
      local details = {}
      if model.params ~= "" then table.insert(details, model.params) end
      if model.size > 0 then table.insert(details, format_size(model.size)) end
      if #details > 0 then label = label .. " (" .. table.concat(details, ", ") .. ")" end
      table.insert(choices, { id = model.name, label = label })
    end

    window:perform_action(
      wezterm.action.InputSelector({
        title = opts.icon .. " Select Ollama Model",
        description = "Choose a model to run",
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(inner_window, inner_pane, id)
          if id then
            inner_window:perform_action(
              wezterm.action.SpawnCommandInNewTab({
                args = { opts.ollama_path, "run", id },
                set_environment_variables = { OLLAMA_MODEL = id },
              }),
              inner_pane
            )
          end
        end),
      }),
      pane
    )
  end)
end

local function create_quick_chat_action_internal(opts)
  -- If no default model, use model selector instead
  if not opts.default_model then
    return create_model_selector_action_internal(opts)
  end

  return wezterm.action.SpawnCommandInNewTab({
    args = { opts.ollama_path, "run", opts.default_model },
    set_environment_variables = { OLLAMA_MODEL = opts.default_model },
  })
end

local function create_session_picker_action_internal(opts)
  return wezterm.action_callback(function(window, pane)
    if not opts.save_sessions then
      window:toast_notification("Ollama", "Session persistence not enabled", nil, 3000)
      return
    end

    local handle = io.popen("ls -t " .. opts.sessions_dir .. "/*.json 2>/dev/null | head -20")
    local sessions = {}
    if handle then
      for line in handle:lines() do
        local filename = line:match("([^/]+)%.json$")
        if filename then
          table.insert(sessions, { path = line, name = filename })
        end
      end
      handle:close()
    end

    if #sessions == 0 then
      window:toast_notification("Ollama", "No saved sessions found", nil, 3000)
      return
    end

    local choices = {}
    for _, session in ipairs(sessions) do
      table.insert(choices, { id = session.path, label = session.name })
    end

    window:perform_action(
      wezterm.action.InputSelector({
        title = opts.icon .. " Resume Ollama Session",
        description = "Choose a session to resume",
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
          if id then
            local model = label:match("^([^_]+)")
            if model then
              inner_window:perform_action(
                wezterm.action.SpawnCommandInNewTab({
                  args = { opts.ollama_path, "run", model },
                  set_environment_variables = { OLLAMA_MODEL = model },
                }),
                inner_pane
              )
            end
          end
        end),
      }),
      pane
    )
  end)
end

-- Public action creators (for custom keybindings)
function M.create_model_selector_action(opts)
  return create_model_selector_action_internal(opts or resolved_opts or defaults)
end

function M.create_quick_chat_action(opts)
  return create_quick_chat_action_internal(opts or resolved_opts or defaults)
end

function M.create_session_picker_action(opts)
  return create_session_picker_action_internal(opts or resolved_opts or defaults)
end

-- ============================================
-- Main Entry Point
-- ============================================

function M.apply_to_config(config, user_opts)
  local opts = merge_opts(user_opts)
  resolved_opts = opts

  -- Ensure sessions directory exists if enabled
  if opts.save_sessions then
    os.execute("mkdir -p " .. opts.sessions_dir)
  end

  -- Add keybindings (if not disabled)
  config.keys = config.keys or {}

  if opts.keys.select_model then
    table.insert(config.keys, {
      key = opts.keys.select_model,
      mods = "LEADER",
      action = create_model_selector_action_internal(opts),
    })
  end

  if opts.keys.quick_chat then
    table.insert(config.keys, {
      key = opts.keys.quick_chat,
      mods = "LEADER",
      action = create_quick_chat_action_internal(opts),
    })
  end

  if opts.save_sessions and opts.keys.resume_session then
    table.insert(config.keys, {
      key = opts.keys.resume_session,
      mods = "LEADER|SHIFT",
      action = create_session_picker_action_internal(opts),
    })
  end

  return opts
end

-- ============================================
-- Utility Exports
-- ============================================

M.check_status = function(opts)
  return check_server_status(opts or resolved_opts or defaults)
end

M.fetch_models = function(opts)
  return fetch_models(opts or resolved_opts or defaults)
end

M.smart_datetime = smart_datetime
M.defaults = defaults

return M
