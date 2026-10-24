--===============================================================
-- lolpanel NDS CIBLE
-- sonde fine sur les remotes actifs + chasse au nom d'argument
-- Delta / Android. 3 onglets: CIBLE / CATALOGUE / LOG
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
local refreshCible, refreshLog, rebuildChips, rebuildCatalog

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
-- remotes du jeu
--===============================================================
local ENGINE_ROOTS = {
    ["RobloxReplicatedStorage"] = true,
    ["RobloxSecurity"] = true,
}

local REMOTES = {}
local SELECTED = nil

local PREFERRED = { "Compass", "Lab", "Event", "Server", "Round", "Award" }

local function preferRank(name)
    for i = 1, #PREFERRED do
        if name == PREFERRED[i] then return i end
    end
    return 100
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
                local isTool = path:find("Backpack", 1, true) ~= nil
                table.insert(REMOTES, {
                    o = o, path = path, cls = cls, name = o.Name,
                    rank = preferRank(o.Name) + (isTool and 50 or 0),
                })
            end
        end
        if i > 90000 then break end
    end
    table.sort(REMOTES, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.path:lower() < b.path:lower()
    end)
    if #REMOTES > 0 and not SELECTED then SELECTED = REMOTES[1] end
    return #REMOTES
end

--===============================================================
-- delta
--===============================================================
local function snap()
    local s = { ws = {}, bp = {}, pos = nil, hp = nil, toolNames = {} }
    local ok1, kids = pcall(function() return workspace:GetChildren() end)
    if ok1 then
        for _, c in ipairs(kids) do s.ws[c] = c.Name end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        local ok2, items = pcall(function() return bp:GetChildren() end)
        if ok2 then
            for _, it in ipairs(items) do
                s.bp[it] = true
                table.insert(s.toolNames, it.Name)
            end
        end
    end
    local r = root()
    if r then s.pos = r.Position end
    local h = hum()
    if h then s.hp = h.Health end
    return s
end

local function diff(a, b)
    local bits = {}
    for k, nameIn in pairs(b.ws) do
        if not a.ws[k] then table.insert(bits, "+ws:" .. nameIn) end
    end
    for k in pairs(b.bp) do
        if not a.bp[k] then table.insert(bits, "+outil:" .. k.Name) end
    end
    if a.pos and b.pos then
        local d = (b.pos - a.pos).Magnitude
        if d > 3 then table.insert(bits, "tp:" .. math.floor(d)) end
    end
    if a.hp and b.hp and math.abs(a.hp - b.hp) > 0.5 then
        table.insert(bits, "hp:" .. math.floor(b.hp - a.hp))
    end
    if #bits == 0 then return nil end
    return table.concat(bits, " ")
end

--===============================================================
-- payloads
--===============================================================
local MODES = {
    { id = "rien", label = "RIEN" },
    { id = "string", label = "TEXTE" },
    { id = "nombre", label = "NOMBRE" },
    { id = "bool", label = "BOOL" },
    { id = "moi", label = "MOI" },
    { id = "part", label = "PART" },
    { id = "vec3", label = "VEC3" },
    { id = "nom+1", label = "TEXTE+1" },
}

local MODE = "string"
local TEXTARG = "Compass"
local REPEAT = 1

local function buildArgs()
    if MODE == "rien" then return {} end
    if MODE == "string" then return { TEXTARG } end
    if MODE == "nombre" then return { tonumber(TEXTARG) or 1 } end
    if MODE == "bool" then return { true } end
    if MODE == "moi" then return { LP } end
    if MODE == "part" then return { root() } end
    if MODE == "vec3" then return { Vector3.new(0, 60, 0) } end
    if MODE == "nom+1" then return { TEXTARG, 1 } end
    return {}
end

local Shot = { on = false, count = 0, hits = 0 }

local function callOnce(entry, args)
    if not entry or not entry.o or not entry.o.Parent then return false end
    if entry.cls == "RemoteFunction" then
        local ok = pcall(function() entry.o:InvokeServer(table.unpack(args)) end)
        return ok
    end
    local ok = pcall(function() entry.o:FireServer(table.unpack(args)) end)
    return ok
end

