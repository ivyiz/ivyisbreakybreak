-- Ivyis Breaky Break (walk only)
-- Walk to selected eggs and keep swinging; carry pets with CPS >= min to Zone1 and drop them.

if getgenv then
    local previous = getgenv().EggFarmer
    if previous and previous.stop then
        pcall(previous.stop)
    end
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local Shared = RS:WaitForChild("Shared")
local EggRewards = require(Shared.EggRewards)
local EggConfig = require(Shared.EggConfig)
local EggTargeting = require(Shared.EggTargeting)
local ZoneLookup = require(Shared.ZoneHitboxLookup)
local DropCarriedRemote = RS:WaitForChild("DropCarriedRemote")
local ClientFolder = LP.PlayerScripts:WaitForChild("Client")
local Controllers = ClientFolder:WaitForChild("Controllers")
local PickaxeConfig = require(Shared.PickaxeConfig)
local AutoSwing = require(Controllers:WaitForChild("AutoSwingController"))
local PickaxeController = require(Controllers:WaitForChild("PickaxeController"))
local firePrompt = fireproximityprompt

local function disconnectOldSource(signal)
    local ok, conns = pcall(getconnections, signal)
    if not ok then
        return
    end
    for _, connection in ipairs(conns) do
        local callback = connection.Function
        if callback then
            local ok2, source = pcall(debug.info, callback, "s")
            if ok2 and type(source) == "string" and source:find("egg-farmer", 1, true) then
                pcall(function()
                    connection:Disconnect()
                end)
            end
        end
    end
end

do
    if getgenv then
        local previousCleanup = getgenv().EggFarmerCleanup
        if previousCleanup then
            pcall(previousCleanup)
        end
    end
    local UIService = game:GetService("UserInputService")
    local LP0 = game:GetService("Players").LocalPlayer
    disconnectOldSource(RunService.RenderStepped)
    disconnectOldSource(UIService.InputBegan)
    disconnectOldSource(UIService.InputChanged)
    if LP0 then
        disconnectOldSource(LP0:GetAttributeChangedSignal("Carrying"))
    end
    pcall(function()
        AutoSwing.SetOn(false)
        AutoSwing.SetOn = function() end
    end)
end

local CONFIG_PATH = "egg-farmer-config.json"
local CONFIG_VERSION = 2
local CONFIG = {
    minCps = 0,
    selected = {},
    dropArea = "zone1",
    autoGems = true,
    zoneStart = true,
    guardGate = true,
    guardSafeDist = 0,
    roamRadius = 900,
    petScanRadius = 250,
    stepSeconds = 0.55,
}

local COLORS = {
    bg = Color3.fromRGB(0, 0, 0),
    surface = Color3.fromRGB(11, 11, 11),
    surfaceHover = Color3.fromRGB(22, 22, 22),
    border = Color3.fromRGB(42, 42, 42),
    text = Color3.fromRGB(245, 245, 245),
    muted = Color3.fromRGB(158, 158, 158),
    accent = Color3.fromRGB(255, 255, 255),
    accentText = Color3.fromRGB(0, 0, 0),
}

local FONT_FAMILY = "rbxasset://fonts/families/Roboto.json"
local FACE_REGULAR, FACE_MEDIUM, FACE_BOLD, FACE_BLACK
do
    local function makeFace(weight)
        local ok, face = pcall(function()
            return Font.new(FONT_FAMILY, weight, Enum.FontStyle.Normal)
        end)
        if ok then
            return face
        end
        return nil
    end
    FACE_REGULAR = makeFace(Enum.FontWeight.Regular)
    FACE_MEDIUM = makeFace(Enum.FontWeight.Medium)
    FACE_BOLD = makeFace(Enum.FontWeight.Bold)
    FACE_BLACK = makeFace(Enum.FontWeight.Heavy)
end

local state = {
    running = false,
    runId = 0,
    status = "Idle",
    dropped = 0,
    skipped = 0,
    lastDrop = "-",
    targetEgg = nil,
    targetAt = 0,
    targetHp = nil,
    returnPos = nil,
    pendingCps = nil,
    moveTarget = nil,
    moveDir = nil,
    stopRadius = nil,
    intentionalDrop = false,
    carrySnapshot = nil,
    recover = nil,
    gemJob = nil,
    swingCount = 0,
    approach = nil,
    orbits = 0,
    forcePushUntil = 0,
    pathGoal = nil,
    debug = { steal = nil, carry = nil, jumps = 0 },
}

local blacklist = {}
local ignored = {}
local dropGuards = {}
local inDroppedZone
local saveConfig
local ui
local api = {}
local connections = {}

local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

local function alive()
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if ch and hum and hum.Health > 0 then
        return ch, hum
    end
    return nil, nil
end

local function root()
    local ch = LP.Character
    local r = ch and ch:FindFirstChild("HumanoidRootPart")
    if r and r:IsA("BasePart") then
        return r
    end
    return nil
end

local TURN_RATE = 10

track(RunService.RenderStepped:Connect(function(dt)
    if not state.moveTarget then
        state.moveDir = nil
        return
    end
    local ch, hum = alive()
    local r = root()
    if not ch or not hum or not r then
        return
    end
    local delta = state.moveTarget - r.Position
    delta = Vector3.new(delta.X, 0, delta.Z)
    local dist = delta.Magnitude
    if dist < (state.stopRadius or 0.8) then
        state.moveDir = nil
        hum:Move(Vector3.zero)
        return
    end
    local desired = delta.Unit
    if state.nudge and os.clock() < state.nudge.until_ then
        desired = (desired + state.nudge.dir * 1.6).Unit
    end
    local current = state.moveDir
    if current and dist > 4 and os.clock() >= state.forcePushUntil then
        local dot = math.clamp(current:Dot(desired), -1, 1)
        local angle = math.acos(dot)
        local step = math.min(angle, TURN_RATE * math.max(dt, 1 / 240))
        state.moveDir = current:Lerp(desired, step / math.max(angle, 1e-4)).Unit
    else
        state.moveDir = desired
    end
    hum:Move(state.moveDir)
    local stall = state.stall
    if not stall or (stall.pos - r.Position).Magnitude > 2 then
        state.stall = { pos = r.Position, at = os.clock() }
    elseif os.clock() - stall.at > 0.6 then
        stall.at = os.clock()
        state.stall = { pos = r.Position, at = os.clock() }
        if hum.FloorMaterial ~= Enum.Material.Air then
            hum.Jump = true
            state.debug.jumps += 1
        end
        local side = Vector3.new(-desired.Z, 0, desired.X)
        if state.moveDir then
            side = Vector3.new(-state.moveDir.Z, 0, state.moveDir.X)
        end
        state.nudge = { until_ = os.clock() + 0.5, dir = side }
    end
end))

local function stopMove()
    state.moveTarget = nil
    state.moveDir = nil
    state.stopRadius = nil
    state.moveToAt = nil
    local _, hum = alive()
    if hum then
        hum:Move(Vector3.zero)
    end
end

local function cleanup()
    state.running = false
    state.runId += 1
    stopMove()
    pcall(function()
        AutoSwing.SetOn(false)
    end)
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)
    if ui and ui.closeDropdown then
        pcall(ui.closeDropdown)
    end
    local playerGui = LP:FindFirstChild("PlayerGui")
    local old = playerGui and playerGui:FindFirstChild("EggFarmerUI")
    if old then
        old:Destroy()
    end
end
getgenv().EggFarmerCleanup = cleanup

do
    local gemDrop = RS:FindFirstChild("EggGemDropRemote")
    if gemDrop and gemDrop:IsA("RemoteEvent") then
        track(gemDrop.OnClientEvent:Connect(function(position, amount)
            if CONFIG.autoGems and typeof(position) == "Vector3" then
                state.gemJob = {
                    pos = position,
                    started = os.clock(),
                    deadline = os.clock() + 6,
                }
            end
        end))
    end
end

local function setStatus(text)
    state.status = text
    if ui then
        ui.setStatus(text)
    end
end

track(LP:GetAttributeChangedSignal("Carrying"):Connect(function()
    if LP:GetAttribute("Carrying") ~= nil then
        return
    end
    if state.intentionalDrop then
        return
    end
    local snapshot = state.carrySnapshot
    if not snapshot or not snapshot.name then
        return
    end
    local r = root()
    state.recover = {
        name = snapshot.name,
        cps = snapshot.cps,
        pos = r and r.Position or Vector3.zero,
        deadline = os.clock() + 60,
    }
    state.carrySnapshot = nil
    setStatus(string.format("Pet %s dropped - recovering...", snapshot.name))
end))

local function fmt(n)
    if type(n) ~= "number" or n ~= n then
        return "0"
    end
    if n >= 1e15 then
        return string.format("%.3gQ", n / 1e15)
    end
    if n >= 1e12 then
        return string.format("%.3gT", n / 1e12)
    end
    if n >= 1e9 then
        return string.format("%.3gB", n / 1e9)
    end
    if n >= 1e6 then
        return string.format("%.3gM", n / 1e6)
    end
    if n >= 1e3 then
        return string.format("%.3gK", n / 1e3)
    end
    return tostring(math.floor(n))
end

