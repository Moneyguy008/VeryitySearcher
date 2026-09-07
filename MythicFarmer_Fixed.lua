--[[
    Verity Autofarm
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Moneyguy008/VeryitySearcher/main/MythicFarmer_Fixed.lua"))()
--]]

if getgenv().MythicFarmerLoaded then return end
getgenv().MythicFarmerLoaded = true

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

local SCRIPT_URL = "https://raw.githubusercontent.com/Moneyguy008/VeryitySearcher/main/MythicFarmer_Fixed.lua"

local queueteleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
    or (Wave and Wave.queue_on_teleport)

local REEXEC_PAYLOAD = 'repeat task.wait() until game:IsLoaded() task.wait(1) loadstring(game:HttpGet("' .. SCRIPT_URL .. '"))()'

-- ── Persistent state ────────────────────────────────────────────────────────
local STATE_FOLDER = "MythicFarmer"
local STATE_FILE   = STATE_FOLDER .. "/state.txt"
local VISITED_FILE = STATE_FOLDER .. "/visited.txt"
local MAX_VISITED  = 20

local function saveState(on)
    pcall(function()
        if not isfolder(STATE_FOLDER) then makefolder(STATE_FOLDER) end
        writefile(STATE_FILE, on and "ON" or "OFF")
    end)
end

local function loadState()
    local ok, result = pcall(function()
        if isfile and isfile(STATE_FILE) then return readfile(STATE_FILE) == "ON" end
        return false
    end)
    return ok and result or false
end

-- Track recently visited servers so we never rejoin them
local visitedServers = {}

local function loadVisited()
    pcall(function()
        if isfile and isfile(VISITED_FILE) then
            local raw = readfile(VISITED_FILE)
            for id in raw:gmatch("[^\n]+") do
                visitedServers[id] = true
            end
        end
    end)
end

local function saveVisited()
    pcall(function()
        if not isfolder(STATE_FOLDER) then makefolder(STATE_FOLDER) end
        -- Collect keys, keep only the most recent MAX_VISITED
        local ids = {}
        for id in pairs(visitedServers) do table.insert(ids, id) end
        while #ids > MAX_VISITED do table.remove(ids, 1) end
        writefile(VISITED_FILE, table.concat(ids, "\n"))
    end)
end

-- Mark the current server as visited on load
loadVisited()
visitedServers[game.JobId] = true
saveVisited()

local autoStart = loadState()

-- ── Rayfield Gen2 ───────────────────────────────────────────────────────────
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")

local SAFE_ZONE = Vector3.new(-121.91282653808594, 13.358054161071777, -144.80528259277344)

local running    = false
local statusText = nil
local farmToggle = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function setStatus(msg)
    if statusText then statusText:Set(tostring(msg)) end
end

local function refreshChar()
    char = lp.Character or lp.CharacterAdded:Wait()
    hrp  = char:WaitForChild("HumanoidRootPart")
end

local function tpTo(pos)
    refreshChar()
    hrp.CFrame = CFrame.new(pos)
    task.wait(0.15)
end

local function modelPosition(model)
    if model.PrimaryPart then return model.PrimaryPart.Position end
    local parts, sum = {}, Vector3.new(0, 0, 0)
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then
            table.insert(parts, v.Position)
            sum = sum + v.Position
        end
    end
    if #parts == 0 then return Vector3.new(0, 0, 0) end
    return sum / #parts
end

local collectedBoxes = {}

local function isBoxValid(box)
    if not box or not box.Parent then return false end
    if collectedBoxes[box] then return false end
    local boxes = workspace:FindFirstChild("Boxes")
    return boxes and box.Parent == boxes
end

local function findMythics()
    local boxes   = workspace:FindFirstChild("Boxes")
    local mythics = {}
    if not boxes then return mythics end
    for _, child in ipairs(boxes:GetChildren()) do
        if (child.Name == "Secret" or child.Name == "Mythic") and not collectedBoxes[child] then
            table.insert(mythics, child)
        end
    end
    return mythics
end

local function firePrompt(model)
    local main   = model:FindFirstChild("Main")
    local prompt = main and main:FindFirstChild("PickupPrompt")
    if prompt and prompt:IsA("ProximityPrompt") then
        fireproximityprompt(prompt)
        task.wait(0.2)
    end
end

