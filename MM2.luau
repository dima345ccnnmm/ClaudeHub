-- ClaudeHub MM2 v0.1.7 | Ordinary Obsidian (deividcomsono, MIT).
-- Ordinary Obsidian. Targeting adapted from Averiias, Stefanuk12, xaxa; MM2-scoped transport.
local VERSION = "0.1.7"
local env = getgenv and getgenv() or _G
local KEY = "__ClaudeHubMM2"
if env[KEY] and not env[KEY].Unloaded then
    env[KEY]:Notify("ClaudeHub MM2 is already open. RightControl toggles the menu.", 4)
    return env[KEY]
end
assert(game.GameId == 66654135, "ClaudeHub MM2: open Murder Mystery 2 first")
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
local serverRows, serverMap, serverCursor = {}, {}, nil
local serversBusy, teleportBusy, serverGeneration = false, false, 0
local serverStatus, targetStatus
local aimGui
local requestHTTP = (type(request)=="function" and request) or (type(http_request)=="function" and http_request)
    or (type(syn)=="table" and syn.request) or (type(http)=="table" and http.request)
local playerNames = {}
local freeAction = "ClaudeHubMM2_Freecam"
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
for _, name in ipairs({"Speed", "Jump", "FOV", "Facing", "Light", "Fly", "Noclip", "AntiFling"}) do pools[name] = {} end
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
local roleColors={Knife=Color3.fromRGB(255,90,100),Gun=Color3.fromRGB(80,165,255),Hero=Color3.fromRGB(255,200,70),Innocent=Color3.fromRGB(80,225,120),Unknown=Color3.fromRGB(175,175,185)}
local roles,rolesAt,rolesBusy,rolesGeneration={},-math.huge,false,0
local roundSignal=nil
local roundConnections={}
local function clearRoles(state)
    roundSignal=state;roles={};rolesAt=-math.huge;rolesGeneration+=1
end
local function booleanFlag(object,names)
    if not object then return nil end
    for _,name in ipairs(names) do
        local value=object:GetAttribute(name)
        if type(value)=="boolean" then return value end
        local child=object:FindFirstChild(name)
        if child and child:IsA("BoolValue") then return child.Value end
    end
    return nil
end
local function inRound(p)
    local mode=val("RoundDetection","Auto")
    if mode=="Lobby (force gray)" then return false end
    if mode=="In round (manual)" then return true end
    if roundSignal==false then return false end
    local lobby=booleanFlag(p,{"InLobby"})
    if lobby==nil then lobby=booleanFlag(p.Character,{"InLobby"}) end
    if lobby==true then return false end
    local personal=booleanFlag(p,{"InRound","InGame"})
    if personal==nil then personal=booleanFlag(p.Character,{"InRound","InGame"}) end
    if personal~=nil then return personal end
    local active=booleanFlag(ReplicatedStorage,{"RoundActive","RoundInProgress"})
    if active==nil then active=booleanFlag(workspace,{"RoundActive","RoundInProgress"}) end
    if active~=nil then return active end
    return roundSignal==true
end
local function acceptRoles(data)
    if type(data)~="table" then return end
    local fresh={}
    for id,row in pairs(data) do
        if type(row)=="table" and type(row.Role)=="string" then
            fresh[tostring(id)]={Role=row.Role,Dead=row.Dead==true,Killed=row.Killed==true}
        end
    end
    roles=fresh;rolesAt=os.clock()
end
local function bindRoundRemote(object)
    if not object:IsA("RemoteEvent") or not object:IsDescendantOf(ReplicatedStorage) or roundConnections[object] then return end
    local name=object.Name
    if name=="RoundStart" or name=="RoundStarted" then
        roundConnections[object]=connect(object.OnClientEvent,function() clearRoles(true) end)
    elseif name=="RoundEnd" or name=="RoundEnded" then
        roundConnections[object]=connect(object.OnClientEvent,function() clearRoles(false) end)
    elseif name=="UpdatePlayerData" then
        roundConnections[object]=connect(object.OnClientEvent,function(data) acceptRoles(data) end)
    end
end
local rolePollAt=-math.huge
local function pollRoles()
    if rolesBusy or os.clock()-rolePollAt<2 then return end
    if not (on("ESP") or on("AimAssist") or on("SilentAim") or on("MurderWarning") or on("HUD")) then return end
    rolePollAt=os.clock()
    local remote=ReplicatedStorage:FindFirstChild("GetPlayerData",true)
    if not remote or not remote:IsA("RemoteFunction") then return end
    rolesBusy=true
    local generation=rolesGeneration
    task.spawn(function()
        local ok,data=pcall(function() return remote:InvokeServer() end)
        rolesBusy=false
        if closed or not ready or generation~=rolesGeneration then return end
        if ok then acceptRoles(data) end
    end)
end
local function toolsIn(container)
    local knife,gun=false,false
    if container then for _,tool in ipairs(container:GetChildren()) do
        if tool:IsA("Tool") then
            local name=tool.Name:lower()
            if name=="knife" then knife=true elseif name=="gun" then gun=true end
        end
    end end
    return knife,gun
end
local function roleHint(p)
    if not inRound(p) then return "Unknown","Lobby / unconfirmed",roleColors.Unknown end
    local row=os.clock()-rolesAt<=6 and (roles[p.Name] or roles[tostring(p.UserId)])
    if row and (row.Dead or row.Killed) then return "Unknown","Eliminated",roleColors.Unknown end
    if row then
        if row.Role=="Murderer" then return "Knife","Murderer",roleColors.Knife end
        if row.Role=="Sheriff" or row.Role=="Hero" then return "Gun",row.Role,row.Role=="Hero" and roleColors.Hero or roleColors.Gun end
        if row.Role=="Innocent" then return "Innocent","Innocent",roleColors.Innocent end
    end
    local knife,gun=toolsIn(p.Character)
    local k,g=toolsIn(p:FindFirstChildOfClass("Backpack"));knife,gun=knife or k,gun or g
    if knife and not gun then return "Knife","Knife seen",roleColors.Knife end
    if gun and not knife then return "Gun","Gun seen",roleColors.Gun end
    return "Unknown","Unknown",roleColors.Unknown
end

local function roleTargetAllowed(target,filter)
    if not inRound(player) or not inRound(target) then return false end
    local targetRole=roleHint(target)
    if filter=="Auto" then
        local ownRole=roleHint(player)
        if ownRole=="Knife" then return targetRole=="Gun" end
        if ownRole=="Gun" then return targetRole=="Knife" end
        return false
    end
    if filter=="Murderer" then return targetRole=="Knife" end
    if filter=="Sheriff / Hero" then return targetRole=="Gun" end
    return filter=="Any visible player" and targetRole~="Unknown"
end

local function observedAttribute(keys)
    for _,object in ipairs({workspace,ReplicatedStorage}) do for _,name in ipairs(keys) do
        local value=object:GetAttribute(name)
        if type(value)=="string" and #value>0 and #value<=80 then return value.." (attribute)" end
    end end
end
local function roundInfo()
    local map=observedAttribute({"MapName","CurrentMap"}) or "not exposed"
    local status=observedAttribute({"RoundState","RoundStatus"}) or (inRound(player) and "In round" or "Lobby / unconfirmed")
    return map,status
end
local gunObjects={}
local function clearGunEntry(object)
    local entry=gunObjects[object]
    if entry then
        if entry.Highlight then entry.Highlight:Destroy() end
        if entry.Gui then entry.Gui:Destroy() end
        gunObjects[object]=nil
    end
end
local function clearGuns() for object in pairs(gunObjects) do clearGunEntry(object) end end
local function gunInInventory(object)
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character and object:IsDescendantOf(p.Character) then return true end
        local backpack=p:FindFirstChildOfClass("Backpack")
        if backpack and object:IsDescendantOf(backpack) then return true end
    end
    return false
end
local function rememberGun(object)
    if object.Name:lower()=="gundrop" and (object:IsA("Model") or object:IsA("BasePart")) and not gunInInventory(object) then
        gunObjects[object]=gunObjects[object] or {}
    end
end
local function scanGuns()
    clearGuns()
    for _,object in ipairs(workspace:GetDescendants()) do rememberGun(object) end
end
local function updateGuns()
    local camera=workspace.CurrentCamera
    for object,entry in pairs(gunObjects) do
        if not object:IsDescendantOf(workspace) or gunInInventory(object) then clearGunEntry(object);continue end
        if not on("GunESP") then
            if entry.Highlight then entry.Highlight:Destroy();entry.Gui:Destroy();entry.Highlight=nil;entry.Gui=nil end
            continue
        end
        local part=object:IsA("BasePart") and object or object:FindFirstChild("Handle",true)
        if not part or not part:IsA("BasePart") then part=object:FindFirstChildWhichIsA("BasePart",true) end
        local distance=part and camera and (part.Position-camera.CFrame.Position).Magnitude
        if not part or not part:IsA("BasePart") or not distance or distance>val("ESPRange",500) then
            if entry.Highlight then entry.Highlight.Enabled=false;entry.Gui.Enabled=false end
            continue
        end
        if not entry.Highlight then
            entry.Highlight=Instance.new("Highlight",markerFolder)
            entry.Highlight.Name="DroppedGunMarker";entry.Highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
            entry.Highlight.FillTransparency=0.6;entry.Highlight.FillColor=Color3.fromRGB(255,205,65)
            entry.Highlight.OutlineColor=Color3.fromRGB(255,235,150)
            entry.Gui=Instance.new("BillboardGui",hud);entry.Gui.Name="DroppedGunLabel"
            entry.Gui.AlwaysOnTop=true;entry.Gui.Size=UDim2.fromOffset(220,30);entry.Gui.StudsOffsetWorldSpace=Vector3.new(0,1.2,0)
            entry.Label=Instance.new("TextLabel",entry.Gui);entry.Label.Size=UDim2.fromScale(1,1)
            entry.Label.BackgroundTransparency=1;entry.Label.Font=Enum.Font.Code;entry.Label.TextSize=14
            entry.Label.TextColor3=Color3.fromRGB(255,225,115);entry.Label.TextStrokeTransparency=0.3
        end
        entry.Highlight.Adornee=part;entry.Highlight.Enabled=true
        entry.Gui.Adornee=part;entry.Gui.MaxDistance=val("ESPRange",500);entry.Gui.Enabled=true
        entry.Label.Text=string.format("Dropped gun | %.0f studs",distance)
    end
