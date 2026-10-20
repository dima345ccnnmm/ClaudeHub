local realOs = os
local now, queue = 0, {}
local os = {clock=function() return now end}
local errors, assertions = {}, 0
local function check(x, label) assert(x,label); assertions += 1 end
local function signal()
 local s={listeners={}}
 function s:Connect(fn) local c={Connected=true};function c:Disconnect() self.Connected=false end;table.insert(self.listeners,{c,fn});return c end
 function s:Fire(...) for _,v in ipairs(self.listeners) do if v[1].Connected then v[2](...) end end end
 return s
end
local task={}
function task.spawn(fn) table.insert(queue,{co=coroutine.create(fn),at=now}) end
function task.wait(n) return coroutine.yield(n or 0.01) end
local function advance(delta)
 local goal=now+delta
 for _=1,10000 do
  local index,at
  for i,v in ipairs(queue) do if v.at<=goal and (not at or v.at<at) then index=i;at=v.at end end
  if not index then now=goal; return end
  local item=table.remove(queue,index);now=item.at
  local ok,delay=coroutine.resume(item.co)
  if not ok then table.insert(errors,tostring(delay));error(delay) end
  if coroutine.status(item.co)~='dead' then item.at=now+(delay or 0.01);table.insert(queue,item) end
 end
 error('scheduler overflow')
end
local made={}
local Instance={new=function(kind)
 local i={ClassName=kind}; function i:Destroy() self.Parent=nil;self.Destroyed=true end
 table.insert(made,i);return i
end}
local UDim2={fromOffset=function(x,y)return{x,y}end,fromScale=function(x,y)return{x,y}end}
local UDim={new=function(x,y)return{x,y}end}
local Vector3={new=function(x,y,z)return{x,y,z}end}
local Color3={fromRGB=function(r,g,b)return{r,g,b}end}
local Enum={Font={GothamBold='GothamBold'}}
local warnings={};local function warn(s)table.insert(warnings,s)end
local Players={PlayerRemoving=signal()}
local function head()return{IsA=function(_,k)return k=='BasePart'end}end
local function makePlayer(id)
 local p={UserId=id,Parent=Players};local c={Head=head(),Humanoid={Health=100}}
 function c:FindFirstChild(k)return self[k]end
 function c:FindFirstChildOfClass(k)return self[k]end
 p.Character=c;return p
end
local me,other=makePlayer(1),makePlayer(2);Players.LocalPlayer=me
local allPlayers={me,other}
function Players:GetPlayers()return allPlayers end
local HttpService={JSONEncode=function(_,v)return v end,JSONDecode=function(_,v)return v end}
local game={JobId='11111111-1111-4111-8111-111111111111',PlaceId=142823291}
function game:GetService(n) if n=='Players' then return Players elseif n=='HttpService' then return HttpService end error(n) end
local env={};local function getgenv()return env end
local calls,reply,code={}, {ok=true,token=string.rep('a',64),peers={1,2,999},ttl=60},200
local duringRequest
local request=function(options)
 table.insert(calls,options)
 if duringRequest then local fn=duringRequest;duringRequest=nil;fn() end
 if options.Url:find('/v1/leave',1,true) then return{StatusCode=200,Body={ok=true}}end
 return {StatusCode=code,Body=reply}
end
local function liveBadges()
 local n=0;for _,i in ipairs(made)do if i.ClassName=='BillboardGui' and i.Parent and not i.Destroyed then n+=1 end end;return n
