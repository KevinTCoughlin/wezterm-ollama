-- wezterm-ollama: Ollama integration for WezTerm
-- https://github.com/KevinTCoughlin/wezterm-ollama

local wezterm = require("wezterm")
local M = {}

M._VERSION = "1.0.0"
M._LICENSE = "MIT"
M._URL = "https://github.com/KevinTCoughlin/wezterm-ollama"

local function detect_ollama_path()
  local paths = {
    "/opt/homebrew/bin/ollama",
    "/usr/local/bin/ollama",
    "/usr/bin/ollama",
  }
  for _, path in ipairs(paths) do
    local file = io.open(path, "r")
    if file then
      file:close()
      return path
    end
  end
  return "ollama"
end

local defaults = {
  host = "http://127.0.0.1:11434",
  ollama_path = nil,
  update_interval = 15000,
  cache_ttl = 30,
  default_model = nil,
  save_sessions = false,
  sessions_dir = (os.getenv("HOME") or "") .. "/.ollama/sessions",
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
  icon = "🦙",
}

local state = {
  models = {},
  models_updated = 0,
  models_host = nil,
  server_status = "unknown",
  loaded_model = nil,
  last_check = 0,
  status_host = nil,
}

local function copy_table(value)
  local result = {}
  for key, item in pairs(value) do
    result[key] = type(item) == "table" and copy_table(item) or item
  end
  return result
end

local function normalize_host(host)
  if type(host) ~= "string" or host == "" then
    error("wezterm-ollama: host must be a non-empty HTTP(S) URL")
  end
  if not host:match("^https?://") then
    error("wezterm-ollama: host must use http:// or https://")
  end
  return host:gsub("/+$", "")
end

local function expand_home(path)
  if path == "~" or path:sub(1, 2) == "~/" then
    local home = os.getenv("HOME")
    if not home or home == "" then
      error("wezterm-ollama: HOME must be set to expand sessions_dir")
    end
    return home .. path:sub(2)
  end
  return path
end

local function resolve_opts(user_opts)
  if user_opts ~= nil and type(user_opts) ~= "table" then
    error("wezterm-ollama: options must be a table")
  end

  local opts = copy_table(defaults)
  for key, value in pairs(user_opts or {}) do
    if type(opts[key]) == "table" and type(value) == "table" then
      for nested_key, nested_value in pairs(value) do
        opts[key][nested_key] = nested_value
      end
    else
      opts[key] = value
    end
  end

  opts.host = normalize_host(opts.host)
  opts.ollama_path = opts.ollama_path or detect_ollama_path()
  opts.sessions_dir = expand_home(opts.sessions_dir)

  if type(opts.ollama_path) ~= "string" or opts.ollama_path == "" then
    error("wezterm-ollama: ollama_path must be a non-empty string")
  end
  if type(opts.cache_ttl) ~= "number" or opts.cache_ttl < 0 then
    error("wezterm-ollama: cache_ttl must be a non-negative number")
  end
  if type(opts.update_interval) ~= "number" or opts.update_interval < 0 then
    error("wezterm-ollama: update_interval must be a non-negative number")
  end
  if type(opts.keys) ~= "table" or type(opts.colors) ~= "table" then
    error("wezterm-ollama: keys and colors must be tables")
  end
  if type(opts.sessions_dir) ~= "string" or opts.sessions_dir == ""
      or opts.sessions_dir:sub(1, 1) == "-" then
    error("wezterm-ollama: sessions_dir must be a non-empty path")
  end

  return opts
end

local resolved_opts = nil

local function safe_json_parse(output)
  if type(output) ~= "string" or output == "" then
    return nil
  end
  local ok, result = pcall(wezterm.json_parse, output)
  if not ok or type(result) ~= "table" then
    wezterm.log_error("wezterm-ollama: invalid JSON returned by Ollama")
    return nil
  end
  return result
end