local function shoot(times, silent)
    if Shot.on then return end
    local entry = SELECTED
    if not entry or not entry.o or not entry.o.Parent then
        logLine("tir: remote absent")
        return
    end
    Shot.on = true
    local label = entry.name .. "(" .. MODE .. (MODE == "string" and (":" .. TEXTARG) or "") .. ")"
    for i = 1, math.max(1, times) do
        if not Shot.on then break end
        local before = snap()
        local ok = callOnce(entry, buildArgs())
        Shot.count = Shot.count + 1
        task.wait(0.34)
        local after = snap()
        local d = diff(before, after)
        if not ok then
            if not silent then logLine("#" .. i .. " " .. label .. " -> refus") end
        elseif d then
            Shot.hits = Shot.hits + 1
            logLine("#" .. i .. " " .. label .. " -> " .. d)
        else
            if not silent then logLine("#" .. i .. " " .. label .. " -> rien") end
        end
        if not silent then refreshCible() end
    end
    Shot.on = false
    refreshCible()
end

--===============================================================
-- catalogue
--===============================================================
local CATALOG = {}
local CATSCAN = { inst = 0, names = 0 }

local HOT_WORDS = {
    "sword", "gun", "weapon", "tool", "item", "kit", "med", "food",
    "apple", "compass", "brick", "part", "block", "bomb", "rocket",
    "shield", "armor", "hat", "ball", "cup", "trophy", "coin",
}

local function hotScore(name)
    local low = name:lower()
    for i = 1, #HOT_WORDS do
        if low:find(HOT_WORDS[i], 1, true) then return i end
    end
    return 999
end

local function scanCatalog()
    CATALOG = {}
    CATSCAN = { inst = 0, names = 0 }
    local seen = {}
    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("StarterPack"),
        game:GetService("Workspace"),
        game:GetService("Lighting"),
    }
    for ri = 1, #roots do
        local ok, desc = pcall(function() return roots[ri]:GetDescendants() end)
        if ok then
            for i = 1, #desc do
                local o = desc[i]
                if not o then break end
                CATSCAN.inst = CATSCAN.inst + 1
                local cls = o.ClassName
                if cls == "Tool" or cls == "Model" or cls == "BasePart"
                    or cls == "Accessory" then
                    local n = o.Name
                    if #n >= 3 and not seen[n] then
                        seen[n] = true
                        table.insert(CATALOG, { name = n, cls = cls, hot = hotScore(n) })
                    end
                end
                if CATSCAN.inst > 80000 then break end
            end
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        local bp = p:FindFirstChild("Backpack")
        if bp then
            for _, it in ipairs(bp:GetChildren()) do
                if not seen[it.Name] then
                    seen[it.Name] = true
                    table.insert(CATALOG, { name = it.Name, cls = it.ClassName, hot = hotScore(it.Name) })
                end
            end
        end
    end
    table.sort(CATALOG, function(a, b)
        if a.hot ~= b.hot then return a.hot < b.hot end
        return a.name:lower() < b.name:lower()
    end)
    CATSCAN.names = #CATALOG
    return #CATALOG
end

--===============================================================
-- chasse automatique
--===============================================================
local Hunt = { on = false, tested = 0, found = 0, limit = 60 }

local function huntNames()
    if Hunt.on then return end
    local entry = SELECTED
    if not entry then
        logLine("chasse: aucune cible")
        return
    end
    if #CATALOG == 0 then scanCatalog() end
    Hunt.on = true
    Hunt.tested = 0
    Hunt.found = 0
    local savedMode, savedText = MODE, TEXTARG
    MODE = "string"
    local cap = math.min(Hunt.limit, #CATALOG)
    logLine("chasse: " .. entry.name .. " contre " .. cap .. " noms")
    for i = 1, cap do
        if not Hunt.on then break end
        local name = CATALOG[i].name
        TEXTARG = name
        local before = snap()
        callOnce(entry, { name })
        Hunt.tested = Hunt.tested + 1
        task.wait(0.36)
        local after = snap()
        local d = diff(before, after)
        if d then
            Hunt.found = Hunt.found + 1
            logLine("TROUVE " .. entry.name .. "(\"" .. name .. "\") -> " .. d)
        end
        if i % 5 == 0 then refreshCible() end
    end
    MODE = savedMode
    TEXTARG = savedText
    Hunt.on = false
    refreshCible()
    logLine("chasse: fin, " .. Hunt.found .. " prises sur " .. Hunt.tested)
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
    local old = getgenv()._nds2
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._nds2 = gui
end

local W, H = 322, 480
local win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 6, 0, 64),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.violet, Thickness = 1, Transparency = 0.4 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "CIBLE", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.violet, Size = UDim2.fromOffset(150, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})

