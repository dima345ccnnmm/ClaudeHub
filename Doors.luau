--[[
DOORS feature portions adapted from Abysall by FireBacon (bocaj111004).
Source: https://github.com/bocaj111004/Abysall
Revision: 66d4192d00d9b824a304b654bc2d2eb89c3b372b
Port: entity/object aliases, ESP and selected interaction, character,
lighting and notification patterns, adapted to ClaudeHub's renderer/lifecycle. Original analytics,
anti-cheat hooks and destructive entity handlers are NOT included.
Additional UI/control patterns adapted from the user-supplied Main.luau.
The old Exploits tab and its hazard/module/audio handlers have been removed.

MIT License

Copyright (c) 2026 FireBacon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
-- ClaudeHub / DOORS v0.4.4 -- initial client-assist module, not an anti-cheat bypass.
-- Lobby and all places in the DOORS universe are routed here by Loader.luau.
local VERSION, STARTED = "v0.4.4", os.clock()
assert(game.GameId == 2440500124, "Use Loader.luau: this module is only for DOORS")
-- Direct execution has the same lobby routing as the universal loader.
if game.PlaceId == 6516141723 then
    local source = game:HttpGet("https://raw.githubusercontent.com/dima345ccnnmm/ClaudeHub/main/DoorsLobby.luau")
    local chunk, err = loadstring(source, "@ClaudeHub/DoorsLobby.luau")
    assert(chunk, "Lobby compilation failed: " .. tostring(err))
    return chunk()
end
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
local alive, ready, connections, cleanup = true, false, {}, {}
local function connect(event, fn)
    local c = event:Connect(function(...)
        if alive and ready then return fn(...) end
    end)
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
    Main = Window:AddTab("General", "gamepad-2"),
    Visuals = Window:AddTab("Visuals", "eye"),
    Assist = Window:AddTab("Session", "layout-dashboard"),
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
        Modes = {"Toggle", "Hold"}, NoUI = true, SyncToggleState = false})
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
    Text = table.concat({"= v0.4.4: simplified controls",
        "- Removed Exploits, Fast Interact, Instant Prompts, Prompt Clip and reach multiplier",
        "+ Legit Speed Boost: fixed +4",
        "= Auto Closet: Rush-like threats only",
        "= Auto Interact: full Abysall source loop and filters",
        "= ESP room visibility, entity identity and TweenService notifications retained",
        "+ Source author: FireBacon (bocaj111004), MIT"}, "\n")})
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
infoTab:AddLabel("Version: " .. VERSION)
infoTab:AddLabel("Library: ObsidianUltra")
infoTab:AddLabel("Fork: joustingmatch / ObsidianUltra", true)
infoTab:AddDivider()
infoTab:AddLabel("DOORS features adapted from Abysall", true)
infoTab:AddLabel("Original author: FireBacon (bocaj111004)", true)
infoTab:AddLabel("License: MIT | original copyright retained", true)
infoTab:AddButton({Text = "Copy ESP Author Link", Func = function()
    copy("https://github.com/bocaj111004/Abysall")
end})
local loadedLabel = infoTab:AddLabel("Loaded in: --")
infoTab:AddButton({Text = "Copy Debug Info", Func = function()
    copy(table.concat({"ClaudeHub DOORS " .. VERSION, "Place: " .. game.PlaceId,
        "Universe: " .. game.GameId, "Server: " .. game.JobId,
        "Latest room: " .. tostring(dataValue("LatestRoom") or "unknown"),
        "Floor: " .. tostring(dataValue("Floor") or "unknown")}, "\n"))
end})

-- Tabboxes follow the supplied Abysall screenshots, while Home/Session stay ClaudeHub-owned.
local panels, extension = {}, {}
local cameraTabs = Tabs.Visuals:AddLeftTabbox("Camera / Effects")
panels.Camera, panels.Effects = cameraTabs:AddTab("Camera"), cameraTabs:AddTab("Effects")
local notifyTabs = Tabs.Visuals:AddRightTabbox("Entities / Settings")
panels.Entities, panels.Notify = notifyTabs:AddTab("Entities"), notifyTabs:AddTab("Settings")
local espTabs = Tabs.Visuals:AddRightTabbox("ESP / Settings")
panels.ESP, panels.ESPSettings = espTabs:AddTab("ESP"), espTabs:AddTab("Settings")

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
    if value and extension.BeforeBright then extension.BeforeBright() end
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
local visuals = panels.Camera
toggle(visuals, "DoorsBright", "Fullbright", setBright)

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

local cameraBox = panels.Camera
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
cameraBox:AddSlider("DoorsFovValue", {Text = "Field of view", Default = 70, Min = 1, Max = 120,
    Rounding = 0, Callback = applyFov})
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
local entityNames = {
    ["RushMoving"] = "Rush",
    ["AmbushMoving"] = "Ambush",
    ["Eyes"] = "Eyes",
    SeekMovingNewClone = "Seek", SeekMoving = "Seek", SeekRig = "Seek", Seek = "Seek",
    Screech = "Screech", GlitchScreech = "Screech",
    ["Lookman"] = "Lookman",
    ["BackdoorRush"] = "Blitz",
    ["BackdoorLookman"] = "Lookman",
    ["Groundskeeper"] = "Groundskeeper",
    ["A60"] = "A-60",
    ["A120"] = "A-120",
    ["GloombatSwarm"] = "Gloombat Swarm",
    ["GlitchRush"] = "RNIUSHCG==",
    ["GlitchAmbush"] = "AR0xMBUSH",
    ["MonumentEntity"] = "Monument",
    ["JeffTheKiller"] = "Jeff the Killer",
    ["CustomEntity"] = "Custom Entity",
    ["FrozenAmbush"] = "Frozen Ambush",
    ["SallyMoving"] = "Sally",
}
-- Copied aliases / labels from Abysall; local adaptations are documented above.
local entityESPLabels = {
	JeffTheKiller = "Jeff the Killer", GiggleCeiling = "Giggle",
	Snare = "Snare", GrumbleRig = "Grumble",
	Drakobloxxer = "Drakobloxxer", Hole = "Mandrake Hole", Groundskeeper = "Groundskeeper",
	LiveEntityBramble = "Bramble", Figure = "Figure", FigureRig = "Figure", FigureRagdoll = "Figure",
	FakeDoor = "Dupe", DoorFake = "Dupe"
}
entityESPLabels.GloomPile = "Gloombat Eggs"
local rusherAliases = {Rush = true, Ambush = true, Eyes = true, Blitz = true, Lookman = true,
    ["A-60"] = true, ["A-120"] = true, Sally = true, ["Jeff the Killer"] = true,
    Monument = true, AR0xMBUSH = true, ["RNIUSHCG=="] = true, ["Custom Entity"] = true,
    ["Frozen Ambush"] = true}
local entityChoices, seenChoices = {}, {}
for _, map in ipairs({entityNames, entityESPLabels}) do
    for _, label in pairs(map) do
        if not seenChoices[label] then seenChoices[label] = true table.insert(entityChoices, label) end
    end
end
table.sort(entityChoices)
-- Conservative Dupe detection. Hidden alone exists on decorative models too.
-- TouchTransmitter is engine evidence of a touch trigger; do not require CanTouch
-- to remain true, because our own local bypass may temporarily set it false.
local function isDupeDoor(obj)
    if not obj:IsA("Model") or (obj.Name ~= "FakeDoor" and obj.Name ~= "DoorFake") then return false end
    local rooms = roomFolder()
    if not rooms or not obj:IsDescendantOf(rooms) then return false end
    local hidden = obj:FindFirstChild("Hidden")
    if not hidden or not hidden:IsA("BasePart") then return false end
    local mode = Options.DoorsDupeDetection and Options.DoorsDupeDetection.Value or "Strict: touch trigger"
    if mode == "Compatible: Hidden hitbox" then return true end
    return hidden:FindFirstChildOfClass("TouchTransmitter") ~= nil
end
-- Resolve whole live rigs, not arbitrary descendants sharing an entity name.
local function entityLabel(obj)
    if not obj:IsA("Model") and not obj:IsA("BasePart") then return end
    if player.Character and obj:IsDescendantOf(player.Character) then return end
    local label = entityNames[obj.Name] or entityESPLabels[obj.Name]
    if not label then return end
    local ancestor = obj.Parent
    while ancestor and ancestor ~= workspace do
        -- A named child (Eyes / FigureRig) inside another entity is not a second entity.
        if ancestor:IsA("Tool") or ancestor:IsA("Accessory") then return end
        if (ancestor:IsA("Model") or ancestor:IsA("BasePart"))
            and (entityNames[ancestor.Name] or entityESPLabels[ancestor.Name]) then return end
        ancestor = ancestor.Parent
    end
    if obj.Name == "Hole" and (not obj.Parent or obj.Parent.Name ~= "MandrakeLive") then return end
    if label == "Dupe" and not isDupeDoor(obj) then return end
    if label == "Eyes" then
        -- Actual Eyes is a world-level Model. Camera decorations and Screech's eyes
        -- are not Eyes. Unknown nested variants are deliberately not guessed.
        if not obj:IsA("Model") or obj.Parent ~= workspace then return end
    end
    if label == "Seek" or label == "Screech" or label == "Figure" then
        if not obj:IsA("Model") then return end
        local rooms = roomFolder()
        local camera = workspace.CurrentCamera
        if label == "Screech" then
            if obj.Parent ~= workspace and obj.Parent ~= camera then return end
        elseif label == "Seek" then
            if obj.Parent ~= workspace and not (rooms and obj:IsDescendantOf(rooms)) then return end
        elseif not (rooms and obj:IsDescendantOf(rooms)) then return end
    end
    return label
end

-- Room ownership is resolved independently of the candidate registry. Hidden
-- candidates stay registered, so returning to a streamed room restores its ESP.
local function objectRoom(obj)
    local rooms = roomFolder()
    local node, attributed = obj, nil
    while node and node ~= workspace do
        if rooms and node.Parent == rooms then return tonumber(node.Name) end
        attributed = attributed or tonumber(node:GetAttribute("ParentRoom"))
        node = node.Parent
    end
    return attributed
end
local function inCurrentRoom(obj)
    if Options.DoorsESPRoomScope and Options.DoorsESPRoomScope.Value == "All loaded rooms" then return true end
    local current = tonumber(player:GetAttribute("CurrentRoom"))
    local owner = objectRoom(obj)
    -- Global moving entities, players and dropped items without an owner remain visible.
    -- Never substitute LatestRoom (another player may be ahead).
    return owner == nil or current == nil or owner == current
end

local itemNames = {
	["KeyObtain"]              = "Door Key",
	["ElectricalKeyObtain"]    = "Electrical Key",
	["MinesGenerator"]         = "Generator",
	["FuseObtain"]             = "Generator Fuse",
	["LiveHintBook"]           = "Hint Book",
	["LiveBreakerPolePickup"]  = "Fuse Breaker",
	["LibraryHintPaper"]       = "Hint Paper",
	["PickupItem"]             = "Hint Paper",
	["CringlePresent"]         = "Present",
	["LeverForGate"]           = "Gate Lever",
	["MinesGateButton"]        = "Gate Button",
	["GardenGateButton"]       = "Gate Button",
}
itemNames.KeycardObtain = "Keycard"
itemNames.TimerLever = "Time lever"
itemNames.MinesAnchor = "Anchor"
itemNames.WaterPump = "Water pump"
itemNames.VineGuillotine = "Vine lever"
local lootNames = {
	["Lighter"]           = "Lighter",
	["Flashlight"]        = "Flashlight",
	["Lockpick"]          = "Lockpicks",
	["Vitamins"]          = "Vitamins",
	["Bandage"]           = "Bandage",
	["StarVial"]          = "Starlight Vial",
	["StarBottle"]        = "Starlight Bottle",
	["StarJug"]           = "Starlight Barrel",
	["Shakelight"]        = "Gummy Flashlight",
	["Straplight"]        = "Straplight",
	["Bulklight"]         = "Spotlight",
	["Battery"]           = "Battery",
	["Candle"]            = "Candle",
	["Crucifix"]          = "Crucifix",
	["CrucifixWall"]      = "Crucifix",
	["Glowsticks"]        = "Glowstick",
	["SkeletonKey"]       = "Skeleton Key",
	["Candy"]             = "Candy",
	["ShieldMini"]        = "Mini Shield Potion",
	["ShieldBig"]         = "Big Shield Potion",
	["BandagePack"]       = "Bandage Pack",
	["BatteryPack"]       = "Battery Pack",
	["RiftCandle"]        = "Moonlight Candle",
	["LaserPointer"]      = "Laser Pointer",
	["HolyGrenade"]       = "Holy Hand Grenade",
	["Shears"]            = "Shears",
	["Smoothie"]          = "Smoothie",
	["Cheese"]            = "Cheese",
	["Bread"]             = "Bread",
	["AlarmClock"]        = "Alarm Clock",
	["RiftSmoothie"]      = "Moonlight Smoothie",
	["GweenSoda"]         = "Gween Soda",
	["GlitchCube"]        = "Glitch Fragment",
	["Scanner"]           = "Tablet",
	["Bomb"]              = "Bomb",
	["Knockbomb"]         = "Knockbomb",
	["Nanner"]            = "Nanner",
	["BigBomb"]           = "Big Bomb",
	["SnakeBox"]          = "Hiding Box",
	["GoldGun"]           = "Golden Gun",
	["StopSign"]          = "Stop Sign",
	["TipJar"]            = "Tip Jar",
	["Lantern"]           = "Lantern",
	["IronKey"]           = "Iron Key",
	["LotusPetal"]        = "Lotus Petal",
	["Compass"]           = "Compass",
	["LotusPetalPickup"]  = "Lotus Petal",
	["LanternLitItem"]    = "Lantern",
	["KeyIron"]           = "Iron Key",
	["IronKeyForCrypt"]   = "Iron Key",
	["LotusHolder"]       = "Lotus Petal",
	["Multitool"]         = "Multitool",
	["RiftJar"]           = "Rift Jar",
	["AloeVera"]          = "Aloe Vera",
	["Donut"]             = "Donut",
	["Lotus"]             = "Lotus",
	["BoxingGloves"]      = "Boxing Gloves"
}
local hideNames = {
	Wardrobe = "Closet", ["Backdoor_Wardrobe"] = "Closet", Toolshed = "Closet",
	RetroWardrobe = "Closet", ["Wardrobe-FOOLS26"] = "Closet",
	Locker_Large = "Locker", Rooms_Locker = "Locker", Rooms_Locker_Fridge = "Locker",
	Bed = "Bed", Double_Bed = "Double Bed", CircularVent = "Vent", Dumpster = "Dumpster"
}
local chestNames = {
	ChestBox = true, ChestBoxLocked = true, Toolbox = true, Toolbox_Locked = true,
	Chest_Vine = "Vine Chest", Toolshed_Small = "Toolshed", Locker_Small_Locked = "Locked Item Locker", MouseHole = "Mouse"
}
local colors = {Exit = Color3.fromRGB(120, 255, 160), Item = Color3.fromRGB(255, 215, 100),
    Hide = Color3.fromRGB(100, 195, 255), Entity = Color3.fromRGB(255, 90, 100),
    Loot = Color3.fromRGB(200, 140, 255), Chest = Color3.fromRGB(255, 180, 90),
    Currency = Color3.fromRGB(255, 240, 90), Ladder = Color3.fromRGB(190, 220, 255),
    Player = Color3.fromRGB(255, 255, 255)}
