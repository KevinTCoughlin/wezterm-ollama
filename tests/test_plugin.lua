local responses = {}
local calls = {}
local errors = {}

local wezterm = {
  action = {},
}

function wezterm.action_callback(callback)
  return callback
end

function wezterm.action.InputSelector(options)
  return { kind = "InputSelector", options = options }
end

function wezterm.action.SpawnCommandInNewTab(options)
  return { kind = "SpawnCommandInNewTab", options = options }
end

function wezterm.run_child_process(command)
  table.insert(calls, command)
  local response = table.remove(responses, 1)
  if not response then
    error("unexpected process call: " .. table.concat(command, " "))
  end
  return table.unpack(response)
end

function wezterm.json_parse(value)
  if value == "tags" then
    return {
      models = {
        { name = "llama3.2:latest", size = 2147483648, details = { parameter_size = "3B" } },
        { model = "gemma:2b", size = 1073741824, details = {} },
      },
    }
  elseif value == "running" then
    return { models = { { name = "llama3.2:latest" } } }
  elseif value == "idle" then
    return { models = {} }
  elseif value == "wrong-shape" then
    return { message = "not an Ollama model response" }
  end
  error("invalid JSON")
end

function wezterm.log_error(message)
  table.insert(errors, message)
end

package.preload.wezterm = function()
  return wezterm
end

local function enqueue(success, output, stderr)
  table.insert(responses, { success, output, stderr })
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
  end
end

local plugin = dofile("plugin/init.lua")

assert_equal(plugin._VERSION, "1.0.0", "version")
assert_equal(plugin.defaults.update_interval, 15000, "default status interval")

local ok, message = pcall(plugin.fetch_models, { host = "file:///etc/passwd" })
assert_equal(ok, false, "invalid host rejected")
assert(message:match("http:// or https://"), "invalid host error should be actionable")

enqueue(true, "tags", "")
local models = plugin.fetch_models({
  host = "http://127.0.0.1:11434/",
  cache_ttl = 0,
})
assert_equal(#models, 2, "model count")
assert_equal(models[1].name, "llama3.2:latest", "model name")
assert_equal(models[1].params, "3B", "parameter size")
assert_equal(calls[#calls][#calls[#calls] - 1], "--", "curl option terminator")
assert_equal(calls[#calls][#calls[#calls]], "http://127.0.0.1:11434/api/tags", "normalized URL")

enqueue(false, "", "connection refused\n")
models = plugin.fetch_models({
  host = "http://127.0.0.1:11434",
  cache_ttl = 0,
})
assert_equal(#models, 0, "failed refresh must not return stale models")

enqueue(true, "running", "")
local status, model = plugin.check_status({
  host = "http://127.0.0.2:11434",
  update_interval = 0,
})
assert_equal(status, "running", "running status")
assert_equal(model, "llama3.2:latest", "loaded model")

enqueue(true, "idle", "")
status, model = plugin.check_status({
  host = "http://127.0.0.3:11434",
  update_interval = 0,
})
assert_equal(status, "running", "idle server status")
assert_equal(model, nil, "idle loaded model")

enqueue(false, "", "connection refused\n")
status = plugin.check_status({
  host = "http://127.0.0.4:11434",
  update_interval = 0,
})
assert_equal(status, "stopped", "failed request status")
assert(errors[#errors]:match("connection refused"), "curl failure should be logged")

enqueue(true, "wrong-shape", "")
models = plugin.fetch_models({
  host = "http://127.0.0.5:11434",
  cache_ttl = 0,
})
assert_equal(#models, 0, "wrong response shape")

local action = plugin.create_quick_chat_action({
  default_model = "gemma:2b",
  ollama_path = "/custom/ollama",
})
assert_equal(action.kind, "SpawnCommandInNewTab", "quick chat action")
assert_equal(action.options.args[1], "/custom/ollama", "custom executable")
assert_equal(action.options.args[3], "gemma:2b", "custom default model")

local config = {}
local options = plugin.apply_to_config(config, {
  keys = { select_model = false, quick_chat = false },
  sessions_dir = "~/.ollama/test-sessions",
})
assert_equal(#config.keys, 0, "disabled default keys")
assert_equal(options.host, "http://127.0.0.1:11434", "default host")
assert_equal(options.sessions_dir, os.getenv("HOME") .. "/.ollama/test-sessions", "home expansion")

print("all tests passed")
