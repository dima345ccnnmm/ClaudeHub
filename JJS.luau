-- ClaudeHub JJS v0.3.1 | Ordinary Obsidian (deividcomsono, MIT).
-- Imported gameplay code: Zorcex / JJS-Script, supplied by the user.
-- Original standalone windows removed; lifecycle and Obsidian controls adapted.
-- Original author: Zorcex. Repository declares no license; see THIRD_PARTY_NOTICES.txt.
-- https://github.com/Zorcex/JJS-Script/blob/main/Auto-Blocking.lua
local VERSION = "0.3.1"
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
local AddonController
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
-- ClaudeHub defense rewrite. Zorcex remote-event detection retained as an optional signal.
local animationWatchers,blockCandidates={},{}
local blockMode,blockVIM,blockGameKey
local blockReason="idle"
local function findBlockRemotes()
    local current=ReplicatedStorage
    for _,name in ipairs({"Knit","Knit","Services","BlockService","RE"}) do
        current=current and current:FindFirstChild(name)
    end
    local a=current and current:FindFirstChild("Activated")
    local d=current and current:FindFirstChild("Deactivated")
    if a and d and a:IsA("RemoteEvent") and d:IsA("RemoteEvent") then return a,d end
    return nil,nil,"Zorcex BlockService remotes unavailable"
end
local function inputBlockKey()
    local name=val("BlockInputKey","F")
    if type(name)~="string" or name=="None" or name=="Unknown" then return nil end
    for id,option in pairs(Options) do
        if id~="BlockInputKey" and (id:match("Bind$") or id=="MenuKeybind") and option.Value==name then return nil end
    end
    local ok,key=pcall(function() return Enum.KeyCode[name] end)
    if ok and key and name~="Escape" and name~="RightControl" then return key end
end
local function releaseDefense()
    if activeBlock then
        local state=activeBlock;activeBlock=nil
        local ok,err=pcall(state.Release)
        if not ok and not closed and os.clock()-lastBlockError>3 then
            lastBlockError=os.clock();notify("Block release failed: "..tostring(err))
        end
    end
    if not on("FaceTarget") then restore(pools.Facing) end
end
stopAutoBlock=function()
    releaseDefense()
    for _,c in ipairs(blockConnections) do c:Disconnect() end
    table.clear(blockConnections);table.clear(hookedRemotes)
    for _,entry in pairs(animationWatchers) do if entry.Connection then entry.Connection:Disconnect() end end
    table.clear(animationWatchers);table.clear(blockCandidates)
    blockActivated,blockDeactivated,blockVIM,blockMode=nil,nil,nil,nil
    blockReason="off"
end
local function resetCombat()
    releaseDefense();restore(pools.Facing);combatTarget=nil
    table.clear(blockCandidates)
end
local function validEnemy(p, origin, maxDistance, visible)
    if p==player then return end
    local c,h,r=character(p)
    if not c or (on("CombatTeamFilter") and player.Team~=nil and p.Team==player.Team) then return end
    local distance=(r.Position-origin).Magnitude
    if distance>maxDistance then return end
    if visible then
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={player.Character,markerFolder}
        local hit=workspace:Raycast(origin,r.Position-origin,params)
        if hit and not hit.Instance:IsDescendantOf(c) then return end
    end
    return c,h,r,distance
end
local function acceptableThreat(model)
    local myChar,_,myRoot=character(player)
    if not myRoot or not model or model==myChar or not model.Parent then return end
    local root=model:FindFirstChild("HumanoidRootPart")
    local hum=model:FindFirstChildOfClass("Humanoid")
    if not root or not root:IsA("BasePart") or not hum or hum.Health<=0 then return end
    local distance=(root.Position-myRoot.Position).Magnitude
    if distance>val("DefenseRange",10) then return end
    local enemy=Players:GetPlayerFromCharacter(model)
    if enemy and not validEnemy(enemy,myRoot.Position,val("DefenseRange",10),on("CombatWallCheck")) then return end
    if not enemy and on("CombatWallCheck") then
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={myChar,markerFolder}
        local hit=workspace:Raycast(myRoot.Position,root.Position-myRoot.Position,params)
        if hit and not hit.Instance:IsDescendantOf(model) then return end
    end
    return root,distance
end
local function faceBlockTarget(target)
    local _,hum,root=character(player)
    if not root or not target or not target.Parent or root.Anchored or hum.Sit then return false end
    local position=Vector3.new(target.Position.X,root.Position.Y,target.Position.Z)
    if (position-root.Position).Magnitude<0.05 then return false end
    override(pools.Facing,hum,"AutoRotate",false)
    root.CFrame=CFrame.lookAt(root.Position,position)
    return true
end
doBlock=function(target,reason)
    if not ready or not on("AutoBlock") or menuBusy() or on("Freecam") or on("Spectate") then return end
    if not target or not acceptableThreat(target.Parent) then return end
    if activeBlock then
        if reason=="animation" and activeBlock.Target==target then
            activeBlock.Expires=math.min(activeBlock.Started+1.2,math.max(activeBlock.Expires,os.clock()+val("BlockHold",0.5)))
        end
        return
    end
    if not faceBlockTarget(target) then return end
    local release
    if blockMode=="Remotes" then
        if not blockActivated or not blockDeactivated or not blockActivated:IsDescendantOf(ReplicatedStorage) or not blockDeactivated:IsDescendantOf(ReplicatedStorage) then
            Toggles.AutoBlock:SetValue(false);notify("BlockService was removed; choose Keyboard transport");return
        end
        local a,d=blockActivated,blockDeactivated
        release=function() d:FireServer() end
        local ok,err=pcall(function() a:FireServer() end)
        if not ok then restore(pools.Facing);Toggles.AutoBlock:SetValue(false);notify("Block activation failed: "..tostring(err));return end
    elseif blockMode=="Keyboard" then
        local key=inputBlockKey()
        if not key then Toggles.AutoBlock:SetValue(false);notify("Set Game block key to the key used in JJS");return end
        local vim=blockVIM
        release=function() vim:SendKeyEvent(false,key,false,game) end
        -- Do not inject while the user is already holding their physical block key.
        if inputDown(key) then restore(pools.Facing);return end
        local ok,err=pcall(function() vim:SendKeyEvent(true,key,false,game) end)
        if not ok then pcall(release);restore(pools.Facing);Toggles.AutoBlock:SetValue(false);notify("Block input rejected: "..tostring(err));return end
    else return end
    activeBlock={Target=target,Release=release,Started=os.clock(),Expires=os.clock()+val("BlockHold",0.5)}
    blockCandidates[target.Parent]=nil
    blockReason=reason or "event"
    if AddonController then AddonController:Counter() end
end
local function attackTrack(track)
    local animation=track.Animation
    if not animation then return false end
    local text=tostring(animation.Name or ""):lower()
    local parent=animation.Parent
    for _=1,3 do if not parent then break end;text..=" "..tostring(parent.Name):lower();parent=parent.Parent end
    if text:find("emote",1,true) or text:find("block",1,true) or text:find("idle",1,true) or text:find("walk",1,true)
        or text:find("run",1,true) or text:find("stun",1,true) or text:find("hitreact",1,true) then return false end
    for _,term in ipairs({"punch","melee","m1","strike","jab","uppercut","downslam","attack","kick","slash"}) do
        if text:find(term,1,true) then return true end
    end
    if val("BlockAnimationFilter","Action + names")=="Names only" then return false end
    local priority=track.Priority
    return priority==Enum.AnimationPriority.Action or priority==Enum.AnimationPriority.Action2
        or priority==Enum.AnimationPriority.Action3 or priority==Enum.AnimationPriority.Action4
end
local function observeAnimation(model,track)
    if not on("AutoBlock") or not on("BlockAnimations") or menuBusy() or not attackTrack(track) then return end
    local root=model:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local duration=math.clamp((tonumber(track.Length) or 0)-(tonumber(track.TimePosition) or 0),0.15,0.6)
    blockCandidates[model]={Track=track,Until=os.clock()+duration}
    doBlock(root,"animation")
end
local function watchAnimator(animator)
    if animationWatchers[animator] or not animator:IsA("Animator") then return end
    local hum=animator.Parent
    local model=hum and hum.Parent
    if not hum or not hum:IsA("Humanoid") or not model or model==player.Character then return end
    local entry={Model=model}
    animationWatchers[animator]=entry
    entry.Connection=animator.AnimationPlayed:Connect(function(track) observeAnimation(model,track) end)
    local ok,tracks=pcall(function() return animator:GetPlayingAnimationTracks() end)
    if ok then for _,track in ipairs(tracks) do observeAnimation(model,track) end end
end
hookRemote=function(remote)
    if not remote:IsA("RemoteEvent") or hookedRemotes[remote] then return end
    if remote==blockActivated or remote==blockDeactivated or remote.Name:lower():find("emote") then return end
    hookedRemotes[remote]=remote.OnClientEvent:Connect(function(...)
        if not on("BlockRemoteSignals") or not ready or not on("AutoBlock") or menuBusy() then return end
        local seen={}
        local function examine(arg,depth)
            if activeBlock then return end
            if typeof(arg)=="Instance" then
                if arg:IsA("Player") then arg=arg.Character end
                if not arg then return end
                local model=arg:IsA("Model") and arg or arg:FindFirstAncestorOfClass("Model")
                -- A tool/submodel can be nested inside the real character.
                while model and not model:FindFirstChildOfClass("Humanoid") do model=model:FindFirstAncestorOfClass("Model") end
                local root=acceptableThreat(model);if root then doBlock(root,"remote event") end
            elseif type(arg)=="table" and depth<2 and not seen[arg] then
                seen[arg]=true;local total=0
                for _,v in pairs(arg) do total+=1;if total>32 then break end;examine(v,depth+1) end
            end
        end
        local args=table.pack(...)
        for i=1,args.n do examine(args[i],0);if activeBlock then break end end
    end)
    table.insert(blockConnections,hookedRemotes[remote])
end
local function startAutoBlock()
    stopAutoBlock()
    local mode=val("BlockTransport","Keyboard")
    local a,d=findBlockRemotes()
    if mode=="Auto" then mode=a and "Remotes" or "Keyboard" end
    if mode=="Remotes" then
        if not a then return false,"BlockService unavailable; select Keyboard transport" end
        blockActivated,blockDeactivated=a,d
    else
        local ok,vim=pcall(function() return game:GetService("VirtualInputManager") end)
        if not ok or not vim then return false,"VirtualInputManager unavailable; cannot send the game block key" end
        if not inputBlockKey() then return false,"Set a valid Game block key" end
        blockVIM=vim
        -- Still exclude the source block events from the optional event detector.
        blockActivated,blockDeactivated=a,d
    end
    blockMode=mode;blockReason="listening"
    table.insert(blockConnections,ReplicatedStorage.DescendantAdded:Connect(hookRemote))
    for _,object in ipairs(ReplicatedStorage:GetDescendants()) do hookRemote(object) end
    table.insert(blockConnections,workspace.DescendantAdded:Connect(function(object)
        if object:IsA("Animator") then watchAnimator(object) end
    end))
    for _,object in ipairs(workspace:GetDescendants()) do if object:IsA("Animator") then watchAnimator(object) end end
    return true
end
local function updateAutoBlock()
    local now=os.clock()
    for animator,entry in pairs(animationWatchers) do
        if not animator:IsDescendantOf(workspace) or not entry.Model.Parent then
            entry.Connection:Disconnect();animationWatchers[animator]=nil;blockCandidates[entry.Model]=nil
        end
    end
    if not on("BlockAnimations") then table.clear(blockCandidates);return end
    if activeBlock then return end
    local closest,best
    for model,candidate in pairs(blockCandidates) do
        if now>=candidate.Until or not model.Parent or candidate.Track.IsPlaying==false then blockCandidates[model]=nil
        else local root,distance=acceptableThreat(model);if root and (not best or distance<best) then closest,best=root,distance end end
    end
    if closest then doBlock(closest,"animation") end
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
-- Local recovery only. Does not remove server-authoritative combat restrictions.
local stunSnapshot,stunHumanoid
local stunStates={Enum.HumanoidStateType.Ragdoll,Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Physics}
local knownWalk,knownJump,knownHeight=16,50,7.2
local function stopNoStun()
    if stunHumanoid and stunSnapshot then
        for state,info in pairs(stunSnapshot) do
            pcall(function() if stunHumanoid:GetStateEnabled(state)==info.Applied then stunHumanoid:SetStateEnabled(state,info.Base) end end)
        end
    end
    stunHumanoid,stunSnapshot=nil,nil
end
local function updateNoStun()
    local _,hum,root=character(player)
    if not on("NoStun") or not hum or on("Freecam") or on("Spectate") or on("SourceMoveset") or on("SourceInvisible") or hum.Sit or root.Anchored then
        stopNoStun();return
    end
    if stunHumanoid~=hum then
        stopNoStun();stunHumanoid=hum;stunSnapshot={}
        knownWalk=hum.WalkSpeed>0 and hum.WalkSpeed or 16
        knownJump=hum.JumpPower>0 and hum.JumpPower or 50
        knownHeight=hum.JumpHeight>0 and hum.JumpHeight or 7.2
        local okGetting,baseGetting=pcall(function() return hum:GetStateEnabled(Enum.HumanoidStateType.GettingUp) end)
        if okGetting then
            stunSnapshot[Enum.HumanoidStateType.GettingUp]={Base=baseGetting,Applied=true}
            pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp,true) end)
        end
        for _,state in ipairs(stunStates) do
            local ok,base=pcall(function() return hum:GetStateEnabled(state) end)
            if ok then stunSnapshot[state]={Base=base,Applied=false};pcall(function() hum:SetStateEnabled(state,false) end) end
        end
    end
    if hum.WalkSpeed>0 then knownWalk=hum.WalkSpeed
    elseif hum.WalkSpeed==0 then hum.WalkSpeed=on("Speed") and val("WalkSpeed",20) or knownWalk end
    if hum.JumpPower>0 then knownJump=hum.JumpPower
    elseif hum.JumpPower==0 then hum.JumpPower=knownJump end
    if hum.JumpHeight>0 then knownHeight=hum.JumpHeight
    elseif hum.JumpHeight==0 then hum.JumpHeight=knownHeight end
    if hum.PlatformStand then hum.PlatformStand=false end
    local ok,state=pcall(function() return hum:GetState() end)
    if ok and table.find(stunStates,state) then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
end

local function cleanup()
    if closed then return end
    closed, ready = true, false
    if AddonController then AddonController:Destroy() end
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    RunService:UnbindFromRenderStep("ClaudeHubJJS_Camera")
    releaseCamera()
    stopAutoBlock()
    stopNoStun()
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
local function buildZorcex(host)
local SOURCES={}
SOURCES.BlackFlash = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title or "Auto Black Flash"),
            Text = tostring(text or "SUPER OP SCRIPT!"),
            Duration = duration or 3,
        })
    end)
end

local DF_CONFIG = {
    BehindOffset = 5.5,
    AlreadyBehindTolerance = 3.5,
    FireDelay = 0.37,
    DashSpeed = 79,
    ArcSegments = 5,
    SideWidth = 0.65,
    TrailLifetime = 0.35,
    DashAnimLeft = "rbxassetid://117223862448096",
    DashAnimRight = "rbxassetid://75203303352791",
    AttackAnimId = "rbxassetid://100962226150441",
    FacingDotThreshold = -0.6,
    RetryDelay = 0.04,
    RetryFire = true,
}

local TODO_CONFIG = {
    Delay_AfterPebble = 1,
    Delay_AfterRight = 0,
    Delay_AfterBrute1 = 0.60,
}

local MAHITO_CONFIG = {
    RefireDelay = 0.3,
}

local YUTA_CONFIG = {
    RefireDelay = 0.3,
}

local function getRemote(...)
    local path = { ... }
    local ok, remote = pcall(function()
        local node = ReplicatedStorage
        for _, child in ipairs(path) do
            node = node:WaitForChild(child, 5)
        end
        return node
    end)
    return ok and remote or nil
end

local divergentFistRemote = getRemote("Knit", "Knit", "Services", "DivergentFistService", "RE", "Activated")
local itadoriRightRemote = getRemote("Knit", "Knit", "Services", "ItadoriService", "RE", "RightActivated")
local pebbleThrowRemote = getRemote("Knit", "Knit", "Services", "PebbleThrowService", "RE", "Activated")
local todoRightRemote = getRemote("Knit", "Knit", "Services", "TodoService", "RE", "RightActivated")
local bruteForceRemote = getRemote("Knit", "Knit", "Services", "BruteForceService", "RE", "Activated")
local focusStrikeRemote = getRemote("Knit", "Knit", "Services", "FocusStrikeService", "RE", "Activated")
local resoluteSlashRemote = getRemote("Knit", "Knit", "Services", "ResoluteSlashService", "RE", "Activated")

local dfOk = divergentFistRemote ~= nil
local todoOk = pebbleThrowRemote ~= nil and todoRightRemote ~= nil and bruteForceRemote ~= nil
local mahitoOk = focusStrikeRemote ~= nil
local yutaOk = resoluteSlashRemote ~= nil

if not dfOk and not todoOk and not mahitoOk and not yutaOk then
    error("No supported Black Flash services found")
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getAnimator()
    local char = LocalPlayer.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    return humanoid:FindFirstChildOfClass("Animator")
end

local function isAliveModel(model)
    local myChar = LocalPlayer.Character
    if model == myChar then return false end
    local root = model:FindFirstChild("HumanoidRootPart")
    local humanoid = model:FindFirstChild("Humanoid")
    return root and humanoid and humanoid.Health > 0
end

local function isTargetFacingAway(targetRoot)
    local hrp = getHRP()
    if not hrp or not targetRoot or not targetRoot.Parent then return false end
    local toPlayer = (hrp.Position - targetRoot.Position)
    if toPlayer.Magnitude < 0.01 then return false end
    local dot = targetRoot.CFrame.LookVector:Dot(toPlayer.Unit)
    return dot < DF_CONFIG.FacingDotThreshold
end

local function findNearestTarget()
    local hrp = getHRP()
    if not hrp then return nil end
    local nearest = nil
    local bestDist = math.huge
    local function checkModel(model)
        if not isAliveModel(model) then return end
        local root = model:FindFirstChild("HumanoidRootPart")
        local dist = (hrp.Position - root.Position).Magnitude
        if dist < bestDist then
            bestDist = dist
            nearest = model
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            checkModel(player.Character)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            checkModel(obj)
        end
    end
    return nearest
end

local function createTrail(rootPart)
    local a0 = Instance.new("Attachment", rootPart)
    local a1 = Instance.new("Attachment", rootPart)
    a1.Position = Vector3.new(0, 2, 0)
    local trail = Instance.new("Trail", rootPart)
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime = DF_CONFIG.TrailLifetime
    trail.MinLength = 0
    trail.FaceCamera = true
    task.delay(DF_CONFIG.TrailLifetime + 0.1, function()
        trail:Destroy()
        a0:Destroy()
        a1:Destroy()
    end)
end

local cachedAnims = {}

local function playDashAnimation(direction, duration)
    local animator = getAnimator()
    if not animator then return nil end
    local animId = (direction == "Left") and DF_CONFIG.DashAnimLeft or DF_CONFIG.DashAnimRight
    if not cachedAnims[direction] then
        local anim = Instance.new("Animation")
        anim.AnimationId = animId
        anim.Name = "DivergentFistDashAnim_" .. direction
        cachedAnims[direction] = anim
    end
    local track = animator:LoadAnimation(cachedAnims[direction])
    track.Priority = Enum.AnimationPriority.Action
    track:Play()
    task.delay(duration + 0.05, function()
        if track and track.IsPlaying then
            track:Stop(0.15)
        end
    end)
    return track
end

local function playAttackAnimation()
    local animator = getAnimator()
    if not animator then return end
    if not cachedAnims["Attack"] then
        local anim = Instance.new("Animation")
        anim.AnimationId = DF_CONFIG.AttackAnimId
        anim.Name = "DivergentFistAttackAnim"
        cachedAnims["Attack"] = anim
    end
    local track = animator:LoadAnimation(cachedAnims["Attack"])
    track.Priority = Enum.AnimationPriority.Action
    track:Play()
    task.delay(1.113, function()
        if track.IsPlaying then
            track:Stop()
        end
    end)
end

local function performCurvedDash(targetRoot)
    local hrp = getHRP()
    if not hrp then return end
    local myPos = hrp.Position
    local destPos = (targetRoot.CFrame * CFrame.new(0, 0, DF_CONFIG.BehindOffset)).Position
    if (myPos - destPos).Magnitude < DF_CONFIG.AlreadyBehindTolerance then
        playAttackAnimation()
        return
    end
    local dist = (destPos - myPos).Magnitude
    if dist < 0.5 then return end
    local dir = (destPos - myPos).Unit
    local side = dir:Cross(Vector3.new(0, 1, 0)).Unit
    local isLeft = math.random(1, 2) == 2
    if isLeft then side = -side end
    local dashDirection = isLeft and "Left" or "Right"
    local arcDef = {
        { 0.10, DF_CONFIG.SideWidth * 0.50 },
        { 0.30, DF_CONFIG.SideWidth * 0.80 },
        { 0.55, DF_CONFIG.SideWidth * 0.70 },
        { 0.75, DF_CONFIG.SideWidth * 0.40 },
        { 1.00, 0 },
    }
    local waypoints = {}
    for i = 1, math.min(DF_CONFIG.ArcSegments, #arcDef) do
        table.insert(waypoints, myPos + (dir * dist * arcDef[i][1]) + (side * dist * arcDef[i][2]))
    end
    local totalTime = math.max(dist / DF_CONFIG.DashSpeed, 0.08)
    local segTime = totalTime / #waypoints
    createTrail(hrp)
    local dashTrack = playDashAnimation(dashDirection, totalTime)
    for i, wp in ipairs(waypoints) do
        local lookDir = (i < #waypoints) and (waypoints[i + 1] - wp).Unit or (targetRoot.Position - wp).Unit
        TweenService:Create(hrp, TweenInfo.new(segTime, Enum.EasingStyle.Linear), {
            CFrame = CFrame.new(wp, wp + lookDir),
        }):Play()
        task.wait(segTime)
    end
    hrp.CFrame = CFrame.lookAt(destPos, targetRoot.Position)
    if dashTrack and dashTrack.IsPlaying then
        dashTrack:Stop(0.1)
    end
    playAttackAnimation()
end

local dfCooling = false
local dfRetrying = false

local function setupDivergentFistHook()
    if not dfOk then return end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() ~= "FireServer" or self ~= divergentFistRemote then
            return oldNamecall(self, ...)
        end
        if dfRetrying then
            return oldNamecall(self, ...)
        end
        if dfCooling then
            return oldNamecall(self, ...)
        end
        dfCooling = true
        local result = oldNamecall(self, ...)
        local args = { ... }
        local target = findNearestTarget()
        local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
        task.delay(DF_CONFIG.FireDelay, function()
            if targetRoot and targetRoot.Parent and not isTargetFacingAway(targetRoot) then
                if itadoriRightRemote then
                    pcall(function() itadoriRightRemote:FireServer() end)
                end
                task.spawn(function()
                    task.wait(DF_CONFIG.RetryDelay)
                    if not targetRoot.Parent or not isAliveModel(targetRoot.Parent) then
                        task.defer(function() dfCooling = false end)
                        return
                    end
                    performCurvedDash(targetRoot)
                    local shouldRetryFire = (DF_CONFIG.RetryFire ~= nil) and DF_CONFIG.RetryFire or DF_CONFIG.RetryFire
                    if not isTargetFacingAway(targetRoot) then
                    elseif not shouldRetryFire then
                    else
                        dfRetrying = true
                        pcall(function() divergentFistRemote:FireServer(table.unpack(args)) end)
                        task.wait(DF_CONFIG.FireDelay)
                        pcall(function() divergentFistRemote:FireServer(table.unpack(args)) end)
                        dfRetrying = false
                    end
                    task.defer(function() dfCooling = false end)
                end)
            else
                pcall(function() divergentFistRemote:FireServer(table.unpack(args)) end)
                task.defer(function() dfCooling = false end)
            end
        end)
        task.spawn(function()
            if not targetRoot or not targetRoot.Parent then return end
            performCurvedDash(targetRoot)
        end)
        task.delay(0.3, function()
            dfRetrying = true
            pcall(function()
                divergentFistRemote:FireServer(table.unpack(args))
            end)
            dfRetrying = false
        end)
        return result
    end)
end

local function getMovesetItem(name)
    local char = LocalPlayer.Character
    if not char then return nil end
    local moveset = char:FindFirstChild("Moveset")
    if not moveset then return nil end
    return moveset:FindFirstChild(name)
end

local isComboRunning = false

local function runCombo()
    if isComboRunning then return end
    isComboRunning = true
    task.delay(TODO_CONFIG.Delay_AfterPebble, function()
        pcall(function() todoRightRemote:FireServer() end)
        task.delay(TODO_CONFIG.Delay_AfterRight, function()
            local bruteArg = getMovesetItem("Brute Force")
            if bruteArg then
                pcall(function() bruteForceRemote:FireServer(bruteArg) end)
            end
            task.delay(TODO_CONFIG.Delay_AfterBrute1, function()
                local bruteArg2 = getMovesetItem("Brute Force")
                if bruteArg2 then
                    pcall(function() bruteForceRemote:FireServer(bruteArg2) end)
                end
                task.defer(function() isComboRunning = false end)
            end)
        end)
    end)
end

local function setupTodoHook()
    if not todoOk then return end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "FireServer" and self == pebbleThrowRemote then
            local result = oldNamecall(self, ...)
            task.spawn(runCombo)
            return result
        end
        return oldNamecall(self, ...)
    end)