local function classify(obj)
    local label = entityLabel(obj)
    if label then return "Entity", label end
    if not obj:IsA("Model") and not obj:IsA("BasePart") then return end
    if player.Character and (obj == player.Character or obj:IsDescendantOf(player.Character)) then return end
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and obj == other.Character and other:GetAttribute("Alive") ~= false then
            return "Player", other.DisplayName .. " (@" .. other.Name .. ")"
        end
    end
    local rooms = roomFolder()
    local drops = workspace:FindFirstChild("Drops")
    local inRooms = rooms and obj:IsDescendantOf(rooms)
    local inDrops = drops and obj:IsDescendantOf(drops)
    if not inRooms and not inDrops then return end
    if obj.Name == "Door" and obj:IsA("Model") and obj.Parent.Parent == rooms then
        return "Exit", "Exit | room " .. obj.Parent.Name
    end
    if itemNames[obj.Name] then return "Item", itemNames[obj.Name] end
    if hideNames[obj.Name] then return "Hide", hideNames[obj.Name] end
    if lootNames[obj.Name] and (obj:FindFirstChild("ModulePrompt", true) or inDrops) then
        return "Loot", lootNames[obj.Name]
    end
    if obj.Name == "Green_Herb" then return "Loot", "Green Herb" end
    if chestNames[obj.Name] then
        local name = chestNames[obj.Name]
        return "Chest", name == true and (obj:GetAttribute("Locked") and "Locked chest" or "Chest") or name
    end
    if obj.Name == "GoldPile" then return "Currency", "Gold [" .. tostring(obj:GetAttribute("GoldValue") or "?") .. "]" end
    if obj.Name == "StardustPickup" then return "Currency", "Stardust" end
    if obj.Name == "Ladder" and obj.Parent.Name ~= "Ladder" then return "Ladder", "Ladder" end
end
local extraRegister = function() end
local alerted = setmetatable({}, {__mode = "k"})
local function alertEntity(obj, label)
    if alerted[obj] or not enabled("DoorsAlerts") then return end
    if extension.EntityAlert then
        if extension.EntityAlert(obj, label) then alerted[obj] = true end
        return
    end
    alerted[obj] = true
    Library:Notify(label .. " detected (replicated object). Check your surroundings; detection is not a safety guarantee.", 6)
end
local function register(obj, allowAlert)
    local category, label = classify(obj)
    if not category then return end
    candidates[obj] = {Category = category, Label = label}
    if category == "Entity" and entityNames[obj.Name] and allowAlert then alertEntity(obj, label) end
end
-- Abysall's rusher highlight preparation, made reversible. No collision,
-- network-ownership, health or entity-position changes are carried over.
local function releasePatch(marker)
    local patch = marker.Patch
    if not patch then return end
    marker.Patch = nil
    if patch.Humanoid then patch.Humanoid:Destroy() end
    if patch.Part.Parent then
        if patch.Part.Transparency == 0.999 then patch.Part.Transparency = patch.Transparency end
        if patch.Part.Material == Enum.Material.Plastic then patch.Part.Material = patch.Material end
    end
end
local function prepareHighlight(marker, obj, part, label, active)
    if marker.Patch and (marker.Patch.Part ~= part or not active) then releasePatch(marker) end
    if not active or marker.Patch or not rusherAliases[label] then return end
    local patch = {Part = part, Transparency = part.Transparency, Material = part.Material}
    marker.Patch = patch
    if obj:IsA("Model") and not obj:FindFirstChildOfClass("Humanoid") then
        patch.Humanoid = Instance.new("Humanoid")
        patch.Humanoid.Name = "ClaudeHubHighlightHumanoid"
        patch.Humanoid.Parent = obj
    end
    -- Preserve visible geometry; upstream unconditionally sets this to 0.999.
    if part.Transparency == 1 then part.Transparency = 0.999 end
    part.Material = Enum.Material.Plastic
end
local function drop(obj)
    local marker = markers[obj]
    if marker then
        if marker.Tracer then marker.Tracer:Destroy() end
        if marker.Arrow then marker.Arrow:Destroy() end
        releasePatch(marker) marker.Billboard:Destroy()
        for _, h in ipairs(marker.Highlights) do h:Destroy() end
        markers[obj] = nil end
end
local function clearMarkers()
    for obj in pairs(markers) do drop(obj) end
end
onCleanup(function() clearMarkers() table.clear(candidates) end)
local markersBox = panels.ESP
for _, entry in ipairs({{"Exit", "Exit doors"}, {"Item", "Objectives / keys / books"},
    {"Hide", "Hiding spots"}, {"Loot", "Loot / consumables"}, {"Chest", "Chests"},
    {"Currency", "Gold / stardust"}, {"Ladder", "Ladders"}, {"Player", "Players"}}) do
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
local entityBox = panels.ESP
toggle(entityBox, "DoorsMarkEntity", "Entity ESP", function(value)
    if not value then
        for obj, marker in pairs(markers) do if marker.Category == "Entity" then drop(obj) end end
    end
end)
entityBox:AddDropdown("DoorsDupeDetection", {Text = "Dupe detection", Values = {"Strict: touch trigger", "Compatible: Hidden hitbox"}, Default = 1, Callback = function()
    for _, candidate in ipairs(workspace:GetDescendants()) do register(candidate, false) end
end})
entityBox:AddDropdown("DoorsEntityList", {Text = "Entities to show (multiple)", Values = entityChoices,
    Default = entityChoices, Multi = true, AllowNull = true, Callback = function()
        -- Rebuild at the next refresh; release transparent-rusher patches now.
        for obj, marker in pairs(markers) do if marker.Category == "Entity" then drop(obj) end end
    end})
entityBox:AddDropdown("DoorsSingleEntity", {Text = "Quick select one entity type", Values = entityChoices,
    AllowNull = true, Callback = function(value)
        if type(value) == "string" and value ~= "" then Options.DoorsEntityList:SetValue({[value] = true}) end
    end})
entityBox:AddButton({Text = "Select all entities", Func = function()
    local selection = {} for _, label in ipairs(entityChoices) do selection[label] = true end
    Options.DoorsEntityList:SetValue(selection)
end})
entityBox:AddButton({Text = "Clear entity selection", Func = function() Options.DoorsEntityList:SetValue({}) end})
entityBox:AddSlider("DoorsEntityDistance", {Text = "Entity range (studs)", Default = 2000, Min = 100,
    Max = 10000, Rounding = 0})
entityBox:AddButton({Text = "Rescan loaded entities", Func = function()
    for _, obj in ipairs(workspace:GetDescendants()) do register(obj, false) end
    Library:Notify("Rescanned loaded objects. Enable Entity markers and check the entity filter/range.", 5)
end})
local alertsBox = panels.Entities
toggle(alertsBox, "DoorsAlerts", "Entity spawn notifications", function(value)
    if value then
        for obj, entry in pairs(candidates) do
            if obj.Parent and entry.Category == "Entity" and entityNames[obj.Name] then alertEntity(obj, entry.Label) end
        end
    end
end)
connect(workspace.DescendantAdded, function(obj)
    register(obj, true)
    extraRegister(obj, true)
    -- Models and their parts may replicate separately. Retry enclosing rigs
    -- when a part, Monument.Top, Dupe.Hidden or Mandrake.Hole arrives later.
    local ancestor = obj.Parent
    while ancestor and ancestor ~= workspace do
        if ancestor:IsA("Model") then register(ancestor, true) extraRegister(ancestor, true) end
        ancestor = ancestor.Parent
    end
end)
-- Connect first, then scan once: descendants arriving during initialization are not lost.
for _, obj in ipairs(workspace:GetDescendants()) do register(obj, false) end
-- Only explicitly named leaf parts: never fall back to the wall-containing
-- outer Door model or a broad bounding-box proxy. Two leaves get two outlines.
local function doorLeaves(obj)
    local leaves = {}
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("BasePart") and child.Name == "Door" then table.insert(leaves, child)
        elseif (child:IsA("Model") or child:IsA("Folder")) and child.Name == "Door" then
            for _, leaf in ipairs(child:GetDescendants()) do
                if leaf:IsA("BasePart") and leaf.Name == "Door" then table.insert(leaves, leaf) end
            end
        end
    end
    return leaves
end
local function markerTarget(obj, category)
    if category == "Exit" then
        local leaves = doorLeaves(obj)
        return leaves[1], leaves[1], leaves
    end
    -- Special target used by Abysall for Monument; fall back until Top exists.
    local target = obj.Name == "MonumentEntity" and obj:FindFirstChild("Top") or obj
    if not target then target = obj end
    if target:IsA("BasePart") then return target, target end
    if target:IsA("Model") then
        local part = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
            or target:FindFirstChildWhichIsA("BasePart", true)
        return part, target
    end
    return nil, obj
end
local function renderMarkers()
    local part = root()
    local camera = workspace.CurrentCamera
    local origin = part and part.Position or (camera and camera.CFrame.Position)
    if not origin then clearMarkers() return end
    local nearest = {}
    for obj, entry in pairs(candidates) do
        local category, label
        if obj:IsDescendantOf(workspace) then category, label = classify(obj) end
        if not category then candidates[obj] = nil drop(obj)
        else
            entry.Category, entry.Label = category, label
            local selected = category ~= "Entity" or (Options.DoorsEntityList.Value[label] == true)
            if enabled("DoorsMark" .. category) and selected and inCurrentRoom(obj) then
                local adornee, target, targets = markerTarget(obj, category)
                if adornee then
                    local distance = (origin - adornee.Position).Magnitude
                    local range = category == "Entity" and Options.DoorsEntityDistance.Value
                        or Options.DoorsMarkerDistance.Value
                    if distance <= range then
                        table.insert(nearest, {Object = obj, Entry = entry, Part = adornee,
                            Target = target, Targets = targets or {target}, Distance = distance})
                    end
                end
            end
        end
    end
    -- Room furniture must not crowd entities out of the bounded renderer.
    local function priority(row)
        if row.Entry.Category ~= "Entity" then return 2 end
        return entityNames[row.Object.Name] and 0 or 1
    end
    table.sort(nearest, function(a, b)
        local ap, bp = priority(a), priority(b)
        if ap ~= bp then return ap < bp end
        return a.Distance < b.Distance
    end)
    local visible, highlightCount = {}, 0
    for i = 1, math.min(#nearest, Options.DoorsESPLimit and Options.DoorsESPLimit.Value or 64) do
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
            marker = {Billboard = billboard, Highlights = {}, Text = text, Category = entry.Category}
            markers[obj] = marker
        end
        marker.Category = entry.Category
        marker.Text.TextColor3 = colors[entry.Category]
        for index = #marker.Highlights, #row.Targets + 1, -1 do
            marker.Highlights[index]:Destroy() table.remove(marker.Highlights, index)
        end
        for index, target in ipairs(row.Targets) do
            local h = marker.Highlights[index]
            if not h then
                h = Instance.new("Highlight")
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = highlights
                marker.Highlights[index] = h
            end
            h.Adornee = target
            h.FillColor, h.OutlineColor = colors[entry.Category], colors[entry.Category]
            h.FillTransparency = Options.DoorsESPFill and Options.DoorsESPFill.Value or 0.85
            h.OutlineTransparency = Options.DoorsESPOutline and Options.DoorsESPOutline.Value or 0.2
            h.Enabled = highlightCount < 24
            if h.Enabled then highlightCount += 1 end
        end
        marker.Highlight = marker.Highlights[1]
        if entry.Category == "Entity" then
            prepareHighlight(marker, obj, row.Part, entry.Label, marker.Highlight and marker.Highlight.Enabled)
        end
        marker.Billboard.Adornee = row.Part
        marker.Text.Text = ("%s | %d studs"):format(entry.Label, math.floor(row.Distance))
        if extension.StyleMarker then extension.StyleMarker(marker, row) end
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
    if accumulator < 0.2 then return end
    accumulator = 0
    refresh()
end)
refresh()

