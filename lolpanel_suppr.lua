--===============================================================
-- lolpanel SUPPR — outil de suppression de parts
-- vise, tape : prompt + remotes du jeu + contact, puis verifie
-- si la part disparait vraiment (donc replication serveur)
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

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
    return mk("UIPadding", { PaddingLeft = UDim.new(0, n), PaddingRight = UDim.new(0, n),
        PaddingTop = UDim.new(0, n), PaddingBottom = UDim.new(0, n) }, o)
end

local function lbl(parent, props)
    local t = { BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = C.txt,
        TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }
    for k, v in pairs(props or {}) do t[k] = v end
    return mk("TextLabel", t, parent)
end

local function btn(parent, props)
    local t = { BackgroundColor3 = C.row, BorderSizePixel = 0, Font = Enum.Font.GothamBold,
        TextColor3 = C.txt, TextSize = 10, Text = "", AutoButtonColor = true }
    for k, v in pairs(props or {}) do t[k] = v end
    local b = mk("TextButton", t, parent)
    corner(7, b)
    return b
end

--=============================================================
local G = { prompt = true, remote = true, brute = false, touch = true, busy = false, last = 0 }

--=============================================================
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
    local origin = cam.CFrame.Position
    local res = workspace:Raycast(origin, cam.CFrame.LookVector * 2000, params)
    if res and res.Instance then return res.Instance end
    return nil
end

--=============================================================
local HINTS = {
    "delete", "remove", "destroy", "break", "mine", "harvest", "collect",
    "pickup", "take", "sell", "clean", "clear", "chop", "dig", "grab",
    "interact", "place", "build", "despawn", "consume", "eat",
}

local function collectRemotes()
    local out = {}
    local seen = {}
    for _, root in ipairs({ RS, workspace }) do
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, o in ipairs(desc) do
                if (o:IsA("RemoteEvent") or o:IsA("RemoteFunction")) and not seen[o] then
                    seen[o] = true
                    table.insert(out, o)
                    if #out >= 400 then return out end
                end
            end
        end
    end
    return out
end

local function hintScore(remote)
    local n = remote:GetFullName():lower()
    for i = 1, #HINTS do
        if n:find(HINTS[i], 1, true) then return i end
    end
    return nil
end

--=============================================================
local function tryPrompts(part)
    local n = 0
    local node = part
    local depth = 0
    while node and node ~= workspace and node ~= game and depth < 4 do
        local ok, desc = pcall(function() return node:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                if d:IsA("ProximityPrompt") and d.Enabled then
                    pcall(function() d:InputHoldBegin() end)
                    task.wait(0.02)
                    pcall(function() d:InputHoldEnd() end)
                    n = n + 1
                end
            end
        end
        node = node.Parent
        depth = depth + 1
    end
    return n
end

local function tryTouch(part)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not part:IsA("BasePart") then return false end
    local old = hrp.CFrame
    pcall(function()
        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 2.5, 0))
    end)
    task.wait(0.12)
    pcall(function() hrp.CFrame = old end)
    return true
end

--=============================================================
local PAYLOADS = { "inst", "inst,true", "inst,player", "name", "path" }

local function buildArgs(kind, part)
    if kind == "inst" then return { part }
    elseif kind == "inst,true" then return { part, true }
    elseif kind == "inst,player" then return { part, LP }
    elseif kind == "name" then return { part.Name }
    elseif kind == "path" then return { part:GetFullName() }
    end
    return { part }
end

local function fireOne(remote, part, kind, onError)
    local args = buildArgs(kind, part)
    if remote:IsA("RemoteFunction") then
        task.spawn(function()
            local ok, err = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
            if not ok and onError then onError(remote, err) end
        end)
        return true
    end
    return pcall(function() remote:FireServer(table.unpack(args)) end)
end

--=============================================================
local function watch(part)
    local t0 = os.clock()
    while os.clock() - t0 < 2.0 do
        if not part or not part.Parent then return "detruit" end
        local okT, tr = pcall(function() return part.Transparency end)
        if okT and type(tr) == "number" and tr >= 0.99 then return "rendu invisible" end
        local okS, sz = pcall(function() return part.Size.Magnitude end)
        if okS and type(sz) == "number" and sz < 0.4 then return "reduit a zero" end
        task.wait(0.08)
    end
    return nil
end

