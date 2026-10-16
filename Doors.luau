-- ClaudeHub / DOORS v0.1.0 -- initial client-assist module, not an anti-cheat bypass.
-- Lobby and all places in the DOORS universe are routed here by Loader.luau.
local VERSION, STARTED = "v0.1.0", os.clock()
assert(game.GameId == 2440500124, "Use Loader.luau: this module is only for DOORS")
local env = getgenv and getgenv() or _G
if env.__ClaudeHubDoors and not env.__ClaudeHubDoors.Unloaded then
    env.__ClaudeHubDoors:Notify("DOORS module is already open.", 3)
    return env.__ClaudeHubDoors
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "LocalPlayer is unavailable; run on the client")
local UI_REPO = "https://raw.githubusercontent.com/joustingmatch/ObsidianUltra/main/"
local function fetch(path)
    local chunk, err = loadstring(game:HttpGet(UI_REPO .. path), "@ObsidianUltra/" .. path)
    assert(chunk, tostring(err))
    return chunk()
end
local Library = fetch("Library.lua")
env.__ClaudeHubDoors = Library
local Options, Toggles = Library.Options, Library.Toggles
local alive, connections, cleanup = true, {}, {}
local function connect(event, fn)
    local c = event:Connect(fn)
    table.insert(connections, c)
    return c
end
local function onCleanup(fn) table.insert(cleanup, fn) end
-- Register cleanup before constructing features, so partial startup can be unloaded.
Library:OnUnload(function()
    alive = false
    for _, c in ipairs(connections) do c:Disconnect() end
    for i = #cleanup, 1, -1 do pcall(cleanup[i]) end
    if env.__ClaudeHubDoors == Library then env.__ClaudeHubDoors = nil end
end)
local Window = Library:CreateWindow({Title = "ClaudeHub | DOORS", Footer = VERSION,
    Center = true, Resizable = true, NotifyOnError = true, Size = UDim2.fromOffset(1040, 720)})
local Tabs = {
    Home = Window:AddTab("Home", "house"),
    Visuals = Window:AddTab("Visuals", "eye"),
    Assist = Window:AddTab("Assist", "bell"),
    Settings = Window:AddTab("UI Settings", "settings"),
}
local function copy(text)
    if setclipboard then
        local ok = pcall(setclipboard, tostring(text))
        if ok then Library:Notify("Copied", 3) return end
    end
    print("[ClaudeHub] " .. tostring(text))
    Library:Notify("Clipboard unavailable; printed in console", 4)
end
local function toggle(box, id, label, callback)
    local t = box:AddToggle(id, {Text = label, Default = false, Callback = callback})
    -- Ultra initializes picker state to false; attach before enabling sync.
    t:AddKeyPicker(id .. "Key", {Default = "None", Text = label, Mode = "Toggle",
        Modes = {"Toggle", "Hold"}, SyncToggleState = false})
    local picker = Options[id .. "Key"]
    picker.SyncToggleState, picker.Toggled = true, t.Value
    picker:Update()
    return t
end
local function enabled(id) return Toggles[id] and Toggles[id].Value end
local function roomFolder() return workspace:FindFirstChild("CurrentRooms") end
local function dataValue(name)
    local data = RS:FindFirstChild("GameData")
    local value = data and data:FindFirstChild(name)
    if value and value:IsA("ValueBase") then return value.Value end
    return nil
end
local function root()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function hum()
    return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

-- HOME: changelog, avatar, nested Game / Games / Info.
Tabs.Home:UpdateWarningBox({Visible = true, IsNormal = true, LockSize = true,
    Title = "Latest Changelog | DOORS " .. VERSION,
    Text = table.concat({"+ New DOORS module and universe-aware loader",
        "+ Home: profile, live room/floor/player information",
        "+ Exit, key/book/lever and hiding-spot markers",
        "+ Entity spawn alerts; optional entity markers",
        "+ Fullbright, local flashlight, FOV and draggable HUD",
        "! First release: test in-game; no bypass or invulnerability claims"}, "\n")})