-- v0.3: selected Abysall feature patterns; original author FireBacon
-- (bocaj111004). The MIT notice above applies to the adapted portions.
-- Five extra ESP categories are registered above: loot, chests, currency,
-- ladders and players. The ten remaining additions are implemented here.

-- Reversible property/attribute ownership, preserving the game's latest value.
local function override(pool, obj, name, value, attribute)
    local current
    if attribute then current = obj:GetAttribute(name) else current = obj[name] end
    local fields = pool[obj]
    if not fields then fields = {} pool[obj] = fields end
    local entry = fields[name]
    if not entry then
        entry = {Before = current, Attribute = attribute}
        fields[name] = entry
    elseif current ~= entry.Applied then entry.Before = current end
    entry.Applied = value
    if current ~= value then
        if attribute then obj:SetAttribute(name, value) else obj[name] = value end
    end
end
local function restore(pool, onlyObject)
    for obj, fields in pairs(pool) do
        if not onlyObject or onlyObject == obj then
            for name, entry in pairs(fields) do
                pcall(function()
                    local current
                    if entry.Attribute then current = obj:GetAttribute(name) else current = obj[name] end
                    if current == entry.Applied then
                        if entry.Attribute then obj:SetAttribute(name, entry.Before) else obj[name] = entry.Before end
                    end
                end)
            end
            pool[obj] = nil
        end
    end
end
local speedOwned, jumpOwned, slideOwned, physicsOwned, fogOwned, hidingOwned = {}, {}, {}, {}, {}, {}
onCleanup(function()
    for _, pool in ipairs({speedOwned, jumpOwned, slideOwned, physicsOwned, fogOwned, hidingOwned}) do restore(pool) end
end)

local movement = Tabs.Main:AddLeftGroupbox("Character", "footprints")
toggle(movement, "DoorsSpeed", "Legit Speed Boost", function(value) if not value then restore(speedOwned) end end)
toggle(movement, "DoorsCanJump", "Enable jumping", function(value) if not value then restore(jumpOwned) end end)
toggle(movement, "DoorsCanSlide", "Enable sliding", function(value) if not value then restore(slideOwned) end end)
toggle(movement, "DoorsInfiniteJump", "Infinite jumps")
toggle(movement, "DoorsNoAcceleration", "No acceleration", function(value) if not value then restore(physicsOwned) end end)
local trackedCharacter
connect(RunService.PreSimulation, function()
    local char, h, part = player.Character, hum(), root()
    if char ~= trackedCharacter then
        restore(speedOwned) restore(jumpOwned) restore(slideOwned) restore(physicsOwned)
        trackedCharacter = char
    end
    if not char or not h then return end
    if enabled("DoorsCanJump") then override(jumpOwned, char, "CanJump", true, true) end
    if enabled("DoorsCanSlide") then override(slideOwned, char, "CanSlide", true, true) end
    if enabled("DoorsSpeed") and h.Health > 0 and not h.Sit and part and not part.Anchored
        and char:GetAttribute("Hiding") ~= true then
        local record = speedOwned[h] and speedOwned[h].WalkSpeed
        local baseline = record and h.WalkSpeed == record.Applied and record.Before or h.WalkSpeed
        override(speedOwned, h, "WalkSpeed", baseline + 4)
    else restore(speedOwned) end
end)
local lastJump = -math.huge
connect(UIS.JumpRequest, function()
    if not enabled("DoorsInfiniteJump") or Library.Toggled or UIS:GetFocusedTextBox() then return end
    local h = hum()
    if h and h.Health > 0 and not h.Sit and os.clock() - lastJump >= 0.15 then
        lastJump = os.clock()
        h:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

local effects = panels.Effects
toggle(effects, "DoorsNoFog", "Remove fog", function(value) if not value then restore(fogOwned) end end)
toggle(effects, "DoorsTransparentHiding", "Transparent occupied hiding spot", function(value)
    if not value then restore(hidingOwned) end
end)
effects:AddSlider("DoorsHidingAlpha", {Text = "Hiding-spot transparency", Default = 0.65, Min = 0, Max = 1, Rounding = 2})
local atmospheres = setmetatable({}, {__mode = "k"})
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    local camera = workspace.CurrentCamera
    if camera then
        for _, obj in ipairs(camera:GetDescendants()) do
            if obj:IsA("Atmosphere") then atmospheres[obj] = true end
        end
    end
end)
local function applyFog()
    if not enabled("DoorsNoFog") then return end
    override(fogOwned, Lighting, "FogStart", 0)
    override(fogOwned, Lighting, "FogEnd", 10000000)
    local camera = workspace.CurrentCamera
    for obj in pairs(atmospheres) do
        if obj:IsDescendantOf(Lighting) or (camera and obj:IsDescendantOf(camera)) then
            override(fogOwned, obj, "Density", 0)
        else restore(fogOwned, obj) atmospheres[obj] = nil end
    end
end
local function applyPhysicalProperties()
    if not enabled("DoorsNoAcceleration") then return end
    local char = player.Character
    if not char then restore(physicsOwned) return end
    for obj in pairs(physicsOwned) do
        if not obj:IsDescendantOf(char) then restore(physicsOwned, obj) end
    end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and not physicsOwned[part] then
            local old = part.CustomPhysicalProperties or part.CurrentPhysicalProperties
            if old then
                local custom = PhysicalProperties.new(100, old.Friction, old.Elasticity,
                    old.FrictionWeight, old.ElasticityWeight)
                override(physicsOwned, part, "CustomPhysicalProperties", custom)
            end
        end
    end
end
local function applyHidingTransparency()
    local active = {}
    if enabled("DoorsTransparentHiding") and player.Character then
        for obj, entry in pairs(candidates) do
            if entry.Category == "Hide" and obj:IsDescendantOf(workspace) then
                local occupied = false
                for _, child in ipairs(obj:GetDescendants()) do
                    if child:IsA("ObjectValue") and child.Name == "HiddenPlayer" and child.Value == player.Character then
                        occupied = true break
                    end
                end
                if occupied then
                    for _, part in ipairs(obj:GetDescendants()) do
                        if part:IsA("BasePart") then
                            active[part] = true
                            local record = hidingOwned[part] and hidingOwned[part].LocalTransparencyModifier
                            local original = record and part.LocalTransparencyModifier == record.Applied
                                and record.Before or part.LocalTransparencyModifier
                            override(hidingOwned, part, "LocalTransparencyModifier", math.max(original, Options.DoorsHidingAlpha.Value))
                        end
                    end
                end
            end
        end
    end
    for obj in pairs(hidingOwned) do if not active[obj] then restore(hidingOwned, obj) end end
end

local prompts = setmetatable({}, {__mode = "kv"})
local promptRoomOwned={}
onCleanup(function() restore(promptRoomOwned) end)
local promptCooldown = setmetatable({}, {__mode = "k"})
local activePrompt
local function finishPrompt()
    local record=activePrompt
    if not record then return end
    activePrompt=nil
    if record.NeedsEnd then pcall(function() record.Prompt:InputHoldEnd() end) end
    pcall(function() if record.Prompt.HoldDuration==0 then record.Prompt.HoldDuration=record.Before end end)
end
onCleanup(finishPrompt)
local focused=true
connect(UIS.WindowFocusReleased,function() focused=false;finishPrompt() end)
connect(UIS.WindowFocused,function() focused=true end)
local function promptAnchor(prompt)
    local owner=prompt.Parent
    if not owner then return end
    if owner:IsA("Attachment") and owner.Parent and owner.Parent:IsA("BasePart") then
        return owner.WorldPosition,owner.Parent
    elseif owner:IsA("BasePart") then return owner.Position,owner
    elseif owner:IsA("Model") then
        local part=owner.PrimaryPart or owner:FindFirstChildWhichIsA("BasePart",true)
        if part then return owner:GetPivot().Position,part end
    end
end
connect(player:GetAttributeChangedSignal("CurrentRoom"),renderMarkers)

local extraAlerts = panels.Entities
toggle(extraAlerts, "DoorsItemAlerts", "Item spawn notifications")
toggle(extraAlerts, "DoorsOxygenAlert", "Low oxygen warning")
extraAlerts:AddSlider("DoorsOxygenThreshold", {Text = "Oxygen warning (%)", Default = 25, Min = 5, Max = 75, Rounding = 0})
local oxygenLabel = extraAlerts:AddLabel("Oxygen: disabled")
toggle(extraAlerts, "DoorsHasteAlert", "Haste timer + warning")
extraAlerts:AddSlider("DoorsHasteThreshold", {Text = "Haste warning (seconds)", Default = 20, Min = 5, Max = 60, Rounding = 0})
local hasteLabel = extraAlerts:AddLabel("Haste timer: disabled")
local itemSeen = setmetatable({}, {__mode = "k"})
extraRegister = function(obj, allowAlert)
    if obj:IsA("ProximityPrompt") and not obj:GetAttribute("FakePrompt") then
        local owner=objectRoom(obj)
        if owner~=nil then override(promptRoomOwned,obj,"ParentRoom",owner,true) end
        prompts[obj]=obj
    end
    if obj:IsA("Atmosphere") then atmospheres[obj] = true end
    local category, label = classify(obj)
    if category == "Loot" and not itemSeen[obj] then
        itemSeen[obj] = true
        if allowAlert and enabled("DoorsItemAlerts") then
            if extension.ItemAlert then extension.ItemAlert(obj, label)
            else Library:Notify("Item spawned: " .. label, 4) end
        end
    end
end
for _, obj in ipairs(workspace:GetDescendants()) do extraRegister(obj, false) end
for _, obj in ipairs(Lighting:GetDescendants()) do extraRegister(obj, false) end
connect(Lighting.DescendantAdded, function(obj) extraRegister(obj, false) end)
local oxygenWarned, hasteWarned, warningCharacter = false, false, nil
local function updateExtraAlerts()
    local char = player.Character
    if warningCharacter ~= char then oxygenWarned = false warningCharacter = char end
    if enabled("DoorsOxygenAlert") then
        local value = char and char:GetAttribute("Oxygen")
        oxygenLabel:SetText(type(value) == "number" and ("Oxygen: %.1f%%"):format(value) or "Oxygen: unavailable")
        if type(value) == "number" then
            if value > Options.DoorsOxygenThreshold.Value + 5 then oxygenWarned = false end
            if value <= Options.DoorsOxygenThreshold.Value and not oxygenWarned then
                oxygenWarned = true
                if extension.Notify then extension.Notify("Low oxygen", ("%.1f%% remaining"):format(value))
                else Library:Notify(("Low oxygen: %.1f%%"):format(value), 5) end
            end
        end
    else oxygenWarned = false oxygenLabel:SetText("Oxygen: disabled") end
    if enabled("DoorsHasteAlert") then
        local floor = RS:FindFirstChild("FloorReplicated")
        local timer = floor and floor:FindFirstChild("DigitalTimer")
        local value = timer and timer:IsA("ValueBase") and timer.Value
        if type(value) == "number" then
            value = math.max(0, math.floor(value))
            hasteLabel:SetText(("Haste timer: %02d:%02d"):format(math.floor(value / 60), value % 60))
            if value > Options.DoorsHasteThreshold.Value + 5 then hasteWarned = false end
            if value <= Options.DoorsHasteThreshold.Value and not hasteWarned then
                hasteWarned = true
                if extension.Notify then extension.Notify("Haste timer", value .. " seconds remaining")
                else Library:Notify("Haste timer low: " .. value .. " seconds", 5) end
            end
        else hasteLabel:SetText("Haste timer: unavailable on this floor") end
    else hasteWarned = false hasteLabel:SetText("Haste timer: disabled") end
end
local extrasElapsed = 0
connect(RunService.Heartbeat, function(dt)
    extrasElapsed += dt
    if extrasElapsed < 0.5 then return end
    extrasElapsed = 0
    applyPhysicalProperties() applyFog() applyHidingTransparency() updateExtraAlerts()
    for _, other in ipairs(Players:GetPlayers()) do if other ~= player and other.Character then register(other.Character, false) end end
end)

