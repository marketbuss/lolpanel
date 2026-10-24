--===============================================================
-- lolpanel GRABBER
-- outil "Grabber" dans le sac: tap = saisir, re-tap = lacher.
-- les parts suivent la camera. orbit autour du joueur.
-- Delta / Android. local seulement, zero remote.
--===============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local C = {
    bg = Color3.fromRGB(9, 11, 16), row = Color3.fromRGB(22, 26, 36),
    row2 = Color3.fromRGB(32, 38, 52), green = Color3.fromRGB(122, 255, 145),
    amber = Color3.fromRGB(255, 178, 70), red = Color3.fromRGB(255, 84, 94),
    blue = Color3.fromRGB(120, 180, 255), violet = Color3.fromRGB(190, 150, 255),
    txt = Color3.fromRGB(228, 234, 243), dim = Color3.fromRGB(118, 130, 150),
}

local logLine
local refreshUI
local win, crosshair

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

--===============================================================
-- helpers
--===============================================================
local function char()
    local c = LP.Character
    if c and c.Parent then return c end
    return nil
end

local function root()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function blocked(o)
    if not o then return true end
    if o:IsA("Terrain") then return true end
    if not o:IsA("BasePart") then return true end
    local c = char()
    if c and o:IsDescendantOf(c) then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and o:IsDescendantOf(p.Character) then return true end
    end
    if o.Name:find("lolpanel", 1, true) then return true end
    return false
end

local function pickAt(sx, sy)
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local ray = cam:ScreenPointToRay(sx, sy)
    local params = RaycastParams.new()
    local ft
    pcall(function() ft = Enum.RaycastFilterType.Exclude end)
    if not ft then ft = Enum.RaycastFilterType.Blacklist end
    params.FilterType = ft
    local ignore = {}
    local c = char()
    if c then table.insert(ignore, c) end
    params.FilterDescendantsInstances = ignore
    local ok, res = pcall(function()
        return workspace:Raycast(ray.Origin, ray.Direction * 4000, params)
    end)
    if ok and res and res.Instance and not blocked(res.Instance) then
        return res.Instance
    end
    return nil
end

local function screenCenterPick()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local v = cam.ViewportSize
    return pickAt(v.X * 0.5, v.Y * 0.5)
end

--===============================================================
-- etat
--===============================================================
local G = {
    part = nil, savedAnchored = true, savedCollide = true,
    rot = CFrame.new(), dist = 12, equipped = false,
}

local Orbit = {
    on = false, parts = {}, saved = {}, angle = 0,
    radius = 14, speed = 2.2, height = 2, cap = 120,
}

--===============================================================
-- grab
--===============================================================
local function releaseOne(part, savedAnchored, savedCollide)
    if not part or not part.Parent then return end
    pcall(function() part.Anchored = savedAnchored end)
    pcall(function() part.CanCollide = savedCollide end)
end

local function release()
    if G.part then
        releaseOne(G.part, G.savedAnchored, G.savedCollide)
    end
    G.part = nil
end

local function grab(part)
    if not part then return end
    release()
    G.part = part
    G.savedAnchored = part.Anchored
    G.savedCollide = part.CanCollide
    G.rot = part.CFrame - part.Position
    pcall(function()
        part.Anchored = true
        part.CanCollide = false
    end)
end

local function toggleGrab()
    if G.part then
        release()
        logLine("grab: lache")
    else
        local p = screenCenterPick()
        if p then
            grab(p)
            local cam = workspace.CurrentCamera
            if cam then
                G.dist = math.clamp((p.Position - cam.CFrame.Position).Magnitude, 3, 120)
            end
            logLine("grab: " .. p.Name)
        else
            logLine("grab: rien sous le viseur")
        end
    end
    refreshUI()
end

--===============================================================
-- orbit
--===============================================================
local function stopOrbit()
    for i = 1, #Orbit.parts do
        local p = Orbit.parts[i]
        if p and p.Parent then
            releaseOne(p, Orbit.saved[i].a, Orbit.saved[i].c)
        end
    end
    Orbit.parts = {}
    Orbit.saved = {}
    Orbit.on = false
end