local function parseNumber(str)
    str = tostring(str or ""):gsub("%s", ""):gsub(",", ".")
    if str == "" then
        return nil
    end
    local suffix = str:sub(-1):lower()
    local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15 })[suffix]
    if mult then
        str = str:sub(1, -2)
    else
        mult = 1
    end
    local n = tonumber(str)
    if not n then
        return nil
    end
    return n * mult
end

local ZONE_EGGS = {
    [1] = { "Forest Egg", "Rock Egg", "Swamp Egg" },
    [2] = { "Cactus Egg", "Bones Egg", "Scorpion Egg" },
    [3] = { "Frozen Egg", "Frosty Egg", "Yeti Egg" },
    [4] = { "Rainbow Egg", "Easter Bunny Egg", "Candy Egg" },
    [5] = { "Gooey Egg", "Tree Egg", "Lake Egg" },
    [6] = { "Sea Stones Egg", "Sea Egg", "Water Egg" },
    [7] = { "Angel Egg", "Fallen Angel Egg", "Volcanic Egg" },
    [8] = { "Bamboo Egg", "Blossom Egg", "Fortune Egg" },
    [9] = { "Starry Egg", "Sun Egg", "BlackHole Egg" },
    [10] = { "Plasma Egg", "Nebula Egg", "Supernova Egg" },
    [11] = { "Skull Egg", "LockedEgg", "Phantom Egg" },
    [12] = { "LunaEgg", "FairyEgg", "PhoenixEgg", "CrystalEgg", "RoyalDragonEgg" },
}

local CATALOG = { byName = {}, byZone = {}, names = {} }
for z = 1, 12 do
    local list = {}
    for _, name in ipairs(ZONE_EGGS[z] or {}) do
        local data = EggConfig.Eggs[name]
        local entry = { zone = z, name = name, hp = data and data.Health or 0 }
        CATALOG.byName[name] = entry
        CATALOG.names[#CATALOG.names + 1] = name
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        return (a.hp or 0) < (b.hp or 0)
    end)
    CATALOG.byZone[z] = list
end

local function prettyEgg(name)
    return (name:gsub("(%l)(%u)", "%1 %2"))
end

local function selectedCount()
    local n = 0
    for name, on in pairs(CONFIG.selected) do
        if on and CATALOG.byName[name] then
            n += 1
        end
    end
    return n
end

local function anySelected()
    return selectedCount() > 0
end

local function selectAll()
    CONFIG.selected = {}
    for _, name in ipairs(CATALOG.names) do
        CONFIG.selected[name] = true
    end
end

local function highestSelectedZone()
    for z = 12, 1, -1 do
        for _, entry in ipairs(CATALOG.byZone[z] or {}) do
            if CONFIG.selected[entry.name] then
                return z
            end
        end
    end
    return nil
end

