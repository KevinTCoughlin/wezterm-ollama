-- Wezterm Ollama Plugin
-- Model selection, chat sessions, and status bar integration
local wezterm = require("wezterm")

local M = {}

-- ============================================
-- Configuration Defaults
-- ============================================

local defaults = {
  host = "http://127.0.0.1:11434",
  update_interval = 2000,
  cache_ttl = 30,
  default_model = "llama3.2",
  show_status = true,
  save_sessions = false,
  sessions_dir = os.getenv("HOME") .. "/.ollama/sessions",
  keys = {
    select_model = "i",
    quick_chat = "o",
    resume_session = "O",
  },
  colors = {
    running = "#9ece6a",
    stopped = "#f7768e",
    model = "#7aa2f7",
    loading = "#e0af68",
    separator = "#565f89",
    datetime = "#565f89",
  },
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
}

-- Merge user options with defaults
local function merge_opts(user_opts)
  local opts = {}
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      opts[k] = {}
      for tk, tv in pairs(v) do
        opts[k][tk] = tv
      end
      if user_opts and user_opts[k] then
        for tk, tv in pairs(user_opts[k]) do
          opts[k][tk] = tv
        end
      end
    else
      opts[k] = user_opts and user_opts[k] ~= nil and user_opts[k] or v
    end
  end
  return opts
end

-- Store resolved options
local resolved_opts = nil

-- ============================================
-- API Helpers
-- ============================================

-- Parse JSON (simple parser for Ollama API responses)
local function parse_json_array(str, key)
  local items = {}
  -- Match array items for models list
  for item in str:gmatch('"' .. key .. '"%s*:%s*"([^"]+)"') do
    table.insert(items, item)
  end
  return items
end

local function parse_model_info(str)
  local models = {}
  local seen = {}
  -- Simple approach: find all "name":"value" patterns, filter to model names
  for name in str:gmatch('"name"%s*:%s*"([^"]+)"') do
    -- Skip if we've seen this name (avoid duplicates from "model" field)
    if not seen[name] then
      seen[name] = true
      -- Find corresponding size
      local size = str:match('"name"%s*:%s*"' .. name:gsub("([%.%-%+])", "%%%1") .. '".-"size"%s*:%s*(%d+)')
      -- Find parameter_size in details
      local params = str:match('"name"%s*:%s*"' .. name:gsub("([%.%-%+])", "%%%1") .. '".-"parameter_size"%s*:%s*"([^"]+)"')
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
  -- Find model names in /api/ps response (handles nested JSON)
  for name in str:gmatch('"name"%s*:%s*"([^"]+)"') do
    if not seen[name] then
      seen[name] = true
      table.insert(models, name)
    end
  end
  return models
end