local function collectNearby(maxCount, maxRadius)
    local origin = root()
    if not origin then return {} end
    local center = origin.Position

    local chars = {}
    local c = char()
    if c then chars[c] = true end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then chars[pl.Character] = true end
    end

    local function inCharacter(o)
        local anc, guard = o.Parent, 0
        while anc and guard < 5 do
            if chars[anc] then return true end
            anc = anc.Parent
            guard = guard + 1
        end
        return false
    end

    local cand = {}
    local ok, desc = pcall(function() return workspace:GetDescendants() end)
    if not ok then return {} end
    for i = 1, #desc do
        local o = desc[i]
        if not o then break end
        if o:IsA("BasePart") and o.Anchored then
            local d = (o.Position - center).Magnitude
            if d <= maxRadius and not inCharacter(o) then
                table.insert(cand, { p = o, d = d })
            end
        end
    end
    table.sort(cand, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(maxCount, #cand) do
        table.insert(out, cand[i].p)
    end
    return out
end

local function startOrbit(useAll)
    if Orbit.on then return end
    if G.part then release() end
    local cap = useAll and Orbit.cap or math.floor(Orbit.cap * 0.35)
    local list = collectNearby(cap, useAll and 220 or 90)
    if #list == 0 then
        logLine("orbit: aucune part ancre autour")
        return
    end
    Orbit.parts = {}
    Orbit.saved = {}
    for i = 1, #list do
        local p = list[i]
        Orbit.saved[i] = { a = p.Anchored, c = p.CanCollide }
        pcall(function()
            p.Anchored = true
            p.CanCollide = false
        end)
        table.insert(Orbit.parts, p)
    end
    Orbit.angle = 0
    Orbit.on = true
    logLine("orbit: " .. #Orbit.parts .. " parts")
    refreshUI()
end

local function toggleOrbit()
    if Orbit.on then
        stopOrbit()
        logLine("orbit: stop")
        refreshUI()
    else
        startOrbit(false)
    end
end

--===============================================================
-- boucle
--===============================================================
RunService.RenderStepped:Connect(function(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end

    if G.part then
        if not G.part.Parent then
            G.part = nil
        else
            local target = cam.CFrame * CFrame.new(0, 0, -G.dist) * G.rot
            pcall(function() G.part.CFrame = target end)
        end
    end

    if Orbit.on then
        if #Orbit.parts == 0 then
            Orbit.on = false
        else
            Orbit.angle = Orbit.angle + dt * Orbit.speed
            local origin = root()
            local center = origin and origin.Position or cam.CFrame.Position
            local n = #Orbit.parts
            local step = (math.pi * 2) / math.max(1, n)
            for i = 1, n do
                local p = Orbit.parts[i]
                if p and p.Parent then
                    local a = Orbit.angle + (i - 1) * step
                    local off = Vector3.new(
                        math.cos(a) * Orbit.radius,
                        Orbit.height + math.sin(a * 2) * 1.5,
                        math.sin(a) * Orbit.radius
                    )
                    pcall(function()
                        p.CFrame = CFrame.new(center + off) * CFrame.Angles(0, a, 0)
                    end)
                end
            end
        end
    end
end)

--===============================================================
-- outil
--===============================================================
local TOOL_NAME = "Grabber"

local function destroyOldTool()
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        local old = bp:FindFirstChild(TOOL_NAME)
        if old then pcall(function() old:Destroy() end) end
    end
    local c = char()
    if c then
        local held = c:FindFirstChild(TOOL_NAME)
        if held then pcall(function() held:Destroy() end) end
    end
end

local tool
local function buildTool()
    destroyOldTool()
    tool = Instance.new("Tool")
    tool.Name = TOOL_NAME
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.ToolTip = "tap: saisir / lacher"
    tool.TextureId = ""

    tool.Equipped:Connect(function()
        G.equipped = true
        if crosshair then crosshair.Visible = true end
        pcall(function() win.Visible = true end)
        refreshUI()
    end)

    tool.Unequipped:Connect(function()
        G.equipped = false
        if crosshair then crosshair.Visible = false end
        release()
        refreshUI()
    end)

    local bp = LP:FindFirstChild("Backpack")
    if bp then
        tool.Parent = bp
    else
        tool.Parent = LP:WaitForChild("Backpack")
    end
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
    local old = getgenv()._grabber
    if old and old ~= gui then pcall(function() old:Destroy() end) end
    getgenv()._grabber = gui
end

local cam = workspace.CurrentCamera
local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
crosshair = mk("Frame", {
    Size = UDim2.fromOffset(6, 6),
    Position = UDim2.fromOffset(math.floor(vs.X / 2) - 3, math.floor(vs.Y / 2) - 3),
    BackgroundColor3 = C.amber, BorderSizePixel = 0, Visible = false,
    ZIndex = 99,
}, gui)
corner(3, crosshair)
mk("UIStroke", { Color = C.bg, Thickness = 1 }, crosshair)

local W, H = 286, 372
win = mk("Frame", {
    Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 8, 0, 74),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, gui)
corner(12, win)
mk("UIStroke", { Color = C.green, Thickness = 1, Transparency = 0.4 }, win)

local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, win)
local drag = mk("Frame", {
    Size = UDim2.new(1, -36, 1, 0), BackgroundTransparency = 1, Active = true,
}, head)
lbl(drag, {
    Text = "GRABBER", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.green, Size = UDim2.fromOffset(150, 28),
    Position = UDim2.fromOffset(12, 0),
})
local closeBtn = btn(head, {
    Text = "X", TextColor3 = C.red, Size = UDim2.fromOffset(26, 22),
    Position = UDim2.new(1, -32, 0, 3),
})
closeBtn.MouseButton1Click:Connect(function() win.Visible = false end)

local statLbl = lbl(win, {
    Text = "", Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.dim,
    Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 30),
    TextWrapped = true,
})

local grabBtn = btn(win, {
    Text = "SAISIR (VISEUR)", Size = UDim2.new(1, -20, 0, 38),
    Position = UDim2.fromOffset(10, 68), TextColor3 = C.green, TextSize = 11,
})
stroke(C.green, grabBtn, 1)
grabBtn.MouseButton1Click:Connect(function() toggleGrab() end)

local distLbl = lbl(win, {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.txt,
    Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 112),
})
local dMinus = btn(win, {
    Text = "DIST -", Size = UDim2.new(0.5, -15, 0, 30),
    Position = UDim2.fromOffset(10, 130), TextSize = 9,
})
local dPlus = btn(win, {
    Text = "DIST +", Size = UDim2.new(0.5, -15, 0, 30),
    Position = UDim2.new(0.5, 5, 0, 130), TextSize = 9,
})
dMinus.MouseButton1Click:Connect(function()
    G.dist = math.max(3, G.dist - 2)
    refreshUI()
end)
dPlus.MouseButton1Click:Connect(function()
    G.dist = math.min(150, G.dist + 2)
    refreshUI()
end)

local orbitBtn = btn(win, {
    Text = "ORBIT", Size = UDim2.new(0.5, -15, 0, 40),
    Position = UDim2.fromOffset(10, 168), TextColor3 = C.amber, TextSize = 11,
})
stroke(C.amber, orbitBtn, 1)
orbitBtn.MouseButton1Click:Connect(function() toggleOrbit() end)

local orbitAllBtn = btn(win, {
    Text = "ORBIT TOUT", Size = UDim2.new(0.5, -15, 0, 40),
    Position = UDim2.new(0.5, 5, 0, 168), TextColor3 = C.violet, TextSize = 10,
})
stroke(C.violet, orbitAllBtn, 1)
orbitAllBtn.MouseButton1Click:Connect(function()
    if Orbit.on then
        stopOrbit()
        logLine("orbit: stop")
        refreshUI()
    else
        startOrbit(true)
    end
end)

local radLbl = lbl(win, {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.txt,
    Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 214),
})
local rMinus = btn(win, {
    Text = "RAYON -", Size = UDim2.new(0.5, -15, 0, 28),
    Position = UDim2.fromOffset(10, 232), TextSize = 9,
})
local rPlus = btn(win, {
    Text = "RAYON +", Size = UDim2.new(0.5, -15, 0, 28),
    Position = UDim2.new(0.5, 5, 0, 232), TextSize = 9,
})
rMinus.MouseButton1Click:Connect(function()
    Orbit.radius = math.max(5, Orbit.radius - 2)
    refreshUI()
end)
rPlus.MouseButton1Click:Connect(function()
    Orbit.radius = math.min(80, Orbit.radius + 2)
    refreshUI()
end)

