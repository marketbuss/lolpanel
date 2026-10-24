--===============================================================
-- lolpanel MINI — serveur direct (mobile)
-- tout part par les remotes du jeu : le serveur traite et replique
--===============================================================
local Players = game:GetService("Players")
local RS, RF = game:GetService("ReplicatedStorage"), game:GetService("ReplicatedFirst")
local UIS, LP = game:GetService("UserInputService"), Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
}

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(r, o) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end

local function pad(n, o)
    return mk("UIPadding", {
        PaddingLeft = UDim.new(0, n), PaddingRight = UDim.new(0, n),
        PaddingTop = UDim.new(0, n), PaddingBottom = UDim.new(0, n),
    }, o)
end

local function lbl(parent, props)
    local t = { BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = C.txt,
        TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center }
    for k, v in pairs(props or {}) do t[k] = v end
    return mk("TextLabel", t, parent)
end

local function btn(parent, props)
    local t = { BackgroundColor3 = C.row, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
        TextColor3 = C.txt, TextSize = 12, Text = "", AutoButtonColor = true }
    for k, v in pairs(props or {}) do t[k] = v end
    local b = mk("TextButton", t, parent)
    corner(8, b)
    return b
end

--=============================================================
local S = { remotes = {}, selected = nil, payload = "none", rate = 8, loops = {}, logLines = {}, scanning = false }
local logLabel, logScroll
local LOGC = { ok = "9dffb0", err = "ff6b76", info = "8b98ad", fire = "ffb246" }

local function addLog(msg, kind)
    local safe = tostring(msg):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    table.insert(S.logLines, '<font color="#' .. LOGC[kind or "info"] .. '">' .. safe .. "</font>")
    if #S.logLines > 150 then table.remove(S.logLines, 1) end
    if logLabel and logLabel.Parent then
        logLabel.Text = table.concat(S.logLines, "\n")
        task.defer(function()
            if logScroll and logScroll.Parent then
                logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
            end
        end)
    end
end

--=============================================================
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function parsePayload(txt)
    local out = {}
    if not txt then return out end
    txt = trim(txt)
    if txt == "" or txt == "none" or txt == "vide" then return out end
    for tok in string.gmatch(txt .. ",", "([^,]*),") do
        local t, low = trim(tok), trim(tok):lower()
        if t ~= "" then
            if low == "player" or low == "me" then table.insert(out, LP)
            elseif low == "random" then table.insert(out, math.random(1, 1000000))
            elseif low == "true" then table.insert(out, true)
            elseif low == "false" then table.insert(out, false)
            elseif t:match("^%-?%d+$") or t:match("^%-?%d*%.%d+$") then table.insert(out, tonumber(t))
            elseif t:match('^".-"$') or t:match("^'.-'$") then table.insert(out, t:sub(2, -2))
            elseif low:match("^vec%(") then
                local a, b, c = low:match("^vec%(%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s*%)$")
                table.insert(out, Vector3.new(tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0))
            elseif t == "{}" then table.insert(out, {})
            else table.insert(out, t) end
        end
    end
    return out
end

local function fire(remote, args, quiet)
    if not remote or not remote.Parent then return false, "remote detruit" end
    if remote:IsA("RemoteFunction") then
        task.spawn(function()
            local ok, err = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
            if not ok and not quiet then addLog("invoke " .. remote.Name .. " -> " .. tostring(err), "err") end
        end)
        return true
    end
    local ok, err = pcall(function() remote:FireServer(table.unpack(args)) end)
    if not ok and not quiet then addLog("fire " .. remote.Name .. " -> " .. tostring(err), "err") end
    return ok
end

--=============================================================
local function stopAll()
    S.loops = {}
    addLog("stop total — boucles coupees", "err")
end

local function startLoop(key, fn, tag)
    if S.loops[key] then
        S.loops[key] = nil
        addLog("boucle " .. (tag or key) .. " OFF", "info")
        return false
    end
    S.loops[key] = true
    addLog("boucle " .. (tag or key) .. " ON", "ok")
    task.spawn(function()
        while S.loops[key] and LP.Parent do
            local ok, err = pcall(fn)
            if not ok then addLog("boucle " .. (tag or key) .. ": " .. tostring(err), "err") break end
            task.wait(math.max(0.02, 1 / math.max(1, S.rate)))
        end
        S.loops[key] = nil
    end)
    return true
