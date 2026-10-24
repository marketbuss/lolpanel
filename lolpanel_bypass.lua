--===============================================================
-- lolpanel BYPASS
-- carte des protections Roblox + contournement par etapes
-- Delta / Android. 4 onglets: SONDE / MIMIC / BYPASS / LOG
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    blue = Color3.fromRGB(120, 180, 255),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
}

--===============================================================
-- config vivante
--===============================================================
local CFG = {
    jitter = true, jitterMin = 0.035, jitterMax = 0.110,
    longEvery = 7, longExtra = 0.45,
    budgetMax = 60, budgetWindow = 60,
    captureWindow = 15, captureLimit = 40, captureAll = false,
    subAll = false,
    pathMimic = true, pathPrompt = true, pathHinted = true,
}

local QUIET = true

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
        TextYAlignment = Enum.TextYAlignment.Top }
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

local function scroll(parent, pos, size)
    local s = mk("ScrollingFrame", {
        Position = pos, Size = size, BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.amber, CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarImageTransparency = 0.45,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, parent)
    return s
end

--===============================================================
-- capacites de l'executor
--===============================================================
local CAP = {}
do
    local names = {
        "hookfunction", "hookmetamethod", "getrawmetatable", "setreadonly",
        "getnamecallmethod", "newcclosure", "checkcaller", "getgenv",
        "getrenv", "isreadonly", "loadstring", "request",
    }
    local env = {}
    pcall(function() env = getgenv() end)
    for _, n in ipairs(names) do
        local f = env[n]
        if type(f) ~= "function" then
            pcall(function() f = getfenv()[n] end)
        end
        if type(f) == "function" then CAP[n] = f end
    end
end

local PLATFORM = "inconnu"
if UIS.TouchEnabled and not UIS.MouseEnabled then PLATFORM = "mobile"
elseif UIS.MouseEnabled and not UIS.TouchEnabled then PLATFORM = "desktop"
else PLATFORM = "hybride" end

--===============================================================
-- sonde des protections
--===============================================================
local PROBE = {}

local AC_NAMES = {
    "anticheat", "anti_cheat", "anti-cheat", "ac_", "_ac", "antiexploit",
    "anti_exploit", "guard", "guardian", "integrity", "detect", "detector",
    "shield", "sentinel", "watchdog", "secure", "security", "protect",
    "honeypot", "trap", "sanity", "verify", "validation", "audit",
}

local function scanClientScripts()
    local hits, seen, total = {}, {}, 0
    local roots = { RS, workspace }
    local sg = LP:FindFirstChildOfClass("PlayerScripts")
    if sg then table.insert(roots, sg) end
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then table.insert(roots, pg) end

    for _, root in ipairs(roots) do
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                total = total + 1
                if total > 24000 then break end
                if (d:IsA("LocalScript") or d:IsA("ModuleScript")) and not seen[d] then
                    seen[d] = true
                    local n = d.Name:lower()
                    for _, k in ipairs(AC_NAMES) do
                        if n:find(k, 1, true) then
                            if #hits < 24 then table.insert(hits, d) end
                            break
                        end
                    end
                end
            end
        end
        if total > 24000 then break end
    end
    return hits, total
end

local function scanRemotes()
    local total, hinted = 0, 0
    local HINTS = {
        "delete", "remove", "destroy", "break", "mine", "harvest", "collect",
        "pickup", "sell", "clean", "clear", "chop", "dig", "grab", "interact",
        "place", "build", "despawn", "consume", "eat",
    }
    local ok, desc = pcall(function() return RS:GetDescendants() end)
    if not ok then return 0, 0 end
    for _, o in ipairs(desc) do
        if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") then
            total = total + 1
            local n = o:GetFullName():lower()
            for _, k in ipairs(HINTS) do
                if n:find(k, 1, true) then hinted = hinted + 1 break end
            end
            if total >= 2000 then break end
        end
    end
    return total, hinted
end

local function probeNamecall()
    if not CAP.getrawmetatable then return "n/a", "pas de getrawmetatable" end
    local ok, res = pcall(function()
        local mt = getrawmetatable(game)
        local nc = rawget(mt, "__namecall")
        if type(nc) ~= "function" then return "absent" end
        local ok2, src = pcall(debug.info, nc, "s")
        if ok2 and type(src) == "string" and src ~= "=[C]" then return "hooke" end
        return "propre"
    end)
    if not ok then return "n/a", "meta verrouillee" end
    if res == "hooke" then return "amber", "deja hooke par un autre script" end
    if res == "absent" then return "amber", "namecall introuvable" end
    return "green", "libre, non hooke"
end

local function probePrompts()
    local n = 0
    local ok, desc = pcall(function() return workspace:GetDescendants() end)
    if not ok then return 0 end
    for _, d in ipairs(desc) do
        if d:IsA("ProximityPrompt") then
            n = n + 1
            if n >= 500 then break end
        end
    end
    return n
end

local function runProbe()
    PROBE = {}
    local function row(name, verdict, col, detail)
        table.insert(PROBE, { name = name, verdict = verdict, col = col, detail = detail })
    end

    -- 1. anti-tamper natif
    if PLATFORM == "desktop" then
        row("Hyperion / Byfron", "BLOQUE", C.red, "anti-tamper natif actif — hors de portee Lua")
    else
        row("Hyperion / Byfron", "LIBRE", C.green, "deploye Windows seulement — absent sur " .. PLATFORM)
    end

    -- 2. scripts anti-triche du jeu
    local acScripts, scanned = scanClientScripts()
    if #acScripts == 0 then
        row("Anti-triche client", "LIBRE", C.green, "aucun script suspect sur " .. scanned .. " instances")
    elseif #acScripts <= 2 then
        row("Anti-triche client", "FAIBLE", C.amber, #acScripts .. " script(s) suspect(s)")
    else
        row("Anti-triche client", "ACTIF", C.red, #acScripts .. " scripts suspects — il te surveille")
    end

    -- 3. etat du hook __namecall
    local ncCol, ncDetail = probeNamecall()
    row("Hook __namecall", ncCol == "green" and "LIBRE" or "ATTENTION",
        ncCol == "green" and C.green or C.amber, ncDetail)

    -- 4. integrite de signature Android
    if PLATFORM == "mobile" then
        row("Play Integrity", "PARTIEL", C.amber, "geree par Delta — pas par Lua")
    else
        row("Play Integrity", "LIBRE", C.green, "non applicable sur " .. PLATFORM)
    end

    -- 5. validation serveur des remotes
    local total, hinted = scanRemotes()
    row("Validation remotes", "INCONNU", C.dim,
        total .. " remotes, " .. hinted .. " a cible — non sondable sans risque")

    -- 6. rate limit serveur
    row("Rate limit serveur", "MITIGE", C.amber,
        "gouvernor " .. CFG.budgetMax .. " appels / " .. CFG.budgetWindow .. "s + jitter")

    -- 7. anti-teleport
    row("Anti-teleport", "EVITE", C.green, "aucun teleport dans ce build")

    -- 8. prompts du jeu (voie propre)
    local np = probePrompts()
    if np > 0 then
        row("ProximityPrompts", "VOIE", C.green, np .. " prompts — voie sans remote")
    else
        row("ProximityPrompts", "AUCUN", C.dim, "pas d'interaction directe possible")
    end

    -- 9. surface de detection de NOTRE gui
    row("Notre surface", "FAIBLE", C.green, "0 asset charge, gui nommee 'Counter', pas d'image")

    -- 10. compte
    row("Compte / telemetrie", "RESIDUEL", C.amber,
        "Delta reste detectable cote client — rien a faire en Lua")

    return PROBE
end

--===============================================================
-- gouvernor: budget + jitter
--===============================================================
local Gov = { stamps = {}, n = 0 }

local function govPurge()
    local now = os.clock()
    while #Gov.stamps > 0 and (now - Gov.stamps[1]) > CFG.budgetWindow do
        table.remove(Gov.stamps, 1)
    end
end

local function govOk()
    govPurge()
    return #Gov.stamps < CFG.budgetMax
end

local function govWait()
    if not CFG.jitter then return end
    local d = CFG.jitterMin + math.random() * (CFG.jitterMax - CFG.jitterMin)
    Gov.n = Gov.n + 1
    if Gov.n % CFG.longEvery == 0 then
        d = d + CFG.longExtra * (0.6 + math.random() * 0.8)
    end
    task.wait(d)
end

--===============================================================
-- MIMIC: capture un appel legit, rejoue avec la cible
--===============================================================
local Cap = { rec = {}, armed = false, mt = nil, orig = nil, left = 0 }

local captureDisarm

local function snapArg(a)
    local t = typeof(a)
    if t == "Instance" then return { k = "inst", v = a } end
    if t == "table" then
        local sub = {}
        for i, v in ipairs(a) do
            sub[i] = snapArg(v)
        end
        return { k = "tbl", v = sub }
    end
    if type(a) == "number" then return { k = "num", v = a } end
    if type(a) == "string" then return { k = "str", v = a } end
    if type(a) == "boolean" then return { k = "bool", v = a } end
    if t == "Vector3" or t == "CFrame" or t == "Vector2" then return { k = "vec", v = a } end
    return { k = "skip" }
end

local function hasInstance(snap)
    for i = 1, #snap do
        local e = snap[i]
        if e.k == "inst" then return true end
        if e.k == "tbl" then
            for j = 1, #e.v do
                if e.v[j].k == "inst" then return true end
            end
        end
    end
    return false
end

local function rebuild(snap, target, slot)
    local out = {}
    for i = 1, #snap do
        local e = snap[i]
        if e.k == "inst" then
            if slot == i then out[i] = target else out[i] = e.v end
        elseif e.k == "tbl" then
            local sub = {}
            local done = false
            for j = 1, #e.v do
                local f = e.v[j]
                if f.k == "inst" then
                    if (slot == nil and not done) or CFG.subAll then
                        sub[j] = target
                        done = true
                    else
                        sub[j] = f.v
                    end
                else
                    sub[j] = f.v
                end
            end
            out[i] = sub
        else
            out[i] = e.v
        end
    end
    return out
end

local function captureArm()
    if Cap.armed then captureDisarm() end
    if not CAP.getrawmetatable or not CAP.newcclosure then
        return false, "executor sans getrawmetatable"
    end
    Cap.rec = {}
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        local old = rawget(mt, "__namecall")
        if type(old) ~= "function" then error("namecall absent") end
        if CAP.isreadonly and isreadonly(mt) then setreadonly(mt, false) end
        Cap.mt = mt
        Cap.orig = old
        local hook = newcclosure(function(self, ...)
            if Cap.armed and typeof(self) == "Instance" then
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    local mine = false
                    if CAP.checkcaller then
                        local okc, v = pcall(checkcaller)
                        mine = okc and v
                    end
                    if (not mine) or CFG.captureAll then
                        local args = table.pack(...)
                        local snap = {}
                        for i = 1, args.n do snap[i] = snapArg(args[i]) end
                        if hasInstance(snap) and #Cap.rec < CFG.captureLimit then
                            table.insert(Cap.rec, {
                                r = self, m = method, args = snap, t = os.clock(),
                            })
                        end
                    end
                end
            end
            return old(self, ...)
        end)
        rawset(mt, "__namecall", hook)
        if CAP.setreadonly then setreadonly(mt, true) end
    end)
    if not ok then return false, tostring(err) end
    Cap.armed = true
    Cap.left = CFG.captureWindow
    return true
end

captureDisarm = function()
    if not Cap.armed then return end
    Cap.armed = false
    pcall(function()
        if CAP.isreadonly and isreadonly(Cap.mt) then setreadonly(Cap.mt, false) end
        rawset(Cap.mt, "__namecall", Cap.orig)
        if CAP.setreadonly then setreadonly(Cap.mt, true) end
    end)
    Cap.mt, Cap.orig = nil, nil
end

local function chooseSlot(snap)
    local top, tbl, part = nil, nil, nil
    local char = LP.Character
    for i = 1, #snap do
        local e = snap[i]
        if e.k == "inst" then
            local v, skip = e.v, false
            pcall(function()
                if char and v:IsDescendantOf(char) then skip = true end
                if v:IsA("Tool") or v:IsA("Player") then skip = true end
            end)
            if not skip then
                if v:IsA("BasePart") and not part then part = i end
                if not top then top = i end
            end
        elseif e.k == "tbl" and not tbl then
            for j = 1, #e.v do
                if e.v[j].k == "inst" then tbl = i break end
            end
        end
    end
    return part or top or tbl
end

local function captureCount()
    return #Cap.rec
end

--===============================================================
-- ciblage
--===============================================================
local filterType
pcall(function() filterType = Enum.RaycastFilterType.Exclude end)
if not filterType then filterType = Enum.RaycastFilterType.Blacklist end

local function crosshairPart()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local params = RaycastParams.new()
    params.FilterType = filterType
    params.FilterDescendantsInstances = { LP.Character }
    params.IgnoreWater = true
    local pos = cam.CFrame.Position
    local dir = cam.CFrame.LookVector
    local remaining = 1200
    for _ = 1, 12 do
        local res = workspace:Raycast(pos, dir * remaining, params)
        if not res then return nil end
        local inst = res.Instance
        local okT, tr = pcall(function() return inst.Transparency end)
        if okT and type(tr) == "number" and tr >= 0.92 then
            local step = (res.Position - pos).Magnitude + 1
            remaining = remaining - step
            if remaining <= 1 then return nil end
            pos = pos + dir * step
        else
            return inst
        end
    end
    return nil
end

local function snapshot(part)
    local b = { tr = 0, size = 0 }
    local okT, tr = pcall(function() return part.Transparency end)
    if okT and type(tr) == "number" then b.tr = tr end
    local okS, sz = pcall(function() return part.Size.Magnitude end)
    if okS and type(sz) == "number" then b.size = sz end
    return b
end

local function watch(part, base)
    local t0 = os.clock()
    while os.clock() - t0 < 2.2 do
        if not part or not part.Parent then return "detruit" end
        local okT, tr = pcall(function() return part.Transparency end)
        if okT and type(tr) == "number" and tr >= 0.99 and base.tr < 0.9 then
            return "masque"
        end
        local okS, sz = pcall(function() return part.Size.Magnitude end)
        if okS and type(sz) == "number" and base.size > 0.5 and sz < base.size * 0.05 then
            return "reduit"
        end
        task.wait(0.08)
    end
    return nil
end

--===============================================================
-- voies de contournement
--===============================================================
local HINTS = {
    "delete", "remove", "destroy", "break", "mine", "harvest", "collect",
    "pickup", "sell", "clean", "clear", "chop", "dig", "grab", "interact",
    "place", "build", "despawn", "consume", "eat",
}

local function hintRank(remote)
    local n = remote:GetFullName():lower()
    for i = 1, #HINTS do
        if n:find(HINTS[i], 1, true) then return i end
    end
    return nil
end

local function collectHinted()
    local hinted, others, seen = {}, {}, {}
    local ok, desc = pcall(function() return RS:GetDescendants() end)
    if not ok then return hinted, others end
    for _, o in ipairs(desc) do
        if (o:IsA("RemoteEvent") or o:IsA("RemoteFunction")) and not seen[o] then
            seen[o] = true
            local s = hintRank(o)
            if s then
                hinted[#hinted + 1] = { r = o, s = s }
            else
                others[#others + 1] = o
            end
        end
    end
    table.sort(hinted, function(a, b) return a.s < b.s end)
    local out = {}
    for i = 1, #hinted do out[i] = hinted[i].r end
    return out, others
end

local function pathPrompt(part, logf)
    local n = 0
    local node = part
    local depth = 0
    while node and node ~= workspace and node ~= game and depth < 4 do
        local ok, desc = pcall(function() return node:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                if d:IsA("ProximityPrompt") and d.Enabled then
                    pcall(function() d:InputHoldBegin() end)
                    task.wait(0.03)
                    pcall(function() d:InputHoldEnd() end)
                    n = n + 1
                    if n >= 6 then break end
                end
            end
        end
        node = node.Parent
        depth = depth + 1
    end
    logf("prompt: " .. n .. " declenche(s)")
    return n > 0
end

local function pathMimic(part, logf)
    if #Cap.rec == 0 then
        logf("mimic: aucune capture")
        return false
    end
    local order = {}
    for i = 1, #Cap.rec do order[i] = Cap.rec[i] end
    table.sort(order, function(a, b)
        local sa = chooseSlot(a.args)
        local sb = chooseSlot(b.args)
        if (sa ~= nil) ~= (sb ~= nil) then return sa ~= nil end
        if a.m ~= b.m then return a.m == "FireServer" end
        return a.t > b.t
    end)

    local fired = 0
    for i = 1, #order do
        if not part.Parent then break end
        if not govOk() then
            logf("mimic: budget atteint")
            break
        end
        local rec = order[i]
        local slot = chooseSlot(rec.args)
        local args = rebuild(rec.args, part, slot)
        if rec.m == "FireServer" then
            pcall(function() rec.r:FireServer(table.unpack(args)) end)
        else
            task.spawn(function()
                pcall(function() rec.r:InvokeServer(table.unpack(args)) end)
            end)
        end
        fired = fired + 1
        table.insert(Gov.stamps, os.clock())
        govWait()
        if fired >= 6 then break end
    end
    logf("mimic: " .. fired .. " rejeu(x)")
    return fired > 0
end

local function pathHinted(part, logf)
    local hinted, others = collectHinted()
    local fired = 0
    for i = 1, #hinted do
        if not part.Parent then break end
        if not govOk() then
            logf("hinted: budget atteint")
            break
        end
        local r = hinted[i]
        if r.Parent then
            local kindArgs = { { part }, { part, true }, { part.Name } }
            for _, a in ipairs(kindArgs) do
                if not part.Parent then break end
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
        if fired >= 18 then break end
    end
    logf("hinted: " .. #hinted .. " remotes, " .. fired .. " tir(s)")
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
    local old = getgenv()._lx
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._lx = gui
end

local W, H = 288, 348
local win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 10, 0, 90),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.amber, Thickness = 1, Transparency = 0.55 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "BYPASS", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.amber, Size = UDim2.fromOffset(120, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})

-- onglets
local TABS = { "SONDE", "MIMIC", "BYPASS", "LOG" }
local tabBtns, pages = {}, {}
local tabW = (W - 20 - 18) / 4

local function setTab(i)
    for k = 1, #pages do
        pages[k].Visible = (k == i)
        tabBtns[k].BackgroundColor3 = (k == i) and C.amber or C.row
        tabBtns[k].TextColor3 = (k == i) and C.bg or C.dim
    end
    if i == 1 then refreshProbe() end
    if i == 2 then refreshMimic() end
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

--===============================================================
-- log
--===============================================================
local LOG = {}
local logBox

local function logLine(txt)
    local stamp = string.format("%02d:%02d", math.floor(os.clock() / 60) % 60, math.floor(os.clock()) % 60)
    table.insert(LOG, stamp .. " " .. tostring(txt))
    while #LOG > 80 do table.remove(LOG, 1) end
    if logBox then logBox.Text = table.concat(LOG, "\n") end
end

--===============================================================
-- page SONDE
--===============================================================
local probeScroll = scroll(pages[1], UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, -34))
local probeRows = {}

local function buildProbeRows()
    for _, r in ipairs(probeRows) do r.frame:Destroy() end
    probeRows = {}
    local y = 0
    for i, row in ipairs(PROBE) do
        local f = mk("Frame", {
            Size = UDim2.new(1, -4, 0, 30), Position = UDim2.fromOffset(0, y),
            BackgroundColor3 = C.row, BorderSizePixel = 0,
        }, probeScroll)
        corner(7, f)
        stroke(C.row2, f, 1)
        lbl(f, {
            Text = row.name, Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = C.txt, Size = UDim2.new(1, -76, 0, 12),
            Position = UDim2.fromOffset(8, 4), TextTruncate = Enum.TextTruncate.AtEnd,
        })
        lbl(f, {
            Text = row.verdict, Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = row.col, Size = UDim2.fromOffset(70, 12),
            Position = UDim2.new(1, -76, 0, 4), TextXAlignment = Enum.TextXAlignment.Right,
        })
        lbl(f, {
            Text = row.detail, Font = Enum.Font.Code, TextSize = 8,
            TextColor3 = C.dim, Size = UDim2.new(1, -16, 0, 12),
            Position = UDim2.fromOffset(8, 16), TextTruncate = Enum.TextTruncate.AtEnd,
        })
        table.insert(probeRows, { frame = f })
        y = y + 33
    end
    probeScroll.CanvasSize = UDim2.new(0, 0, 0, y)
    probeScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
end

function refreshProbe()
    runProbe()
    buildProbeRows()
    logLine("sonde: " .. #PROBE .. " couches")
end

local rescanBtn = btn(pages[1], {
    Text = "RE-SONDER", Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.new(0, 0, 1, -28), TextColor3 = C.green, TextSize = 10,
})
rescanBtn.MouseButton1Click:Connect(function()
    refreshProbe()
end)

--===============================================================
-- page MIMIC
--===============================================================
local mimicInfo = lbl(pages[2], {
    Text = "1. tape ARMER\n2. va dans le jeu, fais l'action sur un objet LEGAL\n3. le tool capture le remote + ses arguments\n4. desarme auto apres 15 s",
    Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromOffset(0, 0), TextWrapped = true,
})
local mimicCount = lbl(pages[2], {
    Text = "captures: 0", Font = Enum.Font.GothamBold, TextSize = 10,
    TextColor3 = C.blue, Size = UDim2.new(1, 0, 0, 16),
    Position = UDim2.fromOffset(0, 66),
})
local mimicList = lbl(pages[2], {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 76), Position = UDim2.fromOffset(0, 84), TextWrapped = true,
})
local armBtn = btn(pages[2], {
    Text = "ARMER", Size = UDim2.new(0.48, 0, 0, 34),
    Position = UDim2.new(0, 0, 1, -76), TextColor3 = C.green, TextSize = 11,
})
local clearBtn = btn(pages[2], {
    Text = "VIDER", Size = UDim2.new(0.48, 0, 0, 34),
    Position = UDim2.new(0.52, 0, 1, -76), TextColor3 = C.amber, TextSize = 11,
})
local allBtn = btn(pages[2], {
    Text = "REMPLACE TOUT: OFF", Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 1, -36), TextSize = 9, TextColor3 = C.dim,
})

local function refreshMimic()
    mimicCount.Text = "captures: " .. captureCount()
    local lines = {}
    for i = #Cap.rec, math.max(1, #Cap.rec - 4), -1 do
        local rec = Cap.rec[i]
        local n = 0
        for j = 1, #rec.args do n = n + 1 end
        table.insert(lines, rec.m .. " " .. rec.r.Name .. "  (" .. n .. " arg)")
    end
    mimicList.Text = table.concat(lines, "\n")
    armBtn.Text = Cap.armed and "ARMED" or "ARMER"
    armBtn.TextColor3 = Cap.armed and C.amber or C.green
end

armBtn.MouseButton1Click:Connect(function()
    if Cap.armed then
        captureDisarm()
        logLine("mimic: desarme")
        refreshMimic()
        return
    end
    local ok, err = captureArm()
    if not ok then
        logLine("mimic: " .. tostring(err))
        return
    end
    logLine("mimic: arme " .. CFG.captureWindow .. "s — agis en jeu")
    refreshMimic()
    task.spawn(function()
        local t0 = os.clock()
        while Cap.armed and (os.clock() - t0) < CFG.captureWindow do
            if #Cap.rec > 0 then refreshMimic() end
            task.wait(0.4)
        end
        captureDisarm()
        refreshMimic()
        logLine("mimic: desarme — " .. #Cap.rec .. " capture(s)")
    end)
end)

clearBtn.MouseButton1Click:Connect(function()
    Cap.rec = {}
    refreshMimic()
    logLine("mimic: captures videes")
end)

allBtn.MouseButton1Click:Connect(function()
    CFG.subAll = not CFG.subAll
    allBtn.Text = "REMPLACE TOUT: " .. (CFG.subAll and "ON" or "OFF")
    allBtn.TextColor3 = CFG.subAll and C.green or C.dim
end)

--===============================================================
-- page BYPASS
--===============================================================
local targetLbl = lbl(pages[3], {
    Text = "vise une part visible", Font = Enum.Font.Code, TextSize = 8,
    TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.fromOffset(0, 0), TextTruncate = Enum.TextTruncate.AtEnd,
})
local statusLbl = lbl(pages[3], {
    Text = "pret", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.green,
    Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 16), TextWrapped = true,
})

local pathBtns = {}
local PATH_KEYS = { "MIMIC", "PROMPT", "HINTED" }
local PATH_STATE = {
    MIMIC = "pathMimic", PROMPT = "pathPrompt", HINTED = "pathHinted",
}
for i = 1, #PATH_KEYS do
    local key = PATH_KEYS[i]
    local b = btn(pages[3], {
        Text = key, Size = UDim2.new(0.333, -2, 0, 24),
        Position = UDim2.fromOffset((i - 1) * (0.333 * 262 + 2), 50),
        TextSize = 9,
    })
    pathBtns[key] = b
    local function paint()
        local on = CFG[PATH_STATE[key]]
        b.BackgroundColor3 = on and C.green or C.row
        b.TextColor3 = on and C.bg or C.dim
    end
    b.MouseButton1Click:Connect(function()
        CFG[PATH_STATE[key]] = not CFG[PATH_STATE[key]]
        paint()
    end)
    paint()
end

local jitterBtn = btn(pages[3], {
    Text = "JITTER + BUDGET", Size = UDim2.new(1, 0, 0, 24),
    Position = UDim2.fromOffset(0, 80), TextSize = 9,
})
local function paintJitter()
    jitterBtn.BackgroundColor3 = CFG.jitter and C.blue or C.row
    jitterBtn.TextColor3 = CFG.jitter and C.bg or C.dim
end
jitterBtn.MouseButton1Click:Connect(function()
    CFG.jitter = not CFG.jitter
    paintJitter()
end)
paintJitter()

local runBtn = btn(pages[3], {
    Text = "EXECUTER", Size = UDim2.new(1, 0, 0, 42),
    Position = UDim2.new(0, 0, 1, -42), TextColor3 = C.green, TextSize = 13,
})
stroke(C.green, runBtn, 1)

local function setStatus(txt, col)
    statusLbl.Text = tostring(txt)
    statusLbl.TextColor3 = col or C.txt
end

--===============================================================
-- page LOG
--===============================================================
local logScroll = scroll(pages[4], UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0))
local logBox = lbl(logScroll, {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -8, 0, 0), Position = UDim2.fromOffset(2, 0),
    TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
    TextYAlignment = Enum.TextYAlignment.Top,
})

