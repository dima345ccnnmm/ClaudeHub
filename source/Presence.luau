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
