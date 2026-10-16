-- ClaudeHub loader v1.0.0 | DOORS universe + universal fallback.
-- Run again after teleporting. This loader never queues itself automatically.
local env = getgenv and getgenv() or _G
local KEY = "__ClaudeHubLoader_v1"
local state = env[KEY]
if state and state.Busy then
    warn("[ClaudeHub] A load is already in progress.")
    return
end
if state and state.Library and not state.Library.Unloaded then
    state.Library:Notify("ClaudeHub is already open. RightControl toggles the menu. Unload it before switching modules.", 5)
    return state.Library
end
state = {Busy = true}
env[KEY] = state
local previousLibrary = env.Library
local BASE = "https://raw.githubusercontent.com/dima345ccnnmm/ClaudeHub/main/"
local module = "unknown"
local ok, result = xpcall(function()
    assert(type(loadstring) == "function", "This environment does not support loadstring")
    if not game:IsLoaded() then game.Loaded:Wait() end
    module = game.GameId == 2440500124 and "Doors.luau" or "ClaudeHub.luau"
    local source = game:HttpGet(BASE .. module)
    assert(type(source) == "string" and #source > 0, "Empty download: " .. module)
    local chunk, compileError = loadstring(source, "@ClaudeHub/" .. module)
    assert(chunk, "Compilation failed: " .. tostring(compileError))
    print("[ClaudeHub] Loading " .. module)
    return chunk()
end, function(err) return tostring(err) end)
state.Busy = false
if not ok then
    -- Both modules use ObsidianUltra's exported Library. Clean up partial UI.
    if env.Library and env.Library ~= previousLibrary then
        pcall(function() env.Library:Unload() end)
    end
    env[KEY] = nil -- a failed download or initialization may be retried
    error("[ClaudeHub] Could not load " .. module .. ": " .. tostring(result), 0)
end
state.Library = type(result) == "table" and result or env.Library
state.Module = module
if state.Library and state.Library.OnUnload then
    state.Library:OnUnload(function()
        if env[KEY] == state then env[KEY] = nil end
    end)
end
return state.Library
