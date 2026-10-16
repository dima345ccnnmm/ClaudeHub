--[[
DOORS feature portions adapted from Abysall by FireBacon (bocaj111004).
Source: https://github.com/bocaj111004/Abysall
Revision: 66d4192d00d9b824a304b654bc2d2eb89c3b372b
Port: entity/object aliases, ESP and selected interaction, character,
lighting and notification patterns, adapted to ClaudeHub's renderer/lifecycle. Original analytics,
anti-cheat hooks and destructive entity handlers are NOT included.
Additional UI/control patterns adapted from the user-supplied Main.luau.
Local hazard switches do not imply server-side invulnerability.

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
-- ClaudeHub DOORS Lobby v0.4.1 | standalone, no Abysall global required.
assert(game.GameId == 2440500124, "DOORS lobby module only")
assert(game.PlaceId == 6516141723, "Not the DOORS lobby; use Loader.luau")
local env = getgenv and getgenv() or _G
if env.__ClaudeHubDoorsLobby and not env.__ClaudeHubDoorsLobby.Unloaded then
    env.__ClaudeHubDoorsLobby:Notify("Lobby module is already open", 3)
    return env.__ClaudeHubDoorsLobby
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "LocalPlayer is unavailable")
local VERSION, STARTED = "v0.4.1", os.clock()
local function fetch(path)
    local chunk, err = loadstring(game:HttpGet("https://raw.githubusercontent.com/joustingmatch/ObsidianUltra/main/" .. path), "@ObsidianUltra/" .. path)
    assert(chunk, tostring(err))
    return chunk()
end
local Library = fetch("Library.lua")
env.__ClaudeHubDoorsLobby = Library
local Options, Toggles = Library.Options, Library.Toggles
local alive, ready, connections = true, false, {}
local redeeming, cancelRedeem = false, false
local function connect(event, fn)
    local c=event:Connect(function(...) if alive and ready then return fn(...) end end)
    table.insert(connections,c)
    return c
end
Library:OnUnload(function()
    alive=false;ready=false;cancelRedeem=true
    for _,c in ipairs(connections) do c:Disconnect() end
    if env.__ClaudeHubDoorsLobby==Library then env.__ClaudeHubDoorsLobby=nil end
end)
local Window=Library:CreateWindow({Title="ClaudeHub | DOORS Lobby",Footer=VERSION,
    Center=true,Resizable=true,NotifyOnError=true,Size=UDim2.fromOffset(1040,720)})
local Tabs={Home=Window:AddTab("Home","house"),General=Window:AddTab("Lobby","door-open"),Settings=Window:AddTab("UI Settings","settings")}
local function enabled(id) return Toggles[id] and Toggles[id].Value==true end
local function value(id,fallback) local o=Options[id] if o and o.Value~=nil then return o.Value end return fallback end
local function toggle(box,id,text)
    local t=box:AddToggle(id,{Text=text,Default=false})
    t:AddKeyPicker(id.."Key",{Default="None",Text=text,Mode="Toggle",Modes={"Toggle","Hold"},NoUI=true,SyncToggleState=false})
    local picker=Options[id.."Key"];picker.SyncToggleState=true;picker.Toggled=t.Value;picker:Update()
    return t
end
local function path(obj,...)
    for _,name in ipairs({...}) do obj=obj and obj:FindFirstChild(name) end
    return obj
end
local function remote(name)
    local folder=RS:FindFirstChild("RemotesFolder")
    local r=folder and folder:FindFirstChild(name)
    return r and r:IsA("RemoteEvent") and r or nil
end
local function send(name, ...)
    local r=remote(name)
    if not r then Library:Notify(name..": remote unavailable in this lobby version",4) return false end
    local ok,err=pcall(r.FireServer,r,...)
    if not ok then Library:Notify(name..": "..tostring(err),4) end
    return ok
end
local function playerByName(name)
    for _,p in ipairs(Players:GetPlayers()) do if p.Name==name then return p end end
end
local function playerNames()
    local names={}
    for _,p in ipairs(Players:GetPlayers()) do if p~=player then table.insert(names,p.Name) end end
    table.sort(names)
    return names
end
local profile=Tabs.Home:AddLeftGroupbox("Profile","user")
profile:AddImage("DoorsLobbyAvatar",{Image=("rbxthumb://type=Avatar&id=%d&w=420&h=420"):format(player.UserId),Height=190})
profile:AddLabel(player.DisplayName.." | @"..player.Name)
profile:AddLabel("ClaudeHub DOORS Lobby "..VERSION)
local info=Tabs.Home:AddRightGroupbox("Lobby information","info")
info:AddLabel("Lobby detected by Place ID: "..game.PlaceId)
info:AddLabel("Standalone lobby module: no run camera, entity ESP or Main_Game adapters are started.",true)
info:AddLabel("Lobby controls adapted from Abysall by FireBacon (bocaj111004); MIT notice preserved.",true)
info:AddLabel("Quick Play requests are validated by the game; unavailable/locked destinations can be rejected. No floor unlock is promised.",true)
info:AddLabel("Re-run the loader after teleporting into a run. No automatic teleport execution is installed.",true)
local loaded=info:AddLabel("Loaded in: --")
local selfBox=Tabs.General:AddLeftGroupbox("Self","user")
toggle(selfBox,"LobbyAutoJoin","Auto join selected player's elevator")
selfBox:AddDropdown("LobbyJoinTarget",{Text="Target player",Values=playerNames(),AllowNull=true,Searchable=true})
selfBox:AddButton({Text="Refresh player list",Func=function()
    Options.LobbyJoinTarget:SetValues(playerNames())
    local chosen=value("LobbyJoinTarget")
    if chosen and not playerByName(chosen) then Options.LobbyJoinTarget:SetValue(nil) end
end})
selfBox:AddButton({Text="Leave elevator",DoubleClick=true,Func=function() send("ElevatorExit") end})
local joinStatus=selfBox:AddLabel("Auto Join: disabled")
selfBox:AddLabel("Auto Join only requests the selected player's current elevator. It does not repeatedly leave elevators when the target is absent.",true)
local badges=Tabs.General:AddLeftGroupbox("Achievements","award")
badges:AddDropdown("LobbyBadge",{Text="Unlocked badge",Values={},AllowNull=true,Searchable=true})
local function unlockedBadges()
    local pg=player:FindFirstChild("PlayerGui")
    local list=path(pg,"MainUI","LobbyFrame","Achievements","List")
    local found={}
    if list then for _,button in ipairs(list:GetChildren()) do
        if button:IsA("ImageButton") and button.ImageTransparency==0 then table.insert(found,button.Name) end
    end end
    table.sort(found)
    return found
end
local function refreshBadges() Options.LobbyBadge:SetValues(unlockedBadges()) end
badges:AddButton({Text="Refresh unlocked badges",Func=refreshBadges})
badges:AddButton({Text="Equip selected badge",Func=function()
    local selected=value("LobbyBadge")
    if not selected or not table.find(unlockedBadges(),selected) then Library:Notify("Select an unlocked badge first",4) return end
    send("FlexAchievement",selected)
end})
toggle(badges,"LobbyCycleBadges","Cycle unlocked achievements")
badges:AddSlider("LobbyBadgeDelay",{Text="Cycle delay (seconds)",Default=3,Min=1,Max=30,Rounding=1})
badges:AddLabel("Cycles unlocked badges only. Empty or single-item lists do not start a retry loop.",true)
local codes=Tabs.General:AddLeftGroupbox("Codes","ticket")
codes:AddInput("LobbyCode",{Text="Code",Default="",Placeholder="Enter a DOORS code",Finished=true,MaxLength=100})
codes:AddButton({Text="Redeem entered code",Func=function()
    local code=tostring(value("LobbyCode","")):match("^%s*(.-)%s*$")
    if code=="" then Library:Notify("Enter a code first",3) return end
    send("ShopCode",code)
end})
local referenceCodes={"67","54","41","CHEDDAR BALLS","XQC","PENGUINZ0","KREEKCRAFT","ISHOWSPEED","DANTDM","KUBZ SCOUTS","FIND THE TROLLFACES","THINKNOODLES","W","RAGDOLL UNIVERSE","RAGDOLL MAYHEM","BIJUU MIKE","8BITRYAN","SCREECHSUCKS","LORE","ABCDEFGHIJKLMNOPQRSTUVWXYZ","3rd","LAZYDEVS","RAGDOLL COMBAT","VOCAB HAVOC","PATHSWAP","JUMP OVER THE BRICK"}
codes:AddLabel("The supplied sample's code list may contain expired codes. Server responses determine redemption; this module does not claim success.",true)
codes:AddButton({Text="Try sample's code list",DoubleClick=true,Func=function()
    if redeeming then Library:Notify("A code batch is already running",3) return end
    if not remote("ShopCode") then Library:Notify("ShopCode remote unavailable",4) return end
    redeeming=true;cancelRedeem=false
    task.spawn(function()
        for i,code in ipairs(referenceCodes) do
            if not alive or cancelRedeem then break end
            if not send("ShopCode",code) then break end
            if i<#referenceCodes then task.wait(5.2) end
        end
        redeeming=false
        if alive then Library:Notify(cancelRedeem and "Code batch stopped" or "Code requests finished; check the game's responses",5) end
    end)
end})
codes:AddButton({Text="Stop code requests",Func=function() cancelRedeem=true end})
local play=Tabs.General:AddRightGroupbox("Quick Play","play")
local destinations={{"The Hotel","Hotel"},{"The Mines","Mines"},{"The Backdoor","Backdoor"},{"The Rooms","Rooms"},{"The Outdoors","Garden"},
    {"Battle Mode","Party"},{"Retro Mode","Retro"},{"Rush Mode","Fools26"},{"Halloween","Halloween25"},{"Hotel-","BeforePlus"},{"Super Hard Mode","SuperHardMode"}}
local function createElevator(destination,maxPlayers,friendsOnly)
    return send("CreateElevator",{Mods={},Settings={},Destination=destination,FriendsOnly=friendsOnly,MaxPlayers=tostring(maxPlayers)})
end
for _,entry in ipairs(destinations) do
    play:AddButton({Text=entry[1],DoubleClick=true,Tooltip="Double-click to request a solo elevator. Availability is controlled by the game.",Func=function()
        createElevator(entry[2],1,false)
    end})
end
play:AddLabel("Archives/Stairwell destination identifiers are not guessed. Event/legacy modes from the reference may no longer be available.",true)
local custom=Tabs.General:AddRightGroupbox("Create elevator","door-open")
local destinationNames={};for _,entry in ipairs(destinations) do table.insert(destinationNames,entry[1]) end
custom:AddDropdown("LobbyDestination",{Text="Destination",Values=destinationNames,Default=1})
custom:AddSlider("LobbyMaxPlayers",{Text="Max players",Default=1,Min=1,Max=12,Rounding=0})
custom:AddToggle("LobbyFriendsOnly",{Text="Friends only",Default=false})
custom:AddButton({Text="Create selected elevator",DoubleClick=true,Func=function()
    for _,entry in ipairs(destinations) do if entry[1]==value("LobbyDestination") then
        createElevator(entry[2],value("LobbyMaxPlayers",1),enabled("LobbyFriendsOnly"))
        return
    end end
end})
local function checkJoin()
    if not enabled("LobbyAutoJoin") then joinStatus:SetText("Auto Join: disabled") return end
    local target=playerByName(value("LobbyJoinTarget"))
    if not target or target==player then joinStatus:SetText("Auto Join: select a player still in this server") return end
    local id=target.Character and target.Character:GetAttribute("InGameElevator")
    if id==nil or id==false or id=="" then joinStatus:SetText("Auto Join: target is not in an elevator") return end
    local ownId=player.Character and player.Character:GetAttribute("InGameElevator")
    if ownId==id then joinStatus:SetText("Auto Join: already with target") return end
    local elevators=path(workspace,"Lobby","LobbyElevators")
    if elevators then for _,e in ipairs(elevators:GetChildren()) do
        if e:GetAttribute("ID")==id then
            if send("ElevatorJoin",e) then joinStatus:SetText("Auto Join: join requested; waiting for game") end
            return
        end
    end end
    joinStatus:SetText("Auto Join: target elevator not replicated")
end
local elapsed,lastJoin,lastBadge,previousBadge=0,-math.huge,-math.huge,nil
connect(RunService.Heartbeat,function(dt)
    elapsed+=dt;if elapsed<0.25 then return end elapsed=0
    if os.clock()-lastJoin>=1 then lastJoin=os.clock();checkJoin() end
    if enabled("LobbyCycleBadges") and os.clock()-lastBadge>=value("LobbyBadgeDelay",3) then
        lastBadge=os.clock()
        local available=unlockedBadges()
        if #available>0 then
            local nextBadge=available[1]
            for _,name in ipairs(available) do if name~=previousBadge then nextBadge=name break end end
            if nextBadge~=previousBadge and send("FlexAchievement",nextBadge) then previousBadge=nextBadge end
        end
    end
end)
local menu=Tabs.Settings:AddLeftGroupbox("Menu","settings")
menu:AddButton({Text="Unload lobby module",Func=function() Library:Unload() end})
menu:AddLabel("Menu key"):AddKeyPicker("LobbyMenuKey",{Text="Menu key",Default="RightControl",NoUI=true})
Library.ToggleKeybind=Options.LobbyMenuKey
local ok,theme=pcall(fetch,"addons/ThemeManager.lua")
if ok then theme:SetLibrary(Library);theme:SetFolder("ClaudeHub/DOORS/Lobby");theme:ApplyToTab(Tabs.Settings) end
local saveOK,save=pcall(fetch,"addons/SaveManager.lua")
if saveOK then
    save:SetLibrary(Library);save:IgnoreThemeSettings();save:SetIgnoreIndexes({"LobbyMenuKey"})
    save:SetFolder("ClaudeHub/DOORS/Lobby/configs");save:BuildConfigSection(Tabs.Settings)
end
ready=true;refreshBadges()
loaded:SetText(("Loaded in: %.2fs"):format(os.clock()-STARTED))
Library:Notify("DOORS Lobby "..VERSION.." ready. RightControl opens the menu. Automation starts OFF.",6)
return Library