local TABS = { "CIBLE", "CATALOGUE", "LOG" }
local tabBtns, pages = {}, {}
local tabW = (W - 20 - 12) / 3

local function setTab(i)
    for k = 1, #pages do
        pages[k].Visible = (k == i)
        tabBtns[k].BackgroundColor3 = (k == i) and C.violet or C.row
        tabBtns[k].TextColor3 = (k == i) and C.bg or C.dim
    end
    if i == 1 then refreshCible() end
    if i == 2 then rebuildCatalog() end
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
    while #LOG > 220 do table.remove(LOG, 1) end
    if logBox then
        logBox.Text = table.concat(LOG, "\n")
        local sc = logBox.Parent
        if sc and sc:IsA("ScrollingFrame") then
            pcall(function() sc.CanvasPosition = Vector2.new(0, 99999) end)
        end
    end
end

--===============================================================
-- page CIBLE
--===============================================================
local remoteBar = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollingDirection = Enum.ScrollingDirection.X,
    AutomaticCanvasSize = Enum.AutomaticSize.X,
}, pages[1])
mk("UIListLayout", {
    Padding = UDim.new(0, 4), FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
}, remoteBar)

local chipRefs = {}

rebuildChips = function()
    clearChildren(remoteBar)
    chipRefs = {}
    local shown = math.min(#REMOTES, 14)
    for i = 1, shown do
        local e = REMOTES[i]
        local b = btn(remoteBar, {
            Text = e.name, Size = UDim2.fromOffset(74, 22), TextSize = 8,
            LayoutOrder = i, BackgroundColor3 = C.row,
        })
        chipRefs[e] = b
        local entry = e
        b.MouseButton1Click:Connect(function()
            SELECTED = entry
            refreshCible()
            logLine("cible: " .. entry.path)
        end)
    end
    local scanChip = btn(remoteBar, {
        Text = "RESCAN", Size = UDim2.fromOffset(66, 22), TextSize = 8,
        LayoutOrder = 99, TextColor3 = C.green,
    })
    scanChip.MouseButton1Click:Connect(function()
        scanRemotes()
        rebuildChips()
        refreshCible()
        logLine("rescan: " .. #REMOTES .. " remotes")
    end)
end

local cibleStat = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 28),
    TextWrapped = true,
})

local modeBar = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 58),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollingDirection = Enum.ScrollingDirection.X,
    AutomaticCanvasSize = Enum.AutomaticSize.X,
}, pages[1])
mk("UIListLayout", {
    Padding = UDim.new(0, 4), FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
}, modeBar)

local modeRefs = {}
for i = 1, #MODES do
    local m = MODES[i]
    local b = btn(modeBar, {
        Text = m.label, Size = UDim2.fromOffset(60, 22), TextSize = 8,
        LayoutOrder = i,
    })
    modeRefs[m.id] = b
    local id = m.id
    b.MouseButton1Click:Connect(function()
        MODE = id
        refreshCible()
    end)
end

local textBox = mk("TextBox", {
    Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 86),
    BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false,
    Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.txt,
    PlaceholderText = "argument texte / nom d'objet...", PlaceholderColor3 = C.dim,
    TextXAlignment = Enum.TextXAlignment.Left, Text = TEXTARG,
}, pages[1])
corner(7, textBox)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, textBox)
textBox:GetPropertyChangedSignal("Text"):Connect(function()
    TEXTARG = textBox.Text
end)

local repLbl = lbl(pages[1], {
    Text = "REPETITIONS", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 120),
})
local repRow = { 1, 5, 20 }
local repRefs = {}
for i = 1, #repRow do
    local b = btn(pages[1], {
        Text = "x" .. repRow[i], Size = UDim2.fromOffset(62, 26),
        Position = UDim2.fromOffset((i - 1) * 68, 138), TextSize = 9,
    })
    repRefs[i] = b
    local v = repRow[i]
    b.MouseButton1Click:Connect(function()
        REPEAT = v
        refreshCible()
    end)