-- Fetch models from Ollama API
local function fetch_models(opts)
  local now = os.time()
  if now - state.models_updated < opts.cache_ttl and #state.models > 0 then
    return state.models
  end

  local success, output = wezterm.run_child_process({
    "curl",
    "-s",
    "--connect-timeout", "2",
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

-- Check Ollama server status and loaded model
local function check_server_status(opts)
  local now = os.time()
  if now - state.last_check < 2 then
    return state.server_status, state.loaded_model
  end

  -- Check /api/ps for running models
  local success, output = wezterm.run_child_process({
    "curl",
    "-s",
    "--connect-timeout", "1",
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
  state.loaded_model = running[1] -- First loaded model, if any

  return state.server_status, state.loaded_model
end

-- ============================================
-- Smart Date/Time Formatter
-- ============================================

local function smart_datetime()
  local now = os.time()
  local date = os.date("*t", now)

  -- 12-hour format
  local hour = date.hour % 12
  if hour == 0 then
    hour = 12
  end
  local ampm = date.hour < 12 and "a" or "p"
  local time = string.format("%d:%02d%s", hour, date.min, ampm)

  -- Weekday for context
  local weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  local wday = weekdays[date.wday]

  return wday .. " " .. time
end

-- ============================================
-- Status Bar Elements
-- ============================================

-- Get Ollama status elements for status bar
function M.get_status_elements(opts)
  opts = opts or resolved_opts or defaults
  local elements = {}

  local status, model = check_server_status(opts)

  -- Ollama icon
  table.insert(elements, { Foreground = { Color = opts.colors.model } })
  table.insert(elements, { Text = "󰳆 " })

  if status == "running" then
    -- Running indicator (green dot)
    table.insert(elements, { Foreground = { Color = opts.colors.running } })
    table.insert(elements, { Text = "● " })

    -- Model name or "idle"
    if model then
      -- Strip tag suffix if present (e.g., "llama3.2:latest" -> "llama3.2")
      local display_name = model:match("^([^:]+)") or model
      table.insert(elements, { Foreground = { Color = opts.colors.model } })
      table.insert(elements, { Text = display_name })
    else
      table.insert(elements, { Foreground = { Color = opts.colors.separator } })
      table.insert(elements, { Text = "idle" })
    end
  elseif status == "loading" then
    -- Loading indicator (orange)
    table.insert(elements, { Foreground = { Color = opts.colors.loading } })
    table.insert(elements, { Text = "◐ loading" })
  else
    -- Stopped indicator (red)
    table.insert(elements, { Foreground = { Color = opts.colors.stopped } })
    table.insert(elements, { Text = "○ off" })
  end

  return elements
end

-- Get smart datetime elements for status bar
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
-- Model Selector (InputSelector)
-- ============================================

local function format_size(bytes)
  if not bytes or bytes == 0 then
    return ""
  end
  local gb = bytes / (1024 * 1024 * 1024)
  if gb >= 1 then
    return string.format("%.1fGB", gb)
  end
  local mb = bytes / (1024 * 1024)
  return string.format("%.0fMB", mb)
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
      if model.params and model.params ~= "" then
        table.insert(details, model.params)
      end
      if model.size > 0 then
        table.insert(details, format_size(model.size))
      end
      if #details > 0 then
        label = label .. " (" .. table.concat(details, ", ") .. ")"
      end
      table.insert(choices, {
        id = model.name,
        label = label,
      })
    end

    window:perform_action(
      wezterm.action.InputSelector({
        title = "󰳆 Select Ollama Model",
        description = "Choose a model to run",
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
          if id then
            inner_window:perform_action(
              wezterm.action.SpawnCommandInNewTab({
                args = { "/opt/homebrew/bin/ollama", "run", id },
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
  return wezterm.action.SpawnCommandInNewTab({
    args = { "/opt/homebrew/bin/ollama", "run", opts.default_model },
    set_environment_variables = { OLLAMA_MODEL = opts.default_model },
  })
end

-- Public action creators
function M.create_model_selector_action(opts)
  opts = opts or resolved_opts or defaults
  return create_model_selector_action_internal(opts)
end

function M.create_quick_chat_action(opts)
  opts = opts or resolved_opts or defaults
  return create_quick_chat_action_internal(opts)
end

-- ============================================
-- Session Persistence (Optional)
-- ============================================

local function ensure_sessions_dir(opts)
  if opts.save_sessions then
    os.execute("mkdir -p " .. opts.sessions_dir)
  end
end

local function list_sessions(opts)
  local sessions = {}
  if not opts.save_sessions then
    return sessions
  end

  local handle = io.popen("ls -t " .. opts.sessions_dir .. "/*.json 2>/dev/null | head -20")
  if handle then
    for line in handle:lines() do
      local filename = line:match("([^/]+)%.json$")
      if filename then
        table.insert(sessions, {
          path = line,
          name = filename,
        })
      end
    end
    handle:close()
  end
  return sessions
end

local function create_session_picker_action(opts)
  return wezterm.action_callback(function(window, pane)
    local sessions = list_sessions(opts)

    if #sessions == 0 then
      window:toast_notification("Ollama", "No saved sessions found", nil, 3000)
      return
    end

    local choices = {}
    for _, session in ipairs(sessions) do
      table.insert(choices, {
        id = session.path,
        label = session.name,
      })
    end

    window:perform_action(
      wezterm.action.InputSelector({
        title = "󰳆 Resume Ollama Session",
        description = "Choose a session to resume",
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
          if id then
            -- For now, just open a new chat with the model from session name
            local model = label:match("^([^_]+)")
            if model then
              inner_window:perform_action(
                wezterm.action.SpawnCommandInNewTab({
                  args = { "/opt/homebrew/bin/ollama", "run", model },
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

-- ============================================
-- Main Entry Point
-- ============================================

function M.apply_to_config(config, user_opts)
  local opts = merge_opts(user_opts)
  resolved_opts = opts

  -- Ensure sessions directory exists if enabled
  ensure_sessions_dir(opts)

  -- Add keybindings
  config.keys = config.keys or {}

  -- Model selector (LEADER + i)
  table.insert(config.keys, {
    key = opts.keys.select_model,
    mods = "LEADER",
    action = create_model_selector_action_internal(opts),
  })

  -- Quick chat (LEADER + o)
  table.insert(config.keys, {
    key = opts.keys.quick_chat,
    mods = "LEADER",
    action = create_quick_chat_action_internal(opts),
  })

  -- Session picker (LEADER + O) - only if sessions enabled
  if opts.save_sessions then
    table.insert(config.keys, {
      key = opts.keys.resume_session,
      mods = "LEADER|SHIFT",
      action = create_session_picker_action(opts),
    })
  end

  return opts
end

-- ============================================
-- Utility Exports
-- ============================================

-- Export for manual status bar composition
M.check_status = function(opts)
  opts = opts or resolved_opts or defaults
  return check_server_status(opts)
end

M.fetch_models = function(opts)
  opts = opts or resolved_opts or defaults
  return fetch_models(opts)
end

M.smart_datetime = smart_datetime

return M
