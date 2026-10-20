--[[
=====================================================================
  HOW TO USE
=====================================================================
  Each feature is a separate block with its OWN window (groupbox):

      ##### [BLOCK: Name] START #####
      ...
      ##### [BLOCK: Name] END #####

  * DELETE a feature  -> delete everything from START to END.
  * MOVE to another tab -> in the block's first line replace
        AddBox(Tabs.Visual, ...)  with  AddBox(Tabs.Main, ...)
  * RENAME a window -> AddBox's second argument (text) and third (icon).
  * NEW feature -> copy any block, change the ID (the first argument
    of AddToggle/AddSlider/...) and the logic. IDs must be unique.
    New blocks can always just be appended at the very bottom of the file --
    there is no block that needs to stay last anymore (the Home tab's
    "Features"/"Loaded In" stats fill themselves in via task.defer, which
    runs after the rest of the script regardless of where in the file the
    Home tab block itself is).

  Windows are automatically distributed between the left and right columns.
  Do not delete or reorder blocks marked [DO NOT TOUCH].
=====================================================================
]]

--##### [BLOCK 0: SETTINGS] START #####------------------------------
local CONFIG = {
    Title      = "ClaudeHub",
    Footer     = "v2.16.1",
    Icon       = 95816097006870,   -- asset id icon or nil
    FolderName = "MyScript",       -- configs and themes folder
    MenuKey    = "RightControl",     -- menu keybind
}
--##### [BLOCK 0: SETTINGS] END #####--------------------------------

local ScriptStartTime = tick() -- for the "Loaded In" stat on the Home tab

--##### [BLOCK 1: LOAD LIBRARIES] START #####  [DO NOT TOUCH]
local repo = "https://raw.githubusercontent.com/joustingmatch/ObsidianUltra/main/"

local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles
--##### [BLOCK 1: LOAD LIBRARIES] END #####


--##### [BLOCK 2: WINDOW AND TABS] START #####
local Window = Library:CreateWindow({
    Title = CONFIG.Title,
    Footer = CONFIG.Footer,
    Icon = CONFIG.Icon,
    NotifyOnError = true,
    Center = true,
    Resizable = true,
    Size = UDim2.fromOffset(1040, 720),
})

-- TABS: add/rename here
local Tabs = {
    Home     = Window:AddTab("Home", "house"),
    Main     = Window:AddTab("Movement", "move"),
    AntiAim  = Window:AddTab("Anti Aim", "shield-off"),
    Visual   = Window:AddTab("Visual", "eye"),
    Players  = Window:AddTab("Players", "users"),
    Servers  = Window:AddTab("Servers", "server"),
    Misc     = Window:AddTab("Misc", "box"),
    Settings = Window:AddTab("UI Settings", "settings"),
}
--##### [BLOCK 2: WINDOW AND TABS] END #####


--##### [BLOCK 3: SHARED FUNCTIONS] START #####  [DO NOT TOUCH]
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local function inputDown(code)
    local environment=getgenv and getgenv() or _G
    local touch=environment.__ClaudeHubTouch
    if touch then
        if code==Enum.KeyCode.W and (touch.Forward or 0)>0 then return true end
        if code==Enum.KeyCode.S and (touch.Back or 0)>0 then return true end
        if code==Enum.KeyCode.A and (touch.Left or 0)>0 then return true end
        if code==Enum.KeyCode.D and (touch.Right or 0)>0 then return true end
        if (code==Enum.KeyCode.E or code==Enum.KeyCode.Space) and (touch.Up or 0)>0 then return true end
        if (code==Enum.KeyCode.Q or code==Enum.KeyCode.LeftControl) and (touch.Down or 0)>0 then return true end
    end
    return UIS:IsKeyDown(code)
end

local Lighting         = game:GetService("Lighting")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Debris           = game:GetService("Debris")
local LocalPlayer      = Players.LocalPlayer
local Mouse            = LocalPlayer:GetMouse()

local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- AddBox(): creates a SEPARATE window in the tab, alternating left/right
local sideCounter = {}
local function AddBox(tab, title, icon)
    sideCounter[tab] = (sideCounter[tab] or 0) + 1
    if sideCounter[tab] % 2 == 1 then
        return tab:AddLeftGroupbox(title, icon)
    else
        return tab:AddRightGroupbox(title, icon)
    end
end

-- connect(): the event disconnects itself automatically on unload
local Connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Connections, c)
    return c
end

-- onCleanup(): code that runs on unload
local CleanupFns = {}
local function onCleanup(fn)
    table.insert(CleanupFns, fn)
end

-- list of other players' names
local function playerNames()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(t, p.Name) end
    end
    return t
end

-- Saved teleport locations ([name] = CFrame), filled in by the TELEPORT
-- WAYPOINTS block. Shared here (instead of being a local inside that block)
-- so other features -- like Auto-Follow -- can also walk to them.
local SharedWaypoints = {}
local function waypointNames()
    local t = {}
    for n in pairs(SharedWaypoints) do table.insert(t, n) end
    table.sort(t)
    return t
end

-- Labels on the Home tab that get their final text filled in by a
-- task.defer() inside the HOME TAB block itself, once every other block in
-- the file has registered its groupboxes (so the "Features" count on Home
-- is accurate). See [BLOCK: HOME TAB] below.
local HomeLabels = {}
-- Inline badges: Ultra initializes new pickers with Toggled=false. Attach
-- without syncing first, then adopt the toggle's real state. This preserves
-- default-ON options and avoids firing their callbacks during construction.
local function addInlineBind(toggle, id, info)
    info.SyncToggleState = false
    info.Modes = {"Toggle", "Hold"}
    toggle:AddKeyPicker(id, info)
    local key = Options[id]
    key.SyncToggleState = true
    key.Toggled = toggle.Value
    key:Update()
    return toggle
end

-- Movement ownership shared by independently removable feature blocks.
local MovementState = { FollowActive = false, WallhopActive = false, ImpulseUntil = 0 }
do
    local tracked, baseline, owned = nil, nil, false
    local function restore()
        if owned and tracked and tracked.Parent then tracked.WalkSpeed = baseline end
        tracked, baseline, owned = nil, nil, false
    end
    connect(RunService.PreSimulation, function()
        local hum = getHum()
        if hum ~= tracked then restore() tracked = hum end
        if not hum then return end
        local sprint = MovementState.GetSprintSpeed and MovementState.GetSprintSpeed()
        local speed = sprint or (Toggles.SpeedToggle and Toggles.SpeedToggle.Value
            and Options.SpeedValue and Options.SpeedValue.Value)
        if speed then
            if not owned then baseline = hum.WalkSpeed end
            owned = true
            hum.WalkSpeed = speed
        elseif owned then
            hum.WalkSpeed = baseline
            owned = false
        end
    end)
    onCleanup(restore)
end

-- Mouse + touch drag helper, with viewport bounds and no per-drag listeners.
-- HUD positions survive hide/show and character respawns (not script reloads).
local HudPositions = {}
local function makeDraggable(object)
    object.Active = true
    local dragging, dragInput, origin, position, absolute
    local entry = {Object = object, Position = object.Position}
    table.insert(HudPositions, entry)
    local function stop() dragging, dragInput = false, nil end
    connect(object.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging, dragInput = true, input
        origin, position, absolute = input.Position, object.Position, object.AbsolutePosition
    end)
    connect(UIS.InputChanged, function(input)
        if not dragging or not object.Parent then return end
        if dragInput.UserInputType == Enum.UserInputType.Touch then
            if input ~= dragInput then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - origin
        local dx, dy = delta.X, delta.Y
        local camera = workspace.CurrentCamera
        if camera then
            local view, size = camera.ViewportSize, object.AbsoluteSize
            dx = math.clamp(absolute.X + dx, 0, math.max(0, view.X - size.X)) - absolute.X
            dy = math.clamp(absolute.Y + dy, 0, math.max(0, view.Y - size.Y)) - absolute.Y
        end
        object.Position = UDim2.new(position.X.Scale, position.X.Offset + dx,
            position.Y.Scale, position.Y.Offset + dy)
    end)
    connect(UIS.InputEnded, function(input)
        if dragging and (input == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1)) then stop() end
    end)
    connect(UIS.WindowFocusReleased, stop)
    entry.Stop = stop
end
local function resetHudPositions()
    for _, entry in ipairs(HudPositions) do
        entry.Stop()
        if entry.Object.Parent then entry.Object.Position = entry.Position end
    end
end

-- Shared by the optional HUD features. Each caller owns its GUI; unload
-- destroys it even if the feature was never switched off manually.
local function createHud(name, width, height, position)
    local gui = Instance.new("ScreenGui")
    gui.Name = "ClaudeHub_" .. name
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 30
    gui.Enabled = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    local label = Instance.new("TextLabel")
    label.Name = "Display"
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = position
    label.Size = UDim2.fromOffset(width, height)
    label.BackgroundColor3 = Color3.fromRGB(18, 16, 25)
    label.BackgroundTransparency = 0.15
    label.BorderSizePixel = 0
    label.TextColor3 = Color3.fromRGB(230, 225, 245)
    label.TextSize = 14
    label.Font = Enum.Font.Code
    label.Text = ""
    label.Parent = gui
    makeDraggable(label)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Color3.fromRGB(100, 70, 170)
    stroke.Transparency = 0.25
    stroke.Parent = label
    onCleanup(function() gui:Destroy() end)
    return gui, label
end
--##### [BLOCK 3: SHARED FUNCTIONS] END #####

--##### [BLOCK: HOME TAB] START #####
-- ObsidianUltra APIs: UpdateWarningBox is a full-width header; tabboxes
-- provide Game / Games / Info without manually patching library internals.
do
    local alive = true
    onCleanup(function() alive = false end)
    local executor, executorVersion = "Unknown", ""
    pcall(function()
        local name, version = identifyexecutor()
        executor, executorVersion = tostring(name or "Unknown"), tostring(version or "")
    end)
    local executionCount, persisted = 1, false
    pcall(function()
        if not (isfile and readfile and writefile) then return end
        local path = CONFIG.FolderName .. "_executions.txt"
        local previous = isfile(path) and tonumber(readfile(path)) or 0
        executionCount = math.max(0, math.floor(previous or 0)) + 1
        writefile(path, tostring(executionCount))
        persisted = true
    end)

    Tabs.Home:UpdateWarningBox({
        Visible = true,
        IsNormal = true,
        LockSize = true,
        Title = "Latest Changelog  |  " .. CONFIG.Title .. " " .. CONFIG.Footer,
        Text = table.concat({
            "+ Manual Fake Wallhop: air + wall + fresh Space press",
            "+ Inline rebindable hotkeys; configurable Click TP combination",
            "= Sprint uses physical key polling and a single speed controller",
            "= No Acceleration yields to Auto-Follow and airborne impulses",
            "+ Mouse/touch dragging for all HUDs, including crosshair",
            "+ UI Settings: Reset HUD Positions; positions survive hide/show",
            "= DOORS module not included",
        }, "\n"),
    })

    local profile = Tabs.Home:AddLeftGroupbox("Profile", "user")
    local avatarView
    local function avatarClone(char)
        local wasArchivable = char.Archivable
        char.Archivable = true
        local ok, clone = pcall(function() return char:Clone() end)
        char.Archivable = wasArchivable
        if not ok or not clone then return nil end
        for _, obj in ipairs(clone:GetDescendants()) do
            if obj:IsA("LuaSourceContainer") or obj:IsA("Sound") or obj:IsA("Tool") then
                obj:Destroy()
            elseif obj:IsA("BasePart") then
                obj.Anchored = true
                obj.CanCollide = false
            end
        end
        clone:PivotTo(CFrame.new())
        return clone
    end
    local char = getChar()
    local preview = char and avatarClone(char)
    if preview then
        local ok, result = pcall(function()
            return profile:AddViewport("HomeAvatarPreview", {
                Object = preview, Clone = false, AutoFocus = true,
                Interactive = true, Height = 190,
            })
        end)
        if ok then avatarView = result else preview:Destroy() end
    end
    if not avatarView then
        profile:AddImage("HomeAvatar", {
            Image = ("rbxthumb://type=Avatar&id=%d&w=420&h=420"):format(LocalPlayer.UserId),
            Height = 190,
        })
    end
    connect(LocalPlayer.CharacterAdded, function(newChar)
        task.delay(1, function()
            if not alive or getChar() ~= newChar or not avatarView then return end
            local clone = avatarClone(newChar)
            if clone then avatarView:SetObject(clone, false) avatarView:Focus() end
        end)
    end)
    profile:AddLabel(LocalPlayer.DisplayName)
    profile:AddLabel("@" .. LocalPlayer.Name .. "   |   " .. tostring(LocalPlayer.UserId))
    profile:AddDivider()
    profile:AddLabel("Executor: " .. executor .. (executorVersion ~= "" and " " .. executorVersion or ""))
    profile:AddLabel("Executions: " .. executionCount .. (persisted and " (saved)" or " (not persisted)"))
    profile:AddLabel(CONFIG.Title .. "  " .. CONFIG.Footer)

    local details = Tabs.Home:AddRightTabbox()
    local gameTab = details:AddTab("Game", "gamepad-2")
    local gamesTab = details:AddTab("Games", "list-checks")
    local infoTab = details:AddTab("Info", "info")
    local gameName = "Loading..."
    local gameLabel = gameTab:AddLabel("Game: " .. gameName)
    gameTab:AddLabel("Place ID: " .. tostring(game.PlaceId))
    local population = gameTab:AddLabel("Players: --")
    gameTab:AddLabel("Mode: universal client utilities")
    gameTab:AddLabel("Compatibility depends on the experience.", true)
    gameTab:AddDivider()
    local function copy(text)
        local ok = pcall(function() setclipboard(text) end)
        Library:Notify(ok and "Copied to clipboard" or "Clipboard unavailable; printed to console", 3)
        if not ok then print(text) end
    end
    gameTab:AddButton({Text = "Copy Server ID", Func = function() copy(game.JobId) end})
    local function refreshPopulation()
        if alive then population:SetText(("Players: %d / %d"):format(#Players:GetPlayers(), Players.MaxPlayers)) end
    end
    refreshPopulation()
    connect(Players.PlayerAdded, function() task.defer(refreshPopulation) end)
    connect(Players.PlayerRemoving, function() task.defer(refreshPopulation) end)
    task.spawn(function()
        local ok, product = pcall(function()
            return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        end)
        if not alive then return end
        gameName = ok and product and product.Name or "Unknown"
        gameLabel:SetText("Game: " .. tostring(gameName))
    end)

    gamesTab:AddLabel("Universal  |  current module")
    gamesTab:AddLabel("General-purpose movement, visuals and utilities.", true)
    gamesTab:AddDivider()
    gamesTab:AddLabel("DOORS  |  not implemented")
    gamesTab:AddLabel("No game-specific support is claimed.", true)

    infoTab:AddLabel("Version: " .. CONFIG.Footer)
    infoTab:AddLabel("Library: ObsidianUltra")
    infoTab:AddLabel("Fork: joustingmatch / ObsidianUltra", true)
    infoTab:AddLabel("Based on Obsidian by deividcomsono", true)
    HomeLabels.LoadedIn = infoTab:AddLabel("Loaded In: ...")
    HomeLabels.Features = infoTab:AddLabel("Feature panels: ...")
    HomeLabels.Controls = infoTab:AddLabel("Controls: ...")
    infoTab:AddDivider()
    infoTab:AddButton({Text = "Copy Debug Info", Func = function()
        copy(table.concat({CONFIG.Title .. " " .. CONFIG.Footer,
            "UI: ObsidianUltra", "Executor: " .. executor .. " " .. executorVersion,
            "Game: " .. tostring(gameName), "Place ID: " .. game.PlaceId,
            "Server ID: " .. game.JobId, HomeLabels.Features.Text, HomeLabels.Controls.Text}, "\n"))
    end})
    infoTab:AddButton({Text = "Copy Library Link", Func = function()
        copy("https://github.com/joustingmatch/ObsidianUltra")
    end})
    local notes = Tabs.Home:AddRightGroupbox("Notes", "notebook-pen")
    notes:AddLabel("New options are OFF by default. Saved autoload configs may enable them.", true)
    notes:AddLabel("Client-only effects do not change server rules or other players' settings.", true)
    notes:AddLabel("RightControl toggles the menu; UI Settings contains themes and configs.", true)

    task.defer(function()
        if not alive then return end
        local panels = 0
        for tab, count in pairs(sideCounter) do
            if tab ~= Tabs.Home and tab ~= Tabs.Settings then panels += count end
        end
        local controls = 0
        for _ in pairs(Toggles) do controls += 1 end
        for _, option in pairs(Options) do
            if option.Type == "Slider" or option.Type == "Dropdown" or option.Type == "Input" then controls += 1 end
        end
        HomeLabels.Features:SetText("Feature panels: " .. panels .. " (not a function count)")
        HomeLabels.Controls:SetText("Controls: " .. controls .. " (includes UI settings)")
        HomeLabels.LoadedIn:SetText(("Loaded In: %.2fs"):format(tick() - ScriptStartTime))
    end)
end
--##### [BLOCK: HOME TAB] END #####


--=====================================================================
--  TAB: MOVEMENT
--=====================================================================

--##### [BLOCK: SPEED] START #####
do
    local Box = AddBox(Tabs.Main, "Speed", "gauge")
    addInlineBind(Box:AddToggle("SpeedToggle", {Text = "Enable", Default = false}), "KeybindSpeed", {Default = "G", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "SpeedToggle"})
    Box:AddSlider("SpeedValue", {Text = "WalkSpeed", Default = 32, Min = 16, Max = 200, Rounding = 0})
    Box:AddLabel("Sprint overrides this speed while its key is held; normal speed returns on release.", true)
end
--##### [BLOCK: SPEED] END #####


--##### [BLOCK: JUMP POWER] START #####
do
    local Box = AddBox(Tabs.Main, "Jump Power", "arrow-up")

    addInlineBind(Box:AddToggle("JumpToggle", { Text = "Enable", Default = false }), "BindJumpToggle", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "JumpToggle"})
    Box:AddSlider("JumpValue", { Text = "JumpPower", Default = 80, Min = 50, Max = 300, Rounding = 0 })

    connect(RunService.Heartbeat, function()
        local hum = getHum()
        if hum and Toggles.JumpToggle.Value then
            hum.UseJumpPower = true
            hum.JumpPower = Options.JumpValue.Value
        end
    end)
end
--##### [BLOCK: JUMP POWER] END #####


--##### [BLOCK: INFINITE JUMP] START #####
do
    local Box = AddBox(Tabs.Main, "Infinite Jump", "chevrons-up")

    addInlineBind(Box:AddToggle("InfJump", { Text = "Enable", Default = false }), "BindInfJump", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "InfJump"})

    connect(UIS.JumpRequest, function()
        if Toggles.InfJump.Value then
            local hum = getHum()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)