end

local mahitoCooling = false
local mahitoRetrying = false

local function setupMahitoHook()
    if not mahitoOk then return end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() ~= "FireServer" or self ~= focusStrikeRemote then
            return oldNamecall(self, ...)
        end
        if mahitoRetrying then
            return oldNamecall(self, ...)
        end
        if mahitoCooling then
            return oldNamecall(self, ...)
        end
        mahitoCooling = true
        local result = oldNamecall(self, ...)
        local args = { ... }
        task.delay(MAHITO_CONFIG.RefireDelay, function()
            mahitoRetrying = true
            pcall(function()
                focusStrikeRemote:FireServer(table.unpack(args))
            end)
            mahitoRetrying = false
            task.defer(function()
                mahitoCooling = false
            end)
        end)
        return result
    end)
end

local yutaCooling = false
local yutaRetrying = false

local function setupYutaHook()
    if not yutaOk then return end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() ~= "FireServer" or self ~= resoluteSlashRemote then
            return oldNamecall(self, ...)
        end
        if yutaRetrying then
            return oldNamecall(self, ...)
        end
        if yutaCooling then
            return oldNamecall(self, ...)
        end
        yutaCooling = true
        local result = oldNamecall(self, ...)
        local args = { ... }
        task.delay(YUTA_CONFIG.RefireDelay, function()
            yutaRetrying = true
            pcall(function()
                resoluteSlashRemote:FireServer(table.unpack(args))
            end)
            yutaRetrying = false
            task.defer(function()
                yutaCooling = false
            end)
        end)
        return result
    end)
end

setupDivergentFistHook();setupTodoHook();setupMahitoHook();setupYutaHook()
return {Supported={Yuji=dfOk,Todo=todoOk,Mahito=mahitoOk,Yuta=yutaOk}}

]====]
SOURCES.Bypass = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local state = {
    Bypass = false,
}

local resetCount = 0

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 2
        })
    end)
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function fireReset()
    local ok, remote = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Knit", 2)
            :WaitForChild("Knit", 2)
            :WaitForChild("Services", 2)
            :WaitForChild("JoinService", 2)
            :WaitForChild("RE", 2)
            :WaitForChild("Reset", 2)
    end)
    if ok and remote and remote:IsA("RemoteEvent") then
        remote:FireServer()
        return true
    end
    return false
end

local function getTarget(maxDistance)
    maxDistance = maxDistance or 500
    local targets = {}
    local myHRP = getHRP()
    if not myHRP then return nil end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and hrp then
                if (hrp.Position - myHRP.Position).Magnitude <= maxDistance then
                    table.insert(targets, humanoid)
                end
            end
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and string.lower(obj.Name) == "dummy" then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
            if humanoid and humanoid.Health > 0 and hrp then
                if (hrp.Position - myHRP.Position).Magnitude <= maxDistance then
                    table.insert(targets, humanoid)
                end
            end
        end
    end

    if #targets > 0 then
        return targets[math.random(1, #targets)]
    end
    return nil
end

task.spawn(function()
    while true do
        task.wait(0.5)
        if state.Bypass then
            local hrp = getHRP()
            local humanoid = getHumanoid()
            if hrp and humanoid and humanoid.Health > 0 then
                local targetHumanoid = getTarget(500)
                local targetHRP = targetHumanoid and targetHumanoid.Parent and (
                    targetHumanoid.Parent:FindFirstChild("HumanoidRootPart") or
                    targetHumanoid.Parent:FindFirstChild("Torso")
                )
                if targetHRP then
                    local startPos = hrp.Position
                    hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 2.5)
                    local teleportedBack = false
                    local timer = 0
                    while timer < 3 do
                        task.wait(0.1)
                        timer = timer + 0.1
                        if not state.Bypass or not humanoid or humanoid.Health <= 0 then
                            break
                        end
                        if (hrp.Position - startPos).Magnitude < 10 then
                            teleportedBack = true
                            break
                        end
                    end
                    if state.Bypass and humanoid and humanoid.Health > 0 then
                        if teleportedBack then
                            notify("Anti-Cheat Bypass", "Rubber Band! Reseting...", 2)
                            while state.Bypass and humanoid and humanoid.Health > 0 do
                                if fireReset() then
                                    resetCount = resetCount + 1
                                end
                                task.wait(3)
                                humanoid = getHumanoid()
                            end
                        else
                            notify("Anti-Cheat Bypass", "No rollback observed; this does not verify a bypass", 2)
                            task.wait(2)
							notify("Anti-Cheat Bypass", "Resets: " .. tostring(resetCount) .. "", 2)
                        end
                    end
                end
            end
        end
    end
end)


state.Bypass=true
return {Stop=function() state.Bypass=false end}

]====]
SOURCES.Counter = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local ItadoriService = ReplicatedStorage
	:WaitForChild("Knit")
	:WaitForChild("Knit")
	:WaitForChild("Services")
	:WaitForChild("ItadoriService")
	:WaitForChild("RE")

local ItadoriActivated = ItadoriService:WaitForChild("Activated")

local BLOCK_ANIMATION = "rbxassetid://120133391090244"
local BLOCK_TRACK

local COUNTER_RANGE = 5   
local COUNTER_ANIMS = {
	"rbxassetid://103513893010999",
	"rbxassetid://103513893010999",
	"rbxassetid://111214152450580",
	"rbxassetid://85003123457049",
}

local function stopOriginalBlockAnimation()
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation and track.Animation.AnimationId == "rbxassetid://101865783312435" then
			track:Stop(0)
		end
	end
end

local function playCustomBlockAnimation()
	stopOriginalBlockAnimation()

	if BLOCK_TRACK then
		BLOCK_TRACK:Stop()
		BLOCK_TRACK:Destroy()
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = BLOCK_ANIMATION

	BLOCK_TRACK = animator:LoadAnimation(anim)
	BLOCK_TRACK.Priority = Enum.AnimationPriority.Action
	BLOCK_TRACK.Looped = true
	BLOCK_TRACK:Play(0)
end

local function getClosestPlayerDistance()
	local char = player.Character
	if not char then return nil, nil end

	local myRoot = char:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil, nil end

	local closestPlayer = nil
	local closestDist = math.huge

	for _, p in pairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local theirRoot = p.Character:FindFirstChild("HumanoidRootPart")
			local theirHum   = p.Character:FindFirstChildOfClass("Humanoid")

			if theirRoot and theirHum and theirHum.Health > 0 then
				local dist = (myRoot.Position - theirRoot.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closestPlayer = p
				end
			end
		end
	end

	return closestPlayer, closestDist
end

local function playRandomCounterAnimation()
	local animId = COUNTER_ANIMS[math.random(1, #COUNTER_ANIMS)]

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()

	print("[Block] 🎬 Counter animation: " .. animId)
	return track
end

local function checkCounterAttack()
	local closestPlayer, dist = getClosestPlayerDistance()

	if closestPlayer and dist and dist <= COUNTER_RANGE then
		print(string.format("[Block] لاعب قريب جداً (%.1f studs) — تفعيل الهجوم المضاد", dist))

		
		local args = { false }
		pcall(function()
			ItadoriActivated:FireServer(unpack(args))
		end)

		
		playRandomCounterAnimation()
	end
end


return {Try=function()
    local _,dist=getClosestPlayerDistance()
    if not dist or dist>COUNTER_RANGE then return false end
    playCustomBlockAnimation()
    checkCounterAttack()
    if BLOCK_TRACK then BLOCK_TRACK:Stop(0);BLOCK_TRACK:Destroy();BLOCK_TRACK=nil end
    return true
end}

]====]
SOURCES.Dash = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local oldTick = tick

local fakeTime = oldTick()

hookfunction(tick, function(...)
    fakeTime = fakeTime + 100
    return fakeTime
end)


]====]
SOURCES.Emotes = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Emote = PlayerGui:WaitForChild("Emotes"):WaitForChild("Emote")
local Page1 = Emote:WaitForChild("Page1")
local Page2 = Emote:WaitForChild("Page2")
local Switch = Emote:WaitForChild("Switch")
local Equipped = PlayerGui:WaitForChild("Menus"):WaitForChild("Group"):WaitForChild("Inventory"):WaitForChild("Items"):WaitForChild("Emotes"):WaitForChild("Equipped")

local function show(gui)
    if gui:IsA("GuiObject") then
        gui.Visible = true
        for _, child in ipairs(gui:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Visible = true
            end
        end
    end
end

local Active = false
Page2.Visible = false
Switch.Visible = true
show(Page1)
show(Equipped)

Switch.MouseButton1Click:Connect(function()
    Active = not Active
    Page1.Visible = not Active
    Page2.Visible = Active
    if Active then show(Page2) else show(Page1) end
end)

]====]
SOURCES.Haruta = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
_G.Multi = Bridge.Value("HarutaMultiplier",100)

local oldNamecall
oldNamecall = hookmetamethod(game,"__namecall",function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if method == "FireServer" and self.Parent == game.Players.LocalPlayer.Character then
        if typeof(args[1]) == "table" then
            local newTable = {}
            for _, v in ipairs(args[1]) do
                for i = 1, math.clamp(Bridge.Value("HarutaMultiplier",100),1,100) do
                    table.insert(newTable, v)
                end
            end
            args[1] = newTable
            return oldNamecall(self, unpack(args))
        end
    end
    return oldNamecall(self, ...)
end)


]====]
SOURCES.Invisible = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local enabled = false
local connections = {}
local platform = nil
local character, humanoid, rootPart
local originalTransparencies = {}
local fixedY = nil
local pendingCF,pendingOffset

local function setupCharacter()
    character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
    originalTransparencies = {}
    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            originalTransparencies[part] = part.Transparency
        end
    end
end

local function createPlatform()
    if platform then
        platform:Destroy()
    end
    platform = Instance.new("Part")
    platform.Name = "InvisPlatform"
    platform.Size = Vector3.new(14, 1, 14)
    platform.Anchored = true
    platform.CanCollide = true
    platform.Transparency = 1
    platform.Parent = workspace
end

local function setLocalTransparency(state)
    if not character then return end
    for part, original in pairs(originalTransparencies) do
        if part and part.Parent then
            part.Transparency = state and 0.65 or original
        end
    end
end

local function startLoop()
    if connections.Heartbeat then
        connections.Heartbeat:Disconnect()
    end
    connections.Heartbeat = RunService.Heartbeat:Connect(function()
        if enabled and character and rootPart and rootPart.Parent and humanoid then
            local realCF = rootPart.CFrame
            pendingCF=realCF
            local oldOffset = humanoid.CameraOffset
            pendingOffset=oldOffset

            if not fixedY then
                fixedY = realCF.Y - 1000
            end

            local hiddenPos = Vector3.new(realCF.X, fixedY, realCF.Z)
            local hiddenCF = CFrame.new(hiddenPos) * (realCF - realCF.Position)

            if platform then
                platform.CFrame = CFrame.new(hiddenPos - Vector3.new(0, 3.5, 0))
            end

            rootPart.CFrame = hiddenCF
            humanoid.CameraOffset = hiddenCF:ToObjectSpace(CFrame.new(realCF.Position)).Position

            RunService.RenderStepped:Wait()

            if rootPart and rootPart.Parent then
                rootPart.CFrame = realCF
                humanoid.CameraOffset = oldOffset
                pendingCF,pendingOffset=nil,nil
            end
        end
    end)
end

local function stopLoop()
    if connections.Heartbeat then
        connections.Heartbeat:Disconnect()
        connections.Heartbeat = nil
    end
    if platform then
        platform:Destroy()
        platform = nil
    end
    fixedY = nil
    setLocalTransparency(false)
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    setupCharacter()
    if enabled then
        fixedY = nil
        createPlatform()
        setLocalTransparency(true)
        startLoop()
    end
end)

setupCharacter()