local function installAbysallAutoInteract()
    -- Auto Interact source: user-supplied Abysall Main.luau, FireBacon, MIT.
    -- TriggerPrompt + Heartbeat body are preserved verbatim; only their local dependencies
    -- and fallback-worker unload restoration are supplied by ClaudeHub.
    local LocalPlayer=player
    local Character,Humanoid,Camera,Drops,Floor
    local missingDrops=Instance.new("Folder")
    onCleanup(function() missingDrops:Destroy() end)
    local Functions,Globals,Connections={},{},{}
    local Objects={Prompts=prompts}
    local Options={AutoInteractIgnoreList=Library.Options.DoorsAutoInteractIgnore,
        AutoInteractKeybind=Library.Options.DoorsAutoInteractKey}
    local Toggles={AutoInteractToggle=Library.Toggles.DoorsAutoInteract}
    local fallbackWorker,fallbackState
    local realTask=task
    local task=setmetatable({spawn=function(fn,...)
        local args=table.pack(...)
        return realTask.spawn(function() if alive then fn(table.unpack(args,1,args.n)) end end)
    end},{__index=realTask})
    local Abysall={Environment={fireproximityprompt=fireproximityprompt}}
    local function context()
        Character=player.Character;Humanoid=hum();Camera=workspace.CurrentCamera
        Drops=workspace:FindFirstChild("Drops") or missingDrops
        Floor=dataValue("Floor")
        Globals.MainUI=player:FindFirstChild("PlayerGui") and player:FindFirstChild("PlayerGui"):FindFirstChild("MainUI")
    end
    context()
    Functions.HasItem=function(Name,OnlyCharacter)
        local pack=LocalPlayer:FindFirstChild("Backpack")
        if not OnlyCharacter and pack and pack:FindFirstChild(Name) then return pack:FindFirstChild(Name)
        elseif Character and Character:FindFirstChild(Name) then return Character:FindFirstChild(Name) end
    end
    local Services={Workspace=workspace,ProximityPromptService=game:GetService("ProximityPromptService")}
    Services.RunService={Heartbeat={Connect=function(_,fn)
        return connect(RunService.Heartbeat,function(...)
            context()
            if Character and Humanoid and Humanoid.Health>0 and Camera then fn(...) end
        end)
    end}}
    onCleanup(function()
        if fallbackWorker and realTask.cancel then pcall(realTask.cancel,fallbackWorker) end
        if fallbackState then
            local state=fallbackState
            pcall(function() state.Prompt:InputHoldEnd() end)
            for field,value in pairs({MaxActivationDistance=state.OldDist,Enabled=state.OldEnable,
                HoldDuration=state.OldHold,RequiresLineOfSight=state.OldLOS}) do pcall(function() state.Prompt[field]=value end) end
            pcall(function() state.Prompt.Parent=state.OldParent end)
            if state.ShownConn then state.ShownConn:Disconnect() end
            if state.FiredConn then state.FiredConn:Disconnect() end
            if state.TempPart then state.TempPart:Destroy() end
            fallbackState=nil
        end
    end)
local PromptsToFire = {}
local PromptCooldown = {}

Functions.FirePrompt      = Abysall.Environment.fireproximityprompt
Functions.ForceFirePrompt = Abysall.Environment.fireproximityprompt

if not Functions.FirePrompt then
	Functions.FirePrompt = function(Prompt)
		if not Prompt:IsA("ProximityPrompt") or PromptCooldown[Prompt] or table.find(PromptsToFire, Prompt) or not Camera then return end
		table.insert(PromptsToFire, Prompt)
	end
	Functions.ForceFirePrompt = Functions.FirePrompt

	fallbackWorker=task.spawn(function()
		while task.wait() and alive do
			local Prompt = table.remove(PromptsToFire, 1)
			if not Prompt then continue end
			PromptCooldown[Prompt] = true

			local OldDist   = Prompt.MaxActivationDistance
			local OldEnable = Prompt.Enabled
			local OldParent = Prompt.Parent
			local OldHold   = Prompt.HoldDuration
			local OldLOS    = Prompt.RequiresLineOfSight
            local state={Prompt=Prompt,OldParent=OldParent,OldDist=OldDist,OldEnable=OldEnable,OldHold=OldHold,OldLOS=OldLOS}
            fallbackState=state

			Prompt.MaxActivationDistance = 99999
			Prompt.Enabled = true
			Prompt.HoldDuration = 0
			Prompt.RequiresLineOfSight = false

			local TempPart = Instance.new("Part")
            state.TempPart=TempPart
			TempPart.Parent = Services.Workspace
			TempPart.CanCollide = false TempPart.CanQuery = false TempPart.CanTouch = false
			TempPart.Anchored = true TempPart.Transparency = 1
			TempPart.Size = Vector3.new(0.001, 0.001, 0.001)
			TempPart.Position = Camera.CFrame:ToWorldSpace(CFrame.new(0, 0, -0.1)).Position

			if not Prompt or not OldParent then
				TempPart:Destroy()
				PromptCooldown[Prompt] = nil
				continue
			end

			pcall(function() Prompt.Parent = TempPart end)

			local Shown, Fired = false, false

			local ShownConn = Services.ProximityPromptService.PromptShown:Connect(function(P)
				if P == Prompt then Shown = true end
			end)
			local FiredConn = Prompt.Triggered:Connect(function() Fired = true end)
            state.ShownConn=ShownConn;state.FiredConn=FiredConn

			local T1 = 0
			while not Shown and T1 < 5 do T1 += 1 task.wait() end

			local T2 = 0
			while not Fired and T2 < 5 do
				Prompt:InputHoldBegin()
				Prompt:InputHoldEnd()
				T2 += 1 task.wait()
			end

			Prompt.MaxActivationDistance = OldDist
			Prompt.Enabled = OldEnable
			Prompt.HoldDuration = OldHold
			Prompt.RequiresLineOfSight = OldLOS
			pcall(function() Prompt.Parent = OldParent end)
			task.wait()
			PromptCooldown[Prompt] = nil
			TempPart:Destroy()
			ShownConn:Disconnect()
			FiredConn:Disconnect()
            if fallbackState==state then fallbackState=nil end
		end
	end)
end

local AutoInteractBlacklist = {
	HidePrompt=true, RiftPrompt=true, StarRiftPrompt=true, InteractPrompt=true, ClimbPrompt=true,
	DonatePrompt=true, DialoguePrompt=true, RevivePrompt=true, EnterPrompt=true, AnimatePrompt=true,
	ToolEventPrompt=true, Prompt=true, PropPrompt=true
}

local TriggerDebounce = false

Functions.TriggerPrompt = function(Prompt)
	if AutoInteractBlacklist[Prompt.Name] then return end
	if not Prompt or not Prompt.Parent then return end
	if TriggerDebounce then return end

	local ParentItem = Functions.HasItem(Prompt.Parent.Name)
	if ParentItem and ParentItem:GetAttribute("Durability") and ParentItem:GetAttribute("DurabilityMax")
		and ParentItem:GetAttribute("Durability") >= ParentItem:GetAttribute("DurabilityMax")
	then return end

	local LockPromptNames = { UnlockPrompt=true, SkullPrompt=true, LockPrompt=true, ThingToEnable=true, FusesPrompt=true }
	local IsLockPrompt = LockPromptNames[Prompt.Name]
		or (Prompt.Parent and Prompt.Parent:GetAttribute("Locked") == true)
		or (Prompt.Parent and Prompt.Parent.Parent and Prompt.Parent.Parent.Name == "Locker_Small_Locked" and Prompt.Name == "ActivateEventPrompt")

	if IsLockPrompt then
		if Options.AutoInteractIgnoreList.Value["Locks"] then return end
		local KeyItems = { "Key","GeneratorFuse","KeyBackdoor","KeyElectrical","KeyIron","Lockpick","SkeletonKey","Shears","Multitool" }
		local OffhandKeyItems = { "Key","GeneratorFuse","KeyElectrical","KeyIron" }
		local HasKey = false
		for _, K in KeyItems do if Functions.HasItem(K, true) then HasKey = true break end end
		for _, K in OffhandKeyItems do if Functions.HasItem(K) then HasKey = true break end end
		if not HasKey then return end
	end

	if Prompt.Parent.Name == "CuttableVines" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Chest_Vine" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Cellar" and not Functions.HasItem("Shears", true) and not Functions.HasItem("Multitool", true) then return end
	if Prompt.Parent.Name == "SkullLock" and not Functions.HasItem("SkeletonKey", true) then return end
	if Prompt.Parent.Name == "Lock1" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) or Prompt.Parent.Name == "Lock2" and not Functions.HasItem("Lockpick", true) and not Functions.HasItem("Multitool", true) then return end
	if Functions.HasItem("Shears", true) and IsLockPrompt and Prompt.Parent.Name ~= "CuttableVines" and Prompt.Parent.Name ~= "Chest_Vine" and Prompt.Parent.Name ~= "Cellar" then return end

	if Prompt.Parent.Name == "GlitchCube" and Options.AutoInteractIgnoreList.Value["Glitch Fragments"] then return end

	if (Prompt.Parent.Name == "KeyObtain" and (Functions.HasItem("Key") or Functions.HasItem("KeyBackdoor")))
		or (Prompt.Parent.Name == "ElectricalKeyObtain" and Functions.HasItem("KeyElectrical"))
	then return end

	if Prompt:IsDescendantOf(Drops) and Options.AutoInteractIgnoreList.Value["Dropped Items"] then return end
	if Prompt.Parent.Name == "TrackLever" then return end
	if Prompt.Name == "ActivateEventPrompt" and (Prompt.ActionText == "Close"
		or Prompt.Parent.Name == "ElevatorBreaker"
		or (Prompt.Parent.Parent and Prompt.Parent.Parent.Name == "IndustrialGate"))
	then return end
	if Prompt.Name == "ActivateEventPrompt" and (Prompt.Parent.Name == "Padlock" or Prompt.Parent.Name == "MinesAnchor") then return end
	if Prompt.Parent.Name == "LeverForGate" and Prompt:GetAttribute("Interactions") then return end
	if Prompt.Parent.Parent and (Prompt.Parent.Parent.Name == "DoorFake" or Prompt.Parent.Parent.Name == "FakeDoor") then return end
	if Prompt.Parent:GetAttribute("JeffShop") and Options.AutoInteractIgnoreList.Value["Jeff Items"] then return end
	if Prompt:GetAttribute("AutoInteractIgnore") then return end
	if Prompt.Name == "PushPrompt" and Options.AutoInteractIgnoreList.Value["Minecarts"] then return end
	if (Prompt.Parent.Name == "GoldPile" or Prompt.Parent.Name == "StardustPickup") and Options.AutoInteractIgnoreList.Value["Currency"] then return end

	if Prompt.Parent.Name == "Bandage" then
		local BPack = Functions.HasItem("BandagePack")
		if Humanoid.Health >= Humanoid.MaxHealth and not BPack then return end
		if BPack and BPack:GetAttribute("Durability") >= BPack:GetAttribute("DurabilityMax") then return end
	end

	if Prompt.Parent.Name == "Battery" then
		local Tool = Character:FindFirstChildOfClass("Tool")
		local BPack = Functions.HasItem("BatteryPack")
		if not Tool and not BPack then return end
		if Tool and Tool:GetAttribute("LightSource") then
			if Tool:GetAttribute("Durability") and Tool:GetAttribute("DurabilityMax")
				and Tool:GetAttribute("Durability") > Tool:GetAttribute("DurabilityMax")
			then return end
		elseif not BPack then
			return
		end
		if BPack and BPack:GetAttribute("Durability") >= BPack:GetAttribute("DurabilityMax") then return end
	end

	if Prompt.Name == "HerbPrompt" then
		local Effects = Globals.MainUI.MainFrame.Healthbar:FindFirstChild("Effects")
		if Effects and Effects.HerbGreenEffect.Visible then return end
	end

	if (Prompt.Parent.Name == "LibraryHintPaper" or Prompt.Parent.Name == "PickupItem") and (Functions.HasItem("LibraryHintPaper") or Functions.HasItem("LibraryHintPaperHard")) then return end
	if Prompt.Parent.Name == "AlarmClock" and Functions.HasItem("AlarmClock") then return end
	if Prompt.Parent.Name == "KeyObtainFake" or Prompt.Parent.Name == "TithingPlate" then return end

	Functions.FirePrompt(Prompt)
	TriggerDebounce = true
	if Floor == "OldHotel" then task.wait() end
	TriggerDebounce = false
end

Globals.LastAutoInteractFire = tick()
Connections.AutoInteract = Services.RunService.Heartbeat:Connect(function()
	local Active = Toggles.AutoInteractToggle.Value or Options.AutoInteractKeybind:GetState()
    if not Active then return end
    if tick() - Globals.LastAutoInteractFire < 1/60 then return end

	for _, Prompt in Objects.Prompts do
        if Prompt:GetAttribute("ParentRoom") and tonumber(Prompt:GetAttribute("ParentRoom")) ~= tonumber(LocalPlayer:GetAttribute("CurrentRoom")) then continue end

		if Prompt.Parent and (Prompt.Parent:IsA("BasePart") or Prompt.Parent:IsA("Model")) then
			local Distance
			if Prompt.Parent:IsA("BasePart") then
				Distance = LocalPlayer:DistanceFromCharacter(Prompt.Parent.Position)
			else
				Distance = LocalPlayer:DistanceFromCharacter(Prompt.Parent:GetPivot().Position)
			end
			if Distance <= Prompt.MaxActivationDistance and Prompt.Enabled or Distance <= Prompt.MaxActivationDistance and Prompt.Name == "LongPushPrompt" or Distance <= Prompt.MaxActivationDistance and Prompt.Name == "BigPropPrompt" then
				task.spawn(Functions.TriggerPrompt, Prompt)
			end
		end
	end
    Globals.LastAutoInteractFire = tick()
end)