local function zoneSelectedLabel(z)
    local parts = {}
    for _, entry in ipairs(CATALOG.byZone[z] or {}) do
        if CONFIG.selected[entry.name] then
            parts[#parts + 1] = prettyEgg(entry.name)
        end
    end
    return table.concat(parts, ", ")
end

local function allowed(egg)
    local name = egg:GetAttribute("EggInfoName")
    if type(name) ~= "string" then
        return false
    end
    return CONFIG.selected[name] == true
end

local function zoneName()
    local r = root()
    if not r then
        return "?"
    end
    local z = ZoneLookup.GetZoneAt(r.Position)
    if z == nil or z == "SafeZone" then
        return "Zone1"
    end
    return z
end

local function zoneHitbox(z)
    local build = Workspace:FindFirstChild("Build")
    local hb = build and build:FindFirstChild("ZoneHitboxes")
    local part = hb and hb:FindFirstChild(tostring(z))
    if part and part:IsA("BasePart") then
        return part
    end
    return nil
end

local function zoneAnchor(z)
    local part = zoneHitbox(z)
    if part then
        return Vector3.new(part.Position.X + 20, 4, part.Position.Z)
    end
    return Vector3.new(-106, 4, -1)
end

local function zoneStartX(z)
    local part = zoneHitbox(z)
    if not part then
        return nil
    end
    return part.Position.X + part.Size.X / 2
end

local function zoneSafeDist(zoneIndex)
    if CONFIG.guardSafeDist and CONFIG.guardSafeDist > 0 then
        return CONFIG.guardSafeDist
    end
    local part = zoneHitbox(zoneIndex)
    if not part then
        return 150
    end
    return math.clamp(part.Size.X / 2, 40, 500)
end

local function guardSafeDistFor()
    local z = tonumber(string.match(zoneName(), "%d+")) or 1
    return zoneSafeDist(z)
end

local function nearestGuard()
    local r = root()
    if not r then
        return nil, math.huge
    end
    local best, bestD = nil, math.huge
    for _, g in ipairs(CS:GetTagged("ZoneGuard")) do
        local ok, pivot = pcall(function()
            return g:GetPivot().Position
        end)
        if ok and pivot then
            local d = (pivot - r.Position).Magnitude
            if d < bestD then
                best, bestD = g, d
            end
        end
    end
    return best, bestD
end

local guardWait = { since = 0, retreatUntil = 0 }

local function guardAllows()
    if not CONFIG.guardGate then
        return true
    end
    local _, d = nearestGuard()
    state.guardDist = d
    local need = guardSafeDistFor()
    local now = os.clock()
    if d >= need then
        guardWait.since = 0
        return true
    end
    if guardWait.since == 0 then
        guardWait.since = now
    end
    if now - guardWait.since > 90 then
        guardWait.since = now
        return true
    end
    if now - guardWait.since > 30 then
        local r = root()
        local z = tonumber(string.match(zoneName(), "%d+")) or 1
        local startX = zoneStartX(z)
        if r and startX and now >= guardWait.retreatUntil then
            guardWait.retreatUntil = now + 4
            state.pathGoal = Vector3.new(startX - 15, r.Position.Y, r.Position.Z)
            state.stopRadius = 4
            state.moveTarget = state.pathGoal
        end
    else
        stopMove()
    end
    setStatus(string.format("Waiting for guard (%dm < %dm)", math.floor(d), math.floor(need)))
    task.wait(0.3)
    return false
end

local function dropZoneName()
    return CONFIG.dropArea == "safe" and "SafeZone" or "Zone1"
end

local function dropLabel()
    return CONFIG.dropArea == "safe" and "Safe Zone" or "Zone 1"
end

local function dropAnchor()
    if CONFIG.dropArea == "safe" then
        return Vector3.new(25, 38, 11)
    end
    return zoneAnchor(1)
end

local function petCps(model)
    local name = model:GetAttribute("AnimalName")
    if type(name) ~= "string" then
        return nil
    end
    local ok, value = pcall(function()
        return EggRewards.PlacedCashPerSecond(
            name,
            model:GetAttribute("SizeMult"),
            model:GetAttribute("Mutation"),
            model:GetAttribute("WeightKg"),
            model:GetAttribute("Variant")
        )
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function carriedModel()
    local folder = Workspace:FindFirstChild("CarriedAnimals")
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and child:GetAttribute("AnimalName") then
                return child
            end
        end
    end
    local ch = LP.Character
    if ch then
        for _, child in ipairs(ch:GetChildren()) do
            if child:IsA("Model") and child:GetAttribute("AnimalName") then
                return child
            end
        end
    end
    return nil
end

local function eggDepth(egg)
    local zone = egg:GetAttribute("ZoneIndex")
    local startX = zoneStartX(zone)
    if not startX then
        return math.huge
    end
    return startX - egg.Position.X
end

local function nearestEgg()
    local r = root()
    if not r then
        return nil, math.huge
    end
    local best, bestD, bestZone, bestDepth
    for _, egg in ipairs(CS:GetTagged("BreakableEgg")) do
        if egg:IsA("BasePart") and egg.Parent and EggTargeting.IsLive(egg) then
            if (blacklist[egg] or 0) < os.clock() and allowed(egg) then
                local zone = egg:GetAttribute("ZoneIndex")
                local d = EggTargeting.SurfaceDistance(egg, r.Position)
                local depth = CONFIG.zoneStart and eggDepth(egg) or nil
                local better = false
                if not bestZone or zone > bestZone then
                    better = true
                elseif zone == bestZone then
                    if depth and bestDepth then
                        if depth < bestDepth - 0.01 then
                            better = true
                        elseif math.abs(depth - bestDepth) <= 0.01 and d < bestD then
                            better = true
                        end
                    elseif d < bestD then
                        better = true
                    end
                end
                if better then
                    best, bestD, bestZone, bestDepth = egg, d, zone, depth
                end
            end
        end
    end
    return best, bestD
end

local function findWantedPet()
    local r = root()
    if not r then
        return nil
    end
    local best, bestD = nil, CONFIG.petScanRadius
    for _, m in ipairs(CS:GetTagged("AnimalPickup")) do
        if m:IsA("Model") and m.Parent and not m:GetAttribute("Despawning") then
            if (not ignored[m] or ignored[m] < os.clock()) and not inDroppedZone(m:GetPivot().Position) then
                local reserved = m:GetAttribute("ReservedUserId")
                if reserved == nil or reserved == LP.UserId then
                    local d = (m:GetPivot().Position - r.Position).Magnitude
                    if d < bestD then
                        local cps = petCps(m)
                        if cps and cps >= CONFIG.minCps and cps > 0 then
                            best, bestD = m, d
                        end
                    end
                end
            end
        end
    end
    return best, bestD
end

local function ignoreNear(pos, radius)
    for _, m in ipairs(CS:GetTagged("AnimalPickup")) do
        if (m:GetPivot().Position - pos).Magnitude <= radius then
            ignored[m] = os.clock() + 300
        end
    end
end

local function markDropped(pos)
    local now = os.clock()
    for i = #dropGuards, 1, -1 do
        if dropGuards[i].until_ < now then
            table.remove(dropGuards, i)
        end
    end
    dropGuards[#dropGuards + 1] = { pos = pos, radius = 30, until_ = now + 300 }
    ignoreNear(pos, 40)
end

function inDroppedZone(pos)
    local now = os.clock()
    for _, guard in ipairs(dropGuards) do
        if guard.until_ >= now and (pos - guard.pos).Magnitude <= guard.radius then
            return true
        end
    end
    return false
end

local function equipPickaxe()
    local ch, hum = alive()
    if not ch then
        return false
    end
    if ch:FindFirstChild("Pickaxe") then
        return true
    end
    local backpack = LP:FindFirstChild("Backpack")
    local tool = backpack and backpack:FindFirstChild("Pickaxe")
    if tool and tool:IsA("Tool") then
        hum:EquipTool(tool)
        task.wait(0.15)
    end
    return ch:FindFirstChild("Pickaxe") ~= nil
end

local function ensureSwing()
    if LP:GetAttribute("Carrying") ~= nil then
        return false
    end
    equipPickaxe()
    pcall(function()
        AutoSwing.SetOn(false)
    end)
    return true
end

local function walkTo(target, maxTime)
    local ch, hum = alive()
    if not ch or not hum then
        return false
    end
    maxTime = maxTime or 30
    local started = os.clock()
    state.stopRadius = 6
    state.pathGoal = target
    state.moveTarget = target
    local last = nil
    local stuck = 0
    while state.running and os.clock() - started <= maxTime do
        local p = root()
        if not p then
            break
        end
        if (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 8 then
            stopMove()
            return true
        end
        if last and (p.Position - last).Magnitude < 0.5 then
            stuck += 1
            if stuck >= 6 then
                hum.Jump = true
                stuck = 0
                state.debug.jumps += 1
            end
        else
            stuck = 0
        end
        last = p.Position
        task.wait(0.1)
    end
    stopMove()
    return false
end

local function pressE()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.45)
        vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

local function findStealPrompt(pos)
    local anchor = Workspace:FindFirstChild("PromptAnchor")
    if anchor then
        for _, child in ipairs(anchor:GetChildren()) do
            if child:IsA("ProximityPrompt") and child.Enabled then
                if child.Name == "StealPrompt" or child.ActionText == "Steal" then
                    local parent = child.Parent
                    if parent and parent:IsA("BasePart") and (parent.Position - pos).Magnitude < 8 then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

local function triggerPrompt(prompt)
    local ok = pcall(function()
        if firePrompt then
            firePrompt(prompt)
        else
            error("no fireproximityprompt")
        end
    end)
    if not ok then
        pcall(function()
            prompt:InputHoldBegin()
        end)
        task.wait((prompt.HoldDuration or 0.35) + 0.1)
        pcall(function()
            prompt:InputHoldEnd()
        end)
    end
end

local function flatten(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function steal(model)
    state.stopRadius = 3.2
    local deadline = os.clock() + 8
    local pos = nil
    while state.running and os.clock() < deadline do
        if LP:GetAttribute("Carrying") ~= nil then
            break
        end
        if not model.Parent then
            break
        end
        local r = root()
        if not r then
            break
        end
        local ok, pivot = pcall(function()
            return model:GetPivot().Position
        end)
        if not ok or not pivot then
            break
        end
        pos = pivot
        state.pathGoal = pivot
        state.moveTarget = pivot
        if (flatten(r.Position) - flatten(pivot)).Magnitude <= 3.2 then
            break
        end
        task.wait(0.05)
    end
    stopMove()
    if LP:GetAttribute("Carrying") ~= nil then
        return true
    end
    if not pos then
        return false
    end
    task.wait(0.2)
    for _ = 1, 3 do
        if LP:GetAttribute("Carrying") ~= nil then
            return true
        end
        local prompt = findStealPrompt(pos)
        if prompt then
            triggerPrompt(prompt)
            task.wait(0.4)
        else
            pressE()
            task.wait(0.4)
        end
    end
    return LP:GetAttribute("Carrying") ~= nil
end

local function dropCarried()
    state.intentionalDrop = true
    for _ = 1, 3 do
        if LP:GetAttribute("Carrying") == nil then
            state.intentionalDrop = false
            return true
        end
        pcall(function()
            DropCarriedRemote:FireServer()
        end)
        local deadline = os.clock() + 1.2
        while os.clock() < deadline do
            if LP:GetAttribute("Carrying") == nil then
                state.intentionalDrop = false
                return true
            end
            task.wait(0.1)
        end
    end
    local done = LP:GetAttribute("Carrying") == nil
    state.intentionalDrop = false
    return done
end

local updateStats

local function handleCarried()
    local model = carriedModel()
    local modelCps = model and petCps(model) or nil
    local cps = state.pendingCps or modelCps
    local r = root()
    if not r or LP:GetAttribute("Carrying") == nil then
        return
    end
    if model and model:GetAttribute("AnimalName") then
        state.carrySnapshot = { name = model:GetAttribute("AnimalName"), cps = cps }
    end
    state.debug.carry = {
        name = model and model.Name or "?",
        animal = model and tostring(model:GetAttribute("AnimalName")) or "nil",
        cps = cps,
        modelCps = modelCps,
        scanCps = state.pendingCps,
        zone = tostring(ZoneLookup.GetZoneAt(r.Position)),
        action = "?",
    }

    if cps and cps < CONFIG.minCps then
        state.debug.carry.action = "skipLow"
        setStatus(string.format("Pet %s below minimum - dropping here", model and model.Name or "?"))
        local p = r.Position
        if dropCarried() then
            markDropped(p)
            state.skipped += 1
            updateStats()
        end
        state.pendingCps = nil
        return
    end

    local targetZone = dropZoneName()
    local areaLabel = dropLabel()
    local hereZone = ZoneLookup.GetZoneAt(r.Position)
    if hereZone == targetZone then
        state.debug.carry.action = "dropHere"
        local p = r.Position
        if dropCarried() then
            state.dropped += 1
            state.lastDrop = string.format("%s %s/s", model and model.Name or "pet", fmt(cps or 0))
            markDropped(p)
            setStatus(string.format("Dropped %s in %s", model and model.Name or "pet", areaLabel))
            updateStats()
        end
        state.pendingCps = nil
        return
    end

    state.debug.carry.action = "walkHome"
    state.returnPos = r.Position
    setStatus(string.format("Carrying %s to %s...", model and model.Name or "pet", areaLabel))
    local anchor = dropAnchor()
    state.pathGoal = anchor
    state.moveTarget = anchor
    local started = os.clock()
    while state.running and os.clock() - started < 180 do
        if LP:GetAttribute("Carrying") == nil then
            break
        end
        state.moveTarget = anchor
        local p = root()
        if not p then
            break
        end
        if ZoneLookup.GetZoneAt(p.Position) == targetZone then
            break
        end
        task.wait(0.1)
    end
    stopMove()
    if LP:GetAttribute("Carrying") == nil then
        return
    end
    local p = root()
    if not p or ZoneLookup.GetZoneAt(p.Position) ~= targetZone then
        setStatus(string.format("Can't reach %s", areaLabel))
        return
    end
    if dropCarried() then
        state.dropped += 1
        state.lastDrop = string.format("%s %s/s", model and model.Name or "pet", fmt(cps or 0))
        markDropped(p.Position)
        setStatus(string.format("Dropped %s in %s", model and model.Name or "pet", areaLabel))
        updateStats()
    end
    state.pendingCps = nil
    task.wait(0.6)
    if state.returnPos then
        setStatus("Returning to farm...")
        walkTo(state.returnPos, 180)
        state.returnPos = nil
    end
end

local function waitRespawn()
    setStatus("Waiting for respawn...")
    local started = os.clock()
    while state.running and os.clock() - started < 40 do
        local ch, hum = alive()
        if ch and hum then
            break
        end
        task.wait(0.5)
    end
    task.wait(1)
end

function updateStats() end

local function farmStep(runId)
    if state.runId ~= runId or not state.running then
        return
    end
    local ch, hum = alive()
    if not ch or not hum then
        waitRespawn()
        return
    end

    if LP:GetAttribute("Carrying") ~= nil then
        handleCarried()
        return
    end


    if state.recover then
        if LP:GetAttribute("BeingChased") ~= nil or LP:GetAttribute("PumpkinKingChased") == true then
            setStatus("Chased - delaying pet recovery")
            state.pathGoal = dropAnchor()
            state.moveTarget = state.pathGoal
            task.wait(0.2)
            return
        end
        if os.clock() > state.recover.deadline then
            setStatus(string.format("Pet %s lost", state.recover.name))
            state.recover = nil
            return
        end
        local rr = root()
        if not rr then
            task.wait(0.2)
            return
        end
        local found, bestD = nil, math.huge
        for _, m in ipairs(CS:GetTagged("AnimalPickup")) do
            if m:IsA("Model") and m.Parent and not m:GetAttribute("Despawning") then
                if m:GetAttribute("AnimalName") == state.recover.name then
                    local reserved = m:GetAttribute("ReservedUserId")
                    if reserved == nil or reserved == LP.UserId then
                        local d = (m:GetPivot().Position - rr.Position).Magnitude
                        if d < bestD then
                            found, bestD = m, d
                        end
                    end
                end
            end
        end
        if found and bestD < 160 then
            setStatus(string.format("Recovering pet %s (%dm)", state.recover.name, math.floor(bestD)))
            if steal(found) then
                state.pendingCps = state.recover.cps
                state.carrySnapshot = { name = found.Name, cps = state.recover.cps }
                state.recover = nil
                setStatus(string.format("Pet %s recovered", found.Name))
            end
            return
        end
        local dist = (rr.Position - state.recover.pos).Magnitude
        if dist > 20 then
            setStatus("Returning for dropped pet...")
            state.pathGoal = state.recover.pos
            state.moveTarget = state.recover.pos
            task.wait(0.2)
            return
        end
        setStatus(string.format("Searching for pet %s...", state.recover.name))
        task.wait(0.5)
        return
    end

    if LP:GetAttribute("BeingChased") ~= nil or LP:GetAttribute("PumpkinKingChased") == true then
        setStatus("Chased - running...")
        state.pathGoal = dropAnchor()
        state.moveTarget = state.pathGoal
        task.wait(0.2)
        return
    end

    if state.gemJob then
        if not CONFIG.autoGems or os.clock() > state.gemJob.deadline then
            state.gemJob = nil
        else
            local folder = Workspace:FindFirstChild("EggGemDrops")
            local pieces = {}
            if folder then
                for _, piece in ipairs(folder:GetChildren()) do
                    if piece:IsA("BasePart") then
                        pieces[#pieces + 1] = piece
                    end
                end
            end
            if #pieces == 0 then
                if os.clock() - (state.gemJob.started or 0) > 0.8 then
                    state.gemJob = nil
                else
                    task.wait(0.1)
                    return
                end
            else
                local r = root()
                if not r then
                    task.wait(0.2)
                    return
                end
                local best, bestD = nil, math.huge
                for _, piece in ipairs(pieces) do
                    local d = (piece.Position - r.Position).Magnitude
                    if d < bestD then
                        best, bestD = piece, d
                    end
                end
                if best then
                    setStatus(string.format("Collecting gems (%dm)", math.floor(bestD)))
                    if bestD > 3 then
                        state.stopRadius = 3
                        state.pathGoal = best.Position
                        state.moveTarget = best.Position
                    else
                        stopMove()
                    end
                    task.wait(0.1)
                    return
                end
            end
        end
    end

    if not anySelected() then
        state.targetEgg = nil
        stopMove()
        setStatus("No eggs selected")
        task.wait(1)
        return
    end

    ensureSwing()

    local pet = findWantedPet()
    if pet then
        if not guardAllows() then
            return
        end
        state.pendingCps = petCps(pet)
        state.carrySnapshot = { name = pet:GetAttribute("AnimalName"), cps = state.pendingCps }
        state.debug.steal = {
            name = pet.Name,
            zone = tostring(ZoneLookup.GetZoneAt(pet:GetPivot().Position)),
            cps = state.pendingCps,
            min = CONFIG.minCps,
        }
        setStatus(string.format("Heading to pet %s...", pet.Name))
        if steal(pet) then
            setStatus("Pet caught - preparing to carry...")
        else
            ignored[pet] = os.clock() + 60
            state.pendingCps = nil
            setStatus("Pet steal failed - skipping")
        end
        return
    end

    local egg = state.targetEgg
    if not egg or not egg.Parent or not EggTargeting.IsLive(egg) or not allowed(egg) then
        egg = nil
        if not guardAllows() then
            return
        end
        if state.targetEgg then
            blacklist[state.targetEgg] = os.clock() + 30
            task.wait(0.12)
        end
        state.targetEgg = nearestEgg()
        egg = state.targetEgg
        if egg then
            state.targetDepth = eggDepth(egg)
            state.targetAt = os.clock()
            state.targetHp = egg:GetAttribute("Health")
            state.lastHpChange = os.clock()
            state.stallRepos = 0
            state.lastSwing = 0
            state.forceApproachUntil = nil
            state.moveAt = 0
        end
    end

    if not egg then
        local z = highestSelectedZone()
        local r0 = root()
        if z and r0 then
            local anchor = zoneAnchor(z)
            local flat = Vector3.new(r0.Position.X, 0, r0.Position.Z)
            local target = Vector3.new(anchor.X, 0, anchor.Z)
            local anchorDist = (flat - target).Magnitude
            if anchorDist > 60 then
                setStatus(string.format("Walking to Zone%d...", z))
                state.pathGoal = anchor
                state.moveTarget = anchor
                task.wait(0.2)
            else
                stopMove()
                setStatus(string.format("Waiting for %s in Zone%d", zoneSelectedLabel(z), z))
                task.wait(1)
            end
        else
            setStatus("No eggs available")
            task.wait(1)
        end
        return
    end

    local r = root()
    if not r then
        task.wait(0.2)
        return
    end
    local dist = EggTargeting.SurfaceDistance(egg, r.Position)
    setStatus(string.format(
        "Farming Zone%s · %s (%dm)",
        tostring(egg:GetAttribute("ZoneIndex") or "?"),
        egg:GetAttribute("EggInfoName") or "Egg",
        math.floor(dist)
    ))

    local forceApproach = state.forceApproachUntil and os.clock() < state.forceApproachUntil
    if dist > 5.5 or forceApproach then
        local away = r.Position - egg.Position
        away = Vector3.new(away.X, 0, away.Z)
        if away.Magnitude < 0.1 then
            away = Vector3.new(0, 0, 1)
        end
        local ring = math.max(egg.Size.X, egg.Size.Z) / 2 + 2.5
        local point = Vector3.new(egg.Position.X, egg.Position.Y, egg.Position.Z) + away.Unit * ring
        state.stopRadius = 1.5
        state.pathGoal = point
        state.moveTarget = point
        if forceApproach then
            state.forcePushUntil = os.clock() + 0.6
        end
        local ap = state.approach
        if not ap or ap.egg ~= egg then
            state.approach = { egg = egg, at = os.clock(), moved = 0, dist = dist, lastPos = r.Position, fails = 0 }
        else
            ap.moved += (r.Position - ap.lastPos).Magnitude
            ap.lastPos = r.Position
            if os.clock() - ap.at > 3 then
                if ap.moved > 15 and dist > ap.dist - 2 then
                    ap.fails += 1
                    state.orbits += 1
                    state.forcePushUntil = os.clock() + 0.9
                    if hum.FloorMaterial ~= Enum.Material.Air then
                        hum.Jump = true
                        state.debug.jumps += 1
                    end
                    if ap.fails >= 3 then
                        blacklist[egg] = os.clock() + 45
                        state.targetEgg = nil
                        state.approach = nil
                    end
                end
                ap.at = os.clock()
                ap.moved = 0
                ap.dist = dist
            end
        end
        task.wait(0.1)
    else
        state.approach = nil
        stopMove()
        local swung = false
        pcall(function()
            swung = PickaxeController.Swing(egg)
        end)
        if swung then
            state.swingCount += 1
        end
        task.wait(0.05)
    end

    local hp = egg:GetAttribute("Health")
    if type(hp) == "number" then
        if type(state.targetHp) ~= "number" or hp < state.targetHp then
            state.targetHp = hp
            state.lastHpChange = os.clock()
            state.stallRepos = 0
        elseif os.clock() - (state.lastHpChange or 0) > 20 then
            state.stallRepos = (state.stallRepos or 0) + 1
            state.lastHpChange = os.clock()
            if state.stallRepos >= 3 then
                blacklist[egg] = os.clock() + 60
                state.targetEgg = nil
            else
                state.forceApproachUntil = os.clock() + 1.2
            end
        end
    end
end

local function farmLoop(runId)
    setStatus("Starting...")
    ensureSwing()
    while state.running and state.runId == runId do
        local ok, err = pcall(farmStep, runId)
        if not ok then
            setStatus("Error: " .. tostring(err))
            task.wait(2)
        end
    end
    if state.runId == runId then
        setStatus("Stopped")
    end
end

local function loadConfig()
    local ok, data = pcall(function()
        if not isfile or not readfile then
            return nil
        end
        if not isfile(CONFIG_PATH) then
            return nil
        end
        return HttpService:JSONDecode(readfile(CONFIG_PATH))
    end)
    CONFIG.selected = {}
    if ok and type(data) == "table" then
        if type(data.minCps) == "number" then
            CONFIG.minCps = data.minCps
        end
        if data.dropArea == "safe" or data.dropArea == "zone1" then
            CONFIG.dropArea = data.dropArea
        end
        if type(data.autoGems) == "boolean" then
            CONFIG.autoGems = data.autoGems
        end
        if type(data.zoneStart) == "boolean" then
            CONFIG.zoneStart = data.zoneStart
        end
        if type(data.guardGate) == "boolean" then
            CONFIG.guardGate = data.guardGate
        end
        if type(data.guardSafeDist) == "number" then
            CONFIG.guardSafeDist = math.max(0, data.guardSafeDist)
        end
        if data.version == CONFIG_VERSION and type(data.selected) == "table" then
            for _, name in ipairs(data.selected) do
                if CATALOG.byName[name] then
                    CONFIG.selected[name] = true
                end
            end
        end
    end
end

function saveConfig()
    local list = {}
    for name, on in pairs(CONFIG.selected) do
        if on and CATALOG.byName[name] then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    pcall(function()
        if not writefile then
            return
        end
        writefile(CONFIG_PATH, HttpService:JSONEncode({
            version = CONFIG_VERSION,
            minCps = CONFIG.minCps,
            dropArea = CONFIG.dropArea,
            autoGems = CONFIG.autoGems,
            zoneStart = CONFIG.zoneStart,
            guardGate = CONFIG.guardGate,
            guardSafeDist = CONFIG.guardSafeDist,
            selected = list,
        }))
    end)
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function stroke(parent, color)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function text(parent, str, size, color, face)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Text = str
    label.TextSize = size
    label.TextColor3 = color
    label.Font = Enum.Font.Roboto
    if face then
        label.FontFace = face
    end
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
end

local function makeButton(parent, str, primary, height)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, height or 34)
    button.BackgroundColor3 = primary and COLORS.accent or COLORS.surface
    button.AutoButtonColor = false
    button.Text = str
    button.Font = Enum.Font.Roboto
    if FACE_MEDIUM then
        button.FontFace = FACE_MEDIUM
    end
    button.TextSize = 15
    button.TextColor3 = primary and COLORS.accentText or COLORS.text
    button.BorderSizePixel = 0
    button.Parent = parent
    corner(button, 6)
    if not primary then
        stroke(button, COLORS.border)
    end
    button:SetAttribute("baseColor", button.BackgroundColor3)
    button:SetAttribute("hoverColor", primary and Color3.fromRGB(230, 230, 230) or COLORS.surfaceHover)
    button:SetAttribute("pressColor", primary and Color3.fromRGB(200, 200, 200) or COLORS.border)
    local function tint(key, tween)
        local color = button:GetAttribute(key)
        if not color then
            return
        end
        if tween then
            TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
        else
            button.BackgroundColor3 = color
        end
    end
    button.MouseEnter:Connect(function()
        if button.Active then
            tint("hoverColor", true)
        end
    end)
    button.MouseLeave:Connect(function()
        if button.Active then
            tint("baseColor", true)
        end
    end)
    button.MouseButton1Down:Connect(function()
        if button.Active then
            tint("pressColor", false)
        end
    end)
    button.MouseButton1Up:Connect(function()
        if button.Active then
            tint("hoverColor", true)
        end
    end)
    return button
end

local function buildUI()
    local old = LP.PlayerGui:FindFirstChild("EggFarmerUI")
    if old then
        old:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "EggFarmerUI"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 50
    screen.Parent = LP:WaitForChild("PlayerGui")

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position = UDim2.new(1, -16, 0, 16)
    panel.Size = UDim2.new(0, 400, 0, 0)
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.BackgroundColor3 = COLORS.bg
    panel.BorderSizePixel = 0
    panel.Parent = screen
    corner(panel, 8)
    stroke(panel, COLORS.border)

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 16)
    padding.PaddingBottom = UDim.new(0, 16)
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.Parent = panel

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 12)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = panel

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 26)
    header.BackgroundTransparency = 1
    header.Active = true
    header.LayoutOrder = 1
    header.Parent = panel

    local title = text(header, "Ivyis Breaky Break", 20, COLORS.text, FACE_BOLD)
    title.Size = UDim2.new(1, -24, 1, 0)

    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(1, 0.5)
    dot.Position = UDim2.new(1, 0, 0.5, 0)
    dot.Size = UDim2.fromOffset(10, 10)
    dot.BackgroundColor3 = COLORS.muted
    dot.BorderSizePixel = 0
    dot.Parent = header
    corner(dot, 5)

    local statusLabel = text(panel, state.status, 14, COLORS.muted)
    statusLabel.Size = UDim2.new(1, 0, 0, 0)
    statusLabel.AutomaticSize = Enum.AutomaticSize.Y
    statusLabel.TextWrapped = true
    statusLabel.LayoutOrder = 2

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, 0, 0, 34)
    tabBar.BackgroundTransparency = 1
    tabBar.LayoutOrder = 3
    tabBar.Parent = panel

    local function makeTabButton(label, x)
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(76, 30)
        button.Position = UDim2.fromOffset(x, 0)
        button.BackgroundTransparency = 1
        button.Text = label
        button.Font = Enum.Font.Roboto
        if FACE_MEDIUM then
            button.FontFace = FACE_MEDIUM
        end
        button.TextSize = 14
        button.TextColor3 = COLORS.muted
        button.ZIndex = 2
        button.Parent = tabBar
        local underline = Instance.new("Frame")
        underline.AnchorPoint = Vector2.new(0, 1)
        underline.Position = UDim2.new(0, 0, 1, -2)
        underline.Size = UDim2.new(1, 0, 0, 2)
        underline.BackgroundColor3 = COLORS.accent
        underline.BorderSizePixel = 0
        underline.Visible = false
        underline.Parent = button
        return button, underline
    end
    local farmTabButton, farmUnderline = makeTabButton("Farm", 0)
    local dropTabButton, dropUnderline = makeTabButton("Drop", 84)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.BackgroundTransparency = 1
    content.LayoutOrder = 4
    content.Parent = panel
    local contentList = Instance.new("UIListLayout")
    contentList.Padding = UDim.new(0, 0)
    contentList.SortOrder = Enum.SortOrder.LayoutOrder
    contentList.Parent = content

    local farmTab = Instance.new("Frame")
    farmTab.Size = UDim2.new(1, 0, 0, 0)
    farmTab.AutomaticSize = Enum.AutomaticSize.Y
    farmTab.BackgroundTransparency = 1
    farmTab.LayoutOrder = 1
    farmTab.Parent = content
    local farmList = Instance.new("UIListLayout")
    farmList.Padding = UDim.new(0, 12)
    farmList.SortOrder = Enum.SortOrder.LayoutOrder
    farmList.Parent = farmTab

    local dropTab = Instance.new("Frame")
    dropTab.Size = UDim2.new(1, 0, 0, 0)
    dropTab.AutomaticSize = Enum.AutomaticSize.Y
    dropTab.BackgroundTransparency = 1
    dropTab.Visible = false
    dropTab.LayoutOrder = 2
    dropTab.Parent = content
    local dropList = Instance.new("UIListLayout")
    dropList.Padding = UDim.new(0, 12)
    dropList.SortOrder = Enum.SortOrder.LayoutOrder
    dropList.Parent = dropTab

    local closeAllDropdowns
    local activeTab = "farm"
    local function setTab(name)
        activeTab = name
        farmTab.Visible = name == "farm"
        dropTab.Visible = name == "drop"
        farmTabButton.TextColor3 = name == "farm" and COLORS.text or COLORS.muted
        dropTabButton.TextColor3 = name == "drop" and COLORS.text or COLORS.muted
        farmUnderline.Visible = name == "farm"
        dropUnderline.Visible = name == "drop"
        if closeAllDropdowns then
            closeAllDropdowns()
        end
    end
    farmTabButton.MouseButton1Click:Connect(function()
        setTab("farm")
    end)
    dropTabButton.MouseButton1Click:Connect(function()
        setTab("drop")
    end)

    local minRow = Instance.new("Frame")
    minRow.Size = UDim2.new(1, 0, 0, 38)
    minRow.BackgroundTransparency = 1
    minRow.LayoutOrder = 1
    minRow.Parent = farmTab

    local minLabel = text(minRow, "Min $/s", 14, COLORS.muted)
    minLabel.Size = UDim2.new(0, 76, 1, 0)

    local minBox = Instance.new("TextBox")
    minBox.Size = UDim2.new(1, -76, 1, 0)
    minBox.Position = UDim2.new(0, 76, 0, 0)
    minBox.BackgroundColor3 = COLORS.surface
    minBox.BorderSizePixel = 0
    minBox.Text = fmt(CONFIG.minCps)
    minBox.PlaceholderText = "0"
    minBox.TextColor3 = COLORS.text
    minBox.PlaceholderColor3 = COLORS.muted
    minBox.TextSize = 15
    minBox.Font = Enum.Font.Roboto
    if FACE_REGULAR then
        minBox.FontFace = FACE_REGULAR
    end
    minBox.TextXAlignment = Enum.TextXAlignment.Left
    minBox.ClearTextOnFocus = false
    minBox.Parent = minRow
    corner(minBox, 6)
    local minStroke = stroke(minBox, COLORS.border)
    local minPad = Instance.new("UIPadding")
    minPad.PaddingLeft = UDim.new(0, 10)
    minPad.PaddingRight = UDim.new(0, 10)
    minPad.Parent = minBox

    local eggButton = makeButton(farmTab, "Eggs: none selected", false, 40)
    eggButton.LayoutOrder = 2
    eggButton.TextXAlignment = Enum.TextXAlignment.Left
    eggButton.TextSize = 15
    local eggPad = Instance.new("UIPadding")
    eggPad.PaddingLeft = UDim.new(0, 12)
    eggPad.Parent = eggButton

    local eggChevron = text(eggButton, "v", 13, COLORS.text, FACE_MEDIUM)
    eggChevron.AnchorPoint = Vector2.new(1, 0.5)
    eggChevron.Position = UDim2.new(1, -12, 0.5, 0)
    eggChevron.Size = UDim2.fromOffset(18, 22)
    eggChevron.TextXAlignment = Enum.TextXAlignment.Center

    local gemRow = Instance.new("Frame")
    gemRow.Size = UDim2.new(1, 0, 0, 34)
    gemRow.BackgroundTransparency = 1
    gemRow.LayoutOrder = 3
    gemRow.Parent = farmTab

    local gemLabel = text(gemRow, "Auto collect gems", 14, COLORS.muted)
    gemLabel.Size = UDim2.new(1, -80, 1, 0)

    local gemToggle = makeButton(gemRow, CONFIG.autoGems and "On" or "Off", false, 30)
    gemToggle.Size = UDim2.fromOffset(70, 30)
    gemToggle.AnchorPoint = Vector2.new(1, 0.5)
    gemToggle.Position = UDim2.new(1, 0, 0.5, 0)
    gemToggle.TextSize = 13

    local dropRow = Instance.new("Frame")
    dropRow.Size = UDim2.new(1, 0, 0, 38)
    dropRow.BackgroundTransparency = 1
    dropRow.LayoutOrder = 1
    dropRow.Parent = dropTab

    local dropRowLabel = text(dropRow, "Drop area", 14, COLORS.muted)
    dropRowLabel.Size = UDim2.new(0, 96, 1, 0)

    local dropButton = makeButton(dropRow, dropLabel(), false, 38)
    dropButton.Size = UDim2.new(1, -96, 1, 0)
    dropButton.Position = UDim2.fromOffset(96, 0)
    dropButton.TextXAlignment = Enum.TextXAlignment.Left
    dropButton.TextSize = 15
    local dropPad = Instance.new("UIPadding")
    dropPad.PaddingLeft = UDim.new(0, 12)
    dropPad.Parent = dropButton
    local dropChevron = text(dropButton, "v", 13, COLORS.text, FACE_MEDIUM)
    dropChevron.AnchorPoint = Vector2.new(1, 0.5)
    dropChevron.Position = UDim2.new(1, -12, 0.5, 0)
    dropChevron.Size = UDim2.fromOffset(18, 22)
    dropChevron.TextXAlignment = Enum.TextXAlignment.Center

    local dropHelp = text(dropTab, "Pets at or above the minimum CPS are dropped when you enter the selected area.", 13, COLORS.muted)
    dropHelp.Size = UDim2.new(1, 0, 0, 0)
    dropHelp.AutomaticSize = Enum.AutomaticSize.Y
    dropHelp.TextWrapped = true
    dropHelp.LayoutOrder = 2

    local zoneRow = Instance.new("Frame")
    zoneRow.Size = UDim2.new(1, 0, 0, 34)
    zoneRow.BackgroundTransparency = 1
    zoneRow.LayoutOrder = 4
    zoneRow.Parent = farmTab

    local zoneLabel = text(zoneRow, "Start-zone eggs first", 14, COLORS.muted)
    zoneLabel.Size = UDim2.new(1, -80, 1, 0)

    local zoneToggle = makeButton(zoneRow, CONFIG.zoneStart and "On" or "Off", false, 30)
    zoneToggle.Size = UDim2.fromOffset(70, 30)
    zoneToggle.AnchorPoint = Vector2.new(1, 0.5)
    zoneToggle.Position = UDim2.new(1, 0, 0.5, 0)
    zoneToggle.TextSize = 13

    local errorLabel = text(farmTab, "", 13, COLORS.text)
    errorLabel.Size = UDim2.new(1, 0, 0, 0)
    errorLabel.AutomaticSize = Enum.AutomaticSize.Y
    errorLabel.TextWrapped = true
    errorLabel.Visible = false
    errorLabel.LayoutOrder = 5

    local toggleButton = makeButton(farmTab, "Start", true, 44)
    toggleButton.LayoutOrder = 6
    toggleButton.TextSize = 16
    local toggleStroke = stroke(toggleButton, COLORS.text)
    toggleStroke.Transparency = 1

    local keyHint = text(panel, "F hide · K start · Tab switch", 12, COLORS.muted)
    keyHint.Size = UDim2.new(1, 0, 0, 16)
    keyHint.LayoutOrder = 5

    local catcher = Instance.new("TextButton")
    catcher.Size = UDim2.fromScale(1, 1)
    catcher.BackgroundTransparency = 1
    catcher.Text = ""
    catcher.AutoButtonColor = false
    catcher.BorderSizePixel = 0
    catcher.Visible = false
    catcher.ZIndex = 60
    catcher.Parent = screen

    local dropdown = Instance.new("Frame")
    dropdown.Visible = false
    dropdown.BackgroundColor3 = COLORS.bg
    dropdown.BorderSizePixel = 0
    dropdown.ClipsDescendants = true
    dropdown.ZIndex = 70
    dropdown.Parent = screen
    corner(dropdown, 8)
    stroke(dropdown, COLORS.border)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -58)
    scroll.Position = UDim2.fromOffset(8, 8)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = COLORS.muted
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ZIndex = 71
    scroll.Parent = dropdown

    local scrollList = Instance.new("UIListLayout")
    scrollList.Padding = UDim.new(0, 1)
    scrollList.SortOrder = Enum.SortOrder.LayoutOrder
    scrollList.Parent = scroll

    local scrollPad = Instance.new("UIPadding")
    scrollPad.PaddingLeft = UDim.new(0, 2)
    scrollPad.PaddingRight = UDim.new(0, 6)
    scrollPad.PaddingBottom = UDim.new(0, 4)
    scrollPad.Parent = scroll

    local footer = Instance.new("Frame")
    footer.AnchorPoint = Vector2.new(0, 1)
    footer.Position = UDim2.new(0, 8, 1, -8)
    footer.Size = UDim2.new(1, -16, 0, 36)
    footer.BackgroundTransparency = 1
    footer.ZIndex = 71
    footer.Parent = dropdown

    local clearButton = makeButton(footer, "Clear all", false, 32)
    clearButton.Size = UDim2.fromOffset(140, 32)
    clearButton.Position = UDim2.fromOffset(0, 2)
    clearButton.TextSize = 13
    clearButton.ZIndex = 72

    local closeButton = makeButton(footer, "Close", false, 32)
    closeButton.Size = UDim2.fromOffset(76, 32)
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, 0, 0, 2)
    closeButton.TextSize = 13
    closeButton.ZIndex = 72

    local function makeCheck(container)
        local box = Instance.new("Frame")
        box.AnchorPoint = Vector2.new(0, 0.5)
        box.Position = UDim2.new(0, 2, 0.5, 0)
        box.Size = UDim2.fromOffset(20, 20)
        box.BackgroundColor3 = COLORS.surface
        box.BorderSizePixel = 0
        box.Parent = container
        corner(box, 5)
        local boxStroke = stroke(box, COLORS.border)
        local tick = text(box, "✓", 14, COLORS.accentText, FACE_BOLD)
        tick.Size = UDim2.fromScale(1, 1)
        tick.TextXAlignment = Enum.TextXAlignment.Center
        tick.Visible = false
        return box, boxStroke, tick
    end

    local function paintRow(entry, row, box, boxStroke, tick, nameLabel)
        local on = CONFIG.selected[entry.name] == true
        box.BackgroundColor3 = on and COLORS.accent or COLORS.surface
        boxStroke.Color = on and COLORS.accent or COLORS.border
        tick.Visible = on
        nameLabel.TextColor3 = COLORS.text
        row.Active = true
    end

    local renderList
    local zoneButtons = {}
    function renderList()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("Frame") or child:IsA("TextButton") then
                child:Destroy()
            end
        end
        zoneButtons = {}
        local order = 0
        for z = 1, 12 do
            order += 1
            local header = Instance.new("Frame")
            header.Size = UDim2.new(1, 0, 0, 28)
            header.BackgroundTransparency = 1
            header.LayoutOrder = order
            header.Parent = scroll
            local zoneLabel = text(header, "Zone " .. z, 13, COLORS.muted, FACE_MEDIUM)
            zoneLabel.Size = UDim2.new(1, -84, 1, 0)
            local allOn = true
            for _, entry in ipairs(CATALOG.byZone[z] or {}) do
                if not CONFIG.selected[entry.name] then
                    allOn = false
                    break
                end
            end
            local zoneButton = Instance.new("TextButton")
            zoneButton.Size = UDim2.fromOffset(80, 22)
            zoneButton.AnchorPoint = Vector2.new(1, 0.5)
            zoneButton.Position = UDim2.new(1, 0, 0.5, 0)
            zoneButton.BackgroundTransparency = 1
            zoneButton.Text = allOn and "Clear" or "Select all"
            zoneButton.Font = Enum.Font.Roboto
            if FACE_REGULAR then
                zoneButton.FontFace = FACE_REGULAR
            end
            zoneButton.TextSize = 12
            zoneButton.TextColor3 = COLORS.accent
            zoneButton.ZIndex = 72
            zoneButton.Parent = header
            zoneButtons[z] = zoneButton
            zoneButton.MouseButton1Click:Connect(function()
                local turnOn = not allOn
                for _, entry in ipairs(CATALOG.byZone[z] or {}) do
                    CONFIG.selected[entry.name] = turnOn and true or nil
                end
                saveConfig()
                renderList()
                if ui then
                    ui.setError(nil)
                    ui.refreshEggButton()
                end
            end)

            for _, entry in ipairs(CATALOG.byZone[z] or {}) do
                order += 1
                local row = Instance.new("TextButton")
                row.Size = UDim2.new(1, 0, 0, 32)
                row.BackgroundTransparency = 1
                row.AutoButtonColor = false
                row.Text = ""
                row.BorderSizePixel = 0
                row.LayoutOrder = order
                row.ZIndex = 72
                row.Parent = scroll
                local box, boxStroke, tick = makeCheck(row)
                local nameLabel = text(row, prettyEgg(entry.name), 15, COLORS.text)
                nameLabel.Size = UDim2.new(1, -32, 1, 0)
                nameLabel.Position = UDim2.fromOffset(32, 0)
                nameLabel.ZIndex = 72
                paintRow(entry, row, box, boxStroke, tick, nameLabel)
                row.MouseEnter:Connect(function()
                    if row.Active then
                        row.BackgroundColor3 = COLORS.surface
                        row.BackgroundTransparency = 0
                    end
                end)
                row.MouseLeave:Connect(function()
                    row.BackgroundColor3 = COLORS.bg
                    row.BackgroundTransparency = 1
                end)
                row.MouseButton1Click:Connect(function()
                    if CONFIG.selected[entry.name] then
                        CONFIG.selected[entry.name] = nil
                    else
                        CONFIG.selected[entry.name] = true
                    end
                    saveConfig()
                    paintRow(entry, row, box, boxStroke, tick, nameLabel)
                    local anyOff = false
                    for _, other in ipairs(CATALOG.byZone[z] or {}) do
                        if not CONFIG.selected[other.name] then
                            anyOff = true
                            break
                        end
                    end
                    local zoneButtonRef = zoneButtons[z]
                    if zoneButtonRef then
                        zoneButtonRef.Text = anyOff and "Select all" or "Clear"
                    end
                    if ui then
                        ui.setError(nil)
                        ui.refreshEggButton()
                    end
                end)
            end
        end
    end

    local function closeDropdown()
        dropdown.Visible = false
        catcher.Visible = false
    end

    local function openDropdown()
        if closeAllDropdowns then
            closeAllDropdowns()
        end
        local abs = eggButton.AbsolutePosition
        local size = eggButton.AbsoluteSize
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local panelLeft = abs.X - 16
        local leftSpace = panelLeft - 8
        local width = panel.AbsoluteSize.X
        local x, y
        if leftSpace >= 340 then
            width = math.min(width, leftSpace)
            x, y = panelLeft - width - 8, math.max(12, abs.Y - 6)
        else
            width = math.min(width, viewport.X - 16)
            x = math.clamp(abs.X, 8, math.max(8, viewport.X - width - 8))
            y = abs.Y + size.Y + 6
        end
        local height = math.clamp(viewport.Y - y - 16, 200, 460)
        dropdown.Position = UDim2.fromOffset(x, y)
        dropdown.Size = UDim2.fromOffset(width, height)
        renderList()
        dropdown.Visible = true
        catcher.Visible = true
        task.delay(0.1, function()
            if dropdown.Visible then
                scroll.CanvasPosition = Vector2.zero
            end
        end)
    end

    local dropDropdown = Instance.new("Frame")
    dropDropdown.Visible = false
    dropDropdown.BackgroundColor3 = COLORS.bg
    dropDropdown.BorderSizePixel = 0
    dropDropdown.ZIndex = 70
    dropDropdown.Parent = screen
    corner(dropDropdown, 8)
    stroke(dropDropdown, COLORS.border)
    local dropListLayout = Instance.new("UIListLayout")
    dropListLayout.Padding = UDim.new(0, 2)
    dropListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    dropListLayout.Parent = dropDropdown
    local dropDropdownPad = Instance.new("UIPadding")
    dropDropdownPad.PaddingTop = UDim.new(0, 6)
    dropDropdownPad.PaddingBottom = UDim.new(0, 6)
    dropDropdownPad.PaddingLeft = UDim.new(0, 6)
    dropDropdownPad.PaddingRight = UDim.new(0, 6)
    dropDropdownPad.Parent = dropDropdown

    local dropOptions = {}
    local function refreshDropOptions()
        for value, row in pairs(dropOptions) do
            local active = CONFIG.dropArea == value
            row.TextColor3 = active and COLORS.text or COLORS.muted
            local check = row:FindFirstChild("Check")
            if check then
                check.Visible = active
            end
        end
    end

    local closeDropDropdown

    local function makeDropOption(value, label, order)
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundTransparency = 1
        row.AutoButtonColor = false
        row.Text = label
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Font = Enum.Font.Roboto
        if FACE_REGULAR then
            row.FontFace = FACE_REGULAR
        end
        row.TextSize = 15
        row.TextColor3 = COLORS.muted
        row.LayoutOrder = order
        row.ZIndex = 71
        row.Parent = dropDropdown
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.Parent = row
        local check = text(row, "✓", 13, COLORS.text, FACE_BOLD)
        check.Name = "Check"
        check.AnchorPoint = Vector2.new(1, 0.5)
        check.Position = UDim2.new(1, -10, 0.5, 0)
        check.Size = UDim2.fromOffset(18, 18)
        check.TextXAlignment = Enum.TextXAlignment.Center
        check.Visible = false
        dropOptions[value] = row
        row.MouseEnter:Connect(function()
            row.BackgroundColor3 = COLORS.surface
            row.BackgroundTransparency = 0
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundColor3 = COLORS.bg
            row.BackgroundTransparency = 1
        end)
        row.MouseButton1Click:Connect(function()
            CONFIG.dropArea = value
            saveConfig()
            dropButton.Text = dropLabel()
            refreshDropOptions()
            closeDropDropdown()
            if ui then
                ui.setError(nil)
            end
        end)
        return row
    end
    makeDropOption("zone1", "Zone 1", 1)
    makeDropOption("safe", "Safe Zone", 2)

    function closeDropDropdown()
        dropDropdown.Visible = false
        catcher.Visible = false
    end

    local function openDropDropdown()
        if closeAllDropdowns then
            closeAllDropdowns()
        end
        local abs = dropButton.AbsolutePosition
        local size = dropButton.AbsoluteSize
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local width = math.min(math.max(size.X, 180), viewport.X - 16)
        local x = math.clamp(abs.X, 8, math.max(8, viewport.X - width - 8))
        local height = 2 * 34 + 12
        local y = abs.Y + size.Y + 6
        if y + height > viewport.Y - 8 then
            y = math.max(8, abs.Y - height - 6)
        end
        dropDropdown.Position = UDim2.fromOffset(x, y)
        dropDropdown.Size = UDim2.fromOffset(width, height)
        refreshDropOptions()
        dropDropdown.Visible = true
        catcher.Visible = true
    end

    closeAllDropdowns = function()
        dropdown.Visible = false
        dropDropdown.Visible = false
        catcher.Visible = false
    end

    dropButton.MouseButton1Click:Connect(function()
        if dropDropdown.Visible then
            closeDropDropdown()
        else
            openDropDropdown()
        end
    end)
    refreshDropOptions()
    setTab(activeTab)

    catcher.MouseButton1Click:Connect(closeAllDropdowns)
    closeButton.MouseButton1Click:Connect(closeDropdown)
    clearButton.MouseButton1Click:Connect(function()
        CONFIG.selected = {}
        saveConfig()
        renderList()
        if ui then
            ui.setError(nil)
            ui.refreshEggButton()
        end
    end)
    eggButton.MouseButton1Click:Connect(function()
        if dropdown.Visible then
            closeDropdown()
        else
            openDropdown()
        end
    end)

    local dragging = false
    local dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            closeDropdown()
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
            local delta = input.Position - dragStart
            local anchorX = viewport.X * startPos.X.Scale + startPos.X.Offset + delta.X
            local minX = panel.AbsoluteSize.X + 8
            local maxX = math.max(minX, viewport.X - 8)
            anchorX = math.clamp(anchorX, minX, maxX)
            local anchorY = math.clamp(startPos.Y.Offset + delta.Y, 8, math.max(8, viewport.Y - 80))
            panel.Position = UDim2.new(startPos.X.Scale, anchorX - viewport.X * startPos.X.Scale, startPos.Y.Scale, anchorY)
        end
    end))

    ui = {}
    function ui.setStatus(str)
        statusLabel.Text = str
        dot.BackgroundColor3 = state.running and COLORS.accent or COLORS.muted
    end
    function ui.setError(str)
        errorLabel.Text = str or ""
        errorLabel.Visible = str ~= nil and str ~= ""
    end
    function ui.refreshEggButton()
        local n = selectedCount()
        if n == 0 then
            eggButton.Text = "Eggs: none selected"
        else
            eggButton.Text = string.format("Eggs: %d selected", n)
        end
    end
    function ui.refresh()
        minBox.Text = fmt(CONFIG.minCps)
        toggleButton.Text = state.running and "Stop" or "Start"
        local base, hover, press
        if state.running then
            base = COLORS.surface
            hover = COLORS.surfaceHover
            press = COLORS.border
            toggleButton.TextColor3 = COLORS.text
            toggleStroke.Color = COLORS.text
            toggleStroke.Transparency = 0
        else
            base = COLORS.accent
            hover = Color3.fromRGB(230, 230, 230)
            press = Color3.fromRGB(200, 200, 200)
            toggleButton.TextColor3 = COLORS.accentText
            toggleStroke.Transparency = 1
        end
        toggleButton:SetAttribute("baseColor", base)
        toggleButton:SetAttribute("hoverColor", hover)
        toggleButton:SetAttribute("pressColor", press)
        toggleButton.BackgroundColor3 = base
        dot.BackgroundColor3 = state.running and COLORS.accent or COLORS.muted
        gemToggle.Text = CONFIG.autoGems and "On" or "Off"
        local gemBase = CONFIG.autoGems and COLORS.accent or COLORS.surface
        local gemHover = CONFIG.autoGems and Color3.fromRGB(230, 230, 230) or COLORS.surfaceHover
        local gemPress = CONFIG.autoGems and Color3.fromRGB(200, 200, 200) or COLORS.border
        gemToggle:SetAttribute("baseColor", gemBase)
        gemToggle:SetAttribute("hoverColor", gemHover)
        gemToggle:SetAttribute("pressColor", gemPress)
        gemToggle.BackgroundColor3 = gemBase
        gemToggle.TextColor3 = CONFIG.autoGems and COLORS.accentText or COLORS.text
        local function styleToggle(button, on)
            local b = on and COLORS.accent or COLORS.surface
            local h = on and Color3.fromRGB(230, 230, 230) or COLORS.surfaceHover
            local p = on and Color3.fromRGB(200, 200, 200) or COLORS.border
            button:SetAttribute("baseColor", b)
            button:SetAttribute("hoverColor", h)
            button:SetAttribute("pressColor", p)
            button.BackgroundColor3 = b
            button.TextColor3 = on and COLORS.accentText or COLORS.text
            button.Text = on and "On" or "Off"
        end
        styleToggle(zoneToggle, CONFIG.zoneStart)
        dropButton.Text = dropLabel()
        refreshDropOptions()
        ui.refreshEggButton()
    end
    ui.renderList = function()
        renderList()
    end
    ui.openDropdown = openDropdown
    ui.closeDropdown = closeAllDropdowns
    ui.setTab = setTab
    ui.toggleVisible = function()
        screen.Enabled = not screen.Enabled
        if not screen.Enabled then
            closeAllDropdowns()
        end
    end
    ui.closeDropDropdown = function()
        closeDropDropdown()
    end
    ui.openDropDropdown = openDropDropdown
    ui.getTab = function()
        return activeTab
    end
    ui.isVisible = function()
        return screen.Enabled
    end

    minBox.Focused:Connect(function()
        minStroke.Color = COLORS.accent
    end)
    minBox.FocusLost:Connect(function()
        minStroke.Color = COLORS.border
        local n = parseNumber(minBox.Text)
        if not n or n < 0 then
            ui.setError("Invalid min $/s")
            minBox.Text = fmt(CONFIG.minCps)
            return
        end
        ui.setError(nil)
        api.setMin(n)
    end)

    gemToggle.MouseButton1Click:Connect(function()
        api.setAutoGems(not CONFIG.autoGems)
    end)

    zoneToggle.MouseButton1Click:Connect(function()
        api.setZoneStart(not CONFIG.zoneStart)
    end)

    toggleButton.MouseButton1Click:Connect(function()
        closeAllDropdowns()
        api.toggle()
    end)

    track(UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed and input.KeyCode ~= Enum.KeyCode.Tab then
            return
        end
        local focused = false
        pcall(function()
            focused = UIS:GetFocusedTextBox() ~= nil
        end)
        if focused then
            return
        end
        if input.KeyCode == Enum.KeyCode.F then
            ui.toggleVisible()
        elseif input.KeyCode == Enum.KeyCode.K then
            api.toggle()
        elseif input.KeyCode == Enum.KeyCode.Tab and screen.Enabled then
            setTab(activeTab == "farm" and "drop" or "farm")
        end
    end))

    ui.refresh()
    return screen
