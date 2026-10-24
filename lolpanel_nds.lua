--===============================================================
-- lolpanel NDS
-- sonde de remotes par delta monde + kit de survie client
-- Delta / Android. 3 onglets: SONDE / SURVIE / LOG
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    blue = Color3.fromRGB(120, 180, 255), violet = Color3.fromRGB(190, 150, 255),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
}

local logLine
local refreshSonde, refreshLog, rebuildSonde

--===============================================================
-- UI kit
--===============================================================
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(r, o) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(col, o, t)
    return mk("UIStroke", { Color = col, Thickness = t or 1 }, o)
end

local function lbl(parent, props)
    local t = { BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        TextColor3 = C.txt, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center }
    for k, v in pairs(props or {}) do t[k] = v end
    return mk("TextLabel", t, parent)
end

local function btn(parent, props)
    local t = { BackgroundColor3 = C.row, BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextColor3 = C.txt, TextSize = 10,
        Text = "", AutoButtonColor = true, ClipsDescendants = true }
    for k, v in pairs(props or {}) do t[k] = v end
    local b = mk("TextButton", t, parent)
    corner(7, b)
    return b
end

local function clearChildren(s)
    for _, ch in ipairs(s:GetChildren()) do
        if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
            pcall(function() ch:Destroy() end)
        end
    end
end

--===============================================================
-- helpers
--===============================================================
local function char()
    local c = LP.Character
    if c and c.Parent then return c end
    return nil
end

local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function root()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function buildPath(o)
    local parts = {}
    local cur = o
    local guard = 0
    while cur and cur ~= game and guard < 24 do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
        guard = guard + 1
    end
    return table.concat(parts, "/")
end

--===============================================================
-- remote inventory
--===============================================================
local ENGINE_ROOTS = {
    ["RobloxReplicatedStorage"] = true,
    ["RobloxSecurity"] = true,
    ["_Engine"] = true,
}

local REMOTES = {}

local PRIORITY = {
    { key = "Remotes/Sandbox/Selection", rank = 2 },
    { key = "Remotes/Sandbox", rank = 1 },
    { key = "Remotes/Server", rank = 3 },
    { key = "Remotes/Round", rank = 4 },
    { key = "Remotes/Compass", rank = 5 },
    { key = "Remotes/Lab", rank = 6 },
    { key = "PrintAnnounceEvent", rank = 9 },
    { key = "RTDTeleportEvent", rank = 10 },
    { key = "ReplicatedStorage/Event", rank = 7 },
    { key = "ReplicatedStorage/Award", rank = 8 },
}

local function gameRank(path)
    for i = 1, #PRIORITY do
        if path:find(PRIORITY[i].key, 1, true) then return PRIORITY[i].rank end
    end
    return 500
end

local function scanRemotes()
    REMOTES = {}
    local ok, desc = pcall(function() return game:GetDescendants() end)
    if not ok then return 0 end
    local seen = {}
    for i = 1, #desc do
        local o = desc[i]
        if not o then break end
        local cls = o.ClassName
        if cls == "RemoteEvent" or cls == "RemoteFunction" then
            local path = buildPath(o)
            local head = path:split("/")[1]
            if not ENGINE_ROOTS[head] and not seen[o] then
                seen[o] = true
                table.insert(REMOTES, {
                    o = o, path = path, cls = cls,
                    name = o.Name, rank = gameRank(path),
                    verdict = "", result = "",
                })
            end
        end
        if i > 90000 then break end
    end
    table.sort(REMOTES, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.path:lower() < b.path:lower()
    end)
    return #REMOTES
end

--===============================================================
-- sonde: delta monde
--===============================================================
local function snapWorld()
    local s = { ws = {}, bp = {}, parts = 0, pos = nil, hp = nil, tools = 0 }
    local ok1, kids = pcall(function() return workspace:GetChildren() end)
    if ok1 then
        for _, c in ipairs(kids) do s.ws[c] = true end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        local ok2, items = pcall(function() return bp:GetChildren() end)
        if ok2 then
            for _, it in ipairs(items) do s.bp[it] = true end
            s.tools = #items
        end
    end
    local r = root()
    if r then s.pos = r.Position end
    local h = hum()
    if h then s.hp = h.Health end
    return s