end

--=============================================================
local TAGS = {
    { id = "VITESSE", pats = { "speed", "walkspeed", "walk", "velocity" }, args = function() return { 100 } end },
    { id = "SAUT", pats = { "jump", "hop", "power" }, args = function() return { 200 } end },
    { id = "TP", pats = { "teleport", "tele", "tp", "position" }, args = function() return { Vector3.new(0, 60, 0) } end },
    { id = "CHAT", pats = { "chat", "say", "message", "msg" }, args = function() return { "gg" } end },
    { id = "DEGATS", pats = { "damage", "hit", "dmg", "attack", "hurt" }, args = function() return { 1 } end },
    { id = "ARGENT", pats = { "coin", "cash", "money", "gem", "token", "currency" }, args = function() return { 1 } end },
    { id = "REWARD", pats = { "reward", "claim", "daily", "bonus", "gift" }, args = function() return {} end },
    { id = "SHOP", pats = { "buy", "purchase", "shop", "spin", "roll", "crate", "egg", "gacha" }, args = function() return { 1 } end },
    { id = "ITEM", pats = { "item", "tool", "weapon", "give", "equip" }, args = function() return { 1 } end },
    { id = "ADMIN", pats = { "admin", "kick", "ban", "vote", "owner", "mod" }, args = function() return {} end },
    { id = "REPORT", pats = { "report", "flag", "abuse" }, args = function() return { LP } end },
}

local function scan()
    S.remotes = {}
    local seen = {}
    for _, root in ipairs({ RS, RF, workspace }) do
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, o in ipairs(desc) do
                if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") or o:IsA("UnreliableRemoteEvent") then
                    if not seen[o] then seen[o] = true; table.insert(S.remotes, o) end
                end
                if #S.remotes >= 800 then break end
            end
        end
        if #S.remotes >= 800 then break end
    end
    table.sort(S.remotes, function(a, b) return a:GetFullName():lower() < b:GetFullName():lower() end)
    return #S.remotes
end

local function findRemote(pats)
    local best, bestScore
    for _, r in ipairs(S.remotes) do
        local n, score = r:GetFullName():lower(), 0
        for _, p in ipairs(pats) do if n:find(p, 1, true) then score = score + 1 end end
        if score > 0 then
            if r:IsA("RemoteEvent") then score = score + 0.5 end
            if not bestScore or score > bestScore then best, bestScore = r, score end
        end
    end
    return best
end

--=============================================================
local function promptSpam(radius)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    local ok, desc = pcall(function() return workspace:GetDescendants() end)
    if not ok then return 0 end
    local n = 0
    for _, d in ipairs(desc) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local part = d.Parent
            if part and part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= radius then
                pcall(function() d:InputHoldBegin(); task.wait(0.02); d:InputHoldEnd() end)
                n = n + 1
            end
        end
    end
    return n
end

local TextChat
pcall(function() TextChat = game:GetService("TextChatService") end)

local function sendChat(msg)
    local sent = false
    if TextChat and TextChat.ChatVersion == Enum.ChatVersion.TextChatService then
        local ch = TextChat:FindFirstChild("TextChannels")
        local gen = ch and ch:FindFirstChild("RBXGeneral")
        if gen then sent = pcall(function() gen:SendAsync(msg) end) end
    end
    if not sent then
        pcall(function()
            local ev = RS:FindFirstChild("DefaultChatSystemChatEvents")
            local say = ev and ev:FindFirstChild("SayMessageRequest")
            if say then say:FireServer(msg, "All") end
        end)
    end
end

--=============================================================
local old = getgenv and getgenv().lolpanelMini
if old then pcall(function() old:Destroy() end) end

local gui = mk("ScreenGui", { Name = "lolpanel_mini", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 950, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
pcall(function() if type(gethui) == "function" then gui.Parent = gethui() end end)
if not gui.Parent then pcall(function() gui.Parent = game:GetService("CoreGui") end) end
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
if getgenv then getgenv().lolpanelMini = gui end

local W = 356
local H = math.min(560, math.max(360, workspace.CurrentCamera.ViewportSize.Y - 70))
local root = mk("Frame", { Name = "panel", Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2), BackgroundColor3 = C.bg, BorderSizePixel = 0 }, gui)
corner(14, root)
mk("UIStroke", { Color = C.green, Thickness = 1, Transparency = 0.35 }, root)

local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, root)
local dragZone = mk("Frame", { Size = UDim2.new(1, -46, 1, 0), BackgroundTransparency = 1, Active = true }, header)
lbl(dragZone, { Text = "lolpanel", Font = Enum.Font.GothamBold, TextSize = 17,
    Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(14, 8) })