local profile = Tabs.Home:AddLeftGroupbox("Profile", "user")
profile:AddImage("DoorsAvatar", {Image = ("rbxthumb://type=Avatar&id=%d&w=420&h=420"):format(player.UserId), Height = 190})
profile:AddLabel(player.DisplayName)
profile:AddLabel("@" .. player.Name .. " | " .. player.UserId)
profile:AddDivider()
profile:AddLabel("ClaudeHub | DOORS " .. VERSION)
local details = Tabs.Home:AddRightTabbox()
local gameTab = details:AddTab("Game", "gamepad-2")
local gamesTab = details:AddTab("Games", "list-checks")
local infoTab = details:AddTab("Info", "info")
gameTab:AddLabel("Game: DOORS")
local floorLabel = gameTab:AddLabel("Floor: --")
local roomLabel = gameTab:AddLabel("Latest room: --")
local playersLabel = gameTab:AddLabel("Players: --")
local contextLabel = gameTab:AddLabel("Context: waiting for game data")
gameTab:AddDivider()
gameTab:AddLabel("Place ID: " .. game.PlaceId)
gameTab:AddButton({Text = "Copy Server ID", Func = function() copy(game.JobId) end})
gamesTab:AddLabel("DOORS | initial module")
gamesTab:AddLabel("Universal | ClaudeHub v2.16.0")
gamesTab:AddLabel("The loader selects by universe, not by floor name.", true)
infoTab:AddLabel("Version: " .. VERSION)
infoTab:AddLabel("Library: ObsidianUltra")
infoTab:AddLabel("Fork: joustingmatch / ObsidianUltra", true)
local loadedLabel = infoTab:AddLabel("Loaded in: --")
infoTab:AddButton({Text = "Copy Debug Info", Func = function()
    copy(table.concat({"ClaudeHub DOORS " .. VERSION, "Place: " .. game.PlaceId,
        "Universe: " .. game.GameId, "Server: " .. game.JobId,
        "Latest room: " .. tostring(dataValue("LatestRoom") or "unknown"),
        "Floor: " .. tostring(dataValue("Floor") or "unknown")}, "\n"))
end})
local notes = Tabs.Home:AddRightGroupbox("Read First", "info")
notes:AddLabel("Re-run the loader after a lobby / floor teleport. No auto-execute is installed.", true)
notes:AddLabel("Markers depend on replicated objects and streaming. They cannot reveal unloaded rooms or guarantee safety.", true)
notes:AddLabel("Latest room is the server's progress value, not necessarily your current room.", true)
notes:AddLabel("RightControl opens the menu. Click the badge beside a toggle to rebind it.", true)

-- Reversible Lighting changes. Track the game's most recent attempted values.
local brightOriginal, writingLight = {}, false
local brightValues = {Brightness = 2, Ambient = Color3.fromRGB(200, 200, 200),
    OutdoorAmbient = Color3.fromRGB(200, 200, 200), GlobalShadows = false}
local function writeLight(property, value)
    writingLight = true
    Lighting[property] = value
    writingLight = false
end
local function setBright(value)
    if value then
        for k, v in pairs(brightValues) do
            if brightOriginal[k] == nil then brightOriginal[k] = Lighting[k] end
            writeLight(k, v)
        end
    else
        for k, v in pairs(brightOriginal) do writeLight(k, v) end
        table.clear(brightOriginal)
    end
end
for k in pairs(brightValues) do
    connect(Lighting:GetPropertyChangedSignal(k), function()
        if writingLight or not enabled("DoorsBright") or Lighting[k] == brightValues[k] then return end
        brightOriginal[k] = Lighting[k]
        -- Defer to avoid recursive property-signal re-entry.
        task.defer(function()
            if alive and enabled("DoorsBright") then writeLight(k, brightValues[k]) end
        end)
    end)
end
onCleanup(function() setBright(false) end)
local visuals = Tabs.Visuals:AddLeftGroupbox("Lighting", "sun")
toggle(visuals, "DoorsBright", "Fullbright", setBright)
visuals:AddLabel("Local lighting only; effects and scripted darkness can still affect the view.", true)

local light
local function removeLight() if light then light:Destroy() light = nil end end
local function updateLight()
    local part = root()
    if not enabled("DoorsFlashlight") or not part then removeLight() return end
    if light and light.Parent ~= part then removeLight() end
    if not light then
        light = Instance.new("PointLight")
        light.Name = "ClaudeHubLocalLight"
        light.Parent = part
    end
    light.Brightness, light.Range, light.Shadows = 2, Options.DoorsLightRange.Value, false
end
toggle(visuals, "DoorsFlashlight", "Local flashlight", updateLight)
visuals:AddSlider("DoorsLightRange", {Text = "Light range", Default = 25, Min = 5, Max = 60, Rounding = 0,
    Callback = updateLight})