enabled=true
createPlatform();setLocalTransparency(true);startLoop()
return {Stop=function()
    enabled=false
    if pendingCF and rootPart and rootPart.Parent then rootPart.CFrame=pendingCF end
    if pendingOffset and humanoid and humanoid.Parent then humanoid.CameraOffset=pendingOffset end
    pendingCF,pendingOffset=nil,nil
    stopLoop()
end}

]====]
SOURCES.MovesetMain = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local animationConfig = {
    ["80843134889167"] = { id = "rbxassetid://103513893010999", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["85382723645632"] = { id = "rbxassetid://140381676724931", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["111902759344637"] = { id = "rbxassetid://111214152450580", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["90226048419187"] = { id = "rbxassetid://85003123457049", speed = 1,   timePos = 0,   fade = 0.1 }, 
}

local animationsToBlock = {}
for id in pairs(animationConfig) do
    animationsToBlock[tonumber(id)] = true
end

local queue = {}
local isAnimating = false

local function playReplacement(animationId)
    if isAnimating then
        table.insert(queue, animationId)
        return
    end

    local config = animationConfig[tostring(animationId)]
    if not config then return end

    isAnimating = true

    local anim = Instance.new("Animation")
    anim.AnimationId = config.id

    local track = humanoid:LoadAnimation(anim)
    track:Play(config.fade)                  
    track:AdjustSpeed(config.speed)          
    track.TimePosition = config.timePos      

    
    track.Stopped:Connect(function()
        isAnimating = false
        if #queue > 0 then
            playReplacement(table.remove(queue, 1))
        end
    end)
end

local function stopBlockedAnimations()
    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
        local id = tonumber(track.Animation.AnimationId:match("%d+"))
        if animationsToBlock[id] then
            track:Stop()
        end
    end
end

local function onAnimationPlayed(track)
    local id = tonumber(track.Animation.AnimationId:match("%d+"))
    if animationsToBlock[id] then
        stopBlockedAnimations()
        track:Stop()
        playReplacement(id)
    end
end

humanoid.AnimationPlayed:Connect(onAnimationPlayed)

local function clampBodyVelocity(obj)
    if obj:IsA("BodyVelocity") then
        obj.Velocity = Vector3.new(obj.Velocity.X, 0, obj.Velocity.Z)
    end
end

character.DescendantAdded:Connect(clampBodyVelocity)
for _, obj in ipairs(character:GetDescendants()) do
    clampBodyVelocity(obj)
end

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Effects = workspace:WaitForChild("Effects")

local white = Color3.new(1, 1, 1)

local function isMyEffect(effect)
	local char = LocalPlayer.Character
	if not char then return false end

	
	for _, obj in ipairs(effect:GetDescendants()) do
		if obj:IsA("Trail") then
			
			if obj.Attachment0 and obj.Attachment0:IsDescendantOf(char) then
				return true
			end
			if obj.Attachment1 and obj.Attachment1:IsDescendantOf(char) then
				return true
			end
		end
	end

	
	for _, obj in ipairs(effect:GetDescendants()) do
		if obj:IsA("BasePart") or obj:IsA("Attachment") then
			
			for _, weld in ipairs(obj:GetChildren()) do
				if weld:IsA("WeldConstraint") or weld:IsA("Weld") then
					local p0 = weld:IsA("Weld") and weld.Part0 or weld.Part0
					local p1 = weld:IsA("Weld") and weld.Part1 or weld.Part1
					if (p0 and p0:IsDescendantOf(char))
						or (p1 and p1:IsDescendantOf(char)) then
						return true
					end
				end
			end
		end
	end

	
	local myRoot = char:FindFirstChild("HumanoidRootPart")
	local effectPos = effect:IsA("BasePart") and effect.Position
		or (effect:FindFirstChildOfClass("BasePart") and effect:FindFirstChildOfClass("BasePart").Position)

	if myRoot and effectPos then
		local dist = (myRoot.Position - effectPos).Magnitude
		if dist < 5 then
			
			for _, p in pairs(Players:GetPlayers()) do
				if p ~= LocalPlayer and p.Character then
					local theirRoot = p.Character:FindFirstChild("HumanoidRootPart")
					if theirRoot then
						local theirDist = (theirRoot.Position - effectPos).Magnitude
						
						if theirDist < dist then
							return false
						end
					end
				end
			end
			return true
		end
	end

	return false
end

local function applyWhite(obj)
	pcall(function()
		if obj:IsA("Trail") then
			obj.Color          = ColorSequence.new(white)
			obj.LightEmission  = 0
			obj.LightInfluence = 1

		elseif obj:IsA("Beam") then
			obj.Color          = ColorSequence.new(white)
			obj.LightEmission  = 0
			obj.LightInfluence = 1

		elseif obj:IsA("ParticleEmitter") then
			obj.Color         = ColorSequence.new(white)
			obj.LightEmission = 0
			obj.Enabled       = true

		elseif obj:IsA("BasePart") then
			obj.Color    = white
			obj.Material = Enum.Material.SmoothPlastic

		elseif obj:IsA("Highlight") then
			obj.FillColor    = white
			obj.OutlineColor = white

		elseif obj:IsA("Decal") then
			obj.Color3 = white

		elseif obj:IsA("Texture") then
			obj.Color3 = white
		end
	end)
end

local function makeCombatTrailWhite(effect)
	
	task.spawn(function()
		task.wait()

		
		if not isMyEffect(effect) then
			return  
		end

		for i = 1, 60 do
			if not effect or not effect.Parent then break end

			applyWhite(effect)
			for _, obj in ipairs(effect:GetDescendants()) do
				applyWhite(obj)
			end

			task.wait()
		end
	end)
end

local function clearAllEffects()
	for _, effect in ipairs(Effects:GetChildren()) do
		if effect.Name == "CombatTrail" then
			makeCombatTrailWhite(effect)
		end
	end
end

Effects.ChildAdded:Connect(function(child)
	if child.Name == "CombatTrail" then
		makeCombatTrailWhite(child)
	end
end)

clearAllEffects()

LocalPlayer.CharacterAdded:Connect(function(char)
	Character = char
	clearAllEffects()
end)

local FLY_PROTECTED_IDS = {
    ["117844331774372"] = true, 
    ["9443519528"]       = true, 
    ["134581973800784"] = true, 
    ["128524425761051"] = true, 
    ["78540995456941"]  = true, 
    ["139078698020363"] = true, 
    ["136676738644802"] = true, 
    ["131522534497146"] = true, 
}

local function isFlyProtected(track)
    local id = track.Animation.AnimationId:match("%d+")
    return id and FLY_PROTECTED_IDS[id]
end

pcall(function() 
    getgenv().Idle:Disconnect() 
end)

getgenv().Idle = game.Players.LocalPlayer.Character.Humanoid.AnimationPlayed:Connect(function(v)

    local original1 = "rbxassetid://120133391090244"
    local original2 = "rbxassetid://138196552148011"
    local DR_FLOAT_ID = "131522534497146"

    if v.Animation.AnimationId == original1 or v.Animation.AnimationId == original2 then

        local humanoid = game.Players.LocalPlayer.Character.Humanoid

        
        for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do
            local id = t.Animation.AnimationId:match("%d+")
            if id == DR_FLOAT_ID then
                return
            end
        end

        local Anim = Instance.new("Animation")
        Anim.AnimationId = "rbxassetid://117844331774372"

        local k = humanoid:LoadAnimation(Anim)

        k.Priority = Enum.AnimationPriority.Idle
        k.Looped = true
        k:Play(0.3)
        k:AdjustSpeed(0)

        local startTime = 0.157
        local endTime = 0.157
        local cycleDuration = 1.5
        local timeElapsed = 0

        local connection
        connection = game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
            timeElapsed = (timeElapsed + deltaTime) % (cycleDuration * 2)

            
            local stillSafe = true
            for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do
                local id = t.Animation.AnimationId:match("%d+")
                if id == DR_FLOAT_ID then
                    stillSafe = false
                    break
                end
            end
            if not stillSafe then
                k:Stop(0.1)
                connection:Disconnect()
                return
            end

            local alpha = (math.sin((timeElapsed / cycleDuration) * math.pi - math.pi / 2) + 1) / 2
            k.TimePosition = startTime + (endTime - startTime) * alpha
        end)

        v.Stopped:Wait()
        k:Stop(0.3)
        connection:Disconnect()
    end
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local cursedStrikeANIM = "rbxassetid://124901309160375"
local roughEnergyANIM  = "rbxassetid://72157009600725"
local luckyVolleyANIM  = "rbxassetid://113722638806911"
local Finisher1ANIM    = "rbxassetid://131506102901134"

local PLAY_DURATION   = 1.2
local DAMAGE_DISTANCE = 60
local DAMAGE_WAIT     = 1.5

local FINISHER1_START = 0.9
local FINISHER1_END   = 2

local isAnimationSequenceActive = false
local didDealDamage    = false
local positionAtStrike = nil

local trackedHumanoids = {}

local function trackHumanoid(humanoid)
	if trackedHumanoids[humanoid] then return end
	trackedHumanoids[humanoid] = true

	local lastHealth = humanoid.Health

	humanoid.HealthChanged:Connect(function(newHealth)
		local character = LocalPlayer.Character
		if not character then return end

		local myRoot    = character:FindFirstChild("HumanoidRootPart")
		local enemyRoot = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")

		if not myRoot or not enemyRoot then return end

		local checkPos = positionAtStrike or myRoot.Position
		local dist = (checkPos - enemyRoot.Position).Magnitude

		if newHealth < lastHealth and dist <= DAMAGE_DISTANCE then
			didDealDamage = true
		end

		lastHealth = newHealth
	end)
end

local function scanAllHumanoids()
	while true do
		task.wait(1)
		for _, obj in pairs(workspace:GetDescendants()) do
			if obj:IsA("Humanoid") then
				trackHumanoid(obj)
			end
		end
	end
end

task.spawn(scanAllHumanoids)

local function waitForDamage(timeout)
	local elapsed = 0
	while elapsed < timeout do
		if didDealDamage then return true end
		elapsed += task.wait(0.05)
	end
	return false
end

local noclipConn = nil

local function enableNoclip(character)
	
	if noclipConn then return end

	noclipConn = RunService.Stepped:Connect(function()
		if not character or not character.Parent then
			noclipConn:Disconnect()
			noclipConn = nil
			return
		end
		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

local function disableNoclip(character)
	
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if not character or not character.Parent then return end
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
		end
	end
end

local function dashForward(character, duration)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	
	enableNoclip(character)

	local elapsed = 0
	local conn

	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		if not rootPart or not rootPart.Parent then
			conn:Disconnect()
			disableNoclip(character)
			return
		end

		if elapsed >= duration then
			conn:Disconnect()
			rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			
			disableNoclip(character)
			return
		end

		local forwardDir = rootPart.CFrame.LookVector
		rootPart.AssemblyLinearVelocity = Vector3.new(
			forwardDir.X * 120,
			0,
			forwardDir.Z * 120
		)
	end)
end

local function launchUpward(character, duration)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	
	enableNoclip(character)

	local elapsed = 0
	local conn

	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		if not rootPart or not rootPart.Parent then
			conn:Disconnect()
			disableNoclip(character)
			return
		end

		if elapsed >= duration then
			conn:Disconnect()
			rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			
			disableNoclip(character)
			return
		end

		rootPart.AssemblyLinearVelocity = Vector3.new(
			rootPart.AssemblyLinearVelocity.X,
			220,
			rootPart.AssemblyLinearVelocity.Z
		)
	end)
end

local function resetState(tracks)
	for _, track in pairs(tracks) do
		pcall(function() track:Stop() end)
	end
	positionAtStrike          = nil
	didDealDamage             = false
	isAnimationSequenceActive = false
end

local function playAnimationSequence(player)
	if isAnimationSequenceActive then return end
	isAnimationSequenceActive = true

	local character = player.Character
	if not character then
		isAnimationSequenceActive = false
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		isAnimationSequenceActive = false
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		isAnimationSequenceActive = false
		return
	end

	local rootPart   = character:FindFirstChild("HumanoidRootPart")
	positionAtStrike = rootPart and rootPart.Position or nil
	didDealDamage    = false

	local enemyLowAtStart = false
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Parent ~= character then
			local enemyRoot = obj.Parent:FindFirstChild("HumanoidRootPart")
			if enemyRoot and rootPart then
				local dist = (rootPart.Position - enemyRoot.Position).Magnitude
				if dist <= DAMAGE_DISTANCE and obj.Health <= 16 then
					enemyLowAtStart = true
					break
				end
			end
		end
	end

	local animRoughEnergy = Instance.new("Animation")
	animRoughEnergy.AnimationId = roughEnergyANIM
	local trackRoughEnergy = animator:LoadAnimation(animRoughEnergy)

	local animLuckyVolley = Instance.new("Animation")
	animLuckyVolley.AnimationId = luckyVolleyANIM
	local trackLuckyVolley = animator:LoadAnimation(animLuckyVolley)

	local animFinisher1 = Instance.new("Animation")
	animFinisher1.AnimationId = Finisher1ANIM
	local trackFinisher1 = animator:LoadAnimation(animFinisher1)

	local allTracks = { trackRoughEnergy, trackLuckyVolley, trackFinisher1 }

	for _, track in pairs(animator:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	task.spawn(function()

		local ok, err = pcall(function()

			trackRoughEnergy:Play()
			trackRoughEnergy.TimePosition = 2
			task.wait(0.5)
			trackRoughEnergy:Stop(0.5)

			local damageConfirmed = waitForDamage(DAMAGE_WAIT)

			if damageConfirmed then

				
				dashForward(character, 0.5)

				trackLuckyVolley:Play()
				trackLuckyVolley.TimePosition = 0
				task.wait(0.5)
				trackLuckyVolley:Stop(0.5)

				if enemyLowAtStart then
					task.wait(0.1)

					local f1Duration = FINISHER1_END - FINISHER1_START

					
					launchUpward(character, f1Duration)

					trackFinisher1:Play()
					trackFinisher1.TimePosition = FINISHER1_START
					task.wait(f1Duration)
					trackFinisher1:Stop(0.2)

					task.wait(0.5)
				end
			end

			task.wait(PLAY_DURATION)

		end)

		if not ok then
			warn("[Skill2] Error:", err)
		end

		
		disableNoclip(LocalPlayer.Character)
		resetState(allTracks)
	end)
end

local function onAnimationPlayed(animationTrack)
	if animationTrack.Animation.AnimationId == cursedStrikeANIM then
		playAnimationSequence(LocalPlayer)
	end
end

local function setupHumanoid(character)
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.Died:Connect(function()
		disableNoclip(character)
		isAnimationSequenceActive = false
		didDealDamage             = false
		positionAtStrike          = nil
		script:Destroy()
	end)

	humanoid.AnimationPlayed:Connect(onAnimationPlayed)
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
setupHumanoid(character)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local cursedStrikeANIM = "rbxassetid://100962226150441"
local roughEnergyANIM  = "rbxassetid://86045680364061"

local PLAY_DURATION = 1.2
local isAnimationSequenceActive = false

local function findTargetInFront()
	local character = LocalPlayer.Character
	if not character then return nil end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end

	local camCF      = workspace.CurrentCamera.CFrame
	local camPos     = camCF.Position
	local camForward = camCF.LookVector

	local bestTarget = nil
	local bestScore  = -math.huge  

	
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Parent ~= character then
			local targetRoot = obj.Parent:FindFirstChild("HumanoidRootPart")
			if targetRoot and obj.Health > 0 then
				local toTarget = (targetRoot.Position - camPos)
				local dist     = toTarget.Magnitude
				local dot      = camForward:Dot(toTarget.Unit)

				
				if dot > 0.3 and dist < 80 then
					
					local score = dot - (dist / 80)
					if score > bestScore then
						bestScore  = score
						bestTarget = targetRoot
					end
				end
			end
		end
	end

	return bestTarget
end

local function rushToTarget(character, target)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or not target then return end

	
	local noclipConn = RunService.Stepped:Connect(function()
		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not rootPart or not rootPart.Parent then
			conn:Disconnect()
			noclipConn:Disconnect()
			return
		end

		local toTarget = target.Position - rootPart.Position
		local dist     = toTarget.Magnitude

		
		if dist < 5 then
			conn:Disconnect()
			noclipConn:Disconnect()

			
			for _, part in pairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = true
				end
			end

			rootPart.AssemblyLinearVelocity = Vector3.zero
			return
		end

		
		local dir = toTarget.Unit
		rootPart.AssemblyLinearVelocity = Vector3.new(
			dir.X * 120,
			0,
			dir.Z * 120
		)
	end)

	
	task.delay(0.4, function()
		if conn.Connected then
			conn:Disconnect()
			noclipConn:Disconnect()

			if rootPart and rootPart.Parent then
				rootPart.AssemblyLinearVelocity = Vector3.zero
				for _, part in pairs(character:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = true
					end
				end
			end
		end
	end)
end

local function playAnimationSequence(player)
	if isAnimationSequenceActive then return end
	isAnimationSequenceActive = true

	local character = player.Character
	if not character then isAnimationSequenceActive = false return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then isAnimationSequenceActive = false return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then isAnimationSequenceActive = false return end

	local animRoughEnergy = Instance.new("Animation")
	animRoughEnergy.AnimationId = roughEnergyANIM
	local trackRoughEnergy = animator:LoadAnimation(animRoughEnergy)

	for _, track in pairs(animator:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	task.spawn(function()

		local ok, err = pcall(function()

			
			local target = findTargetInFront()

			
			if target then
				rushToTarget(character, target)
			end

			task.wait()

			trackRoughEnergy:Play(0.2)
			trackRoughEnergy.TimePosition = 0.52
			trackRoughEnergy:AdjustSpeed(1)

			
			
			task.wait(0.18)

			
			trackRoughEnergy:AdjustSpeed(0)
			task.wait(0.2)

			
			trackRoughEnergy:AdjustSpeed(1)

			
			task.wait(1 - 0.18 - 0.2)
			trackRoughEnergy:Stop(0.5)

			task.wait(PLAY_DURATION)

		end)

		if not ok then
			warn("[Skill3] Error:", err)
		end

		isAnimationSequenceActive = false
		trackRoughEnergy:Stop()
	end)
end

local function onAnimationPlayed(animationTrack)
	if animationTrack.Animation.AnimationId == cursedStrikeANIM then
		playAnimationSequence(LocalPlayer)
	end
end

local function setupHumanoid(character)
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.Died:Connect(function()
		isAnimationSequenceActive = false
	end)

	humanoid.AnimationPlayed:Connect(onAnimationPlayed)
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
setupHumanoid(character)

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
	isAnimationSequenceActive = false
	setupHumanoid(newCharacter)
end)

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local animationConfig = {
    ["95295463826732"] = { id = "rbxassetid://96185406489877", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["124862357369335"] = { id = "rbxassetid://77583711129628", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["105077924973072"] = { id = "rbxassetid://117831239064143", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["92966188946988"] = { id = "rbxassetid://84989753395518", speed = 1,   timePos = 0,   fade = 0.1 }, 
    ["134243365075812"] = { id = "rbxassetid://83843118463884", speed = 1,   timePos = 0,   fade = 0.1 }, 
}

local animationsToBlock = {}
for id in pairs(animationConfig) do
    animationsToBlock[tonumber(id)] = true
end

local queue = {}
local isAnimating = false

local function playReplacement(animationId)
    if isAnimating then
        table.insert(queue, animationId)
        return
    end

    local config = animationConfig[tostring(animationId)]
    if not config then return end

    isAnimating = true

    local anim = Instance.new("Animation")
    anim.AnimationId = config.id

    local track = humanoid:LoadAnimation(anim)
    track:Play(config.fade)          
    track.TimePosition = config.timePos      

    
    track.Stopped:Connect(function()
        isAnimating = false
        if #queue > 0 then
            playReplacement(table.remove(queue, 1))
        end
    end)
end

local function stopBlockedAnimations()
    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
        local id = tonumber(track.Animation.AnimationId:match("%d+"))
        if animationsToBlock[id] then
            track:Stop()
        end
    end
end

local function onAnimationPlayed(track)
    local id = tonumber(track.Animation.AnimationId:match("%d+"))
    if animationsToBlock[id] then
        stopBlockedAnimations()
        track:Stop()
        playReplacement(id)
    end
end

humanoid.AnimationPlayed:Connect(onAnimationPlayed)

local function clampBodyVelocity(obj)
    if obj:IsA("BodyVelocity") then
        obj.Velocity = Vector3.new(obj.Velocity.X, 0, obj.Velocity.Z)
    end
end

character.DescendantAdded:Connect(clampBodyVelocity)
for _, obj in ipairs(character:GetDescendants()) do
    clampBodyVelocity(obj)
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local pl = Players.LocalPlayer
local ef = workspace:WaitForChild("Effects")
local ch = workspace:WaitForChild("Characters")

local ParticleHolder = RS.Utils.Damage.Explode.Head.Attachment

local activeEffects = {}

local function spawnHitEffect(enemyRoot)
    local test = ParticleHolder:Clone()
    test.Parent = enemyRoot
    table.insert(activeEffects, test)

    local emitters = {}
    for _, child in ipairs(test:GetChildren()) do
        if child:IsA("ParticleEmitter") then
            child:Emit(15)
            child.Enabled = true
            table.insert(emitters, child)
        end
    end

    task.spawn(function()
        task.wait(0.1)
        for _, emitter in ipairs(emitters) do
            if emitter.Parent then
                emitter.Enabled = false
            end
        end
        task.wait(0.5)
        if test.Parent then
            test:Destroy()
        end
        
        for i, v in ipairs(activeEffects) do
            if v == test then table.remove(activeEffects, i) break end
        end
    end)
end

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    hum.Died:Connect(function()
        for _, effect in ipairs(activeEffects) do
            if effect and effect.Parent then
                effect:Destroy()
            end
        end
        activeEffects = {}
    end)
end

if pl.Character then onCharacterAdded(pl.Character) end
pl.CharacterAdded:Connect(onCharacterAdded)

local function watchEnemy(enemy)
    local eh = enemy:FindFirstChildOfClass("Humanoid")
    if not eh then return end
    local lastHp = eh.Health
    eh:GetPropertyChangedSignal("Health"):Connect(function()
        local newHp = eh.Health
        if newHp < lastHp then
            local char = ch:FindFirstChild(pl.Name)
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local er = enemy:FindFirstChild("HumanoidRootPart")
            if er and root and (er.Position - root.Position).Magnitude < 15 then
                spawnHitEffect(er)
            end
        end
        lastHp = newHp
    end)
end

for _, ec in ipairs(ch:GetChildren()) do
    if ec.Name ~= pl.Name then watchEnemy(ec) end
end
ch.ChildAdded:Connect(function(c)
    if c.Name ~= pl.Name then
        task.wait(0.2)
        watchEnemy(c)
    end
end)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local cursedStrikeANIM = "rbxassetid://77200218033775"
local roughEnergyANIM  = "rbxassetid://84039122607068"
local vesselMelee1     = "rbxassetid://129678103897608"
local vesselMelee2     = "rbxassetid://99920923658527"
local jumpANIM         = "rbxassetid://135411487367370"
local Finisher1ANIM    = "rbxassetid://106892235857467"
local Finisher2ANIM    = "rbxassetid://77624096831098"

local PLAY_DURATION   = 1.2
local DAMAGE_DISTANCE = 80
local DAMAGE_WAIT     = 1.5

local isAnimationSequenceActive = false
local didDealDamage    = false
local isJumping        = false
local positionAtStrike = nil

local flightConn  = nil
local flightSpeed = 150  

local trackedHumanoids = {}

local function trackHumanoid(humanoid)
	if trackedHumanoids[humanoid] then return end
	trackedHumanoids[humanoid] = true

	local lastHealth = humanoid.Health

	humanoid.HealthChanged:Connect(function(newHealth)
		local character = LocalPlayer.Character
		if not character then return end

		local myRoot    = character:FindFirstChild("HumanoidRootPart")
		local enemyRoot = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")

		if not myRoot or not enemyRoot then return end

		local checkPos = positionAtStrike or myRoot.Position
		local dist = (checkPos - enemyRoot.Position).Magnitude

		if newHealth < lastHealth
			and dist <= DAMAGE_DISTANCE
			and isAnimationSequenceActive then
			didDealDamage = true
		end

		lastHealth = newHealth
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, obj in pairs(workspace:GetDescendants()) do
			if obj:IsA("Humanoid") then
				trackHumanoid(obj)
			end
		end
	end
end)

local function stopFlight()
	if flightConn then
		flightConn:Disconnect()
		flightConn = nil
	end

	local character = LocalPlayer.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			
			rootPart.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function launchPlayer(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	stopFlight()

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	local initDir    = workspace.CurrentCamera.CFrame.LookVector
	local upVelocity = math.sqrt(1.7 * workspace.Gravity * 100)
	rootPart.AssemblyLinearVelocity = (initDir * flightSpeed) + Vector3.new(0, upVelocity, 0)

	flightConn = RunService.Heartbeat:Connect(function()
		if not rootPart or not rootPart.Parent then
			stopFlight()
			return
		end
		local currentDir = workspace.CurrentCamera.CFrame.LookVector
		
		rootPart.AssemblyLinearVelocity = currentDir * flightSpeed
	end)
end

local function waitForDamage(timeout)
	local elapsed = 0
	while elapsed < timeout do
		if didDealDamage then return true end
		elapsed += task.wait(0.05)
	end
	return false
end

local function resetState(tracks)
	stopFlight()
	for _, track in pairs(tracks) do
		pcall(function() track:Stop() end)
	end
	positionAtStrike          = nil
	didDealDamage             = false
	isAnimationSequenceActive = false
	flightSpeed               = 150  
end

local function playAnimationSequence(player)
	if isAnimationSequenceActive then return end
	isAnimationSequenceActive = true

	local character = player.Character
	if not character then
		isAnimationSequenceActive = false
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		isAnimationSequenceActive = false
		return
	end

	local rootPart   = character:FindFirstChild("HumanoidRootPart")
	positionAtStrike = rootPart and rootPart.Position or nil
	didDealDamage    = false
	flightSpeed      = 150  

	
	local enemyLowAtStart = false
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Parent ~= character then
			local enemyRoot = obj.Parent:FindFirstChild("HumanoidRootPart")
			if enemyRoot and rootPart then
				local dist = (rootPart.Position - enemyRoot.Position).Magnitude
				if dist <= DAMAGE_DISTANCE and obj.Health <= 16 then
					enemyLowAtStart = true
					break
				end
			end
		end
	end

	local animRoughEnergy = Instance.new("Animation")
	animRoughEnergy.AnimationId = roughEnergyANIM
	local trackRoughEnergy = humanoid:LoadAnimation(animRoughEnergy)

	local animMelee1 = Instance.new("Animation")
	animMelee1.AnimationId = vesselMelee1
	local trackMelee1 = humanoid:LoadAnimation(animMelee1)

	local animMelee2 = Instance.new("Animation")
	animMelee2.AnimationId = vesselMelee2
	local trackMelee2 = humanoid:LoadAnimation(animMelee2)

	local animJump = Instance.new("Animation")
	animJump.AnimationId = jumpANIM
	local trackJump = humanoid:LoadAnimation(animJump)

	local animFinisher1 = Instance.new("Animation")
	animFinisher1.AnimationId = Finisher1ANIM
	local trackFinisher1 = humanoid:LoadAnimation(animFinisher1)

	local animFinisher2 = Instance.new("Animation")
	animFinisher2.AnimationId = Finisher2ANIM
	local trackFinisher2 = humanoid:LoadAnimation(animFinisher2)

	local allTracks = {
		trackRoughEnergy, trackMelee1, trackMelee2,
		trackJump, trackFinisher1, trackFinisher2
	}

	for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	task.spawn(function()

		local ok, err = pcall(function()

			if not isJumping then
				trackRoughEnergy:Play()
				trackRoughEnergy.TimePosition = 0
				task.wait(0.5)
				trackRoughEnergy:Stop(0.5)
			end

			if isJumping then
				trackJump:Play()
				task.wait(0.51)
				trackJump:Stop(0.2)
				return
			end

			local damageConfirmed = waitForDamage(DAMAGE_WAIT)

			if damageConfirmed then

				
				flightSpeed = 150
				launchPlayer(character)

				trackMelee1:Play()
				task.wait(1.2)
				trackMelee1:Stop(0.5)

				task.wait(0.3)

				trackMelee2:Play()
				trackMelee2.TimePosition = 3.1

				local melee2Duration = trackMelee2.Length - 3.1
				if melee2Duration <= 0 then melee2Duration = 1.5 end

				if enemyLowAtStart and didDealDamage then

					task.wait(melee2Duration - 0.15)
					trackMelee2:Stop(0.15)

					
					flightSpeed = 30

					
					trackFinisher1:Play()
					local f1Duration = trackFinisher1.Length > 0 and trackFinisher1.Length or 2
					task.wait(f1Duration)
					trackFinisher1:Stop(0.3)

					task.wait(0.1)

					
					trackFinisher2:Play()
					trackFinisher2.TimePosition = 5.4
					trackFinisher2:AdjustSpeed(1.3)
					local f2Duration = trackFinisher2.Length > 0
						and ((trackFinisher2.Length - 5.4) / 1.3)
						or 2
					if f2Duration <= 0 then f2Duration = 1 end
					task.wait(f2Duration)
					trackFinisher2:Stop(0.3)

					
					stopFlight()

				else
					task.wait(melee2Duration)
					trackMelee2:Stop(0.5)

					
					stopFlight()
				end
			end

			task.wait(PLAY_DURATION)

		end)

		if not ok then
			warn("[Skill1] Error:", err)
		end

		resetState(allTracks)
	end)
end

local function onAnimationPlayed(animationTrack)
	if animationTrack.Animation.AnimationId == cursedStrikeANIM then
		playAnimationSequence(LocalPlayer)
	end
end

local function setupJumpTracking(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping
			or newState == Enum.HumanoidStateType.Freefall then
			isJumping = true
		else
			isJumping = false
		end
	end)
end

local function setupAnimationListener(character)
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.Died:Connect(function()
		stopFlight()
		isAnimationSequenceActive = false
		didDealDamage             = false
		positionAtStrike          = nil
		isJumping                 = false
		flightSpeed               = 150
	end)

	local animator = humanoid:WaitForChild("Animator")
	animator.AnimationPlayed:Connect(onAnimationPlayed)
	setupJumpTracking(character)
end

if LocalPlayer.Character then
	setupAnimationListener(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(character)
	stopFlight()
	isAnimationSequenceActive = false
	didDealDamage             = false
	positionAtStrike          = nil
	isJumping                 = false
	flightSpeed               = 150
	setupAnimationListener(character)
end)


]====]
SOURCES.MovesetMobile = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character  = player.Character or player.CharacterAdded:Wait()
local humanoid   = character:WaitForChild("Humanoid")
local rootPart   = character:WaitForChild("HumanoidRootPart")
local drAnimator = humanoid:WaitForChild("Animator")

local cleanedUp = false
local function forceCleanup()
    if cleanedUp then return end
    cleanedUp = true

    
    pcall(function()
        if _G.__FlySystemCleanup then _G.__FlySystemCleanup() end
    end)

    
    
    pcall(function() if camera then camera.FieldOfView = 70 end end)

    
    script:Destroy()
end

humanoid.Died:Connect(forceCleanup)
player.CharacterRemoving:Connect(function(char)
    if char == character then forceCleanup() end
end)



local gui=nil
local CFG = {
    NORMAL_SPEED = 30,
    BOOST_SPEED  = 90,
    HOVER_AMP    = 0.5,
    HOVER_FREQ   = 0.5,
    HOVER_SPRING = 14,
    IDLE_FREEZE_TIME = 0.75, 
}

local ANIM = {
    IDLE     = "rbxassetid://99249148382757",
    FORWARD  = "rbxassetid://9443519528",
    BACKWARD = "rbxassetid://134581973800784",
    BOOST    = "rbxassetid://128524425761051",
    LAND     = "rbxassetid://78540995456941",
}

local DR_STARTUP = "rbxassetid://139078698020363"
local DR_RISE    = "rbxassetid://136676738644802"
local DR_FLOAT   = "rbxassetid://131522534497146"

local RISE_HEIGHT = 120
local RISE_SPEED  = 1
local FLOAT_TIME  = 15
local BLEND       = 0.15
local COOLDOWN    = 5

local isDeadCleanup    = false
local flying           = false
local floatMode        = false
local verticalInput    = 0
local currentAnimState = ""

local bodyGyro, bodyVelocity      = nil, nil
local flyConn, animConn, landConn = nil, nil, nil
local landVfxConn                 = nil

local idleTrack, forwardTrack, backwardTrack
local boostTrack, landTrack, floatAnimTrack

local hoverBobT   = 0
local baseHoverY  = 0
local wasIdle     = false
local idleAnimT   = 0
local boostFrozen = false

local boostActive      = false
_G.BoostActive      = false
local boostVfxClone    = nil
local currentFadeTween = nil

local lastWTapTime    = 0
local DOUBLE_TAP_TIME = 0.3 

local prevCameraAngleY = 0   
local tiltSmoothed     = 0   
local TILT_SENSITIVITY = 2.5 

local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))

local cursedStrikeANIM = ReplicatedStorage.Animations.Todo.BruteForce
local roughEnergyANIM  = ReplicatedStorage.Animations.Megumi.Mahoraga.WorldSlash
local isAnimSeqActive  = false

local function playAnimOverride(p)
    if isAnimSeqActive then return end
    isAnimSeqActive = true
    local char = p.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = roughEnergyANIM.AnimationId
    local track = hum:LoadAnimation(anim)
    
    for _, t in pairs(hum:GetPlayingAnimationTracks()) do
        if t ~= idleTrack and t ~= forwardTrack and t ~= backwardTrack
           and t ~= boostTrack and t ~= floatAnimTrack and t ~= landTrack then
            t:Stop()
        end
    end
    task.spawn(function()
        task.wait()
        track:Play(); track.TimePosition = 0.5
        task.wait(1); track:Stop(1)
        task.wait(1.2); isAnimSeqActive = false
    end)
end

local flySound = Instance.new("Sound")
flySound.SoundId       = "rbxassetid://3308152153"
flySound.Volume        = 1.4
flySound.Looped        = true
flySound.PlaybackSpeed = 1.05
flySound.Parent        = SoundService

local boostSound = Instance.new("Sound")
boostSound.SoundId       = "rbxassetid://1295446488"
boostSound.Volume        = 1.5
boostSound.Looped        = false
boostSound.PlaybackSpeed = 1
boostSound.Parent        = SoundService

local function fadeOutSound(dur)
    if currentFadeTween then currentFadeTween:Cancel() end
    currentFadeTween = TweenService:Create(flySound, TweenInfo.new(dur, Enum.EasingStyle.Linear), {Volume = 0})
    currentFadeTween:Play()
    currentFadeTween.Completed:Connect(function()
        flySound:Stop()
        flySound.Volume        = 1.4
        flySound.PlaybackSpeed = 1.05
        currentFadeTween       = nil
    end)
end

local function spawnBoostVfx()
    local char = player.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    if boostVfxClone then boostVfxClone:Destroy(); boostVfxClone = nil end
    local vfxTemplate = ReplicatedStorage.Utils.MeiMei.FallStage3.Attachment
    boostVfxClone = vfxTemplate:Clone()
    boostVfxClone.Parent = head
    boostVfxClone.CFrame = CFrame.new(0,0,0) * CFrame.Angles(math.rad(120),0,0)
    for _, c in ipairs(boostVfxClone:GetChildren()) do
        if c:IsA("ParticleEmitter") then
            c.Enabled = true; c.EmissionDirection = Enum.NormalId.Top; c:Emit(15)
        end
    end
end

local function destroyBoostVfx()
    if not boostVfxClone then return end
    for _, c in ipairs(boostVfxClone:GetChildren()) do
        if c:IsA("ParticleEmitter") then c.Enabled = false end
    end
    local ref = boostVfxClone; boostVfxClone = nil
    task.delay(1.5, function() if ref then ref:Destroy() end end)
end

local activeBoostBlur    = nil
local activeBoostColorFx = nil
local activeBoostBloom   = nil

local function playBoostEffects()
    
    if activeBoostBlur    then activeBoostBlur:Destroy();    activeBoostBlur    = nil end
    if activeBoostColorFx then activeBoostColorFx:Destroy(); activeBoostColorFx = nil end
    if activeBoostBloom   then activeBoostBloom:Destroy();   activeBoostBloom   = nil end

    
    local blur = Instance.new("BlurEffect")
    blur.Size   = 20
    blur.Parent = camera
    activeBoostBlur = blur

    local colorFx = Instance.new("ColorCorrectionEffect")
    colorFx.Brightness = 0.20
    colorFx.Contrast   = 0
    colorFx.Saturation = 0
    colorFx.TintColor  = Color3.fromRGB(255, 255, 255)
    colorFx.Parent     = camera
    activeBoostColorFx = colorFx

    local bloom = Instance.new("BloomEffect")
    bloom.Intensity  = 0.8
    bloom.Size       = 24
    bloom.Threshold  = 0.9
    bloom.Parent     = camera
    activeBoostBloom = bloom

    
    local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    TweenService:Create(blur,    info, { Size       = 0 }):Play()
    TweenService:Create(colorFx, info, { Brightness = 0 }):Play()
    TweenService:Create(bloom,   info, { Intensity  = 0 }):Play()

    
    task.delay(0.7, function()
        if activeBoostBlur    then activeBoostBlur:Destroy();    activeBoostBlur    = nil end
        if activeBoostColorFx then activeBoostColorFx:Destroy(); activeBoostColorFx = nil end
        if activeBoostBloom   then activeBoostBloom:Destroy();   activeBoostBloom   = nil end
        if boostActive then fadeShake() end
    end)

    
    startShake(0.14)
end

local function stopBoostEffects()
    
    if activeBoostBlur    then activeBoostBlur:Destroy();    activeBoostBlur    = nil end
    if activeBoostColorFx then activeBoostColorFx:Destroy(); activeBoostColorFx = nil end
    if activeBoostBloom   then activeBoostBloom:Destroy();   activeBoostBloom   = nil end
    fadeShake()
end

local function spawnLandVfx()
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vfxClone = ReplicatedStorage.Utils.Nanami.CleavingWhirlwind.SlashEmit.Floor:Clone()
    vfxClone.Parent = hrp
    for _, c in ipairs(vfxClone:GetChildren()) do
        if c:IsA("ParticleEmitter") then c.Enabled = true; c:Emit(15) end
    end
    task.delay(0.4, function()
        for _, c in ipairs(vfxClone:GetChildren()) do
            if c:IsA("ParticleEmitter") then c.Enabled = false end
        end
        task.delay(2, function() if vfxClone and vfxClone.Parent then vfxClone:Destroy() end end)
    end)
end

local function startLandVfxMonitor()
    if landVfxConn then landVfxConn:Disconnect(); landVfxConn = nil end
    local vfxFired = false; local elapsed = 0
    landVfxConn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if vfxFired or elapsed > 10 then
            landVfxConn:Disconnect(); landVfxConn = nil; return
        end
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        if hrp.AssemblyLinearVelocity.Y > -1 then return end
        local rp = RaycastParams.new()
        rp.FilterDescendantsInstances = {char}; rp.FilterType = Enum.RaycastFilterType.Exclude
        local res = workspace:Raycast(hrp.Position, Vector3.new(0,-50,0), rp)
        if res and (hrp.Position - res.Position).Magnitude <= 4 then
            vfxFired = true; spawnLandVfx()
        end
    end)
end

local function makeAnim(animator, id)
    local a = Instance.new("Animation")
    a.AnimationId = id
    return animator:LoadAnimation(a)
end

local function setupAnimations(char)
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildWhichIsA("Animator") or Instance.new("Animator", hum)

    idleTrack      = makeAnim(animator, ANIM.IDLE)
    forwardTrack   = makeAnim(animator, ANIM.FORWARD)
    backwardTrack  = makeAnim(animator, ANIM.BACKWARD)
    boostTrack     = makeAnim(animator, ANIM.BOOST)
    landTrack      = makeAnim(animator, ANIM.LAND)
    floatAnimTrack = makeAnim(animator, DR_FLOAT)

    idleTrack.Priority      = Enum.AnimationPriority.Movement
    forwardTrack.Priority   = Enum.AnimationPriority.Movement
    backwardTrack.Priority  = Enum.AnimationPriority.Movement
    boostTrack.Priority     = Enum.AnimationPriority.Action
    landTrack.Priority      = Enum.AnimationPriority.Action
    floatAnimTrack.Priority = Enum.AnimationPriority.Idle

    idleTrack.Looped      = true
    forwardTrack.Looped   = true
    backwardTrack.Looped  = true
    boostTrack.Looped     = true
    floatAnimTrack.Looped = true
end

local function stopAllFlyAnims(fade)
    local f = fade or 0.2
    for _, t in ipairs({idleTrack, forwardTrack, backwardTrack, boostTrack, floatAnimTrack}) do
        if t and t.IsPlaying then t:Stop(f) end
    end
end

local function setAnimState(newState)
    if currentAnimState == newState then return end
    currentAnimState = newState
    stopAllFlyAnims(0.15)

    if newState == "idle" then
        if floatMode then
            if floatAnimTrack then
                floatAnimTrack:Play(0.2)
                task.defer(function()
                    floatAnimTrack:AdjustSpeed(0)
                    floatAnimTrack.TimePosition = 0.7
                end)
            end
        else
            idleAnimT = 0
            if idleTrack then
                idleTrack:Play(0.2)
                task.defer(function()
                    idleTrack:AdjustSpeed(0)
                    idleTrack.TimePosition = CFG.IDLE_FREEZE_TIME
                end)
            end
        end

    elseif newState == "forward" or newState == "backward" then
        local track = newState == "forward" and forwardTrack or backwardTrack
        if track then
            track:Play(0.2)
            task.defer(function()
                track:AdjustSpeed(0); track.TimePosition = 0.1
            end)
        end

    elseif newState == "boost" then
        boostFrozen = false
        if boostTrack then
            boostTrack:Play(0.15)
            task.defer(function()
                boostTrack.TimePosition = 0.4; boostTrack:AdjustSpeed(1)
            end)
        end
    end
end

local function playLanding(hrp)
    if landConn then landConn:Disconnect(); landConn = nil end
    if not landTrack then return end
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    landTrack:Play(0.1); landTrack:AdjustSpeed(1)
    local frozen = false
    landConn = RunService.RenderStepped:Connect(function()
        if not hrp or not hrp.Parent then landConn:Disconnect(); landConn = nil; return end
        local st = hum:GetState()
        local grounded = st == Enum.HumanoidStateType.Running
            or st == Enum.HumanoidStateType.RunningNoPhysics
            or st == Enum.HumanoidStateType.Landed
            or st == Enum.HumanoidStateType.Seated
        if not frozen and landTrack.TimePosition >= 0.1 then landTrack:AdjustSpeed(0); frozen = true end
        if frozen and (hrp.Position.Y <= -0.7 or grounded) then landTrack:AdjustSpeed(1); frozen = false end
        if not landTrack.IsPlaying then landConn:Disconnect(); landConn = nil end
    end)
end

local function activateBoost()
    if not flying then return end
    boostActive = true
    _G.BoostActive = true
    flySound.PlaybackSpeed = 1.35; flySound.Volume = 2
    if not flySound.IsPlaying then flySound:Play() end
    boostSound:Stop(); boostSound:Play()
    spawnBoostVfx()
    
    TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 90}):Play()
    
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            for _, t in pairs(hum:GetPlayingAnimationTracks()) do
                if t ~= boostTrack then t:Stop(0.05) end
            end
        end
    end
    
    playBoostEffects()
end

local function deactivateBoost()
    boostActive = false
    _G.BoostActive = false
    flySound.PlaybackSpeed = 1.05; flySound.Volume = 1.4
    destroyBoostVfx()
    
    TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 70}):Play()
    
    stopBoostEffects()