end
local library={Unloaded=false,callbacks={}}
function library:OnUnload(fn)table.insert(self.callbacks,fn)end
local function unload(lib)lib.Unloaded=true;for _,fn in ipairs(lib.callbacks)do fn()end end
local start=(function()
-- ClaudeHub presence v1.0.0. Same-server, self-reported presence; NOT verified identity.
-- No external library, user list, admin credentials, HWID, or camera hooks.
return function(Library, env)
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
                        label.Font = Enum.Font.GothamBold
                        label.BorderSizePixel = 0
                        label.Parent = badge
                        local corner = Instance.new('UICorner')
                        corner.CornerRadius = UDim.new(0, 6)
                        corner.Parent = label
                        badge.Parent = head
                        badges[player] = badge
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
                })
                if data and data.ok == true and type(data.token) == 'string' and #data.token == 64
                    and type(data.peers) == 'table' then
                    if stopped or not enabled() then leave(data.token)
                    else
                        token = data.token; failures = 0
                        local found = {}
                        for _, id in ipairs(data.peers) do
                            if type(id) == 'number' and id > 0 and id % 1 == 0 and id ~= LocalPlayer.UserId then found[id] = true end
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
end)()
local controller=start(library,env)
check(controller~=nil,'start returns controller');advance(0.5)
check(liveBadges()==1,'only matching other player gets badge')
check(calls[1].Body.userId==1 and calls[1].Body.placeId==game.PlaceId and calls[1].Body.jobId==game.JobId,'heartbeat identity')
check(calls[1].Body.token==nil,'initial registration without token')
local badge;for _,x in ipairs(made)do if x.ClassName=='BillboardGui' and x.Parent then badge=x end end
check(badge.Adornee==other.Character.Head,'badge on head');check(not badge.AlwaysOnTop,'not wall ESP')
other.Character.Head=head();advance(0.5);check(badge.Destroyed and liveBadges()==1,'respawn head replaces badge')
other.Character.Humanoid.Health=0;advance(0.5);check(liveBadges()==0,'dead character clears badge')
other.Character.Humanoid.Health=100;advance(0.5);check(liveBadges()==1,'revived character badge')
other.Parent=nil;Players.PlayerRemoving:Fire(other);check(liveBadges()==0,'player removal clears badge')
allPlayers={me};advance(0.5);check(liveBadges()==0,'no badge for missing player')
other.Parent=Players;allPlayers={me,other};advance(0.5);check(liveBadges()==1,'streamed peer returns')
reply={ok=true,token=string.rep('a',64),peers={},ttl=60};advance(23);check(liveBadges()==0,'fresh empty peers removes old badge')
check(calls[2].Body.token==string.rep('a',64),'subsequent heartbeat owns same session')
reply={ok=true,token=string.rep('a',64),peers={2},ttl=60};advance(23);check(liveBadges()==1,'peer refresh')
code=503;advance(62);check(liveBadges()==0,'outage expires stale badge');check(#warnings==1,'one outage warning')
code=200;advance(100);check(liveBadges()==1,'recovers after outage')
env.ClaudeHubPresenceEnabled=false;advance(1.5);check(liveBadges()==0,'opt out clears badge')
local last=calls[#calls];check(last.Url:find('/v1/leave',1,true)~=nil,'opt out leaves session')
env.ClaudeHubPresenceEnabled=true;advance(1.5);check(liveBadges()==1,'opt in restores presence')
check(calls[#calls].Body.token==nil,'opt in gets new session')
controller.Stop();advance(0);check(liveBadges()==0 and env.__ClaudeHubPresence_v1==nil,'stop clears badge and global')
check(not Players.PlayerRemoving.listeners[1][1].Connected,'stop disconnects signals')
local total=#calls;advance(90);check(#calls==total,'stop leaves no background requests')
controller.Stop();check(#calls==total,'stop is idempotent')
local lib2={Unloaded=false,callbacks={}};lib2.OnUnload=library.OnUnload
local c2=start(lib2,env);advance(0.5);check(liveBadges()==1,'restart clean')
unload(lib2);advance(0);check(liveBadges()==0,'library unload cleanup')
local lib3={Unloaded=false,callbacks={}};lib3.OnUnload=library.OnUnload
local c3=start(lib3,env);duringRequest=function()c3.Stop()end;advance(0.5)
check(liveBadges()==0 and calls[#calls].Url:find('/v1/leave',1,true)~=nil,'late HTTP response after stop is removed')
local saved=request;request=nil;check(start(lib3,env)==nil,'unsupported executor disables gracefully');request=saved
local job=game.JobId;game.JobId='';check(start(lib3,env)==nil,'empty JobId disabled');game.JobId=job
check(#errors==0,'no scheduler errors')
print(assertions..' Luau client assertions passed (mock Roblox, not live gameplay).')