end

local function describeDelta(a, b)
    local bits = {}
    local added = 0
    for k in pairs(b.ws) do
        if not a.ws[k] then added = added + 1 end
    end
    if added > 0 then table.insert(bits, "+" .. added .. " workspace") end

    local newTools = 0
    for k in pairs(b.bp) do
        if not a.bp[k] then newTools = newTools + 1 end
    end
    if newTools > 0 then table.insert(bits, "+" .. newTools .. " outil") end

    if a.pos and b.pos then
        local d = (b.pos - a.pos).Magnitude
        if d > 3 then table.insert(bits, "tp " .. math.floor(d) .. " studs") end
    end

    if a.hp and b.hp and math.abs(a.hp - b.hp) > 0.5 then
        local d = b.hp - a.hp
        table.insert(bits, (d > 0 and "+" or "") .. math.floor(d) .. " hp")
    end

    if #bits == 0 then return "rien" end
    return table.concat(bits, ", ")
end

local PROBES = {
    { name = "vide", make = function() return {} end },
    { name = "moi", make = function() return { LP } end },
    { name = "perso", make = function() return { char() } end },
    { name = "part", make = function() return { root() } end },
    { name = "string", make = function() return { "test" } end },
    { name = "nombre", make = function() return { 1 } end },
    { name = "bool", make = function() return { true } end },
    { name = "vec3", make = function() return { Vector3.new(0, 60, 0) } end },
}

local Sonde = { on = false, done = 0, found = 0 }

local function callRemote(remote, args)
    if not remote or not remote.Parent then return false, nil end
    if remote:IsA("RemoteFunction") then
        local ok, res = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
        return ok, res
    end
    local ok = pcall(function() remote:FireServer(table.unpack(args)) end)
    return ok, nil
end

local function probeOne(entry)
    if not entry or not entry.o or not entry.o.Parent then
        entry.verdict = "mort"
        entry.result = "instance detruite"
        return "mort"
    end

    local isFunc = entry.cls == "RemoteFunction"
    local hits = {}
    local errs = 0

    for i = 1, #PROBES do
        local p = PROBES[i]
        local before = snapWorld()
        local ok, res = callRemote(entry.o, p.make())
        task.wait(0.28)
        local after = snapWorld()

        if ok then
            local d = describeDelta(before, after)
            if d ~= "rien" then
                table.insert(hits, p.name .. " -> " .. d)
            elseif isFunc and res ~= nil then
                local txt = tostring(res)
                if #txt > 40 then txt = txt:sub(1, 40) .. "..." end
                table.insert(hits, p.name .. " -> retour " .. txt)
            end
        else
            errs = errs + 1
        end
        Sonde.done = Sonde.done + 1
    end

    if #hits > 0 then
        Sonde.found = Sonde.found + 1
        entry.verdict = "ACTIF"
        entry.result = table.concat(hits, " | ")
    elseif errs == #PROBES then
        entry.verdict = "REJET"
        entry.result = "les 8 formes refusees"
    else
        entry.verdict = "muet"
        entry.result = "aucun effet visible"
    end

    return entry.verdict
end

