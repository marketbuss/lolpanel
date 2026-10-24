--===============================================================
-- lolpanel SPAWN
-- panneau de spawn: vehicules, modeles, outils, parts
-- Delta / Android. 4 onglets: SPAWN / CATALOGUE / OUTILS / LOG
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RF = game:GetService("ReplicatedFirst")
local LP = Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    blue = Color3.fromRGB(120, 180, 255),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
}

local CFG = {
    mode = "LOCAL", anchor = true, seat = false, atAim = false,
    jitter = true, budgetMax = 60, budgetWindow = 60,
    jitterMin = 0.04, jitterMax = 0.13,
    search = "",
}

local logLine
local statLbl

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

local function makeList(parent)
    local s = mk("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.amber,
        ScrollBarImageTransparency = 0.45, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, parent)
    mk("UIListLayout", {
        Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
    }, s)
    mk("UIPadding", { PaddingRight = UDim.new(0, 6) }, s)
    return s
end

local function clearList(s)
    for _, ch in ipairs(s:GetChildren()) do
        if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
            pcall(function() ch:Destroy() end)
        end
    end
end

--===============================================================
-- scan
--===============================================================
local VEH_HINTS = {
    "car", "truck", "bike", "motor", "boat", "plane", "jet", "heli",
    "tank", "bus", "van", "kart", "train", "ship", "scooter", "atv",
    "vehicle", "ride", "drone", "yacht", "sub",
}

local function looksVehicle(name)
    local n = name:lower()
    for _, k in ipairs(VEH_HINTS) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local CATALOG = {}

local function scanWorld()
    local vehicles = {}
    local rsC, vehC, wsC = {}, {}, {}
    local seen = {}
    local total = 0
    local roots = { RS, RF, workspace }

    for ri = 1, #roots do
        local root = roots[ri]
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                total = total + 1
                if total > 34000 then break end

                if d:IsA("VehicleSeat") then
                    local up = d
                    for _ = 1, 4 do
                        up = up.Parent
                        if not up or up == root then break end
                        vehicles[up] = true
                    end
                end

                local keep = false
                if d:IsA("Tool") then keep = true
                elseif d:IsA("Model") then keep = true
                elseif d:IsA("MeshPart") then keep = true end

                if keep and not seen[d] then
                    local inChar = false
                    pcall(function()
                        if LP.Character and d:IsDescendantOf(LP.Character) then inChar = true end
                    end)
                    if not inChar then
                        seen[d] = true
                        local entry = { inst = d, name = d.Name, class = d.ClassName }
                        if ri == 3 then
                            table.insert(wsC, entry)
                        elseif d:IsA("Tool") or d:IsA("MeshPart") then
                            table.insert(rsC, entry)
                        else
                            table.insert(rsC, entry)
                        end
                        if #rsC + #wsC > 900 then break end
                    end
                end
            end
        end
        if total > 34000 then break end
    end

    local out = {}
    local function push(e)
        if #out >= 400 then return end
        e.veh = vehicles[e.inst] or looksVehicle(e.name)
        table.insert(out, e)
    end

    for i = 1, #rsC do push(rsC[i]) end
    for i = 1, #wsC do push(wsC[i]) end

    table.sort(out, function(a, b)
        if a.veh ~= b.veh then return a.veh end
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then return na < nb end
        return a.class < b.class
    end)
    return out
end

local function countVehicles()
    local n = 0
    for i = 1, #CATALOG do
        if CATALOG[i].veh then n = n + 1 end
    end
    return n
end

--===============================================================
-- gouvernor
--===============================================================
local Gov = { stamps = {} }

local function govOk()
    local now = os.clock()
    while #Gov.stamps > 0 and (now - Gov.stamps[1]) > CFG.budgetWindow do
        table.remove(Gov.stamps, 1)
    end
    return #Gov.stamps < CFG.budgetMax
end

local function govWait()
    if not CFG.jitter then return end
    local d = CFG.jitterMin + math.random() * (CFG.jitterMax - CFG.jitterMin)
    task.wait(d)
end

--===============================================================
-- spawn local
--===============================================================
local Spawned = {}

local function aimPos()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local params = RaycastParams.new()
    local ft
    pcall(function() ft = Enum.RaycastFilterType.Exclude end)
    if not ft then ft = Enum.RaycastFilterType.Blacklist end
    params.FilterType = ft
    params.FilterDescendantsInstances = { LP.Character }
    params.IgnoreWater = true
    local res = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 300, params)
    if res then return CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
    return nil
end

local function baseCF()
    if CFG.atAim then
        local p = aimPos()
        if p then return p end
    end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        return hrp.CFrame * CFrame.new(0, 1, -10)
    end
    return CFrame.new(0, 20, 0)
end

