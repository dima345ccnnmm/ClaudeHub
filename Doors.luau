--[[
DOORS feature portions adapted from Abysall by FireBacon (bocaj111004).
Source: https://github.com/bocaj111004/Abysall
Revision: 66d4192d00d9b824a304b654bc2d2eb89c3b372b
Port: entity/object aliases, ESP and selected interaction, character,
lighting and notification patterns, adapted to ClaudeHub's renderer/lifecycle. Original analytics, remote actions,
anti-cheat hooks and destructive entity handlers are NOT included.

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
-- ClaudeHub / DOORS v0.3.0 -- initial client-assist module, not an anti-cheat bypass.
-- Lobby and all places in the DOORS universe are routed here by Loader.luau.
local VERSION, STARTED = "v0.3.0", os.clock()
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
    Main = Window:AddTab("Main", "gamepad-2"),
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
    Text = table.concat({"+ New DOORS module and universe-aware loader",
        "+ Home: profile, live room/floor/player information",
        "+ Exit, key/book/lever and hiding-spot markers",
        "= Door ESP targets only leaf parts, including double doors",
        "+ Entity selector: multi-list, show only one, select all/clear",
        "+ Fast Interact: inline rebindable Hold key (F by default)",
        "+ 15 more Abysall-inspired functions; all default OFF",
        "+ ESP credit: FireBacon (bocaj111004) | MIT",
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
local entityNames = {
    ["RushMoving"] = "Rush",
    ["AmbushMoving"] = "Ambush",
    ["Eyes"] = "Eyes",
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
local function entityLabel(obj)
    if not obj:IsA("Model") and not obj:IsA("BasePart") then return end
    if player.Character and obj:IsDescendantOf(player.Character) then return end
    -- Abysall targets MandrakeLive.Hole, not every unrelated part named Hole.
    if obj.Name == "Hole" and (not obj.Parent or obj.Parent.Name ~= "MandrakeLive") then return end
    local label = entityESPLabels[obj.Name] or entityNames[obj.Name]
    if not label then return end
    -- Avoid duplicate labels for the same rig (e.g. Figure > FigureRig).
    local ancestor = obj.Parent
    while ancestor and ancestor ~= workspace do
        if (entityESPLabels[ancestor.Name] or entityNames[ancestor.Name]) == label then return end
        ancestor = ancestor.Parent
    end
    return label
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
    if marker then releasePatch(marker) marker.Billboard:Destroy()
        for _, h in ipairs(marker.Highlights) do h:Destroy() end
        markers[obj] = nil end
end
local function clearMarkers()
    for obj in pairs(markers) do drop(obj) end
end
onCleanup(function() clearMarkers() table.clear(candidates) end)
local markersBox = Tabs.Visuals:AddLeftGroupbox("Room markers", "scan-eye")
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
markersBox:AddLabel("Loaded objects only. Item/hiding names are an initial allowlist; some floors need additional adapters. Hiding spots may be occupied or unsafe.", true)
local entityBox = Tabs.Visuals:AddRightGroupbox("Entity ESP | Abysall port", "ghost")
entityBox:AddLabel("By FireBacon (bocaj111004) | adapted for ClaudeHub", true)
toggle(entityBox, "DoorsMarkEntity", "Entity ESP", function(value)
    if not value then
        for obj, marker in pairs(markers) do if marker.Category == "Entity" then drop(obj) end end
    end
end)
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
entityBox:AddLabel("All known types are selected initially, but Entity markers is OFF. Names come from Abysall; Archives/Stairwell-specific entities are not yet verified.", true)
local alertsBox = Tabs.Assist:AddLeftGroupbox("Entity alerts", "bell")
toggle(alertsBox, "DoorsAlerts", "Entity spawn notifications", function(value)
    if value then
        for obj, entry in pairs(candidates) do
            if obj.Parent and entry.Category == "Entity" and entityNames[obj.Name] then alertEntity(obj, entry.Label) end
        end
    end
end)
alertsBox:AddLabel("Spawn notifications use Abysall dynamic-entity names. Room hazards have ESP without flooding spawn notifications. Not every threat is detectable from replicated objects.", true)
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
            if enabled("DoorsMark" .. category) and selected then
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
            h.FillTransparency, h.OutlineTransparency = 0.85, 0.2
            h.Enabled = highlightCount < 24
            if h.Enabled then highlightCount += 1 end
        end
        marker.Highlight = marker.Highlights[1]
        if entry.Category == "Entity" then
            prepareHighlight(marker, obj, row.Part, entry.Label, marker.Highlight and marker.Highlight.Enabled)
        end
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

local movement = Tabs.Main:AddLeftGroupbox("Character | Abysall adaptations", "footprints")
toggle(movement, "DoorsSpeed", "Speed boost", function(value) if not value then restore(speedOwned) end end)
movement:AddSlider("DoorsSpeedAdd", {Text = "Extra speed", Default = 4, Min = 0, Max = 30, Rounding = 0})
toggle(movement, "DoorsCanJump", "Enable jumping", function(value) if not value then restore(jumpOwned) end end)
toggle(movement, "DoorsCanSlide", "Enable sliding", function(value) if not value then restore(slideOwned) end end)
toggle(movement, "DoorsInfiniteJump", "Infinite jumps")
toggle(movement, "DoorsNoAcceleration", "No acceleration", function(value) if not value then restore(physicsOwned) end end)
movement:AddLabel("Client-side movement settings. The game/server may override or reject them; no anti-cheat bypass is installed. No Acceleration uses reversible physical properties, not repeated velocity writes.", true)
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
        override(speedOwned, h, "WalkSpeed", baseline + Options.DoorsSpeedAdd.Value)
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

local effects = Tabs.Visuals:AddRightGroupbox("Environment | Abysall adaptations", "cloud-fog")
toggle(effects, "DoorsNoFog", "Remove fog", function(value) if not value then restore(fogOwned) end end)
toggle(effects, "DoorsTransparentHiding", "Transparent occupied hiding spot", function(value)
    if not value then restore(hidingOwned) end
end)
effects:AddSlider("DoorsHidingAlpha", {Text = "Hiding-spot transparency", Default = 0.65, Min = 0, Max = 1, Rounding = 2})
effects:AddLabel("Transparency applies only to your occupied spot (HiddenPlayer == your character), using local transparency. Other players' hiding spots are unchanged.", true)
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

-- Fast Interact combines Abysall's InstantPrompts/AutoInteract patterns.
-- It never changes reach/line-of-sight or bypasses disabled prompts. Hold F
-- (rebind the inline badge) with the checkbox enabled and the menu closed.
local interaction = Tabs.Main:AddRightGroupbox("Fast Interact", "hand")
local prompts = setmetatable({}, {__mode = "k"})
local promptCooldown = setmetatable({}, {__mode = "k"})
local activePrompt
local function finishPrompt()
    local record = activePrompt
    if not record then return end
    activePrompt = nil
    if record.NeedsEnd then pcall(function() record.Prompt:InputHoldEnd() end) end
    pcall(function()
        if record.Prompt.HoldDuration == 0 then record.Prompt.HoldDuration = record.Before end
    end)
end
interaction:AddToggle("DoorsFastInteract", {Text = "Fast Interact (hold key)", Default = false,
    Callback = function(value) if not value then finishPrompt() end end}):AddKeyPicker("DoorsFastInteractKey", {
    Default = "F", Text = "Fast Interact", Mode = "Hold", Modes = {"Hold", "Toggle"},
    SyncToggleState = false, NoUI = true,
})
interaction:AddSlider("DoorsInteractRange", {Text = "Search range (studs)", Default = 8, Min = 2, Max = 15, Rounding = 0})
interaction:AddDropdown("DoorsInteractIgnore", {Text = "Ignore", Multi = true, AllowNull = true,
    Values = {"Hide / exit", "Locks / purchases", "Dropped items", "Currency", "Fake doors / hazards"},
    Default = {"Hide / exit", "Locks / purchases", "Dropped items", "Fake doors / hazards"}})
interaction:AddLabel("Enable, close the menu, then hold F near a prompt. The badge can be rebound (including modifiers). Search range never exceeds the prompt's own activation distance. Shop/lock/hiding/hazard prompts are ignored by default. Server-required holds may still apply.", true)
onCleanup(finishPrompt)
local focused = true
connect(UIS.WindowFocusReleased, function() focused = false finishPrompt() end)
connect(UIS.WindowFocused, function() focused = true end)
local function promptAnchor(prompt)
    local owner = prompt.Parent
    if not owner then return end
    if owner:IsA("Attachment") and owner.Parent and owner.Parent:IsA("BasePart") then
        return owner.WorldPosition, owner.Parent
    elseif owner:IsA("BasePart") then return owner.Position, owner
    elseif owner:IsA("Model") then
        local part = owner.PrimaryPart or owner:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.Position, part end
    end
end
local function ignoredPrompt(prompt)
    local selection = Options.DoorsInteractIgnore.Value
    if prompt:GetAttribute("AutoInteractIgnore") then return true end
    if selection["Hide / exit"] and (prompt.Name == "HidePrompt" or prompt.Name == "ExitPrompt") then return true end
    if selection["Locks / purchases"] and (prompt.Name:lower():find("lock") or prompt.Name:lower():find("purchase")) then return true end
    local obj = prompt.Parent
    while obj and obj ~= workspace do
        if selection["Locks / purchases"] and (obj:GetAttribute("JeffShop") or obj:GetAttribute("Locked") == true
            or obj.Name == "JeffShop" or obj.Name:lower():find("locked")) then return true end
        if selection["Dropped items"] and obj.Name == "Drops" then return true end
        if selection["Currency"] and (obj.Name == "GoldPile" or obj.Name == "StardustPickup") then return true end
        if selection["Fake doors / hazards"] and (obj.Name == "FakeDoor" or obj.Name == "DoorFake"
            or obj.Name == "KeyObtainFake" or obj.Name == "TithingPlate" or obj.Name == "GlitchCube") then return true end
        obj = obj.Parent
    end
    return false
end
local function fastInteract()
    local key = Options.DoorsFastInteractKey
    if not alive or not focused or not enabled("DoorsFastInteract") or Library.Toggled or Library.IsPicking
        or UIS:GetFocusedTextBox() or not key:GetState() then finishPrompt() return end
    if activePrompt then return end
    local part, h = root(), hum()
    if not part or not h or h.Health <= 0 then return end
    local best, bestDistance
    for prompt in pairs(prompts) do
        if not prompt:IsDescendantOf(workspace) then prompts[prompt] = nil
        elseif prompt.Enabled and not ignoredPrompt(prompt) and os.clock() >= (promptCooldown[prompt] or 0) then
            local position, target = promptAnchor(prompt)
            if position then
                local distance = (position - part.Position).Magnitude
                if distance <= math.min(Options.DoorsInteractRange.Value, prompt.MaxActivationDistance)
                    and (not bestDistance or distance < bestDistance) then
                    local visible = true
                    if prompt.RequiresLineOfSight then
                        local params = RaycastParams.new()
                        params.FilterType = Enum.RaycastFilterType.Exclude
                        params.FilterDescendantsInstances = {player.Character, highlights}
                        local head = player.Character:FindFirstChild("Head") or part
                        local hit = workspace:Raycast(head.Position, position - head.Position, params)
                        visible = not hit or hit.Instance == target
                            or (prompt.Parent:IsA("Model") and hit.Instance:IsDescendantOf(prompt.Parent))
                    end
                    if visible then best, bestDistance = prompt, distance end
                end
            end
        end
    end
    if not best then return end
    local record = {Prompt = best, Before = best.HoldDuration}
    activePrompt = record
    promptCooldown[best] = os.clock() + 0.8
    local ok = pcall(function()
        best.HoldDuration = 0
        if type(fireproximityprompt) == "function" then fireproximityprompt(best)
        else record.NeedsEnd = true best:InputHoldBegin() end
    end)
    if not ok then finishPrompt() return end
    task.delay(0.03, function() if activePrompt == record then finishPrompt() end end)
end

local extraAlerts = Tabs.Assist:AddLeftGroupbox("Items / floor warnings", "bell-ring")
toggle(extraAlerts, "DoorsItemAlerts", "Item spawn notifications")
toggle(extraAlerts, "DoorsOxygenAlert", "Low oxygen warning")
extraAlerts:AddSlider("DoorsOxygenThreshold", {Text = "Oxygen warning (%)", Default = 25, Min = 5, Max = 75, Rounding = 0})
local oxygenLabel = extraAlerts:AddLabel("Oxygen: disabled")
toggle(extraAlerts, "DoorsHasteAlert", "Haste timer + warning")
extraAlerts:AddSlider("DoorsHasteThreshold", {Text = "Haste warning (seconds)", Default = 20, Min = 5, Max = 60, Rounding = 0})
local hasteLabel = extraAlerts:AddLabel("Haste timer: disabled")
extraAlerts:AddLabel("Reads Character.Oxygen and FloorReplicated.DigitalTimer when available. Missing values are shown as unavailable; no data is invented.", true)
local itemSeen = setmetatable({}, {__mode = "k"})
extraRegister = function(obj, allowAlert)
    if obj:IsA("ProximityPrompt") then prompts[obj] = true end
    if obj:IsA("Atmosphere") then atmospheres[obj] = true end
    local category, label = classify(obj)
    if category == "Loot" and not itemSeen[obj] then
        itemSeen[obj] = true
        if allowAlert and enabled("DoorsItemAlerts") then Library:Notify("Item spawned: " .. label, 4) end
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
                oxygenWarned = true Library:Notify(("Low oxygen: %.1f%%"):format(value), 5)
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
                hasteWarned = true Library:Notify("Haste timer low: " .. value .. " seconds", 5)
            end
        else hasteLabel:SetText("Haste timer: unavailable on this floor") end
    else hasteWarned = false hasteLabel:SetText("Haste timer: disabled") end
end
local fastElapsed, extrasElapsed = 0, 0
connect(RunService.Heartbeat, function(dt)
    fastElapsed += dt extrasElapsed += dt
    if fastElapsed >= 0.1 then fastElapsed = 0 fastInteract() end
    if extrasElapsed < 0.5 then return end
    extrasElapsed = 0
    applyPhysicalProperties() applyFog() applyHidingTransparency() updateExtraAlerts()
    for _, other in ipairs(Players:GetPlayers()) do if other ~= player and other.Character then register(other.Character, false) end end
end)

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
    -- No auto-load: a saved config cannot silently enable gameplay aids.
end
loadedLabel:SetText(("Loaded in: %.2fs"):format(os.clock() - STARTED))
Library:Notify("DOORS " .. VERSION .. " ready. RightControl opens the menu. All feature toggles start OFF.", 6)
return Library