-- ── Server hop to a DIFFERENT server ────────────────────────────────────────
local function serverHop(window)
    setStatus("Finding a new server...")
    if queueteleport then queueteleport(REEXEC_PAYLOAD) end
    task.wait(0.2)

    local candidates = {}

    pcall(function()
        local cursor = ""
        for _ = 1, 5 do
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
                .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor ~= "" then url = url .. "&cursor=" .. cursor end

            local data = HttpService:JSONDecode(game:HttpGet(url))
            if data and data.data then
                for _, server in ipairs(data.data) do
                    if server.playing and server.playing < server.maxPlayers
                       and not visitedServers[server.id] then
                        table.insert(candidates, server.id)
                    end
                end
            end
            if data and data.nextPageCursor and data.nextPageCursor ~= "" then
                cursor = data.nextPageCursor
            else break end
        end
    end)

    if #candidates > 0 then
        -- Pick a random server from the valid ones
        local pick = candidates[math.random(1, #candidates)]
        setStatus("Joining server...")
        pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, pick, lp)
    else
        -- No unvisited servers found — clear visited list and do a normal teleport
        -- so we don't get permanently stuck
        setStatus("No new servers — resetting and hopping...")
        visitedServers = {}
        pcall(function()
            if isfile and isfile(VISITED_FILE) then
                writefile(VISITED_FILE, "")
            end
        end)
        pcall(TeleportService.Teleport, TeleportService, game.PlaceId, lp)
    end
end

-- ── Claim boxes ─────────────────────────────────────────────────────────────
local function claimBoxes(boxes, label)
    for i, box in ipairs(boxes) do
        if not running then break end
        if not isBoxValid(box) then
            setStatus("Skipping " .. label .. " #" .. i .. " (already collected)")
            task.wait(0.1)
        else
            setStatus("Teleporting to " .. label .. " #" .. i .. "...")
            tpTo(modelPosition(box))
            task.wait(0.5)
            setStatus("Collecting " .. label .. " #" .. i .. "...")
            firePrompt(box)
            collectedBoxes[box] = true
            task.wait(0.5)
            setStatus("Returning to safe zone...")
            tpTo(SAFE_ZONE)
            task.wait(2)
        end
    end
    if not running then return {} end
    task.wait(0.5)
    return findMythics()
end

-- ── Main loop ───────────────────────────────────────────────────────────────
local function farmLoop(window)
    while running do
        setStatus("Scanning for boxes...")
        local mythics = findMythics()

        if #mythics == 0 then
            setStatus("No boxes found — waiting for server to load...")
            task.wait(3)
            if not running then break end

            setStatus("Scanning again...")
            task.wait(5)
            if not running then break end

            mythics = findMythics()
            if #mythics == 0 then
                setStatus("No boxes — hopping servers...")
                window:Toast({ title = "No boxes found, hopping" })
                serverHop(window)
                return
            end
        end

        setStatus("Found " .. #mythics .. " box(es) — farming...")
        window:Toast({ title = "Found " .. #mythics .. " box(es)" })

        local remaining = claimBoxes(mythics, "Box")
        if not running then break end

        if #remaining > 0 then
            setStatus("Retrying " .. #remaining .. " box(es) in 2s...")
            task.wait(2)
            if not running then break end
            remaining = claimBoxes(remaining, "Retry")
            if not running then break end
        end

        if #remaining == 0 then
            setStatus("All collected — hopping servers...")
        else
            setStatus(#remaining .. " stuck — hopping servers...")
        end

        window:Toast({ title = "Done — hopping to next server" })
        serverHop(window)
        return
    end
    setStatus("Idle")
end

-- ── Window ──────────────────────────────────────────────────────────────────
local window = Rayfield:CreateWindow({
    name = "Verity Autofarm",
    subtitle = "Verity's Game",
    sidebarLayout = true,
})

-- ── Farm tab ────────────────────────────────────────────────────────────────
local farmTab = window:CreateTab({ name = "Farm", icon = 93364949241311 })

statusText = farmTab:CreateText({
    name = "Status",
    text = autoStart and "Resuming from last session..." or "Idle",
})

farmToggle = farmTab:CreateToggle({
    name = "Auto Farm",
    value = autoStart,
    callback = function(value)
        running = value
        saveState(value)
        if running then
            setStatus("Starting...")
            task.spawn(farmLoop, window)
        else
            setStatus("Idle")
        end
    end,
})

-- ── Misc tab ────────────────────────────────────────────────────────────────
local miscTab = window:CreateTab({ name = "Misc", icon = 80827985498498 })

miscTab:CreateButton({
    name = "Server Hop",
    callback = function()
        window:Toast({ title = "Hopping to a new server..." })
        serverHop(window)
    end,
})

miscTab:CreateButton({
    name = "Teleport To Safe Zone",
    callback = function()
        tpTo(SAFE_ZONE)
        window:Toast({ title = "Teleported to safe zone" })
    end,
})

-- ── Startup ─────────────────────────────────────────────────────────────────
window:Toast({ title = "Verity Autofarm loaded" })

if autoStart then
    running = true
    farmToggle:Set(true, true)
    task.spawn(farmLoop, window)
end