local function probeAll()
    if Sonde.on or #REMOTES == 0 then return end
    Sonde.on = true
    Sonde.done = 0
    Sonde.found = 0
    logLine("sonde: " .. #REMOTES .. " remotes du jeu")
    for i = 1, #REMOTES do
        if not Sonde.on then break end
        local e = REMOTES[i]
        probeOne(e)
        refreshSonde()
        logLine("sonde " .. e.name .. ": " .. e.verdict .. (e.result ~= "" and (" — " .. e.result) or ""))
        task.wait(0.15)
    end
    Sonde.on = false
    refreshSonde()
    logLine("sonde: fin, " .. Sonde.found .. " actifs, " .. Sonde.done .. " appels")
end

--===============================================================
-- survie
--===============================================================
local S = {
    fly = false, noclip = false, esp = false, infjump = false,
    platform = false, speed = 60, vs = 60,
}

local flyBV, flyBG, flyConn, noclipConn, platConn, platPart
local espTags = {}

local function clearEsp()
    for i = 1, #espTags do
        pcall(function() espTags[i]:Destroy() end)
    end
    espTags = {}
end

local function stopFly()
    S.fly = false
    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
end

local function startFly()
    stopFly()
    local r = root()
    if not r then return end
    S.fly = true
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    flyBV.Velocity = Vector3.new(0, 0, 0)
    flyBV.Parent = r
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    flyBG.P = 2000
    flyBG.D = 60
    flyBG.Parent = r
    flyConn = RunService.Heartbeat:Connect(function()
        if not flyBV or not flyBG then return end
        local cam = workspace.CurrentCamera
        local rr = root()
        if not cam or not rr then return end
        flyBG.CFrame = cam.CFrame
        local mv = UIS:GetMoveVector()
        if mv.Magnitude > 0.05 then
            local dir = cam.CFrame.RightVector * mv.X + cam.CFrame.LookVector * -mv.Z
            if dir.Magnitude > 0.01 then
                flyBV.Velocity = dir.Unit * S.vs
            end
        else
            flyBV.Velocity = Vector3.new(0, 0, 0)
        end
    end)
end

local function setNoclip(on)
    S.noclip = on
    if noclipConn then pcall(function() noclipConn:Disconnect() end); noclipConn = nil end
    if not on then
        local c = char()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
            end
        end
        return
    end
    noclipConn = RunService.Stepped:Connect(function()
        local c = char()
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                pcall(function() p.CanCollide = false end)
            end
        end
    end)
end

local function setEsp(on)
    S.esp = on
    clearEsp()
    if not on then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local head = p.Character:FindFirstChild("Head")
            if head then
                local old = head:FindFirstChild("lolpanelTag")
                if old then pcall(function() old:Destroy() end) end
                local bb = Instance.new("BillboardGui")
                bb.Name = "lolpanelTag"
                bb.Size = UDim2.fromOffset(160, 24)
                bb.StudsOffset = Vector3.new(0, 2.4, 0)
                bb.AlwaysOnTop = true
                bb.MaxDistance = 900
                local tl = Instance.new("TextLabel")
                tl.BackgroundTransparency = 1
                tl.Size = UDim2.fromScale(1, 1)
                tl.Font = Enum.Font.GothamBold
                tl.TextSize = 12
                tl.TextColor3 = C.red
                tl.TextStrokeTransparency = 0.3
                tl.Text = p.Name
                tl.Parent = bb
                bb.Parent = head
                table.insert(espTags, bb)
            end
        end
    end
end

local function togglePlatform()
    S.platform = not S.platform
    if platConn then pcall(function() platConn:Disconnect() end); platConn = nil end
    if platPart then pcall(function() platPart:Destroy() end); platPart = nil end
    if not S.platform then return end
    local plat = Instance.new("Part")
    plat.Name = "lolpanelPlat"
    plat.Size = Vector3.new(10, 1, 10)
    plat.Anchored = true
    plat.CanCollide = true
    plat.Transparency = 0.75
    plat.Material = Enum.Material.ForceField
    plat.Color = C.green
    pcall(function() plat.Parent = workspace end)
    platPart = plat
    platConn = RunService.Heartbeat:Connect(function()
        local r = root()
        if not r or not plat.Parent then return end
        plat.CFrame = CFrame.new(r.Position - Vector3.new(0, 3.6, 0))
    end)
end

--===============================================================
-- UI
--===============================================================
local gui = mk("ScreenGui", {
    Name = "Counter", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function() if type(gethui) == "function" then gui.Parent = gethui() end end)
if not gui.Parent then pcall(function() gui.Parent = game:GetService("CoreGui") end) end
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

if getgenv then
    local old = getgenv()._nds
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._nds = gui
end

local W, H = 322, 470
local win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 6, 0, 70),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.amber, Thickness = 1, Transparency = 0.4 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "NDS", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.amber, Size = UDim2.fromOffset(150, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})

local TABS = { "SONDE", "SURVIE", "LOG" }
local tabBtns, pages = {}, {}
local tabW = (W - 20 - 12) / 3

