--===============================================================
-- lolpanel REC — enregistreur / rejoueur de remotes
-- capture le trafic remote du JEU, rejoue des payloads deja valides
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
    cyan = Color3.fromRGB(110, 220, 255),
}

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(r, o) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function pad(n, o)
    return mk("UIPadding", { PaddingLeft = UDim.new(0, n), PaddingRight = UDim.new(0, n),
        PaddingTop = UDim.new(0, n), PaddingBottom = UDim.new(0, n) }, o)
end

local function lbl(parent, props)
    local t = { BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = C.txt,
        TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center }
    for k, v in pairs(props or {}) do t[k] = v end
    return mk("TextLabel", t, parent)
end

local function btn(parent, props)
    local t = { BackgroundColor3 = C.row, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
        TextColor3 = C.txt, TextSize = 11, Text = "", AutoButtonColor = true }
    for k, v in pairs(props or {}) do t[k] = v end
    local b = mk("TextButton", t, parent)
    corner(8, b)
    return b
end

--=============================================================
local gv = getgenv and getgenv() or _G

if gv.lolpanelRecWin then pcall(function() gv.lolpanelRecWin:Destroy() end) end

local REC = gv.lolpanelRecState
if not REC then
    REC = { entries = {}, byKey = {}, selected = nil, rate = 10, loop = false,
        hookOn = true, seen = 0, fps = 0 }
    gv.lolpanelRecState = REC
end
REC.loop = false

--=============================================================
local function typeSig(args, n)
    local parts = {}
    for i = 1, math.min(n, 4) do
        local v = args[i]
        local t = type(v)
        if t == "userdata" then
            local ok, cls = pcall(function() return v.ClassName end)
            t = ok and ("u:" .. tostring(cls)) or "userdata"
        elseif t == "table" then
            t = "table"
        end
        parts[#parts + 1] = t
    end
    return table.concat(parts, ",")
end

local function preview(args, n)
    local out = {}
    for i = 1, math.min(n, 3) do
        local v = args[i]
        local s
        if type(v) == "userdata" then
            local ok, name = pcall(function() return v:GetFullName() end)
            s = ok and tostring(name) or "instance"
        elseif type(v) == "table" then
            s = "{table}"
        else
            s = tostring(v)
        end
        if #s > 20 then s = s:sub(1, 20) .. "..." end
        out[#out + 1] = s
    end
    if n > 3 then out[#out + 1] = "+" .. (n - 3) end
    return table.concat(out, ", ")
end

local function capture(self, ...)
    if not REC.hookOn then return end
    local method
    if type(getnamecallmethod) == "function" then
        local ok, m = pcall(getnamecallmethod)
        if ok then method = m end
    end
    if method ~= "FireServer" and method ~= "InvokeServer" then return end
    if type(checkcaller) == "function" then
        local ok, mine = pcall(checkcaller)
        if ok and mine then return end
    end
    local okIs, isRemote = pcall(function()
        return self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent")
    end)
    if not okIs or not isRemote then return end

    local args = table.pack(...)
    local key = self:GetFullName() .. "|" .. args.n .. "|" .. typeSig(args, args.n)
    local e = REC.byKey[key]
    if e then
        e.count = e.count + 1
        e.args = args
    else
        if #REC.entries >= 200 then return end
        e = {
            remote = self, key = key, name = self.Name, full = self:GetFullName(),
            args = args, n = args.n, count = 1, prev = preview(args, args.n),
            className = self.ClassName,
        }
        REC.byKey[key] = e
        table.insert(REC.entries, e)
    end
    REC.seen = REC.seen + 1
end

if not gv.lolpanelRecHooked then
    local okHook, errHook = pcall(function()
        if type(hookmetamethod) == "function" and type(newcclosure) == "function" then
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                pcall(capture, self, ...)
                return old(self, ...)
            end))
            gv.lolpanelRecOld = old
        elseif type(getrawmetatable) == "function" and type(newcclosure) == "function" then
            local mt = getrawmetatable(game)
            local prev = mt.__namecall
            if type(setreadonly) == "function" then pcall(setreadonly, mt, false) end
            mt.__namecall = newcclosure(function(self, ...)
                pcall(capture, self, ...)
                return prev(self, ...)
            end)
            if type(setreadonly) == "function" then pcall(setreadonly, mt, true) end
        else
            error("ni hookmetamethod ni getrawmetatable")
        end
    end)
    gv.lolpanelRecHooked = okHook
    gv.lolpanelRecErr = (not okHook) and tostring(errHook) or nil
end

--=============================================================
local W, H = 340, 470
local gui = mk("ScreenGui", { Name = "lolpanel_rec", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 940, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
pcall(function() if type(gethui) == "function" then gui.Parent = gethui() end end)
if not gui.Parent then pcall(function() gui.Parent = game:GetService("CoreGui") end) end
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
gv.lolpanelRecWin = gui

local root = mk("Frame", { Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5, -W / 2 + 12, 0.5, -H / 2 + 12),
    BackgroundColor3 = C.bg, BorderSizePixel = 0 }, gui)
corner(14, root)
mk("UIStroke", { Color = C.cyan, Thickness = 1, Transparency = 0.35 }, root)

local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1 }, root)
local dragZone = mk("Frame", { Size = UDim2.new(1, -46, 1, 0), BackgroundTransparency = 1, Active = true }, header)
lbl(dragZone, { Text = "REC", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.cyan,
    Size = UDim2.fromOffset(60, 20), Position = UDim2.fromOffset(14, 6) })