end

local function startFlying()
    if flying then return end
    if landConn    then landConn:Disconnect();    landConn    = nil end
    if landVfxConn then landVfxConn:Disconnect(); landVfxConn = nil end
    if landTrack and landTrack.IsPlaying then landTrack:Stop(0.2) end

    local char = player.Character
    if not char then return end
    setupAnimations(char)

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end

    flying           = true
    currentAnimState = ""
    hoverBobT        = 0
    baseHoverY       = hrp.Position.Y
    wasIdle          = false
    boostFrozen      = false
    
    prevCameraAngleY = math.atan2(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Z)
    tiltSmoothed     = 0

    hum.PlatformStand = true

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.P         = 30000
    bodyGyro.Parent    = hrp

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Velocity = Vector3.new()
    bodyVelocity.Parent   = hrp

    if animConn then animConn:Disconnect() end
    animConn = RunService.Heartbeat:Connect(function(dt)
        if not flying then return end

        
        if currentAnimState == "idle" and floatMode then
            if floatAnimTrack and floatAnimTrack.IsPlaying then
                floatAnimTrack:AdjustSpeed(0)
                floatAnimTrack.TimePosition = 0.7
            end
        
        elseif currentAnimState == "idle" and not floatMode then
            if idleTrack and idleTrack.IsPlaying and idleTrack.TimePosition ~= CFG.IDLE_FREEZE_TIME then
                idleTrack:AdjustSpeed(0)
                idleTrack.TimePosition = CFG.IDLE_FREEZE_TIME
            end
        end

        if currentAnimState == "forward"  and forwardTrack  and forwardTrack.IsPlaying  then forwardTrack.TimePosition  = 0.1 end
        if currentAnimState == "backward" and backwardTrack and backwardTrack.IsPlaying then backwardTrack.TimePosition = 0.1 end

        
        if currentAnimState == "boost" and boostTrack and boostTrack.IsPlaying then
            local char2 = player.Character
            if char2 then
                local hum2 = char2:FindFirstChildOfClass("Humanoid")
                if hum2 then
                    for _, t in pairs(hum2:GetPlayingAnimationTracks()) do
                        if t ~= boostTrack then t:Stop(0) end
                    end
                end
            end
            if not boostFrozen then
                if boostTrack.TimePosition >= 0.7 then
                    boostFrozen = true; boostTrack:AdjustSpeed(0); boostTrack.TimePosition = 0.7
                end
            else
                boostTrack.TimePosition = 0.7
            end
        end
    end)

    if flyConn then flyConn:Disconnect() end
    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not flying or not hrp.Parent then return end

        local controls = PlayerModule:GetControls()
        local mv       = controls:GetMoveVector()

        local isMoving   = mv.Magnitude > 0.1 or math.abs(verticalInput) > 0.1
        local isBackward = isMoving and mv.Z > 0.1 and mv.Z > math.abs(mv.X)

        if boostActive and (not isMoving or isBackward) then deactivateBoost() end

        local spd     = boostActive and CFG.BOOST_SPEED or CFG.NORMAL_SPEED
        local nowIdle = not isMoving and not boostActive

        if nowIdle then
            if not wasIdle then baseHoverY = hrp.Position.Y; hoverBobT = 0 end
            hoverBobT = hoverBobT + dt
            local targetY = baseHoverY + math.sin(hoverBobT * CFG.HOVER_FREQ * math.pi * 2) * CFG.HOVER_AMP
            bodyVelocity.Velocity = Vector3.new(0, (targetY - hrp.Position.Y) * CFG.HOVER_SPRING, 0)
        else
            baseHoverY = hrp.Position.Y
            local moveDir = camera.CFrame:VectorToWorldSpace(Vector3.new(mv.X, verticalInput, mv.Z))
            if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
            bodyVelocity.Velocity = moveDir * spd
        end
        wasIdle = nowIdle

        if not nowIdle then
            if not flySound.IsPlaying then flySound.Volume = boostActive and 2 or 1.4; flySound:Play() end
        else
            if flySound.IsPlaying then fadeOutSound(0.6) end
        end

        local desired
        if boostActive      then desired = "boost"
        elseif isMoving     then desired = isBackward and "backward" or "forward"
        else                     desired = "idle" end

        setAnimState(desired)

        
        local currentAngleY = math.atan2(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Z)
        local deltaAngle    = currentAngleY - prevCameraAngleY
        if deltaAngle >  math.pi then deltaAngle = deltaAngle - 2*math.pi end
        if deltaAngle < -math.pi then deltaAngle = deltaAngle + 2*math.pi end
        prevCameraAngleY = currentAngleY

        
        local targetTilt = 0
        if boostActive then
            local camTurnSpeed = deltaAngle / math.max(dt, 0.001)
            local dynamicTilt  = math.clamp(camTurnSpeed * TILT_SENSITIVITY, -math.rad(54), math.rad(47))
            targetTilt = math.rad(31) + dynamicTilt
        end
        tiltSmoothed = tiltSmoothed + (targetTilt - tiltSmoothed) * math.min(dt * 2.5, 1)

        bodyGyro.CFrame = camera.CFrame * CFrame.Angles(0, 0, tiltSmoothed)
    end)
end

local function stopFlying()
    if not flying then return end
    flying = false; boostActive = false; boostFrozen = false; floatMode = false

    destroyBoostVfx()

    if bodyGyro     then bodyGyro:Destroy();     bodyGyro     = nil end
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if flyConn      then flyConn:Disconnect();   flyConn      = nil end
    if animConn     then animConn:Disconnect();  animConn     = nil end

    local char = player.Character; local hrp = nil
    if char then
        local hum = char:FindFirstChild("Humanoid")
        if hum then hum.PlatformStand = false end
        hrp = char:FindFirstChild("HumanoidRootPart")
    end

    if flySound.IsPlaying then fadeOutSound(0.8) end
    stopAllFlyAnims(0.3)
    flySound.PlaybackSpeed = 1.05
    
    TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 70}):Play()
    startLandVfxMonitor()
    if hrp and landTrack then playLanding(hrp) end

    verticalInput = 0; currentAnimState = ""; wasIdle = false
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.W then
        if not flying then return end
        local now = os.clock()
        if now - lastWTapTime <= DOUBLE_TAP_TIME then
            if boostActive then deactivateBoost() else activateBoost() end
            lastWTapTime = 0 
        else
            lastWTapTime = now
        end
    end
end)


task.spawn(function()
    local pg = player:WaitForChild("PlayerGui")
    local ctrl = pg:FindFirstChild("Controls"); if not ctrl then return end
    local mob  = ctrl:FindFirstChild("Mobile"); if not mob  then return end
    local jump = mob:FindFirstChild("Jump");    if not jump  then return end
    local spc  = jump:FindFirstChild("Special");if not spc   then return end
    spc.Activated:Connect(function()
        if not flying then return end
        if boostActive then deactivateBoost() else activateBoost() end
    end)
end)

local character  = player.Character or player.CharacterAdded:Wait()
local humanoid   = character:WaitForChild("Humanoid")
local rootPart   = character:WaitForChild("HumanoidRootPart")
local drAnimator = humanoid:WaitForChild("Animator")

local newButton=nil
local cooldownFrame,uiGradient
local function playCooldownVisual()
    if not cooldownFrame or not uiGradient then return end
    cooldownFrame.Visible   = true
    uiGradient.Transparency = NumberSequence.new(0)
    local startTime = tick(); local cdConn
    cdConn = RunService.RenderStepped:Connect(function()
        local p = math.clamp((tick() - startTime) / COOLDOWN, 0, 1)
        if p >= 1 then cdConn:Disconnect(); cooldownFrame.Visible = false; return end
        if p <= 0.001 then
            uiGradient.Transparency = NumberSequence.new(0)
        else
            uiGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0,                       1),
                NumberSequenceKeypoint.new(p,                       1),
                NumberSequenceKeypoint.new(math.min(p+0.001, 1),   0),
                NumberSequenceKeypoint.new(1,                       0),
            })
        end
    end)
end

local shakeIntensity = 0; local shakeFading = false; local shakeConn = nil

local function startShake(intensity)
    shakeIntensity = intensity; shakeFading = false
    if shakeConn then shakeConn:Disconnect() end
    shakeConn = RunService.RenderStepped:Connect(function(dt)
        if shakeIntensity <= 0 then
            if shakeConn then shakeConn:Disconnect(); shakeConn = nil end; return
        end
        local rx = (math.random()-0.5)*2*shakeIntensity
        local ry = (math.random()-0.5)*2*shakeIntensity
        local rz = (math.random()-0.5)*2*shakeIntensity
        camera.CFrame = camera.CFrame * CFrame.new(rx,ry,0) * CFrame.Angles(math.rad(rz*0.4), math.rad(rx*0.2), 0)
        if shakeFading then
            shakeIntensity = shakeIntensity - (shakeIntensity * dt * 3)
            if shakeIntensity < 0.002 then shakeIntensity = 0 end
        end
    end)
end

local function fadeShake() shakeFading = true end
local function stopShake()
    shakeIntensity = 0; shakeFading = false
    if shakeConn then shakeConn:Disconnect(); shakeConn = nil end
end

local function loadDRAnim(id)
    local a = Instance.new("Animation"); a.AnimationId = id
    return drAnimator:LoadAnimation(a)
end

local drActive = false

local function triggerDestructiveRush()
    if drActive then return end
    drActive = true
    playCooldownVisual()

    humanoid.PlatformStand = true
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero; bv.MaxForce = Vector3.new(0, math.huge, 0); bv.Parent = rootPart

    
    local drGyro = Instance.new("BodyGyro")
    drGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    drGyro.P         = 50000
    drGyro.D         = 500
    local look = rootPart.CFrame.LookVector
    drGyro.CFrame    = CFrame.new(Vector3.zero, Vector3.new(look.X, 0, look.Z))
    drGyro.Parent    = rootPart

    
    local startTrack = loadDRAnim(DR_STARTUP)
    startTrack.Priority = Enum.AnimationPriority.Action4
    startTrack:Play(BLEND); startTrack.TimePosition = 0
    startShake(0.09)

    
    local drStartVfxClone = ReplicatedStorage.Utils.Mechamaru.EjectDeathVFX.DustLand2.VFX.extra2:Clone()
    drStartVfxClone.Parent = rootPart
    for _, child in ipairs(drStartVfxClone:GetChildren()) do
        if child:IsA("ParticleEmitter") then
            child:Emit(15); child.Enabled = true
        end
    end

    local frozen = false; local conn
    conn = RunService.Heartbeat:Connect(function()

        if not frozen and startTrack.TimePosition >= 0.3 then
            frozen = true; startTrack:AdjustSpeed(0)
            task.wait(1); startTrack:AdjustSpeed(1)
        end

        if frozen and startTrack.TimePosition >= 0.6 then
            conn:Disconnect(); fadeShake()

            
            local riseTrack = loadDRAnim(DR_RISE)
            riseTrack.Priority = Enum.AnimationPriority.Action4
            riseTrack.Looped   = true
            riseTrack:Play(BLEND); riseTrack.TimePosition = 4.1; riseTrack:AdjustSpeed(0)
            startTrack:Stop(BLEND)

            
            if drStartVfxClone then
                for _, child in ipairs(drStartVfxClone:GetChildren()) do
                    if child:IsA("ParticleEmitter") then child.Enabled = false end
                end
                local refS = drStartVfxClone; drStartVfxClone = nil
                task.delay(2, function() if refS and refS.Parent then refS:Destroy() end end)
            end

            
            local risingAnchor = Instance.new("Part")
            risingAnchor.Anchored     = true
            risingAnchor.CanCollide   = false
            risingAnchor.CastShadow   = false
            risingAnchor.Transparency = 1
            risingAnchor.Size         = Vector3.new(1, 1, 1)
            risingAnchor.CFrame       = rootPart.CFrame
            risingAnchor.Parent       = workspace

            local risingVfxClone = ReplicatedStorage.Utils.Mechamaru.DeathVFX.DustLand:Clone()
            risingVfxClone.Parent = risingAnchor
            for _, child in ipairs(risingVfxClone:GetChildren()) do
                if child:IsA("ParticleEmitter") then
                    child:Emit(15); child.Enabled = true
                end
            end

            task.delay(0.5, function()
                if risingVfxClone and risingVfxClone.Parent then
                    for _, child in ipairs(risingVfxClone:GetChildren()) do
                        if child:IsA("ParticleEmitter") then child.Enabled = false end
                    end
                end
                task.delay(2, function()
                    if risingAnchor and risingAnchor.Parent then risingAnchor:Destroy() end
                end)
            end)

            
            local risingSound = Instance.new("Sound")
            risingSound.SoundId = "rbxassetid://90269024228015"
            risingSound.Volume  = 1
            risingSound.Parent  = SoundService
            risingSound:Play()
            game:GetService("Debris"):AddItem(risingSound, 10)

            local tween = TweenService:Create(
                rootPart,
                TweenInfo.new(RISE_SPEED, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { CFrame = rootPart.CFrame + Vector3.new(0, RISE_HEIGHT, 0) }
            )
            tween:Play()

            tween.Completed:Connect(function()
                stopShake(); riseTrack:Stop(BLEND)

                
                bv:Destroy()
                
                if drGyro then drGyro:Destroy(); drGyro = nil end
                floatMode = true
                startFlying()

                task.wait(FLOAT_TIME)

                floatMode        = false
                currentAnimState = ""

                task.wait(COOLDOWN)
                drActive = false
            end)
        end
    end)
end

Bridge.Register("Fly",function() if flying then stopFlying() else startFlying() end end)
Bridge.Register("Boost",function() if boostActive then deactivateBoost() else activateBoost() end end)
Bridge.Register("Rush",triggerDestructiveRush)
local function cleanupOnDeath()
    
    if isDeadCleanup then return end
    
    isDeadCleanup = true

    
    pcall(function() if flying then stopFlying() end end)

    pcall(function() if flyConn     then flyConn:Disconnect();     flyConn     = nil end end)
    pcall(function() if animConn    then animConn:Disconnect();    animConn    = nil end end)
    pcall(function() if landConn    then landConn:Disconnect();    landConn    = nil end end)
    pcall(function() if landVfxConn then landVfxConn:Disconnect(); landVfxConn = nil end end)
    pcall(function() if shakeConn   then shakeConn:Disconnect();   shakeConn   = nil end end)
    pcall(function() if _G.__FlySystemThrowBoostConn then _G.__FlySystemThrowBoostConn:Disconnect(); _G.__FlySystemThrowBoostConn = nil end end)

    pcall(function() if bodyGyro     then bodyGyro:Destroy();     bodyGyro     = nil end end)
    pcall(function() if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end end)

    pcall(destroyBoostVfx)
    pcall(stopBoostEffects)

    pcall(function() flySound:Stop();   flySound:Destroy()   end)
    pcall(function() boostSound:Stop(); boostSound:Destroy() end)

    
    pcall(function() if newButton and newButton.Parent then newButton:Destroy() end end)

    
    pcall(function() if gui and gui.Parent then gui:Destroy() end end)

    pcall(function() if camera then camera.FieldOfView = 70 end end)

    flying           = false
    boostActive      = false
    boostFrozen      = false
    floatMode        = false
    drActive         = false
    verticalInput    = 0
    currentAnimState = ""

    
    pcall(function() script:Destroy() end)
end

local deathConn
local function bindDeathHandler(char)
    if deathConn then deathConn:Disconnect(); deathConn = nil end
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    if hum.Health <= 0 then
        cleanupOnDeath()
        return
    end
    deathConn = hum.Died:Connect(cleanupOnDeath)
end

bindDeathHandler(character)
player.CharacterAdded:Connect(bindDeathHandler)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ANIM_ID = "rbxassetid://127171275866632"
local BUTTON_IMAGE_ID = "rbxassetid://8618269848"

local HANG_SOUND_ID = "rbxassetid://82687386744947"
local HANG_SOUND_VOLUME = 0.3

local POSITION_OFFSET = Vector3.new(-0.1, -0.5, -2)
local ROTATION_OFFSET = Vector3.new(10, 180, 0)

local MAX_TARGET_DISTANCE = 15
local REMOTE_HIT_COUNT    = 4
local REMOTE_HIT_DELAY    = 0.5
local AFTER_LAST_HIT_DELAY = 0.45   
local BUTTON_COOLDOWN     = 8

local function getRemote(...)
	local path = { ... }
	local ok, remote = pcall(function()
		local node = ReplicatedStorage
		for _, child in ipairs(path) do
			node = node:WaitForChild(child, 5)
		end
		return node
	end)
	return ok and remote or nil
end

local activatedRemote = getRemote("Knit","Knit","Services","ItadoriService","RE","Activated")

if not activatedRemote then warn("[Choke] Activated remote not found!") end

local gui=nil
local clickSound=Instance.new("Sound",game:GetService("SoundService"))
clickSound.SoundId="rbxassetid://3077287610";clickSound.Volume=4
local cooldownLabel={Text=""}
local button={}
local active = false
local lockedTarget = nil
local animTrack = nil
local hangSound = nil
local healthWatchConn = nil
local lastActivationTime = -math.huge

local sequenceRunId = 0

local function getClosestTargetToCamera(hrp)
	local closest = nil
	local bestScore = -math.huge

	local camPos     = camera.CFrame.Position
	local camForward = camera.CFrame.LookVector

	for _, model in pairs(workspace:GetDescendants()) do
		if model:IsA("Model")
			and model ~= player.Character
			and model:FindFirstChild("Humanoid")
			and model:FindFirstChild("HumanoidRootPart")
			and model:FindFirstChild("Head") then

			local hum = model:FindFirstChild("Humanoid")

			if hum and hum.Health > 0 then
				local targetHRP = model.HumanoidRootPart
				local dist = (hrp.Position - targetHRP.Position).Magnitude

				if dist <= MAX_TARGET_DISTANCE then
					local toTarget = (targetHRP.Position - camPos)
					local dot = camForward:Dot(toTarget.Unit)

					if dot > 0.3 then
						local score = dot - (dist / MAX_TARGET_DISTANCE)
						if score > bestScore then
							bestScore = score
							closest = model
						end
					end
				end
			end
		end
	end

	return closest
end

local function startHangSound(parent)
	if hangSound then hangSound:Destroy() end
	hangSound = Instance.new("Sound")
	hangSound.SoundId = HANG_SOUND_ID
	hangSound.Volume = HANG_SOUND_VOLUME
	hangSound.Looped = true
	hangSound.Parent = parent
	hangSound:Play()
end

local function stopHangSound()
	if hangSound then
		hangSound:Stop()
		hangSound:Destroy()
		hangSound = nil
	end
end

local function forceAnimation(humanoid)
	if animTrack then
		animTrack:Stop()
		animTrack:Destroy()
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = ANIM_ID

	animTrack = humanoid:LoadAnimation(anim)
	animTrack.Priority = Enum.AnimationPriority.Action4
	animTrack.Looped = true

	animTrack:Play(0)
	task.wait()
	animTrack.TimePosition = 1
	animTrack:AdjustSpeed(0)
end

local function releaseHold()
	active = false
	lockedTarget = nil

	button.ImageColor3 = Color3.fromRGB(255, 255, 255)

	if animTrack then
		animTrack:Stop()
		animTrack:Destroy()
		animTrack = nil
	end

	stopHangSound()

	if healthWatchConn then
		healthWatchConn:Disconnect()
		healthWatchConn = nil
	end

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.AutoRotate = true
		end
	end
end

local function watchMyHealth(humanoid)
	if healthWatchConn then
		healthWatchConn:Disconnect()
	end

	local lastHealth = humanoid.Health

	healthWatchConn = humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealth and active then
			print("[Choke] ضرر — تحرير الخنقة (السلسلة تكمل بالخلفية)")
			releaseHold()
		end
		lastHealth = newHealth
	end)