onCleanup(removeLight)

local cameraBox = Tabs.Visuals:AddRightGroupbox("Camera", "camera")
local trackedCamera, originalFov, writingFov
local cameraConnection
local function restoreFov()
    if cameraConnection then cameraConnection:Disconnect() cameraConnection = nil end
    if trackedCamera and originalFov then
        pcall(function() trackedCamera.FieldOfView = originalFov end)
    end
    trackedCamera, originalFov = nil, nil
end
local function applyFov()
    if not enabled("DoorsFov") then restoreFov() return end
    local camera = workspace.CurrentCamera
    if camera ~= trackedCamera then
        restoreFov()
        if not camera then return end
        trackedCamera, originalFov = camera, camera.FieldOfView
        cameraConnection = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if writingFov or not alive or not enabled("DoorsFov")
                or camera.FieldOfView == Options.DoorsFovValue.Value then return end
            originalFov = camera.FieldOfView
            task.defer(function() if alive then applyFov() end end)
        end)
    end
    if camera then
        writingFov = true
        camera.FieldOfView = Options.DoorsFovValue.Value
        writingFov = false
    end
end
toggle(cameraBox, "DoorsFov", "Custom FOV", applyFov)
cameraBox:AddSlider("DoorsFovValue", {Text = "Field of view", Default = 80, Min = 50, Max = 110,
    Rounding = 0, Callback = applyFov})
cameraBox:AddLabel("Off by default. May conflict with scripted cutscene cameras.", true)
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), applyFov)
onCleanup(restoreFov)

-- Markers: event-driven candidate registry; only a bounded number are rendered.
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "ClaudeHubDoorsHUD", false, true
gui.Parent = player:WaitForChild("PlayerGui", 15)
assert(gui.Parent, "PlayerGui did not become available")
local highlights = Instance.new("Folder")
highlights.Name, highlights.Parent = "ClaudeHubDoorsHighlights", workspace
onCleanup(function() gui:Destroy() highlights:Destroy() end)
local candidates, markers = {}, {}
local entityNames = {RushMoving = "Rush", AmbushMoving = "Ambush", A60 = "A-60", A120 = "A-120",
    Eyes = "Eyes", BackdoorLookman = "Lookman", BackdoorRush = "Blitz"}
local itemNames = {KeyObtain = "Key", LiveHintBook = "Book", LeverForGate = "Lever",
    FuseObtain = "Fuse", KeycardObtain = "Keycard"}
local hideNames = {Wardrobe = "Wardrobe", Toolshed = "Hiding spot", Bed = "Bed",
    Rooms_Locker = "Locker", Rooms_Locker_Locker = "Locker", Rooms_Locker_Fridge = "Locker"}
local colors = {Exit = Color3.fromRGB(120, 255, 160), Item = Color3.fromRGB(255, 215, 100),
    Hide = Color3.fromRGB(100, 195, 255), Entity = Color3.fromRGB(255, 90, 100)}
local function classify(obj)
    if not obj:IsA("Model") then return end
    if entityNames[obj.Name] and obj.Parent == workspace then return "Entity", entityNames[obj.Name] end
    local rooms = roomFolder()
    if not rooms or not obj:IsDescendantOf(rooms) then return end
    if obj.Name == "Door" and obj.Parent.Parent == rooms then
        return "Exit", "Exit | room " .. obj.Parent.Name
    end
    if itemNames[obj.Name] then return "Item", itemNames[obj.Name] end
    if hideNames[obj.Name] then return "Hide", hideNames[obj.Name] end
end
local alerted = setmetatable({}, {__mode = "k"})
local function alertEntity(obj, label)
    if alerted[obj] or not enabled("DoorsAlerts") then return end
    alerted[obj] = true
    Library:Notify(label .. " detected (replicated model). Find cover; spawn detection is not a safety guarantee.", 6)
end
local function register(obj, allowAlert)
    local category, label = classify(obj)
    if not category then return end
    candidates[obj] = {Category = category, Label = label}
    if category == "Entity" and allowAlert then alertEntity(obj, label) end
end
local function drop(obj)
    local marker = markers[obj]
    if marker then marker.Billboard:Destroy() marker.Highlight:Destroy() markers[obj] = nil end
end
local function clearMarkers()
    for obj in pairs(markers) do drop(obj) end
