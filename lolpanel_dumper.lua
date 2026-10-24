--===============================================================
-- lolpanel DUMPER
-- liste tous les remotes du jeu: chemin exact, type, args, categorie.
-- export copiable pour transmission. Delta / Android.
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    blue = Color3.fromRGB(120, 180, 255), violet = Color3.fromRGB(190, 150, 255),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
}

local logLine

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

local function box(parent, props)
    local t = { BackgroundColor3 = C.row, BorderSizePixel = 0,
        ClearTextOnFocus = false, Font = Enum.Font.Code, TextSize = 10,
        TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left,
        PlaceholderColor3 = C.dim, Text = "", MultiLine = false }
    for k, v in pairs(props or {}) do t[k] = v end
    local b = mk("TextBox", t, parent)
    corner(7, b)
    return b
end

local function clearChildren(s)
    for _, ch in ipairs(s:GetChildren()) do
        if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding")
            and not ch:IsA("UIGridLayout") then
            pcall(function() ch:Destroy() end)
        end
    end
end

--===============================================================
-- categories
--===============================================================
local CATS = {
    { id = "kill", label = "KILL", col = Color3.fromRGB(255, 84, 94), words = {
        "kill", "damage", "hurt", "attack", "hit", "slay", "eliminate",
        "wound", "stab", "shoot", "elim", "death", "die", "health", "hp" } },
    { id = "flam", label = "FLAM", col = Color3.fromRGB(255, 130, 60), words = {
        "flame", "fire", "burn", "ignite", "torch", "lava", "blaze", "explode", "boom" } },
    { id = "give", label = "GIVE", col = Color3.fromRGB(255, 220, 90), words = {
        "give", "grant", "award", "tool", "item", "weapon", "equip", "drop", "reward" } },
    { id = "brick", label = "BRICK", col = Color3.fromRGB(160, 220, 120), words = {
        "brick", "part", "block", "create", "clone", "place", "build", "spawn", "summon", "add" } },
    { id = "tele", label = "TELE", col = Color3.fromRGB(120, 180, 255), words = {
        "teleport", "tp", "warp", "move", "position", "goto", "setpos", "cframe", "velocity" } },
    { id = "admin", label = "ADMIN", col = Color3.fromRGB(190, 150, 255), words = {
        "admin", "ban", "kick", "command", "cmd", "console", "exec", "mod", "staff", "rank" } },
    { id = "data", label = "DATA", col = Color3.fromRGB(140, 200, 210), words = {
        "get", "fetch", "request", "data", "info", "stats", "profile", "save", "load", "update", "set" } },
}

local function categorize(name)
    local low = name:lower()
    local best, bestPos = nil, 99999
    for i = 1, #CATS do
        local cat = CATS[i]
        for w = 1, #cat.words do
            local pos = low:find(cat.words[w], 1, true)
            if pos and pos < bestPos then
                bestPos = pos
                best = cat
            end
        end
    end
    return best
end

--===============================================================
-- scan
--===============================================================
local REMOTES = {}
local ARGMAP = {}
local SCANNED = { total = 0, scripts = 0, srcOK = 0 }

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

local function countArgs(s)
    if not s or s == "" then return 0 end
    local n = 1
    for _ in string.gmatch(s, ",") do n = n + 1 end
    return n
end

local function harvestArgs(src)
    if not src then return end
    for name, args in string.gmatch(src, "([%w_]+)%s*:%s*FireServer%s*%(([^()]*)%)") do
        local n = countArgs(args)
        if not ARGMAP[name] or ARGMAP[name] < n then ARGMAP[name] = n end
    end
    for name, args in string.gmatch(src, "([%w_]+)%s*:%s*InvokeServer%s*%(([^()]*)%)") do
        local n = countArgs(args)
        if not ARGMAP[name] or ARGMAP[name] < n then ARGMAP[name] = n end
    end
    for name, args in string.gmatch(src, "([%w_]+)%s*:%s*CallServer%s*%(([^()]*)%)") do
        local n = countArgs(args)
        if not ARGMAP[name] or ARGMAP[name] < n then ARGMAP[name] = n end
    end
end