end

local function runRemoteSequence(myId)
	if not activatedRemote then return end

	for i = 1, REMOTE_HIT_COUNT do
		
		if myId ~= sequenceRunId then
			print("[Choke] أُلغيت عند Punch " .. i .. " (سلسلة جديدة/إلغاء يدوي)")
			return
		end

		pcall(function()
			activatedRemote:FireServer(false)
		end)
		print("[Choke] Punch " .. i .. " ✅")

		if i < REMOTE_HIT_COUNT then
			local startWait = tick()
			repeat
				RunService.Heartbeat:Wait()
			until tick() - startWait >= REMOTE_HIT_DELAY or myId ~= sequenceRunId

			if myId ~= sequenceRunId then return end
		end
	end

	print("[Choke] اكتملت 4 ضربات — ننتظر " .. AFTER_LAST_HIT_DELAY .. "s ثم إيقاف")

	
	local waitStart = tick()
	repeat
		RunService.Heartbeat:Wait()
	until tick() - waitStart >= AFTER_LAST_HIT_DELAY or myId ~= sequenceRunId

	if myId == sequenceRunId then
		print("[Choke] إيقاف نهائي بعد 4 Punch")
		releaseHold()
	end
end

Bridge.Register("Choke",function()
	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid then return end

	if not active then
		local now = tick()
		local elapsed = now - lastActivationTime
		if elapsed < BUTTON_COOLDOWN then
			print(string.format("[Choke] كولداون — انتظر %.1f ثانية", BUTTON_COOLDOWN - elapsed))
			return
		end

		local target = getClosestTargetToCamera(hrp)

		if not target then
			print("[Choke] ما في هدف ضمن " .. MAX_TARGET_DISTANCE .. " studs من الكاميرا")
			return
		end

		clickSound:Play()

		active = true
		lockedTarget = target
		lastActivationTime = now

		sequenceRunId += 1
		local myId = sequenceRunId

		button.ImageColor3 = Color3.fromRGB(100, 255, 100)

		forceAnimation(humanoid)
		startHangSound(hrp)
		watchMyHealth(humanoid)

		humanoid.AutoRotate = false

		
		task.spawn(function()
			runRemoteSequence(myId)
		end)

	else
		clickSound:Play()
		sequenceRunId += 1
		releaseHold()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(1)
	print("[Choke] Character respawned — تحرير الجانب البصري فقط")
	releaseHold()
end)

RunService.RenderStepped:Connect(function()
	local now = tick()
	local elapsed = now - lastActivationTime

	if not active then
		if elapsed < BUTTON_COOLDOWN then
			cooldownLabel.Text = string.format("%.1f", BUTTON_COOLDOWN - elapsed)
			button.ImageColor3 = Color3.fromRGB(130, 130, 130)
			button.ImageTransparency = 0.35
		else
			cooldownLabel.Text = ""
			button.ImageColor3 = Color3.fromRGB(255, 255, 255)
			button.ImageTransparency = 0
		end
		return
	end

	cooldownLabel.Text = ""

	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid then return end

	
	if humanoid.Health <= 0 then
		print("[Choke] موت حقيقي — تحرير الجانب البصري")
		releaseHold()
		return
	end

	
	
	if not lockedTarget or not lockedTarget.Parent then
		return
	end

	local targetHum = lockedTarget:FindFirstChildOfClass("Humanoid")

	if not targetHum or targetHum.Health <= 0 then
		return
	end

	local head = lockedTarget:FindFirstChild("Head")

	if not head then
		return
	end

	if not hangSound or not hangSound.IsPlaying then
		startHangSound(hrp)
	end

	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end

	local finalCFrame = head.CFrame
		* CFrame.new(POSITION_OFFSET)
		* CFrame.Angles(
			math.rad(ROTATION_OFFSET.X),
			math.rad(ROTATION_OFFSET.Y),
			math.rad(ROTATION_OFFSET.Z)
		)

	hrp.CFrame = finalCFrame

	if not animTrack or not animTrack.IsPlaying then
		forceAnimation(humanoid)
	end

	if animTrack then
		animTrack.TimePosition = 1
		animTrack:AdjustSpeed(0)
	end
end)

local disabled = false

local function stopEverything()
	disabled = true

	if gui then
		gui:Destroy()
	end

	releaseHold()

	if healthWatchConn then
		healthWatchConn:Disconnect()
	end
end

local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(stopEverything)
end

if player.Character then
	hookCharacter(player.Character)
end

player.CharacterAdded:Connect(stopEverything)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local character
local root

local function SetupCharacter(char)
	character = char
	root = char:WaitForChild("HumanoidRootPart")
end

SetupCharacter(player.Character or player.CharacterAdded:Wait())

player.CharacterAdded:Connect(SetupCharacter)

local RightActivated = ReplicatedStorage
	:WaitForChild("Knit")
	:WaitForChild("Knit")
	:WaitForChild("Services")
	:WaitForChild("ItadoriService")
	:WaitForChild("RE")
	:WaitForChild("RightActivated")

local ThrowableFolder = Workspace.Map.Destructible:WaitForChild("Throwable")

local boostConnection

local function StartThrowBoost()

	if boostConnection then
		boostConnection:Disconnect()
	end

	boostConnection = RunService.Heartbeat:Connect(function()

		if not _G.BoostActive then
			return
		end

		if not character or not root then
			return
		end

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}

		local direction = root.CFrame.LookVector * 15

		local result = Workspace:Raycast(
			root.Position,
			direction,
			rayParams
		)

		if result and result.Instance then

			local hit = result.Instance

			if hit:IsDescendantOf(ThrowableFolder) then
				RightActivated:FireServer()
			end
		end
	end)
end

StartThrowBoost()

_G.__FlySystemThrowBoostConn = boostConnection
]====]
SOURCES.MovesetPC = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character  = player.Character or player.CharacterAdded:Wait()
local humanoid   = character:WaitForChild("Humanoid")
local rootPart   = character:WaitForChild("HumanoidRootPart")
local drAnimator = humanoid:WaitForChild("Animator")

local cleanedUp = false

local flySystemDead = false
local function forceCleanup()
    if cleanedUp then return end
    cleanedUp = true
    flySystemDead = true  

    
    
    pcall(function()
        if _G.__FlySystemCleanup then _G.__FlySystemCleanup() end
    end)
    pcall(function()
        if _G.__ChokeCleanup then _G.__ChokeCleanup() end
    end)

    
    
    pcall(function() if camera then camera.FieldOfView = 70 end end)

    
    script:Destroy()
end

humanoid.Died:Connect(forceCleanup)
player.CharacterRemoving:Connect(function(char)
    if char == character then forceCleanup() end
end)



local gui=nil
local CFG = {
    NORMAL_SPEED = 30,
    BOOST_SPEED  = 90,
    HOVER_AMP    = 0.5,
    HOVER_FREQ   = 0.5,
    HOVER_SPRING = 14,
    IDLE_FREEZE_TIME = 0.75, 
}

local ANIM = {
    IDLE     = "rbxassetid://99249148382757",
    FORWARD  = "rbxassetid://9443519528",
    BACKWARD = "rbxassetid://134581973800784",
    BOOST    = "rbxassetid://128524425761051",
    LAND     = "rbxassetid://78540995456941",
}

local DR_STARTUP = "rbxassetid://139078698020363"
local DR_RISE    = "rbxassetid://136676738644802"
local DR_FLOAT   = "rbxassetid://131522534497146"

local RISE_HEIGHT = 120
local RISE_SPEED  = 1
local FLOAT_TIME  = 15
local BLEND       = 0.15
local COOLDOWN    = 5

local isDeadCleanup    = false
local flying           = false
local floatMode        = false
local verticalInput    = 0
local currentAnimState = ""

local bodyGyro, bodyVelocity      = nil, nil
local flyConn, animConn, landConn = nil, nil, nil
local landVfxConn                 = nil

local idleTrack, forwardTrack, backwardTrack
local boostTrack, landTrack, floatAnimTrack

local hoverBobT   = 0
local baseHoverY  = 0
local wasIdle     = false
local idleAnimT   = 0
local boostFrozen = false

local boostActive      = false
_G.BoostActive      = false
local boostVfxClone    = nil
local currentFadeTween = nil

local lastWTapTime    = 0
local DOUBLE_TAP_TIME = 0.3 

local prevCameraAngleY = 0   
local tiltSmoothed     = 0   
local TILT_SENSITIVITY = 2.5 

local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))

local cursedStrikeANIM = ReplicatedStorage.Animations.Todo.BruteForce
local roughEnergyANIM  = ReplicatedStorage.Animations.Megumi.Mahoraga.WorldSlash
local isAnimSeqActive  = false

local function playAnimOverride(p)
    if isAnimSeqActive then return end
    isAnimSeqActive = true
    local char = p.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = roughEnergyANIM.AnimationId
    local track = hum:LoadAnimation(anim)
    
    for _, t in pairs(hum:GetPlayingAnimationTracks()) do
        if t ~= idleTrack and t ~= forwardTrack and t ~= backwardTrack
           and t ~= boostTrack and t ~= floatAnimTrack and t ~= landTrack then
            t:Stop()
        end
    end
    task.spawn(function()
        task.wait()
        track:Play(); track.TimePosition = 0.5
        task.wait(1); track:Stop(1)
        task.wait(1.2); isAnimSeqActive = false
    end)
end

local flySound = Instance.new("Sound")
flySound.SoundId       = "rbxassetid://3308152153"
flySound.Volume        = 1.4
flySound.Looped        = true
flySound.PlaybackSpeed = 1.05
flySound.Parent        = SoundService

local boostSound = Instance.new("Sound")
boostSound.SoundId       = "rbxassetid://1295446488"
boostSound.Volume        = 1.5
boostSound.Looped        = false
boostSound.PlaybackSpeed = 1
boostSound.Parent        = SoundService

local function fadeOutSound(dur)
    if currentFadeTween then currentFadeTween:Cancel() end
    currentFadeTween = TweenService:Create(flySound, TweenInfo.new(dur, Enum.EasingStyle.Linear), {Volume = 0})
    currentFadeTween:Play()
    currentFadeTween.Completed:Connect(function()
        flySound:Stop()
        flySound.Volume        = 1.4
        flySound.PlaybackSpeed = 1.05
        currentFadeTween       = nil
    end)
end

local function spawnBoostVfx()
    local char = player.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    if boostVfxClone then boostVfxClone:Destroy(); boostVfxClone = nil end
    local vfxTemplate = ReplicatedStorage.Utils.MeiMei.FallStage3.Attachment
    boostVfxClone = vfxTemplate:Clone()
    boostVfxClone.Parent = head
    boostVfxClone.CFrame = CFrame.new(0,0,0) * CFrame.Angles(math.rad(120),0,0)
    for _, c in ipairs(boostVfxClone:GetChildren()) do
        if c:IsA("ParticleEmitter") then
            c.Enabled = true; c.EmissionDirection = Enum.NormalId.Top; c:Emit(15)
        end
    end
end

local function destroyBoostVfx()
    if not boostVfxClone then return end
    for _, c in ipairs(boostVfxClone:GetChildren()) do
        if c:IsA("ParticleEmitter") then c.Enabled = false end
    end
    local ref = boostVfxClone; boostVfxClone = nil
    task.delay(1.5, function() if ref then ref:Destroy() end end)
end

local activeBoostBlur    = nil
local activeBoostColorFx = nil
local activeBoostBloom   = nil

local function playBoostEffects()
    
    if activeBoostBlur    then activeBoostBlur:Destroy();    activeBoostBlur    = nil end
    if activeBoostColorFx then activeBoostColorFx:Destroy(); activeBoostColorFx = nil end
    if activeBoostBloom   then activeBoostBloom:Destroy();   activeBoostBloom   = nil end

    
    local blur = Instance.new("BlurEffect")
    blur.Size   = 20
    blur.Parent = camera
    activeBoostBlur = blur

    local colorFx = Instance.new("ColorCorrectionEffect")
    colorFx.Brightness = 0.20
    colorFx.Contrast   = 0
    colorFx.Saturation = 0
    colorFx.TintColor  = Color3.fromRGB(255, 255, 255)
    colorFx.Parent     = camera
    activeBoostColorFx = colorFx

    local bloom = Instance.new("BloomEffect")
    bloom.Intensity  = 0.8
    bloom.Size       = 24
    bloom.Threshold  = 0.9
    bloom.Parent     = camera
    activeBoostBloom = bloom

    
    local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    TweenService:Create(blur,    info, { Size       = 0 }):Play()
    TweenService:Create(colorFx, info, { Brightness = 0 }):Play()
    TweenService:Create(bloom,   info, { Intensity  = 0 }):Play()

    
    task.delay(0.7, function()
        if activeBoostBlur    then activeBoostBlur:Destroy();    activeBoostBlur    = nil end
        if activeBoostColorFx then activeBoostColorFx:Destroy(); activeBoostColorFx = nil end
        if activeBoostBloom   then activeBoostBloom:Destroy();   activeBoostBloom   = nil end
        if boostActive then fadeShake() end
    end)

    
    startShake(0.14)
end

local function stopBoostEffects()
    
    if activeBoostBlur    then activeBoostBlur:Destroy();    activeBoostBlur    = nil end
    if activeBoostColorFx then activeBoostColorFx:Destroy(); activeBoostColorFx = nil end
    if activeBoostBloom   then activeBoostBloom:Destroy();   activeBoostBloom   = nil end
    fadeShake()
end

local function spawnLandVfx()
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vfxClone = ReplicatedStorage.Utils.Nanami.CleavingWhirlwind.SlashEmit.Floor:Clone()
    vfxClone.Parent = hrp
    for _, c in ipairs(vfxClone:GetChildren()) do
        if c:IsA("ParticleEmitter") then c.Enabled = true; c:Emit(15) end
    end
    task.delay(0.4, function()
        for _, c in ipairs(vfxClone:GetChildren()) do
            if c:IsA("ParticleEmitter") then c.Enabled = false end
        end
        task.delay(2, function() if vfxClone and vfxClone.Parent then vfxClone:Destroy() end end)
    end)
end

local function startLandVfxMonitor()
    if landVfxConn then landVfxConn:Disconnect(); landVfxConn = nil end
    local vfxFired = false; local elapsed = 0
    landVfxConn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if vfxFired or elapsed > 10 then
            landVfxConn:Disconnect(); landVfxConn = nil; return
        end
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        if hrp.AssemblyLinearVelocity.Y > -1 then return end
        local rp = RaycastParams.new()
        rp.FilterDescendantsInstances = {char}; rp.FilterType = Enum.RaycastFilterType.Exclude
        local res = workspace:Raycast(hrp.Position, Vector3.new(0,-50,0), rp)
        if res and (hrp.Position - res.Position).Magnitude <= 4 then
            vfxFired = true; spawnLandVfx()
        end
    end)
end

local function makeAnim(animator, id)
    local a = Instance.new("Animation")
    a.AnimationId = id
    return animator:LoadAnimation(a)
end

local function setupAnimations(char)
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildWhichIsA("Animator") or Instance.new("Animator", hum)

    idleTrack      = makeAnim(animator, ANIM.IDLE)
    forwardTrack   = makeAnim(animator, ANIM.FORWARD)
    backwardTrack  = makeAnim(animator, ANIM.BACKWARD)
    boostTrack     = makeAnim(animator, ANIM.BOOST)
    landTrack      = makeAnim(animator, ANIM.LAND)
    floatAnimTrack = makeAnim(animator, DR_FLOAT)

    idleTrack.Priority      = Enum.AnimationPriority.Movement
    forwardTrack.Priority   = Enum.AnimationPriority.Movement
    backwardTrack.Priority  = Enum.AnimationPriority.Movement
    boostTrack.Priority     = Enum.AnimationPriority.Action
    landTrack.Priority      = Enum.AnimationPriority.Action
    floatAnimTrack.Priority = Enum.AnimationPriority.Idle

    idleTrack.Looped      = true
    forwardTrack.Looped   = true
    backwardTrack.Looped  = true
    boostTrack.Looped     = true
    floatAnimTrack.Looped = true
end

local function stopAllFlyAnims(fade)
    local f = fade or 0.2
    for _, t in ipairs({idleTrack, forwardTrack, backwardTrack, boostTrack, floatAnimTrack}) do
        if t and t.IsPlaying then t:Stop(f) end
    end
end

local function setAnimState(newState)
    if currentAnimState == newState then return end
    currentAnimState = newState
    stopAllFlyAnims(0.15)

    if newState == "idle" then
        if floatMode then
            if floatAnimTrack then
                floatAnimTrack:Play(0.2)
                task.defer(function()
                    floatAnimTrack:AdjustSpeed(0)
                    floatAnimTrack.TimePosition = 0.7
                end)
            end
        else
            idleAnimT = 0
            if idleTrack then
                idleTrack:Play(0.2)
                task.defer(function()
                    idleTrack:AdjustSpeed(0)
                    idleTrack.TimePosition = CFG.IDLE_FREEZE_TIME
                end)
            end
        end

    elseif newState == "forward" or newState == "backward" then
        local track = newState == "forward" and forwardTrack or backwardTrack
        if track then
            track:Play(0.2)
            task.defer(function()
                track:AdjustSpeed(0); track.TimePosition = 0.1
            end)
        end

    elseif newState == "boost" then
        boostFrozen = false
        if boostTrack then
            boostTrack:Play(0.15)
            task.defer(function()
                boostTrack.TimePosition = 0.4; boostTrack:AdjustSpeed(1)
            end)
        end
    end
end

local function playLanding(hrp)
    if landConn then landConn:Disconnect(); landConn = nil end
    if not landTrack then return end
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    landTrack:Play(0.1); landTrack:AdjustSpeed(1)
    local frozen = false
    landConn = RunService.RenderStepped:Connect(function()
        if not hrp or not hrp.Parent then landConn:Disconnect(); landConn = nil; return end
        local st = hum:GetState()
        local grounded = st == Enum.HumanoidStateType.Running
            or st == Enum.HumanoidStateType.RunningNoPhysics
            or st == Enum.HumanoidStateType.Landed
            or st == Enum.HumanoidStateType.Seated
        if not frozen and landTrack.TimePosition >= 0.1 then landTrack:AdjustSpeed(0); frozen = true end
        if frozen and (hrp.Position.Y <= -0.7 or grounded) then landTrack:AdjustSpeed(1); frozen = false end
        if not landTrack.IsPlaying then landConn:Disconnect(); landConn = nil end
    end)
end

local function activateBoost()
    if not flying then return end
    boostActive = true
    _G.BoostActive = true
    flySound.PlaybackSpeed = 1.35; flySound.Volume = 2
    if not flySound.IsPlaying then flySound:Play() end
    boostSound:Stop(); boostSound:Play()
    spawnBoostVfx()
    
    TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 90}):Play()
    
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            for _, t in pairs(hum:GetPlayingAnimationTracks()) do
                if t ~= boostTrack then t:Stop(0.05) end
            end
        end
    end
    
    playBoostEffects()
end

local function deactivateBoost()
    boostActive = false
    _G.BoostActive = false
    flySound.PlaybackSpeed = 1.05; flySound.Volume = 1.4
    destroyBoostVfx()
    
    TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 70}):Play()
    
    stopBoostEffects()
