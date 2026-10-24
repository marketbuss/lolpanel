--===============================================================
-- lolpanel WORM
-- propagation par les remotes du jeu + spoof d'identite + charge
-- Delta / Android. 4 onglets: VER / IDENTITE / CHARGE / LOG
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

local CFG = {
    radius = 70, maxDepth = 3, maxNodes = 150, speed = 0.15,
    chargeRate = 20, chargeKind = 1,
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
-- remotes
--===============================================================
local ACTION_HINTS = {
    "spawn", "summon", "create", "place", "clone", "give", "add",
    "delete", "remove", "destroy", "break", "mine", "collect", "pickup",
    "interact", "trigger", "use", "activate", "buy", "purchase", "sell",
    "request", "send", "update", "set", "apply", "damage", "hit", "attack",
}

local function hintRank(remote)
    local n = remote:GetFullName():lower()
    for i = 1, #ACTION_HINTS do
        if n:find(ACTION_HINTS[i], 1, true) then return i end
    end
    return nil
end

local REMOTES = {}

local function scanRemotes()
    REMOTES = {}
    local seen = {}
    local ok, desc = pcall(function() return RS:GetDescendants() end)
    if not ok then return 0 end
    for _, o in ipairs(desc) do
        if (o:IsA("RemoteEvent") or o:IsA("RemoteFunction")) and not seen[o] then
            seen[o] = true
            table.insert(REMOTES, { r = o, s = hintRank(o) or 999 })
        end
        if #REMOTES >= 600 then break end
    end
    table.sort(REMOTES, function(a, b) return a.s < b.s end)
    return #REMOTES
end

local function fireRemote(r, args)
    if not r or not r.Parent then return false end
    local ok = false
    if r:IsA("RemoteFunction") then
        task.spawn(function()
            pcall(function() r:InvokeServer(table.unpack(args)) end)
        end)
        ok = true
    else
        ok = pcall(function() r:FireServer(table.unpack(args)) end)
    end
    return ok
end

--===============================================================
-- VER: propagation
--===============================================================
local Worm = {
    on = false, queue = {}, seen = {}, nodes = 0,
    spawned = 0, depth = 0, bestDepth = 0,
}

local function enqueue(inst, depth)
    if not inst or Worm.seen[inst] then return end
    if depth > CFG.maxDepth then return end
    if #Worm.queue >= CFG.maxNodes * 6 then return end
    if not inst:IsA("BasePart") and not inst:IsA("Model")
        and not inst:IsA("Tool") and not inst:IsA("ProximityPrompt") then
        return
    end
    Worm.seen[inst] = true
    table.insert(Worm.queue, { inst = inst, depth = depth })
end

local function seedWorm()
    Worm.queue = {}
    Worm.seen = {}
    Worm.nodes = 0
    Worm.spawned = 0
    Worm.bestDepth = 0

    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local origin = hrp and hrp.Position or Vector3.new(0, 0, 0)

    local n = 0
    for _, ch in ipairs(workspace:GetChildren()) do
        if ch:IsA("Model") or ch:IsA("BasePart") then
            local ok, pos = pcall(function()
                if ch:IsA("Model") then
                    return ch:GetPivot().Position
                end
                return ch.Position
            end)
            if ok and pos and (pos - origin).Magnitude <= CFG.radius then
                enqueue(ch, 1)
                n = n + 1
                if n >= 80 then break end
            end
        end
    end
    logLine("ver: " .. #Worm.queue .. " graines dans " .. CFG.radius .. " studs")
    return #Worm.queue
end

local function triggerPrompts(inst)
    local n = 0
    local ok, desc = pcall(function() return inst:GetDescendants() end)
    if not ok then return 0 end
    for _, d in ipairs(desc) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            pcall(function() d:InputHoldBegin() end)
            task.wait(0.02)
            pcall(function() d:InputHoldEnd() end)
            n = n + 1
            if n >= 3 then break end
        end
    end
    return n
end

local function snapshotChildren(root)
    local set = {}
    local ok, kids = pcall(function() return root:GetChildren() end)
    if ok then
        for _, c in ipairs(kids) do set[c] = true end
    end
    return set
end

local function diffChildren(root, before)
    local fresh = {}
    local ok, kids = pcall(function() return root:GetChildren() end)
    if ok then
        for _, c in ipairs(kids) do
            if not before[c] then table.insert(fresh, c) end
        end
    end
    return fresh
end

local function wormLoop()
    while Worm.on do
        local node = table.remove(Worm.queue, 1)
        if not node then
            logLine("ver: file vide — fin apres " .. Worm.nodes .. " noeuds")
            Worm.on = false
            break
        end

        local inst = node.inst
        if inst and inst.Parent then
            Worm.nodes = Worm.nodes + 1
            if node.depth > Worm.bestDepth then Worm.bestDepth = node.depth end

            local root = inst.Parent or workspace
            local before = snapshotChildren(root)
            local wbefore = snapshotChildren(workspace)

            local fired = 0
            for i = 1, math.min(#REMOTES, 12) do
                if not Worm.on then break end
                local r = REMOTES[i].r
                if r and r.Parent then
                    fireRemote(r, { inst })
                    fired = fired + 1
                end
            end
            if not inst:IsA("ProximityPrompt") then
                triggerPrompts(inst)
            else
                pcall(function() inst:InputHoldBegin() end)
                task.wait(0.02)
                pcall(function() inst:InputHoldEnd() end)
            end

            task.wait(CFG.speed)

            local freshA = diffChildren(root, before)
            local freshB = diffChildren(workspace, wbefore)

            for i = 1, #freshA do enqueue(freshA[i], node.depth + 1) end
            for i = 1, #freshB do enqueue(freshB[i], node.depth + 1) end

            local born = #freshA + #freshB
            Worm.spawned = Worm.spawned + born
            refreshWorm()
        end

        if Worm.nodes >= CFG.maxNodes then
            logLine("ver: plafond " .. CFG.maxNodes .. " noeuds atteint")
            Worm.on = false
            break
        end
        task.wait(0.02)
    end
    Worm.on = false
    refreshWorm()
end

local function wormStart()
    if Worm.on then return end
    if #Worm.queue == 0 then seedWorm() end
    if #Worm.queue == 0 then
        logLine("ver: aucune graine, rapproche-toi d'objets")
        return
    end
    Worm.on = true
    logLine("ver: demarre, profondeur max " .. CFG.maxDepth)
    task.spawn(wormLoop)
    refreshWorm()
end

local function wormStop()
    Worm.on = false
    logLine("ver: arret demande (" .. Worm.nodes .. " noeuds)")
end

--===============================================================
-- CHARGE
--===============================================================
local Charge = { on = false, sent = 0, target = nil, idx = 1, pending = 0 }

local deepCache
local function deepTable(depth)
    if deepCache then return deepCache end
    local root = {}
    local cur = root
    for _ = 1, depth do
        local n = { v = string.rep("x", 96) }
        cur.next = n
        cur = n
    end
    deepCache = root
    return root
end

local bigTable
local function getBigTable()
    if bigTable then return bigTable end
    bigTable = {}
    for i = 1, 4000 do
        bigTable[i] = { i = i, s = string.rep("z", 24) }
    end
    return bigTable
end

local PAYLOADS = {
    { name = "OBJET", make = function(node) return { node } end },
    { name = "TABLE PROFONDE", make = function() return { deepTable(160) } end },
    { name = "STRING 50K", make = function() return { string.rep("A", 50000) } end },
    { name = "NOMBRES FOU", make = function() return { 0 / 0, math.huge, -math.huge } end },
    { name = "TABLE 4K", make = function() return { getBigTable() } end },
}

local function chargeNode()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local params = RaycastParams.new()
        local ft
        pcall(function() ft = Enum.RaycastFilterType.Exclude end)
        if not ft then ft = Enum.RaycastFilterType.Blacklist end
        params.FilterType = ft
        params.FilterDescendantsInstances = { char }
        local res = workspace:Raycast(hrp.Position, Vector3.new(0, -20, 0), params)
        if res and res.Instance then return res.Instance end
        return hrp
    end
    return workspace
end

local function chargePick()
    if #REMOTES == 0 then scanRemotes() end
    if #REMOTES == 0 then return nil end
    Charge.idx = ((Charge.idx - 1) % #REMOTES) + 1
    Charge.target = REMOTES[Charge.idx].r
    return Charge.target
end

local function chargeLoop()
    local node = chargeNode()
    while Charge.on do
        local r = Charge.target
        if not r or not r.Parent then
            r = chargePick()
        end
        if r then
            local isFunc = r:IsA("RemoteFunction")
            if (not isFunc) or Charge.pending < 8 then
                local pl = PAYLOADS[CFG.chargeKind]
                if isFunc then
                    Charge.pending = Charge.pending + 1
                    task.spawn(function()
                        pcall(function()
                            r:InvokeServer(table.unpack(pl.make(node)))
                        end)
                        Charge.pending = Charge.pending - 1
                    end)
                    Charge.sent = Charge.sent + 1
                else
                    local ok = pcall(function()
                        fireRemote(r, pl.make(node))
                    end)
                    if ok then Charge.sent = Charge.sent + 1 end
                end
                refreshCharge()
            end
        end
        task.wait(1 / math.max(1, CFG.chargeRate))
    end
    refreshCharge()
end

local function chargeStart()
    if Charge.on then return end
    if not Charge.target or not Charge.target.Parent then chargePick() end
    if not Charge.target then
        logLine("charge: aucun remote")
        return
    end
    Charge.on = true
    Charge.sent = 0
    logLine("charge: " .. Charge.target.Name .. " @ " .. CFG.chargeRate .. "/s payload " .. PAYLOADS[CFG.chargeKind].name)
    task.spawn(chargeLoop)
    refreshCharge()
end

local function chargeStop()
    Charge.on = false
    logLine("charge: stop a " .. Charge.sent .. " appels")
end

--===============================================================
-- IDENTITE
--===============================================================
local Ident = { tagGui = nil, fakeName = "" }

local function clearTag()
    if Ident.tagGui then pcall(function() Ident.tagGui:Destroy() end) end
    Ident.tagGui = nil
end

local function applyTag(text)
    clearTag()
    local char = LP.Character
    local head = char and char:FindFirstChild("Head")
    if not head then return false, "pas de tete" end
    local bb = Instance.new("BillboardGui")
    bb.Name = "lolpanelTag"
    bb.Size = UDim2.fromOffset(200, 34)
    bb.StudsOffset = Vector3.new(0, 2.6, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 200
    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.fromScale(1, 1)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.TextColor3 = C.amber
    tl.TextStrokeTransparency = 0.4
    tl.Text = text
    tl.Parent = bb
    bb.Parent = head
    Ident.tagGui = bb
    Ident.fakeName = text
    pcall(function()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.DisplayName = text end
    end)
    return true
end

local function copyLook(playerName)
    local target = Players:FindFirstChild(playerName)
    if not target then return false, "joueur absent" end
    local tchar = target.Character
    local thum = tchar and tchar:FindFirstChildOfClass("Humanoid")
    if not thum then return false, "pas de perso" end
    local ok, desc = pcall(function() return thum:GetAppliedDescription() end)
    if not ok or not desc then return false, "description illisible" end
    local mychar = LP.Character
    local myhum = mychar and mychar:FindFirstChildOfClass("Humanoid")
    if not myhum then return false, "pas de perso" end
    local ok2 = pcall(function() myhum:ApplyDescription(desc) end)
    if not ok2 then return false, "description refusee" end
    return true
end

local function spoofChat(speaker, msg)
    local ok = pcall(function()
        local TCS = game:GetService("TextChatService")
        if TCS.ChatVersion == Enum.ChatVersion.TextChatService then
            local chans = TCS:FindFirstChild("TextChannels")
            local rb = chans and chans:FindFirstChild("RBXGeneral")
            if rb then
                rb:DisplaySystemMessage('<font color="#ffb246">[' .. speaker .. ']:</font> ' .. msg)
                return
            end
        end
        game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {
            Text = "[" .. speaker .. "]: " .. msg,
            Color = C.amber,
        })
    end)
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
    local old = getgenv()._wx
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._wx = gui
end

local W, H = 302, 406
local win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 8, 0, 76),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.red, Thickness = 1, Transparency = 0.45 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "WORM", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.red, Size = UDim2.fromOffset(150, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})

local TABS = { "VER", "IDENTITE", "CHARGE", "LOG" }
local tabBtns, pages = {}, {}
local tabW = (W - 20 - 18) / 4

local refreshWorm, refreshCharge, rebuildPlayers

local function setTab(i)
    for k = 1, #pages do
        pages[k].Visible = (k == i)
        tabBtns[k].BackgroundColor3 = (k == i) and C.amber or C.row
        tabBtns[k].TextColor3 = (k == i) and C.bg or C.dim
    end
    if i == 1 then refreshWorm() end
    if i == 2 then rebuildPlayers() end
    if i == 3 then refreshCharge() end
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

local LOG = {}
local logBox

logLine = function(txt)
    table.insert(LOG, tostring(txt))
    while #LOG > 90 do table.remove(LOG, 1) end
    if logBox then logBox.Text = table.concat(LOG, "\n") end
end

--===============================================================
-- page VER
--===============================================================
local wormStat = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 54), Position = UDim2.fromOffset(0, 0), TextWrapped = true,
})