local function scanAll()
    REMOTES = {}
    ARGMAP = {}
    SCANNED = { total = 0, scripts = 0, srcOK = 0 }

    local ok, desc = pcall(function() return game:GetDescendants() end)
    if not ok then
        logLine("scan: impossible de parcourir game")
        return 0
    end
    SCANNED.total = #desc

    local found, seen = {}, {}
    local scripts = {}

    for i = 1, #desc do
        local o = desc[i]
        if not o then break end
        local cls = o.ClassName
        if cls == "RemoteEvent" or cls == "RemoteFunction" then
            if not seen[o] then
                seen[o] = true
                table.insert(found, o)
            end
        elseif (cls == "LocalScript" or cls == "ModuleScript") and #scripts < 220 then
            table.insert(scripts, o)
        end
        if i > 90000 then break end
    end

    for i = 1, #scripts do
        local s = scripts[i]
        SCANNED.scripts = SCANNED.scripts + 1
        local ok2, src = pcall(function() return s.Source end)
        if ok2 and type(src) == "string" and #src > 0 and #src < 400000 then
            SCANNED.srcOK = SCANNED.srcOK + 1
            harvestArgs(src)
        end
    end

    for i = 1, #found do
        local o = found[i]
        local short = o.Name
        local cat = categorize(short)
        local args = ARGMAP[short] or 0
        local score = 999
        if cat then
            score = cat.id == "data" and 50 or 10
            if args > 0 then score = score - 5 end
        end
        table.insert(REMOTES, {
            o = o,
            short = short,
            path = buildPath(o),
            cls = o.ClassName == "RemoteEvent" and "RE" or "RF",
            args = args,
            cat = cat and cat.id or "none",
            catLabel = cat and cat.label or "----",
            col = cat and cat.col or C.dim,
            score = score,
        })
    end

    table.sort(REMOTES, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.path:lower() < b.path:lower()
    end)

    return #REMOTES
end

--===============================================================
-- export
--===============================================================
local function nowStamp()
    local ok, d = pcall(function()
        return os.date("%Y-%m-%d %H:%M")
    end)
    return ok and d or "?"
end

local function buildExport(onlySuspects)
    local out = {}
    table.insert(out, "lolpanel DUMPER")
    table.insert(out, "date: " .. nowStamp())
    table.insert(out, "place: " .. tostring(game.PlaceId))
    table.insert(out, "job: " .. tostring(game.JobId))
    table.insert(out, "instances: " .. SCANNED.total)
    table.insert(out, "scripts lus: " .. SCANNED.srcOK .. "/" .. SCANNED.scripts)

    local pool = {}
    for i = 1, #REMOTES do
        local r = REMOTES[i]
        if (not onlySuspects) or r.cat ~= "none" then
            table.insert(pool, r)
        end
    end

    table.insert(out, "remotes: " .. #pool .. "/" .. #REMOTES)
    table.insert(out, "")
    table.insert(out, "format: [CAT] Chemin/Serv/Remote | RE|RF | nbargs")
    table.insert(out, "")

    local order = {}
    for i = 1, #CATS do order[#order + 1] = CATS[i].id end
    order[#order + 1] = "none"

    local written = 0
    for k = 1, #order do
        local id = order[k]
        local group = {}
        for i = 1, #pool do
            if pool[i].cat == id then table.insert(group, pool[i]) end
        end
        if #group > 0 then
            local label = id == "none" and "AUTRES" or string.upper(id)
            table.insert(out, "=== " .. label .. " (" .. #group .. ") ===")
            for i = 1, #group do
                local r = group[i]
                table.insert(out, "[" .. r.catLabel .. "] " .. r.path ..
                    " | " .. r.cls .. " | " .. r.args)
                written = written + 1
                if written >= 900 then break end
            end
            table.insert(out, "")
            if written >= 900 then
                table.insert(out, "... tronque a 900 lignes")
                break
            end
        end
    end

    return table.concat(out, "\n")
end

local function copyText(t)
    local ok = pcall(function() setclipboard(t) end)
    return ok
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
    local old = getgenv()._dx
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._dx = gui
end

local W, H = 322, 470
local win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 6, 0, 70),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.blue, Thickness = 1, Transparency = 0.4 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "DUMPER", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.blue, Size = UDim2.fromOffset(150, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})

local TABS = { "LISTE", "EXPORT" }
local tabBtns, pages = {}, {}
local tabW = (W - 20 - 6) / 2

local refreshList, refreshExport, rebuildRows

local function setTab(i)
    for k = 1, #pages do
        pages[k].Visible = (k == i)
        tabBtns[k].BackgroundColor3 = (k == i) and C.blue or C.row
        tabBtns[k].TextColor3 = (k == i) and C.bg or C.dim
    end
    if i == 1 then refreshList() end
    if i == 2 then refreshExport() end
end

for i = 1, 2 do
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
local statusLbl

logLine = function(txt)
    table.insert(LOG, tostring(txt))
    while #LOG > 40 do table.remove(LOG, 1) end
    if statusLbl then
        statusLbl.Text = tostring(txt)
    end
end

--===============================================================
-- page LISTE
--===============================================================
local searchBox = box(pages[1], {
    Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 0),
    PlaceholderText = "filtrer par nom...",
})
mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, searchBox)