--===============================================================
-- pipeline principal
--===============================================================
local BUSY = false
local LAST = 0

local function runBypass()
    if BUSY then return end
    if os.clock() - LAST < 0.8 then return end
    local part = crosshairPart()
    if not part then
        setStatus("rien de visible sous le viseur", C.amber)
        logLine("cible: aucune")
        return
    end
    BUSY = true
    LAST = os.clock()
    task.delay(30, function() BUSY = false end)

    local base = snapshot(part)
    local name = part.Name
    targetLbl.Text = name .. " [" .. part.ClassName .. "] tr=" .. string.format("%.2f", base.tr)
    setStatus("cible: " .. name, C.txt)
    logLine("cible: " .. name .. " " .. part.ClassName)
    logLine("captures: " .. captureCount())

    task.spawn(function()
        local order = {}
        if CFG.pathMimic then table.insert(order, "MIMIC") end
        if CFG.pathPrompt then table.insert(order, "PROMPT") end
        if CFG.pathHinted then table.insert(order, "HINTED") end

        local result = nil
        local used = nil

        for i = 1, #order do
            if not part.Parent then break end
            local p = order[i]
            setStatus("voie " .. p .. "...", C.blue)
            logLine("voie: " .. p)

            if p == "MIMIC" then
                if #Cap.rec > 0 then pathMimic(part, logLine) end
            elseif p == "PROMPT" then
                pathPrompt(part, logLine)
            elseif p == "HINTED" then
                pathHinted(part, logLine)
            end

            if not part.Parent then
                result, used = "detruit", p
                break
            end
            local r = watch(part, base)
            if r then
                result, used = r, p
                break
            end
        end

        if not part.Parent and not result then
            result, used = "detruit", used or "prompt"
        end

        if result == "detruit" then
            setStatus(name .. " — DETRUIT (voie " .. tostring(used) .. ")", C.green)
            logLine("SUCCES: retiree du monde")
        elseif result == "masque" then
            setStatus(name .. " — masquee via " .. tostring(used), C.green)
            logLine("succes: opacite changee")
        elseif result == "reduit" then
            setStatus(name .. " — reduite a zero via " .. tostring(used), C.green)
            logLine("succes: taille ecrasee")
        else
            setStatus(name .. " — intacte. serveur valide.", C.amber)
            logLine("echec: aucune voie n'a passe")
        end
        BUSY = false
    end)
end

runBtn.MouseButton1Click:Connect(runBypass)

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
setTab(1)
refreshMimic()
logLine("boot " .. PLATFORM .. " | hook __namecall desarme")

LP.CharacterAdded:Connect(function()
    task.wait(1)
    refreshMimic()
end)

pcall(function()
    if not QUIET then print("[lolpanel BYPASS] pret") end
end)