end
--##### [BLOCK: INFINITE JUMP] END #####


--##### [BLOCK: NOCLIP] START #####
do
    local Box = AddBox(Tabs.Main, "Noclip", "ghost")

    addInlineBind(Box:AddToggle("Noclip", { Text = "Enable", Default = false }), "KeybindNoclip", {Default = "N", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "Noclip"})

    connect(RunService.Stepped, function()
        if not Toggles.Noclip.Value then return end
        local char = getChar()
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
end
--##### [BLOCK: NOCLIP] END #####


--##### [BLOCK: FLY] START #####
do
    local Box = AddBox(Tabs.Main, "Fly", "plane")
    local bv, bg

    local function stopFly()
        if bv then bv:Destroy() bv = nil end
        if bg then bg:Destroy() bg = nil end
        local hum = getHum()
        if hum then hum.PlatformStand = false end
    end

    addInlineBind(Box:AddToggle("Fly", {
        Text = "Enable",
        Default = false,
        Callback = function(on)
            stopFly()
            local root, hum = getRoot(), getHum()
            if on and root and hum then
                bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                bv.Velocity = Vector3.zero
                bv.Parent = root
                bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                bg.P = 9e4
                bg.Parent = root
                hum.PlatformStand = true
            end
        end,
    }), "KeybindFly", {Default = "F", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "Fly"})
    Box:AddSlider("FlySpeed", { Text = "Fly Speed", Default = 60, Min = 10, Max = 250, Rounding = 0 })
    Box:AddLabel("W/A/S/D, Space - up, Ctrl - down")

    connect(RunService.RenderStepped, function()
        if not (Toggles.Fly.Value and bv and bg) then return end
        local cam = workspace.CurrentCamera
        local dir = Vector3.zero
        if Library.IsMobile==true or (UIS.TouchEnabled and not UIS.KeyboardEnabled) then
            local hum=getHum();if hum then dir=hum.MoveDirection end
        end
        if inputDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
        if inputDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
        if inputDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
        if inputDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
        if inputDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if inputDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
        bv.Velocity = dir.Magnitude > 0 and dir.Unit * Options.FlySpeed.Value or Vector3.zero
        bg.CFrame = cam.CFrame
    end)

    connect(LocalPlayer.CharacterAdded, function()
        if Toggles.Fly.Value then Toggles.Fly:SetValue(false) end
    end)

    onCleanup(stopFly)
end
--##### [BLOCK: FLY] END #####


--##### [BLOCK: GRAVITY] START #####   (NEW)
do
    local Box = AddBox(Tabs.Main, "Gravity", "arrow-down")
    local defaultGravity = workspace.Gravity

    Box:AddSlider("GravityValue", {
        Text = "Gravity",
        Default = defaultGravity, Min = 0, Max = 400, Rounding = 0,
        Callback = function(v) workspace.Gravity = v end,
    })
    Box:AddButton({
        Text = "Reset",
        Func = function() Options.GravityValue:SetValue(defaultGravity) end,
    })

    onCleanup(function() workspace.Gravity = defaultGravity end)
end
--##### [BLOCK: GRAVITY] END #####


--##### [BLOCK: CLICK TELEPORT] START #####
do
    local Box = AddBox(Tabs.Main, "Click Teleport", "mouse-pointer-click")
    addInlineBind(Box:AddToggle("ClickTP", {Text = "Enable", Default = false}), "BindClickTP", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "ClickTP"})
    local function teleport()
        if not Toggles.ClickTP.Value or UIS:GetFocusedTextBox() then return end
        local root = getRoot()
        if root and Mouse.Target and Mouse.Hit then
            root.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0))
        end
    end
    Box:AddButton({Text = "Teleport to cursor", Func = teleport}):AddKeyPicker("ClickTPAction", {
        Default = "MB1", DefaultModifiers = {"LCtrl"}, Mode = "Press", Modes = {"Press"},
        NoUI = true, Text = "Click TP action",
    })
    Box:AddLabel("Default: Ctrl + left click. Click the key badge beside the action to rebind to a key, mouse button or combination. Escape clears it. Close the menu before targeting the world.", true)
end
--##### [BLOCK: CLICK TELEPORT] END #####


--##### [BLOCK: TELEPORT WAYPOINTS] START #####   (NEW)
do
    local Box = AddBox(Tabs.Main, "Teleport Waypoints", "map-pin")
    -- Saved locations live in SharedWaypoints (declared in BLOCK 3) so other
    -- features -- like Auto-Follow -- can also walk to them.

    Box:AddInput("WPName", { Text = "Waypoint Name", Default = "", Placeholder = "e.g.: Base" })
    Box:AddButton({
        Text = "Save Current Position",
        Func = function()
            local root = getRoot()
            local name = Options.WPName.Value
            if not root then return end
            if name == nil or name == "" then
                Library:Notify("Enter a waypoint name", 3)
                return
            end
            SharedWaypoints[name] = root.CFrame
            Options.WPList:SetValues(waypointNames())
            Library:Notify("Waypoint saved: " .. name, 3)
        end,
    })
    Box:AddDropdown("WPList", { Text = "Waypoints", Values = {}, Default = nil, AllowNull = true })
    Box:AddButton({
        Text = "Teleport",
        Func = function()
            local cf = SharedWaypoints[Options.WPList.Value]
            local root = getRoot()
            if cf and root then root.CFrame = cf end
        end,
    })
    Box:AddButton({
        Text = "Delete Selected",
        Func = function()
            local name = Options.WPList.Value
            if name and SharedWaypoints[name] then
                SharedWaypoints[name] = nil
                Options.WPList:SetValues(waypointNames())
            end
        end,
    })
end
--##### [BLOCK: TELEPORT WAYPOINTS] END #####


--##### [BLOCK: SELF-FLING] START #####   (NEW)
-- Affects ONLY your own character. This is a safe alternative to flinging
-- other players, which touches their physics and can be considered griefing.
do
    local Box = AddBox(Tabs.Main, "Self-Fling", "zap")

    Box:AddLabel("Self-Fling (throw yourself up/sideways)")
    Box:AddSlider("SelfFlingPower", {
        Text = "Fling Power",
        Default = 120, Min = 20, Max = 500, Rounding = 0,
    })
    Box:AddButton({
        Text = "Fling Myself",
        Func = function()
            local root, hum = getRoot(), getHum()
            if not root then return end
            if hum then hum:ChangeState(Enum.HumanoidStateType.Freefall) end

            local power = Options.SelfFlingPower.Value
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            bv.Velocity = Vector3.new(
                (math.random() - 0.5) * power,
                power,
                (math.random() - 0.5) * power
            )
            bv.Parent = root
            Debris:AddItem(bv, 0.25)
        end,
    })
end
--##### [BLOCK: SELF-FLING] END #####


--##### [BLOCK: RAGDOLL] START #####   (NEW)
-- Affects ONLY your own character.
do
    local Box = AddBox(Tabs.Main, "Ragdoll", "zap")

    local ragdollJoints = {}

    local function setRagdoll(character, enabled)
        local hum = character:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        if enabled then
            if ragdollJoints[character] then return end
            hum.PlatformStand = true

            local saved = {}
            for _, motor in ipairs(character:GetDescendants()) do
                if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
                    local a0 = Instance.new("Attachment")
                    a0.Name = "RagdollA0"
                    a0.CFrame = motor.C0
                    a0.Parent = motor.Part0

                    local a1 = Instance.new("Attachment")
                    a1.Name = "RagdollA1"
                    a1.CFrame = motor.C1
                    a1.Parent = motor.Part1

                    local socket = Instance.new("BallSocketConstraint")
                    socket.Name = "RagdollSocket"
                    socket.Attachment0 = a0
                    socket.Attachment1 = a1
                    socket.LimitsEnabled = true
                    socket.TwistLimitsEnabled = true
                    socket.Parent = motor.Part0

                    -- IMPORTANT: disable the motor instead of unparenting it.
                    -- Roblox treats a character whose parts have no rigid
                    -- joint connecting them to the HumanoidRootPart as
                    -- "broken" and force-kills/respawns it after a few
                    -- seconds. Keeping the Motor6D in place (just disabled)
                    -- preserves that connection while letting the
                    -- BallSocketConstraint freely drive the joint instead.
                    motor.Enabled = false

                    table.insert(saved, {
                        motor = motor,
                        a0 = a0, a1 = a1, socket = socket,
                    })
                end
            end
            ragdollJoints[character] = saved
        else
            local saved = ragdollJoints[character]
            if saved then
                for _, data in ipairs(saved) do
                    if data.socket then data.socket:Destroy() end
                    if data.a0 then data.a0:Destroy() end
                    if data.a1 then data.a1:Destroy() end
                    if data.motor then data.motor.Enabled = true end
                end
                ragdollJoints[character] = nil
            end
            hum.PlatformStand = false
        end
    end

    Box:AddLabel("Ragdoll (self)")
    addInlineBind(Box:AddToggle("SelfRagdoll", {
        Text = "Enable",
        Default = false,
        Callback = function(on)
            local char = getChar()
            if char then setRagdoll(char, on) end
        end,
    }), "BindSelfRagdoll", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "SelfRagdoll"})

    connect(LocalPlayer.CharacterAdded, function()
        if Toggles.SelfRagdoll.Value then Toggles.SelfRagdoll:SetValue(false) end
    end)

    onCleanup(function()
        local char = getChar()
        if char then setRagdoll(char, false) end
    end)
end
--##### [BLOCK: RAGDOLL] END #####


--##### [BLOCK: LAUNCH PAD] START #####   (NEW)
-- Affects ONLY your own character — the pad is visible and triggers only for you.
do
    local Box = AddBox(Tabs.Main, "Launch Pad", "zap")
    local pad
    local lastLaunch = 0

    Box:AddLabel("Launch Pad (self only)")
    Box:AddSlider("PadPower", {
        Text = "Launch Power",
        Default = 150, Min = 20, Max = 500, Rounding = 0,
    })
    addInlineBind(Box:AddToggle("PadEnabled", { Text = "Active", Default = true }), "BindPadEnabled", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "PadEnabled"})
    Box:AddButton({
        Text = "Place Pad At Feet",
        Func = function()
            local root = getRoot()
            if not root then return end

            if pad then pad:Destroy() end
            pad = Instance.new("Part")
            pad.Name = "SelfLaunchPad"
            pad.Anchored = true
            pad.CanCollide = true
            pad.Size = Vector3.new(6, 1, 6)
            pad.Material = Enum.Material.Neon
            pad.Color = Color3.fromRGB(0, 170, 255)
            pad.CFrame = CFrame.new(root.Position - Vector3.new(0, 3, 0))
            pad.Parent = workspace

            connect(pad.Touched, function(hit)
                if not Toggles.PadEnabled.Value then return end
                local char = getChar()
                if not (char and hit:IsDescendantOf(char)) then return end
                if tick() - lastLaunch < 0.5 then return end
                lastLaunch = tick()

                local r, hum = getRoot(), getHum()
                if r and hum then
                    hum:ChangeState(Enum.HumanoidStateType.Freefall)
                    r.AssemblyLinearVelocity = Vector3.new(
                        r.AssemblyLinearVelocity.X,
                        Options.PadPower.Value,
                        r.AssemblyLinearVelocity.Z
                    )
                end
            end)
        end,
    })
    Box:AddButton({
        Text = "Remove Pad",
        Func = function()
            if pad then pad:Destroy() pad = nil end
        end,
    })
    Box:AddLabel("The pad is visible and triggers only for you (client-side object) — it does not affect other players.", true)

    onCleanup(function()
        if pad then pad:Destroy() pad = nil end
    end)
end
--##### [BLOCK: LAUNCH PAD] END #####