lbl(dragZone, { Text = "MINI", Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.green,
    Size = UDim2.fromOffset(40, 22), Position = UDim2.fromOffset(93, 9) })
local statusLbl = lbl(dragZone, { Text = "0 remotes · -- ms", Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(14, 26) })

local closeBtn = btn(header, { Text = "X", TextColor3 = C.red, BackgroundColor3 = C.row,
    Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -42, 0, 6), TextSize = 14, Font = Enum.Font.GothamBold })
corner(10, closeBtn)

local body = mk("Frame", { Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46),
    BackgroundTransparency = 1 }, root)
pad(10, body)

local tabBar = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, body)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local pageArea = mk("Frame", { Size = UDim2.new(1, 0, 1, -86), Position = UDim2.fromOffset(0, 40),
    BackgroundTransparency = 1 }, body)
local footer = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, 0),
    AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 }, body)

--=============================================================
local function textbox(parent, y, placeholder, default)
    local b = mk("TextBox", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, y),
        BackgroundColor3 = C.row, BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 12,
        TextColor3 = C.txt, PlaceholderText = placeholder, PlaceholderColor3 = C.dim,
        Text = default or "", TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false }, parent)
    corner(8, b)
    pad(10, b)
    return b
end

local function slider(parent, y, min, max, val, onchange)
    local holder = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, y),
        BackgroundTransparency = 1 }, parent)
    local track = mk("Frame", { Size = UDim2.new(1, -8, 0, 6), Position = UDim2.fromOffset(4, 16),
        BackgroundColor3 = C.row2, BorderSizePixel = 0 }, holder)
    corner(3, track)
    local rel0 = math.clamp((val - min) / (max - min), 0, 1)
    local fill = mk("Frame", { Size = UDim2.new(rel0, 0, 1, 0), BackgroundColor3 = C.green,
        BorderSizePixel = 0 }, track)
    corner(3, fill)
    local knob = mk("Frame", { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(rel0, 0, 0.5, 0), BackgroundColor3 = C.txt, BorderSizePixel = 0 }, track)
    corner(8, knob)
    local hit = mk("TextButton", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Text = "" }, track)
    local valueLbl = lbl(holder, { Text = tostring(val), Font = Enum.Font.Code, TextSize = 11,
        TextColor3 = C.green, TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, -2) })
    local dragging = false
    local function apply(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        local v = math.floor(min + (max - min) * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valueLbl.Text = tostring(v)
        onchange(v)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            apply(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
            apply(i.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

--=============================================================
local pages, tabButtons = {}, {}
local function showPage(id)
    for k, f in pairs(pages) do f.Visible = (k == id) end
    for k, b in pairs(tabButtons) do
        b.BackgroundColor3 = (k == id) and C.green or C.row
        b.TextColor3 = (k == id) and C.bg or C.dim
    end
end

local function newPage(id)
    local f = mk("Frame", { Name = id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Visible = false }, pageArea)
    pages[id] = f
    return f
end

--=============================================================
local scanPage = newPage("SCAN")
local scanBtn = btn(scanPage, { Text = "SCANNER LES REMOTES", Font = Enum.Font.GothamBold, TextSize = 12,
    Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.green, TextColor3 = C.bg })
local filterBox = textbox(scanPage, 46, "filtrer : speed, coin, report...", "")
local countLbl = lbl(scanPage, { Text = "aucun scan", Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 84) })

local listScroll = mk("ScrollingFrame", { Size = UDim2.new(1, 0, 1, -106), Position = UDim2.fromOffset(0, 104),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.green,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, scanPage)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listScroll)

local rowCache, selectRemote = {}, nil

local function refreshList()
    local q = filterBox.Text:lower()
    local shown = 0
    for _, r in ipairs(rowCache) do r.Visible = false end
    for idx, r in ipairs(S.remotes) do
        local row = rowCache[idx]
        if not row then
            row = btn(listScroll, { Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = C.row, Text = "" })
            rowCache[idx] = row
            local nameL = lbl(row, { Size = UDim2.new(1, -74, 1, 0), Position = UDim2.fromOffset(9, 0),
                TextSize = 10, Font = Enum.Font.Code, TextTruncate = Enum.TextTruncate.AtEnd })
            local tagL = lbl(row, { Size = UDim2.fromOffset(64, 16), Position = UDim2.new(1, -72, 0.5, -8),
                TextSize = 9, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Right })
            row:SetAttribute("idx", idx)
            row.MouseButton1Click:Connect(function()
                local target = S.remotes[row:GetAttribute("idx")]
                if target then selectRemote(target) end
            end)
            row._name, row._tag = nameL, tagL
        end
        local full = r:GetFullName()
        if q == "" or full:lower():find(q, 1, true) then
            local tag = "—"
            for _, t in ipairs(TAGS) do
                local hit = false
                for _, p in ipairs(t.pats) do
                    if full:lower():find(p, 1, true) then hit = true; break end
                end
                if hit then tag = t.id; break end
            end
            row._name.Text, row._tag.Text = full, tag
            row._tag.TextColor3 = (tag == "—") and C.dim or C.amber
            row.BackgroundColor3 = (S.selected == r) and C.row2 or C.row
            row.Visible, row.LayoutOrder = true, shown
            shown = shown + 1
        end
    end
    countLbl.Text = shown .. " / " .. #S.remotes .. " remotes"
    listScroll.CanvasPosition = Vector2.new(0, 0)
end

scanBtn.MouseButton1Click:Connect(function()
    if S.scanning then return end
    S.scanning = true
    scanBtn.Text = "SCAN..."
    task.spawn(function()
        local t0 = os.clock()
        local n = scan()
        S.scanning = false
        scanBtn.Text = "SCANNER LES REMOTES"
        addLog("scan: " .. n .. " remotes en " .. string.format("%.0f", (os.clock() - t0) * 1000) .. " ms", "ok")
        refreshList()
    end)
end)
filterBox:GetPropertyChangedSignal("Text"):Connect(refreshList)

--=============================================================
local firePage = newPage("FIRE")
local selLbl = lbl(firePage, { Text = "aucun remote — va dans SCAN", Font = Enum.Font.Code, TextSize = 11,
    TextColor3 = C.amber, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    Size = UDim2.new(1, 0, 0, 40) })
local payloadBox = textbox(firePage, 44, "payload: 1, player, vec(0,60,0), none", "none")

local presetRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 84),
    BackgroundTransparency = 1 }, firePage)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder }, presetRow)