local spdLbl = lbl(win, {
    Text = "", Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.txt,
    Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 264),
})
local sMinus = btn(win, {
    Text = "VITESSE -", Size = UDim2.new(0.5, -15, 0, 28),
    Position = UDim2.fromOffset(10, 282), TextSize = 9,
})
local sPlus = btn(win, {
    Text = "VITESSE +", Size = UDim2.new(0.5, -15, 0, 28),
    Position = UDim2.new(0.5, 5, 0, 282), TextSize = 9,
})
sMinus.MouseButton1Click:Connect(function()
    Orbit.speed = math.max(0.3, Orbit.speed - 0.4)
    refreshUI()
end)
sPlus.MouseButton1Click:Connect(function()
    Orbit.speed = math.min(12, Orbit.speed + 0.4)
    refreshUI()
end)

local detachBtn = btn(win, {
    Text = "TOUT LACHER", Size = UDim2.new(1, -20, 0, 32),
    Position = UDim2.fromOffset(10, 316), TextColor3 = C.red, TextSize = 10,
})
stroke(C.red, detachBtn, 1)
detachBtn.MouseButton1Click:Connect(function()
    release()
    stopOrbit()
    logLine("tout lache")
    refreshUI()
end)

local logLbl = lbl(win, {
    Text = "", Font = Enum.Font.Code, TextSize = 7, TextColor3 = C.dim,
    Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 350),
    TextTruncate = Enum.TextTruncate.AtEnd,
})

