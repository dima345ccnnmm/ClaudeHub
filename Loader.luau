-- ClaudeHub loader v1.5.0 | MM2 + JJS + DOORS/lobby + universal fallback.
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
env.__ClaudeHubTouch = {}
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
local function startSharedControls(Library,env)
    local UIS=game:GetService('UserInputService')
    local Players=game:GetService('Players')
    local RunService=game:GetService('RunService')
    local player=Players.LocalPlayer
    if not player then return end
    local touch=env.__ClaudeHubTouch or {}
    env.__ClaudeHubTouch=touch
    touch.Mobile=Library.IsMobile==true or (UIS.TouchEnabled==true and UIS.KeyboardEnabled~=true)
    local connections,gui={},nil
    local stopped=false
    local function connect(signal,fn) if signal then table.insert(connections,signal:Connect(fn)) end end
    local function reset()
        for _,key in ipairs({'Up','Down','Left','Right','Forward','Back','LookX','LookY'}) do touch[key]=0 end
        touch.Assist=false;touch.Sprint=false
    end
    reset()
    local function stop()
        if stopped then return end
        stopped=true;reset()
        for _,c in ipairs(connections) do c:Disconnect() end
        if gui then gui:Destroy() end
        if env.__ClaudeHubTouch==touch then env.__ClaudeHubTouch=nil end
    end
    Library:OnUnload(stop)
    connect(UIS.WindowFocusReleased,reset)
    connect(player.CharacterRemoving,reset)
    local function fit()
        if not touch.Mobile then return end
        local frame=Library.Window and Library.Window.MainFrame
        local camera=workspace.CurrentCamera
        if not frame or not camera then return end
        local vp=camera.ViewportSize
        local dpi=tonumber(env.ClaudeHubMobileUIScale) or 80
        if type(Library.SetDPIScale)=='function' then Library:SetDPIScale(dpi) end
        local scale=dpi/100
        frame.Size=UDim2.fromOffset(math.max(240,math.min(frame.Size.X.Offset,(vp.X-24)/scale)),
            math.max(180,math.min(frame.Size.Y.Offset,(vp.Y-70)/scale)))
        frame.AnchorPoint=Vector2.new(0,0)
        frame.Position=UDim2.fromOffset(math.max(4,(vp.X-frame.Size.X.Offset*scale)/2),
            math.max(4,(vp.Y-frame.Size.Y.Offset*scale)/2))
    end
    local tab=Library.Tabs and (Library.Tabs.Settings or Library.Tabs['UI Settings'])
    if tab then
        local box=tab:AddRightGroupbox('ClaudeHub users / Mobile','smartphone')
        box:AddSlider('ClaudeHubBadgeSize',{Text='User badge size (%)',Default=math.clamp((tonumber(env.ClaudeHubPresenceScale) or 1)*100,50,200),Min=50,Max=200,Rounding=0,
            Callback=function(value) env.ClaudeHubPresenceScale=value/100 end})
        box:AddToggle('ClaudeHubShareDevice',{Text='Share device / executor',Default=env.ClaudeHubShareDeviceInfo~=false,
            Callback=function(value) env.ClaudeHubShareDeviceInfo=value end})
        box:AddToggle('ClaudeHubTouchControls',{Text='Touch controls',Default=touch.Mobile,
            Callback=function(value) touch.Visible=value;if not value then reset() end;if gui then gui.Enabled=value end end})
        box:AddSlider('ClaudeHubMobileUIScale',{Text='Mobile UI scale (%)',Default=tonumber(env.ClaudeHubMobileUIScale) or 80,Min=50,Max=100,Rounding=0,
            Callback=function(value) env.ClaudeHubMobileUIScale=value;fit() end})
        box:AddButton({Text='Fit mobile window',Func=fit})
    end
    touch.Visible=touch.Mobile
    gui=Instance.new('ScreenGui');gui.Name='ClaudeHubTouchControls';gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=true;gui.DisplayOrder=200;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    gui.Enabled=touch.Visible;gui.Parent=player:WaitForChild('PlayerGui')
    local function style(button,text)
        button.Text=text;button.Font=Enum.Font.GothamBold;button.TextSize=12
        button.TextColor3=Color3.fromRGB(232,223,255);button.BackgroundColor3=Color3.fromRGB(40,28,65)
        button.BackgroundTransparency=0.15;button.BorderSizePixel=0
        local round=Instance.new('UICorner',button);round.CornerRadius=UDim.new(0,7)
    end
    local menu=Instance.new('TextButton',gui);menu.Name='Menu';menu.Size=UDim2.fromOffset(64,36)
    menu.AnchorPoint=Vector2.new(1,0);menu.Position=UDim2.new(1,-10,0,48);style(menu,'CH MENU')
    connect(menu.Activated,function() reset();Library:Toggle() end)
    local pad=Instance.new('TextButton',gui);pad.Size=UDim2.fromOffset(64,32)
    pad.AnchorPoint=Vector2.new(1,0);pad.Position=UDim2.new(1,-10,0,88);style(pad,'PAD')
    local panel=Instance.new('ScrollingFrame',gui);panel.Name='ActionPad';panel.AnchorPoint=Vector2.new(1,0)
    panel.Position=UDim2.new(1,-10,0,126);panel.Size=UDim2.fromOffset(222,180)
    panel.BackgroundTransparency=1;panel.BorderSizePixel=0;panel.ScrollBarThickness=3
    panel.ScrollingDirection=Enum.ScrollingDirection.Y
    local grid=Instance.new('UIGridLayout',panel);grid.CellSize=UDim2.fromOffset(68,40);grid.CellPadding=UDim2.fromOffset(6,6)
    grid.SortOrder=Enum.SortOrder.LayoutOrder
    connect(pad.Activated,function() panel.Visible=not panel.Visible;reset() end)
    local count=0
    local function button(label)
        count+=1;local b=Instance.new('TextButton',panel);b.LayoutOrder=count;style(b,label);return b
    end
    local function held(label,key)
        local b=button(label);local active
        connect(b.InputBegan,function(input)
            if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
            if Library.Toggled or UIS:GetFocusedTextBox() then return end
            active=input;touch[key]=(key=='Assist' or key=='Sprint') and true or 1
        end)
        connect(UIS.InputEnded,function(input) if active==input then active=nil;if key=='Assist' or key=='Sprint' then touch[key]=false else touch[key]=0 end end end)
    end
    local toggles=Library.Toggles or {}
    local function toggleButton(label,ids)
        local chosen
        for _,id in ipairs(ids) do if toggles[id] then chosen=toggles[id];break end end
        if not chosen then return end
        local b=button(label)
        connect(b.Activated,function() reset();chosen:SetValue(not chosen.Value) end)
    end
    toggleButton('FLY',{'Fly','DoorsFly'})
    toggleButton('NOCLIP',{'Noclip','DoorsNoclip'})
    toggleButton('TRIGGER',{'TriggerBot'})
    toggleButton('AIM',{'AimAssist','FaceTarget'})
    toggleButton('BLOCK',{'AutoBlock'})
    toggleButton('INTERACT',{'AutoInteract','DoorsAutoInteract'})
    toggleButton('JUMP+',{'InfiniteJump','InfJump','DoorsInfJump','DoorsInfiniteJump'})
    if toggles.AimAssist then held('ASSIST','Assist') end
    local sprint=toggles.Sprint or toggles.UltraSprint
    if sprint then
        local b=button('SPRINT');local active
        connect(b.InputBegan,function(input)
            if Library.Toggled or UIS:GetFocusedTextBox() then return end
            if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
                active=input;sprint:SetValue(true);touch.Sprint=true
            end
        end)
        connect(UIS.InputEnded,function(input) if input==active then active=nil;touch.Sprint=false end end)
    end
    held('UP','Up');held('DOWN','Down')
    if toggles.Freecam then
        toggleButton('FREECAM',{'Freecam'})
        held('FWD','Forward');held('BACK','Back');held('LEFT','Left');held('RIGHT','Right')
        local look=button('LOOK');local active,last
        connect(look.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.Touch then active=input;last=input.Position end end)
        connect(UIS.InputChanged,function(input)
            if input==active and last then local delta=input.Position-last;last=input.Position;touch.LookX+=delta.X;touch.LookY+=delta.Y end
        end)
        connect(UIS.InputEnded,function(input) if input==active then active=nil;last=nil end end)
    end
    for name,fn in pairs(Library.ClaudeHubTouchActions or {}) do
        local action=fn;local b=button(name)
        connect(b.Activated,function() if not Library.Toggled and not UIS:GetFocusedTextBox() then pcall(action) end end)
    end
    panel.CanvasSize=UDim2.fromOffset(0,math.ceil(count/3)*46)
    local cross=Instance.new('Frame',gui);cross.Name='MobileCrosshair';cross.AnchorPoint=Vector2.new(0.5,0.5)
    cross.Position=UDim2.fromScale(0.5,0.5);cross.Size=UDim2.fromOffset(5,5)
    cross.BackgroundColor3=Color3.fromRGB(225,205,255);cross.BorderSizePixel=0;cross.Active=false;cross.Visible=false
    local elapsed,lastSize=0,nil
    connect(RunService.Heartbeat,function(dt)
        if stopped then return end
        if Library.Toggled or UIS:GetFocusedTextBox() then reset() end
        cross.Visible=touch.Mobile and toggles.TriggerBot and toggles.TriggerBot.Value and not Library.Toggled
            and not (toggles.Freecam and toggles.Freecam.Value) and not (toggles.Spectate and toggles.Spectate.Value) or false
        elapsed+=dt;if elapsed<0.5 then return end;elapsed=0
        gui.Enabled=touch.Visible==true
        local camera=workspace.CurrentCamera
        if camera and camera.ViewportSize~=lastSize then
            lastSize=camera.ViewportSize;fit()
            panel.Size=UDim2.fromOffset(math.min(222,math.max(140,lastSize.X-24)),math.min(230,math.max(92,lastSize.Y-200)))
        end
    end)
    fit()
    return {Stop=stop,Touch=touch,Fit=fit}