for i, p in ipairs({ "none", "1", "999999", "player", "random" }) do
    local b = btn(presetRow, { Text = p, TextSize = 10, Font = Enum.Font.Code, Size = UDim2.new(0, 64, 0, 30),
        BackgroundColor3 = C.row, TextColor3 = C.amber, LayoutOrder = i })
    b.MouseButton1Click:Connect(function()
        payloadBox.Text = p
        S.payload = p
    end)
end

local function doFire(count)
    local r = S.selected
    if not r or not r.Parent then addLog("aucun remote selectionne", "err"); return end
    local args = parsePayload(payloadBox.Text)
    if count == 1 then
        fire(r, args)
        addLog("fire " .. r.Name .. " (" .. #args .. " arg)", "fire")
        return
    end
    task.spawn(function()
        for _ = 1, count do
            if not r.Parent then break end
            fire(r, args, true)
            task.wait(0.03)
        end
        addLog("burst x" .. count .. " -> " .. r.Name, "fire")
    end)
end

local grid = mk("Frame", { Size = UDim2.new(1, 0, 0, 94), Position = UDim2.fromOffset(0, 120),
    BackgroundTransparency = 1 }, firePage)

local function gridBtn(text, col, row, textcol, cb)
    local b = btn(grid, { Text = text, Font = Enum.Font.GothamBold, TextSize = 11,
        Size = UDim2.new(0.5, -3, 0, 44), Position = UDim2.new(col * 0.5, col * 3, 0, row * 50),
        BackgroundColor3 = C.row, TextColor3 = textcol })
    b.MouseButton1Click:Connect(cb)
end

gridBtn("TIR x1", 0, 0, C.green, function() doFire(1) end)
gridBtn("TIR x10", 1, 0, C.green, function() doFire(10) end)
gridBtn("TIR x50", 0, 1, C.amber, function() doFire(50) end)
gridBtn("INVOQUE", 1, 1, C.amber, function()
    local r = S.selected
    if not r then addLog("aucun remote selectionne", "err"); return end
    if not r:IsA("RemoteFunction") then addLog(r.Name .. " n'est pas une RemoteFunction", "err"); return end
    fire(r, parsePayload(payloadBox.Text))
    addLog("invoke " .. r.Name, "fire")
end)

local loopBtn = btn(firePage, { Text = "BOUCLE OFF", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 220),
    BackgroundColor3 = C.row, TextColor3 = C.dim })