local function setTab(i)
    for k = 1, #pages do
        pages[k].Visible = (k == i)
        tabBtns[k].BackgroundColor3 = (k == i) and C.amber or C.row
        tabBtns[k].TextColor3 = (k == i) and C.bg or C.dim
    end
    if i == 1 then rebuildSonde() end
    if i == 3 then refreshLog() end
end

for i = 1, 3 do
    local b = btn(win, {
        Text = TABS[i], Size = UDim2.fromOffset(tabW, 24),
        Position = UDim2.fromOffset(10 + (i - 1) * (tabW + 6), 30),
        TextSize = 9,
    })
    b.MouseButton1Click:Connect(function() setTab(i) end)
    tabBtns[i] = b
    local p = mk("Frame", {
        Size = UDim2.new(1, -20, 1, -66),
        Position = UDim2.fromOffset(10, 60), BackgroundTransparency = 1,
    }, win)
    pages[i] = p
end

local LOG = {}
local logBox

logLine = function(txt)
    table.insert(LOG, tostring(txt))
    while #LOG > 200 do table.remove(LOG, 1) end
    if logBox then
        logBox.Text = table.concat(LOG, "\n")
        local sc = logBox.Parent
        if sc and sc:IsA("ScrollingFrame") then
            pcall(function() sc.CanvasPosition = Vector2.new(0, 99999) end)
        end
    end
end

--===============================================================
-- page SONDE
--===============================================================
local sondeInfo = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 0),
    TextWrapped = true,
})

local sondeList = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 274), Position = UDim2.fromOffset(0, 28),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = C.amber,
    ScrollBarImageTransparency = 0.4, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pages[1])
mk("UIListLayout", {
    Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
}, sondeList)
mk("UIPadding", { PaddingRight = UDim.new(0, 6) }, sondeList)

local allBtn = btn(pages[1], {
    Text = "SONDER TOUT", Size = UDim2.new(0.5, -3, 0, 32),
    Position = UDim2.fromOffset(0, 310), TextColor3 = C.green, TextSize = 10,
})
stroke(C.green, allBtn, 1)

local stopBtn = btn(pages[1], {
    Text = "STOP", Size = UDim2.new(0.5, -3, 0, 32),
    Position = UDim2.new(0.5, 3, 0, 310), TextColor3 = C.red, TextSize = 10,
})
stroke(C.red, stopBtn, 1)

local copyBtn = btn(pages[1], {
    Text = "COPIER LE RAPPORT", Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.fromOffset(0, 348), TextColor3 = C.blue, TextSize = 10,
})

local sondeWarn = lbl(pages[1], {
    Text = "8 formes par remote, 0.28s entre chaque. le jeu n'a pas d'anti-cheat, ca passe.",
    Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 382),
    TextWrapped = true,
})

local function verdictColor(v)
    if v == "ACTIF" then return C.green end
    if v == "REJET" then return C.red end
    if v == "mort" then return C.violet end
    if v == "muet" then return C.amber end
    return C.dim
end