local chipBar = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 32),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollingDirection = Enum.ScrollingDirection.X,
    AutomaticCanvasSize = Enum.AutomaticSize.X,
}, pages[1])
mk("UIListLayout", {
    Padding = UDim.new(0, 4), FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
}, chipBar)

local FILTER = "all"
local CHIP_REFS = {}

local function makeChip(id, label, col, order)
    local b = btn(chipBar, {
        Text = label, Size = UDim2.fromOffset(56, 22), TextSize = 8,
        LayoutOrder = order, BackgroundColor3 = C.row, TextColor3 = col or C.dim,
    })
    CHIP_REFS[id] = b
    b.MouseButton1Click:Connect(function()
        FILTER = id
        refreshList()
    end)
end

makeChip("all", "TOUT", C.txt, 1)
for i = 1, #CATS do
    makeChip(CATS[i].id, CATS[i].label, CATS[i].col, i + 1)
end
makeChip("all2", "RESCAN", C.green, #CATS + 2)
CHIP_REFS["all2"].MouseButton1Click:Connect(function()
    FILTER = "all2"
    local n = scanAll()
    logLine("rescan: " .. n .. " remotes")
    refreshList()
    refreshExport()
end)

local list = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 242), Position = UDim2.fromOffset(0, 60),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = C.blue,
    ScrollBarImageTransparency = 0.4, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pages[1])
mk("UIListLayout", {
    Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
}, list)
mk("UIPadding", { PaddingRight = UDim.new(0, 6) }, list)

local suspectBtn = btn(pages[1], {
    Text = "COPIER LES SUSPECTS", Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.fromOffset(0, 336), TextColor3 = C.green, TextSize = 10,
})
stroke(C.green, suspectBtn, 1)

local countLbl = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 304),
})

statusLbl = lbl(pages[1], {
    Text = "pret", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 319),
    TextTruncate = Enum.TextTruncate.AtEnd,
})

local function rowMatches(r)
    if FILTER ~= "all" and FILTER ~= "all2" then
        if r.cat ~= FILTER then return false end
    end
    local q = searchBox.Text
    if q and q ~= "" then
        if not r.path:lower():find(q:lower(), 1, true) then return false end
    end
    return true
end

rebuildRows = function()
    clearChildren(list)
    local shown, total = 0, 0
    for i = 1, #REMOTES do
        local r = REMOTES[i]
        if rowMatches(r) then
            total = total + 1
            if shown < 200 then
                shown = shown + 1
                local f = mk("TextButton", {
                    Size = UDim2.new(1, -2, 0, 32), BackgroundColor3 = C.row,
                    BorderSizePixel = 0, Text = "", AutoButtonColor = true,
                    LayoutOrder = shown, ClipsDescendants = true,
                }, list)
                corner(6, f)
                mk("UIPadding", { PaddingLeft = UDim.new(0, 6) }, f)

                local tag = lbl(f, {
                    Text = r.catLabel, Font = Enum.Font.GothamBold, TextSize = 8,
                    TextColor3 = r.col, Size = UDim2.fromOffset(40, 32),
                    Position = UDim2.fromOffset(0, 0),
                })

                local meta = lbl(f, {
                    Text = r.cls .. " " .. r.args, Font = Enum.Font.Code, TextSize = 8,
                    TextColor3 = r.args > 0 and C.amber or C.dim,
                    Size = UDim2.fromOffset(40, 32), Position = UDim2.new(1, -42, 0, 0),
                    TextXAlignment = Enum.TextXAlignment.Right,
                })

                lbl(f, {
                    Text = r.path, Font = Enum.Font.Code, TextSize = 8,
                    TextColor3 = C.txt, Size = UDim2.new(1, -96, 0, 32),
                    Position = UDim2.fromOffset(42, 0),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })

                local text = r.path
                f.MouseButton1Click:Connect(function()
                    if copyText(text) then
                        logLine("copie: " .. r.short)
                    else
                        logLine("copie impossible: " .. r.short)
                    end
                end)
            end
        end
    end
    if total == 0 then
        lbl(list, {
            Text = "aucun remote pour ce filtre", Font = Enum.Font.Code,
            TextSize = 9, TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 26),
        })
    end
    countLbl.Text = shown .. " affiches / " .. total .. " filtres / " .. #REMOTES .. " total"