end
local aimTrigger=false
local function resetCombat() combatTarget=nil end
local function assistHeld()
    local mode=val("AimActivation","RMB or L2")
    return (mode~="L2 only" and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
        or (mode~="RMB only" and aimTrigger)
end
local function equippedWeapon()
    local k,g=toolsIn(player.Character);return k or g
end
local function aimCandidate(p,camera,radiusMultiplier,settingsPrefix)
    local prefix=settingsPrefix or "Aim"
    if p==player then return end
    local _,_,myRoot=character(player)
    local c,h,root=character(p)
    if not c or not myRoot then return end
    if (root.Position-myRoot.Position).Magnitude>val(prefix.."Range",180) then return end
    local filter=val(prefix.."Role","Any visible player")
    local hint=roleHint(p)
    if (filter=="Knife seen" or filter=="Murderer") and hint~="Knife" then return end
    if (filter=="Gun seen" or filter=="Sheriff / Hero") and hint~="Gun" then return end
    local choice=val(prefix.."Point","UpperTorso")
    local part
    if choice=="Head" then part=c:FindFirstChild("Head") or root
    elseif choice=="HumanoidRootPart" then part=root
    else part=c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") or root end
    if not part:IsA("BasePart") then return end
    local point=part.Position+root.AssemblyLinearVelocity*val(prefix.."Prediction",0)
    local screen,visible=camera:WorldToViewportPoint(point)
    if not visible or screen.Z<=0 then return end
    local center=camera.ViewportSize/2
    local delta=Vector2.new(screen.X-center.X,screen.Y-center.Y)
    local pixels=delta.Magnitude
    if pixels>val(prefix.."Radius",110)*(radiusMultiplier or 1) then return end
    local offset=point-camera.CFrame.Position
    if offset.Magnitude<0.05 then return end
    local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances={player.Character,markerFolder};ray.IgnoreWater=true
    local hit=workspace:Raycast(camera.CFrame.Position,offset,ray)
    if hit and not hit.Instance:IsDescendantOf(c) then return end
    return point,pixels,c
end
local function chooseAimTarget(camera)
    if on("AimSticky") and combatTarget then
        local point,_,model=aimCandidate(combatTarget,camera,1.1)
        if point then return combatTarget,point,model end
    end
    local selected,point,model,best
    for _,p in ipairs(Players:GetPlayers()) do
        local at,pixels,c=aimCandidate(p,camera,1)
        if at and (not best or pixels<best) then selected,point,model,best=p,at,c,pixels end
    end
    return selected,point,model
end

local flight
local function stopFly()
    if flight then
        local state=flight;flight=nil
        for _,object in pairs({state.Velocity,state.Orientation,state.Attachment}) do pcall(function() object:Destroy() end) end
        pcall(function()
            if state.Root.Parent then state.Root.AssemblyLinearVelocity=Vector3.zero;state.Root.AssemblyAngularVelocity=Vector3.zero end
        end)
    end
    restore(pools.Fly)
end
local function startFly()
    if on("SelfRagdoll") then Toggles.SelfRagdoll:SetValue(false) end
    stopFly()
    local _,h,r=character(player)
    if not h or r.Anchored or h.Sit then return false end
    local attachment=Instance.new("Attachment",r);attachment.Name="ClaudeHubFlightAttachment"
    flight={Root=r,Humanoid=h,Attachment=attachment}
    local velocity=Instance.new("LinearVelocity",r);flight.Velocity=velocity
    velocity.Name="ClaudeHubFlightVelocity";velocity.Attachment0=attachment
    velocity.RelativeTo=Enum.ActuatorRelativeTo.World;velocity.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector
    velocity.ForceLimitsEnabled=false;velocity.MaxForce=math.huge;velocity.VectorVelocity=Vector3.zero
    local orientation=Instance.new("AlignOrientation",r);flight.Orientation=orientation
    orientation.Name="ClaudeHubFlightOrientation";orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment
    orientation.Attachment0=attachment;orientation.MaxTorque=math.huge;orientation.Responsiveness=25
    orientation.CFrame=r.CFrame.Rotation
    override(pools.Fly,h,"AutoRotate",false);override(pools.Fly,h,"PlatformStand",true)
    return true
end
local function updateMovement()
    if not ready then return end
    local c,h,r=character(player)
    if flight then
        if not on("Fly") or not r or flight.Root~=r or r.Anchored or h.Sit or on("Freecam") or on("Spectate") then
            stopFly();if on("Fly") then Toggles.Fly:SetValue(false) end
        else
            override(pools.Fly,h,"AutoRotate",false);override(pools.Fly,h,"PlatformStand",true)
            local camera=workspace.CurrentCamera
            local movement=Vector3.zero
            if camera and not menuBusy() then
                local function key(code) return UIS:IsKeyDown(code) and 1 or 0 end
                local x=key(Enum.KeyCode.D)-key(Enum.KeyCode.A)
                local z=key(Enum.KeyCode.W)-key(Enum.KeyCode.S)
                local up=key(Enum.KeyCode.Space)+key(Enum.KeyCode.E)-key(Enum.KeyCode.LeftControl)-key(Enum.KeyCode.Q)
                local direction=h.MoveDirection
                if x~=0 or z~=0 then
                    local forward=Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z)
                    local right=Vector3.new(camera.CFrame.RightVector.X,0,camera.CFrame.RightVector.Z)
                    if forward.Magnitude>0.001 then forward=forward.Unit end
                    if right.Magnitude>0.001 then right=right.Unit end
                    direction=forward*z+right*x
                end
                movement=direction+Vector3.new(0,up,0)
                if movement.Magnitude>1 then movement=movement.Unit end
                local facing=camera.CFrame.LookVector
                local flat=Vector3.new(facing.X,0,facing.Z)
                if flat.Magnitude>0.001 then flight.Orientation.CFrame=CFrame.lookAt(Vector3.zero,flat) end
            end
            flight.Velocity.VectorVelocity=movement*val("FlySpeed",45)
        end
    end
    if on("Noclip") and c then
        for object in pairs(pools.Noclip) do if not object:IsDescendantOf(c) then restore(pools.Noclip);break end end
        for _,part in ipairs(c:GetDescendants()) do
            if part:IsA("BasePart") and (part.CanCollide or pools.Noclip[part]) then override(pools.Noclip,part,"CanCollide",false) end
        end
    elseif next(pools.Noclip) then restore(pools.Noclip) end
end