lbl(dragZone, { Text = "capture remotes", Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(14, 24) })

local closeBtn = btn(header, { Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(32, 32),
    Position = UDim2.new(1, -40, 0, 5), Font = Enum.Font.GothamBold })
corner(10, closeBtn)

local body = mk("Frame", { Size = UDim2.new(1, 0, 1, -42), Position = UDim2.fromOffset(0, 42),
    BackgroundTransparency = 1 }, root)
pad(10, body)

local statusLbl = lbl(body, { Text = "hook ...", Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 0) })

local listScroll = mk("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 176), Position = UDim2.fromOffset(0, 20),
    BackgroundColor3 = C.row, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y }, body)
corner(8, listScroll)
pad(6, listScroll)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listScroll)

local emptyLbl = lbl(listScroll, { Text = "joue normalement — le trafic du jeu se remplit ici",
    Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim, TextWrapped = true,
    Size = UDim2.new(1, -8, 0, 30), TextYAlignment = Enum.TextYAlignment.Top })

local selLbl = lbl(body, { Text = "rien de selectionne", Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = C.amber, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 202),
    TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
    TextTruncate = Enum.TextTruncate.AtEnd })

local bReplay = btn(body, { Text = "REJOUER", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(0.5, -3, 0, 40), Position = UDim2.fromOffset(0, 232),
    BackgroundColor3 = C.row, TextColor3 = C.green })
local bBurst = btn(body, { Text = "REJOUER x20", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(0.5, -3, 0, 40), Position = UDim2.fromOffset(0, 232),
    BackgroundColor3 = C.row, TextColor3 = C.amber })
bBurst.Position = UDim2.new(0.5, 3, 0, 232)

local bLoop = btn(body, { Text = "BOUCLE OFF", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(0.5, -3, 0, 38), Position = UDim2.fromOffset(0, 278),
    BackgroundColor3 = C.row, TextColor3 = C.dim })
local bHook = btn(body, { Text = "HOOK ON", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(0.5, -3, 0, 38), Position = UDim2.new(0.5, 3, 0, 278),
    BackgroundColor3 = C.row, TextColor3 = C.green })

lbl(body, { Text = "rythme rejeu (tirs/s)", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim,
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 322) })

local track = mk("Frame", { Size = UDim2.new(1, -8, 0, 6), Position = UDim2.fromOffset(4, 348),
    BackgroundColor3 = C.row2, BorderSizePixel = 0 }, body)
corner(3, track)
local rel0 = math.clamp((REC.rate - 1) / 59, 0, 1)
local fill = mk("Frame", { Size = UDim2.new(rel0, 0, 1, 0), BackgroundColor3 = C.cyan,
    BorderSizePixel = 0 }, track)
corner(3, fill)
local knob = mk("Frame", { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(rel0, 0, 0.5, 0), BackgroundColor3 = C.txt, BorderSizePixel = 0 }, track)
corner(8, knob)
local rateLbl = lbl(body, { Text = tostring(REC.rate), Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Right,
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 338) })

local hit = mk("TextButton", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Text = "" }, track)

local slDragging = false
hit.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        slDragging = true
    end
end)
UIS.InputChanged:Connect(function(i)
    if slDragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local rel = math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        REC.rate = math.floor(1 + 59 * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        rateLbl.Text = tostring(REC.rate)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        slDragging = false
    end
end)

local clearBtn = btn(body, { Text = "VIDER", Font = Enum.Font.GothamBold, TextSize = 11,
    Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, 0),
    AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = C.row, TextColor3 = C.dim })

--=============================================================
local rows = {}

local function replay(e, times)
    if not e or not e.remote or not e.remote.Parent then return false end
    for i = 1, times do
        if not e.remote.Parent then break end
        pcall(function() e.remote:FireServer(table.unpack(e.args, 1, e.args.n)) end)
        if times > 1 then task.wait(0.02) end
    end
    return true