end

refreshList = function()
    for id, b in pairs(CHIP_REFS) do
        local active = (id == FILTER) and id ~= "all2"
        if id == "all2" then
            b.BackgroundColor3 = C.row
            b.TextColor3 = C.green
        elseif active then
            b.BackgroundColor3 = C.blue
            b.TextColor3 = C.bg
        else
            b.BackgroundColor3 = C.row
            local cat
            for i = 1, #CATS do
                if CATS[i].id == id then cat = CATS[i] end
            end
            b.TextColor3 = cat and cat.col or C.txt
        end
    end
    rebuildRows()
end

suspectBtn.MouseButton1Click:Connect(function()
    local txt = buildExport(true)
    if copyText(txt) then
        logLine("copie: " .. #txt .. " octets de suspects")
    else
        logLine("copie refusee — onglet EXPORT")
        setTab(2)
        refreshExport()
    end
end)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    rebuildRows()
end)

--===============================================================
-- page EXPORT
--===============================================================
local exportBox = mk("TextBox", {
    Size = UDim2.new(1, 0, 1, -90), Position = UDim2.fromOffset(0, 0),
    BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false,
    Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.txt,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true, MultiLine = true, Text = "",
}, pages[2])
pcall(function() exportBox.TextEditable = false end)
corner(7, exportBox)
mk("UIPadding", {
    PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
    PaddingTop = UDim.new(0, 6),
}, exportBox)

local copyAllBtn = btn(pages[2], {
    Text = "COPIER TOUT", Size = UDim2.new(0.5, -3, 0, 34),
    Position = UDim2.new(0, 0, 1, -84), TextColor3 = C.green, TextSize = 10,
})
stroke(C.green, copyAllBtn, 1)

local copySusBtn = btn(pages[2], {
    Text = "COPIER SUSPECTS", Size = UDim2.new(0.5, -3, 0, 34),
    Position = UDim2.new(0.5, 3, 1, -84), TextColor3 = C.amber, TextSize = 9,
})
stroke(C.amber, copySusBtn, 1)

local exportInfo = lbl(pages[2], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -46),
})

local exportHint = lbl(pages[2], {
    Text = "si la copie echoue, reste appuye dans la zone et selectionne tout",
    Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -30),
    TextWrapped = true,
})

refreshExport = function()
    local txt = buildExport(false)
    exportBox.Text = txt
    local suspects = 0
    for i = 1, #REMOTES do
        if REMOTES[i].cat ~= "none" then suspects = suspects + 1 end
    end
    exportInfo.Text = #REMOTES .. " remotes | " .. suspects .. " suspects | " .. #txt .. " octets"
end

copyAllBtn.MouseButton1Click:Connect(function()
    if copyText(exportBox.Text) then
        logLine("copie: dump complet")
    else
        logLine("copie refusee — selection manuelle")
    end
end)

copySusBtn.MouseButton1Click:Connect(function()
    local txt = buildExport(true)
    if copyText(txt) then
        logLine("copie: " .. #txt .. " octets de suspects")
    else
        logLine("copie refusee — selection manuelle")
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
setTab(1)
local n = scanAll()
refreshList()
refreshExport()
logLine("scan: " .. n .. " remotes | " .. SCANNED.srcOK .. "/" .. SCANNED.scripts .. " scripts lisibles")

LP.CharacterAdded:Connect(function()
    task.wait(1.0)
    refreshList()
    refreshExport()
end)