--##### [BLOCK: ANTI-FLING] START #####   (NEW)
do
    local Box = AddBox(Tabs.Main, "Anti-Fling", "shield")
    local NOCOLLIDE_METHOD = "Disable Hitbox (don't touch other players)"

    addInlineBind(Box:AddToggle("AntiFling", { Text = "Enable", Default = false }), "BindAntiFling", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AntiFling"})
    Box:AddDropdown("AntiFlingMethod", {
        Text = "Method",
        Values = { "Velocity Clamp", "Increase Mass", NOCOLLIDE_METHOD },
        Default = 1,
    })
    Box:AddSlider("AntiFlingVelocity", {
        Text = "Max Velocity",
        Default = 100, Min = 20, Max = 300, Rounding = 0,
        Suffix = " studs/s",
    })
    Box:AddLabel("Protects your character from sudden throws caused by other players' physics (e.g. colliding with another player). Does not affect other players.", true)

    -- METHOD 1: hard-clamp the root part's velocity every frame -----------
    -- METHOD 2: temporarily make the character's parts very "heavy" -------
    local heavyParts = {}

    local function clearHeavy()
        for part, props in pairs(heavyParts) do
            if part and part.Parent then
                part.CustomPhysicalProperties = props
            end
        end
        heavyParts = {}
    end

    local function applyHeavy(character)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and not heavyParts[part] then
                heavyParts[part] = part.CustomPhysicalProperties
                part.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.3, 100, 1)
            end
        end
    end

    -- METHOD 3: force CanCollide = false on every part of every OTHER
    -- player's character, every frame. This never touches your own parts
    -- or the map, so you keep standing on the ground normally — you just
    -- walk straight through other players. This is the most reliable
    -- method: it needs no special permissions (unlike PhysicsService
    -- collision groups, which some executors/games block or reset). ------
    local savedCollide = {}

    local function disableCollision(character)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if savedCollide[part] == nil then
                    savedCollide[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end
    end

    local function restoreCollision(character)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and savedCollide[part] ~= nil then
                part.CanCollide = savedCollide[part]
                savedCollide[part] = nil
            end
        end
    end

    local function restoreAllCollide()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then restoreCollision(plr.Character) end
        end
    end

    local function noCollideActive()
        return Toggles.AntiFling.Value and Options.AntiFlingMethod.Value == NOCOLLIDE_METHOD
    end

    -- Re-applied every frame on purpose: this also catches newly added
    -- limbs/accessories/tools and undoes any CanCollide reset the game
    -- itself might do.
    connect(RunService.Heartbeat, function()
        if not noCollideActive() then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                disableCollision(plr.Character)
            end
        end
    end)

    Toggles.AntiFling:OnChanged(function()
        if not noCollideActive() then restoreAllCollide() end
    end)
    Options.AntiFlingMethod:OnChanged(function()
        if not noCollideActive() then restoreAllCollide() end
        if next(heavyParts) and Options.AntiFlingMethod.Value ~= "Increase Mass" then
            clearHeavy()
        end
    end)

    -- Looped logic only for methods 1 and 2 (method 3 has its own loop above) --
    connect(RunService.Heartbeat, function()
        if not Toggles.AntiFling.Value or Options.AntiFlingMethod.Value == NOCOLLIDE_METHOD then
            if next(heavyParts) then clearHeavy() end
            return
        end

        local root = getRoot()
        if not root then return end

        if Options.AntiFlingMethod.Value == "Increase Mass" then
            local char = getChar()
            if char then applyHeavy(char) end
        else
            if next(heavyParts) then clearHeavy() end

            local maxV = Options.AntiFlingVelocity.Value
            local vel = root.AssemblyLinearVelocity
            local horizontal = Vector3.new(vel.X, 0, vel.Z)
            local newVel = vel

            if horizontal.Magnitude > maxV then
                local clamped = horizontal.Unit * maxV
                newVel = Vector3.new(clamped.X, newVel.Y, clamped.Z)
            end
            if math.abs(newVel.Y) > maxV then
                newVel = Vector3.new(newVel.X, math.clamp(newVel.Y, -maxV, maxV), newVel.Z)
            end
            if newVel ~= vel then
                root.AssemblyLinearVelocity = newVel
            end
        end
    end)

    connect(LocalPlayer.CharacterAdded, function()
        heavyParts = {}
    end)

    onCleanup(function()
        clearHeavy()
        restoreAllCollide()
    end)
end
--##### [BLOCK: ANTI-FLING] END #####

--##### [BLOCK: ANTI AIM] START #####   (NEW)
-- Overrides how your character's model is VISUALLY rotated for everyone
-- else in the server, while your own camera and controls stay completely
-- normal. This is a defensive trick (the same idea as "anti-aim" in other
-- games): other players -- and any aim-prediction that reads your facing
-- direction -- see you facing somewhere other than where you're actually
-- moving, making you a harder target. It only changes your own character's
-- rotation; it never touches or affects any other player.
do
    local Box = AddBox(Tabs.AntiAim, "Anti Aim", "shield-off")

    addInlineBind(Box:AddToggle("AntiAim", { Text = "Enable", Default = false }), "BindAntiAim", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AntiAim"})
    Box:AddDropdown("AntiAimMode", {
        Text = "Mode",
        Values = { "Static Backward", "Jitter (Random)", "Spin" },
        Default = 1,
    })
    Box:AddSlider("AntiAimJitterInterval", {
        Text = "Jitter Interval",
        Default = 0.15, Min = 0.05, Max = 1, Rounding = 2,
        Suffix = "s",
    })
    Box:AddSlider("AntiAimSpinSpeed", {
        Text = "Spin Speed",
        Default = 360, Min = 30, Max = 1080, Rounding = 0,
        Suffix = " deg/s",
    })
    Box:AddLabel("Static Backward: always faces the opposite way from your camera. Jitter: snaps to a random direction every interval. Spin: rotates continuously. Your own view/movement are unaffected -- only how others see your character face is changed.", true)

    local savedAutoRotate = nil
    local spinYaw, jitterYaw, lastJitterTime = 0, 0, 0

    local function setAutoRotate(on)
        local hum = getHum()
        if not hum then return end
        if savedAutoRotate == nil then savedAutoRotate = hum.AutoRotate end
        hum.AutoRotate = on
    end

    local function restoreAutoRotate()
        local hum = getHum()
        if hum and savedAutoRotate ~= nil then
            hum.AutoRotate = savedAutoRotate
        end
        savedAutoRotate = nil
    end

    connect(RunService.Heartbeat, function(dt)
        if MovementState.WallhopActive then return end
        if not Toggles.AntiAim.Value then
            if savedAutoRotate ~= nil then restoreAutoRotate() end
            return
        end

        local root, hum = getRoot(), getHum()
        if not (root and hum) then return end

        setAutoRotate(false)

        local mode = Options.AntiAimMode.Value

        if mode == "Static Backward" then
            -- CFrame.new(origin, target) builds a CFrame whose LookVector (front)
            -- points from origin straight at target. By pointing it at a spot in
            -- the "flipped" direction (opposite of the camera's flattened look
            -- direction), the character's front ends up facing that opposite
            -- direction too -- reliably, with no sign-convention guesswork.
            local camera = workspace.CurrentCamera
            local look = camera and camera.CFrame.LookVector or root.CFrame.LookVector
            local flipped = -Vector3.new(look.X, 0, look.Z)
            if flipped.Magnitude > 0.01 then
                root.CFrame = CFrame.new(root.Position, root.Position + flipped)
            end
        elseif mode == "Jitter (Random)" then
            if tick() - lastJitterTime > Options.AntiAimJitterInterval.Value then
                jitterYaw = math.random() * math.pi * 2
                lastJitterTime = tick()
            end
            root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, jitterYaw, 0)
        elseif mode == "Spin" then
            spinYaw += math.rad(Options.AntiAimSpinSpeed.Value) * dt
            root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, spinYaw, 0)
        end
    end)

    connect(LocalPlayer.CharacterAdded, function()
        savedAutoRotate = nil
    end)

    onCleanup(function()
        -- Release nested wallhop ownership first, then restore AntiAim's
        -- original AutoRotate value (cleanup callbacks run in registration order).
        if MovementState.FinishWallhop then MovementState.FinishWallhop() end
        restoreAutoRotate()
    end)
end
--##### [BLOCK: ANTI AIM] END #####





--##### [BLOCK: ANTI-VOID] START #####   (NEW)
do
    local Box = AddBox(Tabs.Main, "Anti-Void", "life-buoy")

    addInlineBind(Box:AddToggle("AntiVoid", { Text = "Enable", Default = false }), "BindAntiVoid", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AntiVoid"})
    Box:AddSlider("AntiVoidHeight", {
        Text = "Void Y Threshold",
        Default = -50, Min = -500, Max = 0, Rounding = 0,
    })
    Box:AddLabel("Teleports you back to your last safe position if you fall below the threshold height.", true)

    local lastSafe

    connect(RunService.Heartbeat, function()
        local root = getRoot()
        local hum = getHum()
        if not root then return end

        -- Only remember a position as "safe" while actually standing on solid ground
        -- (not merely above the void threshold — this also catches mid-air/falling spots).
        if hum and hum.FloorMaterial ~= Enum.Material.Air then
            lastSafe = root.CFrame
        end

        if Toggles.AntiVoid.Value and lastSafe and root.Position.Y <= Options.AntiVoidHeight.Value then
            root.CFrame = lastSafe
            if hum then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
        end
    end)

    connect(LocalPlayer.CharacterAdded, function()
        lastSafe = nil
    end)
end
--##### [BLOCK: ANTI-VOID] END #####


--=====================================================================
--  TAB: VISUAL
--=====================================================================

--##### [BLOCK: ESP] START #####
do
    local Box = AddBox(Tabs.Visual, "ESP", "eye")

    Box:AddSlider("ESPMaxDistance", {
        Text = "Max Distance",
        Default = 500, Min = 50, Max = 2000, Rounding = 0,
        Suffix = " studs",
    })
    addInlineBind(Box:AddToggle("ESPNames", {
        Text = "Show Name and Distance",
        Default = true,
    }), "BindESPNames", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "ESPNames"})
    Box:AddDivider()

    local function inRange(char)
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local myRoot = getRoot()
        if not (root and myRoot) then return false end
        return (root.Position - myRoot.Position).Magnitude <= Options.ESPMaxDistance.Value
    end

    -- ESP: model highlight + name/distance ---------------------------------
    local espObjects, nameTags = {}, {}

    local function clearESP()
        for plr, h in pairs(espObjects) do h:Destroy() espObjects[plr] = nil end
        for plr, tag in pairs(nameTags) do tag:Destroy() nameTags[plr] = nil end
    end

    local function applyESP(plr, char)
        if espObjects[plr] then espObjects[plr]:Destroy() end
        local h = Instance.new("Highlight")
        h.FillColor = Options.ESPColor.Value
        h.OutlineColor = Color3.new(1, 1, 1)
        h.FillTransparency = 0.5
        h.DepthMode = Toggles.ESPChams.Value and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        h.Adornee = char
        h.Parent = char
        espObjects[plr] = h

        if nameTags[plr] then nameTags[plr]:Destroy() nameTags[plr] = nil end
        local head = char:FindFirstChild("Head")
        if head then
            local gui = Instance.new("BillboardGui")
            gui.Name = "ESPNameTag"
            gui.Size = UDim2.new(0, 160, 0, 36)
            gui.StudsOffset = Vector3.new(0, 2.2, 0)
            gui.AlwaysOnTop = true
            gui.Adornee = head

            local label = Instance.new("TextLabel")
            label.Name = "Label"
            label.BackgroundTransparency = 1
            label.Size = UDim2.fromScale(1, 1)
            label.Font = Enum.Font.GothamBold
            label.TextSize = 14
            label.TextColor3 = Color3.new(1, 1, 1)
            label.TextStrokeTransparency = 0
            label.Text = plr.Name
            label.Parent = gui

            gui.Parent = head
            nameTags[plr] = gui
        end
    end

    local hookedESP = {}
    local function addESP(plr)
        if plr == LocalPlayer then return end
        if plr.Character then applyESP(plr, plr.Character) end
        if not hookedESP[plr] then
            hookedESP[plr] = true
            connect(plr.CharacterAdded, function(char)
                if Toggles.ESP.Value then applyESP(plr, char) end
            end)
        end
    end

    Box:AddLabel("ESP (model highlight)")
    addInlineBind(Box:AddToggle("ESP", {
        Text = "Enable",
        Default = false,
        Callback = function(on)
            if on then
                for _, plr in ipairs(Players:GetPlayers()) do addESP(plr) end
            else
                clearESP()
            end
        end,
    }), "KeybindESP", {Default = "J", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "ESP"}):AddColorPicker("ESPColor", {
        Default = Color3.fromRGB(255, 60, 60),
        Title = "ESP Color",
        Callback = function(color)
            for _, h in pairs(espObjects) do h.FillColor = color end
        end,
    })
    addInlineBind(Box:AddToggle("ESPChams", {
        Text = "See Through Walls (Chams)",
        Default = true,
        Callback = function(on)
            for _, h in pairs(espObjects) do
                h.DepthMode = on and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            end
        end,
    }), "BindESPChams", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "ESPChams"})

    connect(Players.PlayerAdded, function(plr)
        if Toggles.ESP.Value then addESP(plr) end
    end)
    connect(Players.PlayerRemoving, function(plr)
        if espObjects[plr] then espObjects[plr]:Destroy() espObjects[plr] = nil end
        if nameTags[plr] then nameTags[plr]:Destroy() nameTags[plr] = nil end
    end)

    connect(RunService.Heartbeat, function()
        for plr, h in pairs(espObjects) do
            local char = plr.Character
            local visible = char and inRange(char) or false
            h.Enabled = visible

            local tag = nameTags[plr]
            if tag then
                tag.Enabled = Toggles.ESPNames.Value and visible
                if visible then
                    local root = char:FindFirstChild("HumanoidRootPart")
                    local myRoot = getRoot()
                    local label = tag:FindFirstChild("Label")
                    if root and myRoot and label then
                        local dist = math.floor((root.Position - myRoot.Position).Magnitude)
                        label.Text = plr.Name .. " [" .. dist .. "m]"
                    end
                end
            end
        end
    end)

    -- TRACERS: lines from the screen to each player, merged into this same
    -- ESP groupbox (shares the Max Distance slider above) rather than its
    -- own separate groupbox. -------------------------------------------
    local hasDrawing = Drawing ~= nil
    local tracerLines = {}

    local function clearTracers()
        for plr, line in pairs(tracerLines) do
            pcall(function() line:Remove() end)
            tracerLines[plr] = nil
        end
    end

    local function ensureTracer(plr)
        if tracerLines[plr] then return tracerLines[plr] end
        local line = Drawing.new("Line")
        line.Thickness = 1
        line.Color = Options.TracerColor.Value
        line.Transparency = 1
        line.Visible = false
        tracerLines[plr] = line
        return line
    end

    Box:AddDivider()
    Box:AddLabel("Tracers (lines)")
    addInlineBind(Box:AddToggle("Tracers", {
        Text = "Enable",
        Default = false,
        Disabled = not hasDrawing,
        DisabledTooltip = "Your executor does not support the Drawing API",
    }), "BindTracers", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "Tracers"}):AddColorPicker("TracerColor", {
        Default = Color3.fromRGB(0, 255, 120),
        Title = "Line Color",
        Callback = function(color)
            for _, line in pairs(tracerLines) do line.Color = color end
        end,
    })
    Box:AddDropdown("TracerOrigin", {
        Text = "Draw From",
        Values = { "Bottom of Screen", "Cursor" },
        Default = 1,
    })

    if hasDrawing then
        connect(RunService.RenderStepped, function()
            if not Toggles.Tracers.Value then
                for _, line in pairs(tracerLines) do line.Visible = false end
                return
            end

            local cam = workspace.CurrentCamera
            local originPoint
            if Options.TracerOrigin.Value == "Cursor" then
                originPoint = UIS:GetMouseLocation()
            else
                local vp = cam.ViewportSize
                originPoint = Vector2.new(vp.X / 2, vp.Y)
            end

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local line = ensureTracer(plr)
                    if hrp and char and inRange(char) then
                        local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                        line.Visible = onScreen
                        if onScreen then
                            line.From = originPoint
                            line.To = Vector2.new(pos.X, pos.Y)
                        end
                    else
                        line.Visible = false
                    end
                end
            end
        end)

        connect(Players.PlayerRemoving, function(plr)
            if tracerLines[plr] then
                pcall(function() tracerLines[plr]:Remove() end)
                tracerLines[plr] = nil
            end
        end)
    end

    onCleanup(function()
        clearESP()
        clearTracers()
    end)