rebuildSonde = function()
    clearChildren(sondeList)
    for i = 1, #REMOTES do
        local e = REMOTES[i]
        local f = mk("Frame", {
            Size = UDim2.new(1, -2, 0, 40), BackgroundColor3 = C.row,
            BorderSizePixel = 0, LayoutOrder = i, ClipsDescendants = true,
        }, sondeList)
        corner(6, f)

        local tap = mk("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            Text = "", AutoButtonColor = false,
        }, f)

        lbl(f, {
            Text = e.name .. "  (" .. (e.cls == "RemoteEvent" and "RE" or "RF") .. ")",
            Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = C.txt, Size = UDim2.new(1, -70, 0, 18),
            Position = UDim2.fromOffset(7, 2),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        lbl(f, {
            Text = e.result ~= "" and e.result or e.path,
            Font = Enum.Font.Code, TextSize = 7,
            TextColor3 = e.result ~= "" and C.dim or C.dim,
            Size = UDim2.new(1, -70, 0, 18), Position = UDim2.fromOffset(7, 20),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local v = lbl(f, {
            Text = e.verdict ~= "" and e.verdict or "----",
            Font = Enum.Font.GothamBold, TextSize = 8,
            TextColor3 = verdictColor(e.verdict),
            Size = UDim2.fromOffset(62, 40), Position = UDim2.new(1, -66, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
        })

        local entry = e
        tap.MouseButton1Click:Connect(function()
            if Sonde.on then return end
            local label = entry.verdict
            v.Text = "..."
            task.spawn(function()
                probeOne(entry)
                rebuildSonde()
                logLine(entry.name .. ": " .. entry.verdict .. " — " .. entry.result)
            end)
        end)
    end
    if #REMOTES == 0 then
        lbl(sondeList, {
            Text = "aucun remote de jeu detecte", Font = Enum.Font.Code,
            TextSize = 9, TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 26),
        })
    end
    sondeInfo.Text = #REMOTES .. " remotes du jeu | " .. Sonde.done .. " appels" ..
        (Sonde.on and " | SONDE EN COURS" or "")
end

refreshSonde = function()
    sondeInfo.Text = #REMOTES .. " remotes du jeu | " .. Sonde.done .. " appels" ..
        (Sonde.on and " | SONDE EN COURS" or "")
    allBtn.Text = Sonde.on and "EN COURS..." or "SONDER TOUT"
end

allBtn.MouseButton1Click:Connect(function()
    if Sonde.on then return end
    task.spawn(function()
        probeAll()
        rebuildSonde()
    end)
end)

stopBtn.MouseButton1Click:Connect(function()
    Sonde.on = false
    refreshSonde()
    logLine("sonde: arret")
end)

copyBtn.MouseButton1Click:Connect(function()
    local out = {}
    table.insert(out, "lolpanel NDS rapport")
    table.insert(out, "place: " .. tostring(game.PlaceId))
    table.insert(out, "remotes: " .. #REMOTES)
    table.insert(out, "")
    for i = 1, #REMOTES do
        local e = REMOTES[i]
        table.insert(out, e.path .. " | " .. (e.cls == "RemoteEvent" and "RE" or "RF") ..
            " | " .. (e.verdict ~= "" and e.verdict or "non sonde") ..
            (e.result ~= "" and (" | " .. e.result) or ""))
    end
    local txt = table.concat(out, "\n")
    local ok = pcall(function() setclipboard(txt) end)
    logLine(ok and ("rapport copie (" .. #txt .. " octets)") or "copie refusee")
end)

--===============================================================
-- page SURVIE
--===============================================================
local survStat = lbl(pages[2], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 0),
    TextWrapped = true,
})

local TOGGLES = {
    { id = "fly", label = "VOL", col = C.blue },
    { id = "noclip", label = "TRAVERSE", col = C.violet },
    { id = "esp", label = "ESP JOUEURS", col = C.red },
    { id = "infjump", label = "SAUT INFINI", col = C.green },
}

local toggleBtns = {}

local function refreshSurvie()
    for i = 1, #TOGGLES do
        local t = TOGGLES[i]
        local b = toggleBtns[t.id]
        if b then
            local on = S[t.id]
            b.BackgroundColor3 = on and t.col or C.row
            b.TextColor3 = on and C.bg or t.col
        end
    end
    survStat.Text = "vol " .. (S.fly and "ON" or "off") ..
        " | traverse " .. (S.noclip and "ON" or "off") ..
        " | esp " .. (S.esp and "ON" or "off") ..
        " | saut infini " .. (S.infjump and "ON" or "off") ..
        "\nv" .. S.vs .. " | plateforme " .. (S.platform and "ON" or "off")
end

for i = 1, #TOGGLES do
    local t = TOGGLES[i]
    local b = btn(pages[2], {
        Text = t.label, Size = UDim2.new(0.5, -3, 0, 38),
        Position = UDim2.fromOffset(((i - 1) % 2) * 152, 46 + math.floor((i - 1) / 2) * 42),
        TextSize = 10,
    })
    stroke(t.col, b, 1)
    toggleBtns[t.id] = b
    local id = t.id
    b.MouseButton1Click:Connect(function()
        if id == "fly" then
            if S.fly then stopFly() else startFly() end
        elseif id == "noclip" then
            setNoclip(not S.noclip)
        elseif id == "esp" then
            setEsp(not S.esp)
        elseif id == "infjump" then
            S.infjump = not S.infjump
        end
        refreshSurvie()
        logLine("survie: " .. id .. " " .. (S[id] and "ON" or "off"))
    end)
end

local platBtn = btn(pages[2], {
    Text = "PLATEFORME", Size = UDim2.new(1, 0, 0, 36),
    Position = UDim2.fromOffset(0, 136), TextColor3 = C.green, TextSize = 10,
})
stroke(C.green, platBtn, 1)
platBtn.MouseButton1Click:Connect(function()
    togglePlatform()
    refreshSurvie()
    logLine("survie: plateforme " .. (S.platform and "ON" or "off"))
end)

local vsLbl = lbl(pages[2], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 178),
})
local vsMinus = btn(pages[2], {
    Text = "VITESSE -", Size = UDim2.new(0.5, -3, 0, 32),
    Position = UDim2.fromOffset(0, 198), TextSize = 9,
})
local vsPlus = btn(pages[2], {
    Text = "VITESSE +", Size = UDim2.new(0.5, -3, 0, 32),
    Position = UDim2.new(0.5, 3, 0, 198), TextSize = 9,
})
vsMinus.MouseButton1Click:Connect(function()
    S.vs = math.max(10, S.vs - 10)
    refreshSurvie()
end)
vsPlus.MouseButton1Click:Connect(function()
    S.vs = math.min(200, S.vs + 10)
    refreshSurvie()
end)

local compassBtn = btn(pages[2], {
    Text = "TIRER COMPASS", Size = UDim2.new(1, 0, 0, 32),
    Position = UDim2.fromOffset(0, 238), TextColor3 = C.amber, TextSize = 10,
})
compassBtn.MouseButton1Click:Connect(function()
    local c = RS:FindFirstChild("Remotes")
    local comp = c and c:FindFirstChild("Compass")
    if comp then
        local ok = pcall(function() comp:FireServer() end)
        logLine(ok and "compass: tire" or "compass: erreur")
    else
        logLine("compass: introuvable")
    end
end)

local noteSurv = lbl(pages[2], {
    Text = "nds est serveur autoritaire : les degats, les catastrophes et le round ne se forcent pas depuis le client. ces outils agissent sur ton personnage seulement.",
    Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 278),
    TextWrapped = true,
})

refreshSurvie()

--===============================================================
-- page LOG
--===============================================================
local logScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -34),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.amber, AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0),
}, pages[3])
logBox = lbl(logScroll, {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -8, 0, 0), Position = UDim2.fromOffset(2, 0),
    TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
    TextYAlignment = Enum.TextYAlignment.Top,
})

