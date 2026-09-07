--[[
    Mythic Box Farmer
    GUI: Rayfield Gen2 (sirius.menu/gen2)

    loadstring(game:HttpGet("https://raw.githubusercontent.com/Moneyguy008/VeryitySearcher/main/MythicFarmer_Fixed.lua"))()
--]]

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

local SCRIPT_URL = "https://raw.githubusercontent.com/Moneyguy008/VeryitySearcher/main/MythicFarmer_Fixed.lua"

local queueteleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
    or (Wave and Wave.queue_on_teleport)

local REEXEC_PAYLOAD = 'repeat task.wait() until game:IsLoaded() task.wait(1) loadstring(game:HttpGet("' .. SCRIPT_URL .. '"))()'

-- ── State file: persists auto-farm ON/OFF across hops ───────────────────────
local STATE_FOLDER = "MythicFarmer"
local STATE_FILE   = STATE_FOLDER .. "/state.txt"

local function saveState(on)
    pcall(function()
        if not isfolder(STATE_FOLDER) then makefolder(STATE_FOLDER) end
        writefile(STATE_FILE, on and "ON" or "OFF")
    end)
end

local function loadState()
    local ok, result = pcall(function()
        if isfile and isfile(STATE_FILE) then
            return readfile(STATE_FILE) == "ON"
        end
        return false
    end)
    return ok and result or false
end

local autoStart = loadState()

-- ── Load Rayfield Gen2 ──────────────────────────────────────────────────────
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")

local STAGING_POS = Vector3.new(-121.91282653808594, 13.358054161071777, -144.80528259277344)

local running    = false
local statusText = nil
local farmToggle = nil  -- store toggle reference so we can update it

local function setStatus(msg)
    if statusText then
        statusText:Set({ name = "Status", description = tostring(msg) })
    end
    print("[MythicFarmer] " .. tostring(msg))
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
    if model.PrimaryPart then
        return model.PrimaryPart.Position
    end
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

local function findMythics()
    local boxes   = workspace:FindFirstChild("Boxes")
    local mythics = {}
    if not boxes then return mythics end
    for _, child in ipairs(boxes:GetChildren()) do
        if child.Name == "Secret" or child.Name == "Mythic" then
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
    else
        warn("[MythicFarmer] PickupPrompt not found on " .. model:GetFullName())
    end
end

-- ── Server hop to a DIFFERENT server ────────────────────────────────────────
local function serverHop()
    setStatus("🔄 Queueing re-execute and finding a new server...")
    if queueteleport then
        queueteleport(REEXEC_PAYLOAD)
        print("[MythicFarmer] ✅ Queued loadstring from URL")
    else
        warn("[MythicFarmer] ❌ No queueonteleport on this executor")
    end
    task.wait(0.2)

    -- Try to find a different server so we don't rejoin the same one
    local currentJobId = game.JobId
    local foundServer = false

    local success, err = pcall(function()
        local cursor = ""
        for attempt = 1, 5 do
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
                .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor ~= "" then
                url = url .. "&cursor=" .. cursor
            end

            local response = game:HttpGet(url)
            local data = HttpService:JSONDecode(response)

            if data and data.data then
                for _, server in ipairs(data.data) do
                    if server.id ~= currentJobId and server.playing and server.playing < server.maxPlayers then
                        setStatus("🌐 Found different server — teleporting")
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, lp)
                        foundServer = true
                        return
                    end
                end
            end

            -- If there's a next page, keep looking
            if data and data.nextPageCursor and data.nextPageCursor ~= "" then
                cursor = data.nextPageCursor
            else
                break
            end
        end
    end)

    -- Fallback: if we couldn't find a different server, just do a normal teleport
    if not foundServer then
        setStatus("🌐 No alternate server found — normal teleport")
        pcall(TeleportService.Teleport, TeleportService, game.PlaceId, lp)
    end
end

-- ── Attempt to claim a list of boxes ────────────────────────────────────────
local function claimBoxes(boxes, window, label)
    for i, box in ipairs(boxes) do
        if not running then break end
        local pos = modelPosition(box)
        setStatus(label .. " #" .. i .. " — teleporting")
        tpTo(pos)
        task.wait(0.5)
        setStatus("🖱️ Firing prompt on " .. label .. " #" .. i)
        firePrompt(box)
        task.wait(0.5)
        setStatus("🏠 Returning to staging")
        tpTo(STAGING_POS)
        -- 2 second cooldown after each collection to avoid ragdoll
        task.wait(2)
    end

    if not running then return {} end
    task.wait(0.5)
    return findMythics()