end
--##### [BLOCK: ESP] END #####


--##### [BLOCK: HITBOXES] START #####
do
    local Box = AddBox(Tabs.Visual, "Hitboxes", "square")

    Box:AddSlider("HitboxMaxDistance", {
        Text = "Max Distance",
        Default = 500, Min = 50, Max = 2000, Rounding = 0,
        Suffix = " studs",
    })
    Box:AddDivider()

    local function inRange(char)
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local myRoot = getRoot()
        if not (root and myRoot) then return false end
        return (root.Position - myRoot.Position).Magnitude <= Options.HitboxMaxDistance.Value
    end

    -- HITBOXES: HumanoidRootPart bounding box ------------------------------
    local boxes = {}

    local function clearBoxes()
        for plr, b in pairs(boxes) do b:Destroy() boxes[plr] = nil end
    end

    local function applyBox(plr, char)
        if boxes[plr] then boxes[plr]:Destroy() end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local b = Instance.new("BoxHandleAdornment")
        b.Adornee = root
        b.AlwaysOnTop = true
        b.ZIndex = 1
        b.Size = Vector3.new(4, 5, 2) -- approximate character hitbox size
        b.Transparency = 0.6
        b.Color3 = Options.HitboxColor.Value
        b.Parent = root
        boxes[plr] = b
    end

    local hookedBoxes = {}
    local function addBox(plr)
        if plr == LocalPlayer then return end
        if plr.Character then applyBox(plr, plr.Character) end
        if not hookedBoxes[plr] then
            hookedBoxes[plr] = true
            connect(plr.CharacterAdded, function(char)
                if Toggles.Hitboxes.Value then applyBox(plr, char) end
            end)
        end
    end

    Box:AddLabel("Hitboxes (HumanoidRootPart size)")
    addInlineBind(Box:AddToggle("Hitboxes", {
        Text = "Enable",
        Default = false,
        Callback = function(on)
            if on then
                for _, plr in ipairs(Players:GetPlayers()) do addBox(plr) end
            else
                clearBoxes()
            end
        end,
    }), "BindHitboxes", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "Hitboxes"}):AddColorPicker("HitboxColor", {
        Default = Color3.fromRGB(255, 200, 0),
        Title = "Hitbox Color",
        Callback = function(color)
            for _, b in pairs(boxes) do b.Color3 = color end
        end,
    })

    connect(Players.PlayerAdded, function(plr)
        if Toggles.Hitboxes.Value then addBox(plr) end
    end)
    connect(Players.PlayerRemoving, function(plr)
        if boxes[plr] then boxes[plr]:Destroy() boxes[plr] = nil end
    end)

    connect(RunService.Heartbeat, function()
        for plr, box in pairs(boxes) do
            local char = plr.Character
            box.Visible = char and inRange(char) or false
        end
    end)

    onCleanup(clearBoxes)
end
--##### [BLOCK: HITBOXES] END #####


--##### [BLOCK: FULLBRIGHT] START #####
do
    local Box = AddBox(Tabs.Visual, "Fullbright", "sun")

    local orig = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
        Ambient = Lighting.Ambient,
    }
    local function restore()
        for k, v in pairs(orig) do Lighting[k] = v end
    end

    addInlineBind(Box:AddToggle("Fullbright", {
        Text = "Enable",
        Default = false,
        Callback = function(on)
            if on then
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
                Lighting.FogEnd = 1e6
                Lighting.GlobalShadows = false
                Lighting.Ambient = Color3.new(1, 1, 1)
            else
                restore()
            end
        end,
    }), "BindFullbright", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "Fullbright"})

    onCleanup(restore)
end
--##### [BLOCK: FULLBRIGHT] END #####


--##### [BLOCK: FOV] START #####
do
    local Box = AddBox(Tabs.Visual, "Field of View (FOV)", "scan")
    local defaultFov = workspace.CurrentCamera.FieldOfView

    Box:AddSlider("FOV", {
        Text = "FOV",
        Default = defaultFov, Min = 40, Max = 120, Rounding = 0,
        Callback = function(v) workspace.CurrentCamera.FieldOfView = v end,
    })

    onCleanup(function() workspace.CurrentCamera.FieldOfView = defaultFov end)
end
--##### [BLOCK: FOV] END #####


--##### [BLOCK: TIME OF DAY] START #####   (NEW)
do
    local Box = AddBox(Tabs.Visual, "Time of Day", "clock")
    local defaultTime = Lighting.ClockTime

    Box:AddSlider("ClockTimeValue", {
        Text = "Hour (0-24)",
        Default = math.floor(defaultTime), Min = 0, Max = 24, Rounding = 1,
        Callback = function(v) Lighting.ClockTime = v end,
    })

    onCleanup(function() Lighting.ClockTime = defaultTime end)
end
--##### [BLOCK: TIME OF DAY] END #####


--##### [BLOCK: CAMERA DISTANCE] START #####   (NEW)
do
    local Box = AddBox(Tabs.Visual, "Camera Distance", "camera")
    local defaultZoom = LocalPlayer.CameraMaxZoomDistance

    Box:AddSlider("ZoomValue", {
        Text = "Max Zoom Out",
        Default = math.clamp(defaultZoom, 10, 1000), Min = 10, Max = 1000, Rounding = 0,
        Callback = function(v) LocalPlayer.CameraMaxZoomDistance = v end,
    })

    onCleanup(function() LocalPlayer.CameraMaxZoomDistance = defaultZoom end)
end
--##### [BLOCK: CAMERA DISTANCE] END #####


--##### [BLOCK: PERFORMANCE MODE] START #####   (NEW)
do
    local Box = AddBox(Tabs.Visual, "Performance Mode", "zap-off")

    addInlineBind(Box:AddToggle("LowGraphics", { Text = "Enable", Default = false }), "BindLowGraphics", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "LowGraphics"})
    Box:AddLabel("Disables particles, trails, beams and shadows to improve FPS.", true)

    local savedShadows
    local hidden = {}
    local FX_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Smoke", "Fire", "Sparkles" }

    local function isFX(obj)
        for _, class in ipairs(FX_CLASSES) do
            if obj:IsA(class) then return true end
        end
        return false
    end

    local function hideFX(obj)
        if isFX(obj) and obj.Enabled ~= false then
            hidden[obj] = true
            obj.Enabled = false
        end
    end

    local function applyLowGraphics()
        savedShadows = Lighting.GlobalShadows
        Lighting.GlobalShadows = false
        for _, obj in ipairs(workspace:GetDescendants()) do
            hideFX(obj)
        end
    end

    local function restoreGraphics()
        if savedShadows ~= nil then
            Lighting.GlobalShadows = savedShadows
        end
        for obj in pairs(hidden) do
            if obj and obj.Parent then obj.Enabled = true end
        end
        hidden = {}
    end

    connect(workspace.DescendantAdded, function(obj)
        if Toggles.LowGraphics.Value then hideFX(obj) end
    end)

    Toggles.LowGraphics:OnChanged(function(on)
        if on then applyLowGraphics() else restoreGraphics() end
    end)

    onCleanup(restoreGraphics)
end
--##### [BLOCK: PERFORMANCE MODE] END #####


--##### [BLOCK: HIDE PLAYERS] START #####   (NEW)
do
    local Box = AddBox(Tabs.Visual, "Hide Players", "eye-off")

    addInlineBind(Box:AddToggle("HidePlayers", { Text = "Enable", Default = false }), "BindHidePlayers", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "HidePlayers"})
    Box:AddLabel("Hides other players' models to improve FPS. Does not affect collision, ESP or hitboxes.", true)

    local function setHidden(character, hide)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") or part:IsA("Decal") then
                part.LocalTransparencyModifier = hide and 1 or 0
            end
        end
    end

    local hookedHide = {}
    local function hookPlayer(plr)
        if hookedHide[plr] then return end
        hookedHide[plr] = true
        connect(plr.CharacterAdded, function(char)
            if Toggles.HidePlayers.Value then setHidden(char, true) end
        end)
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then hookPlayer(plr) end
    end
    connect(Players.PlayerAdded, function(plr)
        if plr ~= LocalPlayer then hookPlayer(plr) end
    end)

    -- Re-applied every frame because the default character scripts reset
    -- LocalTransparencyModifier on their own (e.g. camera-too-close fade).
    connect(RunService.Heartbeat, function()
        if not Toggles.HidePlayers.Value then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                setHidden(plr.Character, true)
            end
        end
    end)

    Toggles.HidePlayers:OnChanged(function(on)
        if not on then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    setHidden(plr.Character, false)
                end
            end
        end
    end)

    onCleanup(function()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                setHidden(plr.Character, false)
            end
        end
    end)
end
--##### [BLOCK: HIDE PLAYERS] END #####


--##### [BLOCK: FPS / PING WIDGET] START #####   (NEW)
do
    local Box = AddBox(Tabs.Visual, "FPS / Ping Counter", "activity")

    addInlineBind(Box:AddToggle("StatsWidget", { Text = "Enable", Default = false }), "BindStatsWidget", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "StatsWidget"})

    local gui, label
    local frameCount, lastClock, fps = 0, os.clock(), 0

    local function createWidget()
        if gui then gui.Enabled = true return end
        gui = Instance.new("ScreenGui")
        gui.Name = "StatsWidget"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

        label = Instance.new("TextLabel")
        label.Size = UDim2.new(0, 160, 0, 32)
        label.AnchorPoint = Vector2.new(0.5, 0)
        label.Position = UDim2.new(0.5, 0, 0, 8) -- starts top-center
        label.BackgroundColor3 = Color3.new(0, 0, 0)
        label.BackgroundTransparency = 0.4
        label.BorderSizePixel = 0
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.Text = "FPS: -- | Ping: -- ms"
        label.Active = true
        label.Parent = gui

        makeDraggable(label)
    end

    local function destroyWidget()
        if gui then gui:Destroy() end
        gui, label = nil, nil
    end

    connect(RunService.RenderStepped, function()
        frameCount += 1
        local now = os.clock()
        if now - lastClock >= 1 then
            fps = frameCount
            frameCount = 0
            lastClock = now
        end
        if gui and gui.Enabled and label then
            local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
            label.Text = string.format("FPS: %d | Ping: %d ms", fps, ping)
        end
    end)

    Toggles.StatsWidget:OnChanged(function(on)
        if on then createWidget() elseif gui then gui.Enabled = false end
    end)

    onCleanup(destroyWidget)
end
--##### [BLOCK: FPS / PING WIDGET] END #####


--=====================================================================
--  TAB: PLAYERS
--=====================================================================

--##### [BLOCK: TELEPORT TO PLAYER] START #####
do
    local Box = AddBox(Tabs.Players, "Teleport To Player", "send")

    Box:AddDropdown("TPTarget", { Text = "Player", Values = playerNames(), Default = nil, AllowNull = true })
    Box:AddButton({
        Text = "Refresh List",
        Func = function() Options.TPTarget:SetValues(playerNames()) end,
    })
    Box:AddButton({
        Text = "Teleport",
        Func = function()
            local name = Options.TPTarget.Value
            local target = name and Players:FindFirstChild(name)
            local tr = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            local root = getRoot()
            if tr and root then
                root.CFrame = tr.CFrame * CFrame.new(0, 0, 3)
            else
                Library:Notify("Player not found", 3)
            end
        end,
    })
end
--##### [BLOCK: TELEPORT TO PLAYER] END #####


--##### [BLOCK: SPECTATE PLAYER] START #####   (NEW)
do
    local Box = AddBox(Tabs.Players, "Spectate Player", "video")

    local function stopSpectate()
        local hum = getHum()
        if hum then workspace.CurrentCamera.CameraSubject = hum end
    end

    Box:AddDropdown("SpecTarget", { Text = "Player", Values = playerNames(), Default = nil, AllowNull = true })
    Box:AddButton({
        Text = "Refresh List",
        Func = function() Options.SpecTarget:SetValues(playerNames()) end,
    })
    addInlineBind(Box:AddToggle("Spectate", {
        Text = "Spectate",
        Default = false,
        Callback = function(on)
            if not on then stopSpectate() return end
            local name = Options.SpecTarget.Value
            local target = name and Players:FindFirstChild(name)
            local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                workspace.CurrentCamera.CameraSubject = hum
            else
                Library:Notify("Player not found", 3)
                Toggles.Spectate:SetValue(false)
            end
        end,
    }), "BindSpectate", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "Spectate"})

    onCleanup(stopSpectate)
end
--##### [BLOCK: SPECTATE PLAYER] END #####