end

local function startPresence(Library, env)
    env = env or (getgenv and getgenv() or _G)
    local KEY = '__ClaudeHubPresence_v1'
    if env[KEY] and env[KEY].Stop then pcall(env[KEY].Stop) end
    local endpoint = 'https://claudehub-presence.dimaccnnmm1234.workers.dev'
    local requestHTTP = (type(request) == 'function' and request)
        or (type(http_request) == 'function' and http_request)
        or (type(syn) == 'table' and syn.request)
        or (type(http) == 'table' and http.request)
    if type(requestHTTP) ~= 'function' then
        warn('[ClaudeHub Presence] Executor HTTP request unavailable; presence disabled.')
        return nil
    end
    local Players = game:GetService('Players')
    local HttpService = game:GetService('HttpService')
    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer or game.JobId == '' then return nil end
    local stopped, token, expiresAt = false, nil, 0
    local peers, badges, connections = {}, {}, {}
    local controller = {}
    local function cleanText(value)
        if type(value)~='string' then return 'Unknown' end
        local text=value:gsub('[^%w ._+()/%-]',''):sub(1,32):match('^%s*(.-)%s*$')
        return text~='' and text or 'Unknown'
    end
    local function deviceName()
        local ok,uis=pcall(function() return game:GetService('UserInputService') end)
        if not ok then return 'Unknown' end
        local consoleOK,console=pcall(function() return game:GetService('GuiService'):IsTenFootInterface() end)
        if consoleOK and console then return 'Console' end
        local platformOK,platform=pcall(function() return tostring(uis:GetPlatform()) end)
        if platformOK then
            if platform:find('Android') or platform:find('IOS') then return 'Mobile' end
            if platform:find('Windows') or platform:find('OSX') or platform:find('Linux') then return 'PC' end
        end
        if uis.TouchEnabled and not uis.KeyboardEnabled then return 'Mobile' end
        return uis.KeyboardEnabled and 'PC' or 'Unknown'
    end
    local function executorName()
        local detect=(type(identifyexecutor)=='function' and identifyexecutor)
            or (type(getexecutorname)=='function' and getexecutorname)
        if detect then local ok,name=pcall(detect);if ok then return cleanText(name) end end
        return 'Unknown'
    end
    local device,executor=deviceName(),executorName()
    controller.Device=device;controller.Executor=executor
    local function post(path, data)
        local ok, response = pcall(function()
            return requestHTTP({Url = endpoint .. path, Method = 'POST',
                Headers = {['Content-Type'] = 'application/json'},
                Body = HttpService:JSONEncode(data), Timeout = 10})
        end)
        if not ok or type(response) ~= 'table' then return nil, 0 end
        local code = tonumber(response.StatusCode or response.Status) or 0
        if code ~= 200 then return nil, code end
        local decoded, value = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if decoded and type(value) == 'table' then return value, code end
        return nil, code
    end
    local function leave(value)
        if value then task.spawn(function() post('/v1/leave', {token=value}) end) end
    end
    local function clear(player)
        local b = badges[player]
        if b then pcall(function() b:Destroy() end); badges[player] = nil end
    end
    local function clearAll()
        for player in pairs(badges) do clear(player) end
    end
    local function enabled()
        return not stopped and not Library.Unloaded and env.ClaudeHubPresenceEnabled ~= false
    end
    function controller.Stop()
        if stopped then return end
        stopped = true
        clearAll(); table.clear(peers)
        for _, c in ipairs(connections) do c:Disconnect() end
        table.clear(connections)
        local oldToken = token; token = nil; leave(oldToken)
        if env[KEY] == controller then env[KEY] = nil end
    end
    env[KEY] = controller
    if type(Library.OnUnload) == 'function' then Library:OnUnload(controller.Stop) end
    table.insert(connections, Players.PlayerRemoving:Connect(clear))
    local function updateBadges()
        if not enabled() or os.clock() >= expiresAt then clearAll(); return end
        for player in pairs(badges) do
            if player.Parent ~= Players or not peers[player.UserId] then clear(player) end
        end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and peers[player.UserId] then
                local char = player.Character
                local head = char and char:FindFirstChild('Head')
                local humanoid = char and char:FindFirstChildOfClass('Humanoid')
                if not head or not head:IsA('BasePart') or not humanoid or humanoid.Health <= 0 then clear(player)
                else
                    local badge = badges[player]
                    if badge and (badge.Parent ~= head or badge.Adornee ~= head) then clear(player); badge = nil end
                    if not badge then
                        badge = Instance.new('BillboardGui')
                        badge.Name = 'ClaudeHubPresence'
                        badge.Adornee = head
                        badge.Size = UDim2.fromOffset(116, 24)
                        badge.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
                        badge.AlwaysOnTop = false
                        badge.MaxDistance = 120
                        badge.LightInfluence = 0
                        local label = Instance.new('TextLabel')
                        label.Name = 'Badge'
                        label.Size = UDim2.fromScale(1, 1)
                        label.BackgroundColor3 = Color3.fromRGB(21, 17, 32)
                        label.BackgroundTransparency = 0.15
                        label.Text = 'ClaudeHub'
                        label.TextColor3 = Color3.fromRGB(181, 146, 255)
                        label.TextSize = 14
                        label.RichText = false
                        label.Font = Enum.Font.GothamBold
                        label.BorderSizePixel = 0
                        label.Parent = badge
                        local corner = Instance.new('UICorner')
                        corner.CornerRadius = UDim.new(0, 6)
                        corner.Parent = label
                        badge.Parent = head
                        badges[player] = badge
                    end
                    local profile=peers[player.UserId]
                    local label=badge:FindFirstChild('Badge')
                    if label then
                        local text='ClaudeHub | '..cleanText(profile.device)..' | '..cleanText(profile.executor)
                        local scale=tonumber(env.ClaudeHubPresenceScale) or 1
                        if scale~=scale then scale=1 end
                        scale=math.clamp(scale,0.5,2)
                        label.Text=text;label.TextSize=math.floor(14*scale+0.5)
                        badge.Size=UDim2.fromOffset(math.floor(math.clamp(#text*8+20,116,600)*scale),math.floor(24*scale))
                    end
                end
            end
        end
    end
    task.spawn(function()
        while not stopped do
            if Library.Unloaded then controller.Stop(); break end
            local ok = pcall(updateBadges)
            if not ok then clearAll() end
            task.wait(0.5)
        end
    end)
    task.spawn(function()
        local nextPoll, failures, warned = 0, 0, false
        while not stopped do
            if Library.Unloaded then controller.Stop(); break end
            if not enabled() then
                clearAll(); table.clear(peers); expiresAt = 0
                local oldToken = token; token = nil; leave(oldToken)
                nextPoll = 0
            elseif os.clock() >= nextPoll then
                local data, status = post('/v1/heartbeat', {
                    userId = LocalPlayer.UserId, placeId = game.PlaceId, jobId = game.JobId, token = token,
                    device=env.ClaudeHubShareDeviceInfo~=false and device or 'Unknown',
                    executor=env.ClaudeHubShareDeviceInfo~=false and executor or 'Unknown',
                })
                if data and data.ok == true and type(data.token) == 'string' and #data.token == 64
                    and type(data.peers) == 'table' then
                    if stopped or not enabled() then leave(data.token)
                    else
                        token = data.token; failures = 0
                        local found = {}
                        for _, id in ipairs(data.peers) do
                            if type(id) == 'number' and id > 0 and id % 1 == 0 and id ~= LocalPlayer.UserId then found[id] = {device="Unknown",executor="Unknown"} end
                        end
                        if type(data.profiles)=='table' then
                            for index,profile in ipairs(data.profiles) do
                                if index>100 then break end
                                if type(profile)=='table' and found[profile.userId] then
                                    found[profile.userId]={device=cleanText(profile.device),executor=cleanText(profile.executor)}
                                end
                            end
                        end
                        peers = found
                        expiresAt = os.clock() + math.clamp(tonumber(data.ttl) or 60, 1, 60)
                        nextPoll = os.clock() + 20 + math.random() * 2
                    end
                else
                    failures = math.min(failures + 1, 3)
                    nextPoll = os.clock() + (status == 429 and 60 or math.min(20 * 2^(failures-1), 120))
                    if not warned then
                        warned = true
                        warn('[ClaudeHub Presence] API unavailable; hub continues normally. HTTP ' .. tostring(status))
                    end
                end
            end
            task.wait(1)
        end
    end)
    return controller
end

if state.Library then
    local controlsOK,controls=pcall(startSharedControls,state.Library,env)
    if controlsOK then state.Controls=controls
    else warn("[ClaudeHub Mobile] Common controls unavailable; hub remains loaded: "..tostring(controls)) end
    local presenceOK, presence = pcall(startPresence, state.Library, env)
    if presenceOK then state.Presence = presence
    else warn("[ClaudeHub Presence] Could not initialize; hub continues normally.") end
end
return state.Library