-- Target selection from the supplied Universal Silent Aim, with MM2-specific shot transport.
-- Original authors: Averiias, Stefanuk12, xaxa. Standalone Linoria UI removed.
local SilentEngine=(function()
    local engine={
        Settings={Enabled=false,ClassName="Universal Silent Aim - Averiias, Stefanuk12, xaxa",
            ToggleKey="B",TeamCheck=false,VisibleCheck=true,TargetPart="HumanoidRootPart",SilentAimMethod="MM2 Gun",
            FOVRadius=130,FOVVisible=false,ShowSilentAimTarget=false,MouseHitPrediction=false,
            MouseHitPredictionAmount=0.165,HitChance=100,TargetRole="All players (original)"},
        Color=Color3.fromRGB(54,57,241),TargetColor=Color3.fromRGB(54,57,241),
        LastError="",Seen=0,Redirected=0,LastCall="none",WeaponStatus="Equip Gun",
        ConfigPaths={},OwnedStates={},Destroyed=false,
    }
    local Mouse=player:GetMouse()
    local random=Random.new()
    local methods={["MM2 Gun"]=true,Raycast=true,FindPartOnRay=true,FindPartOnRayWithWhitelist=true,
        FindPartOnRayWithIgnoreList=true,["Mouse.Hit/Target"]=true}
    local ExpectedArguments={
        FindPartOnRayWithIgnoreList={ArgCountRequired=3,Args={"Instance","Ray","table","boolean","boolean"}},
        FindPartOnRayWithWhitelist={ArgCountRequired=3,Args={"Instance","Ray","table","boolean"}},
        FindPartOnRay={ArgCountRequired=2,Args={"Instance","Ray","Instance","boolean","boolean"}},
        Raycast={ArgCountRequired=3,Args={"Instance","Vector3","Vector3","RaycastParams"}},
    }
    local function CalculateChance(percentage)
        percentage=math.clamp(math.floor(tonumber(percentage) or 0),0,100)
        if percentage<=0 then return false end
        if percentage>=100 then return true end
        return random:NextNumber(0,100)<percentage
    end
    local function ValidateArguments(args,description)
        local matches=0
        if #args<description.ArgCountRequired then return false end
        for position,argument in next,args do
            if type(position)=="number" and typeof(argument)==description.Args[position] then matches+=1 end
        end
        return matches>=description.ArgCountRequired
    end
    local function getDirection(origin,position)
        local offset=position-origin
        if offset.Magnitude<0.001 then return nil end
        return offset.Unit*1000
    end
    local function getMousePosition() return UIS:GetMouseLocation() end
    local function IsPlayerVisible(target,camera,part)
        if not target.Character or not player.Character then return false end
        local ignore={player.Character,target.Character}
        if markerFolder then table.insert(ignore,markerFolder) end
        -- The source mixed Instances into CastPoints; Roblox expects Vector3s.
        return #camera:GetPartsObscuringTarget({part.Position},ignore)==0
    end
    -- Port of main.lua:getClosestPlayer; original mode has no MM2 role dependency.
    local function getClosestPlayer()
        if not engine.Settings.TargetPart then engine.Target=nil;return nil end
        local camera=workspace.CurrentCamera
        if not camera then engine.Target=nil;return nil end
        local closest,distanceToMouse
        local previous=on("SilentSticky") and engine.Target or nil
        engine.Target=nil
        for _,target in next,Players:GetPlayers() do
            if target==player then continue end
            if engine.Settings.TeamCheck and target.Team==player.Team then continue end
            -- Optional ClaudeHub extension. Default bypasses role/round detection entirely.
            if engine.Settings.TargetRole~="All players (original)" and not roleTargetAllowed(target,engine.Settings.TargetRole) then continue end
            local c=target.Character
            if not c then continue end
            local root=c:FindFirstChild("HumanoidRootPart")
            local h=c:FindFirstChild("Humanoid")
            if not root or not h or h.Health<=0 then continue end
            local name=engine.Settings.TargetPart
            if name=="Random" then name=({"Head","HumanoidRootPart"})[math.random(1,2)] end
            local part=c:FindFirstChild(name)
            if not part or not part:IsA("BasePart") then continue end
            if engine.Settings.VisibleCheck and not IsPlayerVisible(target,camera,part) then continue end
            local screen,onScreen=camera:WorldToScreenPoint(root.Position)
            if not onScreen then continue end
            local distance=(getMousePosition()-Vector2.new(screen.X,screen.Y)).Magnitude
            if distance<=engine.Settings.FOVRadius then
                if target==previous then engine.Target=target;return part end
                if distance<=(distanceToMouse or engine.Settings.FOVRadius) then
                    closest=part;distanceToMouse=distance;engine.Target=target
                end
            end
        end
        return closest
    end
    local function active()
        return not engine.Destroyed and not closed and ready and engine.Settings.Enabled
            and focused and not cameraState and UIS:GetFocusedTextBox()==nil and Library.Toggled~=true
    end
    local function gunRemote()
        local c=player.Character
        local gun=c and c:FindFirstChild("Gun")
        if not gun or not gun:IsA("Tool") then return nil,"Equip Gun" end
        local script=gun:FindFirstChild("KnifeLocal")
        local beam=script and script:FindFirstChild("CreateBeam")
        if not beam then return nil,"Gun: CreateBeam not found" end
        -- Known MM2 layout: Gun.KnifeLocal.CreateBeam.RemoteFunction.
        -- Some builds expose CreateBeam itself as the remote. No generic remote guessing.
        local remote=beam:FindFirstChild("RemoteFunction")
        if remote and remote:IsA("RemoteFunction") then return remote,"MM2 remote ready" end
        if beam:IsA("RemoteFunction") or beam:IsA("RemoteEvent") then return beam,"MM2 remote ready" end
        return nil,"Gun: unsupported CreateBeam layout"
    end
    local function weaponCaller(caller)
        if typeof(caller)~="Instance" then return false end
        local c=player.Character
        if not c then return false end
        for _,name in ipairs({"Gun","Knife"}) do
            local tool=c:FindFirstChild(name)
            if tool and tool:IsA("Tool") and caller:IsDescendantOf(tool) then return true end
        end
        return false
    end
    local function rayResolver(method,args,caller)
        if not active() then return nil end
        local chosen=engine.Settings.SilentAimMethod
        if chosen=="MM2 Gun" then
            if method~="InvokeServer" and method~="FireServer" then return nil end
            local remote,status=gunRemote();engine.WeaponStatus=status
            if not remote or args[1]~=remote then return nil end
            if (remote:IsA("RemoteFunction") and method~="InvokeServer")
                or (remote:IsA("RemoteEvent") and method~="FireServer") then return nil end
            engine.Seen+=1
            -- Preserve the original call/arity. Only the known target-position field changes.
            if args.n~=4 or args[2]~=1 or typeof(args[3])~="Vector3" or args[4]~="AH2" then
                engine.LastError="Unsupported MM2 shot signature; left unchanged"
                return nil
            end
            engine.LastCall="Gun / "..method.." (1, Vector3, AH2)"
            if not CalculateChance(engine.Settings.HitChance) then return nil end
            local hitPart=getClosestPlayer()
            if not hitPart then return nil end
            args[3]=hitPart.Position
            engine.LastError="";engine.Redirected+=1
            return args
        end
        -- Legacy compatibility modes FAIL CLOSED. Camera/shared/unknown callers are never changed.
        if not weaponCaller(caller) or args[1]~=workspace then return nil end
        if method=="findPartOnRay" then method="FindPartOnRay" end
        if chosen~=method then return nil end
        engine.Seen+=1
        local description=ExpectedArguments[method]
        if not description or not ValidateArguments(args,description) then return nil end
        if not CalculateChance(engine.Settings.HitChance) then return nil end
        local hitPart=getClosestPlayer()
        if not hitPart then return nil end
        local origin=method=="Raycast" and args[2] or args[2].Origin
        local originalDirection=method=="Raycast" and args[3] or args[2].Direction
        local offset=hitPart.Position-origin
        if offset.Magnitude<0.001 or originalDirection.Magnitude<0.001 then return nil end
        local direction=offset.Unit*originalDirection.Magnitude
        if method=="Raycast" then args[3]=direction else args[2]=Ray.new(origin,direction) end
        engine.LastCall="Weapon script / "..method
        engine.Redirected+=1
        return args
    end
    local function indexResolver(index,caller)
        if not active() or engine.Settings.SilentAimMethod~="Mouse.Hit/Target" or not weaponCaller(caller) then return false end
        if type(index)~="string" then return false end
        index=index:lower()
        if index~="target" and index~="hit" and index~="unitray" then return false end
        engine.Seen+=1
        if not CalculateChance(engine.Settings.HitChance) then return false end
        local hitPart=getClosestPlayer()
        if not hitPart then return false end
        engine.Redirected+=1
        if index=="target" then return true,hitPart end
        if index=="hit" then
            local cf=hitPart.CFrame
            if engine.Settings.MouseHitPrediction then cf+=hitPart.AssemblyLinearVelocity*engine.Settings.MouseHitPredictionAmount end
            return true,cf
        end
        local camera=workspace.CurrentCamera
        if not camera then return false end
        local mouseOrigin=Mouse.Origin
        local origin=typeof(mouseOrigin)=="CFrame" and mouseOrigin.Position or camera.CFrame.Position
        local direction=getDirection(origin,hitPart.Position)
        if direction then return true,Ray.new(origin,direction.Unit) end
        return false
    end
    local function recordError(err)
        engine.LastError=tostring(err):sub(1,220)
    end
    function engine:RefreshTarget()
        local _,status=gunRemote();self.WeaponStatus=status
        if active() then return getClosestPlayer() end
        self.Target=nil
        return nil
    end
    function engine:Stop()
        self.Target=nil
        self.Settings.Enabled=false
        for _,state in pairs(self.OwnedStates) do
            if state.Owner==self then state.Resolve=nil;state.RecordError=nil;state.Owner=nil end
        end
    end
    function engine:Install()
        if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" or type(checkcaller)~="function" then
            return false,"Silent Aim needs hookmetamethod, getnamecallmethod and checkcaller"
        end
        if self.Settings.SilentAimMethod~="MM2 Gun" and type(getcallingscript)~="function" then
            return false,"Legacy mode needs getcallingscript; use MM2 Gun"
        end
        self.LastError=""
        -- Old global hooks cannot reliably be removed. Make ClaudeHub-owned resolvers passive.
        for _,key in ipairs({"__ClaudeHubMM2SilentHook","__ClaudeHubMM2SilentRaycastHook",
            "__ClaudeHubMM2SilentFullNamecall_v1","__ClaudeHubMM2SilentFullIndex_v1",
            "__ClaudeHubMM2SilentFullNamecall_v2","__ClaudeHubMM2SilentFullIndex_v2",
            "__ClaudeHubMM2SilentFullNamecall_v3","__ClaudeHubMM2SilentFullIndex_v3"}) do
            local previousState=env[key]
            if type(previousState)=="table" then previousState.Resolve=nil;previousState.RecordError=nil;previousState.Owner=nil end
        end
        local wrap=type(newcclosure)=="function" and newcclosure or function(fn) return fn end
        local getMethod,isCaller=getnamecallmethod,checkcaller
        local callerAPI=type(getcallingscript)=="function" and getcallingscript or nil
        local function captureCaller()
            if not callerAPI then return nil end
            local ok,value=pcall(callerAPI)
            if ok then return value end
            return nil
        end
        local rayState=env.__ClaudeHubMM2SilentFullNamecall_v4
        if not rayState or not rayState.Installed then
            rayState={};local state=rayState;local oldNamecall
            local function intercept(...)
                local method=getMethod()
                if state.Resolve and not state.Busy and not isCaller()
                    and (method=="InvokeServer" or method=="FireServer" or method=="Raycast"
                        or method=="FindPartOnRay" or method=="findPartOnRay"
                        or method=="FindPartOnRayWithIgnoreList" or method=="FindPartOnRayWithWhitelist") then
                    local args=table.pack(...)
                    local caller=state.NeedsCaller and captureCaller() or nil
                    state.Busy=true
                    local ok,modified=pcall(state.Resolve,method,args,caller)
                    state.Busy=false
                    if ok and modified then return oldNamecall(table.unpack(modified,1,modified.n)) end
                    if not ok and state.RecordError then state.RecordError(modified) end
                end
                return oldNamecall(...)
            end
            local ok,previous=pcall(function() return hookmetamethod(game,"__namecall",wrap(intercept)) end)
            if not ok or type(previous)~="function" then return false,tostring(previous) end
            oldNamecall=previous;rayState.Installed=true;env.__ClaudeHubMM2SilentFullNamecall_v4=rayState
        end
        self.OwnedStates.Ray=rayState
        rayState.NeedsCaller=self.Settings.SilentAimMethod~="MM2 Gun"
        rayState.Owner=self;rayState.Resolve=rayResolver;rayState.RecordError=recordError
        -- Default MM2 Gun mode installs NO Mouse.__index hook.
        if self.Settings.SilentAimMethod=="Mouse.Hit/Target" then
            local indexState=env.__ClaudeHubMM2SilentFullIndex_v4
            if not indexState or not indexState.Installed then
                indexState={};local state=indexState;local oldIndex;local mouse=Mouse
                local function intercept(self,index)
                    if state.Resolve and not state.Busy and self==mouse and not isCaller() then
                        local caller=captureCaller()
                        state.Busy=true
                        local ok,handled,value=pcall(state.Resolve,index,caller)
                        state.Busy=false
                        if ok and handled then return value end
                        if not ok and state.RecordError then state.RecordError(handled) end
                    end
                    return oldIndex(self,index)
                end
                local ok,previous=pcall(function() return hookmetamethod(game,"__index",wrap(intercept)) end)
                if not ok or type(previous)~="function" then
                    rayState.Resolve=nil;rayState.RecordError=nil;rayState.Owner=nil
                    return false,"Mouse index hook: "..tostring(previous)
                end
                oldIndex=previous;indexState.Installed=true;env.__ClaudeHubMM2SilentFullIndex_v4=indexState
            end
            self.OwnedStates.Index=indexState
            indexState.Owner=self;indexState.Resolve=indexResolver;indexState.RecordError=recordError
        end
        self.Settings.Enabled=true
        return true
    end
    local drawingCircle,drawingTarget,visualGui,nativeCircle,nativeTarget,circleStroke
    local function destroyVisuals()
        for _,object in pairs({drawingCircle,drawingTarget}) do pcall(function() object:Remove() end) end
        drawingCircle,drawingTarget=nil,nil
        if visualGui then visualGui:Destroy();visualGui=nil end
    end
    function engine:CreateVisuals()
        if type(Drawing)=="table" and type(Drawing.new)=="function" then
            local ok=pcall(function()
                drawingCircle=Drawing.new("Circle");drawingCircle.Thickness=1;drawingCircle.NumSides=100
                drawingCircle.Filled=false;drawingCircle.Transparency=1;drawingCircle.ZIndex=999
                drawingCircle.Visible=false
                drawingTarget=Drawing.new("Square");drawingTarget.Thickness=20;drawingTarget.Size=Vector2.new(20,20)
                drawingTarget.Filled=true;drawingTarget.ZIndex=999;drawingTarget.Visible=false
            end)
            if ok then return end
            destroyVisuals()
        end
        visualGui=Instance.new("ScreenGui");visualGui.Name="ClaudeHubMM2_SilentVisuals"
        visualGui.IgnoreGuiInset=true;visualGui.ResetOnSpawn=false;visualGui.DisplayOrder=20
        visualGui.Parent=player:WaitForChild("PlayerGui")
        nativeCircle=Instance.new("Frame",visualGui);nativeCircle.AnchorPoint=Vector2.new(0.5,0.5)
        nativeCircle.BackgroundTransparency=1;nativeCircle.BorderSizePixel=0;nativeCircle.Visible=false
        local corner=Instance.new("UICorner",nativeCircle);corner.CornerRadius=UDim.new(1,0)
        circleStroke=Instance.new("UIStroke",nativeCircle);circleStroke.Thickness=1
        nativeTarget=Instance.new("Frame",visualGui);nativeTarget.Size=UDim2.fromOffset(20,20)
        nativeTarget.BorderSizePixel=0;nativeTarget.Visible=false
    end
    function engine:UpdateVisuals()
        local show=active()
        local mouse=getMousePosition()
        local circleVisible=not self.Destroyed and not closed and ready and focused and self.Settings.FOVVisible
        if drawingCircle then
            drawingCircle.Visible=circleVisible;drawingCircle.Position=mouse
            drawingCircle.Radius=self.Settings.FOVRadius;drawingCircle.Color=self.Color
            drawingTarget.Visible=false;drawingTarget.Color=self.TargetColor
        elseif nativeCircle then
            nativeCircle.Visible=circleVisible;nativeCircle.Position=UDim2.fromOffset(mouse.X,mouse.Y)
            nativeCircle.Size=UDim2.fromOffset(self.Settings.FOVRadius*2,self.Settings.FOVRadius*2)
            circleStroke.Color=self.Color;nativeTarget.Visible=false;nativeTarget.BackgroundColor3=self.TargetColor
        end
        if not show or not self.Settings.ShowSilentAimTarget then return end
        local part=getClosestPlayer()
        local camera=workspace.CurrentCamera
        if not part or not camera then return end
        local root=part.Parent:FindFirstChild("HumanoidRootPart") or part
        local projected,onScreen=camera:WorldToScreenPoint(root.Position)
        if not onScreen then return end
        if drawingTarget then drawingTarget.Position=Vector2.new(projected.X,projected.Y);drawingTarget.Visible=true
        elseif nativeTarget then nativeTarget.Position=UDim2.fromOffset(projected.X,projected.Y);nativeTarget.Visible=true end
    end
    local configFolder="ClaudeHub/MM2/UniversalSilentAim/"..tostring(game.PlaceId)
    local legacyFolder="UniversalSilentAim/"..tostring(game.PlaceId)
    local function ensureFolder(path)
        if type(isfolder)~="function" or type(makefolder)~="function" then error("File-system functions unavailable",0) end
        local current=""
        for segment in path:gmatch("[^/]+") do
            current=current=="" and segment or current.."/"..segment
            if not isfolder(current) then makefolder(current) end
        end
    end
    function engine:ListConfigs()
        if type(listfiles)~="function" or type(isfolder)~="function" then return {},"File-system functions unavailable" end
        local paths,labels={},{}
        local ok,err=pcall(function()
            for _,folder in ipairs({configFolder,legacyFolder}) do
                if not isfolder(folder) then continue end
                for _,path in ipairs(listfiles(folder)) do
                    if path:sub(-4):lower()~=".lua" then continue end
                    local filename=path:match("([^/\\]+)%.lua$")
                    if filename then
                        local label=filename..(folder==legacyFolder and " [original]" or "")
                        paths[label]=path;table.insert(labels,label)
                    end
                end
            end
        end)
        if not ok then return {},tostring(err) end
        table.sort(labels);self.ConfigPaths=paths
        return labels
    end
    function engine:SaveConfig(name)
        if type(name)~="string" or #name<1 or #name>60 or not name:match("^[%w _%-]+$") then
            return false,"Name: 1-60 letters, digits, spaces, _ or -"
        end
        local ok,err=pcall(function()
            if type(writefile)~="function" then error("writefile unavailable",0) end
            ensureFolder(configFolder)
            local data=table.clone(self.Settings)
            data.Color={self.Color.R,self.Color.G,self.Color.B}
            data.TargetColor={self.TargetColor.R,self.TargetColor.G,self.TargetColor.B}
            writefile(configFolder.."/"..name..".lua",HttpService:JSONEncode(data))
        end)
        return ok,err
    end
    function engine:ReadConfig(label)
        local path=self.ConfigPaths[label]
        if not path then return nil,"Select a configuration" end
        local ok,data=pcall(function()
            if type(readfile)~="function" then error("readfile unavailable",0) end
            return HttpService:JSONDecode(readfile(path))
        end)
        if not ok or type(data)~="table" then return nil,tostring(data) end
        return data
    end
    engine.Methods=methods
    function engine:Destroy()
        self:Stop();self.Destroyed=true;destroyVisuals()
    end
    return engine
end)()
local silentStatus
local function stopSilent() SilentEngine:Stop() end