end

function api.setMin(n)
    CONFIG.minCps = math.max(0, n or 0)
    saveConfig()
    if ui then
        ui.refresh()
    end
end

function api.setDropArea(area)
    if area == "safe" or area == "zone1" then
        CONFIG.dropArea = area
        saveConfig()
        if ui then
            ui.refresh()
        end
    end
end

function api.setAutoGems(value)
    CONFIG.autoGems = value == true
    saveConfig()
    if ui then
        ui.refresh()
    end
end

function api.setZoneStart(value)
    CONFIG.zoneStart = value == true
    saveConfig()
    if ui then
        ui.refresh()
    end
end

function api.setGuardGate(value)
    CONFIG.guardGate = value == true
    saveConfig()
    if ui then
        ui.refresh()
    end
end

function api.setGuardSafeDist(value)
    CONFIG.guardSafeDist = math.max(0, tonumber(value) or 0)
    saveConfig()
    if ui then
        ui.refresh()
    end
end

function api.selectAll()
    selectAll()
    saveConfig()
    if ui then
        ui.refreshEggButton()
        if ui.renderList then
            ui.renderList()
        end
    end
end

function api.clearSelection()
    CONFIG.selected = {}
    saveConfig()
    if ui then
        ui.refreshEggButton()
        if ui.renderList then
            ui.renderList()
        end
    end