end

local function startFlying()
    if flySystemDead then return end  
    if flying then return end
    if landConn    then landConn:Disconnect();    landConn    = nil end
    if landVfxConn then landVfxConn:Disconnect(); landVfxConn = nil end
    if landTrack and landTrack.IsPlaying then landTrack:Stop(0.2) end

    local char = player.Character
    if not char then return end
    setupAnimations(char)

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end

    flying           = true
    currentAnimState = ""
    hoverBobT        = 0
    baseHoverY       = hrp.Position.Y
    wasIdle          = false
    boostFrozen      = false
    
    prevCameraAngleY = math.atan2(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Z)
    tiltSmoothed     = 0

    hum.PlatformStand = true

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.P         = 30000
    bodyGyro.Parent    = hrp

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Velocity = Vector3.new()
    bodyVelocity.Parent   = hrp

    if animConn then animConn:Disconnect() end
    animConn = RunService.Heartbeat:Connect(function(dt)
        if not flying then return end

        
        if currentAnimState == "idle" and floatMode then
            if floatAnimTrack and floatAnimTrack.IsPlaying then
                floatAnimTrack:AdjustSpeed(0)
                floatAnimTrack.TimePosition = 0.7
            end
        
        elseif currentAnimState == "idle" and not floatMode then
            if idleTrack and idleTrack.IsPlaying and idleTrack.TimePosition ~= CFG.IDLE_FREEZE_TIME then
                idleTrack:AdjustSpeed(0)
                idleTrack.TimePosition = CFG.IDLE_FREEZE_TIME
            end
        end

        if currentAnimState == "forward"  and forwardTrack  and forwardTrack.IsPlaying  then forwardTrack.TimePosition  = 0.1 end
        if currentAnimState == "backward" and backwardTrack and backwardTrack.IsPlaying then backwardTrack.TimePosition = 0.1 end

        
        if currentAnimState == "boost" and boostTrack and boostTrack.IsPlaying then
            local char2 = player.Character
            if char2 then
                local hum2 = char2:FindFirstChildOfClass("Humanoid")
                if hum2 then
                    for _, t in pairs(hum2:GetPlayingAnimationTracks()) do
                        if t ~= boostTrack then t:Stop(0) end
                    end
                end
            end
            if not boostFrozen then
                if boostTrack.TimePosition >= 0.7 then
                    boostFrozen = true; boostTrack:AdjustSpeed(0); boostTrack.TimePosition = 0.7
                end
            else
                boostTrack.TimePosition = 0.7
            end
        end
    end)

    if flyConn then flyConn:Disconnect() end
    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not flying or not hrp.Parent then return end

        local controls = PlayerModule:GetControls()
        local mv       = controls:GetMoveVector()

        local isMoving   = mv.Magnitude > 0.1 or math.abs(verticalInput) > 0.1
        local isBackward = isMoving and mv.Z > 0.1 and mv.Z > math.abs(mv.X)

        if boostActive and (not isMoving or isBackward) then deactivateBoost() end

        local spd     = boostActive and CFG.BOOST_SPEED or CFG.NORMAL_SPEED
        local nowIdle = not isMoving and not boostActive

        if nowIdle then
            if not wasIdle then baseHoverY = hrp.Position.Y; hoverBobT = 0 end
            hoverBobT = hoverBobT + dt
            local targetY = baseHoverY + math.sin(hoverBobT * CFG.HOVER_FREQ * math.pi * 2) * CFG.HOVER_AMP
            bodyVelocity.Velocity = Vector3.new(0, (targetY - hrp.Position.Y) * CFG.HOVER_SPRING, 0)
        else
            baseHoverY = hrp.Position.Y
            local moveDir = camera.CFrame:VectorToWorldSpace(Vector3.new(mv.X, verticalInput, mv.Z))
            if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
            bodyVelocity.Velocity = moveDir * spd
        end
        wasIdle = nowIdle

        if not nowIdle then
            if not flySound.IsPlaying then flySound.Volume = boostActive and 2 or 1.4; flySound:Play() end
        else
            if flySound.IsPlaying then fadeOutSound(0.6) end
        end

        local desired
        if boostActive      then desired = "boost"
        elseif isMoving     then desired = isBackward and "backward" or "forward"
        else                     desired = "idle" end

        setAnimState(desired)

        
        local currentAngleY = math.atan2(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Z)
        local deltaAngle    = currentAngleY - prevCameraAngleY
        if deltaAngle >  math.pi then deltaAngle = deltaAngle - 2*math.pi end
        if deltaAngle < -math.pi then deltaAngle = deltaAngle + 2*math.pi end
        prevCameraAngleY = currentAngleY

        
        local targetTilt = 0
        if boostActive then
            local camTurnSpeed = deltaAngle / math.max(dt, 0.001)
            local dynamicTilt  = math.clamp(camTurnSpeed * TILT_SENSITIVITY, -math.rad(54), math.rad(47))
            targetTilt = math.rad(31) + dynamicTilt
        end
        tiltSmoothed = tiltSmoothed + (targetTilt - tiltSmoothed) * math.min(dt * 2.5, 1)

        bodyGyro.CFrame = camera.CFrame * CFrame.Angles(0, 0, tiltSmoothed)
    end)
end

local function stopFlying()
    if not flying then return end
    flying = false; boostActive = false; boostFrozen = false; floatMode = false

    destroyBoostVfx()

    if bodyGyro     then bodyGyro:Destroy();     bodyGyro     = nil end
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if flyConn      then flyConn:Disconnect();   flyConn      = nil end
    if animConn     then animConn:Disconnect();  animConn     = nil end

    local char = player.Character; local hrp = nil
    if char then
        local hum = char:FindFirstChild("Humanoid")
        if hum then hum.PlatformStand = false end
        hrp = char:FindFirstChild("HumanoidRootPart")
    end

    if flySound.IsPlaying then fadeOutSound(0.8) end
    stopAllFlyAnims(0.3)
    flySound.PlaybackSpeed = 1.05
    
    TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 70}):Play()
    startLandVfxMonitor()
    if hrp and landTrack then playLanding(hrp) end

    verticalInput = 0; currentAnimState = ""; wasIdle = false
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if flySystemDead then return end  

    if input.KeyCode == Enum.KeyCode.W then
        if not flying then return end
        local now = os.clock()
        if now - lastWTapTime <= DOUBLE_TAP_TIME then
            if boostActive then deactivateBoost() else activateBoost() end
            lastWTapTime = 0 
        else
            lastWTapTime = now
        end
    end
end)

local character  = player.Character or player.CharacterAdded:Wait()
local humanoid   = character:WaitForChild("Humanoid")
local rootPart   = character:WaitForChild("HumanoidRootPart")
local drAnimator = humanoid:WaitForChild("Animator")

local newButton=nil
local cooldownFrame,uiGradient
local function playCooldownVisual()
    if not cooldownFrame or not uiGradient then return end
    cooldownFrame.Visible   = true
    uiGradient.Transparency = NumberSequence.new(0)
    local startTime = tick(); local cdConn
    cdConn = RunService.RenderStepped:Connect(function()
        local p = math.clamp((tick() - startTime) / COOLDOWN, 0, 1)
        if p >= 1 then cdConn:Disconnect(); cooldownFrame.Visible = false; return end
        if p <= 0.001 then
            uiGradient.Transparency = NumberSequence.new(0)
        else
            uiGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0,                       1),
                NumberSequenceKeypoint.new(p,                       1),
                NumberSequenceKeypoint.new(math.min(p+0.001, 1),   0),
                NumberSequenceKeypoint.new(1,                       0),
            })
        end
    end)
end

local shakeIntensity = 0; local shakeFading = false; local shakeConn = nil

local function startShake(intensity)
    shakeIntensity = intensity; shakeFading = false
    if shakeConn then shakeConn:Disconnect() end
    shakeConn = RunService.RenderStepped:Connect(function(dt)
        if shakeIntensity <= 0 then
            if shakeConn then shakeConn:Disconnect(); shakeConn = nil end; return
        end
        local rx = (math.random()-0.5)*2*shakeIntensity
        local ry = (math.random()-0.5)*2*shakeIntensity
        local rz = (math.random()-0.5)*2*shakeIntensity
        camera.CFrame = camera.CFrame * CFrame.new(rx,ry,0) * CFrame.Angles(math.rad(rz*0.4), math.rad(rx*0.2), 0)
        if shakeFading then
            shakeIntensity = shakeIntensity - (shakeIntensity * dt * 3)
            if shakeIntensity < 0.002 then shakeIntensity = 0 end
        end
    end)
end

local function fadeShake() shakeFading = true end
local function stopShake()
    shakeIntensity = 0; shakeFading = false
    if shakeConn then shakeConn:Disconnect(); shakeConn = nil end
end

local function loadDRAnim(id)
    local a = Instance.new("Animation"); a.AnimationId = id
    return drAnimator:LoadAnimation(a)
end

local drActive = false

local function triggerDestructiveRush()
    if flySystemDead then return end  
    if drActive then return end
    drActive = true
    playCooldownVisual()

    humanoid.PlatformStand = true
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero; bv.MaxForce = Vector3.new(0, math.huge, 0); bv.Parent = rootPart

    
    local drGyro = Instance.new("BodyGyro")
    drGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    drGyro.P         = 50000
    drGyro.D         = 500
    local look = rootPart.CFrame.LookVector
    drGyro.CFrame    = CFrame.new(Vector3.zero, Vector3.new(look.X, 0, look.Z))
    drGyro.Parent    = rootPart

    
    local startTrack = loadDRAnim(DR_STARTUP)
    startTrack.Priority = Enum.AnimationPriority.Action4
    startTrack:Play(BLEND); startTrack.TimePosition = 0
    startShake(0.09)

    
    local drStartVfxClone = ReplicatedStorage.Utils.Mechamaru.EjectDeathVFX.DustLand2.VFX.extra2:Clone()
    drStartVfxClone.Parent = rootPart
    for _, child in ipairs(drStartVfxClone:GetChildren()) do
        if child:IsA("ParticleEmitter") then
            child:Emit(15); child.Enabled = true
        end
    end

    local frozen = false; local conn
    conn = RunService.Heartbeat:Connect(function()

        if not frozen and startTrack.TimePosition >= 0.3 then
            frozen = true; startTrack:AdjustSpeed(0)
            task.wait(1); startTrack:AdjustSpeed(1)
        end

        if frozen and startTrack.TimePosition >= 0.6 then
            conn:Disconnect(); fadeShake()

            
            local riseTrack = loadDRAnim(DR_RISE)
            riseTrack.Priority = Enum.AnimationPriority.Action4
            riseTrack.Looped   = true
            riseTrack:Play(BLEND); riseTrack.TimePosition = 4.1; riseTrack:AdjustSpeed(0)
            startTrack:Stop(BLEND)

            
            if drStartVfxClone then
                for _, child in ipairs(drStartVfxClone:GetChildren()) do
                    if child:IsA("ParticleEmitter") then child.Enabled = false end
                end
                local refS = drStartVfxClone; drStartVfxClone = nil
                task.delay(2, function() if refS and refS.Parent then refS:Destroy() end end)
            end

            
            local risingAnchor = Instance.new("Part")
            risingAnchor.Anchored     = true
            risingAnchor.CanCollide   = false
            risingAnchor.CastShadow   = false
            risingAnchor.Transparency = 1
            risingAnchor.Size         = Vector3.new(1, 1, 1)
            risingAnchor.CFrame       = rootPart.CFrame
            risingAnchor.Parent       = workspace

            local risingVfxClone = ReplicatedStorage.Utils.Mechamaru.DeathVFX.DustLand:Clone()
            risingVfxClone.Parent = risingAnchor
            for _, child in ipairs(risingVfxClone:GetChildren()) do
                if child:IsA("ParticleEmitter") then
                    child:Emit(15); child.Enabled = true
                end
            end

            task.delay(0.5, function()
                if risingVfxClone and risingVfxClone.Parent then
                    for _, child in ipairs(risingVfxClone:GetChildren()) do
                        if child:IsA("ParticleEmitter") then child.Enabled = false end
                    end
                end
                task.delay(2, function()
                    if risingAnchor and risingAnchor.Parent then risingAnchor:Destroy() end
                end)
            end)

            
            local risingSound = Instance.new("Sound")
            risingSound.SoundId = "rbxassetid://90269024228015"
            risingSound.Volume  = 1
            risingSound.Parent  = SoundService
            risingSound:Play()
            game:GetService("Debris"):AddItem(risingSound, 10)

            local tween = TweenService:Create(
                rootPart,
                TweenInfo.new(RISE_SPEED, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { CFrame = rootPart.CFrame + Vector3.new(0, RISE_HEIGHT, 0) }
            )
            tween:Play()

            tween.Completed:Connect(function()
                stopShake(); riseTrack:Stop(BLEND)

                
                bv:Destroy()
                
                if drGyro then drGyro:Destroy(); drGyro = nil end
                floatMode = true
                startFlying()

                task.wait(FLOAT_TIME)

                floatMode        = false
                currentAnimState = ""

                task.wait(COOLDOWN)
                drActive = false
            end)
        end
    end)
end

Bridge.Register("Fly",function() if flying then stopFlying() else startFlying() end end)
Bridge.Register("Boost",function() if boostActive then deactivateBoost() else activateBoost() end end)
Bridge.Register("Rush",triggerDestructiveRush)
local function cleanupOnDeath()
    
    if isDeadCleanup then return end
    
    isDeadCleanup = true
    flySystemDead = true  

    
    pcall(function() if flying then stopFlying() end end)

    pcall(function() if flyConn     then flyConn:Disconnect();     flyConn     = nil end end)
    pcall(function() if animConn    then animConn:Disconnect();    animConn    = nil end end)
    pcall(function() if landConn    then landConn:Disconnect();    landConn    = nil end end)
    pcall(function() if landVfxConn then landVfxConn:Disconnect(); landVfxConn = nil end end)
    pcall(function() if shakeConn   then shakeConn:Disconnect();   shakeConn   = nil end end)
    pcall(function() if _G.__FlySystemThrowBoostConn then _G.__FlySystemThrowBoostConn:Disconnect(); _G.__FlySystemThrowBoostConn = nil end end)

    pcall(function() if bodyGyro     then bodyGyro:Destroy();     bodyGyro     = nil end end)
    pcall(function() if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end end)

    pcall(destroyBoostVfx)
    pcall(stopBoostEffects)

    pcall(function() flySound:Stop();   flySound:Destroy()   end)
    pcall(function() boostSound:Stop(); boostSound:Destroy() end)

    
    pcall(function() if newButton and newButton.Parent then newButton:Destroy() end end)

    
    pcall(function() if gui and gui.Parent then gui:Destroy() end end)

    pcall(function() if camera then camera.FieldOfView = 70 end end)

    flying           = false
    boostActive      = false
    boostFrozen      = false
    floatMode        = false
    drActive         = false
    verticalInput    = 0
    currentAnimState = ""

    
    pcall(function() script:Destroy() end)
end

_G.__FlySystemCleanup = cleanupOnDeath

local deathConn
local function bindDeathHandler(char)
    if deathConn then deathConn:Disconnect(); deathConn = nil end
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    if hum.Health <= 0 then
        cleanupOnDeath()
        return
    end
    deathConn = hum.Died:Connect(cleanupOnDeath)
end

bindDeathHandler(character)
player.CharacterAdded:Connect(bindDeathHandler)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
	character = char
	root = char:WaitForChild("HumanoidRootPart")
end)

local RightActivated = ReplicatedStorage
	:WaitForChild("Knit")
	:WaitForChild("Knit")
	:WaitForChild("Services")
	:WaitForChild("ItadoriService")
	:WaitForChild("RE")
	:WaitForChild("RightActivated")

local ThrowableFolder = Workspace.Map.Destructible:WaitForChild("Throwable")

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.FilterDescendantsInstances = {character}

local throwBoostConn
throwBoostConn = RunService.Heartbeat:Connect(function()
	if not _G.BoostActive then
		return
	end

	if not character or not root then
		return
	end

	overlapParams.FilterDescendantsInstances = {character}

	local parts = Workspace:GetPartBoundsInRadius(
		root.Position + root.CFrame.LookVector * 12,
		8, 
		overlapParams
	)

	for _, part in ipairs(parts) do
		if part:IsDescendantOf(ThrowableFolder) then
			RightActivated:FireServer()
			break
		end
	end
end)

_G.__FlySystemThrowBoostConn = throwBoostConn

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ANIM_ID = "rbxassetid://127171275866632"

local HANG_SOUND_ID = "rbxassetid://82687386744947"
local HANG_SOUND_VOLUME = 0.3

local POSITION_OFFSET = Vector3.new(-0.1, -0.5, -2)
local ROTATION_OFFSET = Vector3.new(10, 180, 0)

local MAX_TARGET_DISTANCE = 15
local REMOTE_HIT_COUNT    = 4
local REMOTE_HIT_DELAY    = 0.5
local AFTER_LAST_HIT_DELAY = 0.45
local BUTTON_COOLDOWN     = 4

local function getRemote(...)
local path = { ... }
local ok, remote = pcall(function()
local node = ReplicatedStorage
for _, child in ipairs(path) do
node = node:WaitForChild(child, 5)
end
return node
end)
return ok and remote or nil
end

local activatedRemote = getRemote("Knit","Knit","Services","ItadoriService","RE","Activated")

if not activatedRemote then warn("[Choke] Activated remote not found!") end

local clickSound = Instance.new("Sound")
clickSound.SoundId = "rbxassetid://3077287610"
clickSound.Volume = 4
clickSound.Parent = game:GetService("SoundService")

local active = false
local dead = false
local lockedTarget = nil
local animTrack = nil
local hangSound = nil
local healthWatchConn = nil
local lastActivationTime = -math.huge

local sequenceRunId = 0

local function getClosestTargetToCamera(hrp)
local closest = nil
local bestScore = -math.huge

local camPos     = camera.CFrame.Position    
local camForward = camera.CFrame.LookVector    

for _, model in pairs(workspace:GetDescendants()) do    
	if model:IsA("Model")    
		and model ~= player.Character    
		and model:FindFirstChild("Humanoid")    
		and model:FindFirstChild("HumanoidRootPart")    
		and model:FindFirstChild("Head") then    

		local hum = model:FindFirstChild("Humanoid")    

		if hum and hum.Health > 0 then    
			local targetHRP = model.HumanoidRootPart    
			local dist = (hrp.Position - targetHRP.Position).Magnitude    

			if dist <= MAX_TARGET_DISTANCE then    
				local toTarget = (targetHRP.Position - camPos)    
				local dot = camForward:Dot(toTarget.Unit)    

				if dot > 0.3 then    
					local score = dot - (dist / MAX_TARGET_DISTANCE)    
					if score > bestScore then    
						bestScore = score    
						closest = model    
					end    
				end    
			end    
		end    
	end    
end    

return closest

end

local function startHangSound(parent)
if hangSound then hangSound:Destroy() end
hangSound = Instance.new("Sound")
hangSound.SoundId = HANG_SOUND_ID
hangSound.Volume = HANG_SOUND_VOLUME
hangSound.Looped = true
hangSound.Parent = parent
hangSound:Play()
end

local function stopHangSound()
if hangSound then
hangSound:Stop()
hangSound:Destroy()
hangSound = nil
end
end

local function forceAnimation(humanoid)
if animTrack then
animTrack:Stop()
animTrack:Destroy()
end

local anim = Instance.new("Animation")    
anim.AnimationId = ANIM_ID    

animTrack = humanoid:LoadAnimation(anim)    
animTrack.Priority = Enum.AnimationPriority.Action4    
animTrack.Looped = true    

animTrack:Play(0)    
task.wait()    
animTrack.TimePosition = 1    
animTrack:AdjustSpeed(0)

end

local function releaseHold()
active = false
lockedTarget = nil

if animTrack then    
	animTrack:Stop()    
	animTrack:Destroy()    
	animTrack = nil    
end    

stopHangSound()    

if healthWatchConn then    
	healthWatchConn:Disconnect()    
	healthWatchConn = nil    
end    

local char = player.Character    
if char then    
	local hum = char:FindFirstChildOfClass("Humanoid")    
	if hum then    
		hum.AutoRotate = true    
	end    
end

end

local function watchMyHealth(humanoid)
if healthWatchConn then
healthWatchConn:Disconnect()
end

local lastHealth = humanoid.Health    

healthWatchConn = humanoid.HealthChanged:Connect(function(newHealth)    
	if newHealth < lastHealth and active then    
		print("[Choke] ضرر — تحرير الخنقة (السلسلة تكمل بالخلفية)")    
		releaseHold()    
	end    
	lastHealth = newHealth    
end)

end

local function runRemoteSequence(myId)
if not activatedRemote then return end

for i = 1, REMOTE_HIT_COUNT do    
	if myId ~= sequenceRunId then    
		print("[Choke] أُلغيت عند Punch " .. i .. " (سلسلة جديدة/إلغاء يدوي)")    
		return    
	end    

	pcall(function()    
		activatedRemote:FireServer(false)    
	end)    
	print("[Choke] Punch " .. i .. " ✅")    

	if i < REMOTE_HIT_COUNT then    
		local startWait = tick()    
		repeat    
			RunService.Heartbeat:Wait()    
		until tick() - startWait >= REMOTE_HIT_DELAY or myId ~= sequenceRunId    

		if myId ~= sequenceRunId then return end    
	end    
end    

print("[Choke] اكتملت 4 ضربات — ننتظر " .. AFTER_LAST_HIT_DELAY .. "s ثم إيقاف")    

local waitStart = tick()    
repeat    
	RunService.Heartbeat:Wait()    
until tick() - waitStart >= AFTER_LAST_HIT_DELAY or myId ~= sequenceRunId    

if myId == sequenceRunId then    
	print("[Choke] إيقاف نهائي بعد 4 Punch")    
	releaseHold()    
end

end

local function tryToggle()
if dead then return end

local char = player.Character
if not char then return end

local hrp = char:FindFirstChild("HumanoidRootPart")    
local humanoid = char:FindFirstChildOfClass("Humanoid")    

if not hrp or not humanoid then return end    

if not active then    
	local now = tick()    
	local elapsed = now - lastActivationTime    
	if elapsed < BUTTON_COOLDOWN then    
		print(string.format("[Choke] كولداون — انتظر %.1f ثانية", BUTTON_COOLDOWN - elapsed))    
		return    
	end    

	local target = getClosestTargetToCamera(hrp)    

	if not target then    
		print("[Choke] ما في هدف ضمن " .. MAX_TARGET_DISTANCE .. " studs من الكاميرا")    
		return    
	end    

	clickSound:Play()    

	active = true    
	lockedTarget = target    
	lastActivationTime = now    

	sequenceRunId += 1    
	local myId = sequenceRunId    

	forceAnimation(humanoid)    
	startHangSound(hrp)    
	watchMyHealth(humanoid)    

	humanoid.AutoRotate = false    

	task.spawn(function()    
		runRemoteSequence(myId)    
	end)    

else    
	clickSound:Play()    
	sequenceRunId += 1    
	releaseHold()    
end

end

Bridge.Register("Choke",tryToggle)


player.CharacterAdded:Connect(function()
task.wait(1)
print("[Choke] Character respawned — تحرير الجانب البصري فقط")
releaseHold()
end)

RunService.RenderStepped:Connect(function()
if not active then return end

local char = player.Character    
if not char then return end    

local hrp = char:FindFirstChild("HumanoidRootPart")    
local humanoid = char:FindFirstChildOfClass("Humanoid")    

if not hrp or not humanoid then return end    

if humanoid.Health <= 0 then    
	print("[Choke] موت حقيقي — تحرير الجانب البصري")    
	releaseHold()    
	return    
end    

if not lockedTarget or not lockedTarget.Parent then    
	return    
end    

local targetHum = lockedTarget:FindFirstChildOfClass("Humanoid")    

if not targetHum or targetHum.Health <= 0 then    
	return    
end    

local head = lockedTarget:FindFirstChild("Head")    

if not head then    
	return    
end    

if not hangSound or not hangSound.IsPlaying then    
	startHangSound(hrp)    
end    

if humanoid.AutoRotate then    
	humanoid.AutoRotate = false    
end    

local finalCFrame = head.CFrame    
	* CFrame.new(POSITION_OFFSET)    
	* CFrame.Angles(    
		math.rad(ROTATION_OFFSET.X),    
		math.rad(ROTATION_OFFSET.Y),    
		math.rad(ROTATION_OFFSET.Z)    
	)    

hrp.CFrame = finalCFrame    

if not animTrack or not animTrack.IsPlaying then    
	forceAnimation(humanoid)    
end    

if animTrack then    
	animTrack.TimePosition = 1    
	animTrack:AdjustSpeed(0)    
end

end)