local startBtn = btn(pages[1], {
    Text = "DEMARRER", Size = UDim2.new(0.5, -3, 0, 40),
    Position = UDim2.fromOffset(0, 58), TextColor3 = C.green, TextSize = 11,
})
stroke(C.green, startBtn, 1)
local stopBtn = btn(pages[1], {
    Text = "STOP", Size = UDim2.new(0.5, -3, 0, 40),
    Position = UDim2.new(0.5, 3, 0, 58), TextColor3 = C.red, TextSize = 11,
})
stroke(C.red, stopBtn, 1)
startBtn.MouseButton1Click:Connect(function() wormStart() end)
stopBtn.MouseButton1Click:Connect(function() wormStop() end)

local seedBtn = btn(pages[1], {
    Text = "SCAN GRAINES", Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.fromOffset(0, 106), TextColor3 = C.amber, TextSize = 10,
})
seedBtn.MouseButton1Click:Connect(function()
    scanRemotes()
    seedWorm()
    refreshWorm()
end)

local depthLbl = lbl(pages[1], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.txt,
    Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 144),
})
local function depthRow()
    local y = 168
    local labels = { "-", "+" }
    local b1 = btn(pages[1], {
        Text = "-", Size = UDim2.fromOffset(38, 28),
        Position = UDim2.fromOffset(0, y), TextSize = 14,
    })
    local b2 = btn(pages[1], {
        Text = "+", Size = UDim2.fromOffset(38, 28),
        Position = UDim2.fromOffset(42, y), TextSize = 14,
    })
    b1.MouseButton1Click:Connect(function()
        CFG.maxDepth = math.max(1, CFG.maxDepth - 1)
        refreshWorm()
    end)
    b2.MouseButton1Click:Connect(function()
        CFG.maxDepth = math.min(6, CFG.maxDepth + 1)
        refreshWorm()
    end)
    lbl(pages[1], {
        Text = "PROFONDEUR MAX", Font = Enum.Font.Code, TextSize = 9,
        TextColor3 = C.dim, Size = UDim2.new(1, -90, 0, 28),
        Position = UDim2.fromOffset(88, y),
    })

    local c1 = btn(pages[1], {
        Text = "-", Size = UDim2.fromOffset(38, 28),
        Position = UDim2.fromOffset(0, y + 34), TextSize = 14,
    })
    local c2 = btn(pages[1], {
        Text = "+", Size = UDim2.fromOffset(38, 28),
        Position = UDim2.fromOffset(42, y + 34), TextSize = 14,
    })
    c1.MouseButton1Click:Connect(function()
        CFG.maxNodes = math.max(20, CFG.maxNodes - 25)
        refreshWorm()
    end)
    c2.MouseButton1Click:Connect(function()
        CFG.maxNodes = math.min(400, CFG.maxNodes + 25)
        refreshWorm()
    end)
    lbl(pages[1], {
        Text = "NOEUDS MAX", Font = Enum.Font.Code, TextSize = 9,
        TextColor3 = C.dim, Size = UDim2.new(1, -90, 0, 28),
        Position = UDim2.fromOffset(88, y + 34),
    })