--##### [BLOCK: AUTO-FOLLOW] START #####   (NEW)
-- Obstacle handling, iteration 4. The "am I stuck?" check now looks at full
-- 3D displacement instead of just horizontal speed -- climbing a staircase
-- moves you mostly upward with little horizontal speed, so a horizontal-only
-- check wrongly thought that was "stuck" and jumped for no reason. That's
-- fixed now: real progress in ANY direction (including up a staircase)
-- counts as "not stuck", so stairs are left alone.
--
-- Real blockages (walls, gaps between platforms) now go through three
-- escalating phases instead of just hopping in place forever:
--   1. a normal jump in place -- clears curbs, crates, low lips.
--   2. if that's not enough (wall too tall / gap too wide to just hop over),
--      a running-jump style velocity boost -- same technique as the Launch
--      Pad feature -- carries the character up and across.
--   3. if even that fails, back up briefly and recompute the route instead
--      of retrying the same blocked move forever.
-- Status notifications show which phase it's in, so problems are visible
-- instead of being a silent black box.
--
-- Movement itself still uses Roblox's standard Humanoid:MoveTo() +
-- MoveToFinished pattern (smooth native walking on both R6 and R15), with a
-- watchdog that resumes the bot if your own movement input interrupts it.
--
-- "Target Type" lets this walk to either a live player OR one of the saved
-- locations from the Teleport Waypoints feature (shared via SharedWaypoints
-- in BLOCK 3) -- same pathfinding/obstacle handling either way, just a
-- different source for the destination position.
do
    local Box = AddBox(Tabs.Players, "Auto-Follow", "navigation")
    local PathfindingService = game:GetService("PathfindingService")

    Box:AddDropdown("FollowTargetType", {
        Text = "Target Type",
        Values = { "Player", "Saved Waypoint" },
        Default = 1,
    })
    Box:AddDropdown("FollowTarget", { Text = "Player", Values = playerNames(), Default = nil, AllowNull = true })
    Box:AddDropdown("FollowWaypoint", {
        Text = "Waypoint",
        Values = waypointNames(),
        Default = nil, AllowNull = true,
    })
    Box:AddButton({
        Text = "Refresh List",
        Func = function()
            Options.FollowTarget:SetValues(playerNames())
            Options.FollowWaypoint:SetValues(waypointNames())
        end,
    })
    addInlineBind(Box:AddToggle("AutoFollow", { Text = "Enable", Default = false }), "BindAutoFollow", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AutoFollow"})
    Box:AddSlider("FollowDistance", {
        Text = "Stop Distance",
        Default = 5, Min = 2, Max = 30, Rounding = 0,
    })
    Box:AddDivider()
    addInlineBind(Box:AddToggle("AutoJumpObstacles", {
        Text = "Get Past Obstacles When Blocked",
        Default = true,
    }), "BindAutoJumpObstacles", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AutoJumpObstacles"})
    Box:AddSlider("VaultPower", {
        Text = "Vault Boost Power (Walls / Gaps)",
        Default = 90, Min = 30, Max = 250, Rounding = 0,
    })
    addInlineBind(Box:AddToggle("FollowDebugNotify", {
        Text = "Show Status Notifications",
        Default = true,
    }), "BindFollowDebugNotify", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "FollowDebugNotify"})
    Box:AddLabel("If blocked: tries a normal jump first, then a running-jump boost over bigger walls/gaps, then backs up and recalculates the route as a last resort. Stairs are detected correctly and left alone.", true)
    Box:AddDivider()
    addInlineBind(Box:AddToggle("ShowFollowPath", {
        Text = "Show Path Line",
        Default = true,
    }), "BindShowFollowPath", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "ShowFollowPath"}):AddColorPicker("FollowPathColor", {
        Default = Color3.fromRGB(0, 200, 255),
        Title = "Path Color",
    })
    Box:AddLabel("The line shows the live route the bot is walking, including the turns it takes around obstacles.", true)

    -- PATH VISUALIZATION: a 3D line made of Beams strung between the waypoints --
    local pathFolder = Instance.new("Folder")
    pathFolder.Name = "AutoFollowPathVisual"
    pathFolder.Parent = workspace

    local segments = {}

    local function clearPathVisual()
        for _, seg in ipairs(segments) do
            if seg.beam then seg.beam:Destroy() end
            if seg.p0 then seg.p0:Destroy() end
            if seg.p1 then seg.p1:Destroy() end
        end
        segments = {}
    end

    local function makeAnchor(position)
        local part = Instance.new("Part")
        part.Name = "WP"
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Transparency = 1
        part.Size = Vector3.new(0.2, 0.2, 0.2)
        part.CFrame = CFrame.new(position)
        part.Parent = pathFolder

        local att = Instance.new("Attachment")
        att.Parent = part
        return part, att
    end

    local function drawPathVisual(points)
        clearPathVisual()
        if not Toggles.ShowFollowPath.Value then return end
        for i = 1, #points - 1 do
            local p0, a0 = makeAnchor(points[i])
            local p1, a1 = makeAnchor(points[i + 1])

            local beam = Instance.new("Beam")
            beam.Attachment0 = a0
            beam.Attachment1 = a1
            beam.Width0 = 0.3
            beam.Width1 = 0.3
            beam.FaceCamera = true
            beam.Color = ColorSequence.new(Options.FollowPathColor.Value)
            beam.Transparency = NumberSequence.new(0.15)
            beam.Parent = p0

            table.insert(segments, { p0 = p0, p1 = p1, beam = beam })
        end
    end

    Options.FollowPathColor:OnChanged(function(color)
        for _, seg in ipairs(segments) do
            if seg.beam then seg.beam.Color = ColorSequence.new(color) end
        end
    end)

    Toggles.ShowFollowPath:OnChanged(function(on)
        if not on then clearPathVisual() end
    end)

    local lastNotifyMsg, lastNotifyTime = nil, 0
    local function notify(msg)
        if not Toggles.FollowDebugNotify.Value then return end
        -- Avoid spamming the same message every frame.
        if msg == lastNotifyMsg and tick() - lastNotifyTime < 2 then return end
        lastNotifyMsg, lastNotifyTime = msg, tick()
        Library:Notify(msg, 2)
    end

    -- PATHFINDING (Roblox's standard MoveTo + MoveToFinished pattern) --------
    local agentParams = {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
    }

    local waypoints, waypointIndex = {}, 1
    local lastPathTargetPos
    local lastPathAttempt = 0
    local followActive = false
    local moveToFinishedConn
    local lastAdvanceTime = 0

    -- Watchdog state: tracks whether we're actually making progress overall.
    local lastProgressCheck, posAtLastProgressCheck, stuckStreak = 0, nil, 0

    -- Bump/jump/vault state: tracks how blocked we are against the current
    -- waypoint and which escalation phase we're in.
    local jumpAttempts, vaultAttempts = 0, 0
    local lastBumpCheckTime, lastBumpCheckPos = 0, nil
    local unstuckUntil = 0 -- while > tick(), we're doing a backward "unstuck" nudge

    local function clearMoveToConn()
        if moveToFinishedConn then
            moveToFinishedConn:Disconnect()
            moveToFinishedConn = nil
        end
    end

    local function resetWatchdog()
        lastProgressCheck = tick()
        posAtLastProgressCheck = nil
        stuckStreak = 0
    end

    local function resetBumpState()
        jumpAttempts, vaultAttempts = 0, 0
        lastBumpCheckTime, lastBumpCheckPos = 0, nil
    end

    local function advanceTo(index)
        local hum = getHum()
        local wp = waypoints[index]
        if not (hum and wp) then return end
        hum:MoveTo(wp.Position)
        if wp.Action == Enum.PathWaypointAction.Jump then
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            hum.Jump = true
        end
        lastAdvanceTime = tick()
    end

    local function onMoveToFinished(reached)
        if not followActive then return end
        if not reached then
            -- Timed out / blocked -- drop the path so the next Heartbeat tick
            -- computes a fresh one instead of retrying the same stuck move.
            waypoints, waypointIndex = {}, 1
            return
        end
        waypointIndex += 1
        if waypoints[waypointIndex] then
            advanceTo(waypointIndex)
        else
            waypoints, waypointIndex = {}, 1 -- path finished; Heartbeat will recompute if still too far
        end
    end

    local function startPath(startPos, targetPos)
        local path = PathfindingService:CreatePath(agentParams)
        local ok = pcall(function() path:ComputeAsync(startPos, targetPos) end)
        if ok and path.Status == Enum.PathStatus.Success then
            waypoints = path:GetWaypoints()
            waypointIndex = 2 -- skip the starting waypoint
        else
            -- Pathfinding failed (no navmesh / blocked / unreachable) -- fall back
            -- to a straight line so the bot keeps moving instead of standing still.
            waypoints = {
                { Position = startPos, Action = Enum.PathWaypointAction.Walk },
                { Position = targetPos, Action = Enum.PathWaypointAction.Walk },
            }
            waypointIndex = 2
        end
        lastPathTargetPos = targetPos
        resetWatchdog()
        resetBumpState()

        local hum = getHum()
        clearMoveToConn()
        if hum then
            moveToFinishedConn = connect(hum.MoveToFinished, onMoveToFinished)
            advanceTo(waypointIndex)
        end

        if Toggles.ShowFollowPath.Value then
            local pts = {}
            for _, wp in ipairs(waypoints) do table.insert(pts, wp.Position) end
            drawPathVisual(pts)
        else
            clearPathVisual()
        end
    end

    local function stopFollowing()
        followActive = false
        MovementState.FollowActive = false
        clearMoveToConn()
        waypoints, waypointIndex = {}, 1
        lastPathTargetPos = nil
        unstuckUntil = 0
        resetWatchdog()
        resetBumpState()
        local hum = getHum()
        if hum then hum:Move(Vector3.new(), false) end
        clearPathVisual()
    end

    connect(RunService.Heartbeat, function()
        if not Toggles.AutoFollow.Value then
            if followActive then stopFollowing() end
            return
        end

        local hum, root = getHum(), getRoot()

        -- Target can be either a live player (position updates every frame)
        -- or a fixed saved waypoint (static position) -- either way we end
        -- up with a plain targetPosition Vector3 for the rest of the logic.
        local targetPosition
        if Options.FollowTargetType.Value == "Saved Waypoint" then
            local cf = SharedWaypoints[Options.FollowWaypoint.Value]
            targetPosition = cf and cf.Position
        else
            local name = Options.FollowTarget.Value
            local target = name and Players:FindFirstChild(name)
            local targetChar = target and target.Character
            local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
            targetPosition = targetRoot and targetRoot.Position
        end
        if not (hum and root and targetPosition) then
            if followActive then stopFollowing() end
            return
        end

        local stopDist = Options.FollowDistance.Value
        local dist = (root.Position - targetPosition).Magnitude

        if followActive then
            if dist <= stopDist then
                stopFollowing()
                return
            end
        else
            -- Small buffer above the stop distance avoids rapid stop/start
            -- jitter while the target hovers right at the boundary.
            if dist <= stopDist + 2 then return end
            followActive = true
            MovementState.FollowActive = true
            resetWatchdog()
            resetBumpState()
        end

        -- Emergency "unstuck" nudge: briefly walk backward and jump, then let
        -- the next path recompute take over. Overrides normal MoveTo for a
        -- fraction of a second.
        if tick() < unstuckUntil then
            hum:Move(-(hum.MoveDirection.Magnitude > 0.01 and hum.MoveDirection.Unit or Vector3.new(0, 0, 1)), false)
            hum.Jump = true
            return
        end

        local needNewPath = (#waypoints == 0)
            or (not lastPathTargetPos)
            or (targetPosition - lastPathTargetPos).Magnitude > 10

        if needNewPath then
            if tick() - lastPathAttempt > 0.4 then
                lastPathAttempt = tick()
                startPath(root.Position, targetPosition)
            end
            return
        end

        local wp = waypoints[waypointIndex]
        local toWpFlat = wp and Vector3.new(wp.Position.X - root.Position.X, 0, wp.Position.Z - root.Position.Z)

        -- BUMP DETECTION: are we actually making progress, in ANY direction
        -- (not just horizontally), while trying to reach the waypoint?
        -- Checking full 3D displacement -- instead of horizontal speed only
        -- -- is what makes this correctly leave staircases alone: climbing
        -- stairs is mostly vertical movement with low horizontal speed, so a
        -- horizontal-only check used to misread that as "stuck" and jump for
        -- no reason. Real movement in any direction now counts as progress.
        if Toggles.AutoJumpObstacles.Value and toWpFlat and toWpFlat.Magnitude > 0.5
            and tick() - lastAdvanceTime > 0.3 -- give movement a moment to ramp up after each MoveTo
            and tick() - lastBumpCheckTime > 0.3 -- sample displacement, not instantaneous noise
        then
            local moved = lastBumpCheckPos and (root.Position - lastBumpCheckPos).Magnitude or 999
            lastBumpCheckPos, lastBumpCheckTime = root.Position, tick()

            if moved < 1 then
                local dirUnit = toWpFlat.Magnitude > 0.1 and toWpFlat.Unit or root.CFrame.LookVector

                if jumpAttempts < 3 then
                    -- Phase 1: a normal jump in place -- clears curbs, crates,
                    -- half-blocks, and other low lips.
                    jumpAttempts += 1
                    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    hum.Jump = true
                    notify(("Auto-Follow: obstacle ahead, jumping... (%d/3)"):format(jumpAttempts))
                elseif vaultAttempts < 2 then
                    -- Phase 2: a normal jump wasn't enough -- this is a wall too
                    -- tall or a gap too wide to just hop over. Give the
                    -- character a running-jump style velocity boost (the same
                    -- technique the Launch Pad feature uses) toward the
                    -- waypoint to carry it up and across.
                    vaultAttempts += 1
                    notify(("Auto-Follow: obstacle too big to just jump, vaulting... (%d/2)"):format(vaultAttempts))
                    hum:ChangeState(Enum.HumanoidStateType.Freefall)
                    root.AssemblyLinearVelocity = dirUnit * Options.VaultPower.Value
                        + Vector3.new(0, Options.VaultPower.Value * 0.8, 0)
                else
                    -- Still stuck after jumping AND vaulting -- back up for a
                    -- moment to break away from it, then get a fresh route,
                    -- instead of retrying the same blocked move forever.
                    notify("Auto-Follow: still stuck, backing up and rerouting...")
                    resetBumpState()
                    unstuckUntil = tick() + 0.5
                    lastPathTargetPos = nil -- forces a recompute right after the nudge
                    return
                end
            else
                -- Making real progress again -- the obstacle is behind us.
                jumpAttempts, vaultAttempts = 0, 0
            end
        end

        -- Watchdog: confirm we're actually making progress toward the
        -- waypoint over a longer window. If not, something interrupted the
        -- move (your own movement input, a physics shove, etc.) without
        -- properly ending it.
        if tick() - lastProgressCheck > 1 then
            if posAtLastProgressCheck and (root.Position - posAtLastProgressCheck).Magnitude < 2 then
                stuckStreak += 1
                if stuckStreak >= 3 then
                    notify("Auto-Follow: stuck, recalculating route...")
                    startPath(root.Position, targetPosition)
                else
                    -- Likely just interrupted (e.g. you moved manually) -- simply
                    -- resume toward the same waypoint instead of recomputing.
                    advanceTo(waypointIndex)
                end
            else
                stuckStreak = 0
            end
            posAtLastProgressCheck = root.Position
            lastProgressCheck = tick()
        end
    end)

    connect(LocalPlayer.CharacterAdded, function()
        stopFollowing()
    end)

    onCleanup(function()
        stopFollowing()
        pathFolder:Destroy()
    end)
end
--##### [BLOCK: AUTO-FOLLOW] END #####


--=====================================================================
--  TAB: MISC
--=====================================================================

--##### [BLOCK: ANTI-AFK] START #####
do
    local Box = AddBox(Tabs.Misc, "Anti-AFK", "timer")

    addInlineBind(Box:AddToggle("AntiAFK", { Text = "Enable", Default = false }), "BindAntiAFK", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AntiAFK"})

    connect(LocalPlayer.Idled, function()
        if Toggles.AntiAFK.Value then
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.zero)
        end
    end)
end
--##### [BLOCK: ANTI-AFK] END #####


--##### [BLOCK: AUTO CLICKER] START #####   (NEW)
do
    local Box = AddBox(Tabs.Misc, "Auto Clicker", "mouse-pointer-2")
    local VIM = game:GetService("VirtualInputManager")
    local running = false

    Box:AddSlider("CPS", { Text = "Clicks Per Second", Default = 10, Min = 1, Max = 30, Rounding = 0 })
    addInlineBind(Box:AddToggle("AutoClick", {
        Text = "Enable",
        Default = false,
        Callback = function(on)
            running = on
            if not on then return end
            task.spawn(function()
                while running do
                    local pos = UIS:GetMouseLocation()
                    pcall(function()
                        VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
                        VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
                    end)
                    task.wait(1 / Options.CPS.Value)
                end
            end)
        end,
    }), "BindAutoClick", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "AutoClick"})

    onCleanup(function() running = false end)
end
--##### [BLOCK: AUTO CLICKER] END #####


--##### [BLOCK: RESPAWN] START #####
do
    local Box = AddBox(Tabs.Misc, "Respawn", "refresh-cw")

    Box:AddButton({
        Text = "Respawn Character",
        Func = function()
            local hum = getHum()
            if hum then hum.Health = 0 end
        end,
    })
end
--##### [BLOCK: RESPAWN] END #####


--##### [BLOCK: GOD MODE] START #####   (NEW)
do
    local Box = AddBox(Tabs.Misc, "God Mode", "heart")

    addInlineBind(Box:AddToggle("GodMode", {
        Text = "Auto Heal (God Mode)",
        Default = false,
    }), "KeybindGodMode", {Default = "H", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "GodMode"})
    addInlineBind(Box:AddToggle("NoFallDamage", {
        Text = "No Fall Damage",
        Default = false,
    }), "BindNoFallDamage", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "NoFallDamage"})

    connect(RunService.Heartbeat, function()
        local hum = getHum()
        if not hum then return end
        if Toggles.GodMode.Value then
            hum.Health = hum.MaxHealth
        end
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not Toggles.NoFallDamage.Value)
    end)

    onCleanup(function()
        local hum = getHum()
        if hum then hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end
    end)