local function destroyChoke()
	if dead then return end
	dead = true

	
	pcall(function()
		releaseHold()
	end)

	sequenceRunId += 1
	active = false
	lockedTarget = nil

	
	if clickSound then
		clickSound:Destroy()
	end

	if hangSound then
		hangSound:Destroy()
	end

	
	if healthWatchConn then
		healthWatchConn:Disconnect()
		healthWatchConn = nil
	end

	print("[Choke] Deleted forever after death")
end

_G.__ChokeCleanup = destroyChoke

local function setupDeath(char)
	local hum = char:WaitForChild("Humanoid")

	hum.Died:Connect(function()
		destroyChoke()
	end)
end

if player.Character then
	setupDeath(player.Character)
end

player.CharacterAdded:Connect(function(char)
	task.wait(0.2)
	destroyChoke()
end)
]====]
SOURCES.PianoData = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local function pm(data)
    local pos = 1
    local function rb() local b = string.byte(data, pos); assert(b,"Truncated MIDI"); pos = pos + 1; return b end
    local function rs(len) assert(len>=0 and pos+len-1<=#data,"Truncated MIDI chunk");local s = string.sub(data, pos, pos + len - 1); pos = pos + len; return s end
    local function r16() return rb() * 256 + rb() end
    local function r32() return rb() * 16777216 + rb() * 65536 + rb() * 256 + rb() end
    local function rvlq()
        local v = 0
        for _=1,4 do
            local b = rb()
            v = v * 128 + bit32.band(b, 0x7F)
            if bit32.band(b, 0x80) == 0 then break end
        end
        assert(v<268435456,"Invalid MIDI variable integer")
        return v
    end

    if rs(4) ~= "MThd" then return {} end
    local headerLength=r32();assert(headerLength>=6,"Invalid MIDI header")
    local fmt, ntrk, div = r16(), r16(), r16()
    assert(fmt<=1 and div>0 and div<32768,"Only format 0/1 PPQN MIDI is supported")
    rs(headerLength-6)
    local evs = {}

    for i = 1, ntrk do
        if rs(4) ~= "MTrk" then break end
        local len = r32()
        assert(pos+len-1<=#data,"Truncated MIDI track")
        local endp, tick, lst = pos + len, 0, 0
        while pos < endp do
            local d = rvlq()
            tick = tick + d
            local s = rb()
            if s < 0x80 then assert(lst>=0x80 and lst<0xF0,"Invalid running status");s = lst; pos = pos - 1 elseif s<0xF0 then lst=s end
            local et = bit32.rshift(s, 4)
            local ch = bit32.band(s, 0x0F)
            if s == 0xFF then
                local mt = rb()
                local ml = rvlq()
                local md = rs(ml)
                if mt == 0x51 and ml == 3 then
                    local mpqn = string.byte(md, 1) * 65536 + string.byte(md, 2) * 256 + string.byte(md, 3)
                    table.insert(evs, {tick = tick, type = "t", mpqn = mpqn})
                end
            elseif s==0xF0 or s==0xF7 then rs(rvlq())
            elseif s>=0xF0 then error("Unsupported MIDI system event")
            elseif et == 0x9 and ch ~= 9 then
                local n, v = rb(), rb()
                if v > 0 then table.insert(evs, {tick = tick, type = "n", note = n}) end
            elseif et == 0x8 or et == 0xA or et == 0xB or et == 0xE then rb() rb()
            elseif et == 0xC or et == 0xD then rb() end
        end
        assert(pos<=endp,"MIDI event crosses track boundary")
        pos = endp
    end

    table.sort(evs, function(a, b) return a.tick < b.tick end)
    local res, curt, curtm, mpqn = {}, 0, 0, 500000

    for _, e in ipairs(evs) do
        local dt = e.tick - curt
        if dt > 0 then
            curtm = curtm + (dt / div) * (mpqn / 1000000)
            curt = e.tick
        end
        if e.type == "t" then mpqn = e.mpqn
        elseif e.type == "n" then table.insert(res, {time = curtm, note = e.note}) end
    end
    return res
end

-- Full note map including all shift keys
local nm = {
    [60]="1",[62]="2",[64]="3",[65]="4",[67]="5",[69]="6",[71]="7",[72]="8",[74]="9",[76]="0",
    [77]="q",[79]="w",[81]="e",[83]="r",[84]="t",[86]="y",[88]="u",[89]="i",[91]="o",[93]="p",
    [95]="a",[96]="s",[98]="d",[100]="f",[102]="g",[103]="h",[105]="j",[107]="k",[108]="l",
    [110]="z",[112]="x",[114]="c",[115]="v",[117]="b",[119]="n",[121]="m",
    -- Sharps (shift keys)
    [61]="!",[63]="@",[66]="$",[68]="%",[70]="^",[73]="*",[75]="(",
    [78]="Q",[80]="W",[82]="E",[85]="T",[87]="Y",[90]="I",[92]="O",
    [94]="P",[97]="S",[99]="D",[101]="G",[104]="H",[106]="J",[109]="L",
    [111]="Z",[113]="C",[116]="V",[118]="B"
}

-- Complete key map including ALL shift-key mappings
local km = {
    ["1"]=Enum.KeyCode.One,["2"]=Enum.KeyCode.Two,["3"]=Enum.KeyCode.Three,
    ["4"]=Enum.KeyCode.Four,["5"]=Enum.KeyCode.Five,["6"]=Enum.KeyCode.Six,
    ["7"]=Enum.KeyCode.Seven,["8"]=Enum.KeyCode.Eight,["9"]=Enum.KeyCode.Nine,["0"]=Enum.KeyCode.Zero,
    ["q"]=Enum.KeyCode.Q,["w"]=Enum.KeyCode.W,["e"]=Enum.KeyCode.E,["r"]=Enum.KeyCode.R,
    ["t"]=Enum.KeyCode.T,["y"]=Enum.KeyCode.Y,["u"]=Enum.KeyCode.U,["i"]=Enum.KeyCode.I,
    ["o"]=Enum.KeyCode.O,["p"]=Enum.KeyCode.P,["a"]=Enum.KeyCode.A,["s"]=Enum.KeyCode.S,
    ["d"]=Enum.KeyCode.D,["f"]=Enum.KeyCode.F,["g"]=Enum.KeyCode.G,["h"]=Enum.KeyCode.H,
    ["j"]=Enum.KeyCode.J,["k"]=Enum.KeyCode.K,["l"]=Enum.KeyCode.L,["z"]=Enum.KeyCode.Z,
    ["x"]=Enum.KeyCode.X,["c"]=Enum.KeyCode.C,["v"]=Enum.KeyCode.V,["b"]=Enum.KeyCode.B,
    ["n"]=Enum.KeyCode.N,["m"]=Enum.KeyCode.M,
    -- Shift symbols mapped to their base key
    ["!"]=Enum.KeyCode.One,["@"]=Enum.KeyCode.Two,["$"]=Enum.KeyCode.Four,
    ["%"]=Enum.KeyCode.Five,["^"]=Enum.KeyCode.Six,["*"]=Enum.KeyCode.Eight,["("]=Enum.KeyCode.Nine,
    -- Uppercase = shift + letter (the ones missing before)
    ["Q"]=Enum.KeyCode.Q,["W"]=Enum.KeyCode.W,["E"]=Enum.KeyCode.E,["T"]=Enum.KeyCode.T,
    ["Y"]=Enum.KeyCode.Y,["I"]=Enum.KeyCode.I,["O"]=Enum.KeyCode.O,["P"]=Enum.KeyCode.P,
    ["S"]=Enum.KeyCode.S,["D"]=Enum.KeyCode.D,["G"]=Enum.KeyCode.G,["H"]=Enum.KeyCode.H,
    ["J"]=Enum.KeyCode.J,["L"]=Enum.KeyCode.L,["Z"]=Enum.KeyCode.Z,["C"]=Enum.KeyCode.C,
    ["V"]=Enum.KeyCode.V,["B"]=Enum.KeyCode.B
}

local function isShift(k)
    -- Shift if it's an uppercase letter or a shift symbol
    return k:match("^[A-Z]$") or k:match("^[!@$%%^*(]$")
end


return {Parse=pm,Notes=nm,Keys=km,IsShift=isShift}

]====]
SOURCES.Ratio = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Service = ReplicatedStorage.Knit.Knit.Services.NanamiService
local Active = true

Service.RE.Effects.OnClientEvent:Connect(function(...)
    local args = {...}
    if not Active or args[1] ~= "SpawnRatio" or args[2] ~= Player then return end

    local value = tonumber(args[6])
    if not value then return end

    local delayTime = math.max(0, value * 0.5676767676767676 - Player:GetNetworkPing())
    delayTime = math.max(0, delayTime + math.random(-3, 3) / 1000)

    task.delay(delayTime, function()
        if Active then
            Service.RE.RightActivated:FireServer()
        end
    end)
end)


]====]
SOURCES.Sweep = [====[
-- Zorcex original; ClaudeHub lifecycle/UI adaptation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local state = {
    SweepAll = false,
    Bypass = false,
    Noclip = false,
}

local CONFIG = {
    SweepTime = 0.05
}

local resetCount = 0

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3
        })
    end)
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function fireReset()
    local ok, remote = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Knit", 2)
            :WaitForChild("Knit", 2)
            :WaitForChild("Services", 2)
            :WaitForChild("JoinService", 2)
            :WaitForChild("RE", 2)
            :WaitForChild("Reset", 2)
    end)
    if ok and remote and remote:IsA("RemoteEvent") then
        remote:FireServer()
        return true
    end
    return false
end

local function getTarget(maxDistance)
    maxDistance = maxDistance or 500
    local targets = {}
    local myHRP = getHRP()
    if not myHRP then return nil end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and hrp then
                if (hrp.Position - myHRP.Position).Magnitude <= maxDistance then
                    table.insert(targets, humanoid)
                end
            end
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and string.lower(obj.Name) == "dummy" then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
            if humanoid and humanoid.Health > 0 and hrp then
                if (hrp.Position - myHRP.Position).Magnitude <= maxDistance then
                    table.insert(targets, humanoid)
                end
            end
        end
    end

    if #targets > 0 then
        return targets[math.random(1, #targets)]
    end
    return nil
end

RunService.Stepped:Connect(function()
    if Bridge.Enabled("SweepNoclip") and LocalPlayer.Character then
        for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(Bridge.Value("SweepDelay",0.05))
        if state.SweepAll then
            local myHRP = getHRP()
            local humanoid = getHumanoid()
            if myHRP and humanoid and humanoid.Health > 0 then
                local targets = {}
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                        local hrp = p.Character.HumanoidRootPart
                        if (hrp.Position - myHRP.Position).Magnitude <= 500 then
                            table.insert(targets, hrp)
                        end
                    end
                end
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if obj:IsA("Model") and string.lower(obj.Name) == "dummy" then
                        local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
                        if hrp and (hrp.Position - myHRP.Position).Magnitude <= 500 then
                            table.insert(targets, hrp)
                        end
                    end
                end
                for _, targetHRP in ipairs(targets) do
                    if not state.SweepAll or not humanoid or humanoid.Health <= 0 then break end
                    if myHRP and targetHRP and targetHRP.Parent then
                        myHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 2.5)
                        task.wait(Bridge.Value("SweepDelay",0.05))
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        if state.Bypass then
            local hrp = getHRP()
            local humanoid = getHumanoid()
            if hrp and humanoid and humanoid.Health > 0 then
                local targetHumanoid = getTarget(500)
                local targetHRP = targetHumanoid and targetHumanoid.Parent and (
                    targetHumanoid.Parent:FindFirstChild("HumanoidRootPart") or
                    targetHumanoid.Parent:FindFirstChild("Torso")
                )
                if targetHRP then
                    local startPos = hrp.Position
                    hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 2.5)
                    local teleportedBack = false
                    local timer = 0
                    while timer < 3 do
                        task.wait(0.1)
                        timer = timer + 0.1
                        if not state.Bypass or not humanoid or humanoid.Health <= 0 then
                            break
                        end
                        if (hrp.Position - startPos).Magnitude < 10 then
                            teleportedBack = true
                            break
                        end
                    end
                    if state.Bypass and humanoid and humanoid.Health > 0 then
                        if teleportedBack then
                            notify("Anti-Cheat Bypass", "Rubber Band! Reseting...", 2)
                            while state.Bypass and humanoid and humanoid.Health > 0 do
                                if fireReset() then
                                    resetCount = resetCount + 1
                                end
                                task.wait(3)
                                humanoid = getHumanoid()
                            end
                        else
                            notify("Anti-Cheat Bypass", "Anti-Cheat Bypass Success", 2)
                            task.wait(2)
                            notify("Anti-Cheat Bypass", "Resets: " .. tostring(resetCount) .. "", 2)
                        end
                    end
                end
            end
        end
    end
end)