local function clearAntiFling() restore(pools.AntiFling) end
local function updateAntiFling()
    if not ready or not on("AntiFling") then
        if next(pools.AntiFling) then clearAntiFling() end
        return
    end
    local accepted={}
    for _,other in ipairs(Players:GetPlayers()) do
        if other==player or not other.Character then continue end
        for _,part in ipairs(other.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                accepted[part]=true
                override(pools.AntiFling,part,"CanCollide",false)
            end
        end
    end
    local stale={}
    for object,fields in pairs(pools.AntiFling) do
        if not accepted[object] then stale[object]=fields;pools.AntiFling[object]=nil end
    end
    restore(stale)
end
local grabState
local function finishGrab()
    local state=grabState
    if not state then return end
    grabState=nil
    if state.TouchStarted and type(firetouchinterest)=="function" then
        pcall(function() firetouchinterest(state.Root,state.Part,1) end)
    end
    pcall(function()
        if not state.Object:IsDescendantOf(workspace) or gunInInventory(state.Object) then return end
        if state.IsModel then
            if (state.Object:GetPivot().Position-state.Applied.Position).Magnitude<0.1 then state.Object:PivotTo(state.Original) end
        elseif (state.Part.Position-state.Applied.Position).Magnitude<0.1 then
            state.Part.CFrame=state.Original
        end
    end)
end
local function gunHitbox(object)
    if object:IsA("BasePart") then return object end
    for _,descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("TouchTransmitter") and descendant.Parent and descendant.Parent:IsA("BasePart") then return descendant.Parent end
    end
    local handle=object:FindFirstChild("Handle",true)
    if handle and handle:IsA("BasePart") then return handle end
    return object:FindFirstChildWhichIsA("BasePart",true)
end
local function grabGun()
    if grabState then notify("Grab Gun: wait for the current attempt");return end
    local _,_,root=character(player)
    if not root then notify("Grab Gun: character unavailable");return end
    local selected,part,best
    for _,object in ipairs(workspace:GetDescendants()) do
        if object.Name:lower()~="gundrop" or not (object:IsA("Model") or object:IsA("BasePart")) or gunInInventory(object) then continue end
        local hitbox=gunHitbox(object)
        if hitbox then
            local distance=(hitbox.Position-root.Position).Magnitude
            if not best or distance<best then selected,part,best=object,hitbox,distance end
        end
    end
    if not selected then notify("Grab Gun: no streamed GunDrop found");return end
    local state={Object=selected,Part=part,Root=root,IsModel=selected:IsA("Model")}
    state.Original=state.IsModel and selected:GetPivot() or part.CFrame
    state.Applied=state.IsModel and (root.CFrame*part.CFrame:Inverse()*state.Original) or root.CFrame
    grabState=state
    local ok,err=pcall(function()
        if state.IsModel then selected:PivotTo(state.Applied) else part.CFrame=state.Applied end
        if type(firetouchinterest)=="function" then
            state.TouchStarted=true
            firetouchinterest(root,part,0)
        end
    end)
    if not ok then finishGrab();notify("Grab Gun: "..tostring(err));return end
    task.delay(0.4,function()
        if grabState~=state then return end
        finishGrab()
        if not closed then
            local _,hasGun=toolsIn(player.Character)
            local _,storedGun=toolsIn(player:FindFirstChildOfClass("Backpack"))
            notify((hasGun or storedGun) and "Gun observed in inventory" or "Grab attempted; server pickup not confirmed")
        end
    end)
end

local function jumpNow()
    if not ready or not on("InfiniteJump") or on("Freecam") or on("Spectate") or on("SelfRagdoll") or on("Fly") or menuBusy() or os.clock()-lastJump < 0.12 then return end
    local _,h,r = character(player)
    if not h or r.Anchored or h.Sit then return end
    lastJump = os.clock()
    h:ChangeState(Enum.HumanoidStateType.Jumping)
    local velocity = r.AssemblyLinearVelocity
    r.AssemblyLinearVelocity = Vector3.new(velocity.X, val("JumpVelocity",50), velocity.Z)
end
-- Movement mechanics adapted from the user's universal ClaudeHub.
local Movement=(function()
    local m={Root=nil,Humanoid=nil,Safe=nil,Points={},PointMap={},Generation=0,PathBusy=false,
        PathAt=-math.huge,Nodes=nil,Node=1,FollowPoint=nil,LastWallhop=-math.huge}
    local owned={Jump={},Gravity={},Ragdoll={},Wallhop={}}
    local joints={}
    local pad,padConnection,lastLaunch
    local pendingHop
    local function held(id,fallback)
        local key=val(id,fallback)
        if type(key)~="string" or key=="None" then return false end
        local ok,value=pcall(function() return UIS:IsKeyDown(Enum.KeyCode[key]) end)
        return ok and value
    end
    function m:EndWallhop()
        if pendingHop then
            local state=pendingHop;pendingHop=nil
            pcall(function()
                if state.Root.Parent and state.Root.CFrame.LookVector:Dot(state.Applied.LookVector)>0.98 then
                    state.Root.CFrame=CFrame.new(state.Root.Position)*state.Rotation
                end
            end)
        end
        restore(owned.Wallhop)
    end
    function m:ClearRagdoll()
        for _,joint in ipairs(joints) do
            joint.Socket:Destroy();joint.A0:Destroy();joint.A1:Destroy()
        end
        table.clear(joints);restore(owned.Ragdoll)
    end
    function m:Ragdoll(c,h)
        if #joints>0 then return end
        -- Neck remains connected; disabling it can kill RequiresNeck avatars.
        for _,motor in ipairs(c:GetDescendants()) do
            if motor:IsA("Motor6D") and motor.Name~="Neck" and motor.Enabled and motor.Part0 and motor.Part1 then
                local a0=Instance.new("Attachment",motor.Part0);a0.CFrame=motor.C0
                local a1=Instance.new("Attachment",motor.Part1);a1.CFrame=motor.C1
                local socket=Instance.new("BallSocketConstraint",motor.Part0)
                socket.Attachment0=a0;socket.Attachment1=a1
                socket.LimitsEnabled=true;socket.TwistLimitsEnabled=true
                table.insert(joints,{Socket=socket,A0=a0,A1=a1})
                override(owned.Ragdoll,motor,"Enabled",false)
            end
        end
        override(owned.Ragdoll,h,"PlatformStand",true)
    end
    function m:StopFollow()
        self.Generation+=1;self.Nodes=nil;self.FollowPoint=nil;self.PathAt=-math.huge
        if self.FollowHumanoid and self.FollowHumanoid.Parent then
            local root=self.FollowHumanoid.Parent:FindFirstChild("HumanoidRootPart")
            if root then pcall(function() self.FollowHumanoid:MoveTo(root.Position) end) end
        end
        self.FollowHumanoid=nil
    end
    function m:Reset()
        self:EndWallhop();self:ClearRagdoll();self:StopFollow()
        self.Safe=nil;self.Root=nil;self.Humanoid=nil
        restore(owned.Jump)
    end
    function m:RemovePad()
        if padConnection then padConnection:Disconnect();padConnection=nil end
        if pad then pad:Destroy();pad=nil end
    end
    function m:Destroy()
        self:Reset();self:RemovePad()
        for _,pool in pairs(owned) do restore(pool) end
        table.clear(self.Points);table.clear(self.PointMap)
    end
    function m:Wallhop()
        if not ready or not on("FakeWallhop") or menuBusy() or cameraState or on("Fly") or on("SelfRagdoll") then return false end
        local c,h,r=character(player)
        if not r or r.Anchored or h.Sit or h.FloorMaterial~=Enum.Material.Air then return false end
        if os.clock()-self.LastWallhop<0.18 then return true end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        local ignore={c}
        if markerFolder then table.insert(ignore,markerFolder) end
        for _,other in ipairs(Players:GetPlayers()) do
            if other~=player and other.Character then table.insert(ignore,other.Character) end
        end
        params.FilterDescendantsInstances=ignore;params.IgnoreWater=true
        local wall=false
        for index=0,7 do
            local angle=index*math.pi/4
            local hit=workspace:Raycast(r.Position,Vector3.new(math.cos(angle),0,math.sin(angle))*val("WallhopReach",3.2),params)
            if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
                and hit.Normal and math.abs(hit.Normal.Y)<0.35 and not Players:GetPlayerFromCharacter(hit.Instance:FindFirstAncestorOfClass("Model")) then wall=true;break end
        end
        if not wall then return false end
        self:EndWallhop();self.LastWallhop=os.clock();lastJump=os.clock()
        local rotation=r.CFrame.Rotation
        local sign=val("WallhopSide","Left")=="Right" and -1 or 1
        local applied=rotation*CFrame.Angles(0,sign*math.rad(80),0)
        pendingHop={Root=r,Rotation=rotation,Applied=applied,Until=os.clock()+0.075}
        override(owned.Wallhop,h,"AutoRotate",false)
        r.CFrame=CFrame.new(r.Position)*applied
        local velocity=r.AssemblyLinearVelocity
        h:ChangeState(Enum.HumanoidStateType.Jumping)
        r.AssemblyLinearVelocity=Vector3.new(velocity.X,val("JumpVelocity",50),velocity.Z)
        return true
    end
    function m:Launch()
        if not focused or UIS:GetFocusedTextBox() or cameraState or on("Fly") or on("SelfRagdoll") then return end
        local _,h,r=character(player)
        if r and not r.Anchored and not h.Sit then
            local power=val("SelfFlingPower",120)
            h:ChangeState(Enum.HumanoidStateType.Freefall)
            r.AssemblyLinearVelocity=Vector3.new((math.random()-0.5)*power,power,(math.random()-0.5)*power)
        end
    end
    function m:PlacePad()
        local _,_,r=character(player);if not r then return end
        self:RemovePad()
        pad=Instance.new("Part");pad.Name="ClaudeHubMM2_SelfLaunchPad"
        pad.Anchored=true;pad.CanCollide=true;pad.Size=Vector3.new(6,1,6)
        pad.Material=Enum.Material.Neon;pad.Color=Color3.fromRGB(150,100,255)
        pad.CFrame=CFrame.new(r.Position-Vector3.new(0,3,0));pad.Parent=workspace
        lastLaunch=-math.huge
        padConnection=pad.Touched:Connect(function(hit)
            if not ready or not on("PadEnabled") or cameraState or menuBusy() or on("Fly") or on("SelfRagdoll") then return end
            local c,h,root=character(player)
            if not c or not hit:IsDescendantOf(c) or root.Anchored or h.Sit or os.clock()-lastLaunch<0.5 then return end
            lastLaunch=os.clock();local velocity=root.AssemblyLinearVelocity
            h:ChangeState(Enum.HumanoidStateType.Freefall)
            root.AssemblyLinearVelocity=Vector3.new(velocity.X,val("PadPower",150),velocity.Z)
        end)
    end
    function m:Follow(c,h,r)
        local target
        for _,p in ipairs(Players:GetPlayers()) do if tostring(p.UserId)==self.PointMap[val("FollowPlayer","")] then target=p;break end end
        local other
        if target then local _,_,root=character(target);other=root end
        if not other or target==player or menuBusy() or cameraState or on("Fly") or on("SelfRagdoll") then
            if self.FollowHumanoid then self:StopFollow() end
            return
        end
        self.FollowHumanoid=h
        local delta=other.Position-r.Position
        if delta.Magnitude<=val("FollowDistance",5) then
            self.FollowPoint=nil;self.Nodes=nil;h:MoveTo(r.Position);return
        end
        if delta.Magnitude>250 then self:StopFollow();return end
        if not self.PathBusy and os.clock()-self.PathAt>=1 then
            self.PathBusy=true;self.PathAt=os.clock()
            local generation=self.Generation;local origin=r.Position;local goal=other.Position
            task.spawn(function()
                local ok,nodes=pcall(function()
                    local path=game:GetService("PathfindingService"):CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true})
                    path:ComputeAsync(origin,goal)
                    if path.Status==Enum.PathStatus.Success then return path:GetWaypoints() end
                end)
                self.PathBusy=false
                if closed or not ready or generation~=self.Generation or self.Root~=r then return end
                self.Nodes=ok and nodes or nil;self.Node=2
            end)
        end
        local node=self.Nodes and self.Nodes[self.Node]
        while node and (node.Position-r.Position).Magnitude<3 do self.Node+=1;node=self.Nodes[self.Node] end
        self.FollowPoint=node and node.Position or other.Position
        if node and node.Action==Enum.PathWaypointAction.Jump then h.Jump=true end
        h:MoveTo(self.FollowPoint)
    end
    function m:Update()
        if not ready then return end
        local c,h,r=character(player)
        if r~=self.Root then self:Reset();self.Root=r;self.Humanoid=h end
        if on("CustomGravity") then override(owned.Gravity,workspace,"Gravity",val("GravityValue",196.2))
        elseif next(owned.Gravity) then restore(owned.Gravity) end
        if pendingHop and (os.clock()>=pendingHop.Until or not on("FakeWallhop") or on("Fly") or cameraState) then self:EndWallhop() end
        if not r then restore(pools.Speed);return end
        local blocked=menuBusy() or cameraState or on("Fly") or r.Anchored or h.Sit
        if on("SelfRagdoll") and not blocked then self:Ragdoll(c,h)
        elseif next(owned.Ragdoll) then self:ClearRagdoll() end
        if on("JumpPower") and not blocked and not on("SelfRagdoll") then
            override(owned.Jump,h,"UseJumpPower",true);override(owned.Jump,h,"JumpPower",val("JumpPowerValue",80))
        elseif next(owned.Jump) then restore(owned.Jump) end
        for object in pairs(pools.Speed) do if object~=h then restore(pools.Speed);break end end
        local sprint=on("Sprint") and held("SprintKey","LeftShift") and h.MoveDirection.Magnitude>0.05
        if not blocked and not on("SelfRagdoll") and (on("Speed") or sprint) then
            local baseline=pools.Speed[h] and pools.Speed[h].WalkSpeed.Base or h.WalkSpeed
            local speed=on("Speed") and val("WalkSpeed",20) or baseline
            if sprint then speed=math.max(speed,val("SprintSpeed",28)) end
            override(pools.Speed,h,"WalkSpeed",speed)
        elseif next(pools.Speed) then restore(pools.Speed) end
        if on("AutoFollow") and not blocked and not on("SelfRagdoll") then self:Follow(c,h,r)
        elseif self.FollowHumanoid then self:StopFollow() end
        if on("NoAcceleration") and not blocked and not on("SelfRagdoll") then
            local direction=h.MoveDirection
            if self.FollowPoint then
                local delta=self.FollowPoint-r.Position;direction=Vector3.new(delta.X,0,delta.Z)
                if direction.Magnitude>0.05 then direction=direction.Unit end
            end
            local velocity=r.AssemblyLinearVelocity;local move=direction*h.WalkSpeed
            r.AssemblyLinearVelocity=Vector3.new(move.X,velocity.Y,move.Z)
        end
        local round=inRound(player)
        if self.Round~=round then self.Safe=nil;self.Round=round end
        local threshold=val("AntiVoidHeight",-50)
        if on("AntiVoid") and not blocked and not on("SelfRagdoll") then
            if r.Position.Y>threshold+5 and h.FloorMaterial~=Enum.Material.Air then self.Safe=r.CFrame end
            if self.Safe and r.Position.Y<=threshold then
                r.CFrame=self.Safe;r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
                h:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        else self.Safe=nil end
    end
    function m:Build(tab,toggle,slider,action)
        local movement=tab:AddLeftGroupbox("Jump / Sprint","footprints")
        toggle(movement,"JumpPower","Jump Power")
        slider(movement,"JumpPowerValue","Power",80,20,300)
        local sprint=toggle(movement,"Sprint","Sprint")
        sprint:AddKeyPicker("SprintKey",{Default="LeftShift",Mode="Hold",NoUI=true,Text="Sprint",SyncToggleState=false})
        slider(movement,"SprintSpeed","Sprint speed",28,16,120)
        toggle(movement,"NoAcceleration","No Acceleration")
        local wall=tab:AddLeftGroupbox("Fake Wallhop","arrow-up")
        toggle(wall,"FakeWallhop","Fake Wallhop")
        wall:AddDropdown("WallhopSide",{Text="Turn direction",Values={"Left","Right"},Default=1})
        slider(wall,"WallhopReach","Wall distance",3.2,1,5,1)
        local gravity=tab:AddLeftGroupbox("Gravity / Anti Void","arrow-down")
        toggle(gravity,"CustomGravity","Gravity")
        slider(gravity,"GravityValue","Gravity",workspace.Gravity,0,400)
        toggle(gravity,"AntiVoid","Anti Void")
        slider(gravity,"AntiVoidHeight","Void Y",-50,-500,0)
        local tp=tab:AddRightGroupbox("Click Teleport / Waypoints","map-pin")
        local click=toggle(tp,"ClickTP","Click TP")
        click:AddKeyPicker("ClickTPModifier",{Default="LeftControl",Mode="Hold",NoUI=true,Text="Click TP modifier",SyncToggleState=false})
        tp:AddInput("WaypointName",{Text="Waypoint name",Default="",Finished=true})
        tp:AddDropdown("WaypointList",{Text="Saved positions",Values={},AllowNull=true})
        local function refresh()
            local names={};for name in pairs(self.Points) do table.insert(names,name) end;table.sort(names)
            Options.WaypointList:SetValues(names)
            if not self.Points[val("WaypointList","")] then Options.WaypointList:SetValue(nil) end
        end
        action(tp,"Save position",function()
            local _,_,root=character(player);local name=val("WaypointName",""):match("^%s*(.-)%s*$")
            if not root or name=="" or #name>40 then notify("Enter a waypoint name (1-40 characters)");return end
            self.Points[name]=root.CFrame;refresh();Options.WaypointList:SetValue(name)
        end)
        action(tp,"Teleport to position",function()
            local _,_,root=character(player);local cf=self.Points[val("WaypointList","")]
            if root and cf and not cameraState and not on("Fly") then self:StopFollow();root.CFrame=cf;root.AssemblyLinearVelocity=Vector3.zero end
        end)
        action(tp,"Delete position",function() self.Points[val("WaypointList","")]=nil;refresh() end)
        local follow=tab:AddRightGroupbox("Auto Follow","navigation")
        follow:AddDropdown("FollowPlayer",{Text="Player",Values={},AllowNull=true})
        toggle(follow,"AutoFollow","Auto Follow")
        slider(follow,"FollowDistance","Follow distance",5,3,30)
        function self:RefreshPlayers()
            local names={};table.clear(self.PointMap)
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=player then local label=p.DisplayName.." (@"..p.Name..")";self.PointMap[label]=tostring(p.UserId);table.insert(names,label) end
            end
            table.sort(names);Options.FollowPlayer:SetValues(names)
            if not self.PointMap[val("FollowPlayer","")] then Options.FollowPlayer:SetValue(nil);self:StopFollow() end
        end
        self:RefreshPlayers()
        connect(Players.PlayerAdded,function() if ready then self:RefreshPlayers() end end)
        connect(Players.PlayerRemoving,function() task.defer(function() if ready and not closed then self:RefreshPlayers() end end) end)
        Options.FollowPlayer:OnChanged(function() self:StopFollow() end)
        Toggles.AutoFollow:OnChanged(function() self:StopFollow() end)
        local selfBox=tab:AddRightGroupbox("Self movement","zap")
        toggle(selfBox,"SelfRagdoll","Self Ragdoll")
        slider(selfBox,"SelfFlingPower","Self Fling power",120,20,500)
        action(selfBox,"Self Fling",function() self:Launch() end)
        toggle(selfBox,"PadEnabled","Launch Pad enabled")
        slider(selfBox,"PadPower","Launch power",150,20,500)
        action(selfBox,"Place Launch Pad",function() self:PlacePad() end)
        action(selfBox,"Remove Launch Pad",function() self:RemovePad() end)
        Toggles.SelfRagdoll:OnChanged(function()
            if not ready then return end
            if on("SelfRagdoll") and on("Fly") then Toggles.Fly:SetValue(false) end
            self:ClearRagdoll();self:EndWallhop()
        end)
        Toggles.FakeWallhop:OnChanged(function() if not on("FakeWallhop") then self:EndWallhop() end end)
        Toggles.JumpPower:OnChanged(function() restore(owned.Jump) end)
        Toggles.CustomGravity:OnChanged(function() if not on("CustomGravity") then restore(owned.Gravity) end end)
        connect(UIS.InputBegan,function(input,processed)
            if processed or not ready or menuBusy() or cameraState or on("Fly") or on("SelfRagdoll") then return end
            if on("ClickTP") and input.UserInputType==Enum.UserInputType.MouseButton1 and held("ClickTPModifier","LeftControl") then
                local _,_,root=character(player);local mouse=player:GetMouse()
                if root and mouse.Target and mouse.Hit then
                    self:StopFollow();root.CFrame=CFrame.new(mouse.Hit.Position+Vector3.new(0,3,0));root.AssemblyLinearVelocity=Vector3.zero
                end
            end
        end)
    end
    return m