end

function api.setEggs(names)
    CONFIG.selected = {}
    if type(names) == "table" then
        for _, name in ipairs(names) do
            if CATALOG.byName[name] then
                CONFIG.selected[name] = true
            end
        end
    end
    saveConfig()
    if ui then
        ui.refreshEggButton()
        if ui.renderList then
            ui.renderList()
        end
    end
end

function api.start()
    if state.running then
        return
    end
    if not root() then
        ui.setError("Not spawned")
        return
    end
    if not anySelected() then
        ui.setError("No eggs selected")
        return
    end
    ui.setError(nil)
    state.runId += 1
    local runId = state.runId
    state.running = true
    state.dropped = 0
    state.skipped = 0
    state.lastDrop = "-"
    state.targetEgg = nil
    state.returnPos = nil
    state.swingCount = 0
    state.orbits = 0
    state.approach = nil
    state.pathGoal = nil
    updateStats()
    if ui then
        ui.refresh()
    end
    task.spawn(function()
        local ok, err = pcall(farmLoop, runId)
        if not ok then
            setStatus("Error: " .. tostring(err))
        end
        if state.runId == runId then
            state.running = false
            if ui then
                ui.refresh()
            end
        end
    end)
end

function api.stop()
    state.running = false
    state.runId += 1
    state.targetEgg = nil
    state.lastSwing = nil
    state.forceApproachUntil = nil
    state.gemJob = nil
    state.approach = nil
    state.forcePushUntil = 0
    state.pathGoal = nil
    stopMove()
    setStatus("Stopped")
    pcall(function()
        AutoSwing.SetOn(false)
    end)
    if ui then
        ui.refresh()
    end
