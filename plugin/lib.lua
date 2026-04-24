-- wezterm_utils.lua: Shared utility functions for WezTerm plugins
-- Provides safe process execution, logging, error handling, and validation

local wezterm = require("wezterm")
local M = {}

-- Configuration
M.debug_mode = os.getenv("WEZTERM_DEBUG") == "1"

-- Unified logger
local function get_logger()
  return setmetatable({}, {
    __call = function(self, msg, level)
      level = level or "INFO"
      if M.debug_mode or level == "ERROR" then
        wezterm.log_error(string.format("[%s] %s", level, msg))
      end
    end
  })
end

M.log = get_logger()

-- Safe command execution with array form (no shell injection)
-- Returns: success (bool), output (string or nil), stderr (string or nil)
function M.safe_run(cmd, timeout_secs)
  if type(cmd) == "string" then
    error("safe_run() requires array form: {cmd, arg1, arg2, ...} not string")
  end
  
  timeout_secs = timeout_secs or 5
  
  local start_time = os.time()
  local success, output, stderr = wezterm.run_child_process(cmd)
  local elapsed = os.time() - start_time
  
  if M.debug_mode then
    M.log(string.format("safe_run(%s) => success=%s, elapsed=%ds", 
      table.concat(cmd, " "), success, elapsed), "DEBUG")
  end
  
  if elapsed > timeout_secs then
    M.log(string.format("Command timeout: %s exceeded %ds", 
      cmd[1], timeout_secs), "WARN")
  end
  
  return success, output, stderr
end

-- Escape string for AppleScript (prevents injection)
function M.escape_applescript(str)
  -- Escape backslashes and quotes
  str = str:gsub("\\", "\\\\")
  str = str:gsub('"', '\\"')
  return str
end

-- Platform detection
function M.is_macos()
  local ostype = os.getenv("OSTYPE") or ""
  return ostype:match("darwin") ~= nil
end

function M.is_linux()
  local ok = io.open("/etc/os-release")
  if ok then
    ok:close()
    return true
  end
  return false
end

function M.is_windows()
  return wezterm.target_triple:find("windows") ~= nil
end

-- Safe directory creation
function M.mkdir_p(path)
  if not path or path == "" then
    M.log("mkdir_p() called with empty path", "WARN")
    return false
  end
  
  local success, output, stderr
  if M.is_windows() then
    success, output, stderr = M.safe_run({"powershell", "-Command", 
      "if (-not (Test-Path '" .. path:gsub("'", "''") .. "')) { New-Item -ItemType Directory -Force -Path '" .. 
      path:gsub("'", "''") .. "' | Out-Null }"})
  else
    success, output, stderr = M.safe_run({"mkdir", "-p", path})
  end
  
  if not success then
    M.log(string.format("mkdir_p failed for %s: %s", path, stderr or "unknown error"), "ERROR")
    return false
  end
  return true
end

-- Get secure temp file
function M.get_temp_file(prefix, suffix)
  prefix = prefix or "wezterm"
  suffix = suffix or ""
  
  local tmp_file = os.tmpname()
  if suffix ~= "" then
    tmp_file = tmp_file .. suffix
  end
  
  return tmp_file
end

-- Safe file write with error handling
function M.safe_write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    M.log(string.format("Cannot open %s for writing: %s", path, err), "ERROR")
    return false
  end
  
  local ok, err = f:write(content)
  f:close()
  
  if not ok then
    M.log(string.format("Cannot write to %s: %s", path, err), "ERROR")
    return false
  end
  
  return true
end

-- Config validation with schema
function M.validate_config(config, schema)
  if not schema then
    return true
  end
  
  local errors = {}
  
  for key, type_spec in pairs(schema) do
    local value = config[key]
    local expected_type = type_spec
    
    -- Handle optional fields with nil
    if value == nil and (type_spec == "optional" or type_spec:match("^optional:")) then
      goto next_field
    end
    
    -- Extract type from "optional:type" format
    if type_spec:match("^optional:") then
      expected_type = type_spec:sub(10)
    end
    
    local actual_type = type(value)
    if actual_type ~= expected_type then
      table.insert(errors, string.format("Field '%s': expected %s, got %s", 
        key, expected_type, actual_type))
    end
    
    ::next_field::
  end
  
  if #errors > 0 then
    for _, err in ipairs(errors) do
      M.log(err, "WARN")
    end
    return false
  end
  
  return true
end

-- Validate environment variables
function M.validate_env()
  local home = os.getenv("HOME")
  if not home or home == "" then
    M.log("HOME environment variable not set", "ERROR")
    return false
  end
  
  -- Check if HOME is writable
  local test_file = home .. "/.wezterm_test_" .. os.time()
  local f = io.open(test_file, "w")
  if f then
    f:close()
    os.remove(test_file)
  else
    M.log(string.format("HOME directory (%s) is not writable", home), "WARN")
  end
  
  return true
end

-- Debounce helper for status bar updates
function M.debounce(func, delay_ms)
  delay_ms = delay_ms or 500
  local timer = nil
  
  return function(...)
    local args = {...}
    
    if timer then
      return
    end
    
    func(unpack(args))
    
    timer = true
    wezterm.sleep_ms(delay_ms)
    timer = nil
  end
end

-- Cache with TTL
function M.cache_with_ttl(getter, ttl_secs)
  ttl_secs = ttl_secs or 30
  local cached_value = nil
  local cached_time = 0
  
  return function()
    local now = os.time()
    if now - cached_time >= ttl_secs then
      cached_value = getter()
      cached_time = now
    end
    return cached_value
  end
end

-- Wrap external call with error handler
function M.error_handler(func, fallback)
  fallback = fallback or function() return nil end
  
  return function(...)
    local ok, result = pcall(func, ...)
    if not ok then
      M.log(string.format("Error in wrapped function: %s", result), "ERROR")
      return fallback()
    end
    return result
  end
end

-- JSON parse with error handling
function M.safe_json_parse(str)
  if not str or str == "" then
    return nil
  end
  
  local ok, result = pcall(wezterm.json_parse, str)
  if not ok then
    M.log(string.format("JSON parse error: %s", result), "WARN")
    return nil
  end
  
  return result
end

-- JSON encode with error handling
function M.safe_json_encode(obj)
  local ok, result = pcall(wezterm.json_encode, obj)
  if not ok then
    M.log(string.format("JSON encode error: %s", result), "ERROR")
    return nil
  end
  
  return result
end

return M