end
--##### [BLOCK: GOD MODE] END #####


--##### [BLOCK: SERVER ID] START #####   (NEW)
do
    local Box = AddBox(Tabs.Servers, "Server ID", "link")

    Box:AddButton({
        Text = "Copy This Server's ID",
        Func = function()
            local id = game.JobId
            local ok = pcall(function() setclipboard(id) end)
            if ok then
                Library:Notify("Server ID copied to clipboard", 3)
            else
                Library:Notify("Server ID: " .. id, 6)
            end
        end,
    })
    Box:AddLabel("Share your Server ID with a friend so they can paste it into Join Server to join you.", true)
end
--##### [BLOCK: SERVER ID] END #####


--##### [BLOCK: JOIN SERVER] START #####   (NEW)
do
    local Box = AddBox(Tabs.Servers, "Join Server", "log-in")

    Box:AddInput("JoinServerId", {
        Text = "Server ID to join",
        Default = "",
        Placeholder = "Paste a friend's Server ID here",
    })
    Box:AddButton({
        Text = "Join That Server",
        Func = function()
            local id = Options.JoinServerId.Value
            if not id or id == "" then
                Library:Notify("Paste a Server ID first", 3)
                return
            end
            TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
        end,
    })
end
--##### [BLOCK: JOIN SERVER] END #####


--##### [BLOCK: REJOIN] START #####   (NEW)
do
    local Box = AddBox(Tabs.Servers, "Rejoin", "refresh-cw")

    Box:AddButton({
        Text = "Rejoin This Server",
        DoubleClick = true,   -- requires two clicks
        Func = function()
            if #Players:GetPlayers() <= 1 then
                LocalPlayer:Kick("\nRejoining...")
                task.wait()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end,
    })
end
--##### [BLOCK: REJOIN] END #####


--##### [BLOCK: SERVER HOP] START #####   (NEW)
do
    local Box = AddBox(Tabs.Servers, "Server Hop", "shuffle")

    -- Fetch the list of public servers for this place via the Roblox API
    local function fetchServers()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if not ok then return nil, body end

        local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok2 then return nil, data end

        return data.data
    end

    Box:AddButton({
        Text = "Server Hop (random other server)",
        Func = function()
            local servers, err = fetchServers()
            if not servers then
                Library:Notify("Failed to fetch server list: " .. tostring(err), 4)
                return
            end

            local candidates = {}
            for _, s in ipairs(servers) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers then
                    table.insert(candidates, s)
                end
            end

            if #candidates == 0 then
                Library:Notify("No other servers found", 4)
                return
            end

            local pick = candidates[math.random(1, #candidates)]
            TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
        end,
    })
end
--##### [BLOCK: SERVER HOP] END #####


--##### [BLOCK: LOW-POPULATION SERVER] START #####   (NEW)
do
    local Box = AddBox(Tabs.Servers, "Low-Population Server", "users")

    -- Fetch the list of public servers for this place via the Roblox API
    local function fetchServers()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if not ok then return nil, body end

        local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok2 then return nil, data end

        return data.data
    end

    Box:AddSlider("LowPopThreshold", {
        Text = "Desired Player Count (max)",
        Default = 3, Min = 1, Max = 20, Rounding = 0,
    })
    Box:AddButton({
        Text = "Join a Low-Population Server",
        Func = function()
            local servers, err = fetchServers()
            if not servers then
                Library:Notify("Failed to fetch server list: " .. tostring(err), 4)
                return
            end

            local threshold = Options.LowPopThreshold.Value
            local underThreshold, all = {}, {}
            for _, s in ipairs(servers) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers then
                    table.insert(all, s)
                    if s.playing <= threshold then
                        table.insert(underThreshold, s)
                    end
                end
            end

            local pool = #underThreshold > 0 and underThreshold or all
            if #pool == 0 then
                Library:Notify("No suitable server found", 4)
                return
            end

            table.sort(pool, function(a, b) return a.playing < b.playing end)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, pool[1].id, LocalPlayer)
        end,
    })
end
--##### [BLOCK: LOW-POPULATION SERVER] END #####


--##### [BLOCK: SCRIPT NETWORK] START #####   (NEW)
-- Lets you see other players (in any server) who are also running this
-- script and broadcasting, and join a specific one of them if they're in
-- the same game. This needs YOUR OWN free Firebase Realtime Database --
-- the script talks only to a database you create and control, never to any
-- server of ours. One-time setup:
--   1. Go to https://console.firebase.google.com and create a free project.
--   2. Open "Realtime Database" (not Firestore) -> Create Database -> pick
--      any region -> start in test mode.
--   3. Copy the database URL shown at the top (looks like
--      https://your-project-id-default-rtdb.firebaseio.com) and paste it
--      into the "Database URL" field below.
-- "Test mode" means anyone with the URL can read/write it -- fine for a
-- small group of friends. Tighten the database's security rules later if
-- you want it locked down further.
do
    local Box = AddBox(Tabs.Servers, "Script Network", "radio")

    -- UNC-style request wrapper: tries whatever HTTP function your executor
    -- exposes (request / http_request / syn.request), falling back to the
    -- native HttpService if none of those exist.
    local customRequest = (syn and syn.request) or http_request or request
    local function webRequest(opts)
        if customRequest then
            local ok, res = pcall(customRequest, opts)
            if ok and res then return res end
        end
        local ok, res = pcall(function()
            return HttpService:RequestAsync({
                Url = opts.Url,
                Method = opts.Method or "GET",
                Headers = opts.Headers,
                Body = opts.Body,
            })
        end)
        if ok then return res end
        return nil
    end

    local PRESENCE_PATH = "claudehub_presence"
    local PRESENCE_TIMEOUT = 45 -- seconds -- entries older than this are hidden (assumed offline)
    local BROADCAST_INTERVAL = 15

    local found = {} -- label -> { placeId = ..., jobId = ... }
    local running = false

    local function baseUrl()
        local url = Options.PresenceEndpoint.Value
        if not url or url == "" then return nil end
        return (url:gsub("/+$", "")) -- trim trailing slashes
    end

    local function broadcastOnce()
        local base = baseUrl()
        if not base then return end
        local body = HttpService:JSONEncode({
            name = LocalPlayer.Name,
            placeId = game.PlaceId,
            jobId = game.JobId,
            ts = os.time(),
        })
        webRequest({
            Url = ("%s/%s/%d.json"):format(base, PRESENCE_PATH, LocalPlayer.UserId),
            Method = "PUT",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end

    local function removePresence()
        local base = baseUrl()
        if not base then return end
        webRequest({
            Url = ("%s/%s/%d.json"):format(base, PRESENCE_PATH, LocalPlayer.UserId),
            Method = "DELETE",
        })
    end

    local function refreshList()
        local base = baseUrl()
        if not base then
            Library:Notify("Set a Firebase Database URL first", 3)
            return
        end

        local res = webRequest({
            Url = ("%s/%s.json"):format(base, PRESENCE_PATH),
            Method = "GET",
        })
        if not (res and (res.StatusCode == 200 or res.Success)) then
            Library:Notify("Failed to reach the database -- check the URL", 4)
            return
        end

        local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
        if not ok then
            Library:Notify("Failed to read the user list from the database", 4)
            return
        end
        data = (type(data) == "table") and data or {}

        found = {}
        local labels = {}
        local now = os.time()
        for userId, entry in pairs(data) do
            if type(entry) == "table" and tostring(userId) ~= tostring(LocalPlayer.UserId)
                and entry.ts and (now - entry.ts) <= PRESENCE_TIMEOUT
            then
                local sameServer = entry.placeId == game.PlaceId and entry.jobId == game.JobId
                local label = ("%s (ID %s)%s"):format(
                    entry.name or "Unknown",
                    tostring(userId),
                    sameServer and " - this server" or ""
                )
                found[label] = { placeId = entry.placeId, jobId = entry.jobId }
                table.insert(labels, label)
            end
        end

        table.sort(labels)
        Options.PresenceUsers:SetValues(labels)
        Library:Notify(("Found %d user(s) online"):format(#labels), 3)
    end

    local function joinSelected()
        local label = Options.PresenceUsers.Value
        local entry = label and found[label]
        if not entry then
            Library:Notify("Pick a user from the list first", 3)
            return
        end
        if entry.placeId ~= game.PlaceId then
            Library:Notify("That user is in a different game -- can't join across games", 4)
            return
        end
        TeleportService:TeleportToPlaceInstance(entry.placeId, entry.jobId, LocalPlayer)
    end

    Box:AddInput("PresenceEndpoint", {
        Text = "Firebase Database URL",
        Default = "",
        Placeholder = "https://your-project-id-default-rtdb.firebaseio.com",
    })
    addInlineBind(Box:AddToggle("PresenceEnabled", {
        Text = "Broadcast My Presence",
        Default = false,
        Callback = function(on)
            running = on
            if not on then
                removePresence()
                return
            end
            if not baseUrl() then
                Library:Notify("Set a Firebase Database URL first", 3)
                running = false
                Toggles.PresenceEnabled:SetValue(false)
                return
            end
            task.spawn(function()
                while running do
                    broadcastOnce()
                    task.wait(BROADCAST_INTERVAL)
                end
            end)
        end,
    }), "BindPresenceEnabled", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "PresenceEnabled"})
    Box:AddDropdown("PresenceUsers", { Text = "Found Users", Values = {}, Default = nil, AllowNull = true })
    Box:AddButton({ Text = "Refresh List", Func = refreshList })
    Box:AddButton({ Text = "Join Selected User's Server", Func = joinSelected })
    Box:AddLabel("Shows other players (in any server) who also have this script running and broadcasting. Needs your own free Firebase Realtime Database -- see the setup steps in this block's comment header in the source file.", true)

    onCleanup(function()
        running = false
        if Toggles.PresenceEnabled.Value then removePresence() end
    end)
end
--##### [BLOCK: SCRIPT NETWORK] END #####


--##### [BLOCK: CHARACTER SCALE] START #####   (NEW)
-- Uses Model:ScaleTo(), a built-in Roblox API that uniformly scales a whole
-- character model (including collision & joints). Unlike the old Humanoid
-- Body*Scale/HeadScale NumberValues (R15-only, and unreliable even there),
-- ScaleTo works the same way on both R15 and R6 rigs.
do
    local Box = AddBox(Tabs.Misc, "Character Scale", "maximize")

    local function applyScale(value)
        local char = getChar()
        if not char then return end
        pcall(function() char:ScaleTo(value) end)
    end

    Box:AddSlider("CharScale", {
        Text = "Scale", Default = 1, Min = 0.5, Max = 3, Rounding = 2,
        Callback = applyScale,
    })
    Box:AddButton({
        Text = "Reset",
        Func = function() Options.CharScale:SetValue(1) end,
    })
    Box:AddLabel("Works on both R15 and R6 avatars.", true)

    connect(LocalPlayer.CharacterAdded, function()
        task.wait(0.5)
        applyScale(Options.CharScale.Value)
    end)
end
--##### [BLOCK: CHARACTER SCALE] END #####


--=====================================================================
--  THEME / CONFIG SETUP. Feature blocks may also follow this section.
--=====================================================================


--##### [BLOCK 5: MENU, THEMES, CONFIGS] START #####  [DO NOT TOUCH]
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddButton({
    Text = "Unload Script",
    Func = function() Library:Unload() end,
})

MenuGroup:AddButton({Text = "Reset HUD Positions", Func = resetHudPositions})

MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
    Default = CONFIG.MenuKey,
    NoUI = true,
    Text = "Menu Keybind",
})
Library.ToggleKeybind = Options.MenuKeybind

Library:OnUnload(function()
    for _, c in ipairs(Connections) do c:Disconnect() end
    for _, fn in ipairs(CleanupFns) do pcall(fn) end
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder(CONFIG.FolderName)
SaveManager:SetFolder(CONFIG.FolderName .. "/configs")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
task.defer(function()
    if not Library.Unloaded then SaveManager:LoadAutoloadConfig() end
end)
--##### [BLOCK 5: MENU, THEMES, CONFIGS] END #####


--##### [BLOCK: CUSTOM SCRIPT (button + input field)] START #####   (NEW)
do
    local Box = Tabs.Settings:AddRightGroupbox("Custom Script", "terminal")
    local slots = { "", "", "" }

    Box:AddDropdown("ScriptSlot", {
        Text = "Slot",
        Values = { "Slot 1", "Slot 2", "Slot 3" },
        Default = 1,
        Callback = function(value)
            local idx = tonumber(value:match("%d+")) or 1
            Options.CustomScriptCode:SetValue(slots[idx])
        end,
    })

    Box:AddInput("CustomScriptCode", {
        Text = "Code To Run",
        Default = "",
        Placeholder = "print('Hello!')",
        ClearTextOnFocus = false,
        AllowEmpty = true,
        Callback = function(value)
            local idx = tonumber(Options.ScriptSlot.Value:match("%d+")) or 1
            slots[idx] = value
        end,
    })
    Box:AddLabel("Single-line Lua code. Separate multiple statements with ; (semicolon). Use the slot dropdown to store up to 3 snippets.", true)

    Box:AddButton({
        Text = "Run",
        Func = function()
            local code = Options.CustomScriptCode.Value
            if not code or code == "" then
                Library:Notify("Field is empty — nothing to run", 3)
                return
            end

            local fn, compileErr = loadstring(code)
            if not fn then
                Library:Notify("Compile error: " .. tostring(compileErr), 5)
                return
            end

            local ok, runErr = pcall(fn)
            if not ok then
                Library:Notify("Runtime error: " .. tostring(runErr), 5)
            end
        end,
    })
end
--##### [BLOCK: CUSTOM SCRIPT (button + input field)] END #####

--##### [BLOCK: NO ACCELERATION] START #####
-- Only assists grounded manual movement. Never overwrite pathfinding,
-- airborne momentum, a wallhop impulse or the Fly controller.
do
    local Box = AddBox(Tabs.Main, "No Acceleration", "gauge")
    addInlineBind(Box:AddToggle("NoAcceleration", {Text = "Enable", Default = false}), "BindNoAcceleration", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "NoAcceleration"})
    Box:AddLabel("Instant start/stop for grounded manual walking. Yields to Auto-Follow, Fly and airborne impulses so they retain native movement.", true)
    connect(RunService.PreSimulation, function()
        if not Toggles.NoAcceleration.Value or MovementState.FollowActive
            or MovementState.WallhopActive or tick() < MovementState.ImpulseUntil
            or (Toggles.Fly and Toggles.Fly.Value) then return end
        local hum, root = getHum(), getRoot()
        if not (hum and root) or hum.Health <= 0 or hum.Sit or hum.PlatformStand
            or hum.FloorMaterial == Enum.Material.Air then return end
        local velocity, direction = root.AssemblyLinearVelocity, hum.MoveDirection
        local flat = Vector3.new(direction.X, 0, direction.Z)
        local target = flat.Magnitude > 0.05 and flat.Unit * hum.WalkSpeed or Vector3.zero
        root.AssemblyLinearVelocity = Vector3.new(target.X, velocity.Y, target.Z)
    end)
end
--##### [BLOCK: NO ACCELERATION] END #####


--##### [BLOCK: FAKE WALLHOP] START #####
-- Manual wall-assisted air hop. No automatic jumping and no JumpRequest
-- (which can repeat while Space is held). Restore orientation, NOT position.
do
    local Box = AddBox(Tabs.Main, "Fake Wallhop", "arrow-big-up-dash")
    local activeRoot, activeHum, originalRotation, originalAutoRotate, untilTime
    local turnSign, spaceDown, lastHop = 1, false, -math.huge
    local function finishTurn()
        if activeRoot and activeRoot.Parent and originalRotation then
            activeRoot.CFrame = CFrame.new(activeRoot.Position) * originalRotation
        end
        if activeHum and activeHum.Parent and originalAutoRotate ~= nil then
            activeHum.AutoRotate = originalAutoRotate
        end
        activeRoot, activeHum, originalRotation, originalAutoRotate, untilTime = nil, nil, nil, nil, nil
        MovementState.WallhopActive = false
    end
    MovementState.FinishWallhop = finishTurn
    addInlineBind(Box:AddToggle("FakeWallhop", {Text = "Enable", Default = false,
        Callback = function(on) if not on then finishTurn() end end}), "BindFakeWallhop", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "FakeWallhop"})
    Box:AddSlider("WallhopInterval", {Text = "Cooldown", Default = 0.3, Min = 0.15, Max = 1, Rounding = 2, Suffix = "s"})
    Box:AddDropdown("WallhopSide", {Text = "Turn direction", Values = {"Left", "Right", "Alternate"}, Default = 3})
    Box:AddSlider("WallhopWallDistance", {Text = "Wall detection (studs)", Default = 3, Min = 1.5, Max = 5, Rounding = 1})
    Box:AddSlider("WallhopTurnAngle", {Text = "Turn angle", Default = 85, Min = 30, Max = 120, Rounding = 0})
    Box:AddSlider("WallhopTurnDuration", {Text = "Turn duration", Default = 0.12, Min = 0.06, Max = 0.3, Rounding = 2, Suffix = "s"})
    Box:AddSlider("WallhopJumpSpeed", {Text = "Upward jump speed", Default = 48, Min = 20, Max = 85, Rounding = 0})
    Box:AddSlider("WallhopSideSpeed", {Text = "Side kick", Default = 6, Min = 0, Max = 20, Rounding = 0})
    Box:AddLabel("Jump normally, then RELEASE and press Space again while airborne beside a solid wall. Turns and hops together, then restores facing at your current position. Holding Space never auto-hops.", true)
    local function nearWall(root, char)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {char}
        params.IgnoreWater = true
        params.RespectCanCollide = true
        -- Horizontal rays reject floors / ramps by their surface normal.
        for i = 0, 7 do
            local angle = i * math.pi / 4
            local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
            local hit = workspace:Raycast(root.Position, direction * Options.WallhopWallDistance.Value, params)
            if hit and hit.Instance and math.abs(hit.Normal.Y) < 0.35 then
                local solid = hit.Instance:IsA("Terrain")
                    or (hit.Instance:IsA("BasePart") and hit.Instance.CanCollide)
                if solid then return true end
            end
        end
        return false
    end
    connect(UIS.InputBegan, function(input)
        if input.KeyCode ~= Enum.KeyCode.Space then return end
        if spaceDown then return end
        spaceDown = true
        if not Toggles.FakeWallhop.Value or UIS:GetFocusedTextBox() or Library.IsPicking
            or MovementState.WallhopActive or tick() - lastHop < Options.WallhopInterval.Value
            or (Toggles.Fly and Toggles.Fly.Value) then return end
        local hum, root, char = getHum(), getRoot(), getChar()
        if not (hum and root and char) or hum.Health <= 0 or hum.Sit or hum.PlatformStand
            or hum.FloorMaterial ~= Enum.Material.Air then return end
        local state = hum:GetState()
        if state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall then return end
        if not nearWall(root, char) then return end
        local side = Options.WallhopSide.Value
        if side == "Left" then turnSign = 1 elseif side == "Right" then turnSign = -1 else turnSign = -turnSign end
        activeRoot, activeHum = root, hum
        originalRotation, originalAutoRotate = root.CFrame.Rotation, hum.AutoRotate
        untilTime = tick() + Options.WallhopTurnDuration.Value
        lastHop = tick()
        MovementState.WallhopActive = true
        MovementState.ImpulseUntil = untilTime + 0.15
        hum.AutoRotate = false
        -- Apply facing and jump velocity in this same input callback.
        root.CFrame = CFrame.new(root.Position) * originalRotation * CFrame.Angles(0, math.rad(Options.WallhopTurnAngle.Value) * turnSign, 0)
        local velocity = root.AssemblyLinearVelocity
        local sideKick = originalRotation.RightVector * (-turnSign * Options.WallhopSideSpeed.Value)
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X + sideKick.X,
            Options.WallhopJumpSpeed.Value, velocity.Z + sideKick.Z)
    end)
    connect(UIS.InputEnded, function(input) if input.KeyCode == Enum.KeyCode.Space then spaceDown = false end end)
    connect(UIS.WindowFocusReleased, function() spaceDown = false finishTurn() end)
    connect(LocalPlayer.CharacterAdded, function() spaceDown = false finishTurn() end)
    local renderName = "ClaudeHub_Wallhop_" .. HttpService:GenerateGUID(false)
    RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 2, function()
        if not MovementState.WallhopActive then return end
        if not Toggles.FakeWallhop.Value or getRoot() ~= activeRoot or not activeRoot.Parent
            or not activeHum.Parent or activeHum.Health <= 0 or tick() >= untilTime then finishTurn() return end
        activeHum.AutoRotate = false
        activeRoot.CFrame = CFrame.new(activeRoot.Position) * originalRotation
            * CFrame.Angles(0, math.rad(Options.WallhopTurnAngle.Value) * turnSign, 0)
    end)
    onCleanup(function()
        RunService:UnbindFromRenderStep(renderName)
        finishTurn()
        MovementState.FinishWallhop = nil
    end)