--=============================================================
local gui = mk("ScreenGui", { Name = "lolpanel_suppr", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 960, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
pcall(function() if type(gethui) == "function" then gui.Parent = gethui() end end)
if not gui.Parent then pcall(function() gui.Parent = game:GetService("CoreGui") end) end
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local oldGui = getgenv and getgenv().lolpanelSupprGui
if oldGui and oldGui ~= gui then pcall(function() oldGui:Destroy() end) end
if getgenv then getgenv().lolpanelSupprGui = gui end

local W, H = 262, 180
local win = mk("Frame", { Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 14, 0, 110),
    BackgroundColor3 = C.bg, BorderSizePixel = 0 }, gui)
corner(12, win)
mk("UIStroke", { Color = C.amber, Thickness = 1, Transparency = 0.35 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", { Size = UDim2.new(1, -34, 1, 0), BackgroundTransparency = 1, Active = true }, head)
lbl(drag, { Text = "SUPPR", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.amber,
    Size = UDim2.fromOffset(120, 30), Position = UDim2.fromOffset(12, 0) })
local closeBtn = btn(head, { Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(28, 24),
    Position = UDim2.new(1, -34, 0, 3) })
corner(8, closeBtn)

local targetLbl = lbl(win, { Text = "vise une part, equipe SUPPR, tape", Font = Enum.Font.Code,
    TextSize = 9, TextColor3 = C.dim, Size = UDim2.new(1, -24, 0, 13), Position = UDim2.fromOffset(12, 32),
    TextTruncate = Enum.TextTruncate.AtEnd })

local statusLbl = lbl(win, { Text = "pret", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.green,
    Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 46), TextWrapped = true })

local logLbl = lbl(win, { Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 78), TextWrapped = true })

local function status(txt, col)
    statusLbl.Text = tostring(txt)
    statusLbl.TextColor3 = col or C.green
end

local function addLog(txt)
    local cur = logLbl.Text
    local lines = {}
    if cur ~= "" then
        for l in string.gmatch(cur, "[^\n]+") do table.insert(lines, l) end
    end
    table.insert(lines, tostring(txt))
    while #lines > 3 do table.remove(lines, 1) end
    logLbl.Text = table.concat(lines, "\n")
end

local toggles = {}
local function makeToggle(key, label, x)
    local b = btn(win, { Text = label, Size = UDim2.new(0.25, -8, 0, 26),
        Position = UDim2.fromOffset(x, 112), BackgroundColor3 = C.row, TextColor3 = C.dim })
    toggles[key] = b
    b.MouseButton1Click:Connect(function()
        G[key] = not G[key]
        b.BackgroundColor3 = G[key] and C.green or C.row
        b.TextColor3 = G[key] and C.bg or C.dim
    end)
    b.BackgroundColor3 = G[key] and C.green or C.row
    b.TextColor3 = G[key] and C.bg or C.dim
    return b
end

makeToggle("prompt", "PROMPT", 10)
makeToggle("remote", "REMOTE", 74)
makeToggle("brute", "BRUTE", 138)
makeToggle("touch", "TOUCH", 202)

lbl(win, { Text = "BRUTE = tire sur TOUS les remotes. risque de kick.",
    Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 146), TextWrapped = true })

local dot = mk("Frame", { Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0.5, -3, 0.5, -3),
    BackgroundColor3 = C.green, BorderSizePixel = 0, Visible = false }, gui)
corner(3, dot)
mk("UIStroke", { Color = C.bg, Thickness = 1 }, dot)

--=============================================================
local function suppress()
    if G.busy then return end
    if os.clock() - G.last < 0.6 then return end
    local part = crosshairPart()
    if not part then
        status("rien sous le viseur", C.amber)
        return
    end
    G.last = os.clock()
    G.busy = true
    targetLbl.Text = part.Name .. "  [" .. part.ClassName .. "]"
    status("travail sur " .. part.Name .. "...", C.txt)
    local name = part.Name

    task.spawn(function()
        if G.prompt then
            status("prompt...", C.txt)
            local ok, n = pcall(tryPrompts, part)
            addLog("prompt: " .. (ok and n or 0))
        end

        if not part.Parent then
            status(name .. " — detruit (prompt)", C.green)
            addLog("SUCCES: plus la")
            G.busy = false
            return
        end

        if G.remote then
            status("scan des remotes...", C.txt)
            local remotes = collectRemotes()
            local hinted, others = {}, {}
            for _, r in ipairs(remotes) do
                local s = hintScore(r)
                if s then hinted[#hinted + 1] = r
                else others[#others + 1] = r end
            end
            addLog("remotes: " .. #hinted .. " cibles / " .. #others .. " autres")

            for i, r in ipairs(hinted) do
                if not part.Parent then break end
                if r.Parent then
                    for _, kind in ipairs(PAYLOADS) do
                        if not r.Parent then break end
                        pcall(fireOne, r, part, kind)
                    end
                end
                if i % 8 == 0 then
                    status("remotes cibles " .. i .. "/" .. #hinted, C.txt)
                    task.wait(0.01)
                end
            end

            if G.brute and part.Parent then
                for i, r in ipairs(others) do
                    if not part.Parent then break end
                    if r.Parent then pcall(fireOne, r, part, "inst") end
                    if i % 25 == 0 then
                        status("brute " .. i .. "/" .. #others, C.amber)
                        task.wait(0.03)
                    end
                end
            end
        end

        if G.touch and part.Parent then
            status("contact...", C.txt)
            pcall(tryTouch, part)
        end

        status("attente du serveur...", C.txt)
        local res = watch(part)
        if res == "detruit" then
            status(name .. " — DETRUIT (serveur)", C.green)
            addLog("SUCCES: retiree du monde")
        elseif res == "rendu invisible" then
            status(name .. " — masquee par le serveur", C.green)
            addLog("SUCCES: invisible pour tous")
        elseif res == "reduit a zero" then
            status(name .. " — reduite a zero", C.green)
            addLog("SUCCES: scale 0")
        else
            status(name .. " — toujours la. ce jeu valide.", C.amber)
            addLog("aucun remote n'a supprime")
        end
        G.busy = false
    end)
end

--=============================================================
local function hookTool(tool)
    tool.Activated:Connect(suppress)
    tool.Equipped:Connect(function()
        dot.Visible = true
        win.Visible = true
    end)
    tool.Unequipped:Connect(function() dot.Visible = false end)
end

local function give()
    local bp = LP:FindFirstChildOfClass("Backpack")
    if not bp then return end
    local old = bp:FindFirstChild("SUPPR")
    if old then pcall(function() old:Destroy() end) end
    local tool = Instance.new("Tool")
    tool.Name = "SUPPR"
    tool.ToolTip = "vise, tape, supprime"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    hookTool(tool)
    tool.Parent = bp
end

give()
LP.CharacterAdded:Connect(function()
    task.wait(1)
    give()
end)

--=============================================================
closeBtn.MouseButton1Click:Connect(function() win.Visible = false end)

local dragging, dragStart, startPos = false, nil, nil
drag.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragStart, startPos = true, i.Position, win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - dragStart
        win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

print("[lolpanel SUPPR] outil donne — 4 passes: prompt / remotes / brute / contact")