loopBtn.MouseButton1Click:Connect(function()
    if not S.selected then addLog("aucun remote selectionne", "err"); return end
    local r, args = S.selected, parsePayload(payloadBox.Text)
    local on = startLoop("sel", function() fire(r, args, true) end, "FIRE " .. r.Name)
    loopBtn.Text = on and "BOUCLE ON" or "BOUCLE OFF"
    loopBtn.BackgroundColor3 = on and C.green or C.row
    loopBtn.TextColor3 = on and C.bg or C.dim
end)

lbl(firePage, { Text = "rythme (tirs/seconde)", Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 264) })
slider(firePage, 276, 1, 60, S.rate, function(v) S.rate = v end)

function selectRemote(r)
    S.selected = r
    selLbl.Text = r:GetFullName() .. "  [" .. r.ClassName .. "]"
    addLog("selection: " .. r:GetFullName(), "info")
    showPage("FIRE")
    refreshList()
end

--=============================================================
local autoPage = newPage("AUTO")
local autoScroll = mk("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.green,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, autoPage)
mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, autoScroll)

local autoBtns = {}
local function autoRow(text, sub, cb)
    local b = btn(autoScroll, { Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = C.row,
        Text = "", LayoutOrder = #autoBtns + 1 })
    local t = lbl(b, { Text = text, Font = Enum.Font.GothamBold, TextSize = 11,
        Size = UDim2.new(1, -16, 0, 15), Position = UDim2.fromOffset(9, 6) })
    local s = lbl(b, { Text = sub or "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
        Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(9, 21),
        TextTruncate = Enum.TextTruncate.AtEnd })
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(cb, b, t, s)
        if not ok then addLog("auto: " .. tostring(err), "err") end
    end)
    table.insert(autoBtns, b)
    return b, t, s
end

for _, tag in ipairs(TAGS) do
    autoRow("▸ " .. tag.id, "cherche un remote " .. tag.pats[1], function(b, t, s)
        if #S.remotes == 0 then addLog("scan d'abord (onglet SCAN)", "err"); return end
        local key = "tag:" .. tag.id
        if S.loops[key] then
            S.loops[key] = nil
            b.BackgroundColor3, t.TextColor3 = C.row, C.txt
            addLog(tag.id .. " OFF", "info")
            return
        end
        local r = findRemote(tag.pats)
        if not r then addLog(tag.id .. ": aucun remote correspondant", "err"); s.Text = "introuvable"; return end
        S.selected = r
        b.BackgroundColor3, t.TextColor3 = C.row2, C.green
        s.Text = r:GetFullName()
        selLbl.Text = r:GetFullName() .. "  [" .. r.ClassName .. "]"
        startLoop(key, function() fire(r, tag.args(), true) end, tag.id)
        refreshList()
    end)
end

autoRow("PROMPT SPAM (40 studs)", "portes, leviers, achats — le serveur traite", function(b, t, s)
    local key = "prompts"
    if S.loops[key] then
        S.loops[key] = nil
        b.BackgroundColor3, t.TextColor3 = C.row, C.txt
        addLog("PROMPT SPAM OFF", "info")
        return
    end
    b.BackgroundColor3, t.TextColor3 = C.row2, C.green
    startLoop(key, function()
        local n = promptSpam(40)
        if n > 0 then s.Text = n .. " prompts touches" end
    end, "PROMPT SPAM")
end)

autoRow("CHAT FLOOD", "TextChatService puis fallback legacy", function(b, t)
    local key = "chat"
    if S.loops[key] then
        S.loops[key] = nil
        b.BackgroundColor3, t.TextColor3 = C.row, C.txt
        addLog("CHAT FLOOD OFF", "info")
        return
    end
    b.BackgroundColor3, t.TextColor3 = C.row2, C.green
    startLoop(key, function() sendChat("gg ez") end, "CHAT FLOOD")
end)

autoRow("RESET PERSONNAGE", "Humanoid.Health = 0, replique serveur", function()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.Health = 0; addLog("reset envoye", "fire") else addLog("pas de personnage", "err") end
end)

autoRow("SERVEUR SUIVANT", "TeleportService, quitte la partie", function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
end)

--=============================================================
local logPage = newPage("LOG")
logScroll = mk("ScrollingFrame", { Size = UDim2.new(1, 0, 1, -42), BackgroundColor3 = C.row,
    BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.green,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, logPage)
corner(8, logScroll)
pad(8, logScroll)
logLabel = mk("TextLabel", { Size = UDim2.new(1, -6, 0, 0), BackgroundTransparency = 1,
    Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.txt, RichText = true, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    AutomaticSize = Enum.AutomaticSize.Y, Text = "" }, logScroll)

local clearBtn = btn(logPage, { Text = "VIDER LE LOG", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1),
    BackgroundColor3 = C.row, TextColor3 = C.dim })
clearBtn.MouseButton1Click:Connect(function() S.logLines = {}; logLabel.Text = "" end)

--=============================================================
for i, id in ipairs({ "SCAN", "FIRE", "AUTO", "LOG" }) do
    local b = btn(tabBar, { Text = id, Font = Enum.Font.GothamBold, TextSize = 10,
        Size = UDim2.new(0.25, -3, 1, 0), BackgroundColor3 = C.row, TextColor3 = C.dim, LayoutOrder = i })
    corner(8, b)
    tabButtons[id] = b
    b.MouseButton1Click:Connect(function() showPage(id) end)
end

--=============================================================
local panicBtn = btn(footer, { Text = "STOP TOUT", Font = Enum.Font.GothamBold, TextSize = 12,
    Size = UDim2.new(0.62, -3, 1, 0), BackgroundColor3 = C.red, TextColor3 = C.txt })
panicBtn.MouseButton1Click:Connect(function()
    stopAll()
    loopBtn.Text, loopBtn.BackgroundColor3, loopBtn.TextColor3 = "BOUCLE OFF", C.row, C.dim
    for _, b in ipairs(autoBtns) do
        b.BackgroundColor3 = C.row
        local t = b:FindFirstChildWhichIsA("TextLabel")
        if t then t.TextColor3 = C.txt end
    end
    refreshList()
end)

local hideBtn = btn(footer, { Text = "RANGER", Font = Enum.Font.GothamBold, TextSize = 12,
    Size = UDim2.new(0.38, -3, 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0),
    BackgroundColor3 = C.row, TextColor3 = C.dim })

local float = btn(gui, { Text = "LP", Font = Enum.Font.GothamBold, TextSize = 13,
    Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 16, 0.5, -23),
    BackgroundColor3 = C.green, TextColor3 = C.bg, Visible = false })
corner(23, float)
float.MouseButton1Click:Connect(function() float.Visible = false; root.Visible = true end)
hideBtn.MouseButton1Click:Connect(function() root.Visible = false; float.Visible = true end)

closeBtn.MouseButton1Click:Connect(function()
    stopAll()
    gui:Destroy()
    if getgenv then getgenv().lolpanelMini = nil end
end)

--=============================================================
local dragging, dragStart, startPos = false, nil, nil
dragZone.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragStart, startPos = true, i.Position, root.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - dragStart
        root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

--=============================================================
task.spawn(function()
    while gui.Parent do
        local ping = "--"
        pcall(function() ping = string.format("%.0f", LP:GetNetworkPing() * 1000) end)
        local loops = 0
        for _ in pairs(S.loops) do loops = loops + 1 end
        statusLbl.Text = #S.remotes .. " remotes · " .. ping .. " ms · " .. loops .. " loop"
        task.wait(1)
    end
end)

showPage("SCAN")
refreshList()
addLog("lolpanel MINI pret — scanne, choisis, tire", "ok")
addLog("tout passe par les remotes du jeu", "info")
print("[lolpanel MINI] charge — parent UI: " .. tostring(gui.Parent))