end

local function farmLoop(window)
    while running do
        setStatus("🔍 Scanning for Mythic boxes...")
        local mythics = findMythics()

        if #mythics == 0 then
            window:Notify({ title = "No Mythics Found", content = "Waiting 3s then scanning again before hopping...", duration = 4 })
            setStatus("⏳ Waiting 3s for server to load...")
            task.wait(3)
            if not running then break end

            setStatus("⏳ Scanning again in 5s...")
            task.wait(5)
            if not running then break end

            mythics = findMythics()
            if #mythics == 0 then
                setStatus("❌ Still no Mythics — server hopping")
                window:Notify({ title = "Still None", content = "Server hopping to find Mythics.", duration = 3 })
                serverHop()
                return
            end
        end

        window:Notify({ title = "Mythics Found!", content = "Found " .. #mythics .. " Mythic box(es). Farming...", duration = 4 })
        setStatus("✅ Found " .. #mythics .. " Mythic(s). Farming...")

        -- First pass
        local remaining = claimBoxes(mythics, window, "📦 Mythic")
        if not running then break end

        -- Retry pass: if any left, wait 2s and try once more
        if #remaining > 0 then
            window:Notify({ title = "Retrying", content = #remaining .. " box(es) left. Retrying in 2s...", duration = 3 })
            setStatus("⏳ " .. #remaining .. " uncollectable — retrying in 2s")
            task.wait(2)
            if not running then break end

            remaining = claimBoxes(remaining, window, "🔁 Retry")
            if not running then break end
        end

        if #remaining == 0 then
            window:Notify({ title = "All Mythics Claimed!", content = "Hopping to a new server.", duration = 4 })
            setStatus("🎉 All claimed — server hopping")
        else
            window:Notify({ title = "Some Still Stuck", content = #remaining .. " box(es) couldn't be claimed after retry. Hopping.", duration = 4 })
            setStatus("⚠️ " .. #remaining .. " stuck after retry — hopping")
        end
        serverHop()
        return
    end
    setStatus("⏸️ Stopped")
end

-- ── GUI ─────────────────────────────────────────────────────────────────────
local window = Rayfield:CreateWindow({ name = "Mythic Farmer", subtitle = "Auto Box Hunter", sidebarLayout = true })
local tab = window:CreateTab({ name = "Farmer", icon = 93364949241311 })

statusText = tab:CreateText({ name = "Status", description = autoStart and "🚀 Auto-starting from last session..." or "Idle — toggle Auto Farm to start" })

farmToggle = tab:CreateToggle({
    name = "Auto Farm",
    description = "Scans for Mythic boxes, claims them, and server hops automatically. State persists across hops.",
    CurrentValue = autoStart,
    callback = function(value)
        running = value
        saveState(value)
        if running then
            setStatus("🚀 Starting...")
            window:Notify({ title = "Mythic Farmer", content = "Auto-farm started.", duration = 3 })
            task.spawn(farmLoop, window)
        else
            setStatus("⏸️ Stopped")
            window:Notify({ title = "Mythic Farmer", content = "Auto-farm stopped.", duration = 3 })
        end
    end,
})

tab:CreateButton({ name = "Scan Now", description = "Run one scan pass (no server hop).", callback = function()
    local m = findMythics()
    window:Notify({ title = "Scan Result", content = "Found " .. #m .. " Mythic box(es).", duration = 5 })
    setStatus("🔍 Manual scan: " .. #m .. " Mythic(s) found")
end })

tab:CreateButton({ name = "Go to Staging", description = "Teleport to the staging position.", callback = function()
    tpTo(STAGING_POS)
    setStatus("📍 Teleported to staging position")
end })

tab:CreateButton({ name = "Server Hop", description = "Queue re-execute then hop to a different server.", callback = function()
    serverHop()
end })

tab:CreateDivider()
tab:CreateText({ name = "How it works", description = "Scans workspace.Boxes for Mythics, teleports to each, fires the PickupPrompt, returns to staging with 2s cooldown. Uncollectable boxes get one retry after 2s. Hops to a different server (skips current). Toggle state persists across hops." })

window:Notify({ title = "Mythic Farmer Loaded", content = autoStart and "✅ Auto-farm was ON — resuming!" or "Toggle Auto Farm to begin.", duration = 5 })

-- ── Auto-start if state was ON from last hop ────────────────────────────────
if autoStart then
    running = true
    -- Set the toggle visually to ON so the user can turn it off
    pcall(function() farmToggle:Set(true) end)
    task.spawn(farmLoop, window)
end