end

local fireBtn = btn(pages[1], {
    Text = "TIRER", Size = UDim2.new(0.5, -3, 0, 38),
    Position = UDim2.fromOffset(0, 172), TextColor3 = C.green, TextSize = 11,
})
stroke(C.green, fireBtn, 1)

local stopBtn = btn(pages[1], {
    Text = "STOP", Size = UDim2.new(0.5, -3, 0, 38),
    Position = UDim2.new(0.5, 3, 0, 172), TextColor3 = C.red, TextSize = 11,
})
stroke(C.red, stopBtn, 1)

local huntBtn = btn(pages[1], {
    Text = "CHASSER LES NOMS (60)", Size = UDim2.new(1, 0, 0, 32),
    Position = UDim2.fromOffset(0, 216), TextColor3 = C.amber, TextSize = 10,
})
stroke(C.amber, huntBtn, 1)

local lastLbl = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.blue,
    Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 252),
    TextWrapped = true,
})

local hitsLbl = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.green,
    Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 290),
})

local bitNote = lbl(pages[1], {
    Text = "un tir toutes les 0.34s. si un nom atterrit dans le sac, c'est gagne.",
    Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 312),
    TextWrapped = true,
})

refreshCible = function()
    for e, b in pairs(chipRefs) do
        if e == SELECTED then
            b.BackgroundColor3 = C.violet
            b.TextColor3 = C.bg
        else
            b.BackgroundColor3 = C.row
            b.TextColor3 = C.txt
        end
    end
    for id, b in pairs(modeRefs) do
        if id == MODE then
            b.BackgroundColor3 = C.amber
            b.TextColor3 = C.bg
        else
            b.BackgroundColor3 = C.row
            b.TextColor3 = C.dim
        end
    end
    for i = 1, #repRefs do
        if repRow[i] == REPEAT then
            repRefs[i].BackgroundColor3 = C.blue
            repRefs[i].TextColor3 = C.bg
        else
            repRefs[i].BackgroundColor3 = C.row
            repRefs[i].TextColor3 = C.dim
        end
    end
    local e = SELECTED
    cibleStat.Text = (e and (e.path .. "  [" .. (e.cls == "RemoteEvent" and "RE" or "RF") .. "]") or "aucune cible") ..
        "\nenvoye " .. Shot.count .. " | prises " .. Shot.hits
    fireBtn.Text = Shot.on and "..." or "TIRER"
    huntBtn.Text = Hunt.on and ("CHASSE " .. Hunt.tested .. "/" .. math.min(Hunt.limit, #CATALOG or 0)) or "CHASSER LES NOMS (60)"
    hitsLbl.Text = "prises: " .. Shot.hits .. "  |  chasse: " .. Hunt.found .. "/" .. Hunt.tested ..
        "  |  catalogue: " .. #CATALOG
    if #LOG > 0 then
        lastLbl.Text = LOG[#LOG]
    end
end

fireBtn.MouseButton1Click:Connect(function()
    if Shot.on then return end
    task.spawn(function() shoot(REPEAT, false) end)
end)

stopBtn.MouseButton1Click:Connect(function()
    Shot.on = false
    Hunt.on = false
    refreshCible()
    logLine("stop")
end)

huntBtn.MouseButton1Click:Connect(function()
    if Hunt.on then return end
    task.spawn(function() huntNames() end)
end)

--===============================================================
-- page CATALOGUE
--===============================================================
local catInfo = lbl(pages[2], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 0),
    TextWrapped = true,
})

local catList = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 300), Position = UDim2.fromOffset(0, 28),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = C.violet,
    ScrollBarImageTransparency = 0.4, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pages[2])
mk("UIListLayout", {
    Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
}, catList)
mk("UIPadding", { PaddingRight = UDim.new(0, 6) }, catList)

local rescanBtn = btn(pages[2], {
    Text = "RESCANNER LE CATALOGUE", Size = UDim2.new(0.5, -3, 0, 30),
    Position = UDim2.fromOffset(0, 336), TextColor3 = C.green, TextSize = 9,
})