local function placeAt(obj, cf)
    pcall(function()
        if obj:IsA("Model") then
            if not obj.PrimaryPart then
                obj.PrimaryPart = obj:FindFirstChildWhichIsA("BasePart", true)
            end
            obj:PivotTo(cf)
        elseif obj:IsA("BasePart") then
            obj.CFrame = cf
        end
    end)
end

local function anchorAll(obj)
    pcall(function()
        if obj:IsA("BasePart") then obj.Anchored = true end
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = true end
        end
    end)
end

local function seatIn(obj)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local seat
    if obj:IsA("VehicleSeat") then
        seat = obj
    else
        seat = obj:FindFirstChildWhichIsA("VehicleSeat", true)
    end
    if seat then
        pcall(function() seat:Sit(hum) end)
    end
end

local function spawnLocal(entry, quiet)
    local tpl = entry.inst
    if not tpl or not tpl.Parent then return false, "template disparu" end
    local obj
    local ok = pcall(function() obj = tpl:Clone() end)
    if not ok or not obj then return false, "clone impossible" end

    local cf = baseCF()
    placeAt(obj, cf)
    if CFG.anchor then anchorAll(obj) end

    if obj:IsA("Tool") then
        local bp = LP:FindFirstChildOfClass("Backpack")
        if bp then obj.Parent = bp else obj:Destroy() return false, "pas de backpack" end
    else
        obj.Parent = workspace
    end

    table.insert(Spawned, obj)
    if CFG.seat then seatIn(obj) end
    if not quiet then
        logLine("spawn local: " .. entry.name .. " [" .. entry.class .. "]")
    end
    return true, obj
end

local function clearSpawned()
    local n = #Spawned
    for i = n, 1, -1 do
        pcall(function() Spawned[i]:Destroy() end)
    end
    Spawned = {}
    logLine("nettoye: " .. n .. " objet(s)")
    return n
end

--===============================================================
-- spawn serveur
--===============================================================
local SPAWN_HINTS = {
    "spawn", "summon", "create", "place", "vehicle", "car", "buy",
    "purchase", "garage", "deploy", "request", "give", "unlock",
    "equip", "tame", "build", "craft", "morph",
}

local function hintRank(remote)
    local n = remote:GetFullName():lower()
    for i = 1, #SPAWN_HINTS do
        if n:find(SPAWN_HINTS[i], 1, true) then return i end
    end
    return nil
end

local function collectHinted()
    local hinted, seen = {}, {}
    local ok, desc = pcall(function() return RS:GetDescendants() end)
    if not ok then return hinted end
    for _, o in ipairs(desc) do
        if (o:IsA("RemoteEvent") or o:IsA("RemoteFunction")) and not seen[o] then
            seen[o] = true
            local s = hintRank(o)
            if s then table.insert(hinted, { r = o, s = s }) end
        end
    end
    table.sort(hinted, function(a, b) return a.s < b.s end)
    local out = {}
    for i = 1, math.min(#hinted, 10) do out[i] = hinted[i].r end
    return out
end

local function spawnServer(entry)
    local tpl = entry.inst
    if not tpl or not tpl.Parent then
        logLine("serveur: template disparu")
        return false
    end
    local remotes = collectHinted()
    if #remotes == 0 then
        logLine("serveur: aucun remote de spawn")
        return false
    end
    local tpl = entry.inst
    local variants = { { entry.name }, { tpl }, { tpl:GetFullName() } }
    local fired = 0
    for i = 1, #remotes do
        if not govOk() then break end
        local r = remotes[i]
        if r.Parent then
            for _, a in ipairs(variants) do
                if not govOk() then break end
                if r:IsA("RemoteFunction") then
                    task.spawn(function()
                        pcall(function() r:InvokeServer(table.unpack(a)) end)
                    end)
                else
                    pcall(function() r:FireServer(table.unpack(a)) end)
                end
                table.insert(Gov.stamps, os.clock())
                govWait()
                fired = fired + 1
            end
        end
    end
    logLine("serveur: " .. fired .. " tir(s) sur " .. #remotes .. " remotes")
    return fired > 0
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
    local old = getgenv()._sx
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._sx = gui
end

local W, H = 302, 408
local win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 8, 0, 80),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.amber, Thickness = 1, Transparency = 0.55 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "SPAWN", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.amber, Size = UDim2.fromOffset(150, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})

-- tabs
local TABS = { "SPAWN", "CATALOGUE", "OUTILS", "LOG" }
local tabBtns, pages = {}, {}
local tabW = (W - 20 - 18) / 4

local rebuildMain, rebuildCat

local function setTab(i)
    for k = 1, #pages do
        pages[k].Visible = (k == i)
        tabBtns[k].BackgroundColor3 = (k == i) and C.amber or C.row
        tabBtns[k].TextColor3 = (k == i) and C.bg or C.dim
    end
    if i == 1 then rebuildMain() end
    if i == 2 then rebuildCat() end