end

local function refresh()
    local n = #REC.entries
    emptyLbl.Visible = (n == 0)
    for i, e in ipairs(REC.entries) do
        local entry = e
        local row = rows[i]
        if not row then
            row = btn(listScroll, { Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = C.row, Text = "" })
            rows[i] = row
            local nameL = lbl(row, { Size = UDim2.new(1, -44, 0, 15), Position = UDim2.fromOffset(8, 3),
                Font = Enum.Font.Code, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd })
            local prevL = lbl(row, { Size = UDim2.new(1, -44, 0, 12), Position = UDim2.fromOffset(8, 17),
                Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
                TextTruncate = Enum.TextTruncate.AtEnd })
            local cntL = lbl(row, { Size = UDim2.fromOffset(36, 30), Position = UDim2.new(1, -40, 0, 1),
                Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.amber,
                TextXAlignment = Enum.TextXAlignment.Right })
            row._n, row._p, row._c = nameL, prevL, cntL
            row.MouseButton1Click:Connect(function()
                REC.selected = entry
                selLbl.Text = entry.full .. " [" .. entry.className .. "] " .. entry.n .. " arg"
                row.BackgroundColor3 = C.row2
            end)
        end
        row._n.Text = e.name
        row._p.Text = e.prev
        row._c.Text = "x" .. e.count
        row.Visible = true
        row.LayoutOrder = i
        if REC.selected == e then row.BackgroundColor3 = C.row2
        elseif row.BackgroundColor3 ~= C.row then row.BackgroundColor3 = C.row end
    end
    for i = n + 1, #rows do rows[i].Visible = false end
end

bReplay.MouseButton1Click:Connect(function()
    if replay(REC.selected, 1) then selLbl.TextColor3 = C.green
    else selLbl.TextColor3 = C.red end
end)

bBurst.MouseButton1Click:Connect(function()
    local e = REC.selected
    if not e then return end
    task.spawn(function()
        for i = 1, 20 do
            if not e.remote.Parent then break end
            pcall(function() e.remote:FireServer(table.unpack(e.args, 1, e.args.n)) end)
            task.wait(0.03)
        end
    end)
end)

local loopToken = false
bLoop.MouseButton1Click:Connect(function()
    if loopToken then
        loopToken = false
        REC.loop = false
        bLoop.Text, bLoop.BackgroundColor3, bLoop.TextColor3 = "BOUCLE OFF", C.row, C.dim
        return
    end
    if not REC.selected then return end
    loopToken = true
    REC.loop = true
    local e = REC.selected
    bLoop.Text, bLoop.BackgroundColor3, bLoop.TextColor3 = "BOUCLE ON", C.cyan, C.bg
    task.spawn(function()
        while loopToken and e.remote and e.remote.Parent do
            pcall(function() e.remote:FireServer(table.unpack(e.args, 1, e.args.n)) end)
            task.wait(math.max(0.02, 1 / math.max(1, REC.rate)))
        end
        loopToken = false
        REC.loop = false
        bLoop.Text, bLoop.BackgroundColor3, bLoop.TextColor3 = "BOUCLE OFF", C.row, C.dim
    end)
end)

bHook.MouseButton1Click:Connect(function()
    REC.hookOn = not REC.hookOn
    bHook.Text = REC.hookOn and "HOOK ON" or "HOOK OFF"
    bHook.TextColor3 = REC.hookOn and C.green or C.red
end)

clearBtn.MouseButton1Click:Connect(function()
    REC.entries = {}
    REC.byKey = {}
    REC.selected = nil
    REC.seen = 0
    selLbl.Text = "rien de selectionne"
    refresh()
end)

closeBtn.MouseButton1Click:Connect(function()
    loopToken = false
    REC.loop = false
    gui:Destroy()
    gv.lolpanelRecWin = nil
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
    local lastSeen = REC.seen
    while gui.Parent do
        REC.fps = REC.seen - lastSeen
        lastSeen = REC.seen
        statusLbl.Text = (REC.hookOn and "hook ON" or "hook OFF")
            .. " · " .. #REC.entries .. " sig · " .. REC.seen .. " appels · " .. REC.fps .. "/s"
        refresh()
        task.wait(0.5)
    end
end)

if gv.lolpanelRecErr then
    statusLbl.Text = "hook: " .. tostring(gv.lolpanelRecErr)
end

refresh()
print("[lolpanel REC] charge — hook: " .. tostring(gv.lolpanelRecHooked)
    .. " · signatures: " .. tostring(#REC.entries))