end

function api.toggle()
    if state.running then
        api.stop()
    else
        api.start()
    end
end

function api.getState()
    return {
        running = state.running,
        status = state.status,
        zone = zoneName(),
        minCps = CONFIG.minCps,
        selectedCount = selectedCount(),
        dropped = state.dropped,
        skipped = state.skipped,
        dropZone = dropZoneName(),
        dropArea = CONFIG.dropArea,
        autoGems = CONFIG.autoGems,
        zoneStart = CONFIG.zoneStart,
        guardGate = CONFIG.guardGate,
        guardSafeDist = guardSafeDistFor(),
        recovering = state.recover ~= nil,
        recoverName = state.recover and state.recover.name or nil,
        targetName = state.targetEgg and state.targetEgg:GetAttribute("EggInfoName") or nil,
        targetHp = state.targetEgg and state.targetEgg:GetAttribute("Health") or nil,
        targetDepth = state.targetDepth,
        guardDist = state.guardDist,
        swings = state.swingCount,
        orbits = state.orbits,
        carrying = tostring(LP:GetAttribute("Carrying")),
        steal = state.debug.steal,
        carryInfo = state.debug.carry,
        jumps = state.debug.jumps,
    }
end

loadConfig()
buildUI()
getgenv().EggFarmer = api
getgenv().EggFarmerUI = ui