end
--##### [BLOCK: FAKE WALLHOP] END #####

--=====================================================================
--  OPTIONAL UTILITY FEATURES (self/client-side only)
--  All callbacks are cleanup-owned. Each feature can be deleted alone.
--=====================================================================

--##### [BLOCK: SPRINT] START #####
-- Poll the physical key through the library's Hold picker. Do not rely on
-- InputBegan's gameProcessed flag (Shift Lock / game scripts can consume it).
-- The shared PreSimulation speed controller is the sole WalkSpeed writer.
do
    local Box = AddBox(Tabs.Main, "Sprint", "footprints")
    local focused = true
    Box:AddToggle("UltraSprint", {Text = "Enable (hold the bound key)", Default = false}):AddKeyPicker("UltraSprintKey", {
        Default = "LeftShift", Mode = "Hold", Modes = {"Hold"}, SyncToggleState = false,
        NoUI = true, Text = "Sprint: hold",
    })
    Box:AddSlider("UltraSprintSpeed", {Text = "Sprint speed (absolute)", Default = 48, Min = 16, Max = 120, Rounding = 0})
    Box:AddLabel("Hold LeftShift by default. Click its key badge to rebind. Overrides Speed while held, then restores it; does not bypass server movement limits.", true)
    connect(UIS.WindowFocusReleased, function() focused = false end)
    connect(UIS.WindowFocused, function() focused = true end)
    MovementState.GetSprintSpeed = function()
        local key = Options.UltraSprintKey
        if focused and Toggles.UltraSprint.Value and key and (key:GetState() or ((getgenv and getgenv() or _G).__ClaudeHubTouch or {}).Sprint)
            and not UIS:GetFocusedTextBox() and not Library.IsPicking then return Options.UltraSprintSpeed.Value end
        return nil
    end
    onCleanup(function() MovementState.GetSprintSpeed = nil end)
end
--##### [BLOCK: SPRINT] END #####