end
depthRow()

refreshWorm = function()
    wormStat.Text = "graines en file: " .. #Worm.queue ..
        "\nnoeuds traites: " .. Worm.nodes ..
        "\ninstances nees: " .. Worm.spawned ..
        "\nprofondeur atteinte: " .. Worm.bestDepth ..
        "\netat: " .. (Worm.on and "EN COURS" or "arrete") ..
        "\nremotes: " .. #REMOTES
    depthLbl.Text = "profondeur " .. CFG.maxDepth .. "  |  noeuds " .. CFG.maxNodes
    startBtn.Text = Worm.on and "EN COURS" or "DEMARRER"
end

--===============================================================
-- page IDENTITE
--===============================================================
local idInfo = lbl(pages[2], {
    Text = "copie du look = replique aux autres.\nle reste est local.",
    Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 0), TextWrapped = true,
})

local playerList = makeList(pages[2])
playerList.Position = UDim2.fromOffset(0, 30)
playerList.Size = UDim2.new(1, 0, 1, -120)

local nameBox = mk("TextBox", {
    Position = UDim2.fromOffset(0, 258), Size = UDim2.new(1, -90, 0, 28),
    BackgroundColor3 = C.row, BorderSizePixel = 0, ClearTextOnFocus = false,
    Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.txt,
    PlaceholderText = "nom affiche...", PlaceholderColor3 = C.dim,
    TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, pages[2])
corner(7, nameBox)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, nameBox)

