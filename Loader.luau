-- ClaudeHub loader v1.3.0 | MM2 + JJS + DOORS/lobby + universal fallback.
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
    if game.GameId == 66654135 then
        module = "MM2.luau"
    elseif game.GameId == 3508322461 then
        module = "JJS.luau"
    elseif game.GameId == 2440500124 then
        module = game.PlaceId == 6516141723 and "DoorsLobby.luau" or "Doors.luau"
    else module = "ClaudeHub.luau" end
    local source = game:HttpGet(BASE .. module)
    assert(type(source) == "string" and #source > 0, "Empty download: " .. module)
    local chunk, compileError = loadstring(source, "@ClaudeHub/" .. module)
    assert(chunk, "Compilation failed: " .. tostring(compileError))
    print("[ClaudeHub] Loading " .. module)
    return chunk()
end, function(err) return tostring(err) end)
state.Busy = false
if not ok then
    -- Clean up a library exported by a partially initialized module.
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