end

for i = 1, 4 do
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

-- log
local LOG = {}
local logBox

logLine = function(txt)
    table.insert(LOG, tostring(txt))
    while #LOG > 90 do table.remove(LOG, 1) end
    if logBox then logBox.Text = table.concat(LOG, "\n") end
end

--===============================================================
-- page SPAWN
--===============================================================
local searchBox = mk("TextBox", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -66, 0, 26),
    BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false,
    Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.txt,
    PlaceholderText = "filtrer...", PlaceholderColor3 = C.dim,
    TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, pages[1])
corner(7, searchBox)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, searchBox)

local rescanBtn = btn(pages[1], {
    Text = "SCAN", Size = UDim2.fromOffset(60, 26),
    Position = UDim2.new(1, -60, 0, 0), TextColor3 = C.green, TextSize = 9,
})
rescanBtn.MouseButton1Click:Connect(function()
    logLine("scan...")
    CATALOG = scanWorld()
    logLine("scan: " .. #CATALOG .. " objets, " .. countVehicles() .. " vehicules")
    rebuildMain()
    rebuildCat()
end)
searchBox.FocusLost:Connect(function()
    CFG.search = searchBox.Text
    rebuildMain()
end)

local mainList = makeList(pages[1])
mainList.Position = UDim2.fromOffset(0, 32)
mainList.Size = UDim2.new(1, 0, 1, -32)

local filterRow
local function buildFilterChips()
    if filterRow then filterRow:Destroy() end
    filterRow = mk("Frame", {
        Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
    }, pages[1])
    local opts = { "TOUT", "VEHICULE", "OUTIL", "MODEL" }
    for i = 1, #opts do
        local b = btn(filterRow, {
            Text = opts[i], Size = UDim2.fromOffset(66, 20),
            Position = UDim2.fromOffset((i - 1) * 70, 0), TextSize = 8,
        })
        local key = opts[i]
        b.MouseButton1Click:Connect(function()
            CFG.filter = (CFG.filter == key) and nil or key
            rebuildMain()
        end)
    end
end

local function passesFilter(e)
    if CFG.search and CFG.search ~= "" then
        if not e.name:lower():find(CFG.search:lower(), 1, true) then return false end
    end
    local f = CFG.filter
    if not f or f == "TOUT" then return true end
    if f == "VEHICULE" then return e.veh end
    if f == "OUTIL" then return e.class:find("Tool") ~= nil end
    if f == "MODEL" then return e.class == "Model" end
    return true
end

local function rowFor(parent, e, order)
    local f = mk("Frame", {
        Size = UDim2.new(1, -2, 0, 34), BackgroundColor3 = C.row,
        BorderSizePixel = 0, LayoutOrder = order,
    }, parent)
    corner(7, f)
    if e.veh then stroke(C.amber, f, 1) end

    local b = mk("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false,
    }, f)

    lbl(f, {
        Text = e.name, Font = Enum.Font.GothamBold, TextSize = 9,
        TextColor3 = e.veh and C.amber or C.txt,
        Size = UDim2.new(1, -80, 0, 14), Position = UDim2.fromOffset(8, 4),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    lbl(f, {
        Text = (e.veh and "VEH  " or "") .. e.class,
        Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
        Size = UDim2.new(1, -80, 0, 12), Position = UDim2.fromOffset(8, 18),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    lbl(f, {
        Text = "+", Font = Enum.Font.GothamBold, TextSize = 16,
        TextColor3 = C.green, Size = UDim2.fromOffset(30, 34),
        Position = UDim2.new(1, -38, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    b.MouseButton1Click:Connect(function()
        if CFG.mode == "LOCAL" then
            local ok, res = spawnLocal(e)
            if not ok then logLine("echec: " .. tostring(res)) end
        else
            pcall(spawnServer, e)
        end
    end)
    return f
end

rebuildMain = function()
    clearList(mainList)
    local shown = 0
    for i = 1, #CATALOG do
        local e = CATALOG[i]
        if passesFilter(e) then
            shown = shown + 1
            rowFor(mainList, e, shown)
            if shown >= 120 then break end
        end
    end
    if shown == 0 then
        lbl(mainList, {
            Text = "rien trouve. tape SCAN.", Font = Enum.Font.Code, TextSize = 9,
            TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0,
        })
    end
end

buildFilterChips()
mainList.Position = UDim2.fromOffset(0, 56)
mainList.Size = UDim2.new(1, 0, 1, -56)

--===============================================================
-- page CATALOGUE
--===============================================================
local catInfo = lbl(pages[2], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 0), TextWrapped = true,
})
local catList = makeList(pages[2])
catList.Position = UDim2.fromOffset(0, 36)
catList.Size = UDim2.new(1, 0, 1, -36)

rebuildCat = function()
    clearList(catList)
    local veh = 0
    for i = 1, #CATALOG do
        if CATALOG[i].veh then veh = veh + 1 end
    end
    catInfo.Text = #CATALOG .. " objets scannes  |  " .. veh ..
        " vehicules  |  " .. #Spawned .. " spawnes"
    if statLbl then
        statLbl.Text = "objets spawnes: " .. #Spawned ..
            "\nvehicules detectes: " .. veh ..
            "\ncatalogue: " .. #CATALOG
    end

    local n = 0
    for i = 1, #CATALOG do
        local e = CATALOG[i]
        if e.veh then
            n = n + 1
            rowFor(catList, e, n)
            if n >= 60 then break end
        end
    end
    if n == 0 then
        lbl(catList, {
            Text = "aucun vehicule detecte.\nlance SCAN dans l'onglet SPAWN.",
            Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
            Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 0, TextWrapped = true,
        })
    end
end

--===============================================================
-- page OUTILS
--===============================================================
local modeBtn = btn(pages[3], {
    Text = "MODE: LOCAL", Size = UDim2.new(1, 0, 0, 34),
    Position = UDim2.fromOffset(0, 0), TextColor3 = C.green, TextSize = 11,
})
stroke(C.green, modeBtn, 1)
modeBtn.MouseButton1Click:Connect(function()
    CFG.mode = (CFG.mode == "LOCAL") and "SERVEUR" or "LOCAL"
    modeBtn.Text = "MODE: " .. CFG.mode
    modeBtn.TextColor3 = (CFG.mode == "LOCAL") and C.green or C.amber
    logLine("mode: " .. CFG.mode)
end)

local function toggleBtn(parent, label, key, y, onCol)
    local b = btn(parent, {
        Text = label, Size = UDim2.new(0.5, -3, 0, 28),
        Position = UDim2.fromOffset(0, y), TextSize = 9,
    })
    if onCol == nil then onCol = C.blue end
    local function paint()
        local on = CFG[key]
        b.BackgroundColor3 = on and onCol or C.row
        b.TextColor3 = on and C.bg or C.dim
        b.Text = label .. ": " .. (on and "ON" or "OFF")
    end
    b.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        paint()
    end)
    paint()
    return b
end

local anchorBtn = toggleBtn(pages[3], "ANCRER", "anchor", 42, C.blue)
anchorBtn.Position = UDim2.fromOffset(0, 42)
local seatBtn = toggleBtn(pages[3], "ASSEOIR", "seat", 42, C.blue)
seatBtn.Position = UDim2.new(0.5, 3, 0, 42)
local aimBtn = toggleBtn(pages[3], "VISEUR", "atAim", 74, C.blue)
aimBtn.Position = UDim2.fromOffset(0, 74)
local jitBtn = toggleBtn(pages[3], "JITTER", "jitter", 74, C.blue)
jitBtn.Position = UDim2.new(0.5, 3, 0, 74)

local allBtn = btn(pages[3], {
    Text = "SPAWN TOUT (30)", Size = UDim2.new(1, 0, 0, 40),
    Position = UDim2.fromOffset(0, 116), TextColor3 = C.amber, TextSize = 11,
})
stroke(C.amber, allBtn, 1)
allBtn.MouseButton1Click:Connect(function()
    local n = 0
    for i = 1, #CATALOG do
        if CATALOG[i].veh and n < 30 then
            local ok = spawnLocal(CATALOG[i], true)
            if ok then n = n + 1 end
        end
    end
    if n == 0 then
        for i = 1, #CATALOG do
            if n >= 15 then break end
            if spawnLocal(CATALOG[i], true) then n = n + 1 end
        end
    end
    logLine("spawn tout: " .. n .. " objet(s) local")
    rebuildCat()
end)

local clearBtn2 = btn(pages[3], {
    Text = "NETTOYER", Size = UDim2.new(1, 0, 0, 34),
    Position = UDim2.fromOffset(0, 164), TextColor3 = C.red, TextSize = 10,
})
clearBtn2.MouseButton1Click:Connect(function()
    clearSpawned()
    rebuildCat()
end)

statLbl = lbl(pages[3], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 206), TextWrapped = true,
})

--===============================================================
-- page LOG
--===============================================================
local logScroll = mk("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.amber, AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pages[4])
logBox = lbl(logScroll, {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -8, 0, 0), Position = UDim2.fromOffset(2, 0),
    TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
    TextYAlignment = Enum.TextYAlignment.Top,
})

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
CATALOG = scanWorld()
logLine("boot: " .. #CATALOG .. " objets, " .. countVehicles() .. " vehicules")
setTab(1)
rebuildCat()

LP.CharacterAdded:Connect(function()
    task.wait(1)
    clearSpawned()
end)
