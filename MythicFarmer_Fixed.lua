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

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")

local STAGING_POS = Vector3.new(-121.91282653808594, 13.358054161071777, -144.80528259277344)

local running    = false
local statusText = nil

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

local function serverHop()
    setStatus("🔄 Queueing re-execute and server hopping...")
    if queueteleport then
        queueteleport(REEXEC_PAYLOAD)
        print("[MythicFarmer] ✅ Queued loadstring from URL")
    else
        warn("[MythicFarmer] ❌ No queueonteleport on this executor")
    end
    task.wait(0.2)
    local ok, err = pcall(TeleportService.Teleport, TeleportService, game.PlaceId, lp)
    if not ok then
        warn("[MythicFarmer] Teleport failed: " .. tostring(err))
    end
end

-- ── Attempt to claim a list of boxes, returns any that are still there ──────
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
        task.wait(0.5)
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

        -- Done — report and hop
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

tab:CreateToggle({
    name = "Auto Farm",
    description = "Scans for Mythic boxes, claims them, and server hops automatically. State persists across hops.",
    currentValue = autoStart,
    callback = function(value)
        running = value
        saveState(value)
        if running then
            setStatus("🚀 Starting...")
            window:Notify({ title = "Mythic Farmer", content = "Auto-farm started. State saved — will persist across hops.", duration = 3 })
            task.spawn(farmLoop, window)
        else
            setStatus("⏸️ Stopped")
            window:Notify({ title = "Mythic Farmer", content = "Auto-farm stopped. State saved — won't auto-start next hop.", duration = 3 })
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

tab:CreateButton({ name = "Server Hop", description = "Queue re-execute then hop to a new server.", callback = function()
    serverHop()
end })

tab:CreateDivider()
tab:CreateText({ name = "How it works", description = "Scans workspace.Boxes for Mythics, teleports to each, fires the PickupPrompt, returns to staging. Uncollectable boxes get one retry after 2s. State persists via workspace/MythicFarmer/state.txt." })

window:Notify({ title = "Mythic Farmer Loaded", content = autoStart and "✅ Auto-farm was ON — resuming automatically!" or "Toggle Auto Farm to begin.", duration = 5 })

-- ── Auto-start if state was ON from last hop ────────────────────────────────
if autoStart then
    running = true
    task.spawn(farmLoop, window)
end