end

-- v0.4 port layer. Everything below is opt-in; no source loader/analytics is executed.
do
local function installReferencePort()
    local function slider(box, id, text, default, min, max, rounding)
        return box:AddSlider(id, {Text=text, Default=default, Min=min, Max=max, Rounding=rounding or 0, Compact=true})
    end
    local function val(id, fallback)
        local option = Options[id]
        if option and option.Value ~= nil then return option.Value end
        return fallback
    end
    local function multi(box, id, text, values, defaults)
        return box:AddDropdown(id, {Text=text, Values=values, Default=defaults or values, Multi=true, AllowNull=true})
    end
    local function dropdown(box, id, text, values, default)
        return box:AddDropdown(id, {Text=text, Values=values, Default=default or 1})
    end
    local function badge(id, key)
        -- SetValue also accepts modifier combinations in ObsidianUltra.
        if Options[id.."Key"] then Options[id.."Key"]:SetValue({key, "Toggle"}) end
    end

    -- Per-category colors live beside the same toggle, not in a separate bind list.
    local categories = {{"Item","Objectives",Color3.fromRGB(0,255,0)}, {"Exit","Doors",Color3.fromRGB(0,200,255)},
        {"Hide","Hiding spots",Color3.fromRGB(255,170,0)}, {"Player","Players",Color3.fromRGB(255,255,255)},
        {"Chest","Chests",Color3.fromRGB(255,255,0)}, {"Loot","Items",Color3.fromRGB(170,0,255)},
        {"Currency","Currency",Color3.fromRGB(255,255,0)}, {"Ladder","Ladders",Color3.fromRGB(255,255,255)},
        {"Entity","Entities",Color3.fromRGB(255,0,0)}}
    for _, entry in ipairs(categories) do
        Toggles["DoorsMark"..entry[1]]:AddColorPicker("DoorsColor"..entry[1],
            {Text=entry[2],Default=entry[3],Transparency=0})
    end
    local esp = panels.ESPSettings
    dropdown(esp,"DoorsESPRoomScope","Room visibility",{"Current room","All loaded rooms"})
    toggle(esp,"DoorsESPRainbow","Rainbow effect")
    esp:AddToggle("DoorsESPDistance",{Text="Show distance",Default=true})
    slider(esp,"DoorsESPFill","Fill transparency",0.75,0,1,2)
    slider(esp,"DoorsESPOutline","Outline transparency",0,0,1,2)
    slider(esp,"DoorsESPTextAlpha","Text transparency",0,0,1,2)
    slider(esp,"DoorsESPStrokeAlpha","Text outline transparency",0,0,1,2)
    slider(esp,"DoorsESPFade","Fade-in time",0.25,0,2,2)
    slider(esp,"DoorsESPLimit","Render limit (labels)",64,1,240)
    slider(esp,"DoorsESPTextSize","Text size",16,10,32)
    dropdown(esp,"DoorsESPFont","Text font",{"Code","Gotham","Arial","Highway","SourceSans"})
    dropdown(esp,"DoorsTracerOrigin","Tracer origin",{"Bottom","Center","Top"})
    slider(esp,"DoorsTracerThickness","Tracer thickness",0.75,0.5,4,2)
    toggle(esp,"DoorsESPTracers","Enable tracers")
    slider(esp,"DoorsArrowRadius","Arrow radius",250,40,500)
    toggle(esp,"DoorsESPArrows","Enable arrows")
    extension.StyleMarker = function(marker,row)
        if not marker.Born then marker.Born=os.clock() end
        local color = enabled("DoorsESPRainbow") and Color3.fromHSV((os.clock()*0.12)%1,0.85,1)
            or val("DoorsColor"..row.Entry.Category, colors[row.Entry.Category])
        marker.Color=color
        marker.Text.TextColor3=color
        marker.Text.Font=Enum.Font[val("DoorsESPFont","Code")]
        marker.Text.TextSize=val("DoorsESPTextSize",16)
        marker.Billboard.Size=UDim2.fromOffset(math.max(190,#row.Entry.Label*val("DoorsESPTextSize",16)*0.6+110),40)
        marker.Text.Text = row.Entry.Label .. (enabled("DoorsESPDistance") and (" | %d studs"):format(math.floor(row.Distance)) or "")
        for _, h in ipairs(marker.Highlights) do h.FillColor=color h.OutlineColor=color end
    end
    local function decorateMarkers()
        local camera=workspace.CurrentCamera
        if not camera then return end
        local view=camera.ViewportSize
        local center=Vector2.new(view.X/2,view.Y/2)
        for _,marker in pairs(markers) do
            local fade=val("DoorsESPFade",0.25)
            local opacity=fade==0 and 1 or math.clamp((os.clock()-(marker.Born or 0))/fade,0,1)
            marker.Text.TextTransparency=1-(1-val("DoorsESPTextAlpha",0))*opacity
            marker.Text.TextStrokeTransparency=1-(1-val("DoorsESPStrokeAlpha",0))*opacity
            local target=marker.Billboard.Adornee
            if not target or not target.Parent then
                if marker.Tracer then marker.Tracer.Visible=false end
                if marker.Arrow then marker.Arrow.Visible=false end
                continue
            end
            local point,onScreen=camera:WorldToViewportPoint(target.Position)
            local inFront=point.Z>0
            if enabled("DoorsESPTracers") and inFront and onScreen then
                if not marker.Tracer then
                    marker.Tracer=Instance.new("Frame")
                    marker.Tracer.Name="ClaudeHubTracer";marker.Tracer.BorderSizePixel=0
                    marker.Tracer.AnchorPoint=Vector2.new(0.5,0.5);marker.Tracer.Parent=gui
                end
                local origin=val("DoorsTracerOrigin","Bottom")
                local start=Vector2.new(center.X,origin=="Top" and 0 or origin=="Center" and center.Y or view.Y)
                local finish=Vector2.new(point.X,point.Y)
                local delta=finish-start
                marker.Tracer.Visible=true;marker.Tracer.BackgroundColor3=marker.Color or marker.Text.TextColor3
                marker.Tracer.BackgroundTransparency=1-opacity
                marker.Tracer.Position=UDim2.fromOffset((start.X+finish.X)/2,(start.Y+finish.Y)/2)
                marker.Tracer.Size=UDim2.fromOffset(delta.Magnitude,val("DoorsTracerThickness",0.75))
                marker.Tracer.Rotation=math.deg(math.atan2(delta.Y,delta.X))
            elseif marker.Tracer then marker.Tracer.Visible=false end
            if enabled("DoorsESPArrows") and (not onScreen or not inFront) then
                if not marker.Arrow then
                    marker.Arrow=Instance.new("TextLabel")
                    marker.Arrow.Name="ClaudeHubArrow";marker.Arrow.BackgroundTransparency=1
                    marker.Arrow.AnchorPoint=Vector2.new(0.5,0.5);marker.Arrow.Size=UDim2.fromOffset(26,26)
                    marker.Arrow.Text=">";marker.Arrow.Font=Enum.Font.Code;marker.Arrow.TextSize=25
                    marker.Arrow.TextStrokeTransparency=0;marker.Arrow.Parent=gui
                end
                -- Camera-local direction avoids projecting a behind-camera point to the wrong side.
                local localPoint=camera.CFrame:PointToObjectSpace(target.Position)
                local direction=Vector2.new(localPoint.X,-localPoint.Y)
                if direction.Magnitude<0.001 then direction=Vector2.new(0,1) end
                direction=direction.Unit
                local radius=math.max(10,math.min(val("DoorsArrowRadius",250),center.X-20,center.Y-20))
                local pos=center+direction*radius
                marker.Arrow.Visible=true;marker.Arrow.Position=UDim2.fromOffset(pos.X,pos.Y)
                marker.Arrow.Rotation=math.deg(math.atan2(direction.Y,direction.X))
                marker.Arrow.TextColor3=marker.Color or marker.Text.TextColor3
            elseif marker.Arrow then marker.Arrow.Visible=false end
        end
    end
    connect(RunService.RenderStepped, decorateMarkers)

    -- Notification filters are independent of the ESP selection.
    local itemChoices={"Green Herb"}
    local uniqueItems={["Green Herb"]=true}
    for _,label in pairs(lootNames) do if not uniqueItems[label] then uniqueItems[label]=true table.insert(itemChoices,label) end end
    table.sort(itemChoices)
    multi(panels.Entities,"DoorsNotifyEntities","Entity list",entityChoices)
    multi(panels.Entities,"DoorsNotifyItems","Item list",itemChoices)
    toggle(panels.Entities,"DoorsNotifyDistance","Show item distance")
    toggle(panels.Entities,"DoorsLibraryAlert","Notify library code")
    local libraryLabel=panels.Entities:AddLabel("Library code: unavailable")
    local notifyPanel=panels.Notify
    toggle(notifyPanel,"DoorsNotifyChat","Notify chat (public)")
    notifyPanel:AddInput("DoorsNotifyMessage",{Text="Message",Default="spawned!",Placeholder="spawned!",MaxLength=100,Finished=true})
    dropdown(notifyPanel,"DoorsNotifyStyle","Notify style",{"Abysall","Doors","STX","Library"})
    slider(notifyPanel,"DoorsNotifyVolume","Sound volume",3,0,10,1)
    toggle(notifyPanel,"DoorsNotifySound","Play sound")
    toggle(notifyPanel,"DoorsNotifyKeep","Keep entity notifications")
    local noticeRoot=Instance.new("Frame")
    noticeRoot.Name="ClaudeHubNoticeStack";noticeRoot.BackgroundTransparency=1
    noticeRoot.Size=UDim2.fromOffset(420,36);noticeRoot.Position=UDim2.fromOffset(24,210);noticeRoot.Parent=gui
    local handle=Instance.new("TextLabel")
    handle.Name="DragHeader";handle.BackgroundColor3=Color3.fromRGB(20,17,28);handle.BorderSizePixel=0
    handle.Size=UDim2.fromOffset(420,24);handle.Text="ClaudeHub notifications  |  drag"
    handle.TextColor3=Color3.fromRGB(185,160,240);handle.Font=Enum.Font.Code;handle.TextSize=12
    handle.Active=true;handle.Visible=false;handle.Parent=noticeRoot
    local notices,noticeDrag,noticeOrigin,noticePosition={},nil,nil,nil
    local TweenService=game:GetService("TweenService")
    local function tween(n,field,obj,seconds,style,goal)
        if n[field] then n[field]:Cancel() end
        n[field]=TweenService:Create(obj,TweenInfo.new(seconds,style,Enum.EasingDirection.Out),goal)
        n[field]:Play()
    end
    local function removeNotice(n)
        for _,field in ipairs({"MotionTween","ProgressTween"}) do if n[field] then n[field]:Cancel() end end
        n.Frame:Destroy()
    end
    connect(handle.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            noticeDrag=input;noticeOrigin=input.Position;noticePosition=noticeRoot.AbsolutePosition
        end
    end)
    connect(UIS.InputChanged,function(input)
        if not noticeDrag then return end
        if noticeDrag.UserInputType==Enum.UserInputType.Touch and input~=noticeDrag then return end
        if noticeDrag.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local camera=workspace.CurrentCamera;if not camera then return end
        local delta=input.Position-noticeOrigin
        local view=camera.ViewportSize
        local stackHeight=28
        for _,n in ipairs(notices) do stackHeight+=n.Height+10 end
        noticeRoot.Position=UDim2.fromOffset(math.clamp(noticePosition.X+delta.X,0,math.max(0,view.X-420)),
            math.clamp(noticePosition.Y+delta.Y,0,math.max(0,view.Y-math.max(100,stackHeight))))
    end)
    connect(UIS.InputEnded,function(input)
        if input==noticeDrag or input.UserInputType==Enum.UserInputType.MouseButton1 then noticeDrag=nil end
    end)
    connect(UIS.WindowFocusReleased,function() noticeDrag=nil end)
    local function updateNotices()
        for i=#notices,1,-1 do
            local n=notices[i]
            local keep=enabled("DoorsNotifyKeep") and n.Object and n.Object:IsDescendantOf(workspace) or false
            if os.clock()>=n.Expires and not keep then
                removeNotice(n);table.remove(notices,i)
            elseif n.Kept~=keep then
                n.Kept=keep
                if keep then
                    if n.ProgressTween then n.ProgressTween:Cancel() end
                    n.Progress.Size=UDim2.new(1,0,0,3)
                else
                    tween(n,"ProgressTween",n.Progress,math.max(0.05,n.Expires-os.clock()),Enum.EasingStyle.Linear,{Size=UDim2.new(0,0,0,3)})
                end
            end
        end
        handle.Visible=#notices>0
        local y=28
        for _,n in ipairs(notices) do
            if n.TargetY~=y then
                if n.TargetY==nil then n.Frame.Position=UDim2.fromOffset(420,y) end
                n.TargetY=y
                tween(n,"MotionTween",n.Frame,0.35,Enum.EasingStyle.Exponential,{Position=UDim2.fromOffset(0,y)})
            end
            y+=n.Height+10
        end
    end
    extension.Notify=function(title,body,obj)
        title,body=tostring(title or "ClaudeHub"),tostring(body or "")
        local style=val("DoorsNotifyStyle","Abysall")
        if style=="Library" then Library:Notify(title..(body~="" and ("\n"..body) or ""),6)
        else
            if #notices>=6 then removeNotice(notices[1]);table.remove(notices,1) end
            local width,height=420,50
            if style=="STX" then width,height=240,90 elseif style=="Doors" then width,height=370,96 end
            local accent=obj and Color3.fromRGB(255,90,90) or Color3.fromRGB(133,80,255)
            if style=="Doors" then accent=obj and Color3.fromRGB(255,110,80) or Color3.fromRGB(255,213,130) end
            local frame=Instance.new("Frame")
            frame.Name="Notice";frame.Size=UDim2.fromOffset(width,height);frame.BorderSizePixel=0
            frame.BackgroundColor3=style=="Doors" and Color3.fromRGB(32,25,20)
                or (style=="STX" and Color3.fromRGB(40,40,40) or Color3.fromRGB(19,17,29))
            frame.BackgroundTransparency=style=="Abysall" and 0.4 or 0
            frame.Parent=noticeRoot
            Instance.new("UICorner",frame).CornerRadius=UDim.new(0,4)
            local function text(name,value,x,y,w,h,size,font)
                local label=Instance.new("TextLabel")
                label.Name=name;label.BackgroundTransparency=1;label.Position=UDim2.fromOffset(x,y);label.Size=UDim2.fromOffset(w,h)
                label.TextColor3=Color3.fromRGB(240,235,250);label.TextWrapped=true
                label.TextXAlignment=Enum.TextXAlignment.Left;label.TextYAlignment=Enum.TextYAlignment.Top
                label.Font=font or Enum.Font.Code;label.TextSize=size;label.RichText=false;label.Text=value;label.Parent=frame
                return label
            end
            if style=="STX" then
                text("Title",title,8,5,width-34,20,12,Enum.Font.GothamSemibold)
                local divider=Instance.new("Frame",frame);divider.BorderSizePixel=0;divider.BackgroundColor3=accent
                divider.Position=UDim2.fromOffset(0,25);divider.Size=UDim2.fromOffset(width,2)
                text("Description",body,8,34,width-16,46,12,Enum.Font.Gotham)
            else
                local icon=Instance.new("ImageLabel")
                icon.Name="WarningIcon";icon.BackgroundTransparency=1;icon.Position=UDim2.fromOffset(10,5)
                icon.Size=UDim2.fromOffset(40,40);icon.Image="rbxassetid://3944668821";icon.ImageColor3=accent;icon.Parent=frame
                if style=="Doors" then
                    local border=Instance.new("UIStroke",frame);border.Color=accent;border.Thickness=1
                    text("Heading",obj and "WARNING" or "NOTIFICATION",60,7,width-90,14,11,Enum.Font.Highway).TextColor3=accent
                    text("Title",title,60,25,width-86,25,16,Enum.Font.Highway)
                    text("Description",body,60,53,width-76,35,12,Enum.Font.Highway)
                else
                    text("Title",title,60,7,width-90,15,10)
                    text("Description",body,60,24,width-76,18,10)
                end
            end
            local progress=Instance.new("Frame",frame)
            progress.Name="Lifetime";progress.BorderSizePixel=0;progress.BackgroundColor3=accent
            progress.Position=UDim2.new(0,0,1,-3);progress.Size=UDim2.new(1,0,0,3)
            local close=Instance.new("TextButton")
            close.Name="Close";close.Size=UDim2.fromOffset(22,20);close.Position=UDim2.fromOffset(width-24,0)
            close.Text="x";close.BackgroundTransparency=1;close.TextColor3=Color3.fromRGB(240,235,250);close.Parent=frame
            close.Activated:Connect(function()
                for i,n in ipairs(notices) do if n.Frame==frame then removeNotice(n);table.remove(notices,i) break end end
                updateNotices()
            end)
            table.insert(notices,{Frame=frame,Expires=os.clock()+6,Created=os.clock(),Object=obj,Height=height,Progress=progress});updateNotices()
        end
        if enabled("DoorsNotifySound") then
            local sound=Instance.new("Sound")
            sound.Name="ClaudeHubNoticeSound";sound.SoundId="rbxassetid://4590662766"
            sound.Volume=val("DoorsNotifyVolume",3)/10;sound.Parent=gui;sound:Play()
            task.delay(4,function() if sound.Parent then sound:Destroy() end end)
        end
    end
    local lastChat=-math.huge
    extension.EntityAlert=function(obj,label)
        if val("DoorsNotifyEntities",{})[label]~=true then return false end
        extension.Notify(label.." detected",val("DoorsNotifyMessage","spawned!"),obj)
        if enabled("DoorsNotifyChat") and os.clock()-lastChat>=2 then
            lastChat=os.clock()
            local text=label.." "..tostring(val("DoorsNotifyMessage","spawned!")):sub(1,100)
            task.spawn(function()
                if not alive or not enabled("DoorsNotifyChat") then return end
                local ok,err=pcall(function()
                    local chat=game:GetService("TextChatService")
                    local channels=chat:FindFirstChild("TextChannels")
                    local general=channels and channels:FindFirstChild("RBXGeneral")
                    if general then general:SendAsync(text)
                    else
                        local events=RS:FindFirstChild("DefaultChatSystemChatEvents")
                        local send=events and events:FindFirstChild("SayMessageRequest")
                        assert(send and send:IsA("RemoteEvent"),"No supported chat channel")
                        send:FireServer(text,"All")
                    end
                end)
                if not ok and alive then Library:Notify("Chat notification failed: "..tostring(err),4) end
            end)
        end
        return true
    end
    extension.ItemAlert=function(obj,label)
        if val("DoorsNotifyItems",{})[label]~=true then return end
        local body="Spawned in a loaded room"
        if enabled("DoorsNotifyDistance") then
            local anchor=markerTarget(obj,"Loot");local r=root()
            if anchor and r then body..=(" | %d studs"):format(math.floor((anchor.Position-r.Position).Magnitude)) end
        end
        extension.Notify(label,body)
    end
    notifyPanel:AddButton({Text="Test Notification",Func=function() extension.Notify("Test notification","ClaudeHub DOORS "..VERSION) end})
    notifyPanel:AddButton({Text="Clear notifications",Func=function()
        for _,n in ipairs(notices) do removeNotice(n) end table.clear(notices);handle.Visible=false
    end})
    notifyPanel:AddButton({Text="Reset notification position",Func=function() noticeDrag=nil;noticeRoot.Position=UDim2.fromOffset(24,210) end})

    -- Camera adapter: require only after opt-in and only the known game module.
    local cameraOwned,tableOwned,thirdParts,ambientOwned={},{},{},{}
    extension.BeforeBright=function() restore(ambientOwned) end
    local mainGame,moduleObject,modulePending,lastModuleTry=nil,nil,false,-math.huge
    local adapterLabel=panels.Camera:AddLabel("Game camera adapter: not requested")
    local function mainUI() local pg=player:FindFirstChild("PlayerGui") return pg and pg:FindFirstChild("MainUI") end
    local function path(obj,...)
        for _,name in ipairs({...}) do obj=obj and obj:FindFirstChild(name) end return obj
    end
    local function requestMainGame()
        if modulePending or os.clock()-lastModuleTry<5 then return end
        local module=path(mainUI(),"Initiator","Main_Game")
        if moduleObject==module and mainGame then return end
        lastModuleTry=os.clock()
        if not module or not module:IsA("ModuleScript") then adapterLabel:SetText("Game camera adapter: Main_Game unavailable") return end
        modulePending=true
        task.spawn(function()
            local ok,result=pcall(require,module)
            modulePending=false
            if not alive then return end
            restore(tableOwned)
            if ok and type(result)=="table" then mainGame=result;moduleObject=module;adapterLabel:SetText("Game camera adapter: loaded")
            else mainGame=nil;moduleObject=nil;adapterLabel:SetText("Game camera adapter: require unsupported / failed") end
        end)
    end
    toggle(panels.Camera,"DoorsAmbient","Ambient",function(value) if not value then restore(ambientOwned) end end)
        :AddColorPicker("DoorsAmbientColor",{Text="Ambient",Default=Color3.fromRGB(255,255,255),Transparency=0})
    toggle(panels.Camera,"DoorsNoShake","Remove camera shake")
    toggle(panels.Camera,"DoorsNoBobbing","Remove camera bobbing")
    toggle(panels.Camera,"DoorsRemoveCutscenes","Remove cutscenes (known modules)")
    toggle(panels.Camera,"DoorsThirdPerson","Third person",function(value)
        if not value then restore(thirdParts) if extension.ResetThirdPerson then extension.ResetThirdPerson() end end
    end)
    badge("DoorsThirdPerson","T")
    slider(panels.Camera,"DoorsThirdX","X offset",1.5,-10,10,1)
    slider(panels.Camera,"DoorsThirdY","Y offset",1,-10,10,1)
    slider(panels.Camera,"DoorsThirdZ","Z offset",5,-10,10,1)
    toggle(panels.Camera,"DoorsThirdWall","Wall check")
    toggle(panels.Camera,"DoorsViewmodel","Viewmodel offset")
    slider(panels.Camera,"DoorsViewX","Viewmodel X",0,-10,10,1)
    slider(panels.Camera,"DoorsViewY","Viewmodel Y",0,-10,10,1)
    slider(panels.Camera,"DoorsViewZ","Viewmodel Z",0,-10,10,1)
    local lastAppliedCamera,lastBase,lastResult
    local function undoOffset()
        if lastAppliedCamera and lastAppliedCamera.Parent and lastResult and lastAppliedCamera.CFrame==lastResult then
            lastAppliedCamera.CFrame=lastBase
        end
        lastAppliedCamera,lastBase,lastResult=nil,nil,nil
    end
    extension.ResetThirdPerson=undoOffset
    local function beforeCamera() undoOffset() end
    local function cameraStep()
        if not alive or not ready then return end
        local camera=workspace.CurrentCamera
        if not camera then return end
        local h=hum()
        local third=enabled("DoorsThirdPerson") and h and h.Health>0 and not extension.Spectating
            and player:GetAttribute("Alive")~=false and player.Character~=nil
            and player.Character:GetAttribute("Hiding")~=true
            and player.Character:GetAttribute("AnimatingClient")~=true
        if not third then restore(thirdParts) return end
        local char=player.Character
        local base=camera.CFrame
        local offset=Vector3.new(val("DoorsThirdX",1.5),val("DoorsThirdY",1),val("DoorsThirdZ",5))
        local desired=base*CFrame.new(offset)
        if enabled("DoorsThirdWall") and (desired.Position-base.Position).Magnitude>0.001 then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={char,highlights};params.RespectCanCollide=true
            local diff=desired.Position-base.Position
            local hit=workspace:Raycast(base.Position,diff,params)
            if hit then
                local length=math.max(0,(hit.Position-base.Position).Magnitude-0.3)
                desired=base+diff.Unit*math.min(diff.Magnitude,length)
            end
        end
        lastAppliedCamera,lastBase,lastResult=camera,base,desired;camera.CFrame=desired
        for _,part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name~="HumanoidRootPart" and part.Name~="Collision" and part.Name~="CollisionPart" then
                override(thirdParts,part,"LocalTransparencyModifier",0)
                if part.Name=="Head" or part.Parent:IsA("Accessory") then override(thirdParts,part,"Transparency",0) end
            end
        end
        for part in pairs(thirdParts) do
            if not part:IsDescendantOf(char) then restore(thirdParts,part) end
        end
    end
    local cameraPre="ClaudeHubDoorsPreCamera_"..player.UserId
    local cameraPost="ClaudeHubDoorsPostCamera_"..player.UserId
    RunService:BindToRenderStep(cameraPre,Enum.RenderPriority.Camera.Value-1,beforeCamera)
    RunService:BindToRenderStep(cameraPost,Enum.RenderPriority.Last.Value+1,cameraStep)
    onCleanup(function()
        RunService:UnbindFromRenderStep(cameraPre);RunService:UnbindFromRenderStep(cameraPost)
        undoOffset();restore(thirdParts);restore(cameraOwned);restore(tableOwned);restore(ambientOwned)
    end)
    local function updateCameraAdapter()
        if enabled("DoorsAmbient") then
            -- Fullbright owns Ambient when both are on, avoiding two competing writers.
            if enabled("DoorsBright") then restore(ambientOwned)
            else override(ambientOwned,Lighting,"Ambient",val("DoorsAmbientColor",Color3.fromRGB(255,255,255))) end
        else restore(ambientOwned) end
        local need=enabled("DoorsNoShake") or enabled("DoorsNoBobbing") or enabled("DoorsViewmodel")
        if need then requestMainGame() end
        if not mainGame then return end
        local wanted={}
        if enabled("DoorsNoShake") and mainGame.csgo~=nil then override(tableOwned,mainGame,"csgo",CFrame.new());wanted.csgo=true end
        if enabled("DoorsViewmodel") and mainGame.tooloffset~=nil then
            override(tableOwned,mainGame,"tooloffset",Vector3.new(val("DoorsViewX",0),val("DoorsViewY",0),val("DoorsViewZ",0)));wanted.tooloffset=true
        end
        if enabled("DoorsNoBobbing") and type(mainGame.spring)=="table" and type(mainGame.spring.Speed)=="number" then
            override(tableOwned,mainGame.spring,"Speed",9e9)
        else if mainGame.spring then restore(tableOwned,mainGame.spring) end end
        local fields=tableOwned[mainGame]
        if fields then
            for name,record in pairs(fields) do if not wanted[name] then
                if mainGame[name]==record.Applied then mainGame[name]=record.Before end fields[name]=nil
            end end
        end
    end

    -- Reversible visual modules. Unknown layouts are skipped instead of WaitForChild hangs.
    local visualObjects=setmetatable({}, {__mode="k"})
    local visualOwned={}
    local effectEntries={{"DoorsNoGlitchScare","Disable Glitch jumpscare","Glitch"},
        {"DoorsNoTimothyScare","Disable Timothy jumpscare","SpiderJumpscare"},
        {"DoorsNoVoidScare","Disable Void jumpscare","Void"},
        {"DoorsNoHideVignette","Disable Hide vignette"}, {"DoorsNoFiredamp","Disable firedamp effect"},
        {"DoorsNoEntityScares","Disable entity jumpscares","Jumpscares"}}
    for _,entry in ipairs(effectEntries) do toggle(panels.Effects,entry[1],entry[2]) end
    local cutscenes={Figure=true,FigureEnd=true,FigureHotelEnd=true,FigureHotelFire=true,SeekIntroFools=true,
        SeekIntroHotel=true,SeekIntroMines=true,SeekIntroMines2=true,SerewSeekDrain=true,SewerSeekLower=true,GrumbleNestEnd=true,EyestalkIntro=true}
    local relevantNames={Glitch=true,SpiderJumpscare=true,Void=true,Jumpscares=true,HideVignette=true,LiveFiredamp=true}
    local function watchObject(obj)
        if obj:IsA("ModuleScript") and (relevantNames[obj.Name] or cutscenes[obj.Name])
            or obj.Name=="HideVignette" or obj.Name=="LiveFiredamp" then
            visualObjects[obj]=obj.Name
        end
    end
    for _,obj in ipairs(workspace:GetDescendants()) do watchObject(obj) end
    for _,obj in ipairs(RS:GetDescendants()) do watchObject(obj) end
    local pg=player:FindFirstChild("PlayerGui")
    if pg then for _,obj in ipairs(pg:GetDescendants()) do watchObject(obj) end connect(pg.DescendantAdded,watchObject) end
    connect(workspace.DescendantAdded,watchObject);connect(RS.DescendantAdded,watchObject)
    local function activeField(pool,obj,name)
        local fields=pool[obj];local entry=fields and fields[name]
        if entry then
            pcall(function() if obj[name]==entry.Applied then obj[name]=entry.Before end end)
            fields[name]=nil
            if not next(fields) then pool[obj]=nil end
        end
    end
    connect(RunService.RenderStepped, updateCameraAdapter)
    local function updateVisualEffects()
        for obj,name in pairs(visualObjects) do
            if not obj.Parent then restore(visualOwned,obj);visualObjects[obj]=nil continue end
            local ownUI=obj:IsDescendantOf(gui)
            local relevant=(pg and obj:IsDescendantOf(pg)) or obj:IsDescendantOf(RS)
            local disable=false
            if relevant and not ownUI and obj:IsA("ModuleScript") then
                for _,entry in ipairs(effectEntries) do if entry[3]==name and enabled(entry[1]) then disable=true end end
                if cutscenes[name] and enabled("DoorsRemoveCutscenes") then
                    local parentName=obj.Parent.Name
                    disable=parentName=="Cutscenes" or obj.Parent.Name=="FloorReplicated"
                end
            end
            if disable then override(visualOwned,obj,"Name",name.."_ClaudeHubDisabled") else activeField(visualOwned,obj,"Name") end
            if name=="HideVignette" and relevant and obj:IsA("GuiObject") and enabled("DoorsNoHideVignette") then
                override(visualOwned,obj,"Visible",false)
            else activeField(visualOwned,obj,"Visible") end
            if name=="LiveFiredamp" and enabled("DoorsNoFiredamp") then
                if obj:IsA("PostEffect") or obj:IsA("ParticleEmitter") then override(visualOwned,obj,"Enabled",false)
                elseif obj:IsA("GuiObject") then override(visualOwned,obj,"Visible",false) end
            elseif name=="LiveFiredamp" then restore(visualOwned,obj) end
        end
        -- Firedamp is an attribute on streamed rooms; do not spoof CurrentRoom.
        local rooms=roomFolder()
        if rooms then for _,room in ipairs(rooms:GetChildren()) do
            if enabled("DoorsNoFiredamp") and room:GetAttribute("Firedamp")~=nil then override(visualOwned,room,"Firedamp",false,true)
            else
                local fields=visualOwned[room]
                if fields and fields.Firedamp then restore(visualOwned,room) end
            end
        end end
    end
    onCleanup(function() restore(visualOwned) end)

    -- Character additions: own only the parts and constraints created/modified here.
    local noclipOwned,flightOwned={},{ }
    local flightRoot,flightAttachment,flightVelocity,flightAlign
    local function stopFly()
        for _,obj in ipairs({flightVelocity,flightAlign,flightAttachment}) do if obj then obj:Destroy() end end
        if flightRoot and flightRoot.Parent and flightVelocity then
            pcall(function() flightRoot.AssemblyLinearVelocity=Vector3.zero end)
        end
        flightRoot,flightAttachment,flightVelocity,flightAlign=nil,nil,nil,nil
        restore(flightOwned)
    end
    toggle(movement,"DoorsFly","Fly",function(v) if not v then stopFly() end end);badge("DoorsFly","G")
    slider(movement,"DoorsFlySpeed","Fly speed",20,1,80)
    toggle(movement,"DoorsNoclip","Noclip",function(v) if not v then restore(noclipOwned) end end);badge("DoorsNoclip","N")
    local function flyStep()
        local char,h,r=player.Character,hum(),root()
        if enabled("DoorsNoclip") and char and h and h.Health>0 then
            for _,part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then override(noclipOwned,part,"CanCollide",false) end end
            for part in pairs(noclipOwned) do if not part:IsDescendantOf(char) then restore(noclipOwned,part) end end
        else restore(noclipOwned) end
        if not enabled("DoorsFly") or not r or not h or h.Health<=0 or r.Anchored or char:GetAttribute("Hiding")==true then stopFly() return end
        if flightRoot~=r then
            stopFly();flightRoot=r
            flightAttachment=Instance.new("Attachment");flightAttachment.Name="ClaudeHubFlight";flightAttachment.Parent=r
            flightVelocity=Instance.new("LinearVelocity");flightVelocity.Name="ClaudeHubFlightVelocity"
            flightVelocity.Attachment0=flightAttachment;flightVelocity.RelativeTo=Enum.ActuatorRelativeTo.World
            flightVelocity.MaxForce=math.huge;flightVelocity.Parent=r
            flightAlign=Instance.new("AlignOrientation");flightAlign.Name="ClaudeHubFlightOrientation"
            flightAlign.Mode=Enum.OrientationAlignmentMode.OneAttachment;flightAlign.Attachment0=flightAttachment
            flightAlign.MaxTorque=math.huge;flightAlign.Responsiveness=20;flightAlign.Parent=r
        end
        override(flightOwned,h,"AutoRotate",false)
        local vector=Vector3.zero
        local camera=workspace.CurrentCamera
        if camera and focused and not Library.Toggled and not Library.IsPicking and not UIS:GetFocusedTextBox() then
            local function down(key) return UIS:IsKeyDown(Enum.KeyCode[key]) and 1 or 0 end
            vector=camera.CFrame.LookVector*(down("W")-down("S"))+camera.CFrame.RightVector*(down("D")-down("A"))
                +Vector3.new(0,down("Space")-math.max(down("LeftControl"),down("RightControl")),0)
            if vector.Magnitude>1 then vector=vector.Unit end
        end
        flightVelocity.VectorVelocity=vector*val("DoorsFlySpeed",20)
        if camera then flightAlign.CFrame=camera.CFrame.Rotation end
    end
    connect(RunService.PreSimulation,flyStep)
    onCleanup(function() stopFly();restore(noclipOwned) end)

    local automation=Tabs.Main:AddRightGroupbox("Automation","wand-sparkles")
    automation:AddToggle("DoorsAutoInteract",{Text="Auto Interact",Default=false})
        :AddKeyPicker("DoorsAutoInteractKey",{Default="R",Text="Auto Interact",Mode="Hold",Modes={"Hold","Toggle"},SyncToggleState=false,NoUI=true})
    automation:AddDropdown("DoorsAutoInteractIgnore",{Text="Ignore List",Multi=true,AllowNull=true,
        Values={"Glitch Fragments","Jeff Items","Dropped Items","Currency","Minecarts","Locks"},
        Default={"Glitch Fragments","Jeff Items","Dropped Items"}})
    installAbysallAutoInteract()
    toggle(automation,"DoorsAutoPadlock","Auto unlock padlock (known code)")
    slider(automation,"DoorsPadlockRange","Unlock distance",10,2,20)
    toggle(automation,"DoorsAutoAnchor","Auto solve anchors (visible hint)")
    toggle(automation,"DoorsSpectate","Spectate entity")
    dropdown(automation,"DoorsSpectateMode","Spectate mode",{"Player to entity","Entity camera"})
    multi(automation,"DoorsSpectateEntities","Spectate entity list",entityChoices)
    local automationLabel=automation:AddLabel("Automation: idle")
    local function libraryCode()
        local char=player.Character;local pack=player:FindFirstChild("Backpack")
        local paper=char and (char:FindFirstChild("LibraryHintPaper") or char:FindFirstChild("LibraryHintPaperHard"))
            or pack and (pack:FindFirstChild("LibraryHintPaper") or pack:FindFirstChild("LibraryHintPaperHard"))
        local ui=paper and paper:FindFirstChild("UI")
        local hints=path(player:FindFirstChild("PlayerGui"),"PermUI","Hints")
        if not ui or not hints then return nil end
        local count=dataValue("Floor")=="Fools" and 10 or 5
        local code=table.create(count,"_")
        for _,hint in ipairs(hints:GetChildren()) do
            if hint:IsA("ImageLabel") then
                local number=hint:FindFirstChild("TextLabel")
                if number and number:IsA("TextLabel") and number.Text:match("^%d$") then
                    for _,shape in ipairs(ui:GetChildren()) do
                        local index=tonumber(shape.Name)
                        if shape:IsA("ImageLabel") and index and code[index] and shape.ImageRectOffset==hint.ImageRectOffset then code[index]=number.Text end
                    end
                end
            end
        end
        return table.concat(code)
    end
    local lastLibrary,lastSubmit,lastAnchorSubmit=nil,-math.huge,-math.huge
    local anchorBusy=false
    local puzzleObjects=setmetatable({}, {__mode="k"})
    local function watchPuzzle(obj)
        if obj.Name=="Padlock" or obj.Name=="MinesAnchor" then puzzleObjects[obj]=true end
    end
    for _,obj in ipairs(workspace:GetDescendants()) do watchPuzzle(obj) end
    connect(workspace.DescendantAdded,watchPuzzle)
    local function remotes() return RS:FindFirstChild("RemotesFolder") or RS:FindFirstChild("EntityInfo") or RS:FindFirstChild("Bricks") end
    local function updateAutomation()
        local code=libraryCode()
        libraryLabel:SetText("Library code: "..tostring(code or "unavailable"))
        if enabled("DoorsLibraryAlert") and code and code~=lastLibrary then extension.Notify("Library code",code);lastLibrary=code end
        if not enabled("DoorsLibraryAlert") then lastLibrary=nil end
        local r,h=root(),hum()
        if not r or not h or h.Health<=0 or not focused or Library.Toggled or UIS:GetFocusedTextBox() then return end
        for obj in pairs(puzzleObjects) do
            if not obj:IsDescendantOf(workspace) then puzzleObjects[obj]=nil continue end
            local part=obj:IsA("BasePart") and obj or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)
            if not part then continue end
            local distance=(r.Position-part.Position).Magnitude
            if obj.Name=="Padlock" and enabled("DoorsAutoPadlock") and code and not code:find("_")
                and distance<=val("DoorsPadlockRange",10) and os.clock()-lastSubmit>=2 then
                local remote=path(remotes(),"PL")
                if remote and remote:IsA("RemoteEvent") then lastSubmit=os.clock();remote:FireServer(code);automationLabel:SetText("Padlock: submitted known code")
                else automationLabel:SetText("Padlock: PL remote unavailable") end
            elseif obj.Name=="MinesAnchor" and enabled("DoorsAutoAnchor") and not obj:GetAttribute("Activated") and not anchorBusy and os.clock()-lastAnchorSubmit>=2 then
                local hint=path(mainUI(),"AnchorHintFrame")
                local designation=path(hint,"AnchorCode") or path(hint,"Anchor")
                local sign=path(obj,"Sign","TextLabel")
                local number=path(hint,"Code")
                local prompt=obj:FindFirstChild("ActivateEventPrompt",true)
                local remote=obj:FindFirstChild("AnchorRemote")
                -- Never solve another anchor using the current hint's code.
                if designation and sign and number and designation.Text==sign.Text and number.Text:match("^%d+$")
                    and prompt and prompt:IsA("ProximityPrompt") and distance<=prompt.MaxActivationDistance
                    and remote and remote:IsA("RemoteFunction") then
                    lastAnchorSubmit=os.clock();anchorBusy=true
                    task.spawn(function()
                        local ok=pcall(function() if alive and enabled("DoorsAutoAnchor") then remote:InvokeServer(number.Text) end end)
                        anchorBusy=false
                        if alive then automationLabel:SetText(ok and "Anchor: visible code submitted" or "Anchor: request failed") end
                    end)
                end
            end
        end
    end
    local spectateOwned={}
    local function updateSpectate()
        extension.Spectating=false
        if not enabled("DoorsSpectate") then restore(spectateOwned) return end
        local camera=workspace.CurrentCamera;local r=root()
        if not camera or not r then restore(spectateOwned) return end
        local nearest,best
        for obj,entry in pairs(candidates) do
            if entry.Category=="Entity" and entityNames[obj.Name] and obj:IsDescendantOf(workspace)
                and val("DoorsSpectateEntities",{})[entry.Label] then
                local part=markerTarget(obj,"Entity")
                if part then local d=(r.Position-part.Position).Magnitude if not best or d<best then nearest=part;best=d end end
            end
        end
        if not nearest then restore(spectateOwned) return end
        for old in pairs(spectateOwned) do if old~=camera then restore(spectateOwned,old) end end
        if camera.CameraType==Enum.CameraType.Scriptable then restore(spectateOwned) return end
        extension.Spectating=true
        if val("DoorsSpectateMode","Player to entity")=="Entity camera" then
            activeField(spectateOwned,camera,"CFrame")
            override(spectateOwned,camera,"CameraSubject",nearest)
        else
            activeField(spectateOwned,camera,"CameraSubject")
            -- This mode adjusts the rendered camera only, never the character's orientation.
            local delta=nearest.Position-camera.CFrame.Position
            if delta.Magnitude>0.01 then override(spectateOwned,camera,"CFrame",CFrame.lookAt(camera.CFrame.Position,nearest.Position)) end
        end
    end
    connect(RunService.RenderStepped,updateSpectate)
    onCleanup(function() extension.Spectating=false;restore(spectateOwned) end)

    local misc=Tabs.Main:AddRightGroupbox("Miscellaneous","ellipsis")
    local function remoteButton(text,name,tooltip)
        misc:AddButton({Text=text,DoubleClick=true,Tooltip=tooltip,Func=function()
            local remote=path(remotes(),name)
            if not remote or not remote:IsA("RemoteEvent") then Library:Notify(text..": compatible remote unavailable",4) return end
            local ok,err=pcall(function() remote:FireServer() end)
            if not ok then Library:Notify(text..": "..tostring(err),4) end
        end})
    end
    remoteButton("Play Again","PlayAgain","Double-click to request a new run; availability is controlled by the game.")
    remoteButton("Return to Lobby","Lobby","Double-click to request a return to the lobby.")
    -- Revive can consume a limited inventory item. Require an explicit one-shot confirmation.
    misc:AddButton({Text="Revive (uses your revive)",DoubleClick=true,Tooltip="May consume one of your revives; no purchase is initiated. Double-click to confirm.",Func=function()
        if player:GetAttribute("Alive")~=false then Library:Notify("Revive is available only after death",4) return end
        local remote=path(remotes(),"Revive")
        if remote and remote:IsA("RemoteEvent") then remote:FireServer() else Library:Notify("Revive remote unavailable",4) end
    end})
    misc:AddButton({Text="Reset Character",DoubleClick=true,Tooltip="Kills your character locally; double-click to confirm.",Func=function() local h=hum() if h then h.Health=0 end end})

    -- Remaining portable General controls from the reference (all OFF).
    local interaction=Tabs.Main:AddLeftGroupbox("Self","hand")
    toggle(interaction,"DoorsDoorReach","Door reach (server request)")
    slider(interaction,"DoorsDoorReachRange","Door reach distance",15,5,75)
    toggle(interaction,"DoorsAntiIdle","Disable idle kick (VirtualUser)")
    toggle(movement,"DoorsClosetDelay","Remove closet exit delay")
    local lastExit=-math.huge
    connect(player.Idled,function()
        if not alive or not enabled("DoorsAntiIdle") then return end
        local ok=pcall(function()
            local virtualUser=game:GetService("VirtualUser")
            virtualUser:CaptureController();virtualUser:ClickButton2(Vector2.new())
        end)
        if not ok and alive then Library:Notify("Anti-idle: VirtualUser is unavailable in this executor",4) end
    end)
    local rushLikeEntities={Rush=true,Ambush=true,Blitz=true,["A-60"]=true,["A-120"]=true,
        ["Frozen Ambush"]=true,AR0xMBUSH=true,["RNIUSHCG=="]=true}
    local rushLikeChoices={"Rush","Ambush","Blitz","A-60","A-120","Frozen Ambush","AR0xMBUSH","RNIUSHCG=="}
    toggle(automation,"DoorsAutoCloset","Auto closet (nearby empty spot)");badge("DoorsAutoCloset","Q")
    multi(automation,"DoorsAutoClosetIgnore","Auto closet: ignore entities",rushLikeChoices,{})
    slider(automation,"DoorsAutoClosetRange","Threat radius",150,25,500)
    toggle(automation,"DoorsAutoBreaker","Auto breaker box (after interaction)")
    local doorTimes=setmetatable({}, {__mode="k"})
    local breakerCodes=setmetatable({}, {__mode="k"})
    local lastCloset,lastBreaker=-math.huge,-math.huge
    local function bindBreaker(obj)
        if obj.Name~="ElevatorBreaker" then return end
        local code=path(obj,"SurfaceGui","Frame","Code")
        if not code or not code:IsA("TextLabel") or breakerCodes[code] then return end
        breakerCodes[code]=true
        connect(code:GetPropertyChangedSignal("Text"),function()
            if not alive or not enabled("DoorsAutoBreaker") or not focused or Library.Toggled or UIS:GetFocusedTextBox()
                or os.clock()-lastBreaker<0.3 or not obj:IsDescendantOf(workspace) then return end
            local part=obj:IsA("BasePart") and obj or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)
            local r,h=root(),hum()
            if not part or not r or not h or h.Health<=0 or (part.Position-r.Position).Magnitude>25 then return end
            local remote=path(remotes(),"EBF")
            if remote and remote:IsA("RemoteEvent") then lastBreaker=os.clock();remote:FireServer() end
        end)
    end
    local function tryBindBreaker(obj)
        bindBreaker(obj)
        local parent=obj.Parent
        for _=1,4 do if not parent or parent==workspace then break end bindBreaker(parent);parent=parent.Parent end
    end
    for _,obj in ipairs(workspace:GetDescendants()) do bindBreaker(obj) end
    connect(workspace.DescendantAdded,tryBindBreaker)
    local function lineOfSight(prompt,position,target)
        if not prompt.RequiresLineOfSight then return true end
        local r=root();if not r then return false end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={player.Character,highlights}
        local origin=player.Character:FindFirstChild("Head") or r
        local hit=workspace:Raycast(origin.Position,position-origin.Position,params)
        return not hit or hit.Instance==target or (prompt.Parent:IsA("Model") and hit.Instance:IsDescendantOf(prompt.Parent))
    end
    local function requestHide(prompt)
        if activePrompt or not prompt.Enabled then return end
        local record={Prompt=prompt,Before=prompt.HoldDuration}
        activePrompt=record;promptCooldown[prompt]=os.clock()+0.8
        local ok=pcall(function()
            prompt.HoldDuration=0
            if type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
            else record.NeedsEnd=true;prompt:InputHoldBegin() end
        end)
        if not ok then finishPrompt() return end
        task.delay(0.03,function() if activePrompt==record then finishPrompt() end end)
    end
    local function updateMoreAutomation()
        local char,r,h=player.Character,root(),hum()
        if not char or not r or not h or h.Health<=0 or not focused or Library.Toggled or UIS:GetFocusedTextBox() then return end
        if enabled("DoorsClosetDelay") and char:GetAttribute("Hiding")==true and char:GetAttribute("AnimatingClient")~=true
            and r.Anchored and h.MoveDirection.Magnitude>0.05 and os.clock()-lastExit>=0.8 then
            local remote=path(remotes(),"CamLock")
            if remote and remote:IsA("RemoteEvent") then lastExit=os.clock();remote:FireServer() end
        end
        if enabled("DoorsDoorReach") and char:GetAttribute("Hiding")~=true then
            local best,bestDistance
            for obj,entry in pairs(candidates) do
                if entry.Category=="Exit" and obj:IsDescendantOf(workspace) and not obj:GetAttribute("Opened") and obj:GetAttribute("Locked")~=true then
                    local leaves=doorLeaves(obj)
                    local part=leaves[1]
                    local remote=obj:FindFirstChild("ClientOpen")
                    if part and remote and remote:IsA("RemoteEvent") then
                        local distance=(r.Position-part.Position).Magnitude
                        if distance<=val("DoorsDoorReachRange",15) and (not bestDistance or distance<bestDistance)
                            and os.clock()>=(doorTimes[obj] or 0) then best=obj;bestDistance=distance end
                    end
                end
            end
            if best then doorTimes[best]=os.clock()+1;best:FindFirstChild("ClientOpen"):FireServer() end
        end
        if not enabled("DoorsAutoCloset") or char:GetAttribute("Hiding")==true or activePrompt or os.clock()-lastCloset<1.5 then return end
        local threat=false
        for obj,entry in pairs(candidates) do
            if entry.Category=="Entity" and rushLikeEntities[entry.Label] and obj:IsDescendantOf(workspace)
                and not val("DoorsAutoClosetIgnore",{})[entry.Label] then
                local p=markerTarget(obj,"Entity")
                if p and (p.Position-r.Position).Magnitude<=val("DoorsAutoClosetRange",150) then threat=true break end
            end
        end
        if not threat then return end
        local best,bestDistance
        for obj,entry in pairs(candidates) do
            if entry.Category=="Hide" and obj:IsDescendantOf(workspace) and inCurrentRoom(obj) then
                local hidden=obj:FindFirstChild("HiddenPlayer",true)
                local prompt=obj:FindFirstChild("HidePrompt",true)
                -- Missing occupancy metadata is treated as unknown, never assumed empty.
                if hidden and hidden:IsA("ObjectValue") and hidden.Value==nil and prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                    local position,target=promptAnchor(prompt)
                    if position then
                        local distance=(position-r.Position).Magnitude
                        if distance<=prompt.MaxActivationDistance and (not bestDistance or distance<bestDistance)
                            and lineOfSight(prompt,position,target) then best=prompt;bestDistance=distance end
                    end
                end
            end
        end
        if best then lastCloset=os.clock();requestHide(best) end
    end

    local elapsed=0
    connect(RunService.Heartbeat,function(dt)
        elapsed+=dt
        if elapsed<0.2 then return end elapsed=0
        updateNotices();updateVisualEffects();updateAutomation();updateMoreAutomation()
    end)
    extension.Finalize=function()
        for _,obj in ipairs(workspace:GetDescendants()) do watchObject(obj);watchPuzzle(obj);tryBindBreaker(obj) end
        for _,obj in ipairs(RS:GetDescendants()) do watchObject(obj) end
        if pg then for _,obj in ipairs(pg:GetDescendants()) do watchObject(obj) end end
    end
    -- Individual feature-off callbacks also restore at the next 0.2s adapter tick.
    -- All pools are restored synchronously by the unload handlers, including pending holds.
    onCleanup(function() for _,n in ipairs(notices) do removeNotice(n) end table.clear(notices);table.clear(visualObjects) end)
end
installReferencePort()
end

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
    SaveManager:SetFolder("ClaudeHub/DOORS/configs-v044")
    SaveManager:BuildConfigSection(Tabs.Settings)
    -- No auto-load: a saved config cannot silently enable gameplay aids.
end
for _, obj in ipairs(workspace:GetDescendants()) do register(obj, false) extraRegister(obj, false) end
if extension.Finalize then extension.Finalize() end
ready = true
refresh()
loadedLabel:SetText(("Loaded in: %.2fs"):format(os.clock() - STARTED))
Library:Notify("DOORS " .. VERSION .. " ready. RightControl opens the menu. All feature toggles start OFF.", 6)
return Library