local testAllBtn = btn(pages[2], {
    Text = "TESTER LES 60 PREMIERS", Size = UDim2.new(0.5, -3, 0, 30),
    Position = UDim2.new(0.5, 3, 0, 336), TextColor3 = C.amber, TextSize = 8,
})

rebuildCatalog = function()
    clearChildren(catList)
    for i = 1, math.min(#CATALOG, 140) do
        local it = CATALOG[i]
        local f = mk("TextButton", {
            Size = UDim2.new(1, -2, 0, 30), BackgroundColor3 = C.row,
            BorderSizePixel = 0, Text = "", LayoutOrder = i,
            AutoButtonColor = true, ClipsDescendants = true,
        }, catList)
        corner(6, f)
        mk("UIPadding", { PaddingLeft = UDim.new(0, 7) }, f)
        lbl(f, {
            Text = it.name, Font = Enum.Font.Code, TextSize = 8,
            TextColor3 = it.hot < 999 and C.amber or C.txt,
            Size = UDim2.new(1, -70, 0, 30), Position = UDim2.fromOffset(0, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        lbl(f, {
            Text = it.cls:gsub("BasePart", "Part"):gsub("Model", "Mod"),
            Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
            Size = UDim2.fromOffset(56, 30), Position = UDim2.new(1, -60, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
        })
        local name = it.name
        f.MouseButton1Click:Connect(function()
            TEXTARG = name
            textBox.Text = name
            MODE = "string"
            setTab(1)
            refreshCible()
            logLine("catalogue: \"" .. name .. "\" charge dans la cible")
        end)
    end
    if #CATALOG == 0 then
        lbl(catList, {
            Text = "catalogue vide — rescanne", Font = Enum.Font.Code,
            TextSize = 9, TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 26),
        })
    end
    catInfo.Text = CATSCAN.names .. " noms uniques | " .. CATSCAN.inst .. " instances lues" ..
        "\ntap un nom pour le charger dans la cible"
end

rescanBtn.MouseButton1Click:Connect(function()
    local n = scanCatalog()
    rebuildCatalog()
    logLine("catalogue: " .. n .. " noms")
end)

testAllBtn.MouseButton1Click:Connect(function()
    if Hunt.on then return end
    task.spawn(function() huntNames() end)
end)

--===============================================================
-- page LOG
--===============================================================
local logScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -64),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.violet, AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0),
}, pages[3])
logBox = lbl(logScroll, {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -8, 0, 0), Position = UDim2.fromOffset(2, 0),
    TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
    TextYAlignment = Enum.TextYAlignment.Top,
})

local copyLogBtn = btn(pages[3], {
    Text = "COPIER LE JOURNAL", Size = UDim2.new(0.5, -3, 0, 28),
    Position = UDim2.new(0, 0, 1, -58), TextColor3 = C.blue, TextSize = 9,
})
local clearLogBtn = btn(pages[3], {
    Text = "VIDER", Size = UDim2.new(0.5, -3, 0, 28),
    Position = UDim2.new(0.5, 3, 1, -58), TextColor3 = C.red, TextSize = 9,
})
local logNote = lbl(pages[3], {
    Text = "les lignes TROUVE sont celles a m'envoyer",
    Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -30),
    TextWrapped = true,
})

copyLogBtn.MouseButton1Click:Connect(function()
    local txt = table.concat(LOG, "\n")
    local ok = pcall(function() setclipboard(txt) end)
    logLine(ok and ("journal copie (" .. #txt .. " octets)") or "copie refusee")
end)

clearLogBtn.MouseButton1Click:Connect(function()
    LOG = {}
    if logBox then logBox.Text = "" end
end)

refreshLog = function()
    if logBox then logBox.Text = table.concat(LOG, "\n") end
end

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
rebuildChips()
refreshCible()
setTab(1)
logLine("boot: " .. n .. " remotes | cible " .. (SELECTED and SELECTED.name or "aucune"))

task.spawn(function()
    local c = scanCatalog()
    rebuildCatalog()
    logLine("catalogue: " .. c .. " noms")
end)

LP.CharacterAdded:Connect(function()
    task.wait(0.9)
    refreshCible()
end)