end
onCleanup(function() clearMarkers() table.clear(candidates) end)
local markersBox = Tabs.Visuals:AddLeftGroupbox("Room markers", "scan-eye")
for _, entry in ipairs({{"Exit", "Exit doors"}, {"Item", "Keys / books / levers"},
    {"Hide", "Hiding spots"}, {"Entity", "Entity markers"}}) do
    toggle(markersBox, "DoorsMark" .. entry[1], entry[2], function(value)
        if not value then
            for obj, marker in pairs(markers) do
                if marker.Category == entry[1] then drop(obj) end
            end
        end
    end)
end
markersBox:AddSlider("DoorsMarkerDistance", {Text = "Marker range (studs)", Default = 250, Min = 30,
    Max = 750, Rounding = 0})
markersBox:AddLabel("Loaded objects only. Item/hiding names are an initial allowlist; some floors need additional adapters. Hiding spots may be occupied or unsafe.", true)
local alertsBox = Tabs.Assist:AddLeftGroupbox("Entity alerts", "bell")
toggle(alertsBox, "DoorsAlerts", "Entity spawn notifications", function(value)
    if value then
        for obj, entry in pairs(candidates) do
            if obj.Parent and entry.Category == "Entity" then alertEntity(obj, entry.Label) end
        end
    end
end)
alertsBox:AddLabel("Initial detection: Rush, Ambush, A-60, A-120, Eyes, Lookman and Blitz model names. Not an exhaustive threat detector; streamed/local-only entities may not be detected.", true)
connect(workspace.DescendantAdded, function(obj) register(obj, true) end)
-- Connect first, then scan once: descendants arriving during initialization are not lost.
for _, obj in ipairs(workspace:GetDescendants()) do register(obj, false) end
local function renderMarkers()
    local part = root()
    if not part then clearMarkers() return end
    local nearest = {}
    for obj, entry in pairs(candidates) do
        if not obj:IsDescendantOf(workspace) then candidates[obj] = nil drop(obj)
        elseif enabled("DoorsMark" .. entry.Category) then
            local adornee = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
            if adornee then
                local distance = (part.Position - adornee.Position).Magnitude
                if distance <= Options.DoorsMarkerDistance.Value then
                    table.insert(nearest, {Object = obj, Entry = entry, Part = adornee, Distance = distance})
                end
            end
        end
    end
    table.sort(nearest, function(a, b) return a.Distance < b.Distance end)
    local visible = {}
    for i = 1, math.min(#nearest, 64) do
        local row = nearest[i]
        local obj, entry = row.Object, row.Entry
        visible[obj] = true
        local marker = markers[obj]
        if not marker then
            local billboard = Instance.new("BillboardGui")
            billboard.Name, billboard.AlwaysOnTop = "ClaudeHubMarker", true
            billboard.Size, billboard.StudsOffset = UDim2.fromOffset(190, 30), Vector3.new(0, 2, 0)
            billboard.Parent = gui
            local text = Instance.new("TextLabel")
            text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
            text.Font, text.TextSize = Enum.Font.Code, 13
            text.TextColor3, text.TextStrokeTransparency = colors[entry.Category], 0.35
            text.Parent = billboard
            local highlight = Instance.new("Highlight")
            highlight.Adornee, highlight.DepthMode = obj, Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor, highlight.OutlineColor = colors[entry.Category], colors[entry.Category]
            highlight.FillTransparency, highlight.OutlineTransparency = 0.85, 0.2
            highlight.Parent = highlights
            marker = {Billboard = billboard, Highlight = highlight, Text = text, Category = entry.Category}
            markers[obj] = marker
        end
        marker.Highlight.Enabled = i <= 24
        marker.Billboard.Adornee = row.Part
        marker.Text.Text = ("%s | %d studs"):format(entry.Label, math.floor(row.Distance))
    end
    for obj in pairs(markers) do if not visible[obj] then drop(obj) end end
end

-- One draggable HUD, pointer movement clamped to the viewport.
local hud = Instance.new("TextLabel")
hud.Name, hud.Size, hud.Position = "SessionHUD", UDim2.fromOffset(330, 76), UDim2.fromOffset(24, 110)
hud.BackgroundColor3, hud.BackgroundTransparency = Color3.fromRGB(15, 13, 23), 0.12
hud.BorderSizePixel, hud.TextColor3 = 0, Color3.fromRGB(215, 195, 255)
hud.Font, hud.TextSize, hud.TextWrapped = Enum.Font.Code, 14, true
hud.Active, hud.Visible, hud.Parent = true, false, gui
Instance.new("UICorner", hud).CornerRadius = UDim.new(0, 7)
local drag, dragOrigin, dragPosition
connect(hud.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        drag, dragOrigin, dragPosition = input, input.Position, hud.AbsolutePosition
    end
end)
connect(UIS.InputChanged, function(input)
    if not drag then return end
    if drag.UserInputType == Enum.UserInputType.Touch and input ~= drag then return end
    if drag.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local delta = input.Position - dragOrigin
    local view, size = camera.ViewportSize, hud.AbsoluteSize
    hud.Position = UDim2.fromOffset(math.clamp(dragPosition.X + delta.X, 0, math.max(0, view.X - size.X)),
        math.clamp(dragPosition.Y + delta.Y, 0, math.max(0, view.Y - size.Y)))
end)
connect(UIS.InputEnded, function(input)
    if input == drag or input.UserInputType == Enum.UserInputType.MouseButton1 then drag = nil end
end)
connect(UIS.WindowFocusReleased, function() drag = nil end)
local hudBox = Tabs.Assist:AddRightGroupbox("Session HUD", "layout-dashboard")
toggle(hudBox, "DoorsHUD", "Show draggable HUD", function(value) hud.Visible = value end)
hudBox:AddButton({Text = "Reset HUD position", Func = function() drag = nil hud.Position = UDim2.fromOffset(24, 110) end})
hudBox:AddButton({Text = "Reset session timer", Func = function() STARTED = os.clock() end})
hudBox:AddLabel("Mouse / touch dragging. Timer is time since loading/reset, not the run's official time.", true)
local accumulator = 0
local function refresh()
    local latest, floor = dataValue("LatestRoom"), dataValue("Floor")
    local rooms = roomFolder()
    local context = rooms and "Run (replicated rooms)" or "Lobby / waiting for rooms"
    floorLabel:SetText("Floor: " .. tostring(floor or "unknown"))
    roomLabel:SetText("Latest room: " .. tostring(latest or "--"))
    playersLabel:SetText(("Players: %d / %d"):format(#Players:GetPlayers(), Players.MaxPlayers))
    contextLabel:SetText("Context: " .. context)
    local seconds = math.floor(os.clock() - STARTED)
    local h = hum()
    hud.Text = ("ClaudeHub DOORS | %02d:%02d\nLatest room: %s | Floor: %s\nHealth: %s | Players: %d")
        :format(math.floor(seconds / 60), seconds % 60, tostring(latest or "--"), tostring(floor or "?"),
            h and (math.floor(h.Health) .. "/" .. math.floor(h.MaxHealth)) or "--", #Players:GetPlayers())
    updateLight()
    renderMarkers()
end
connect(RunService.Heartbeat, function(dt)
    accumulator += dt
    if accumulator < 0.5 then return end
    accumulator = 0
    refresh()
end)
refresh()

local menu = Tabs.Settings:AddLeftGroupbox("Menu", "settings")
menu:AddButton({Text = "Unload DOORS module", Func = function() Library:Unload() end})
menu:AddLabel("Menu key"):AddKeyPicker("DoorsMenuKey", {Default = "RightControl", NoUI = true, Text = "Menu key"})
Library.ToggleKeybind = Options.DoorsMenuKey
-- Optional addons: UI remains usable if their requests fail.
local themeOk, ThemeManager = pcall(fetch, "addons/ThemeManager.lua")
if themeOk then
    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("ClaudeHub/DOORS")
    ThemeManager:ApplyToTab(Tabs.Settings)
else Library:Notify("Theme addon unavailable; default theme is active.", 5) end
local saveOk, SaveManager = pcall(fetch, "addons/SaveManager.lua")
if saveOk then
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({"DoorsMenuKey"})
    SaveManager:SetFolder("ClaudeHub/DOORS/configs")
    SaveManager:BuildConfigSection(Tabs.Settings)
    -- No auto-load in v0.1: a saved config cannot silently enable gameplay aids.
end
loadedLabel:SetText(("Loaded in: %.2fs"):format(os.clock() - STARTED))
Library:Notify("DOORS " .. VERSION .. " ready. RightControl opens the menu. All feature toggles start OFF.", 6)
return Library