--##### [BLOCK: CAMERA OFFSET] START #####
do
    local Box = AddBox(Tabs.Visual, "Camera Offset", "camera")
    local current, original
    local function restore()
        if current and current.Parent then current.CameraOffset = original end
        current, original = nil, nil
    end
    addInlineBind(Box:AddToggle("UltraCameraOffset", {Text = "Enable", Default = false,
        Callback = function(on) if not on then restore() end end}), "BindUltraCameraOffset", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraCameraOffset"})
    Box:AddSlider("UltraCameraX", {Text = "Shoulder offset", Default = 1.8, Min = -5, Max = 5, Rounding = 1})
    Box:AddSlider("UltraCameraY", {Text = "Vertical offset", Default = 0, Min = -3, Max = 3, Rounding = 1})
    Box:AddLabel("For the standard Humanoid camera; scripted cameras may ignore this.", true)
    connect(RunService.RenderStepped, function()
        if not Toggles.UltraCameraOffset.Value then return end
        local hum = getHum()
        if hum ~= current then
            restore()
            if hum then current, original = hum, hum.CameraOffset end
        end
        if hum then hum.CameraOffset = original + Vector3.new(Options.UltraCameraX.Value, Options.UltraCameraY.Value, 0) end
    end)
    onCleanup(restore)
end
--##### [BLOCK: CAMERA OFFSET] END #####

--##### [BLOCK: CROSSHAIR] START #####
do
    local Box = AddBox(Tabs.Visual, "Crosshair", "crosshair")
    local gui = Instance.new("ScreenGui")
    gui.Name = "ClaudeHub_Crosshair"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 30
    gui.Enabled = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    local center = Instance.new("Frame")
    center.Name = "DragCenter"
    center.BackgroundTransparency = 1
    center.Size = UDim2.fromOffset(100, 100)
    center.AnchorPoint = Vector2.new(0.5, 0.5)
    center.Position = UDim2.fromScale(0.5, 0.5)
    center.Parent = gui
    makeDraggable(center)
    Box:AddLabel("Drag the center area to move the crosshair. UI Settings > Reset HUD Positions centers it again.", true)
    local arms = {}
    for i = 1, 4 do
        local arm = Instance.new("Frame")
        arm.BorderSizePixel = 0
        arm.AnchorPoint = Vector2.new(0.5, 0.5)
        arm.Parent = center
        arms[i] = arm
    end
    local function update()
        local length, gap = Options.UltraCrossLength.Value, Options.UltraCrossGap.Value
        for i, arm in ipairs(arms) do
            local horizontal = i <= 2
            local sign = i % 2 == 1 and -1 or 1
            arm.Size = horizontal and UDim2.fromOffset(length, 2) or UDim2.fromOffset(2, length)
            arm.Position = UDim2.new(0.5, horizontal and sign * (gap + length / 2) or 0,
                0.5, horizontal and 0 or sign * (gap + length / 2))
            arm.BackgroundColor3 = Options.UltraCrossColor.Value
        end
    end
    addInlineBind(Box:AddToggle("UltraCrosshair", {Text = "Enable", Default = false, Callback = function(on) gui.Enabled = on end}), "BindUltraCrosshair", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraCrosshair"})
    Box:AddSlider("UltraCrossLength", {Text = "Arm length", Default = 8, Min = 2, Max = 25, Rounding = 0})
    Box:AddSlider("UltraCrossGap", {Text = "Center gap", Default = 5, Min = 0, Max = 20, Rounding = 0})
    Box:AddLabel("Color"):AddColorPicker("UltraCrossColor", {Default = Color3.fromRGB(160, 110, 255)})
    Options.UltraCrossLength:OnChanged(update)
    Options.UltraCrossGap:OnChanged(update)
    Options.UltraCrossColor:OnChanged(update)
    update()
    onCleanup(function() gui:Destroy() end)
end
--##### [BLOCK: CROSSHAIR] END #####

--##### [BLOCK: POST FX CONTROL] START #####
do
    local Box = AddBox(Tabs.Visual, "Post-FX Control", "aperture")
    local saved = {}
    local function disable(obj)
        if not obj:IsA("PostEffect") or obj.Name == "ClaudeHub_ColorGrade" then return end
        if saved[obj] == nil then saved[obj] = obj.Enabled end
        obj.Enabled = false
    end
    local function restore()
        for obj, enabled in pairs(saved) do if obj.Parent then obj.Enabled = enabled end end
        table.clear(saved)
    end
    local function scan()
        for _, obj in ipairs(Lighting:GetChildren()) do disable(obj) end
        local cam = workspace.CurrentCamera
        if cam then for _, obj in ipairs(cam:GetChildren()) do disable(obj) end end
    end
    addInlineBind(Box:AddToggle("UltraNoPostFX", {Text = "Disable game post-effects", Default = false,
        Callback = function(on) if on then scan() else restore() end end}), "BindUltraNoPostFX", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraNoPostFX"})
    Box:AddLabel("Disables blur, bloom, depth of field and game color effects locally. Games can reapply effects.", true)
    -- Throttled scan also covers replaced cameras and newly created effects.
    local elapsed = 0
    connect(RunService.Heartbeat, function(dt)
        if not Toggles.UltraNoPostFX.Value then return end
        elapsed += dt
        if elapsed >= 0.25 then elapsed = 0 scan() end
    end)
    onCleanup(restore)
end
--##### [BLOCK: POST FX CONTROL] END #####

--##### [BLOCK: COLOR GRADING] START #####
do
    local Box = AddBox(Tabs.Visual, "Color Grading", "palette")
    local effect = Instance.new("ColorCorrectionEffect")
    effect.Name = "ClaudeHub_ColorGrade"
    effect.Enabled = false
    effect.Parent = Lighting
    local function update()
        effect.Brightness = Options.UltraGradeBrightness.Value
        effect.Contrast = Options.UltraGradeContrast.Value
        effect.Saturation = Options.UltraGradeSaturation.Value
        effect.TintColor = Options.UltraGradeTint.Value
    end
    addInlineBind(Box:AddToggle("UltraColorGrade", {Text = "Enable", Default = false, Callback = function(on) effect.Enabled = on end}), "BindUltraColorGrade", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraColorGrade"})
    Box:AddSlider("UltraGradeBrightness", {Text = "Brightness", Default = 0, Min = -0.3, Max = 0.3, Rounding = 2})
    Box:AddSlider("UltraGradeContrast", {Text = "Contrast", Default = 0.1, Min = -0.5, Max = 0.5, Rounding = 2})
    Box:AddSlider("UltraGradeSaturation", {Text = "Saturation", Default = 0.1, Min = -1, Max = 1, Rounding = 2})
    Box:AddLabel("Tint"):AddColorPicker("UltraGradeTint", {Default = Color3.new(1, 1, 1)})
    for _, id in ipairs({"UltraGradeBrightness", "UltraGradeContrast", "UltraGradeSaturation", "UltraGradeTint"}) do
        Options[id]:OnChanged(update)
    end
    update()
    onCleanup(function() effect:Destroy() end)
end
--##### [BLOCK: COLOR GRADING] END #####

--##### [BLOCK: CHARACTER LIGHT] START #####
do
    local Box = AddBox(Tabs.Visual, "Character Light", "flashlight")
    local light
    local function remove() if light then light:Destroy() light = nil end end
    addInlineBind(Box:AddToggle("UltraCharacterLight", {Text = "Enable", Default = false,
        Callback = function(on) if not on then remove() end end}), "BindUltraCharacterLight", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraCharacterLight"})
    Box:AddSlider("UltraLightRange", {Text = "Range", Default = 24, Min = 5, Max = 60, Rounding = 0})
    Box:AddSlider("UltraLightBrightness", {Text = "Brightness", Default = 2, Min = 0.2, Max = 6, Rounding = 1})
    Box:AddLabel("Local light attached to your character; not visible to other clients.", true)
    connect(RunService.Heartbeat, function()
        if not Toggles.UltraCharacterLight.Value then return end
        local root = getRoot()
        if not root then remove() return end
        if not light or light.Parent ~= root then
            remove()
            light = Instance.new("PointLight")
            light.Name = "ClaudeHub_Light"
            light.Shadows = false
            light.Parent = root
        end
        light.Range = Options.UltraLightRange.Value
        light.Brightness = Options.UltraLightBrightness.Value
    end)
    onCleanup(remove)
end
--##### [BLOCK: CHARACTER LIGHT] END #####

--##### [BLOCK: MOVEMENT TRAIL] START #####
do
    local Box = AddBox(Tabs.Visual, "Movement Trail", "wind")
    local trail, a0, a1
    local function remove()
        if trail then trail:Destroy() trail = nil end
        if a0 then a0:Destroy() a0 = nil end
        if a1 then a1:Destroy() a1 = nil end
    end
    addInlineBind(Box:AddToggle("UltraTrail", {Text = "Enable", Default = false,
        Callback = function(on) if not on then remove() end end}), "BindUltraTrail", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraTrail"})
    Box:AddSlider("UltraTrailLife", {Text = "Lifetime", Default = 1, Min = 0.1, Max = 4, Rounding = 1})
    Box:AddLabel("Color"):AddColorPicker("UltraTrailColor", {Default = Color3.fromRGB(140, 90, 255)})
    connect(RunService.Heartbeat, function()
        if not Toggles.UltraTrail.Value then return end
        local root = getRoot()
        if not root then remove() return end
        if not trail or trail.Parent ~= root then
            remove()
            a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
            a0.Position, a1.Position = Vector3.new(-0.7, 0, 0), Vector3.new(0.7, 0, 0)
            a0.Parent, a1.Parent = root, root
            trail = Instance.new("Trail")
            trail.Name = "ClaudeHub_Trail"
            trail.Attachment0, trail.Attachment1 = a0, a1
            trail.FaceCamera = true
            trail.Transparency = NumberSequence.new(0.2, 1)
            trail.Parent = root
        end
        trail.Lifetime = Options.UltraTrailLife.Value
        trail.Color = ColorSequence.new(Options.UltraTrailColor.Value)
    end)
    onCleanup(remove)
end
--##### [BLOCK: MOVEMENT TRAIL] END #####

--##### [BLOCK: BREADCRUMBS] START #####
do
    local Box = AddBox(Tabs.Visual, "Breadcrumbs", "route")
    local folder = Instance.new("Folder")
    folder.Name = "ClaudeHub_Breadcrumbs"
    folder.Parent = workspace
    local dots, previous, elapsed = {}, nil, 0
    local function clear()
        folder:ClearAllChildren()
        table.clear(dots)
        previous = nil
    end
    addInlineBind(Box:AddToggle("UltraBreadcrumbs", {Text = "Leave local path markers", Default = false,
        Callback = function(on) if not on then clear() end end}), "BindUltraBreadcrumbs", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraBreadcrumbs"})
    Box:AddSlider("UltraBreadcrumbSpacing", {Text = "Spacing (studs)", Default = 5, Min = 2, Max = 20, Rounding = 0})
    Box:AddSlider("UltraBreadcrumbLimit", {Text = "Maximum markers", Default = 80, Min = 10, Max = 200, Rounding = 0})
    Box:AddButton({Text = "Clear markers", Func = clear})
    connect(LocalPlayer.CharacterAdded, clear)
    connect(RunService.Heartbeat, function(dt)
        if not Toggles.UltraBreadcrumbs.Value then return end
        elapsed += dt
        if elapsed < 0.15 then return end
        elapsed = 0
        local root = getRoot()
        if not root then return end
        -- Trim even while standing still after lowering the limit.
        while #dots > Options.UltraBreadcrumbLimit.Value do table.remove(dots, 1):Destroy() end
        local pos = root.Position - Vector3.new(0, 2.7, 0)
        if previous and (pos - previous).Magnitude < Options.UltraBreadcrumbSpacing.Value then return end
        previous = pos
        local dot = Instance.new("Part")
        dot.Name = "Marker"
        dot.Shape = Enum.PartType.Ball
        dot.Size = Vector3.new(0.35, 0.35, 0.35)
        dot.Position = pos
        dot.Anchored, dot.CanCollide, dot.CanTouch, dot.CanQuery = true, false, false, false
        dot.Material = Enum.Material.Neon
        dot.Color = Color3.fromRGB(145, 90, 255)
        dot.Parent = folder
        table.insert(dots, dot)
        while #dots > Options.UltraBreadcrumbLimit.Value do table.remove(dots, 1):Destroy() end
    end)
    onCleanup(function() folder:Destroy() end)
end
--##### [BLOCK: BREADCRUMBS] END #####

--##### [BLOCK: COMPASS] START #####
do
    local Box = AddBox(Tabs.Visual, "Compass", "compass")
    local gui, label = createHud("Compass", 230, 30, UDim2.new(0.5, 0, 0, 48))
    addInlineBind(Box:AddToggle("UltraCompass", {Text = "Enable", Default = false, Callback = function(on) gui.Enabled = on end}), "BindUltraCompass", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraCompass"})
    Box:AddLabel("World axes: north = -Z, east = +X; not a game's custom north.", true)
    local elapsed = 0
    local names = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
    connect(RunService.RenderStepped, function(dt)
        if not gui.Enabled then return end
        elapsed += dt
        if elapsed < 0.05 then return end
        elapsed = 0
        local cam = workspace.CurrentCamera
        if not cam then return end
        local look = cam.CFrame.LookVector
        if Vector2.new(look.X, look.Z).Magnitude < 0.001 then return end
        local degrees = math.deg(math.atan2(look.X, -look.Z)) % 360
        local direction = names[math.floor((degrees + 22.5) / 45) % 8 + 1]
        label.Text = ("%s   |   %03d deg"):format(direction, math.floor(degrees + 0.5) % 360)
    end)
end
--##### [BLOCK: COMPASS] END #####

--##### [BLOCK: COORDINATES HUD] START #####
do
    local Box = AddBox(Tabs.Visual, "Coordinates HUD", "map-pin")
    local gui, label = createHud("Coordinates", 360, 30, UDim2.new(0.5, 0, 1, -116))
    addInlineBind(Box:AddToggle("UltraCoordinates", {Text = "Enable", Default = false, Callback = function(on) gui.Enabled = on end}), "BindUltraCoordinates", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraCoordinates"})
    Box:AddButton({Text = "Copy coordinates", Func = function()
        local root = getRoot()
        if not root then Library:Notify("Character is not ready", 3) return end
        local pos = root.Position
        local text = ("Vector3.new(%.2f, %.2f, %.2f)"):format(pos.X, pos.Y, pos.Z)
        local ok = pcall(function() setclipboard(text) end)
        if not ok then print(text) end
        Library:Notify(ok and "Coordinates copied" or "Coordinates printed to console", 3)
    end})
    local elapsed = 0
    connect(RunService.Heartbeat, function(dt)
        if not gui.Enabled then return end
        elapsed += dt
        if elapsed < 0.1 then return end
        elapsed = 0
        local root = getRoot()
        if not root then label.Text = "Coordinates: waiting for character" return end
        local p = root.Position
        label.Text = ("X %.1f   Y %.1f   Z %.1f"):format(p.X, p.Y, p.Z)
    end)
end
--##### [BLOCK: COORDINATES HUD] END #####

--##### [BLOCK: SESSION TIMER] START #####
do
    local Box = AddBox(Tabs.Misc, "Session Timer", "timer")
    local gui, label = createHud("SessionTimer", 230, 30, UDim2.new(0.5, 0, 0, 84))
    local started, elapsed = os.clock(), 0
    addInlineBind(Box:AddToggle("UltraSessionTimer", {Text = "Show timer", Default = false, Callback = function(on) gui.Enabled = on end}), "BindUltraSessionTimer", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraSessionTimer"})
    Box:AddButton({Text = "Reset timer", Func = function() started = os.clock() end})
    Box:AddLabel("Time since this script loaded, or since the last reset. Continues while hidden.", true)
    connect(RunService.Heartbeat, function(dt)
        if not gui.Enabled then return end
        elapsed += dt
        if elapsed < 0.25 then return end
        elapsed = 0
        local seconds = math.floor(os.clock() - started)
        label.Text = ("Session  %02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end)
end
--##### [BLOCK: SESSION TIMER] END #####

--##### [BLOCK: HEALTH HUD] START #####
do
    local Box = AddBox(Tabs.Visual, "Health HUD", "heart-pulse")
    local gui, label = createHud("Health", 290, 32, UDim2.new(0.5, 0, 1, -78))
    local bar = Instance.new("Frame")
    bar.BorderSizePixel = 0
    bar.Position = UDim2.new(0, 0, 1, -3)
    bar.Size = UDim2.new(1, 0, 0, 3)
    bar.BackgroundColor3 = Color3.fromRGB(85, 210, 140)
    bar.Parent = label
    addInlineBind(Box:AddToggle("UltraHealthHUD", {Text = "Enable", Default = false, Callback = function(on) gui.Enabled = on end}), "BindUltraHealthHUD", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraHealthHUD"})
    local elapsed = 0
    connect(RunService.Heartbeat, function(dt)
        if not gui.Enabled then return end
        elapsed += dt
        if elapsed < 0.1 then return end
        elapsed = 0
        local hum = getHum()
        if not hum then label.Text = "Health: waiting for character" bar.Visible = false return end
        local hp, maximum = hum.Health, hum.MaxHealth
        if hp == math.huge or maximum == math.huge then
            label.Text = "Health: infinite / non-finite"
            bar.Visible = false
            return
        end
        local ratio = maximum > 0 and math.clamp(hp / maximum, 0, 1) or 0
        label.Text = ("Health  %.0f / %.0f"):format(hp, maximum)
        bar.Visible = true
        bar.Size = UDim2.new(ratio, 0, 0, 3)
        bar.BackgroundColor3 = Color3.fromRGB(240, 85, 100):Lerp(Color3.fromRGB(85, 210, 140), ratio)
    end)
end
--##### [BLOCK: HEALTH HUD] END #####

--##### [BLOCK: LOCAL AUDIO CONTROL] START #####
do
    local Box = AddBox(Tabs.Misc, "Local Audio Control", "volume-2")
    local soundService = game:GetService("SoundService")
    -- Roblox has no SoundService.Volume: use a private SoundGroup instead.
    local group = Instance.new("SoundGroup")
    group.Name = "ClaudeHub_LocalAudio"
    group.Parent = soundService
    local saved = {}
    local function route(obj)
        if not obj:IsA("Sound") or saved[obj] ~= nil then return end
        -- Preserve existing SoundGroups (effects / nested mix) rather than
        -- silently replacing the experience's audio routing.
        if obj.SoundGroup == nil then
            saved[obj] = false
            obj.SoundGroup = group
        end
    end
    local function restore()
        for sound in pairs(saved) do
            if sound.Parent and sound.SoundGroup == group then sound.SoundGroup = nil end
        end
        table.clear(saved)
    end
    addInlineBind(Box:AddToggle("UltraAudioControl", {Text = "Enable", Default = false, Callback = function(on)
        if on then for _, obj in ipairs(game:GetDescendants()) do route(obj) end else restore() end
    end}), "BindUltraAudioControl", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraAudioControl"})
    Box:AddSlider("UltraAudioVolume", {Text = "Ungrouped sound volume (%)", Default = 50, Min = 0, Max = 100, Rounding = 0,
        Callback = function(value) group.Volume = value / 100 end})
    group.Volume = Options.UltraAudioVolume.Value / 100
    Box:AddLabel("Local only. Controls legacy Sounds without a SoundGroup; grouped audio and AudioPlayer are left unchanged.", true)
    connect(game.DescendantAdded, function(obj)
        if Toggles.UltraAudioControl.Value then route(obj) end
    end)
    onCleanup(function() restore() group:Destroy() end)
end
--##### [BLOCK: LOCAL AUDIO CONTROL] END #####

--##### [BLOCK: HIDE OWN ACCESSORIES] START #####
do
    local Box = AddBox(Tabs.Visual, "Hide Own Accessories", "shirt")
    local saved, elapsed = {}, 1
    local renderName = "ClaudeHub_Accessories_" .. HttpService:GenerateGUID(false)
    local function restore()
        for part, transparency in pairs(saved) do
            if part.Parent then part.LocalTransparencyModifier = transparency end
        end
        table.clear(saved)
    end
    addInlineBind(Box:AddToggle("UltraHideAccessories", {Text = "Hide locally", Default = false,
        Callback = function(on) if on then elapsed = 1 else restore() end end}), "BindUltraHideAccessories", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraHideAccessories"})
    Box:AddLabel("Hides your own accessory parts on this client only. Does not remove accessories.", true)
    connect(LocalPlayer.CharacterAdded, function() restore() elapsed = 1 end)
    -- Discover parts at 4 Hz, but apply after the standard camera every
    -- frame so Roblox's first-person transparency controller cannot flicker them.
    RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
        if not Toggles.UltraHideAccessories.Value then return end
        local char = getChar()
        if not char then return end
        elapsed += dt
        if elapsed >= 0.25 then
            elapsed = 0
            for _, accessory in ipairs(char:GetChildren()) do
                if accessory:IsA("Accessory") then
                    for _, part in ipairs(accessory:GetDescendants()) do
                        if part:IsA("BasePart") and saved[part] == nil then
                            saved[part] = part.LocalTransparencyModifier
                        end
                    end
                end
            end
        end
        for part in pairs(saved) do
            if part.Parent then part.LocalTransparencyModifier = 1 else saved[part] = nil end
        end
    end)
    onCleanup(function() RunService:UnbindFromRenderStep(renderName) restore() end)
end
--##### [BLOCK: HIDE OWN ACCESSORIES] END #####

--##### [BLOCK: JUMP COUNTER] START #####
do
    local Box = AddBox(Tabs.Misc, "Jump Counter", "arrow-up-0-1")
    local count, trackedHum, stateConnection = 0, nil, nil
    local label = Box:AddLabel("Jumps: 0")
    local function detach()
        if stateConnection then stateConnection:Disconnect() stateConnection = nil end
        trackedHum = nil
    end
    addInlineBind(Box:AddToggle("UltraJumpCounter", {Text = "Count jumps", Default = false,
        Callback = function(on) if not on then detach() end end}), "BindUltraJumpCounter", {Default = "None", Mode = "Toggle", SyncToggleState = true, NoUI = true, Text = "UltraJumpCounter"})
    Box:AddButton({Text = "Reset count", Func = function() count = 0 label:SetText("Jumps: 0") end})
    Box:AddLabel("Counts Humanoid transitions to Jumping while enabled; keeps the total across respawns.", true)
    connect(RunService.Heartbeat, function()
        if not Toggles.UltraJumpCounter.Value then return end
        local hum = getHum()
        if hum == trackedHum then return end
        detach()
        if not hum then return end
        trackedHum = hum
        stateConnection = hum.StateChanged:Connect(function(_, newState)
            if newState == Enum.HumanoidStateType.Jumping then
                count += 1
                label:SetText("Jumps: " .. count)
            end
        end)
    end)
    onCleanup(detach)
end
--##### [BLOCK: JUMP COUNTER] END #####