local tagBtn = btn(pages[2], {
    Text = "TAG", Size = UDim2.fromOffset(80, 28),
    Position = UDim2.new(1, -84, 0, 258), TextColor3 = C.amber, TextSize = 9,
})
tagBtn.MouseButton1Click:Connect(function()
    if nameBox.Text == "" then
        clearTag()
        logLine("tag: retire")
        return
    end
    local ok, err = applyTag(nameBox.Text)
    if ok then logLine("tag: " .. nameBox.Text) else logLine("tag: " .. tostring(err)) end
end)

local chatBtn = btn(pages[2], {
    Text = "SPOOF CHAT", Size = UDim2.new(0.5, -3, 0, 28),
    Position = UDim2.new(0, 0, 1, -28), TextColor3 = C.blue, TextSize = 9,
})
chatBtn.MouseButton1Click:Connect(function()
    local who = nameBox.Text ~= "" and nameBox.Text or "System"
    spoofChat(who, "message local")
    logLine("chat: spoof de " .. who)
end)

local selfBtn = btn(pages[2], {
    Text = "MON LOOK", Size = UDim2.new(0.5, -3, 0, 28),
    Position = UDim2.new(0.5, 3, 1, -28), TextColor3 = C.dim, TextSize = 9,
})
selfBtn.MouseButton1Click:Connect(function()
    pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ApplyDescription(Players:GetHumanoidDescriptionFromUserId(LP.UserId)) end
    end)
    logLine("look: reset")