state.SweepAll=true
return {Stop=function() state.SweepAll=false;state.Bypass=false;state.Noclip=false end}

]====]
-- Managed execution for locally embedded Zorcex source. Not a security sandbox.
local function makeManagedRuntime(host)
    local nativeTask=task
    local runtime={Scopes={},Closed=false}
    local rootEnv=getgenv and getgenv() or _G
    local realTick=tick
    local function namecallSlot(scope,fn)
        local key="__ClaudeHubJJS_NamecallRouter_v1"
        local router=rootEnv[key]
        if not router then
            router={Slots={},Keys={}}
            local function dispatch(index,self,...)
                while index>0 do
                    local slot=router.Slots[index]
                    if slot.Scope and slot.Scope.Alive and slot.Func then
                        local owner=slot.Scope
                        local result=table.pack(pcall(slot.Func,owner:Wrap(self),...))
                        if result[1] then return table.unpack(result,2,result.n) end
                        owner:Stop()
                        if owner.Report then owner.Report(tostring(result[2])) end
                    end
                    index-=1
                end
                return router.Original(self,...)
            end
            router.Dispatch=dispatch
            local callback=function(self,...) return dispatch(#router.Slots,self,...) end
            if type(newcclosure)=="function" then callback=newcclosure(callback) end
            if type(hookmetamethod)=="function" then router.Original=hookmetamethod(game,"__namecall",callback)
            else
                assert(type(getrawmetatable)=="function" and type(setreadonly)=="function","Namecall hooks are not supported")
                local mt=getrawmetatable(game);router.Original=mt.__namecall
                setreadonly(mt,false);mt.__namecall=callback;setreadonly(mt,true)
            end
            rootEnv[key]=router
        end
        scope.HookSerial+=1
        local slotKey=scope.Name..":"..scope.HookSerial
        local index=router.Keys[slotKey]
        if not index then index=#router.Slots+1;router.Keys[slotKey]=index;router.Slots[index]={} end
        local slot=router.Slots[index];slot.Scope,slot.Func=scope,fn
        table.insert(scope.HookSlots,slot)
        return function(self,...)
            local args=table.pack(...);for i=1,args.n do args[i]=scope:Unwrap(args[i]) end
            return router.Dispatch(index-1,scope:Unwrap(self),table.unpack(args,1,args.n))
        end
    end
    local function tickHook(scope,fn)
        assert(type(hookfunction)=="function","hookfunction is unavailable; Infinite Dash cannot start")
        local key="__ClaudeHubJJS_TickRouter_v1"
        local router=rootEnv[key]
        if not router then
            router={}
            router.Original=hookfunction(realTick,function(...)
                if router.Scope and router.Scope.Alive and router.Func then return router.Func(...) end
                return router.Original(...)
            end)
            rootEnv[key]=router
        end
        router.Scope,router.Func=scope,fn
        scope.TickRouter=router
        return router.Original
    end
    function runtime:New(name,onError)
        assert(not self.Closed,"Addons runtime is closed")
        local scope={Name=name,Alive=true,Threads={},Connections={},Created={},Owned={},Props={},Tweens={},Tracks={},
            Report=onError,Proxy={},Raw=setmetatable({},{__mode="k"}),HookSlots={},HookSerial=0,Private={},Actions={},Exports={},StopCallbacks={}}
        self.Scopes[scope]=true
        function scope:Unwrap(v)
            if type(v)=="table" then
                if self.Raw[v] then return self.Raw[v] end
                if typeof(v)~="table" then return v end
                local out={};for k,x in pairs(v) do out[k]=self:Unwrap(x) end;return out
            end
            return v
        end
        function scope:Record(object,key,value,force)
            if self.Owned[object] or key=="CFrame" or key=="Position" or key=="AssemblyLinearVelocity" or key=="AssemblyAngularVelocity" or key=="Health" then return end
            local fields=self.Props[object]
            if not fields then fields={};self.Props[object]=fields end
            local data=fields[key]
            if not data then
                local ok,base=pcall(function() return object[key] end)
                if not ok then return end
                data={Base=base};fields[key]=data
            end
            data.Applied=value;data.Force=force or data.Force
        end
        function scope:RestoreProperty(key)
            for object,fields in pairs(self.Props) do
                local data=fields[key]
                if data then
                    pcall(function() if data.Force or object[key]==data.Applied then object[key]=data.Base end end)
                    fields[key]=nil
                end
            end
        end
        function scope:Own(object)
            if not self.Owned[object] then self.Owned[object]=true;table.insert(self.Created,object) end
            return object
        end
        function scope:Spawn(fn,...)
            if not self.Alive then return end
            local args=table.pack(...)
            local co
            co=coroutine.create(function()
                if self.Alive then
                    local ok,err=pcall(fn,table.unpack(args,1,args.n))
                    if not ok and self.Alive then
                        self:Stop()
                        if onError then onError(tostring(err)) end
                    end
                end
                self.Threads[co]=nil
            end)
            self.Threads[co]=true;nativeTask.spawn(co)
            return co
        end
        function scope:Wrap(value)
            local kind=typeof(value)
            if kind~="Instance" and kind~="RBXScriptSignal" then
                if kind=="table" then local out={};for k,v in pairs(value) do out[k]=self:Wrap(v) end;return out end
                return value
            end
            if self.Proxy[value] then return self.Proxy[value] end
            local proxy={};self.Proxy[value]=proxy;self.Raw[proxy]=value
            setmetatable(proxy,{
                __index=function(_,key)
                    if kind=="RBXScriptSignal" then
                        if key=="Connect" or key=="Once" then return function(_,fn)
                            if not scope.Alive then return {Disconnect=function() end,Connected=false} end
                            local connection
                            connection=value:Connect(function(...)
                                if key=="Once" and connection then connection:Disconnect() end
                                if scope.Alive then
                                    local args=table.pack(...)
                                    for i=1,args.n do args[i]=scope:Wrap(args[i]) end
                                    scope:Spawn(fn,table.unpack(args,1,args.n))
                                end
                            end)
                            table.insert(scope.Connections,connection);return connection
                        end end
                        if key=="Wait" then return function()
                            local args=table.pack(value:Wait())
                            assert(scope.Alive,"Feature stopped")
                            for i=1,args.n do args[i]=scope:Wrap(args[i]) end
                            return table.unpack(args,1,args.n)
                        end end
                    end
                    local member=value[key]
                    if type(member)~="function" then return scope:Wrap(member) end
                    return function(_, ...)
                        assert(scope.Alive or scope.Stopping,"Feature stopped")
                        local args=table.pack(...)
                        for i=1,args.n do args[i]=scope:Unwrap(args[i]) end
                        if key=="WaitForChild" then
                            -- Imported features are opt-in; missing APIs fail without indefinite waits.
                            local result=value:FindFirstChild(args[1])
                            assert(result,"Missing child: "..tostring(args[1]).." in "..value.Name)
                            return scope:Wrap(result)
                        end
                        if key=="Destroy" and not scope.Owned[value] then error("Refusing to destroy an existing game object: "..value.Name) end
                        if key=="SetCore" and args[1]=="SendNotification" then
                            host.Notify(tostring(args[2].Title or scope.Name)..": "..tostring(args[2].Text or ""));return
                        end
                        if key=="Create" and value==game:GetService("TweenService") then
                            for property,goal in pairs(args[3] or {}) do scope:Record(args[1],property,goal,true) end
                        end
                        local results=table.pack(member(value,table.unpack(args,1,args.n)))
                        if key=="Clone" and results[1] then
                            scope:Own(results[1]);for _,child in ipairs(results[1]:GetDescendants()) do scope:Own(child) end
                        elseif key=="LoadAnimation" and results[1] then table.insert(scope.Tracks,results[1]);scope:Own(results[1])
                        elseif key=="Create" and value==game:GetService("TweenService") and results[1] then table.insert(scope.Tweens,results[1]) end
                        for i=1,results.n do results[i]=scope:Wrap(results[i]) end
                        return table.unpack(results,1,results.n)
                    end
                end,
                __newindex=function(_,key,v)
                    assert(scope.Alive or scope.Stopping,"Feature stopped")
                    local raw=scope:Unwrap(v);scope:Record(value,key,raw);value[key]=raw
                end,
                __tostring=function() return tostring(value) end,
            })
            return proxy
        end
        local tasks={}
        function tasks.wait(duration)
            assert(scope.Alive,"Feature stopped")
            local elapsed=nativeTask.wait(duration)
            assert(scope.Alive,"Feature stopped");return elapsed
        end
        function tasks.spawn(fn,...) return scope:Spawn(fn,...) end
        function tasks.defer(fn,...) return scope:Spawn(function(...) tasks.wait();fn(...) end,...) end
        function tasks.delay(duration,fn,...)
            return scope:Spawn(function(...) tasks.wait(duration);fn(...) end,...)
        end
        function tasks.cancel(co) scope.Threads[co]=nil;pcall(nativeTask.cancel,co) end
        local environment=setmetatable({
            game=scope:Wrap(game),workspace=scope:Wrap(workspace),task=tasks,wait=tasks.wait,Wait=tasks.wait,
            Instance={new=function(class,parent)
                assert(scope.Alive or scope.Stopping,"Feature stopped")
                return scope:Wrap(scope:Own(Instance.new(class,scope:Unwrap(parent))))
            end},
            _G=scope.Private,getgenv=function() return scope.Private end,
            typeof=function(v) return typeof(scope:Unwrap(v)) end,
            require=function(v) return require(scope:Unwrap(v)) end,
            script={Destroy=function() scope:Stop();host.Stopped(name) end},
            hookmetamethod=function(_,key,fn) assert(key=="__namecall","Unsupported hook");return namecallSlot(scope,fn) end,
            hookfunction=function(target,fn) assert(target==realTick,"Unsupported function hook");return tickHook(scope,fn) end,
            newcclosure=function(fn) return fn end,
        },{__index=getfenv()})
        scope.Environment=environment
        function scope:Stop()
            if not self.Alive or self.Stopping then return end
            self.Alive=false;self.Stopping=true
            for _,fn in ipairs(self.StopCallbacks) do pcall(fn) end
            for _,key in ipairs({"__FlySystemCleanup","__ChokeCleanup"}) do if type(self.Private[key])=="function" then pcall(self.Private[key]) end end
            for _,export in ipairs(self.Exports) do if type(export)=="table" and type(export.Stop)=="function" then pcall(export.Stop) end end
            for _,c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
            for co in pairs(self.Threads) do if co~=coroutine.running() then pcall(nativeTask.cancel,co) end end
            for _,slot in ipairs(self.HookSlots) do if slot.Scope==self then slot.Scope,slot.Func=nil,nil end end
            if self.TickRouter and self.TickRouter.Scope==self then self.TickRouter.Scope,self.TickRouter.Func=nil,nil end
            for _,tween in ipairs(self.Tweens) do pcall(function() tween:Cancel() end) end
            for _,track in ipairs(self.Tracks) do pcall(function() track:Stop(0);track:Destroy() end) end
            for object,fields in pairs(self.Props) do for key,data in pairs(fields) do
                pcall(function() if data.Force or object[key]==data.Applied then object[key]=data.Base end end)
            end end
            for i=#self.Created,1,-1 do pcall(function() self.Created[i]:Destroy() end) end
            self.Stopping=false
            table.clear(self.Threads);table.clear(self.Connections);table.clear(self.Actions)
            runtime.Scopes[self]=nil
        end
        function scope:Run(source,bridge,done)
            self.Environment.Bridge=bridge
            return self:Spawn(function()
                local chunk,err=loadstring(source,"@ClaudeHub/Zorcex/"..name)
                assert(chunk,err);setfenv(chunk,self.Environment)
                local exported=chunk()
                table.insert(self.Exports,exported or {})
                if done and self.Alive then done(exported) end
            end)
        end
        return scope
    end
    function runtime:Destroy()
        self.Closed=true;for scope in pairs(self.Scopes) do scope:Stop() end;table.clear(self.Scopes)
    end
    return runtime
end

-- Local source ports, controlled only through the existing Obsidian window.
local function createZorcex(host)
    local Window,Library,Options,Toggles=host.Window,host.Library,host.Options,host.Toggles
    local controller={Scopes={},Dead=false,Ignore={},PianoButtons={},Status={}}
    local notify=host.Notify
    local function value(id,default) local o=Options[id];return o and o.Value or default end
    local function enabled(id) return Toggles[id] and Toggles[id].Value==true end
    local function setOff(id) if Toggles[id] and Toggles[id].Value then Toggles[id]:SetValue(false) end end
    local function fail(id,message)
        local scope=controller.Scopes[id]
        if scope then scope:Stop();controller.Scopes[id]=nil end
        setOff(id);if controller.Status[id] then controller.Status[id]:SetText("Status: off") end;notify(id..": "..tostring(message))
    end
    local runtime=makeManagedRuntime({Notify=notify,Stopped=function(id) setOff(id) end})
    local function toggle(box,id,text,key)
        local t=box:AddToggle(id,{Text=text,Default=false})
        table.insert(controller.Ignore,id)
        if key then
            t:AddKeyPicker(id.."Bind",{Default=key,Text=text,Mode="Toggle",NoUI=true,SyncToggleState=false})
            local picker=Options[id.."Bind"];picker.SyncToggleState,picker.Toggled=true,false;picker:Update()
        end
        return t
    end
    local function slider(box,id,text,default,low,high,round)
        box:AddSlider(id,{Text=text,Default=default,Min=low,Max=high,Rounding=round or 0})
    end
    local function button(box,text,fn,id,key)
        local b=box:AddButton({Text=text,Func=function()
            if not controller.Dead and host.CanAct() then local ok,err=pcall(fn);if not ok then notify(text..": "..tostring(err)) end end
        end})
        if id then b:AddKeyPicker(id,{Default=key or "None",Text=text,Mode="Press",NoUI=true});table.insert(controller.PianoButtons,b) end
        return b
    end
    local positionDrivers={"SourceBypass","SourceSweep","SourceInvisible","SourceMoveset","Freecam","Spectate"}
    local function excludeDrivers(id)
        for _,other in ipairs(positionDrivers) do if id~=other then setOff(other) end end
    end
    function controller:StopPositionDrivers()
        for _,id in ipairs(positionDrivers) do if id~="Freecam" and id~="Spectate" then setOff(id) end end
    end
    function controller:BlockStopped() setOff("SourceCounter") end
    local function findRemote(service,event)
        local node=game:GetService("ReplicatedStorage")
        for _,name in ipairs({"Knit","Knit","Services",service,"RE",event}) do node=node and node:FindFirstChild(name) end
        return node and node:IsA("RemoteEvent") and node or nil
    end
    local function start(id,source,done)
        local old=controller.Scopes[id];if old then old:Stop() end
        local scope=runtime:New(id,function(err) fail(id,err) end)
        controller.Scopes[id]=scope
        local bridge={Value=value,Enabled=enabled,Register=function(name,fn) scope.Actions[name]=fn end}
        scope:Run(source,bridge,done)
        return scope,bridge
    end
    local function bind(id,source,preflight,done)
        Toggles[id]:OnChanged(function()
            if controller.Dead then return end
            if not enabled(id) then
                local s=controller.Scopes[id];if s then s:Stop();controller.Scopes[id]=nil end
                if controller.Status[id] then controller.Status[id]:SetText("Status: off") end
                return
            end
            if preflight then local ok,err=pcall(preflight);if not ok then fail(id,err);return end end
            start(id,source,done)
        end)
    end
    local extras=Window:AddTab("Zorcex","sparkles")
    local combat=host.Combat:AddRightGroupbox("Zorcex combat","shield")
    toggle(combat,"SourceBlackFlash","Auto Black Flash","None")
    local bfStatus=combat:AddLabel("Black Flash: off");controller.Status.SourceBlackFlash=bfStatus
    toggle(combat,"SourceRatio","Auto Nanami Ratio","None")
    toggle(combat,"SourceCounter","Auto Counter (Itadori)","None")
    toggle(combat,"SourceHaruta","Haruta One Shot","None")
    slider(combat,"HarutaMultiplier","Haruta multiplier",100,1,100)
    local utility=extras:AddLeftGroupbox("Character / utility","user")
    toggle(utility,"SourceEmotes","Extra Emote Slots","None")
    toggle(utility,"SourceDash","Infinite Dash","None")
    toggle(utility,"SourceInvisible","Invisibility","None")
    local sweep=extras:AddRightGroupbox("Gojo Sweep All","wind")
    toggle(sweep,"SourceSweep","Gojo Sweep All","None")
    toggle(sweep,"SweepNoclip","Sweep Noclip")
    slider(sweep,"SweepDelay","Sweep delay",0.05,0.03,1,2)
    local bypass=extras:AddLeftGroupbox("Experimental","triangle-alert")
    toggle(bypass,"SourceBypass","Anti-Cheat Bypass (source)","None")
    bypass:AddLabel("Bypass can teleport and reset your character.")
    bypass:AddLabel("Infinite Dash changes the shared tick() clock.")
    bypass:AddLabel("Haruta duplicates remote arguments (not a guaranteed kill).")
    local credits=extras:AddRightGroupbox("Credits","info")
    credits:AddLabel("Source scripts: Zorcex / JJS-Script")
    credits:AddLabel("Adaptation: ClaudeHub; UI: ordinary Obsidian")
    credits:AddLabel("All imported functions start OFF.")
    local moves=Window:AddTab("Moveset","rocket")
    local mg=moves:AddLeftGroupbox("Viltrumite / Zorcex","rocket")
    mg:AddDropdown("MovesetMode",{Text="Controls",Values={"PC","Mobile"},Default=1})
    toggle(mg,"SourceMoveset","Enable Viltrumite Moveset","None")
    local movesStatus=mg:AddLabel("Moveset: off");controller.Status.SourceMoveset=movesStatus
    local function moveAction(name)
        local s=controller.Scopes.SourceMoveset
        local fn=s and s.Alive and s.Actions[name]
        if not fn then notify("Enable Moveset and wait for it to load first");return end
        s:Spawn(fn)
    end
    button(mg,"Fly / land",function() moveAction("Fly") end,"MovesetFlyBind","None")
    button(mg,"Boost / stop",function() moveAction("Boost") end,"MovesetBoostBind","None")
    button(mg,"Destructive Rush",function() moveAction("Rush") end,"MovesetRushBind","None")
    button(mg,"Choke / release",function() moveAction("Choke") end,"MovesetChokeBind","None")
    local mi=moves:AddRightGroupbox("Controls","info")
    mi:AddLabel("Flight, boost, rush and choke use the buttons above.")
    mi:AddLabel("Right-click a bind to change it. W twice: source boost.")
    mi:AddLabel("No device selector, Tora/Rayfield windows or extra ESP.")
    mi:AddLabel("Animations/VFX are client-side; server damage is not guaranteed.")
    mi:AddLabel("Use respawn if an animation remains after stopping.")
    bind("SourceBlackFlash",SOURCES.BlackFlash,function()
        assert(type(hookmetamethod)=="function" or type(getrawmetatable)=="function","Namecall hooks unavailable")
    end,function(export)
        local names={};for name,ok in pairs(export.Supported or {}) do if ok then table.insert(names,name) end end
        table.sort(names);bfStatus:SetText("Black Flash: "..table.concat(names,", "))
    end)
    bind("SourceRatio",SOURCES.Ratio)
    bind("SourceEmotes",SOURCES.Emotes)
    bind("SourceDash",SOURCES.Dash,function() assert(type(hookfunction)=="function","hookfunction unavailable") end)
    bind("SourceHaruta",SOURCES.Haruta,function()
        assert(type(hookmetamethod)=="function" or type(getrawmetatable)=="function","Namecall hooks unavailable")
    end)
    bind("SourceInvisible",SOURCES.Invisible,function() excludeDrivers("SourceInvisible") end)
    bind("SourceSweep",SOURCES.Sweep,function() excludeDrivers("SourceSweep") end)
    Toggles.SweepNoclip:OnChanged(function()
        local s=controller.Scopes.SourceSweep
        if s and not enabled("SweepNoclip") then s:RestoreProperty("CanCollide") end
    end)
    bind("SourceBypass",SOURCES.Bypass,function()
        assert(findRemote("JoinService","Reset"),"JoinService.Reset unavailable")
        excludeDrivers("SourceBypass")
        notify("Experimental source bypass enabled: may teleport/reset; no bypass guarantee")
    end)
    local counterReady,lastCounter=false,-math.huge
    bind("SourceCounter",SOURCES.Counter,function()
        assert(findRemote("ItadoriService","Activated"),"ItadoriService.Activated unavailable")
        Toggles.AutoBlock:SetValue(true)
        assert(enabled("AutoBlock"),"Auto Block could not start")
        counterReady=false
    end,function() counterReady=true end)
    function controller:Counter()
        local s=self.Scopes.SourceCounter
        if not enabled("SourceCounter") or not counterReady or not s or not s.Alive or os.clock()-lastCounter<1 then return end
        lastCounter=os.clock()
        s:Spawn(function()
            local export=s.Exports[1]
            if export and export.Try then export.Try() end
        end)
    end
    bind("SourceMoveset",SOURCES.MovesetMain,function()
        excludeDrivers("SourceMoveset")
        for _,id in ipairs({"Speed","FaceTarget","AutoBlock","SourceCounter","InfiniteJump","AntiShake"}) do setOff(id) end
        movesStatus:SetText("Moveset: loading...")
    end,function()
        local s=controller.Scopes.SourceMoveset
        if not s or not s.Alive then return end
        local bridge={Value=value,Enabled=enabled,Register=function(name,fn) s.Actions[name]=fn end}
        s:Run(value("MovesetMode","PC")=="Mobile" and SOURCES.MovesetMobile or SOURCES.MovesetPC,bridge,function()
            movesStatus:SetText("Moveset: "..value("MovesetMode","PC"))
        end)
    end)
    Options.MovesetMode:OnChanged(function() if enabled("SourceMoveset") then setOff("SourceMoveset");notify("Moveset stopped; enable it again to change controls") end end)
    -- One native Obsidian piano panel; parser and keyboard map come from the source.
    local piano=Window:AddTab("Piano","music")
    local pg=piano:AddLeftGroupbox("MIDI player / Zorcex","music")
    pg:AddDropdown("PianoSong",{Text="Song (.mid)",Values={},AllowNull=true})
    slider(pg,"PianoSpeed","Playback speed",1,0.25,3,2)
    slider(pg,"PianoTranspose","Transpose",0,-12,12)
    toggle(pg,"PianoLoop","Loop")
    local pianoStatus=pg:AddLabel("Piano: stopped")
    local help=piano:AddRightGroupbox("Local songs","folder")
    help:AddLabel("Put .mid files in RobloxPiano/Songs.")
    help:AddLabel("Sit at a piano before Play; the menu closes on Play.")
    help:AddLabel("Hub hotkeys are suspended during playback.")
    help:AddLabel("Pause/stop or leaving the seat releases all notes.")
    local pstate={Generation=0,Playing=false,Paused=false,Keys={},Files={},Events={},Index=1,Clock=0,Disabled={}}
    local pdata
    do
        local chunk,err=loadstring(SOURCES.PianoData,"@ClaudeHub/Zorcex/PianoData")
        assert(chunk,err);pdata=chunk()
    end
    local vim
    local function releaseKeys()
        for code in pairs(pstate.Keys) do pcall(function() vim:SendKeyEvent(false,code,false,game) end) end
        table.clear(pstate.Keys)
    end
    local function suspendKeys(enable)
        if enable then
            for _,t in pairs(Toggles) do
                if t.SetDisabled then pstate.Disabled[t]=t.Disabled==true;t:SetDisabled(true) end
            end
            for _,b in ipairs(controller.PianoButtons) do if b.SetDisabled then pstate.Disabled[b]=b.Disabled==true;b:SetDisabled(true) end end
        else
            for object,old in pairs(pstate.Disabled) do pcall(function() object:SetDisabled(old) end) end
            table.clear(pstate.Disabled)
        end
    end
    local function stopPiano(reset)
        pstate.Generation+=1;pstate.Playing=false
        releaseKeys();suspendKeys(false)
        if reset then pstate.Clock=0;pstate.Index=1;pstate.Paused=false end
        pianoStatus:SetText(reset and "Piano: stopped" or "Piano: paused")
    end
    local function refreshSongs()
        assert(type(listfiles)=="function" and type(readfile)=="function","Executor file APIs unavailable")
        if type(makefolder)=="function" and type(isfolder)=="function" then
            if not isfolder("RobloxPiano") then makefolder("RobloxPiano") end
            if not isfolder("RobloxPiano/Songs") then makefolder("RobloxPiano/Songs") end
        end
        local files=listfiles("RobloxPiano/Songs");local labels={};pstate.Files={}
        for _,path in ipairs(files) do
            if path:lower():match("%.mid$") then
                local label=path:match("[^/\\]+$") or path
                if not pstate.Files[label] then table.insert(labels,label);pstate.Files[label]=path end
            end
        end
        table.sort(labels);Options.PianoSong:SetValues(labels)
        if #labels>0 then Options.PianoSong:SetValue(labels[1]) end
        pianoStatus:SetText("Piano: "..#labels.." song(s)")
    end
    local function playPiano()
        if pstate.Playing then return end
        local _,hum=host.Character(player)
        assert(hum and hum.Sit,"Sit at a piano before playback")
        assert(type(readfile)=="function","readfile unavailable")
        vim=game:GetService("VirtualInputManager")
        if not pstate.Paused then
            local path=pstate.Files[value("PianoSong","")];assert(path,"Refresh and choose a .mid file")
            local data=readfile(path);assert(type(data)=="string" and #data<=4*1024*1024,"MIDI exceeds 4 MB or is unreadable")
            local ok,events=pcall(pdata.Parse,data);assert(ok,"Invalid/unsupported MIDI: "..tostring(events))
            assert(#events>0 and #events<=100000,"No notes, or more than 100000 notes")
            pstate.Events=events;pstate.Index=1;pstate.Clock=0
        end
        pstate.Generation+=1;local generation=pstate.Generation
        pstate.Playing=true;pstate.Paused=false;releaseKeys();suspendKeys(true)
        if Library.Toggled then Library:Toggle() end
        pianoStatus:SetText("Piano: playing")
        task.spawn(function()
            local ok,err=pcall(function()
                local previous=os.clock()
                while not controller.Dead and pstate.Playing and generation==pstate.Generation do
                    local _,h=host.Character(player)
                    if not h or not h.Sit or not host.PianoCanPlay() then break end
                    local now=os.clock();pstate.Clock+=(now-previous)*value("PianoSpeed",1);previous=now
                    local events=pstate.Events
                    local processed=0
                    local plain,shifted={},{}
                    local firstDue=events[pstate.Index] and events[pstate.Index].time or math.huge
                    local chordEnd=math.min(pstate.Clock,firstDue+0.02)
                    while pstate.Index<=#events and events[pstate.Index].time<=chordEnd and processed<64 do
                        local event=events[pstate.Index];pstate.Index+=1;processed+=1
                        local note=pdata.Notes[event.note+value("PianoTranspose",0)]
                        local code=note and pdata.Keys[note]
                        if code then table.insert(pdata.IsShift(note) and shifted or plain,code) end
                    end
                    local function chord(codes,shift)
                        if #codes==0 or generation~=pstate.Generation then return end
                        if shift then pstate.Keys[Enum.KeyCode.LeftShift]=true;vim:SendKeyEvent(true,Enum.KeyCode.LeftShift,false,game) end
                        for _,code in ipairs(codes) do pstate.Keys[code]=true;vim:SendKeyEvent(true,code,false,game) end
                        task.wait(0.02)
                        if generation~=pstate.Generation then return end
                        for _,code in ipairs(codes) do vim:SendKeyEvent(false,code,false,game);pstate.Keys[code]=nil end
                        if shift then vim:SendKeyEvent(false,Enum.KeyCode.LeftShift,false,game);pstate.Keys[Enum.KeyCode.LeftShift]=nil end
                    end
                    chord(plain,false);chord(shifted,true)
                    if generation~=pstate.Generation then return end
                    if pstate.Index>#events then
                        if enabled("PianoLoop") then pstate.Index=1;pstate.Clock=0;previous=os.clock();task.wait(0.15)
                        else break end
                    end
                    task.wait(0.01)
                end
            end)
            if generation==pstate.Generation then stopPiano(true);if not ok then notify("Piano: "..tostring(err)) end end
        end)
    end
    button(pg,"Refresh songs",refreshSongs)
    button(pg,"Play / resume",playPiano)
    button(pg,"Pause",function() if pstate.Playing then stopPiano(false);pstate.Paused=true end end)
    button(pg,"Stop",function() stopPiano(true) end)
    Options.PianoSong:OnChanged(function() stopPiano(true) end)
    function controller:Destroy()
        if self.Dead then return end
        self.Dead=true;stopPiano(true);runtime:Destroy();table.clear(self.Scopes)
    end
    return controller
end

return createZorcex(host)
end

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
    info:AddLabel("Zorcex imports are optional and start OFF")
    info:AddLabel("UI: deividcomsono (MIT)")
    info:AddLabel("Imported scripts: Zorcex / JJS-Script")
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
    toggle(defense,"AutoBlock","Auto Block","B")
    defense:AddDropdown("BlockTransport",{Text="Block transport",Values={"Keyboard","Auto","Remotes"},Default=1})
    defense:AddLabel("Game block key"):AddKeyPicker("BlockInputKey",{Default="F",Text="Game block key",Mode="Press",NoUI=true})
    toggle(defense,"BlockAnimations","Animation detection")
    Toggles.BlockAnimations:SetValue(true)
    toggle(defense,"BlockRemoteSignals","Remote event detection")
    Toggles.BlockRemoteSignals:SetValue(true)
    defense:AddDropdown("BlockAnimationFilter",{Text="Animation filter",Values={"Action + names","Names only"},Default=1})
    toggle(defense,"NoStun","No Stun (Client)","None")
    slider(defense,"DefenseRange","Block Distance",10,3,30)
    slider(defense,"BlockHold","Block Duration",0.5,0.1,1,2)
    defense:AddLabel("Rewrite + optional Zorcex event detector")
    defense:AddLabel("Counter: Itadori / Zorcex Moveset")
    defenseStatus=defense:AddLabel("Defense: off")
    action(defense,"Check Block API",function()
        local activated,_,err=findBlockRemotes()
        defenseStatus:SetText(activated and "Remotes available / Keyboard available" or "Remotes unavailable / use Keyboard")
        notify(activated and "Zorcex remotes found; Keyboard does not require them" or (tostring(err).."; try Keyboard with your JJS block key"))
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
            if AddonController then AddonController:StopPositionDrivers() end
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
            stopAutoBlock();if AddonController then AddonController:BlockStopped() end;defenseStatus:SetText("Defense: off");return
        end
        local ok,err=startAutoBlock()
        if not ok then
            Toggles.AutoBlock:SetValue(false)
            defenseStatus:SetText("Block API: unavailable")
            notify("Auto Block unavailable: " .. tostring(err))
        else defenseStatus:SetText("Defense: listening / "..tostring(blockMode)) end
    end)
    Toggles.NoStun:OnChanged(function() if not on("NoStun") then stopNoStun() end end)
    local function restartDefense()
        if ready and on("AutoBlock") then
            local ok,err=startAutoBlock()
            if not ok then Toggles.AutoBlock:SetValue(false);notify(err) end
        end
    end
    Options.BlockTransport:OnChanged(restartDefense)
    -- KeyPicker.OnChanged fires on key/mode changes, not a press.
    Options.BlockInputKey:OnChanged(restartDefense)
    Toggles.BlockAnimations:OnChanged(function() if not on("BlockAnimations") then table.clear(blockCandidates) end end)
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
    connect(player.CharacterRemoving,function() resetCombat();stopNoStun() end)
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
        if on("AutoBlock") then updateAutoBlock() end
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
        if on("AutoBlock") then
            if blockMode=="Remotes" and (not blockActivated or not blockDeactivated or not blockActivated:IsDescendantOf(ReplicatedStorage) or not blockDeactivated:IsDescendantOf(ReplicatedStorage)) then
                Toggles.AutoBlock:SetValue(false);notify("BlockService disappeared; select Keyboard")
            else defenseStatus:SetText((activeBlock and "Blocking / " or "Listening / ")..tostring(blockMode).." / "..blockReason) end
        else defenseStatus:SetText("Defense: off") end
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
        updateNoStun()
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
        local touch=env.__ClaudeHubTouch
        if freeMoving and touch then
            freeYaw-=(touch.LookX or 0)*0.003
            freePitch=math.clamp(freePitch-(touch.LookY or 0)*0.003,-1.5,1.5)
            touch.LookX=0;touch.LookY=0
        end
        local rotation = CFrame.fromOrientation(freePitch, freeYaw, 0)
        if freeMoving then
            local function key(code) return inputDown(code) and 1 or 0 end
            local v = Vector3.new(key(Enum.KeyCode.D)-key(Enum.KeyCode.A),key(Enum.KeyCode.E)-key(Enum.KeyCode.Q),key(Enum.KeyCode.S)-key(Enum.KeyCode.W))
            if v.Magnitude > 1 then v = v.Unit end
            local multiplier = inputDown(Enum.KeyCode.LeftShift) and 3 or 1
            freePosition += rotation:VectorToWorldSpace(v) * val("FreecamSpeed",32) * multiplier * math.min(dt,0.1)
        end
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.new(freePosition) * rotation
        camera.Focus = camera.CFrame * CFrame.new(0,0,-512)
    end)
    refreshPlayers()
    AddonController=buildZorcex({Window=Window,Combat=Tabs.Combat,Library=Library,Options=Options,Toggles=Toggles,
        Notify=notify,Character=character,
        CanAct=function() return ready and focused and UIS:GetFocusedTextBox()==nil end,
        PianoCanPlay=function() return focused and UIS:GetFocusedTextBox()==nil and not Library.Toggled end})
    local function addon(path, fn)
        local ok, err = pcall(function() fn(download(path)) end)
        if not ok then warn("[ClaudeHub JJS] Optional addon unavailable: " .. path .. ": " .. tostring(err)) end
    end
    addon("addons/ThemeManager.lua", function(manager)
        manager:SetLibrary(Library); manager:SetFolder("ClaudeHub/Obsidian"); manager:ApplyToTab(Tabs.Settings)
    end)
    addon("addons/SaveManager.lua", function(manager)
        manager:SetLibrary(Library); manager:IgnoreThemeSettings()
        local ignore={"MenuKeybind","Freecam","Spectate","SpectatePlayer","CombatPlayer","ServerChoice","JobID","AutoBlock","NoStun"}
        for _,id in ipairs(AddonController.Ignore) do table.insert(ignore,id) end
        manager:SetIgnoreIndexes(ignore)
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
