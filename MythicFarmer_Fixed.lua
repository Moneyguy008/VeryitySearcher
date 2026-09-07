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
            window:Notify({ title = "All Mythics Claimed!", content = "Hopping to a new server.", duration = 4 })
            setStatus("🎉 All claimed — server hopping")
        else
            window:Notify({ title = "Some Uncollectable", content = #remaining .. " box(es) remain. Hopping.", duration = 4 })
            setStatus("⚠️ " .. #remaining .. " remaining — hopping")
        end
        serverHop()
        return
    end
    setStatus("⏸️ Stopped")
end

local window = Rayfield:CreateWindow({ name = "Mythic Farmer", subtitle = "Auto Box Hunter", sidebarLayout = true })
local tab = window:CreateTab({ name = "Farmer", icon = 93364949241311 })

statusText = tab:CreateText({ name = "Status", description = "✅ Ready — toggle Auto Farm to start" })

tab:CreateToggle({
    name = "Auto Farm",
    description = "Scans for Mythic boxes, claims them, and server hops automatically.",
    callback = function(value)
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
tab:CreateText({ name = "How it works", description = "Scans workspace.Boxes for Mythics, teleports to each, fires the PickupPrompt, returns to staging, then server hops when done." })

window:Notify({ title = "Mythic Farmer Loaded", content = "✅ URL-based autorun ready. No setup needed!", duration = 5 })