end)

rebuildPlayers = function()
    clearList(playerList)
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        n = n + 1
        local f = mk("Frame", {
            Size = UDim2.new(1, -2, 0, 36), BackgroundColor3 = C.row,
            BorderSizePixel = 0, LayoutOrder = n,
        }, playerList)
        corner(7, f)
        local isMe = (p == LP)
        if isMe then stroke(C.green, f, 1) end
        lbl(f, {
            Text = p.Name .. (isMe and "  (toi)" or ""),
            Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = isMe and C.green or C.txt,
            Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(8, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local b = btn(f, {
            Text = "COPIER", Size = UDim2.fromOffset(58, 26),
            Position = UDim2.new(1, -64, 0, 5), TextSize = 8,
            BackgroundColor3 = C.row2, TextColor3 = C.amber,
        })
        local target = p.Name
        b.MouseButton1Click:Connect(function()
            local ok, err = copyLook(target)
            if ok then logLine("look: copie de " .. target)
            else logLine("look: " .. tostring(err)) end
        end)
    end
    if n == 0 then
        lbl(playerList, {
            Text = "aucun joueur", Font = Enum.Font.Code, TextSize = 9,
            TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 26),
        })
    end
end

Players.PlayerAdded:Connect(function() rebuildPlayers() end)
Players.PlayerRemoving:Connect(function() rebuildPlayers() end)

--===============================================================
-- page CHARGE
--===============================================================
local chargeStat = lbl(pages[3], {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 0), TextWrapped = true,
})

local pickBtn = btn(pages[3], {
    Text = "CIBLE", Size = UDim2.new(1, 0, 0, 32),
    Position = UDim2.fromOffset(0, 46), TextColor3 = C.blue, TextSize = 10,
})
pickBtn.MouseButton1Click:Connect(function()
    scanRemotes()
    local r = chargePick()
    if r then logLine("charge: cible " .. r:GetFullName()) end
    refreshCharge()
end)

local payloadBtns = {}
for i = 1, #PAYLOADS do
    local b = btn(pages[3], {
        Text = PAYLOADS[i].name, Size = UDim2.new(0.5, -3, 0, 26),
        Position = UDim2.fromOffset(((i - 1) % 2) * 148, 86 + math.floor((i - 1) / 2) * 30),
        TextSize = 8,
    })
    payloadBtns[i] = b
    b.MouseButton1Click:Connect(function()
        CFG.chargeKind = i
        refreshCharge()
    end)
end

local rateOpts = { 5, 20, 50, 120 }
local rateBtns = {}
for i = 1, #rateOpts do
    local b = btn(pages[3], {
        Text = tostring(rateOpts[i]) .. "/s", Size = UDim2.new(0.25, -2, 0, 26),
        Position = UDim2.fromOffset((i - 1) * 73, 186), TextSize = 8,
    })
    rateBtns[i] = b
    b.MouseButton1Click:Connect(function()
        CFG.chargeRate = rateOpts[i]
        refreshCharge()
    end)
end

local cStart = btn(pages[3], {
    Text = "TIRER", Size = UDim2.new(0.5, -3, 0, 40),
    Position = UDim2.fromOffset(0, 220), TextColor3 = C.red, TextSize = 11,
})
stroke(C.red, cStart, 1)
local cStop = btn(pages[3], {
    Text = "STOP", Size = UDim2.new(0.5, -3, 0, 40),
    Position = UDim2.new(0.5, 3, 0, 220), TextColor3 = C.dim, TextSize = 11,
})
cStart.MouseButton1Click:Connect(function() chargeStart() end)
cStop.MouseButton1Click:Connect(function() chargeStop() end)

lbl(pages[3], {
    Text = "le ban est quasi certain. c'est le module qui te coute ton compte.",
    Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.red,
    Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 268), TextWrapped = true,
})