local clearLogBtn = btn(pages[3], {
    Text = "VIDER", Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.new(0, 0, 1, -28), TextColor3 = C.red, TextSize = 9,
})
clearLogBtn.MouseButton1Click:Connect(function()
    LOG = {}
    if logBox then logBox.Text = "" end
end)

refreshLog = function()
    if logBox then logBox.Text = table.concat(LOG, "\n") end
end

--===============================================================
-- saut infini
--===============================================================
UIS.JumpRequest:Connect(function()
    if not S.infjump then return end
    local h = hum()
    if h then
        pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end)

--===============================================================
-- drag + close
--===============================================================
closeBtn.MouseButton1Click:Connect(function() win.Visible = false end)

local dragging, dStart, pStart = false, nil, nil
drag.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dStart, pStart = true, i.Position, win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - dStart
        win.Position = UDim2.new(pStart.X.Scale, pStart.X.Offset + d.X,
            pStart.Y.Scale, pStart.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

--===============================================================
-- boot
--===============================================================
win.Visible = true
local n = scanRemotes()
rebuildSonde()
refreshSonde()
setTab(1)
logLine("boot: " .. n .. " remotes de jeu (moteur exclus)")

LP.CharacterAdded:Connect(function()
    task.wait(0.9)
    if S.fly then startFly() end
    if S.noclip then setNoclip(true) end
    if S.esp then setEsp(true) end
    refreshSurvie()
end)