end)()

local function cleanup()
    if closed then return end
    closed, ready = true, false
    SilentEngine:Destroy();Movement:Destroy();finishGrab();clearAntiFling();stopFly();clearRoles(nil)
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    RunService:UnbindFromRenderStep("ClaudeHubMM2_Camera")
    releaseCamera()
    resetCombat()
    serverGeneration += 1
    for _, pool in pairs(pools) do restore(pool) end
    clearMarkers()
    clearGuns()
    if aimGui then aimGui:Destroy() end
    if hud then hud:Destroy() end
    if markerFolder then markerFolder:Destroy() end
    if env[KEY] == Library then env[KEY] = nil end
    if env.Library == Library then env.Library = nil end
end
Library:OnUnload(cleanup)
local success, failure = xpcall(function()
    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = false
    local Window = Library:CreateWindow({Title="ClaudeHub | MM2", Footer="MM2 v" .. VERSION .. " | Obsidian",
        Center=true, AutoShow=true, Resizable=true, NotifySide="Right", ShowCustomCursor=true})
    local Tabs = {
        Home=Window:AddTab("Home", "house"),
        Character=Window:AddTab("Character", "user"),
        Movement=Window:AddTab("Movement", "footprints"),
        Visuals=Window:AddTab("Visuals", "eye"),
        Camera=Window:AddTab("Camera", "camera"),
        Combat=Window:AddTab("Combat", "crosshair"),
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
    home:AddLabel("Murder Mystery 2")
    home:AddLabel("ClaudeHub v" .. VERSION)
    local mapLabel=home:AddLabel("Map: not exposed")
    local roundLabel=home:AddLabel("Round: not exposed")
    local myRoleLabel=home:AddLabel("Role: Lobby / unconfirmed")
    local serverLabel = home:AddLabel("Players: --")
    local info = Tabs.Home:AddRightGroupbox("Release", "info")
    info:AddLabel("Ordinary Obsidian")
    info:AddLabel("Character / Visuals / Camera / Combat / Servers")
    info:AddLabel("Gameplay features start disabled")
    info:AddLabel("No anticheat bypass")
    info:AddLabel("UI: deividcomsono (MIT)")
    info:AddLabel("Silent Aim: Averiias / Stefanuk12 / xaxa")
    local char = Tabs.Movement:AddLeftGroupbox("Movement", "footprints")
    toggle(char, "Speed", "WalkSpeed", "V")
    slider(char, "WalkSpeed", "Speed", 20, 0, 120)
    toggle(char, "InfiniteJump", "Infinite Jump", "J")
    slider(char, "JumpVelocity", "Jump Strength", 50, 20, 100)
    toggle(char,"Fly","Fly","F")
    slider(char,"FlySpeed","Fly Speed",45,5,150)
    toggle(char,"Noclip","Noclip","N")
    local protection=Tabs.Character:AddLeftGroupbox("Protection","shield")
    toggle(protection,"AntiFling","Anti Fling","P")
    local pickup=Tabs.Combat:AddRightGroupbox("Grab Gun","hand")
    action(pickup,"Grab Gun",grabGun,"K","GrabGunBind")
    local pickupStatus=pickup:AddLabel("Gun: not found")
    local alerts=Tabs.Combat:AddRightGroupbox("Notifications","bell")
    toggle(alerts,"GunNotification","Dropped gun notification")
    toggle(alerts,"MurderWarning","Nearby murderer warning")
    slider(alerts,"MurderWarningRange","Warning distance",40,10,150)
    Movement:Build(Tabs.Movement,toggle,slider,action)
    local hudBox = Tabs.Character:AddRightGroupbox("HUD", "monitor")
    toggle(hudBox, "HUD", "MM2 HUD", "F9")
    local visuals = Tabs.Visuals:AddLeftGroupbox("Players", "users")
    toggle(visuals, "ESP", "Player ESP", "H")
    toggle(visuals, "ESPNames", "Names")
    toggle(visuals, "ESPHealth", "Health")
    toggle(visuals, "ESPDistance", "Distance")
    toggle(visuals,"ESPRoles","Role labels")
    toggle(visuals,"ESPRoleColors","Role colors")
    visuals:AddDropdown("RoundDetection",{Text="Round detection",Values={"Auto","Lobby (force gray)","In round (manual)"},Default=1})
    toggle(visuals,"GunESP","Dropped Gun ESP","G")
    for _,id in ipairs({"ESPNames","ESPDistance","ESPRoles","ESPRoleColors"}) do Toggles[id]:SetValue(true) end
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
    toggle(cam, "AntiShake", "Soft Camera")
    slider(cam, "Stabilize", "Stabilization", 70, 10, 95)
    toggle(cam, "Freecam", "Freecam", "F6")
    slider(cam, "FreecamSpeed", "Freecam Speed", 32, 5, 150)
    action(cam,"Restore Character Camera",function()
        Toggles.Freecam:SetValue(false);Toggles.Spectate:SetValue(false)
        releaseCamera();releaseMouse();smoothCamera=nil
        local camera=workspace.CurrentCamera
        local _,h=character(player)
        if camera and h then
            camera.CameraType=Enum.CameraType.Custom;camera.CameraSubject=h
            UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true
        end
    end)
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
        local selected = Options.SpectatePlayer.Value
        Options.SpectatePlayer:SetValues(names)
        if selected and not playerNames[selected] then
            Options.SpectatePlayer:SetValue(nil)
            if on("Spectate") then Toggles.Spectate:SetValue(false) end
        end
    end
    action(watch, "Refresh Players", refreshPlayers)
    local targetBox = Tabs.Combat:AddLeftGroupbox("Aim Assist", "crosshair")
    toggle(targetBox,"AimAssist","Soft Aim Assist","X")
    targetBox:AddDropdown("AimActivation",{Text="Hold to assist",Values={"RMB or L2","RMB only","L2 only"},Default=1})
    targetBox:AddDropdown("AimPoint",{Text="Aim point",Values={"UpperTorso","Head","HumanoidRootPart"},Default=1})
    targetBox:AddDropdown("AimRole",{Text="Target filter",Values={"Any visible player","Murderer","Sheriff / Hero"},Default=1})
    slider(targetBox,"AimRadius","Assist radius (pixels)",110,25,300)
    slider(targetBox,"AimSmoothing","Tracking strength",55,10,120)
    toggle(targetBox,"AimHardLock","Hard Lock")
    slider(targetBox,"AimRange","Max distance (studs)",180,20,500)
    slider(targetBox,"AimPrediction","Movement prediction",0,0,0.2,2)
    toggle(targetBox,"AimRequireWeapon","Require equipped weapon")
    toggle(targetBox,"AimCircle","Show assist circle")
    toggle(targetBox,"TargetHighlight","Highlight aim target")
    Toggles.AimCircle:SetValue(true)
    targetStatus=targetBox:AddLabel("Assist: off")
    toggle(targetBox,"AimSticky","Sticky target")
    local aimInfo=Tabs.Combat:AddRightGroupbox("Soft Aim information","info")
    aimInfo:AddLabel("Hold RMB or L2; release to stop assistance.")
    aimInfo:AddLabel("Visibility check is always enabled.")
    aimInfo:AddLabel("Camera smoothing only; no bullet/damage changes.")
    aimInfo:AddLabel("Device type is not spoofed.")
    aimInfo:AddLabel("Role filters use role data or observed weapons during a round.")
    local evidence=Tabs.Home:AddRightGroupbox("Client information","info")
    evidence:AddLabel("Lobby/unconfirmed: gray. Innocent role: green.")
    evidence:AddLabel("Murderer: red. Sheriff: blue. Hero: gold.")
    evidence:AddLabel("Auto: round events/flags. Manual fallback in Visuals.")
    evidence:AddLabel("No role data: unknown stays gray.")
    local silentBox=Tabs.Combat:AddRightGroupbox("Silent Aim","scan-eye")
    toggle(silentBox,"SilentAim","Silent Aim","B")
    silentBox:AddDropdown("SilentRole",{Text="Target role",Values={"All players (original)","Auto","Murderer","Sheriff / Hero"},Default=1})
    toggle(silentBox,"SilentSticky","Sticky target")
    toggle(silentBox,"SilentTeamCheck","Team Check")
    toggle(silentBox,"SilentVisibleCheck","Visible Check")
    Toggles.SilentVisibleCheck:SetValue(true)
    silentBox:AddDropdown("SilentPoint",{Text="Target Part",Values={"Head","HumanoidRootPart","Random"},Default=2})
    silentBox:AddDropdown("SilentMethod",{Text="Silent Aim Method",Values={"MM2 Gun","Raycast","FindPartOnRay","FindPartOnRayWithWhitelist","FindPartOnRayWithIgnoreList","Mouse.Hit/Target"},Default=1})
    slider(silentBox,"SilentHitChance","Hit chance",100,0,100,1)
    silentStatus=silentBox:AddLabel("Silent Aim: off")
    local silentTargetStatus=silentBox:AddLabel("Target: none")
    local silentVisuals=Tabs.Combat:AddRightGroupbox("Silent Aim FOV","scan-eye")
    toggle(silentVisuals,"SilentFOVVisible","Show FOV Circle")
    silentVisuals:AddLabel("Circle Color"):AddColorPicker("SilentFOVColor",{Default=SilentEngine.Color,Title="Silent Aim Circle"})
    slider(silentVisuals,"SilentRadius","FOV Circle Radius",130,0,360)
    toggle(silentVisuals,"SilentShowTarget","Show Silent Aim Target")
    silentVisuals:AddLabel("Target Color"):AddColorPicker("SilentTargetColor",{Default=SilentEngine.TargetColor,Title="Silent Aim Target"})
    local silentPrediction=Tabs.Combat:AddRightGroupbox("Silent Aim Prediction","move-right")
    toggle(silentPrediction,"SilentPredictionEnabled","Mouse.Hit/Target Prediction")
    slider(silentPrediction,"SilentPredictionAmount","Prediction Amount",0.165,0.165,1,3)
    local silentInfo=Tabs.Combat:AddRightGroupbox("Credits / Status","info")
    silentInfo:AddLabel("MM2-scoped Silent Aim")
    silentInfo:AddLabel("Averiias / Stefanuk12 / xaxa")
    silentInfo:AddLabel("MM2 Gun: only equipped Gun CreateBeam calls")
    silentInfo:AddLabel("Legacy modes: weapon-script callers only")
    local silentWeaponStatus=silentInfo:AddLabel("Weapon: Equip Gun")
    local silentLastCall=silentInfo:AddLabel("Last shot call: none")
    local silentCounter=silentInfo:AddLabel("Matching calls: 0 | redirected: 0")
    local silentError=silentInfo:AddLabel("Last error: none")
    local configs=Tabs.Combat:AddRightGroupbox("Configurations","save")
    configs:AddInput("SilentConfigName",{Text="Create Configuration",Default="",Finished=true})
    configs:AddDropdown("SilentConfigChoice",{Text="Saved Configuration",Values={},AllowNull=true})
    local function refreshSilentConfigs()
        local labels,err=SilentEngine:ListConfigs()
        Options.SilentConfigChoice:SetValues(labels)
        if err then notify("Silent Aim configs: "..err) end
    end
    local function saveSilentConfig(name)
        SilentEngine.Settings.ToggleKey=Options.SilentAimBind.Value
        local ok,err=SilentEngine:SaveConfig(name)
        if not ok then notify("Silent Aim config: "..tostring(err));return end
        refreshSilentConfigs();notify("Silent Aim configuration saved")
    end
    action(configs,"Create Configuration",function() saveSilentConfig(val("SilentConfigName","")) end)
    action(configs,"Save Configuration",function()
        local label=val("SilentConfigChoice","")
        if label=="" or label:find(" [original]",1,true) then
            notify("Enter a new name to create a configuration copy");return
        end
        saveSilentConfig(label)
    end)
    action(configs,"Load Configuration",function()
        local data,err=SilentEngine:ReadConfig(val("SilentConfigChoice",""))
        if not data then notify("Silent Aim config: "..tostring(err));return end
        Toggles.SilentAim:SetValue(false)
        for field,id in pairs({TeamCheck="SilentTeamCheck",VisibleCheck="SilentVisibleCheck",FOVVisible="SilentFOVVisible",
            ShowSilentAimTarget="SilentShowTarget",MouseHitPrediction="SilentPredictionEnabled"}) do
            if type(data[field])=="boolean" then Toggles[id]:SetValue(data[field]) end
        end
        if data.TargetPart=="Head" or data.TargetPart=="HumanoidRootPart" or data.TargetPart=="Random" then
            Options.SilentPoint:SetValue(data.TargetPart)
        end
        if type(data.SilentAimMethod)=="string" and SilentEngine.Methods[data.SilentAimMethod] then
            Options.SilentMethod:SetValue(data.SilentAimMethod)
        end
        for field,spec in pairs({FOVRadius={"SilentRadius",0,360},HitChance={"SilentHitChance",0,100},
            MouseHitPredictionAmount={"SilentPredictionAmount",0.165,1}}) do
            local value=data[field]
            if type(value)=="number" and value==value and math.abs(value)<math.huge then
                Options[spec[1]]:SetValue(math.clamp(value,spec[2],spec[3]))
            end
        end
        for field,id in pairs({Color="SilentFOVColor",TargetColor="SilentTargetColor"}) do
            local rgb=data[field]
            if type(rgb)=="table" and type(rgb[1])=="number" and type(rgb[2])=="number" and type(rgb[3])=="number" then
                Options[id]:SetValueRGB(Color3.new(math.clamp(rgb[1],0,1),math.clamp(rgb[2],0,1),math.clamp(rgb[3],0,1)))
            end
        end
        if type(data.ToggleKey)=="string" then
            local key=data.ToggleKey
            local valid=key=="None" or pcall(function() assert(Enum.KeyCode[key]) end)
            if valid then Options.SilentAimBind:SetValue({key,"Toggle"}) end
        end
        if data.Enabled==true then Toggles.SilentAim:SetValue(true) end
        if data.TargetRole=="All players (original)" or data.TargetRole=="Auto" or data.TargetRole=="Murderer" or data.TargetRole=="Sheriff / Hero" then
            Options.SilentRole:SetValue(data.TargetRole)
        end
        notify("Silent Aim configuration loaded")
    end)
    action(configs,"Refresh Configurations",refreshSilentConfigs)
    local function bindSilentToggle(id,field)
        SilentEngine.Settings[field]=on(id)
        Toggles[id]:OnChanged(function() SilentEngine.Settings[field]=on(id) end)
    end
    local function bindSilentOption(id,field)
        SilentEngine.Settings[field]=Options[id].Value
        Options[id]:OnChanged(function() SilentEngine.Settings[field]=Options[id].Value end)
    end
    for id,field in pairs({SilentTeamCheck="TeamCheck",SilentVisibleCheck="VisibleCheck",SilentFOVVisible="FOVVisible",
        SilentShowTarget="ShowSilentAimTarget",SilentPredictionEnabled="MouseHitPrediction"}) do bindSilentToggle(id,field) end
    for id,field in pairs({SilentPoint="TargetPart",SilentMethod="SilentAimMethod",SilentHitChance="HitChance",
        SilentRadius="FOVRadius",SilentRole="TargetRole",SilentPredictionAmount="MouseHitPredictionAmount"}) do bindSilentOption(id,field) end
    Options.SilentFOVColor:OnChanged(function() SilentEngine.Color=Options.SilentFOVColor.Value end)
    Options.SilentTargetColor:OnChanged(function() SilentEngine.TargetColor=Options.SilentTargetColor.Value end)
    Options.SilentAimBind:OnChanged(function() SilentEngine.Settings.ToggleKey=Options.SilentAimBind.Value end)
    Options.SilentRole:OnChanged(function() SilentEngine.Target=nil;SilentEngine.Settings.TargetRole=val("SilentRole","All players (original)") end)
    SilentEngine:CreateVisuals()
    connect(RunService.RenderStepped,function()
        if not ready then return end
        local ok,err=pcall(function() SilentEngine:UpdateVisuals() end)
        if not ok then SilentEngine.LastError=tostring(err):sub(1,220) end
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
    hud.Name, hud.ResetOnSpawn, hud.ZIndexBehavior = "ClaudeHubMM2_HUD", false, Enum.ZIndexBehavior.Sibling
    hud.DisplayOrder = 20
    hud.Parent = player:WaitForChild("PlayerGui")
    aimGui=Instance.new("ScreenGui")
    aimGui.Name="ClaudeHubMM2_AimOverlay";aimGui.ResetOnSpawn=false;aimGui.IgnoreGuiInset=true
    aimGui.DisplayOrder=19;aimGui.Parent=player:WaitForChild("PlayerGui")
    local aimCircle=Instance.new("Frame",aimGui)
    aimCircle.Name="AssistRadius";aimCircle.AnchorPoint=Vector2.new(0.5,0.5)
    aimCircle.Position=UDim2.fromScale(0.5,0.5);aimCircle.BackgroundTransparency=1
    aimCircle.BorderSizePixel=0;aimCircle.Visible=false;aimCircle.Active=false
    local round=Instance.new("UICorner",aimCircle);round.CornerRadius=UDim.new(1,0)
    local aimStroke=Instance.new("UIStroke",aimCircle);aimStroke.Color=Color3.fromRGB(170,130,255)
    aimStroke.Thickness=1.5;aimStroke.Transparency=0.3
    local targetMarker = Instance.new("Highlight", hud)
    targetMarker.Name, targetMarker.Enabled = "CombatTarget", false
    targetMarker.FillColor, targetMarker.OutlineColor = Color3.fromRGB(255,90,100), Color3.fromRGB(255,170,70)
    targetMarker.FillTransparency, targetMarker.DepthMode = 0.8, Enum.HighlightDepthMode.AlwaysOnTop
    local frame = Instance.new("Frame")
    frame.Name, frame.Size, frame.Position = "DraggableHUD", UDim2.fromOffset(370,136), UDim2.fromOffset(24,110)
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
    text.Text, text.Active = "CLAUDEHUB  |  MM2", false
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
        if input.KeyCode==Enum.KeyCode.ButtonL2 then
            aimTrigger=focused and not menuBusy() and input.Position.Z>0.2
        end
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
        if input.KeyCode==Enum.KeyCode.ButtonL2 then aimTrigger=false end
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragInput = nil end
    end)
    connect(UIS.WindowFocusReleased, function() aimTrigger=false;focused = false; dragInput = nil; freeMoving = false; releaseMouse(); resetCombat() end)
    connect(UIS.WindowFocused, function() focused = true end)
    connect(UIS.GamepadDisconnected,function() aimTrigger=false;resetCombat() end)
    markerFolder = Instance.new("Folder", workspace); markerFolder.Name = "ClaudeHubMM2_Markers"
    local function updateMarkers()
        if not on("ESP") then clearMarkers(); return end
        local camera = workspace.CurrentCamera
        if not camera then clearMarkers(); return end
        local accepted, total = {}, 0
        for _, p in ipairs(Players:GetPlayers()) do
            local c, h, r = character(p)
            local distance = r and (r.Position - camera.CFrame.Position).Magnitude or math.huge
            local teammate = false
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
                local _,hint,hintColor=roleHint(p)
                if on("ESPRoleColors") then color=hintColor end
                m.Highlight.FillColor, m.Highlight.OutlineColor = color, color
                m.Highlight.FillTransparency, m.Highlight.OutlineTransparency = val("ESPFill",0.8), 0
                m.Gui.Adornee, m.Gui.MaxDistance = c:FindFirstChild("Head") or r, val("ESPRange",500)
                local parts = {}
                if on("ESPNames") then table.insert(parts, p.DisplayName) end
                if on("ESPRoles") then table.insert(parts,hint) end
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
            if on("Fly") then Toggles.Fly:SetValue(false) end
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
    Toggles.Fly:OnChanged(function()
        if not ready then return end
        if not on("Fly") then stopFly();return end
        Toggles.Freecam:SetValue(false);Toggles.Spectate:SetValue(false)
        local ok,active=pcall(startFly)
        if not ok or not active then
            stopFly();Toggles.Fly:SetValue(false);notify("Fly: character is not ready or constraints unavailable")
        end
    end)
    Toggles.Noclip:OnChanged(function() if ready and not on("Noclip") then restore(pools.Noclip) end end)
    Toggles.SilentAim:OnChanged(function()
        if not ready then return end
        stopSilent()
        if not on("SilentAim") then silentStatus:SetText("Silent Aim: off");return end
        Toggles.AimAssist:SetValue(false);Toggles.AntiShake:SetValue(false)
        resetCombat();smoothCamera=nil
        local ok,reason=SilentEngine:Install()
        if not ok then
            Toggles.SilentAim:SetValue(false);notify("Silent Aim unavailable: "..tostring(reason));return
        end
        silentStatus:SetText("Enabled: "..SilentEngine.Settings.SilentAimMethod)
    end)
    Options.SilentMethod:OnChanged(function()
        SilentEngine.Settings.SilentAimMethod=val("SilentMethod","MM2 Gun")
        if not ready or not on("SilentAim") then return end
        stopSilent()
        local ok,reason=SilentEngine:Install()
        if not ok then Toggles.SilentAim:SetValue(false);notify("Silent Aim unavailable: "..tostring(reason)) end
    end)
    Options.RoundDetection:OnChanged(function() roles={};rolesAt=-math.huge;rolePollAt=-math.huge;rolesGeneration+=1;resetCombat() end)
    for _,object in ipairs(ReplicatedStorage:GetDescendants()) do bindRoundRemote(object) end
    connect(ReplicatedStorage.DescendantAdded,bindRoundRemote)
    connect(RunService.PreSimulation,updateMovement)
    connect(RunService.PreSimulation,updateAntiFling)
    Toggles.AntiFling:OnChanged(function() if ready and not on("AntiFling") then clearAntiFling() end end)
    Toggles.AimAssist:OnChanged(function() resetCombat();targetMarker.Enabled=false;aimCircle.Visible=false end)
    Options.AimRole:OnChanged(resetCombat)
    Toggles.GunESP:OnChanged(function() if ready then updateGuns() end end)
    connect(workspace.DescendantAdded,function(object) if ready then rememberGun(object) end end)
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
                if combatTarget==p then resetCombat() end
                playerNames[name] = nil
            end
        end
        task.defer(function() if ready and not closed then refreshPlayers() end end)
    end)
    connect(player.CharacterRemoving,function()
        resetCombat();Movement:Reset();finishGrab();clearAntiFling();stopFly();restore(pools.Noclip)
        if ready then Toggles.Fly:SetValue(false) end
    end)
    connect(player.CharacterAdded, function()
        if not ready then return end
        Toggles.Freecam:SetValue(false); Toggles.Spectate:SetValue(false)
        Toggles.Fly:SetValue(false);stopFly();restore(pools.Noclip)
        Movement:Reset();Toggles.SelfRagdoll:SetValue(false)
        restore(pools.Speed); resetCombat(); smoothCamera=nil
    end)
    local function requestedJump() if not Movement:Wallhop() then jumpNow() end end
    connect(UIS.JumpRequest,requestedJump)
    connect(UIS.InputBegan,function(input,processed)
        if input.KeyCode==Enum.KeyCode.ButtonL2 and not processed and not menuBusy() then aimTrigger=true end
        if input.KeyCode==Enum.KeyCode.Space and not processed then requestedJump() end
    end)
    local function updateAim(dt,camera)
        local ownCharacter=character(player)
        local subject=camera and camera.CameraSubject
        local ownView=ownCharacter and subject and (subject==ownCharacter or subject:IsDescendantOf(ownCharacter))
        local allowed=on("AimAssist") and camera and camera.CameraType~=Enum.CameraType.Scriptable
            and ownView and not cameraState and not menuBusy() and not on("SilentAim")
        aimCircle.Visible=allowed and on("AimCircle") or false
        local diameter=val("AimRadius",110)*2;aimCircle.Size=UDim2.fromOffset(diameter,diameter)
        if not allowed or not assistHeld() or (on("AimRequireWeapon") and not equippedWeapon()) then
            resetCombat();targetMarker.Enabled=false;return
        end
        local target,point,model=chooseAimTarget(camera)
        combatTarget=target
        targetMarker.Adornee=model;targetMarker.Enabled=model~=nil and on("TargetHighlight")
        if point then
            local desired=CFrame.lookAt(camera.CFrame.Position,point)
            local alpha=on("AimHardLock") and 1 or 1-math.exp(-val("AimSmoothing",55)*math.min(dt,0.1))
            camera.CFrame=camera.CFrame:Lerp(desired,alpha)
        end
    end
    local warningTarget,warningAt=nil,-math.huge
    local function updateAlerts(root)
        local nearestDistance,nearest
        for object,entry in pairs(gunObjects) do
            if not object:IsDescendantOf(workspace) or gunInInventory(object) then continue end
            local part=object:IsA("BasePart") and object or object:FindFirstChildWhichIsA("BasePart",true)
            if not part or not root then continue end
            local distance=(part.Position-root.Position).Magnitude
            if not nearestDistance or distance<nearestDistance then nearestDistance,nearest=distance,object end
            if on("GunNotification") and inRound(player) and not entry.Notified then
                entry.Notified=true;notify(string.format("Dropped gun | %.0f studs",distance))
            end
        end
        pickupStatus:SetText(nearest and string.format("Gun: %.0f studs",nearestDistance) or "Gun: not found")
        if not on("MurderWarning") or not root or not inRound(player) then warningTarget=nil;return end
        local selected,best
        for _,p in ipairs(Players:GetPlayers()) do
            local _,_,otherRoot=character(p)
            if p~=player and otherRoot and roleHint(p)=="Knife" then
                local distance=(otherRoot.Position-root.Position).Magnitude
                if not best or distance<best then selected,best=p,distance end
            end
        end
        local limit=val("MurderWarningRange",40)
        if not selected or best>limit+5 then warningTarget=nil;return end
        if best<=limit and selected~=warningTarget and os.clock()-warningAt>=8 then
            warningAt=os.clock();warningTarget=selected
            notify(string.format("Murderer nearby: %s | %.0f studs",selected.DisplayName,best))
        end
    end
    local accumulator = 0
    connect(RunService.Heartbeat, function(dt)
        if not ready then return end
        local _, h, r = character(player)
        updateAntiFling()
        Movement:Update()
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
        pollRoles();updateMarkers();updateGuns();updateAlerts(r)
        SilentEngine:RefreshTarget()
        silentCounter:SetText(string.format("Matching calls: %d | redirected: %d",SilentEngine.Seen,SilentEngine.Redirected))
        silentWeaponStatus:SetText("Weapon: "..SilentEngine.WeaponStatus)
        silentLastCall:SetText("Last shot call: "..SilentEngine.LastCall)
        silentError:SetText("Last error: "..(SilentEngine.LastError~="" and SilentEngine.LastError or "none"))
        silentStatus:SetText(not on("SilentAim") and "Silent Aim: off" or (menuBusy() or cameraState) and "Silent Aim: paused" or ("Enabled: "..SilentEngine.Settings.SilentAimMethod))
        silentTargetStatus:SetText("Target: "..(SilentEngine.Target and SilentEngine.Target.DisplayName or "none"))
        local map,roundState=roundInfo()
        mapLabel:SetText("Map: "..map);roundLabel:SetText("Round: "..roundState)
        local _,myHint=roleHint(player);myRoleLabel:SetText("Role: "..myHint)
        serverLabel:SetText(string.format("Players: %d / %d",#Players:GetPlayers(),Players.MaxPlayers))
        targetStatus:SetText(not on("AimAssist") and "Assist: off" or (combatTarget and "Target: "..combatTarget.DisplayName or "Assist: hold RMB / L2"))
        if on("HUD") then
            local speed = r and Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude or 0
            local pos = r and r.Position or Vector3.zero
            local activeTarget=on("SilentAim") and SilentEngine.Target or combatTarget
            local name=activeTarget and activeTarget.DisplayName or "none"
            text.Text = string.format("CLAUDEHUB  |  MM2 v%s\nSpeed: %.1f studs/s  |  HP: %.0f\nXYZ: %.0f  %.0f  %.0f\nRole: %s\nTarget: %s",VERSION,speed,h and h.Health or 0,pos.X,pos.Y,pos.Z,myHint,name)
            clampHUD(frame.Position.X.Offset,frame.Position.Y.Offset)
        end
    end)
    RunService:BindToRenderStep("ClaudeHubMM2_Camera", Enum.RenderPriority.Last.Value + 100, function(dt)
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
            local ownCharacter=character(player)
            local subject=camera and camera.CameraSubject
            local ownView=ownCharacter and subject and (subject==ownCharacter or subject:IsDescendantOf(ownCharacter))
            if camera and ownView and camera.CameraType~=Enum.CameraType.Scriptable and not menuBusy()
                and on("AntiShake") and not on("SilentAim") and not on("AimAssist") then
                local alpha=1-math.exp(-(100-val("Stabilize",70))*dt)
                local rotation=camera.CFrame.Rotation
                smoothCamera=smoothCamera and smoothCamera:Lerp(rotation,alpha) or rotation
                camera.CFrame=CFrame.new(camera.CFrame.Position)*smoothCamera
            else smoothCamera=nil end
            updateAim(dt,camera)
            return
        end
        resetCombat();targetMarker.Enabled=false;aimCircle.Visible=false
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
        if not ok then warn("[ClaudeHub MM2] Optional addon unavailable: " .. path .. ": " .. tostring(err)) end
    end
    addon("addons/ThemeManager.lua", function(manager)
        manager:SetLibrary(Library); manager:SetFolder("ClaudeHub/Obsidian"); manager:ApplyToTab(Tabs.Settings)
    end)
    addon("addons/SaveManager.lua", function(manager)
        manager:SetLibrary(Library); manager:IgnoreThemeSettings()
        manager:SetIgnoreIndexes({"MenuKeybind","Freecam","Spectate","SpectatePlayer","ServerChoice","JobID","AimAssist","SilentAim","Fly","Noclip","AntiFling","AimHardLock","RoundDetection","SilentConfigName","SilentConfigChoice","SilentMethod","CustomGravity","JumpPower","Sprint","NoAcceleration","FakeWallhop","ClickTP","AntiVoid","AutoFollow","SelfRagdoll","PadEnabled","FollowPlayer","WaypointList","WaypointName"})
        manager:SetFolder("ClaudeHub/MM2"); manager:BuildConfigSection(Tabs.Settings)
    end)
    ready = true
    for _,id in ipairs({"Fly","Noclip","SilentAim","AntiFling","CustomGravity","JumpPower","Sprint","NoAcceleration","FakeWallhop","ClickTP","AntiVoid","AutoFollow","SelfRagdoll","PadEnabled"}) do Toggles[id]:SetValue(false) end
    scanGuns()
    Options.RoundDetection:SetValue("Auto")
    -- Match the supplied MM2 preset at startup, including after an older config.
    Toggles.SilentTeamCheck:SetValue(false)
    Toggles.SilentVisibleCheck:SetValue(true)
    Options.SilentPoint:SetValue("HumanoidRootPart")
    Options.SilentMethod:SetValue("MM2 Gun")
    Options.SilentHitChance:SetValue(100)
    Options.SilentRadius:SetValue(130)
    Options.AimSmoothing:SetValue(55)
    SilentEngine.Settings.Enabled=false
    Options.SilentRole:SetValue("All players (original)")
    Toggles.SilentSticky:SetValue(false)
    notify("ClaudeHub MM2 v" .. VERSION .. " loaded. RightControl: menu.")
end, function(err) return tostring(err) end)
if not success then
    cleanup()
    pcall(function() Library:Unload() end)
    error("[ClaudeHub MM2] Startup failed: " .. tostring(failure),0)
end
return Library