refreshCharge = function()
    local t = Charge.target
    chargeStat.Text = "cible: " .. (t and t:GetFullName() or "aucune") ..
        "\npayload: " .. PAYLOADS[CFG.chargeKind].name ..
        "\ncadence: " .. CFG.chargeRate .. "/s   envoyes: " .. Charge.sent ..
        "\netat: " .. (Charge.on and "EN COURS" or "arrete")
    for i = 1, #payloadBtns do
        local on = (i == CFG.chargeKind)
        payloadBtns[i].BackgroundColor3 = on and C.amber or C.row
        payloadBtns[i].TextColor3 = on and C.bg or C.dim
    end
    for i = 1, #rateBtns do
        local on = (rateOpts[i] == CFG.chargeRate)
        rateBtns[i].BackgroundColor3 = on and C.blue or C.row
        rateBtns[i].TextColor3 = on and C.bg or C.dim
    end
    cStart.Text = Charge.on and "EN COURS" or "TIRER"
end

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
local nrem = scanRemotes()
seedWorm()
refreshWorm()
refreshCharge()
rebuildPlayers()
setTab(1)
logLine("boot: " .. nrem .. " remotes, " .. #Worm.queue .. " graines")

LP.CharacterAdded:Connect(function()
    task.wait(1.2)
    clearTag()
    rebuildPlayers()
end)