local function request_json(opts, path, timeout_seconds)
  local success, output, stderr = wezterm.run_child_process({
    "curl",
    "--fail",
    "--silent",
    "--show-error",
    "--connect-timeout",
    tostring(timeout_seconds),
    "--max-time",
    tostring(timeout_seconds),
    "--",
    opts.host .. path,
  })

  if not success then
    if stderr and stderr ~= "" then
      wezterm.log_error("wezterm-ollama: Ollama request failed: " .. stderr:gsub("%s+$", ""))
    end
    return nil
  end
  return safe_json_parse(output)
end

local function parse_model_info(response)
  if type(response.models) ~= "table" then
    return nil
  end

  local models = {}
  local seen = {}
  for _, model in ipairs(response.models) do
    if type(model) == "table" then
      local name = model.name or model.model
      if type(name) == "string" and name ~= "" and not seen[name] then
        seen[name] = true
        local details = type(model.details) == "table" and model.details or {}
        table.insert(models, {
          name = name,
          size = type(model.size) == "number" and model.size or 0,
          params = type(details.parameter_size) == "string" and details.parameter_size or "",
        })
      end
    end
  end
  return models
end

local function parse_running_models(response)
  if type(response.models) ~= "table" then
    return nil
  end

  local models = {}
  local seen = {}
  for _, model in ipairs(response.models) do
    if type(model) == "table" then
      local name = model.name or model.model
      if type(name) == "string" and name ~= "" and not seen[name] then
        seen[name] = true
        table.insert(models, name)
      end
    end
  end
  return models
end

local function fetch_models(opts)
  local now = os.time()
  if state.models_host == opts.host
      and now - state.models_updated < opts.cache_ttl
      and #state.models > 0 then
    return state.models
  end

  local response = request_json(opts, "/api/tags", 2)
  local models = response and parse_model_info(response) or nil
  if not models then
    return {}
  end
  state.models = models
  state.models_updated = now
  state.models_host = opts.host
  return state.models
end

local function check_server_status(opts)
  local now = os.time()
  local interval_seconds = math.max(1, math.ceil(opts.update_interval / 1000))
  if state.status_host == opts.host and now - state.last_check < interval_seconds then
    return state.server_status, state.loaded_model
  end

  local response = request_json(opts, "/api/ps", 1)
  local running = response and parse_running_models(response) or nil
  state.last_check = now
  state.status_host = opts.host

  if not running then
    state.server_status = "stopped"
    state.loaded_model = nil
  else
    state.server_status = "running"
    state.loaded_model = running[1]
  end
  return state.server_status, state.loaded_model
end

local function smart_datetime()
  local date = os.date("*t")
  local hour = date.hour % 12
  if hour == 0 then
    hour = 12
  end
  local ampm = date.hour < 12 and "a" or "p"
  local weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  return string.format("%s %d:%02d%s", weekdays[date.wday], hour, date.min, ampm)
end

function M.get_status_elements(user_opts)
  local opts = user_opts and resolve_opts(user_opts) or resolved_opts or resolve_opts()
  local elements = {}
  local status, model = check_server_status(opts)

  table.insert(elements, { Foreground = { Color = opts.colors.model } })
  table.insert(elements, { Text = opts.icon .. " " })
  if status == "running" then
    table.insert(elements, { Foreground = { Color = opts.colors.running } })
    table.insert(elements, { Text = "● " })
    if model then
      table.insert(elements, { Foreground = { Color = opts.colors.model } })
      table.insert(elements, { Text = model:match("^([^:]+)") or model })
    else
      table.insert(elements, { Foreground = { Color = opts.colors.separator } })
      table.insert(elements, { Text = "idle" })
    end
  else
    table.insert(elements, { Foreground = { Color = opts.colors.stopped } })
    table.insert(elements, { Text = "○ off" })
  end
  return elements
end

function M.get_datetime_elements(user_opts)
  local opts = user_opts and resolve_opts(user_opts) or resolved_opts or resolve_opts()
  return {
    { Foreground = { Color = opts.colors.separator } },
    { Text = "  │  " },
    { Foreground = { Color = opts.colors.datetime } },
    { Text = smart_datetime() .. "  " },
  }
end

