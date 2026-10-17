-- ClaudeHub JJS v0.2.1 | Ordinary Obsidian (deividcomsono, MIT).
-- Auto Block adapted from Zorcex/JJS-Script/Auto-Blocking.lua.
-- Original author: Zorcex. Repository declares no license; see THIRD_PARTY_NOTICES.txt.
-- https://github.com/Zorcex/JJS-Script/blob/main/Auto-Blocking.lua
local VERSION = "0.2.1"
local env = getgenv and getgenv() or _G
local KEY = "__ClaudeHubJJS"
if env[KEY] and not env[KEY].Unloaded then
    env[KEY]:Notify("ClaudeHub JJS is already open. RightControl toggles the menu.", 4)
    return env[KEY]
end
assert(game.GameId == 3508322461, "ClaudeHub JJS: open Jujutsu Shenanigans first")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local function download(path)
    local source = game:HttpGet(repo .. path)
    assert(type(source) == "string" and #source > 0, "Empty Obsidian download: " .. path)
    local chunk, err = loadstring(source, "@Obsidian/" .. path)
    assert(chunk, tostring(err))
    return chunk()
end
local Library = download("Library.lua")
env[KEY] = Library
env.Library = Library
local Options, Toggles = Library.Options, Library.Toggles
local ready, closed, focused = false, false, true
local started = os.clock()
local connections, pools, markers = {}, {}, {}
local hud, markerFolder
local cameraState, mouseState
local freePosition, freePitch, freeYaw
local freeMoving = false
local lastJump = 0
local combatTarget, smoothCamera, controlsState
local blockConnections = {}
local hookedRemotes = {}
local blockActivated, blockDeactivated, activeBlock
local stopAutoBlock, doBlock, hookRemote
local lastBlockError = -math.huge
local serverRows, serverMap, serverCursor = {}, {}, nil
local serversBusy, teleportBusy, serverGeneration = false, false, 0
local serverStatus, defenseStatus, targetStatus
local requestHTTP = (type(request)=="function" and request) or (type(http_request)=="function" and http_request)
    or (type(syn)=="table" and syn.request) or (type(http)=="table" and http.request)
local playerNames = {}
local freeAction = "ClaudeHubJJS_Freecam"
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end
local function character(p)
    local c = p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then return c, h, r end
    return nil, nil, nil
end
local function notify(text) if not closed then Library:Notify(text, 4) end end
local function on(id) return Toggles[id] and Toggles[id].Value == true end
local function val(id, default)
    local o = Options[id]
    if o and o.Value ~= nil then return o.Value end
    return default
end
local function restore(pool)
    for object, fields in pairs(pool) do
        for name, data in pairs(fields) do
            pcall(function() if object[name] == data.Applied then object[name] = data.Base end end)
        end
    end
    table.clear(pool)
end
local function override(pool, object, name, value)
    local fields = pool[object]
    if not fields then fields = {}; pool[object] = fields end
    local data = fields[name]
    if not data then data = {Base = object[name]}; fields[name] = data
    elseif object[name] ~= data.Applied then data.Base = object[name] end
    data.Applied = value
    if object[name] ~= value then object[name] = value end
end
for _, name in ipairs({"Speed", "Jump", "FOV", "Facing", "Light"}) do pools[name] = {} end
local function clearMarker(p)
    local m = markers[p]
    if m then m.Highlight:Destroy(); m.Gui:Destroy(); markers[p] = nil end
end
local function clearMarkers()
    for p in pairs(markers) do clearMarker(p) end
end
local function releaseMouse()
    if mouseState then
        if UIS.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition then UIS.MouseBehavior = mouseState.Behavior end
        if UIS.MouseIconEnabled == false then UIS.MouseIconEnabled = mouseState.Icon end
        mouseState = nil
    end
end
local function releaseCamera()
    CAS:UnbindAction(freeAction)
    freeMoving = false
    if controlsState then
        pcall(function() if controlsState.WasEnabled then controlsState.Controls:Enable() end end)
        controlsState = nil
    end
    restore(pools.Jump)
    releaseMouse()
    if cameraState then
        local s = cameraState
        pcall(function()
            if s.Camera.CameraType == s.OwnedType then
                s.Camera.CameraType = s.Type
                if s.Mode == "Free" then s.Camera.CFrame, s.Camera.Focus = s.CFrame, s.Focus end
                local _, h = character(player)
                s.Camera.CameraSubject = s.Subject and s.Subject.Parent and s.Subject or h
            end
        end)
        cameraState = nil
    end
end
local function menuBusy()
    return not focused or UIS:GetFocusedTextBox() ~= nil or Library.Toggled == true
end
local function startCamera(mode)
    releaseCamera()
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local subject
    if mode == "Spectate" then
        local target = playerNames[val("SpectatePlayer", "")]
        if target then local _, targetHumanoid = character(target); subject = targetHumanoid end
        if not subject then return false end
    end
    cameraState = {Camera=camera, Mode=mode, Type=camera.CameraType, Subject=camera.CameraSubject,
        CFrame=camera.CFrame, Focus=camera.Focus, OwnedType=mode == "Free" and Enum.CameraType.Scriptable or Enum.CameraType.Custom}
    camera.CameraType = cameraState.OwnedType
    if mode == "Spectate" then camera.CameraSubject = subject
    else
        freePosition = camera.CFrame.Position
        freePitch, freeYaw = camera.CFrame:ToOrientation()
        pcall(function()
            local scripts = player:FindFirstChild("PlayerScripts")
            local module = scripts and scripts:FindFirstChild("PlayerModule")
            if module then
                local controls = require(module):GetControls()
                if controls.controlsEnabled == true then
                    controlsState = {Controls=controls, WasEnabled=true}
                    controls:Disable()
                end
            end
        end)
        CAS:BindActionAtPriority(freeAction, function()
            return Enum.ContextActionResult.Sink
        end, false, 10000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.LeftShift)
    end
    smoothCamera = nil
    return true
end
local function findBlockRemotes()
    local path={"Knit","Knit","Services","BlockService","RE"}
    local current=ReplicatedStorage
    for _,name in ipairs(path) do
        current=current:FindFirstChild(name)
        if not current then return nil,nil,"Missing: ReplicatedStorage." .. table.concat(path,".") end
    end
    local activated=current:FindFirstChild("Activated")
    local deactivated=current:FindFirstChild("Deactivated")
    if not activated or not activated:IsA("RemoteEvent") or not deactivated or not deactivated:IsA("RemoteEvent") then
        return nil,nil,"Missing BlockService RE.Activated / RE.Deactivated RemoteEvents"
    end
    return activated,deactivated
end
local function releaseDefense()
    if activeBlock then
        local state=activeBlock
        activeBlock=nil
        -- Use the exact remote which started the block, even if the character changed.
        local ok,err=pcall(function() state.Release:FireServer() end)
        if not ok and not closed and os.clock()-lastBlockError>3 then
            lastBlockError=os.clock();notify("Block release failed: " .. tostring(err))
        end
    end
    if not on("FaceTarget") then restore(pools.Facing) end
end
stopAutoBlock=function()
    releaseDefense()
    for _,c in ipairs(blockConnections) do c:Disconnect() end
    table.clear(blockConnections)
    table.clear(hookedRemotes)
    blockActivated,blockDeactivated=nil,nil
end
local function resetCombat()
    releaseDefense()
    restore(pools.Facing)
    combatTarget=nil
end
local function validEnemy(p, origin, maxDistance, visible)
    if p == player then return end
    local c,h,r = character(p)
    if not c or (on("CombatTeamFilter") and player.Team ~= nil and p.Team == player.Team) then return end
    local distance = (r.Position-origin).Magnitude
    if distance > maxDistance then return end
    if visible then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {player.Character, markerFolder}
        local hit = workspace:Raycast(origin, r.Position-origin, params)
        if hit and not hit.Instance:IsDescendantOf(c) then return end
    end
    return c,h,r,distance
end
-- Zorcex Auto-Blocking.lua: faceTarget, doBlock and hookRemote adapted to ClaudeHub.
local function faceBlockTarget(targetHrp)
    local _,hum,root=character(player)
    if not root or not targetHrp or not targetHrp.Parent or root.Anchored or hum.Sit then return false end
    local position=Vector3.new(targetHrp.Position.X,root.Position.Y,targetHrp.Position.Z)
    if (position-root.Position).Magnitude<0.05 then return false end
    override(pools.Facing,hum,"AutoRotate",false)
    root.CFrame=CFrame.lookAt(root.Position,position)
    return true
end
doBlock=function(enemyHrp)
    if activeBlock or not ready or not on("AutoBlock") or menuBusy() or on("Freecam") or on("Spectate") then return end
    if not blockActivated or not blockDeactivated then return end
    if not blockActivated:IsDescendantOf(ReplicatedStorage) or not blockDeactivated:IsDescendantOf(ReplicatedStorage) then
        Toggles.AutoBlock:SetValue(false);notify("BlockService was removed; Auto Block disabled");return
    end
    if not faceBlockTarget(enemyHrp) then return end
    local ok,err=pcall(function() blockActivated:FireServer() end)
    if not ok then
        restore(pools.Facing)
        Toggles.AutoBlock:SetValue(false);notify("Block activation failed: " .. tostring(err));return
    end
    activeBlock={Target=enemyHrp, Release=blockDeactivated, Expires=os.clock()+val("BlockHold",0.5)}
end
hookRemote=function(remote)
    if not remote:IsA("RemoteEvent") or hookedRemotes[remote] then return end
    if remote==blockActivated or remote==blockDeactivated or remote.Name:lower():find("emote") then return end
    hookedRemotes[remote]=remote.OnClientEvent:Connect(function(...)
        if not ready or not on("AutoBlock") or activeBlock or menuBusy() or on("Freecam") or on("Spectate") then return end
        local myChar,_,myRoot=character(player)
        if not myRoot then return end
        local arguments=table.pack(...)
        for i=1,arguments.n do
            local arg=arguments[i]
            if typeof(arg)~="Instance" then continue end
            local c=arg:IsA("Model") and arg or arg:FindFirstAncestorOfClass("Model")
            if not c or c==myChar then continue end
            local root=c:FindFirstChild("HumanoidRootPart")
            local humanoid=c:FindFirstChildOfClass("Humanoid")
            if not root or not humanoid or humanoid.Health<=0 or not root:IsA("BasePart") then continue end
            if (myRoot.Position-root.Position).Magnitude>val("DefenseRange",10) then continue end
            local enemy=Players:GetPlayerFromCharacter(c)
            if enemy and not validEnemy(enemy,myRoot.Position,val("DefenseRange",10),on("CombatWallCheck")) then continue end
            if not enemy and on("CombatWallCheck") then
                local params=RaycastParams.new()
                params.FilterType=Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances={myChar,markerFolder}
                local hit=workspace:Raycast(myRoot.Position,root.Position-myRoot.Position,params)
                if hit and not hit.Instance:IsDescendantOf(c) then continue end
            end
            doBlock(root)
            if activeBlock then return end
        end
    end)
    table.insert(blockConnections,hookedRemotes[remote])
end
local function startAutoBlock()
    stopAutoBlock()
    local activated,deactivated,err=findBlockRemotes()
    if not activated then return false,err end
    blockActivated,blockDeactivated=activated,deactivated
    table.insert(blockConnections,ReplicatedStorage.DescendantAdded:Connect(hookRemote))
    -- Subscribe first; the set prevents duplicate connections if a remote arrives during the scan.
    for _,object in ipairs(ReplicatedStorage:GetDescendants()) do hookRemote(object) end
    return true
end
local function selectTarget()
    local _,_,root = character(player)
    if not root then return end
    local range = val("TargetRange",50)
    local visible = on("CombatWallCheck")
    local mode = val("TargetMode","Nearest")
    if mode == "Selected" then
        local p = playerNames[val("CombatPlayer","")]
        if p and validEnemy(p, root.Position, range, visible) then return p end
        return
    end
    local best, score = nil, math.huge
    local camera = workspace.CurrentCamera
    for _,p in ipairs(Players:GetPlayers()) do
        local _,_,r,distance = validEnemy(p, root.Position, range, visible)
        if r then
            local current = distance
            if mode == "Crosshair" then
                if not camera then continue end
                local screen,inView = camera:WorldToViewportPoint(r.Position)
                if not inView or screen.Z <= 0 then continue end
                current = (Vector2.new(screen.X,screen.Y)-camera.ViewportSize/2).Magnitude
            end
            if current < score then best,score = p,current end
        end
    end
    return best
end
local function jumpNow()
    if not ready or not on("InfiniteJump") or on("Freecam") or not focused or UIS:GetFocusedTextBox() or os.clock()-lastJump < 0.12 then return end
    local _,h,r = character(player)
    if not h or r.Anchored or h.Sit then return end
    lastJump = os.clock()
    h:ChangeState(Enum.HumanoidStateType.Jumping)
    local velocity = r.AssemblyLinearVelocity
    r.AssemblyLinearVelocity = Vector3.new(velocity.X, val("JumpVelocity",50), velocity.Z)
end
local function cleanup()
    if closed then return end
    closed, ready = true, false
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    RunService:UnbindFromRenderStep("ClaudeHubJJS_Camera")
    releaseCamera()
    stopAutoBlock()
    resetCombat()
    serverGeneration += 1
    for _, pool in pairs(pools) do restore(pool) end
    clearMarkers()
    if hud then hud:Destroy() end
    if markerFolder then markerFolder:Destroy() end
    if env[KEY] == Library then env[KEY] = nil end
    if env.Library == Library then env.Library = nil end
end
Library:OnUnload(cleanup)
local success, failure = xpcall(function()
    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = false
    local Window = Library:CreateWindow({Title="ClaudeHub | JJS", Footer="JJS v" .. VERSION .. " | Obsidian",
        Center=true, AutoShow=true, Resizable=true, NotifySide="Right", ShowCustomCursor=true})
    local Tabs = {
        Home=Window:AddTab("Home", "house"),
        Character=Window:AddTab("Character", "user"),
        Visuals=Window:AddTab("Visuals", "eye"),
        Camera=Window:AddTab("Camera", "camera"),
        Combat=Window:AddTab("Combat", "swords"),
        Servers=Window:AddTab("Servers", "server"),
        Settings=Window:AddTab("Settings", "settings"),
    }
    local function toggle(box, id, text, key)
        local t = box:AddToggle(id, {Text=text, Default=false})
        if key then
            t:AddKeyPicker(id .. "Bind", {Default=key, Text=text, Mode="Toggle", SyncToggleState=false, NoUI=true})
            local picker = Options[id .. "Bind"]
            picker.SyncToggleState, picker.Toggled = true, t.Value
            picker:Update()
        end
        return t
    end
    local function slider(box, id, text, default, low, high, rounding)
        box:AddSlider(id, {Text=text, Default=default, Min=low, Max=high, Rounding=rounding or 0})
    end
    local function action(box, text, fn, key, id)
        local button = box:AddButton({Text=text, Func=function()
            if ready and focused and UIS:GetFocusedTextBox() == nil then fn() end
        end})
        if key then
            button:AddKeyPicker(id, {Default=key, Mode="Press", NoUI=true, Text=text})
        end
    end
    local home = Tabs.Home:AddLeftGroupbox("Profile", "user")
    home:AddLabel(player.DisplayName .. "  @" .. player.Name)
    home:AddLabel("User ID: " .. tostring(player.UserId))
    home:AddLabel("Jujutsu Shenanigans")
    home:AddLabel("ClaudeHub v" .. VERSION)
    local sessionLabel = home:AddLabel("Session: 00:00")
    local serverLabel = home:AddLabel("Players: --")
    local info = Tabs.Home:AddRightGroupbox("Release", "info")
    info:AddLabel("Ordinary Obsidian")
    info:AddLabel("Character / Visuals / Camera / Combat / Servers")
    info:AddLabel("Gameplay features start disabled")
    info:AddLabel("No anticheat bypass")
    info:AddLabel("UI: deividcomsono (MIT)")
    info:AddLabel("Auto Block: Zorcex / JJS-Script")
    local char = Tabs.Character:AddLeftGroupbox("Movement", "footprints")
    toggle(char, "Speed", "WalkSpeed", "V")
    slider(char, "WalkSpeed", "Speed", 20, 0, 120)
    toggle(char, "InfiniteJump", "Infinite Jump", "J")
    slider(char, "JumpVelocity", "Jump Strength", 50, 20, 100)
    local hudBox = Tabs.Character:AddRightGroupbox("HUD", "monitor")
    toggle(hudBox, "HUD", "Combat HUD", "F9")
    local visuals = Tabs.Visuals:AddLeftGroupbox("Players", "users")
    toggle(visuals, "ESP", "Player ESP", "H")
    toggle(visuals, "ESPNames", "Names")
    toggle(visuals, "ESPHealth", "Health")
    toggle(visuals, "ESPDistance", "Distance")
    toggle(visuals, "TeamFilter", "Hide Teammates")
    visuals:AddLabel("Marker Color"):AddColorPicker("ESPColor", {Default=Color3.fromRGB(150,110,255), Title="Player ESP"})
    local visualSettings = Tabs.Visuals:AddRightGroupbox("Rendering", "palette")
    slider(visualSettings, "ESPRange", "Render Distance", 500, 50, 2000)
    slider(visualSettings, "ESPFill", "Fill Transparency", 0.8, 0, 1, 2)
    slider(visualSettings, "ESPText", "Text Size", 14, 10, 24)
    toggle(visualSettings, "Fullbright", "Fullbright")
    toggle(visualSettings, "NoFog", "Remove Fog")
    local cam = Tabs.Camera:AddLeftGroupbox("Camera", "camera")
    toggle(cam, "CustomFOV", "Custom FOV")
    slider(cam, "FOV", "Field of View", 80, 40, 120)
    toggle(cam, "AntiShake", "Anti Camera Shake")
    slider(cam, "Stabilize", "Stabilization", 70, 10, 95)
    toggle(cam, "Freecam", "Freecam", "F6")
    slider(cam, "FreecamSpeed", "Freecam Speed", 32, 5, 150)
    local watch = Tabs.Camera:AddRightGroupbox("Spectate", "users")
    watch:AddDropdown("SpectatePlayer", {Text="Player", Values={}, AllowNull=true})
    toggle(watch, "Spectate", "Spectate Player", "F7")
    local function refreshPlayers()
        local names = {}
        table.clear(playerNames)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then
                local name = p.DisplayName .. " (@" .. p.Name .. ")"
                table.insert(names, name); playerNames[name] = p
            end
        end
        table.sort(names)
        if Options.CombatPlayer then
            local combatSelected=Options.CombatPlayer.Value
            Options.CombatPlayer:SetValues(names)
            if combatSelected and not playerNames[combatSelected] then Options.CombatPlayer:SetValue(nil) end
        end
        local selected = Options.SpectatePlayer.Value
        Options.SpectatePlayer:SetValues(names)
        if selected and not playerNames[selected] then
            Options.SpectatePlayer:SetValue(nil)
            if on("Spectate") then Toggles.Spectate:SetValue(false) end
        end
    end
    action(watch, "Refresh Players", refreshPlayers)
    local targetBox = Tabs.Combat:AddLeftGroupbox("Targeting", "crosshair")
    targetBox:AddDropdown("TargetMode", {Text="Target Mode", Values={"Nearest","Crosshair","Selected"}, Default=1})
    targetBox:AddDropdown("CombatPlayer", {Text="Selected Player", Values={}, AllowNull=true})
    toggle(targetBox, "FaceTarget", "Face Target (Gamepad Style)", "X")
    slider(targetBox, "TargetRange", "Target Range", 50, 5, 200)
    slider(targetBox, "TurnSpeed", "Turn Speed", 25, 5, 60)
    slider(targetBox, "Prediction", "Movement Prediction", 0, 0, 0.25, 2)
    toggle(targetBox, "CombatWallCheck", "Wall Check")
    toggle(targetBox, "CombatTeamFilter", "Hide Teammates")
    toggle(targetBox, "TargetHighlight", "Highlight Target")
    targetStatus = targetBox:AddLabel("Target: none")
    local defense = Tabs.Combat:AddRightGroupbox("Defense | Zorcex", "shield")
    toggle(defense,"AutoBlock","Auto Block (Zorcex)","B")
    slider(defense,"DefenseRange","Block Distance",10,3,30)
    slider(defense,"BlockHold","Block Duration",0.5,0.1,1,2)
    defense:AddLabel("Auto Block author: Zorcex")
    defense:AddLabel("Auto Counter: source not available")
    defenseStatus=defense:AddLabel("Defense: off")
    action(defense,"Check Block API",function()
        local activated,_,err=findBlockRemotes()
        defenseStatus:SetText(activated and "Block API: available" or "Block API: unavailable")
        notify(activated and "Zorcex BlockService remotes found" or tostring(err))
    end)
    local servers = Tabs.Servers:AddLeftGroupbox("Public Servers", "server")
    servers:AddDropdown("ServerSort", {Text="Sort", Values={"Players (low)","Ping (low)"}, Default=1})
    servers:AddDropdown("ServerChoice", {Text="Server", Values={}, AllowNull=true})
    serverStatus = servers:AddLabel("Servers: not loaded")
    local serverActions = Tabs.Servers:AddRightGroupbox("Connection", "network")
    serverActions:AddLabel("Job: " .. (game.JobId ~= "" and game.JobId or "unavailable"))
    serverActions:AddInput("JobID", {Text="Job ID", Default="", Finished=true})
    local function teleport(job)
        if teleportBusy then notify("Teleport already in progress"); return end
        if type(job) ~= "string" or #job < 1 or #job > 100 or not job:match("^[%w%-]+$") then notify("Invalid Job ID"); return end
        teleportBusy = true
        releaseDefense()
        local ok,err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId,job,player) end)
        if not ok then teleportBusy=false;notify("Teleport failed: " .. tostring(err));return end
        notify("Teleport requested")
        task.delay(15,function() if not closed then teleportBusy=false end end)
    end
    local function displayServers()
        local sorting = val("ServerSort","Players (low)")
        table.sort(serverRows,function(a,b)
            local aa = sorting == "Ping (low)" and (tonumber(a.ping) or math.huge) or a.playing
            local bb = sorting == "Ping (low)" and (tonumber(b.ping) or math.huge) or b.playing
            return aa == bb and a.id < b.id or aa < bb
        end)
        local labels = {}
        table.clear(serverMap)
        for _,row in ipairs(serverRows) do
            local label = string.format("%d/%d | %s ms | %s",row.playing,row.maxPlayers,tostring(row.ping or "?"),row.id)
            table.insert(labels,label);serverMap[label]=row.id
        end
        Options.ServerChoice:SetValues(labels)
        serverStatus:SetText(string.format("Servers: %d%s",#labels,serverCursor and " | more available" or ""))
    end
    local function fetchServers(reset)
        if serversBusy then notify("Server list is already loading"); return end
        if not reset and not serverCursor then notify("No next page"); return end
        serversBusy=true
        serverGeneration+=1
        local generation=serverGeneration
        local cursor = not reset and serverCursor or nil
        serverStatus:SetText("Loading public servers...")
        task.spawn(function()
            local ok,result=pcall(function()
                local url="https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Asc&limit=100"
                if cursor then url ..= "&cursor=" .. HttpService:UrlEncode(cursor) end
                local body
                if requestHTTP then
                    local response=requestHTTP({Url=url,Method="GET"})
                    assert(response and (response.StatusCode==200 or response.Success==true), "HTTP " .. tostring(response and response.StatusCode))
                    body=response.Body
                else body=game:HttpGet(url) end
                assert(type(body)=="string" and #body < 2000000,"Invalid server response")
                local data=HttpService:JSONDecode(body)
                assert(type(data)=="table" and type(data.data)=="table","Invalid server data")
                return data
            end)
            if closed or generation~=serverGeneration then return end
            serversBusy=false
            if not ok then serverStatus:SetText("Server list unavailable");notify("Server list: " .. tostring(result));return end
            if reset then table.clear(serverRows);Options.ServerChoice:SetValue(nil) end
            local known={}
            for _,row in ipairs(serverRows) do known[row.id]=true end
            for _,row in ipairs(result.data) do
                if type(row)=="table" and type(row.id)=="string" and type(row.playing)=="number" and type(row.maxPlayers)=="number"
                    and row.id~=game.JobId and row.playing<row.maxPlayers and not known[row.id] and #serverRows<500 then
                    table.insert(serverRows,row);known[row.id]=true
                end
            end
            serverCursor=type(result.nextPageCursor)=="string" and result.nextPageCursor or nil
            if #serverRows>=500 then serverCursor=nil end
            displayServers()
        end)
    end
    action(servers,"Refresh Servers",function() fetchServers(true) end)
    action(servers,"Load Next Page",function() fetchServers(false) end)
    action(servers,"Join Selected Server",function()
        local job=serverMap[val("ServerChoice","")]
        if not job then notify("Select a server first");return end
        teleport(job)
    end)
    action(servers,"Hop to First Listed",function()
        if not serverRows[1] then notify("Load public servers first");return end
        teleport(serverRows[1].id)
    end)
    action(serverActions,"Rejoin",function() teleport(game.JobId) end)
    action(serverActions,"Join Job ID",function() teleport(tostring(val("JobID",""))) end)
    action(serverActions,"Copy Job ID",function()
        if type(setclipboard)~="function" then notify("Clipboard is not supported");return end
        setclipboard(game.JobId);notify("Job ID copied")
    end)
    Options.ServerSort:OnChanged(displayServers)
    connect(TeleportService.TeleportInitFailed,function(p,_,message)
        if p==player then teleportBusy=false;notify("Teleport failed: " .. tostring(message)) end
    end)
    local menu = Tabs.Settings:AddLeftGroupbox("Interface", "settings")
    menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {Default="RightControl", NoUI=true, Text="Menu"})
    Library.ToggleKeybind = Options.MenuKeybind
    action(menu, "Unload", function() Library:Unload() end)
    hud = Instance.new("ScreenGui")
    hud.Name, hud.ResetOnSpawn, hud.ZIndexBehavior = "ClaudeHubJJS_HUD", false, Enum.ZIndexBehavior.Sibling
    hud.DisplayOrder = 20
    hud.Parent = player:WaitForChild("PlayerGui")
    local targetMarker = Instance.new("Highlight", hud)
    targetMarker.Name, targetMarker.Enabled = "CombatTarget", false
    targetMarker.FillColor, targetMarker.OutlineColor = Color3.fromRGB(255,90,100), Color3.fromRGB(255,170,70)
    targetMarker.FillTransparency, targetMarker.DepthMode = 0.8, Enum.HighlightDepthMode.AlwaysOnTop
    local frame = Instance.new("Frame")
    frame.Name, frame.Size, frame.Position = "DraggableHUD", UDim2.fromOffset(330,112), UDim2.fromOffset(24,110)
    frame.BackgroundColor3, frame.BackgroundTransparency = Color3.fromRGB(17,15,25), 0.12
    frame.BorderSizePixel, frame.Active, frame.Visible = 0, true, false
    frame.Parent = hud
    local corner = Instance.new("UICorner", frame); corner.CornerRadius = UDim.new(0,8)
    local stroke = Instance.new("UIStroke", frame); stroke.Color = Color3.fromRGB(140,95,235); stroke.Transparency = 0.3
    local text = Instance.new("TextLabel", frame)
    text.Size, text.Position = UDim2.new(1,-20,1,-12), UDim2.fromOffset(10,6)
    text.BackgroundTransparency, text.TextColor3 = 1, Color3.fromRGB(225,220,240)
    text.Font, text.TextSize = Enum.Font.Code, 14
    text.TextXAlignment, text.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    text.Text, text.Active = "CLAUDEHUB  |  JJS", false
    local dragInput, dragStart, dragOrigin
    local function clampHUD(x, y)
        local camera = workspace.CurrentCamera
        local size = camera and camera.ViewportSize or Vector2.new(1280,720)
        frame.Position = UDim2.fromOffset(math.clamp(x,0,math.max(0,size.X-frame.AbsoluteSize.X)),
            math.clamp(y,0,math.max(0,size.Y-frame.AbsoluteSize.Y-36)))
    end
    action(hudBox, "Reset HUD Position", function() clampHUD(24,110) end)
    connect(frame.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragInput, dragStart, dragOrigin = input, input.Position, frame.AbsolutePosition
        end
    end)
    connect(UIS.InputChanged, function(input)
        if dragInput and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            clampHUD(dragOrigin.X + delta.X, dragOrigin.Y + delta.Y)
        end
        if ready and on("Freecam") and cameraState and mouseState and input.UserInputType == Enum.UserInputType.MouseMovement and not menuBusy() then
            freeYaw -= input.Delta.X * 0.003
            freePitch = math.clamp(freePitch - input.Delta.Y * 0.003, -1.5, 1.5)
        end
    end)
    connect(UIS.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragInput = nil end
    end)
    connect(UIS.WindowFocusReleased, function() focused = false; dragInput = nil; freeMoving = false; releaseMouse(); resetCombat() end)
    connect(UIS.WindowFocused, function() focused = true end)
    markerFolder = Instance.new("Folder", workspace); markerFolder.Name = "ClaudeHubJJS_Markers"
    local function updateMarkers()
        if not on("ESP") then clearMarkers(); return end
        local camera = workspace.CurrentCamera
        if not camera then clearMarkers(); return end
        local accepted, total = {}, 0
        for _, p in ipairs(Players:GetPlayers()) do
            local c, h, r = character(p)
            local distance = r and (r.Position - camera.CFrame.Position).Magnitude or math.huge
            local teammate = on("TeamFilter") and player.Team ~= nil and p.Team == player.Team
            if p ~= player and c and not teammate and distance <= val("ESPRange",500) and total < 24 then
                total += 1; accepted[p] = true
                local m = markers[p]
                if m and m.Character ~= c then clearMarker(p); m = nil end
                if not m then
                    local highlight = Instance.new("Highlight", markerFolder)
                    highlight.Name, highlight.Adornee, highlight.DepthMode = "PlayerMarker", c, Enum.HighlightDepthMode.AlwaysOnTop
                    local gui = Instance.new("BillboardGui", hud)
                    gui.Name, gui.AlwaysOnTop, gui.Size = "PlayerLabel", true, UDim2.fromOffset(240,54)
                    gui.StudsOffsetWorldSpace = Vector3.new(0,3.5,0)
                    local label = Instance.new("TextLabel", gui)
                    label.BackgroundTransparency, label.Size = 1, UDim2.fromScale(1,1)
                    label.Font, label.TextStrokeTransparency = Enum.Font.Code, 0.35
                    m = {Highlight=highlight, Gui=gui, Label=label, Character=c}; markers[p] = m
                end
                local color = val("ESPColor",Color3.fromRGB(150,110,255))
                m.Highlight.FillColor, m.Highlight.OutlineColor = color, color
                m.Highlight.FillTransparency, m.Highlight.OutlineTransparency = val("ESPFill",0.8), 0
                m.Gui.Adornee, m.Gui.MaxDistance = c:FindFirstChild("Head") or r, val("ESPRange",500)
                local parts = {}
                if on("ESPNames") then table.insert(parts, p.DisplayName) end
                if on("ESPHealth") then table.insert(parts, string.format("HP %.0f/%.0f", h.Health,h.MaxHealth)) end
                if on("ESPDistance") then table.insert(parts, string.format("%.0f studs",distance)) end
                m.Label.Text, m.Label.TextColor3, m.Label.TextSize = table.concat(parts," | "), color, val("ESPText",14)
                m.Gui.Enabled = #parts > 0
            end
        end
        for p in pairs(markers) do if not accepted[p] then clearMarker(p) end end
    end
    local function cameraToggle(id, other, mode)
        Toggles[id]:OnChanged(function()
            if not ready then return end
            if not on(id) then
                if cameraState and cameraState.Mode == mode then releaseCamera() end
                return
            end
            if on(other) then Toggles[other]:SetValue(false) end
            if mode == "Free" then
                resetCombat()
                Library:Toggle(false)
            end
            if not startCamera(mode) then Toggles[id]:SetValue(false); notify("Camera or selected player is not ready") end
        end)
    end
    cameraToggle("Freecam", "Spectate", "Free")
    cameraToggle("Spectate", "Freecam", "Spectate")
    Options.SpectatePlayer:OnChanged(function()
        if ready and on("Spectate") and not startCamera("Spectate") then Toggles.Spectate:SetValue(false) end
    end)
    Toggles.AutoBlock:OnChanged(function()
        if not ready then return end
        if not on("AutoBlock") then
            stopAutoBlock();defenseStatus:SetText("Defense: off");return
        end
        local ok,err=startAutoBlock()
        if not ok then
            Toggles.AutoBlock:SetValue(false)
            defenseStatus:SetText("Block API: unavailable")
            notify("Auto Block unavailable: " .. tostring(err))
        else defenseStatus:SetText("Defense: listening (Zorcex)") end
    end)
    Toggles.FaceTarget:OnChanged(function() if not on("FaceTarget") then restore(pools.Facing) end end)
    Toggles.AntiShake:OnChanged(function() smoothCamera=nil end)
    for id, poolName in pairs({Speed="Speed", CustomFOV="FOV"}) do
        local name = poolName
        Toggles[id]:OnChanged(function() if ready then restore(pools[name]) end end)
    end
    Toggles.ESP:OnChanged(function() if ready and not on("ESP") then clearMarkers() end end)
    for _, id in ipairs({"Fullbright", "NoFog"}) do
        Toggles[id]:OnChanged(function() if ready then restore(pools.Light) end end)
    end
    Toggles.HUD:OnChanged(function() frame.Visible = on("HUD") end)
    connect(Players.PlayerAdded, refreshPlayers)
    connect(Players.PlayerRemoving, function(p)
        clearMarker(p)
        -- PlayerRemoving fires before GetPlayers necessarily excludes the player.
        for name, target in pairs(playerNames) do
            if target == p then
                if val("SpectatePlayer", "") == name then Toggles.Spectate:SetValue(false); Options.SpectatePlayer:SetValue(nil) end
                if Options.CombatPlayer.Value==name then Options.CombatPlayer:SetValue(nil) end
                if combatTarget==p then resetCombat() end
                playerNames[name] = nil
            end
        end
        task.defer(function() if ready and not closed then refreshPlayers() end end)
    end)
    connect(player.CharacterRemoving,function() resetCombat() end)
    connect(player.CharacterAdded, function()
        if not ready then return end
        Toggles.Freecam:SetValue(false); Toggles.Spectate:SetValue(false)
        restore(pools.Speed); resetCombat(); smoothCamera=nil
    end)
    connect(UIS.JumpRequest,jumpNow)
    connect(UIS.InputBegan,function(input,processed)
        if input.KeyCode==Enum.KeyCode.Space and not processed then jumpNow() end
    end)
    local function updateCombat(dt)
        if menuBusy() or on("Freecam") or on("Spectate") then
            resetCombat();targetMarker.Enabled=false
            if defenseStatus then defenseStatus:SetText("Defense: paused") end
            return
        end
        local _,hum,root=character(player)
        if not root then resetCombat();targetMarker.Enabled=false;return end
        local active=on("FaceTarget") or on("AutoBlock") or on("TargetHighlight") or on("HUD")
        if not active then resetCombat();targetMarker.Enabled=false;return end
        combatTarget=selectTarget()
        local tc,_,tr
        if combatTarget then tc,_,tr=character(combatTarget) end
        for object in pairs(pools.Facing) do if object~=hum then restore(pools.Facing);break end end
        if activeBlock then
            if os.clock()>=activeBlock.Expires or not activeBlock.Target.Parent then releaseDefense()
            elseif not faceBlockTarget(activeBlock.Target) then releaseDefense() end
        end
        if tr and on("FaceTarget") and not activeBlock and not root.Anchored and not hum.Sit then
            override(pools.Facing,hum,"AutoRotate",false)
            local aim=tr.Position+tr.AssemblyLinearVelocity*val("Prediction",0)
            local flat=Vector3.new(aim.X,root.Position.Y,aim.Z)
            if (flat-root.Position).Magnitude>0.05 then
                root.CFrame=root.CFrame:Lerp(CFrame.lookAt(root.Position,flat),1-math.exp(-val("TurnSpeed",25)*dt))
            end
        elseif not activeBlock and next(pools.Facing) then restore(pools.Facing) end
        targetMarker.Adornee=tc
        targetMarker.Enabled=tc~=nil and on("TargetHighlight")
        if on("AutoBlock") and blockActivated then
            if not blockActivated:IsDescendantOf(ReplicatedStorage) or not blockDeactivated:IsDescendantOf(ReplicatedStorage) then
                Toggles.AutoBlock:SetValue(false);notify("BlockService disappeared; Auto Block disabled")
            else defenseStatus:SetText(activeBlock and "Defense: blocking (Zorcex)" or "Defense: listening (Zorcex)") end
        elseif not on("AutoBlock") then defenseStatus:SetText("Defense: off") end
    end
    local accumulator = 0
    connect(RunService.Heartbeat, function(dt)
        if not ready then return end
        local _, h, r = character(player)
        -- Old character references must not survive respawn or removal.
        for object in pairs(pools.Speed) do if object ~= h then restore(pools.Speed); break end end
        if h and on("Speed") and not on("Freecam") then
            override(pools.Speed,h,"WalkSpeed",val("WalkSpeed",20))
        elseif next(pools.Speed) then restore(pools.Speed) end
        updateCombat(dt)
        if on("Fullbright") then
            override(pools.Light,Lighting,"Brightness",2)
            override(pools.Light,Lighting,"Ambient",Color3.fromRGB(180,180,180))
            override(pools.Light,Lighting,"OutdoorAmbient",Color3.fromRGB(180,180,180))
            override(pools.Light,Lighting,"GlobalShadows",false)
        end
        if on("NoFog") then
            override(pools.Light,Lighting,"FogStart",100000)
            override(pools.Light,Lighting,"FogEnd",100000)
        end
        accumulator += dt
        if accumulator < 0.15 then return end
        accumulator = 0
        updateMarkers()
        local session = math.floor(os.clock()-started)
        sessionLabel:SetText(string.format("Session: %02d:%02d",math.floor(session/60),session%60))
        serverLabel:SetText(string.format("Players: %d / %d",#Players:GetPlayers(),Players.MaxPlayers))
        targetStatus:SetText("Target: " .. (combatTarget and combatTarget.DisplayName or "none"))
        if on("HUD") then
            local speed = r and Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude or 0
            local pos = r and r.Position or Vector3.zero
            local name=combatTarget and combatTarget.DisplayName or "none"
            text.Text = string.format("CLAUDEHUB  |  JJS v%s\nSpeed: %.1f studs/s  |  HP: %.0f\nXYZ: %.0f  %.0f  %.0f\nTarget: %s",VERSION,speed,h and h.Health or 0,pos.X,pos.Y,pos.Z,name)
            clampHUD(frame.Position.X.Offset,frame.Position.Y.Offset)
        end
    end)
    RunService:BindToRenderStep("ClaudeHubJJS_Camera", Enum.RenderPriority.Last.Value + 100, function(dt)
        if not ready then return end
        local camera = workspace.CurrentCamera
        if cameraState and cameraState.Camera ~= camera then
            local mode = cameraState.Mode
            releaseCamera()
            if not startCamera(mode) then
                Toggles.Freecam:SetValue(false); Toggles.Spectate:SetValue(false)
            end
        end
        for object in pairs(pools.FOV) do if object ~= camera then restore(pools.FOV); break end end
        if camera and on("CustomFOV") then override(pools.FOV,camera,"FieldOfView",val("FOV",80))
        elseif next(pools.FOV) then restore(pools.FOV) end
        if not cameraState then
            if camera and on("AntiShake") then
                local alpha=1-math.exp(-(100-val("Stabilize",70))*dt)
                smoothCamera=smoothCamera and smoothCamera:Lerp(camera.CFrame,alpha) or camera.CFrame
                camera.CFrame=smoothCamera
            else smoothCamera=nil end
            return
        end
        smoothCamera=nil
        if cameraState.Mode == "Spectate" then
            local target = playerNames[val("SpectatePlayer", "")]
            local subject
            if target then local _, h = character(target); subject = h end
            if not subject then Toggles.Spectate:SetValue(false); notify("Spectate target is unavailable"); return end
            camera.CameraType, camera.CameraSubject = Enum.CameraType.Custom, subject
            return
        end
        freeMoving = not menuBusy()
        local _, h = character(player)
        if h then
            override(pools.Jump,h,"AutoRotate",false)
            h:Move(Vector3.zero,false)
        end
        if freeMoving and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            if not mouseState then mouseState = {Behavior=UIS.MouseBehavior,Icon=UIS.MouseIconEnabled} end
            UIS.MouseBehavior, UIS.MouseIconEnabled = Enum.MouseBehavior.LockCurrentPosition, false
        else releaseMouse() end
        local rotation = CFrame.fromOrientation(freePitch, freeYaw, 0)
        if freeMoving then
            local function key(code) return UIS:IsKeyDown(code) and 1 or 0 end
            local v = Vector3.new(key(Enum.KeyCode.D)-key(Enum.KeyCode.A),key(Enum.KeyCode.E)-key(Enum.KeyCode.Q),key(Enum.KeyCode.S)-key(Enum.KeyCode.W))
            if v.Magnitude > 1 then v = v.Unit end
            local multiplier = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
            freePosition += rotation:VectorToWorldSpace(v) * val("FreecamSpeed",32) * multiplier * math.min(dt,0.1)
        end
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.new(freePosition) * rotation
        camera.Focus = camera.CFrame * CFrame.new(0,0,-512)
    end)
    refreshPlayers()
    local function addon(path, fn)
        local ok, err = pcall(function() fn(download(path)) end)
        if not ok then warn("[ClaudeHub JJS] Optional addon unavailable: " .. path .. ": " .. tostring(err)) end
    end
    addon("addons/ThemeManager.lua", function(manager)
        manager:SetLibrary(Library); manager:SetFolder("ClaudeHub/Obsidian"); manager:ApplyToTab(Tabs.Settings)
    end)
    addon("addons/SaveManager.lua", function(manager)
        manager:SetLibrary(Library); manager:IgnoreThemeSettings()
        manager:SetIgnoreIndexes({"MenuKeybind","Freecam","Spectate","SpectatePlayer","CombatPlayer","ServerChoice","JobID","AutoBlock"})
        manager:SetFolder("ClaudeHub/JJS"); manager:BuildConfigSection(Tabs.Settings)
    end)
    ready = true
    notify("ClaudeHub JJS v" .. VERSION .. " loaded. RightControl: menu.")
end, function(err) return tostring(err) end)
if not success then
    cleanup()
    pcall(function() Library:Unload() end)
    error("[ClaudeHub JJS] Startup failed: " .. tostring(failure),0)
end
return Library
