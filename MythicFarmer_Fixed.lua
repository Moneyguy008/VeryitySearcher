--[[
    Mythic Box Farmer
    GUI: Rayfield Gen2 (sirius.menu/gen2)

    SETUP: Save this file as MythicFarmer/MythicFarmer.lua in your
           executor's workspace folder. Run it once — after that it
           auto-runs on every server hop.
--]]

-- ── Wait for game to load (critical after teleport) ─────────────────────────
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

-- ── Resolve queueonteleport across executors (IY-style) ─────────────────────
local queueteleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
    or (Wave and Wave.queue_on_teleport)

-- ── File paths ──────────────────────────────────────────────────────────────
local FOLDER        = "MythicFarmer"
local FILE          = FOLDER .. "/MythicFarmer.lua"
local AUTOEXEC      = "autoexec"
local AUTOEXEC_FILE = AUTOEXEC .. "/MythicFarmer.lua"

-- ── Check that the saved file exists (required for re-execute) ──────────────
local hasSavedFile = isfile and isfile(FILE)

-- If the file doesn't exist yet, try to create it from autoexec or warn the user
if not hasSavedFile then
    -- Maybe it's in autoexec but not in MythicFarmer/
    if isfile and isfile(AUTOEXEC_FILE) then
        pcall(function()
            if not isfolder(FOLDER) then makefolder(FOLDER) end
            writefile(FILE, readfile(AUTOEXEC_FILE))
        end)
        hasSavedFile = isfile(FILE)
    end
end

-- ── The tiny payload we queue before every hop ──────────────────────────────
-- This is the key fix: we queue a small loader, not the whole script.
local REEXEC_PAYLOAD = [[
repeat task.wait() until game:IsLoaded()
task.wait(1)
if readfile and isfile then
    if isfile("MythicFarmer/MythicFarmer.lua") then
        loadstring(readfile("MythicFarmer/MythicFarmer.lua"))()
    elseif isfile("autoexec/MythicFarmer.lua") then
        loadstring(readfile("autoexec/MythicFarmer.lua"))()
    end
end
]]

-- ── Load Rayfield Gen2 ──────────────────────────────────────────────────────
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- ── Services ────────────────────────────────────────────────────────────────
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")

-- ── Constants ───────────────────────────────────────────────────────────────
local STAGING_POS = Vector3.new(-121.91282653808594, 13.358054161071777, -144.80528259277344)

-- ── State ───────────────────────────────────────────────────────────────────
local running    = false
local statusText = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────
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
        print("[MythicFarmer] ✅ Queued re-execute payload")
    else
        warn("[MythicFarmer] ❌ No queueonteleport — won't auto-run after hop")
    end

    task.wait(0.2)

    local ok, err = pcall(TeleportService.Teleport, TeleportService, game.PlaceId, lp)
    if not ok then
        warn("[MythicFarmer] Teleport failed: " .. tostring(err))
    end
end

-- ── Main farm loop ───────────────────────────────────────────────────────────
local function farmLoop(window)
    while running do
        setStatus("🔍 Scanning for Mythic boxes...")
        local mythics = findMythics()

        if #mythics == 0 then
            window:Notify({
                title    = "No Mythics Found",
                content  = "Waiting 3s then scanning again before hopping...",
                duration = 4,
            })
            setStatus("⏳ Waiting 3s for server to load...")
            task.wait(3)
            if not running then break end

            setStatus("⏳ Scanning again in 5s...")
            task.wait(5)
            if not running then break end

            mythics = findMythics()
            if #mythics == 0 then
                setStatus("❌ Still no Mythics — server hopping")
                window:Notify({
                    title    = "Still None",
                    content  = "Server hopping to find Mythics.",
                    duration = 3,
                })
                serverHop()
                return
            end
        end

        window:Notify({
            title    = "Mythics Found!",
            content  = "Found " .. #mythics .. " Mythic box(es). Farming...",
            duration = 4,
        })
        setStatus("✅ Found " .. #mythics .. " Mythic(s). Farming...")

        for i, box in ipairs(mythics) do
            if not running then break end

            local pos = modelPosition(box)
            setStatus("📦 Mythic #" .. i .. " — teleporting")
            tpTo(pos)
            task.wait(0.5)

            setStatus("🖱️ Firing prompt on Mythic #" .. i)
            firePrompt(box)
            task.wait(0.5)

            setStatus("🏠 Returning to staging")
            tpTo(STAGING_POS)
            task.wait(0.5)
        end

        if not running then break end

        task.wait(1)
        local remaining = findMythics()
        if #remaining == 0 then
            window:Notify({
                title    = "All Mythics Claimed!",
                content  = "Hopping to a new server.",
                duration = 4,
            })
            setStatus("🎉 All claimed — server hopping")
        else
            window:Notify({
                title    = "Some Uncollectable",
                content  = #remaining .. " box(es) remain but can't be picked up. Hopping.",
                duration = 4,
            })
            setStatus("⚠️ " .. #remaining .. " remaining — hopping")
        end
        serverHop()
        return
    end

    setStatus("⏸️ Stopped")
end

-- ── Rayfield Gen2 Window ────────────────────────────────────────────────────
local window = Rayfield:CreateWindow({
    name          = "Mythic Farmer",
    subtitle      = "Auto Box Hunter",
    sidebarLayout = true,
})

local tab = window:CreateTab({ name = "Farmer", icon = 93364949241311 })

statusText = tab:CreateText({
    name        = "Status",
    description = hasSavedFile
        and "✅ File found — ready to auto-farm"
        or "⚠️ Save this script to workspace/MythicFarmer/MythicFarmer.lua first!",
})

tab:CreateToggle({
    name        = "Auto Farm",
    description = "Scans for Mythic boxes, claims them, and server hops automatically.",
    callback    = function(value)
        running = value
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

tab:CreateButton({
    name        = "Scan Now",
    description = "Run one scan pass (no server hop).",
    callback    = function()
        local mythics = findMythics()
        window:Notify({
            title    = "Scan Result",
            content  = "Found " .. #mythics .. " Mythic box(es) in this server.",
            duration = 5,
        })
        setStatus("🔍 Manual scan: " .. #mythics .. " Mythic(s) found")
    end,
})

tab:CreateButton({
    name        = "Go to Staging",
    description = "Teleport to the staging position.",
    callback    = function()
        tpTo(STAGING_POS)
        setStatus("📍 Teleported to staging position")
    end,
})

tab:CreateButton({
    name        = "Server Hop",
    description = "Queue re-execute then hop to a new server.",
    callback    = function()
        serverHop()
    end,
})

tab:CreateDivider()

tab:CreateText({
    name        = "How it works",
    description = "Scans workspace.Boxes for Mythics, teleports to each, fires the PickupPrompt, returns to staging, then server hops when done.",
})

-- ── Startup notification ────────────────────────────────────────────────────
if hasSavedFile then
    window:Notify({
        title    = "Mythic Farmer Loaded",
        content  = "✅ Script file found. Auto-run after hop is ready!",
        duration = 5,
    })
else
    window:Notify({
        title    = "⚠️ One-Time Setup Needed",
        content  = "Save this script as MythicFarmer.lua inside workspace/MythicFarmer/ folder. Server hop won't auto-run until you do!",
        duration = 12,
    })
end