local function format_size(bytes)
  if not bytes or bytes == 0 then
    return ""
  end
  local gb = bytes / (1024 * 1024 * 1024)
  if gb >= 1 then
    return string.format("%.1fGB", gb)
  end
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
      if model.params ~= "" then
        table.insert(details, model.params)
      end
      if model.size > 0 then
        table.insert(details, format_size(model.size))
      end
      if #details > 0 then
        label = label .. " (" .. table.concat(details, ", ") .. ")"
      end
      table.insert(choices, { id = model.name, label = label })
    end

    window:perform_action(wezterm.action.InputSelector({
      title = opts.icon .. " Select Ollama Model",
      description = "Choose a model to run",
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id)
        if id then
          inner_window:perform_action(wezterm.action.SpawnCommandInNewTab({
            args = { opts.ollama_path, "run", id },
            set_environment_variables = { OLLAMA_MODEL = id },
          }), inner_pane)
        end
      end),
    }), pane)
  end)
end

local function create_quick_chat_action_internal(opts)
  if not opts.default_model then
    return create_model_selector_action_internal(opts)
  end
  return wezterm.action.SpawnCommandInNewTab({
    args = { opts.ollama_path, "run", opts.default_model },
    set_environment_variables = { OLLAMA_MODEL = opts.default_model },
  })
end

local function mkdir_p(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local success = wezterm.run_child_process({ "mkdir", "-p", "--", path })
  return success
end

local function create_session_picker_action_internal(opts)
  return wezterm.action_callback(function(window, pane)
    if not opts.save_sessions then
      window:toast_notification("Ollama", "Session persistence not enabled", nil, 3000)
      return
    end

    local success, output = wezterm.run_child_process({
      "find", opts.sessions_dir, "-maxdepth", "1", "-name", "*.json", "-type", "f",
    })
    local sessions = {}
    if success and output then
      for line in output:gmatch("[^\n]+") do
        local filename = line:match("([^/]+)%.json$")
        if filename then
          table.insert(sessions, { path = line, name = filename })
        end
      end
      table.sort(sessions, function(a, b)
        return a.name > b.name
      end)
      while #sessions > 20 do
        table.remove(sessions)
      end
    end

    if #sessions == 0 then
      window:toast_notification("Ollama", "No saved sessions found", nil, 3000)
      return
    end

    local choices = {}
    for _, session in ipairs(sessions) do
      table.insert(choices, { id = session.path, label = session.name })
    end
    window:perform_action(wezterm.action.InputSelector({
      title = opts.icon .. " Resume Ollama Session",
      description = "Choose a session to resume",
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, _, label)
        local model = label and label:match("^([^_]+)")
        if model then
          inner_window:perform_action(wezterm.action.SpawnCommandInNewTab({
            args = { opts.ollama_path, "run", model },
            set_environment_variables = { OLLAMA_MODEL = model },
          }), inner_pane)
        end
      end),
    }), pane)
  end)
end

function M.create_model_selector_action(user_opts)
  return create_model_selector_action_internal(resolve_opts(user_opts or resolved_opts))
end

function M.create_quick_chat_action(user_opts)
  return create_quick_chat_action_internal(resolve_opts(user_opts or resolved_opts))
end

function M.create_session_picker_action(user_opts)
  return create_session_picker_action_internal(resolve_opts(user_opts or resolved_opts))
end

function M.apply_to_config(config, user_opts)
  if type(config) ~= "table" and type(config) ~= "userdata" then
    error("wezterm-ollama: config must be a config builder")
  end
  local opts = resolve_opts(user_opts)
  resolved_opts = opts

  if opts.save_sessions and not mkdir_p(opts.sessions_dir) then
    wezterm.log_error("wezterm-ollama: failed to create sessions directory: " .. opts.sessions_dir)
  end

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

function M.check_status(user_opts)
  return check_server_status(resolve_opts(user_opts or resolved_opts))
end

function M.fetch_models(user_opts)
  return fetch_models(resolve_opts(user_opts or resolved_opts))
end

M.smart_datetime = smart_datetime
M.defaults = copy_table(defaults)

return M