logLine = function(txt)
    if logLbl then logLbl.Text = tostring(txt) end
end

refreshUI = function()
    statLbl.Text = (G.equipped and "equipe" or "outil dans le sac") ..
        " | orbit " .. (#Orbit.parts > 0 and #Orbit.parts or 0) .. " parts" ..
        "\nsaisi: " .. (G.part and G.part.Name or "rien")
    grabBtn.Text = G.part and "LACHER" or "SAISIR (VISEUR)"
    grabBtn.TextColor3 = G.part and C.amber or C.green
    distLbl.Text = "distance " .. math.floor(G.dist) .. " studs"
    radLbl.Text = "rayon " .. math.floor(Orbit.radius) .. " | hauteur " .. Orbit.height
    spdLbl.Text = "vitesse " .. string.format("%.1f", Orbit.speed)
    if Orbit.on then
        orbitBtn.BackgroundColor3 = C.amber
        orbitBtn.TextColor3 = C.bg
        orbitBtn.Text = "ORBIT STOP"
        orbitAllBtn.BackgroundColor3 = C.row
        orbitAllBtn.TextColor3 = C.violet
        orbitAllBtn.Text = "ORBIT TOUT"
    else
        orbitBtn.BackgroundColor3 = C.row
        orbitBtn.TextColor3 = C.amber
        orbitBtn.Text = "ORBIT"
        orbitAllBtn.BackgroundColor3 = C.row
        orbitAllBtn.TextColor3 = C.violet
        orbitAllBtn.Text = "ORBIT TOUT"
    end
end

--===============================================================
-- drag fenetre
--===============================================================
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
-- touch libre: tap dans le monde = saisir
--===============================================================
UIS.TouchTap:Connect(function(pos, processed)
    if processed then return end
    if not G.equipped then return end
    if not win.Visible then return end
    local p = pickAt(pos.X, pos.Y)
    if p then
        if G.part == p then
            release()
            logLine("grab: lache")
        else
            grab(p)
            local cam2 = workspace.CurrentCamera
            if cam2 then
                G.dist = math.clamp((p.Position - cam2.CFrame.Position).Magnitude, 3, 120)
            end
            logLine("grab: " .. p.Name)
        end
        refreshUI()
    end
end)

--===============================================================
-- boot
--===============================================================
buildTool()
win.Visible = true
refreshUI()
logLine("pret: equipe le Grabber dans le sac")

LP.CharacterAdded:Connect(function()
    task.wait(1.2)
    G.part = nil
    G.equipped = false
    stopOrbit()
    buildTool()
    refreshUI()
end)
