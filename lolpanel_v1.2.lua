--=====================================================================
--  lolpanel v1.2 — mod menu Roblox (mobile first, Delta-safe)
--  Exécuteurs : Delta / Fluxus / Codex / Arceus / desktop
--  Répliqué : mouvement, animations, chat, fling/orbit/ragdoll.
--  Local : ESP, lumière, cosmétiques, FOV.
--=====================================================================

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UIS           = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local Lighting      = game:GetService("Lighting")
local TCS           = game:GetService("TextChatService")
local TeleportSvc   = game:GetService("TeleportService")
local HttpService   = game:GetService("HttpService")
local LP            = Players.LocalPlayer

--=====================================================================
--  PALETTE + HELPERS
--=====================================================================
local P = {
    bg        = Color3.fromRGB(9, 10, 15),
    panel     = Color3.fromRGB(15, 17, 24),
    card      = Color3.fromRGB(22, 25, 34),
    cardAlt   = Color3.fromRGB(29, 33, 44),
    stroke    = Color3.fromRGB(44, 49, 64),
    text      = Color3.fromRGB(235, 239, 247),
    muted     = Color3.fromRGB(138, 147, 168),
    accent    = Color3.fromRGB(157, 255, 94),
    accentDim = Color3.fromRGB(78, 140, 46),
    danger    = Color3.fromRGB(255, 92, 92),
}

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in next, props do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function corner(inst, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, inst)
end

local function stroke(inst, color, thickness)
    return new("UIStroke", {
        Color = color or P.stroke,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, inst)
end

local function label(parent, text, size, color, font, textSize, xAlign)
    return new("TextLabel", {
        Size = size or UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = color or P.text,
        Font = font or Enum.Font.GothamMedium,
        TextSize = textSize or 14,
        TextXAlignment = xAlign or Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
end

--=====================================================================
--  ROOT GUI
--=====================================================================
local function makeGuiRoot()
    local candidates = {}
    pcall(function()
        if type(gethui) == "function" then
            local hui = gethui()
            if hui then table.insert(candidates, hui) end
        end
    end)
    pcall(function() table.insert(candidates, game:GetService("CoreGui")) end)
    pcall(function()
        table.insert(candidates, LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui", 10))
    end)

    for _, parent in ipairs(candidates) do
        if parent then
            local built
            local ok = pcall(function()
                built = Instance.new("ScreenGui")
                built.Name = "lolpanel"
                built.ResetOnSpawn = false
                built.IgnoreGuiInset = true
                built.DisplayOrder = 999
                built.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                built.Enabled = true
                built.Parent = parent
            end)
            if ok and built and built.Parent then return built end
            if built then pcall(function() built:Destroy() end) end
        end
    end
    return nil
end

local gui = makeGuiRoot()
if not gui then
    warn("[lolpanel] ScreenGui impossible — exécuteur bloque CoreGui et PlayerGui")
    return
end

if getgenv then
    if getgenv().lolpanel_gui and getgenv().lolpanel_gui ~= gui then
        pcall(function() getgenv().lolpanel_gui:Destroy() end)
    end
    getgenv().lolpanel_gui = gui
    getgenv().lolpanel_loaded = true
end

--=====================================================================
--  NOTIFICATIONS
--=====================================================================
local function notify(text)
    if not gui.Parent then return end
    local holder = gui:FindFirstChild("toasts")
    if not holder then
        holder = new("Frame", {
            Name = "toasts",
            Size = UDim2.fromOffset(280, 220),
            Position = UDim2.new(0.5, -140, 0, 14),
            BackgroundTransparency = 1,
            ZIndex = 90,
        }, gui)
        new("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }, holder)
    end

    local toast = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = P.cardAlt,
        BorderSizePixel = 0,
        ZIndex = 90,
    }, holder)
    corner(toast, 9)
    new("Frame", {
        Size = UDim2.new(0, 3, 1, -12),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundColor3 = P.accent,
        BorderSizePixel = 0,
    }, toast)
    local txt = label(toast, tostring(text), UDim2.new(1, -24, 1, 0), P.text, Enum.Font.GothamMedium, 13)
    txt.Position = UDim2.fromOffset(16, 0)

    task.delay(2.6, function()
        if toast.Parent then toast:Destroy() end
    end)
end

--=====================================================================
--  ÉTAT
--=====================================================================
local Flags = {
    speed = 16, jump = 50,
    fly = false, flySpeed = 60,
    infJump = false, noclip = false, antifall = false, autoJump = false,
    spin = false, spinSpeed = 180,
    esp = false, espNames = false,
    fullbright = false, nofog = false,
    follow = false,
    chatSpam = false, chatMsg = "lolpanel on top",
    emoteSpam = false, animSpeed = 1, antiafk = true, freezeAnim = false,
    neon = false, selfHL = false,
}

local Char, HRP, Hum
local lastSafe
local transpStore, matStore = {}, {}

local function getChar() return LP.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end
local function playerOptions()
    local opts = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then table.insert(opts, { label = p.Name, value = p }) end
    end
    return opts
end

--=====================================================================
--  MOUVEMENT
--=====================================================================
local flyState = { on = false, vert = 0 }
local flyBV, flyBG, flyConn

local function stopFly()
    flyState.on = false
    flyState.vert = 0
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    local hum = getHum()
    if hum then pcall(function() hum.PlatformStand = false end) end
end

local function startFly()
    local char, hum = getChar(), getHum()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hrp and hum) then notify("Personnage indisponible") return end

    hum.PlatformStand = true

    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "lolpanel_fly_bv"
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.P = 1250
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = hrp

    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "lolpanel_fly_bg"
    flyBG.MaxTorque = Vector3.new(4e4, 4e4, 4e4)
    flyBG.P = 3000
    flyBG.D = 100
    flyBG.CFrame = hrp.CFrame - hrp.CFrame.Position
    flyBG.Parent = hrp

    local controls
    pcall(function()
        local pm = require(LP.PlayerScripts:WaitForChild("PlayerModule", 5))
        controls = pm:GetControls()
    end)

    flyConn = RunService.Heartbeat:Connect(function()
        if not flyState.on then return end
        if not hrp.Parent then stopFly() return end
        local cam = workspace.CurrentCamera
        if not cam then return end

        local mv = Vector3.zero
        if controls then
            local ok, v = pcall(function() return controls:GetMoveVector() end)
            if ok and typeof(v) == "Vector3" then mv = v end
        elseif hum then
            mv = hum.MoveDirection
        end

        local dir = Vector3.zero
        if mv.Magnitude > 0.05 then
            local camCF = cam.CFrame
            dir = camCF.RightVector * mv.X + camCF.LookVector * -mv.Z
            if dir.Magnitude > 0 then dir = dir.Unit end
        end

        flyBV.Velocity = dir * Flags.flySpeed + Vector3.new(0, flyState.vert * Flags.flySpeed, 0)
        flyBG.CFrame = cam.CFrame - cam.CFrame.Position
    end)

    flyState.on = true
end

local function tpTo(pos)
    local hrp = getHRP()
    if hrp and pos then hrp.CFrame = CFrame.new(pos) end
end

local function tpToPlayer(plr)
    local hrp = getHRP()
    local target = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if hrp and target then hrp.CFrame = target.CFrame * CFrame.new(0, 3, 3) end
end

local function tpSpawn()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") then
            tpTo(obj.Position + Vector3.new(0, 4, 0))
            return
        end
    end
    notify("Aucun spawn trouvé")
end

local function tpRandom()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(list, p)
        end
    end
    if #list == 0 then notify("Aucun joueur") return end
    tpToPlayer(list[math.random(1, #list)])
end

local function makePlatform()
    local hrp = getHRP()
    if not hrp then return end
    local part = Instance.new("Part")
    part.Size = Vector3.new(7, 1, 7)
    part.Position = hrp.Position - Vector3.new(0, 3.6, 0)
    part.Anchored = true
    part.CanCollide = true
    part.Material = Enum.Material.Neon
    part.Color = P.accent
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = workspace
    task.delay(6, function() if part and part.Parent then part:Destroy() end end)
end

local function resetChar()
    local hum = getHum()
    if hum then hum.Health = 0 end
end

RunService.Heartbeat:Connect(function(dt)
    local char = getChar()
    if not char or not char.Parent then return end
    local hrp, hum = getHRP(), getHum()
    if not (hrp and hum) then return end

    hum.WalkSpeed = Flags.speed
    hum.JumpPower = Flags.jump
    hum.UseJumpPower = true

    if Flags.noclip then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
        end
    end

    if Flags.spin then
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(Flags.spinSpeed) * dt, 0)
    end

    if hum.FloorMaterial ~= Enum.Material.Air then lastSafe = hrp.CFrame end
    if Flags.antifall and lastSafe and hrp.Position.Y < workspace.FallenPartsDestroyHeight + 25 then
        hrp.CFrame = lastSafe + Vector3.new(0, 3, 0)
    end
end)

UIS.JumpRequest:Connect(function()
    if Flags.infJump then
        local hum = getHum()
        if hum and hum:GetState() ~= Enum.HumanoidStateType.Dead then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(0.35)
        if Flags.autoJump then
            local hum = getHum()
            if hum and hum:GetState() ~= Enum.HumanoidStateType.Dead then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
end)

--=====================================================================
--  ANIMATIONS
--=====================================================================
local EMOTE_IDS = {
    wave = 507770239, point = 507770453, dance = 507771019,
    dance2 = 507776043, dance3 = 507777826, laugh = 507770818, cheer = 507770677,
}

local function playCustom(idText)
    local id = tostring(idText or ""):gsub("%D", "")
    if id == "" then notify("ID vide") return end
    local hum = getHum()
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. id
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if ok and track then
        pcall(function() track:Play() end)
        notify("Animation lancée")
    else
        notify("Animation invalide")
    end
end

local function playEmote(name)
    local hum = getHum()
    if not hum or hum.Health <= 0 then return end
    local ok = pcall(function() hum:PlayEmote(name) end)
    if ok then return end
    if EMOTE_IDS[name] then playCustom(tostring(EMOTE_IDS[name])) end
end

local function stopEmotes()
    local hum = getHum()
    if not hum then return end
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        pcall(function() track:Stop() end)
    end
end

task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        local hum = getHum()
        if hum then
            if Flags.animSpeed ~= 1 then
                for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                    pcall(function() track:AdjustSpeed(Flags.animSpeed) end)
                end
            end
            if Flags.freezeAnim then
                for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                    pcall(function() track:Stop() end)
                end
            end
        end
    end
end)

task.spawn(function()
    local cycle = { "wave", "point", "dance", "dance2", "dance3", "laugh", "cheer" }
    local i = 1
    while gui.Parent do
        task.wait(1.6)
        if Flags.emoteSpam then
            playEmote(cycle[i])
            i = (i % #cycle) + 1
        end
    end
end)

--=====================================================================
--  CHAT
--=====================================================================
local function sendChat(msg)
    msg = tostring(msg or "")
    if msg == "" then return false end
    local sent = false

    pcall(function()
        local channels = TCS:FindFirstChild("TextChannels")
        if channels then
            local channel = channels:FindFirstChild("RBXGeneral")
                or channels:FindFirstChildWhichIsA("TextChannel")
            if channel then
                channel:SendAsync(msg)
                sent = true
            end
        end
    end)

    if not sent then
        pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local ev = rs:FindFirstChild("DefaultChatSystemChatEvents")
            local req = ev and ev:FindFirstChild("SayMessageRequest")
            if req then
                req:FireServer(msg, "All")
                sent = true
            end
        end)
    end
    return sent
end

task.spawn(function()
    while gui.Parent do
        task.wait(1.25)
        if Flags.chatSpam then sendChat(Flags.chatMsg) end
    end
end)

--=====================================================================
--  ESP
--=====================================================================
local function refreshESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            if char then
                local hl = char:FindFirstChild("lolpanel_hl")
                if Flags.esp then
                    if not hl then
                        hl = Instance.new("Highlight")
                        hl.Name = "lolpanel_hl"
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillColor = P.accent
                        hl.FillTransparency = 0.7
                        hl.OutlineColor = P.accent
                        hl.OutlineTransparency = 0
                        hl.Parent = char
                    end
                elseif hl then
                    hl:Destroy()
                end

                local hrp = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChildOfClass("Humanoid")
                local tag = hrp and hrp:FindFirstChild("lolpanel_tag")

                if Flags.espNames and hrp and hum then
                    if not tag then
                        tag = Instance.new("BillboardGui")
                        tag.Name = "lolpanel_tag"
                        tag.Size = UDim2.fromOffset(220, 30)
                        tag.StudsOffset = Vector3.new(0, 2.6, 0)
                        tag.AlwaysOnTop = true
                        tag.MaxDistance = 600
                        tag.Adornee = hrp
                        tag.Parent = hrp
                        local txt = Instance.new("TextLabel")
                        txt.Name = "text"
                        txt.Size = UDim2.fromScale(1, 1)
                        txt.BackgroundTransparency = 1
                        txt.Font = Enum.Font.GothamBold
                        txt.TextSize = 13
                        txt.TextColor3 = P.accent
                        txt.TextStrokeTransparency = 0.2
                        txt.Parent = tag
                    end
                    local txt = tag:FindFirstChild("text")
                    if txt then
                        txt.Text = string.format("%s  %d/%d", plr.Name,
                            math.floor(hum.Health + 0.5), math.floor(hum.MaxHealth + 0.5))
                    end
                elseif tag then
                    tag:Destroy()
                end
            end
        end
    end
end

task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        if Flags.esp or Flags.espNames then refreshESP() end
    end
end)

--=====================================================================
--  LUMIÈRE
--=====================================================================
local fbSaved, fogSaved

local function applyFullbright(on)
    if on then
        if not fbSaved then
            fbSaved = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                GlobalShadows = Lighting.GlobalShadows,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                ExposureCompensation = Lighting.ExposureCompensation,
            }
        end
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(190, 190, 190)
        Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
        Lighting.ExposureCompensation = 0
    elseif fbSaved then
        for k, v in next, fbSaved do
            pcall(function() Lighting[k] = v end)
        end
        fbSaved = nil
    end
end

local function applyNoFog(on)
    if on then
        if not fogSaved then
            fogSaved = { FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart }
        end
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
    elseif fogSaved then
        Lighting.FogEnd = fogSaved.FogEnd
        Lighting.FogStart = fogSaved.FogStart
        fogSaved = nil
    end
end

--=====================================================================
--  COSMÉTIQUES (local)
--=====================================================================
local function applyScale(v)
    local hum = getHum()
    if not hum then return end
    for _, name in ipairs({ "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }) do
        local obj = hum:FindFirstChild(name)
        if obj and obj:IsA("NumberValue") then obj.Value = v end
    end
end

local function applyNeon(on)
    local char = getChar()
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            if on then
                if matStore[d] == nil then matStore[d] = d.Material end
                d.Material = Enum.Material.Neon
            elseif matStore[d] ~= nil then
                d.Material = matStore[d]
            end
        end
    end
end

local function applyTransp(v)
    local char = getChar()
    if not char or not char.Parent then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            if transpStore[d] == nil then transpStore[d] = d.Transparency end
            d.Transparency = transpStore[d] + (1 - transpStore[d]) * v
        end
    end
end

local function setFace(idText)
    local id = tostring(idText or ""):gsub("%D", "")
    if id == "" then notify("ID visage vide") return end
    local char = getChar()
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    local decal = head:FindFirstChildOfClass("Decal")
    if not decal then
        decal = Instance.new("Decal")
        decal.Name = "face"
        decal.Parent = head
    end
    decal.Texture = "rbxassetid://" .. id
end

local function setClothing(class, idText)
    local id = tostring(idText or ""):gsub("%D", "")
    if id == "" then notify("ID vide") return end
    local char = getChar()
    if not char then return end
    local item = char:FindFirstChildOfClass(class)
    if not item then
        item = Instance.new(class)
        item.Parent = char
    end
    if class == "Shirt" then
        item.ShirtTemplate = "rbxassetid://" .. id
    else
        item.PantsTemplate = "rbxassetid://" .. id
    end
end

local function applySelfHL(on)
    local char = getChar()
    if not char then return end
    local hl = char:FindFirstChild("lolpanel_self")
    if on and not hl then
        hl = Instance.new("Highlight")
        hl.Name = "lolpanel_self"
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor = Color3.fromRGB(120, 200, 255)
        hl.FillTransparency = 0.75
        hl.OutlineColor = Color3.fromRGB(120, 200, 255)
        hl.Parent = char
    elseif not on and hl then
        hl:Destroy()
    end
end

local function removeAccessories()
    local char = getChar()
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Accoutrement") then d:Destroy() end
    end
    notify("Accessoires supprimés")
end

--=====================================================================
--  ANTI-AFK
--=====================================================================
LP.Idled:Connect(function()
    if not Flags.antiafk then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end)

--=====================================================================
--  OUTILS
--=====================================================================
local Config, ToggleRefs, SliderRefs = {}, {}, {}

local function revert(key)
    task.defer(function()
        local ref = ToggleRefs[key]
        if ref then ref(false) end
    end)
end

local function copyToClipboard(text)
    local ok = pcall(function() setclipboard(tostring(text)) end)
    notify(ok and "Copié" or "Clipboard indisponible")
end

local function httpGet(url)
    local body
    pcall(function()
        local req = nil
        if syn and syn.request then req = syn.request
        elseif http and http.request then req = http.request
        elseif http_request then req = http_request
        elseif request then req = request
        end
        if req then
            local res = req({ Url = url, Method = "GET" })
            body = res and res.Body
        end
    end)
    return body
end

local function serverHop()
    task.spawn(function()
        local body = httpGet("https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?limit=100")
        if not body then notify("HTTP absent chez cet exécuteur") return end
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok or not data or not data.data then notify("Aucun serveur trouvé") return end
        for _, srv in ipairs(data.data) do
            if srv.id and srv.id ~= game.JobId and srv.playing and srv.maxPlayers
                and srv.playing < srv.maxPlayers then
                pcall(function() TeleportSvc:TeleportToPlaceInstance(game.PlaceId, srv.id, LP) end)
                return
            end
        end
        notify("Aucun serveur libre")
    end)
end

local function saveConfig()
    local ok, err = pcall(function()
        if type(writefile) ~= "function" then error("writefile absent") end
        writefile("lolpanel.json", HttpService:JSONEncode(Config))
    end)
    notify(ok and "Config sauvegardée" or ("Échec: " .. tostring(err)))
end

local function loadConfig()
    local ok, err = pcall(function()
        if type(readfile) ~= "function" then error("readfile absent") end
        if type(isfile) == "function" and not isfile("lolpanel.json") then error("fichier absent") end
        local data = HttpService:JSONDecode(readfile("lolpanel.json"))
        for key, value in next, data do
            if ToggleRefs[key] then ToggleRefs[key](value)
            elseif SliderRefs[key] then SliderRefs[key](value) end
        end
    end)
    notify(ok and "Config chargée" or ("Échec: " .. tostring(err)))
end

--=====================================================================
--  ANTI-BAN
--=====================================================================
local AntiBan = {
    safe = false, kickShield = false, remoteGuard = false, jitter = false,
    blocked = 0, scripts = 0, hook = false,
}

local SUSPECT = {
    "anticheat", "anti-cheat", "anti_cheat", "cheatdetect", "exploitdetect",
    "detect", "report", "flag", "watchdog", "guardian", "exploit",
}

local function installAntiBanHook()
    if AntiBan.hook then return true end
    if type(getrawmetatable) ~= "function" or type(getnamecallmethod) ~= "function" then
        return false
    end
    local mt = getrawmetatable(game)
    if not mt then return false end

    local ok = pcall(function()
        local old = mt.__namecall
        if type(old) ~= "function" then error("__namecall absent") end
        if type(setreadonly) == "function" then setreadonly(mt, false) end

        local function hook(self, ...)
            local method = getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer") and AntiBan.remoteGuard then
                local name = tostring(self.Name):lower()
                for _, pat in ipairs(SUSPECT) do
                    if name:find(pat, 1, true) then
                        AntiBan.blocked = AntiBan.blocked + 1
                        return nil
                    end
                end
            end
            if method == "Kick" and AntiBan.kickShield and self == LP then
                AntiBan.blocked = AntiBan.blocked + 1
                return nil
            end
            return old(self, ...)
        end

        if type(newcclosure) == "function" then
            local okc, wrapped = pcall(newcclosure, hook)
            mt.__namecall = okc and wrapped or hook
        else
            mt.__namecall = hook
        end

        if type(setreadonly) == "function" then setreadonly(mt, true) end
    end)

    if ok then AntiBan.hook = true end
    return ok
end

local KILL_PATTERNS = {
    "anticheat", "anti-cheat", "anti_cheat", "cheatdetect", "exploitdetect",
    "detector", "watchdog", "guardian",
}

local function killDetectionScripts()
    local n = 0
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("LocalScript") and obj.Enabled then
            local nm = obj.Name:lower()
            for _, pat in ipairs(KILL_PATTERNS) do
                if nm:find(pat, 1, true) then
                    pcall(function()
                        obj.Enabled = false
                        obj:Destroy()
                    end)
                    n = n + 1
                    break
                end
            end
        end
    end
    AntiBan.scripts = AntiBan.scripts + n
    notify(n .. " script(s) de détection désactivé(s)")
end

--=====================================================================
--  MOTEUR DANGER (répliqué — physique du personnage)
--=====================================================================
local Danger = {
    orbit = false, trap = false, promptSpam = false, fuzzer = false,
    fuzzerRate = 20, orbitTarget = nil,
}
local spinAV, spinConn, spinMode = nil, nil, nil

local function stopSpin()
    spinMode = nil
    if spinConn then spinConn:Disconnect(); spinConn = nil end
    if spinAV then spinAV:Destroy(); spinAV = nil end
    local hum = getHum()
    if hum then pcall(function() hum.PlatformStand = false end) end
end

local function startSpin(mode)
    if AntiBan.safe then notify("Safe mode — fling bloqué") return end
    stopSpin()
    local hrp, hum = getHRP(), getHum()
    if not (hrp and hum) then notify("Personnage indisponible") return end

    spinMode = mode
    hum.PlatformStand = true
    if mode == "ragdoll" then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    end

    spinAV = Instance.new("BodyAngularVelocity")
    spinAV.AngularVelocity = Vector3.new(0, 5e5, 0)
    spinAV.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    spinAV.P = 1e6
    spinAV.Parent = hrp

    spinConn = RunService.Heartbeat:Connect(function()
        if not spinMode then return end
        if not hrp.Parent then stopSpin() return end
        if AntiBan.jitter and spinAV then
            spinAV.AngularVelocity = Vector3.new(0, 5e5 * (0.9 + math.random() * 0.2), 0)
        end
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(200000), 0)
    end)
end

local function flingNearest()
    if AntiBan.safe then notify("Safe mode — fling bloqué") return end
    local hrp = getHRP()
    local best, dist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local t = p.Character:FindFirstChild("HumanoidRootPart")
            if t and hrp then
                local d = (t.Position - hrp.Position).Magnitude
                if d < dist then dist, best = d, p end
            end
        end
    end
    if not best then notify("Aucun joueur") return end
    tpToPlayer(best)
    startSpin("fling")
    if ToggleRefs.flingAura then ToggleRefs.flingAura(true) end
    task.delay(2.5, function()
        if spinMode == "fling" then stopSpin() end
        if ToggleRefs.flingAura then ToggleRefs.flingAura(false) end
    end)
end

task.spawn(function()
    while gui.Parent do
        task.wait(0.06)
        if AntiBan.safe then
            Danger.orbit = false
            Danger.trap = false
        end
        local hrp = getHRP()
        local target = Danger.orbitTarget
        local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if hrp and thrp then
            if Danger.orbit then
                local a = os.clock() * 5
                hrp.CFrame = thrp.CFrame * CFrame.new(math.cos(a) * 8, 3, math.sin(a) * 8)
            elseif Danger.trap then
                hrp.CFrame = thrp.CFrame
            end
        end
    end
end)

local promptCache, promptCacheAt = {}, 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.8)
        if Danger.promptSpam and not AntiBan.safe then
            if os.clock() - promptCacheAt > 5 then
                promptCache = {}
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then table.insert(promptCache, d) end
                end
                promptCacheAt = os.clock()
            end
            local hrp = getHRP()
            if hrp then
                for _, d in ipairs(promptCache) do
                    local parent = d.Parent
                    if parent and parent:IsA("BasePart")
                        and (parent.Position - hrp.Position).Magnitude < 40 then
                        pcall(function() d:InputHoldBegin() end)
                        task.delay(0.05, function()
                            pcall(function() d:InputHoldEnd() end)
                        end)
                    end
                end
            end
        end
    end
end)

local remotes, remotesAt = {}, 0
local PAYLOADS = { 0, 1, -1, 1e6, -1e6, true, false, "", "lolpanel", {} }

local function refreshRemotes()
    remotes = {}
    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("ReplicatedFirst"),
        workspace,
    }
    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent")
                or obj:IsA("RemoteFunction") then
                table.insert(remotes, obj)
            end
        end
    end
    remotesAt = os.clock()
end

task.spawn(function()
    while gui.Parent do
        local rate = math.clamp(Danger.fuzzerRate, 1, 200)
        task.wait(1 / rate)
        if Danger.fuzzer and not AntiBan.safe then
            if os.clock() - remotesAt > 10 then refreshRemotes() end
            if #remotes > 0 then
                local remote = remotes[math.random(1, #remotes)]
                local payload = PAYLOADS[math.random(1, #PAYLOADS)]
                if remote:IsA("RemoteFunction") then
                    task.spawn(function()
                        pcall(function() remote:InvokeServer(payload) end)
                    end)
                else
                    pcall(function() remote:FireServer(payload) end)
                end
            end
        end
    end
end)

--=====================================================================
--  LIAISON PERSONNAGE
--=====================================================================
local function bindCharacter(char)
    Char = char
    HRP, Hum = nil, nil
    transpStore, matStore = {}, {}
    lastSafe = nil
    pcall(function()
        HRP = char:WaitForChild("HumanoidRootPart", 10)
        Hum = char:WaitForChild("Humanoid", 10)
    end)
    if Flags.selfHL then applySelfHL(true) end
    if Flags.neon then applyNeon(true) end
    if Flags.fly then
        task.delay(0.8, function() if Flags.fly then startFly() end end)
    end
end

LP.CharacterAdded:Connect(function(c) task.spawn(bindCharacter, c) end)
if LP.Character then task.spawn(bindCharacter, LP.Character) end

--=====================================================================
--  DRAG
--=====================================================================
local function makeDraggable(handle, target, onMoved)
    local dragging = false
    local startPos, startOffset

    handle.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            startPos = input.Position
            startOffset = target.Position
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - startPos
        target.Position = UDim2.new(
            startOffset.X.Scale, startOffset.X.Offset + delta.X,
            startOffset.Y.Scale, startOffset.Y.Offset + delta.Y
        )
        if onMoved then onMoved() end
    end)

    UIS.InputEnded:Connect(function(input)
        if isPress(input) then dragging = false end
    end)
end

--=====================================================================
--  PANEL
--=====================================================================
local userMoved = false
local panel = new("Frame", {
    Name = "panel",
    Size = UDim2.fromOffset(430, 620),
    Position = UDim2.fromOffset(40, 80),
    BackgroundColor3 = P.panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 10,
}, gui)
corner(panel, 16)
stroke(panel, P.stroke, 1)

local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 56),
    BackgroundColor3 = P.bg,
    BorderSizePixel = 0,
    ZIndex = 11,
}, panel)
new("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = P.accent,
    BackgroundTransparency = 0.6,
    BorderSizePixel = 0,
    ZIndex = 11,
}, header)

local logo = new("Frame", {
    Size = UDim2.fromOffset(32, 32),
    Position = UDim2.fromOffset(12, 12),
    BackgroundColor3 = P.accent,
    BorderSizePixel = 0,
    ZIndex = 12,
}, header)
corner(logo, 9)
label(logo, "L", UDim2.fromScale(1, 1), P.bg, Enum.Font.GothamBlack, 18, Enum.TextXAlignment.Center)

local title = label(header, "lolpanel", UDim2.new(1, -80, 0, 22), P.text, Enum.Font.GothamBlack, 17)
title.Position = UDim2.fromOffset(54, 8)
local subtitle = label(header, "mobile mod menu · v1.2 · 80+ mods", UDim2.new(1, -80, 0, 16), P.muted, Enum.Font.GothamMedium, 11)
subtitle.Position = UDim2.fromOffset(54, 30)

local minBtn = new("TextButton", {
    Size = UDim2.fromOffset(32, 32),
    Position = UDim2.new(1, -44, 0, 12),
    BackgroundColor3 = P.cardAlt,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 12,
}, header)
corner(minBtn, 8)
label(minBtn, "—", UDim2.fromScale(1, 1), P.text, Enum.Font.GothamBold, 16, Enum.TextXAlignment.Center)

local dragZone = new("Frame", {
    Size = UDim2.new(1, -60, 1, 0),
    BackgroundTransparency = 1,
    ZIndex = 12,
}, header)
makeDraggable(dragZone, panel, function() userMoved = true end)

local tabBar = new("ScrollingFrame", {
    Size = UDim2.new(1, -20, 0, 34),
    Position = UDim2.fromOffset(10, 63),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    ScrollingDirection = Enum.ScrollingDirection.X,
    AutomaticCanvasSize = Enum.AutomaticSize.X,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ZIndex = 11,
}, panel)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Center,
}, tabBar)

local contentHost = new("Frame", {
    Size = UDim2.new(1, -8, 1, -126),
    Position = UDim2.fromOffset(8, 104),
    BackgroundTransparency = 1,
    ZIndex = 11,
}, panel)

local footer = new("Frame", {
    Size = UDim2.new(1, -24, 0, 18),
    Position = UDim2.new(0, 12, 1, -24),
    BackgroundTransparency = 1,
    ZIndex = 11,
}, panel)

local fpsLbl = label(footer, "FPS --", UDim2.new(0, 80, 1, 0), P.muted, Enum.Font.GothamMedium, 11)
local pingLbl = label(footer, "-- ms", UDim2.new(0, 80, 1, 0), P.muted, Enum.Font.GothamMedium, 11, Enum.TextXAlignment.Center)
pingLbl.Position = UDim2.new(0.5, -40, 0, 0)
local stampLbl = label(footer, "ofx", UDim2.new(0, 60, 1, 0), P.accentDim, Enum.Font.GothamBlack, 11, Enum.TextXAlignment.Right)
stampLbl.Position = UDim2.new(1, -60, 0, 0)

--=====================================================================
--  TABS
--=====================================================================
local pages, pills = {}, {}
local tabCount = 0

local function showTab(name)
    for tabName, page in next, pages do page.Visible = (tabName == name) end
    for tabName, pill in next, pills do
        local active = (tabName == name)
        pill.BackgroundColor3 = active and P.accent or P.card
        pill.TextColor3 = active and P.bg or P.muted
    end
end

local function addTab(name)
    tabCount = tabCount + 1
    local pill = new("TextButton", {
        Size = UDim2.fromOffset(0, 30),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = P.card,
        Text = name,
        TextColor3 = P.muted,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        LayoutOrder = tabCount,
        ZIndex = 12,
    }, tabBar)
    corner(pill, 15)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)

    local page = new("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = P.accentDim,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
        ZIndex = 12,
    }, contentHost)
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, page)
    new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 16) }, page)

    pages[name] = page
    pills[name] = pill
    pill.Activated:Connect(function() showTab(name) end)
    if tabCount == 1 then showTab(name) end
    return page
end

--=====================================================================
--  ROW BUILDERS
--=====================================================================
local orders = setmetatable({}, { __mode = "k" })
local function nextOrder(page)
    orders[page] = (orders[page] or 0) + 1
    return orders[page]
end

local function makeToggle(page, key, text, default, cb)
    local on = default and true or false
    Config[key] = on

    local row = new("Frame", {
        Size = UDim2.new(1, -14, 0, 46),
        BackgroundColor3 = P.card,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(row, 10)
    stroke(row)

    local lbl = label(row, text, UDim2.new(1, -90, 1, 0), P.text, Enum.Font.GothamMedium, 14)
    lbl.Position = UDim2.fromOffset(12, 0)

    local track = new("Frame", {
        Size = UDim2.fromOffset(44, 24),
        Position = UDim2.new(1, -54, 0.5, -12),
        BackgroundColor3 = on and P.accent or P.cardAlt,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, row)
    corner(track, 12)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(18, 18),
        Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
        BackgroundColor3 = on and P.bg or P.muted,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, track)
    corner(knob, 9)

    local function paint(state)
        TweenService:Create(track, TweenInfo.new(0.15), {
            BackgroundColor3 = state and P.accent or P.cardAlt,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
            BackgroundColor3 = state and P.bg or P.muted,
        }):Play()
    end

    local function setState(state, fire)
        on = state and true or false
        Config[key] = on
        paint(on)
        if fire ~= false and cb then cb(on) end
    end

    row.InputBegan:Connect(function(input)
        if isPress(input) then setState(not on, true) end
    end)

    ToggleRefs[key] = function(v) setState(v, true) end
    if cb then cb(on) end
    return row
end

local dragState = nil

UIS.InputChanged:Connect(function(input)
    if not dragState then return end
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local pct = (input.Position.X - dragState.startX) / dragState.width
    local value = dragState.startValue + pct * (dragState.max - dragState.min)
    dragState.apply(value)
end)

UIS.InputEnded:Connect(function(input)
    if isPress(input) then dragState = nil end
end)

local function makeSlider(page, key, text, min, max, default, step, suffix, cb)
    Config[key] = default
    local value = default

    local row = new("Frame", {
        Size = UDim2.new(1, -14, 0, 62),
        BackgroundColor3 = P.card,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(row, 10)
    stroke(row)

    local lbl = label(row, text, UDim2.new(1, -100, 0, 26), P.text, Enum.Font.GothamMedium, 14)
    lbl.Position = UDim2.fromOffset(12, 6)
    local valLbl = label(row, "", UDim2.new(0, 76, 0, 26), P.accent, Enum.Font.GothamBold, 13, Enum.TextXAlignment.Right)
    valLbl.Position = UDim2.new(1, -88, 0, 6)

    local track = new("Frame", {
        Size = UDim2.new(1, -24, 0, 8),
        Position = UDim2.fromOffset(12, 42),
        BackgroundColor3 = P.cardAlt,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, row)
    corner(track, 4)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = P.accent,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, track)
    corner(fill, 4)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(18, 18),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = P.text,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, track)
    corner(knob, 9)

    local function paint()
        local pct = math.clamp((value - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        valLbl.Text = tostring(math.floor(value + 0.5)) .. (suffix or "")
    end

    local function apply(v, fire)
        v = math.clamp(v, min, max)
        if step and step > 0 then v = math.floor(v / step + 0.5) * step end
        value = v
        Config[key] = v
        paint()
        if fire ~= false and cb then cb(v) end
    end

    track.InputBegan:Connect(function(input)
        if isPress(input) then
            dragState = {
                startX = input.Position.X,
                startValue = value,
                width = math.max(track.AbsoluteSize.X, 1),
                min = min,
                max = max,
                apply = apply,
            }
        end
    end)

    SliderRefs[key] = function(v) apply(v, true) end
    apply(default, true)
    return row
end

local function makeButton(page, text, cb, danger)
    local btn = new("TextButton", {
        Size = UDim2.new(1, -14, 0, 44),
        BackgroundColor3 = danger and Color3.fromRGB(42, 20, 24) or P.cardAlt,
        AutoButtonColor = false,
        Text = "",
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(btn, 10)
    stroke(btn, danger and Color3.fromRGB(90, 34, 40) or P.stroke)

    local lbl = label(btn, text, UDim2.new(1, -24, 1, 0), danger and P.danger or P.text, Enum.Font.GothamMedium, 14)
    lbl.Position = UDim2.fromOffset(12, 0)

    btn.Activated:Connect(function() if cb then cb() end end)
    return btn
end

local function makeHold(page, text, onDown, onUp)
    local btn = new("TextButton", {
        Size = UDim2.new(1, -14, 0, 44),
        BackgroundColor3 = P.card,
        AutoButtonColor = false,
        Text = "",
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(btn, 10)
    stroke(btn)

    local lbl = label(btn, text, UDim2.new(1, -24, 1, 0), P.accent, Enum.Font.GothamBold, 14)
    lbl.Position = UDim2.fromOffset(12, 0)

    btn.InputBegan:Connect(function(input) if isPress(input) then onDown() end end)
    btn.InputEnded:Connect(function(input) if isPress(input) then onUp() end end)
    UIS.InputEnded:Connect(function(input) if isPress(input) then onUp() end end)
    return btn
end

local function makeTextbox(page, placeholder, defaultText, onCommit)
    local box = new("TextBox", {
        Size = UDim2.new(1, -14, 0, 44),
        BackgroundColor3 = P.card,
        Text = defaultText or "",
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = P.muted,
        TextColor3 = P.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(box, 10)
    stroke(box)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
    box.FocusLost:Connect(function(enter) if onCommit then onCommit(box.Text, enter) end end)
    return box
end

local function makeSelector(page, text, optionsFn)
    local index = 1
    local row = new("Frame", {
        Size = UDim2.new(1, -14, 0, 46),
        BackgroundColor3 = P.card,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(page),
    }, page)
    corner(row, 10)
    stroke(row)

    local lbl = label(row, text, UDim2.new(1, -160, 1, 0), P.text, Enum.Font.GothamMedium, 14)
    lbl.Position = UDim2.fromOffset(12, 0)
    local valueLbl = label(row, "—", UDim2.fromOffset(56, 46), P.accent, Enum.Font.GothamBold, 12, Enum.TextXAlignment.Center)
    valueLbl.Position = UDim2.new(1, -96, 0, 0)

    local prev = new("TextButton", {
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.new(1, -124, 0.5, -14),
        BackgroundColor3 = P.cardAlt,
        Text = "‹",
        TextColor3 = P.text,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, row)
    corner(prev, 8)

    local nextBtn = new("TextButton", {
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.new(1, -34, 0.5, -14),
        BackgroundColor3 = P.cardAlt,
        Text = "›",
        TextColor3 = P.text,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, row)
    corner(nextBtn, 8)

    local function current()
        local opts = optionsFn()
        if #opts == 0 then return nil end
        index = math.clamp(index, 1, #opts)
        return opts[index]
    end

    local function refreshLabel()
        local sel = current()
        valueLbl.Text = sel and sel.label or "—"
    end

    prev.Activated:Connect(function()
        local opts = optionsFn()
        if #opts == 0 then return end
        index = ((index - 2) % #opts) + 1
        refreshLabel()
    end)

    nextBtn.Activated:Connect(function()
        local opts = optionsFn()
        if #opts == 0 then return end
        index = (index % #opts) + 1
        refreshLabel()
    end)

    refreshLabel()
    return { current = current, refresh = refreshLabel }
end

--=====================================================================
--  PAGES
--=====================================================================
local floating
local function showPanel()
    panel.Visible = true
    if floating then floating.Visible = false end
end
local function hidePanel()
    panel.Visible = false
    if floating then floating.Visible = true end
end
minBtn.Activated:Connect(hidePanel)

-- MOVE ---------------------------------------------------------------
local pageMove = addTab("MOVE")
makeSlider(pageMove, "speed", "Vitesse", 16, 500, 16, 1, "", function(v) Flags.speed = v end)
makeSlider(pageMove, "jump", "Saut", 50, 500, 50, 1, "", function(v) Flags.jump = v end)
makeToggle(pageMove, "fly", "Vol (joystick)", false, function(v)
    Flags.fly = v
    if v then startFly() else stopFly() end
end)
makeSlider(pageMove, "flySpeed", "Vitesse vol", 10, 300, 60, 5, "", function(v) Flags.flySpeed = v end)
makeHold(pageMove, "Monter", function() flyState.vert = 1 end, function() flyState.vert = 0 end)
makeHold(pageMove, "Descendre", function() flyState.vert = -1 end, function() flyState.vert = 0 end)
makeToggle(pageMove, "infJump", "Saut infini", false, function(v) Flags.infJump = v end)
makeToggle(pageMove, "autoJump", "Saut automatique", false, function(v) Flags.autoJump = v end)
makeToggle(pageMove, "noclip", "Noclip", false, function(v) Flags.noclip = v end)
makeToggle(pageMove, "antifall", "Anti-chute", false, function(v) Flags.antifall = v end)
makeToggle(pageMove, "spin", "Rotation", false, function(v) Flags.spin = v end)
makeSlider(pageMove, "spinSpeed", "Vitesse rotation", 30, 720, 180, 10, "°", function(v) Flags.spinSpeed = v end)
makeButton(pageMove, "Téléport au spawn", tpSpawn)
makeButton(pageMove, "Téléport joueur aléatoire", tpRandom)
makeButton(pageMove, "Plateforme sous les pieds", makePlatform)
makeSlider(pageMove, "gravity", "Gravité", 0, 300,
    math.clamp(math.floor(workspace.Gravity), 0, 300), 1, "",
    function(v) workspace.Gravity = v end)
makeButton(pageMove, "Réinitialiser le personnage", resetChar, true)

-- ANIM ---------------------------------------------------------------
local pageAnim = addTab("ANIM")
makeButton(pageAnim, "Salut", function() playEmote("wave") end)
makeButton(pageAnim, "Pointer", function() playEmote("point") end)
makeButton(pageAnim, "Danse", function() playEmote("dance") end)
makeButton(pageAnim, "Danse 2", function() playEmote("dance2") end)
makeButton(pageAnim, "Danse 3", function() playEmote("dance3") end)
makeButton(pageAnim, "Rire", function() playEmote("laugh") end)
makeButton(pageAnim, "Acclamation", function() playEmote("cheer") end)
makeButton(pageAnim, "Arrêter l'animation", stopEmotes)
makeSlider(pageAnim, "animSpeed", "Vitesse animation", 0.2, 3, 1, 0.1, "x", function(v) Flags.animSpeed = v end)
local customBox = makeTextbox(pageAnim, "ID d'animation (ex: 507771019)", "", nil)
makeButton(pageAnim, "Jouer l'ID", function() playCustom(customBox.Text) end)
makeToggle(pageAnim, "emoteSpam", "Spam d'emotes", false, function(v) Flags.emoteSpam = v end)

-- SOCIAL -------------------------------------------------------------
local pageSocial = addTab("SOCIAL")
local chatBox = makeTextbox(pageSocial, "Message de chat", "lolpanel on top", function(text, enter)
    Flags.chatMsg = text
    if enter then sendChat(text) end
end)
makeButton(pageSocial, "Envoyer le message", function()
    Flags.chatMsg = chatBox.Text
    if not sendChat(chatBox.Text) then notify("Chat bloqué par le jeu") end
end)
makeToggle(pageSocial, "chatSpam", "Spam chat (~1 msg/s)", false, function(v) Flags.chatSpam = v end)
makeButton(pageSocial, "Prédéfini : lolpanel", function() sendChat("lolpanel on top") end)
makeButton(pageSocial, "Prédéfini : gg", function() sendChat("gg") end)
makeButton(pageSocial, "Prédéfini : ez", function() sendChat("ez") end)
makeToggle(pageSocial, "follow", "Suivre un joueur aléatoire", false, function(v) Flags.follow = v end)
local playerSelector = makeSelector(pageSocial, "Joueur", playerOptions)
makeButton(pageSocial, "Téléporter vers le joueur", function()
    local sel = playerSelector.current()
    if sel then tpToPlayer(sel.value) else notify("Aucun joueur") end
end)
makeButton(pageSocial, "Copier la liste des joueurs", function()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do table.insert(names, p.Name) end
    copyToClipboard(table.concat(names, "\n"))
end)
makeButton(pageSocial, "Copier le Job ID", function() copyToClipboard(game.JobId) end)
makeButton(pageSocial, "Rejoindre le serveur", function()
    pcall(function() TeleportSvc:Teleport(game.PlaceId, LP) end)
end)
makeButton(pageSocial, "Server hop", serverHop)

-- VISUEL -------------------------------------------------------------
local pageVis = addTab("VISUEL")
makeToggle(pageVis, "esp", "ESP joueurs", false, function(v)
    Flags.esp = v
    refreshESP()
end)
makeToggle(pageVis, "espNames", "Pseudo + vie", false, function(v)
    Flags.espNames = v
    refreshESP()
end)
makeToggle(pageVis, "fullbright", "Fullbright", false, applyFullbright)
makeToggle(pageVis, "nofog", "Sans brouillard", false, applyNoFog)

local cam0 = workspace.CurrentCamera
local fovDefault = cam0 and math.clamp(math.floor(cam0.FieldOfView), 40, 120) or 70
makeSlider(pageVis, "fov", "Champ de vision", 40, 120, fovDefault, 1, "°", function(v)
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = v end
end)

makeButton(pageVis, "Supprimer mes accessoires", removeAccessories)
makeToggle(pageVis, "selfHL", "Surbrillance perso", false, applySelfHL)
makeToggle(pageVis, "freezeAnim", "Figer les animations", false, function(v) Flags.freezeAnim = v end)
makeToggle(pageVis, "antiafk", "Anti-AFK", true, function(v) Flags.antiafk = v end)

-- PERSO --------------------------------------------------------------
local pagePerso = addTab("PERSO")
makeSlider(pagePerso, "scale", "Taille (R15)", 0.5, 2, 1, 0.05, "x", applyScale)
makeToggle(pagePerso, "neon", "Matériau néon", false, function(v)
    Flags.neon = v
    applyNeon(v)
end)
makeSlider(pagePerso, "transp", "Transparence", 0, 0.9, 0, 0.05, "", applyTransp)
local faceBox = makeTextbox(pagePerso, "ID visage", "", nil)
makeButton(pagePerso, "Appliquer le visage", function() setFace(faceBox.Text) end)
local shirtBox = makeTextbox(pagePerso, "ID chemise", "", nil)
makeButton(pagePerso, "Appliquer la chemise", function() setClothing("Shirt", shirtBox.Text) end)
local pantsBox = makeTextbox(pagePerso, "ID pantalon", "", nil)
makeButton(pagePerso, "Appliquer le pantalon", function() setClothing("Pants", pantsBox.Text) end)

-- DANGER -------------------------------------------------------------
local pageDanger = addTab("DANGER")
makeToggle(pageDanger, "flingAura", "Fling Aura (contact)", false, function(v)
    if v then
        if AntiBan.safe then notify("Safe mode — bloqué"); revert("flingAura"); return end
        startSpin("fling")
    elseif spinMode == "fling" then
        stopSpin()
    end
end)
makeButton(pageDanger, "Fling le joueur le plus proche", flingNearest, true)
makeToggle(pageDanger, "spinFling", "Spin Fling (rotation max)", false, function(v)
    if v then
        if AntiBan.safe then notify("Safe mode — bloqué"); revert("spinFling"); return end
        startSpin("spin")
    elseif spinMode == "spin" then
        stopSpin()
    end
end)
makeToggle(pageDanger, "ragdollFling", "Ragdoll Fling", false, function(v)
    if v then
        if AntiBan.safe then notify("Safe mode — bloqué"); revert("ragdollFling"); return end
        startSpin("ragdoll")
    elseif spinMode == "ragdoll" then
        stopSpin()
    end
end)
makeToggle(pageDanger, "orbit", "Orbiter autour de la cible", false, function(v)
    if v and AntiBan.safe then notify("Safe mode — bloqué"); revert("orbit"); return end
    Danger.orbit = v
end)
local orbitSelector
makeButton(pageDanger, "Définir la cible d'orbite", function()
    local sel = orbitSelector and orbitSelector.current()
    Danger.orbitTarget = sel and sel.value or nil
    notify(sel and ("Cible: " .. sel.label) or "Aucune cible")
end)
orbitSelector = makeSelector(pageDanger, "Cible", playerOptions)
makeToggle(pageDanger, "trap", "Téléport collé sur la cible", false, function(v)
    if v and AntiBan.safe then notify("Safe mode — bloqué"); revert("trap"); return end
    Danger.trap = v
end)
makeToggle(pageDanger, "promptSpam", "Spam ProximityPrompt (40 studs)", false, function(v)
    if v and AntiBan.safe then notify("Safe mode — bloqué"); revert("promptSpam"); return end
    Danger.promptSpam = v
end)
makeToggle(pageDanger, "fuzzer", "Remote Fuzzer (peut crasher ton client)", false, function(v)
    if v and AntiBan.safe then notify("Safe mode — bloqué"); revert("fuzzer"); return end
    Danger.fuzzer = v
end)
makeSlider(pageDanger, "fuzzerRate", "Fuzzer / seconde", 1, 200, 20, 1, "/s", function(v)
    Danger.fuzzerRate = v
end)
makeSlider(pageDanger, "simRadius", "Rayon de simulation", 50, 5000, 100, 50, "", function(v)
    pcall(function() setsimulationradius(v, v) end)
    pcall(function() sethiddenproperty(LP, "SimulationRadius", v) end)
    pcall(function() sethiddenproperty(LP, "MaxSimulationRadius", v) end)
end)
makeButton(pageDanger, "Vitesse extrême (1000)", function()
    if SliderRefs.speed then SliderRefs.speed(1000) end
    notify("Vitesse 1000")
end, true)
makeButton(pageDanger, "Saut extrême (1000)", function()
    if SliderRefs.jump then SliderRefs.jump(1000) end
    notify("Saut 1000")
end, true)
makeButton(pageDanger, "Panic — tout couper", function()
    Danger.orbit, Danger.trap, Danger.promptSpam, Danger.fuzzer = false, false, false, false
    stopSpin()
    for _, k in ipairs({ "flingAura", "spinFling", "ragdollFling", "orbit", "trap", "promptSpam", "fuzzer" }) do
        if ToggleRefs[k] then task.defer(function() ToggleRefs[k](false) end) end
    end
    Flags.noclip = false
    Flags.spin = false
    if ToggleRefs.noclip then task.defer(function() ToggleRefs.noclip(false) end) end
    if ToggleRefs.spin then task.defer(function() ToggleRefs.spin(false) end) end
    if SliderRefs.speed then task.defer(function() SliderRefs.speed(16) end) end
    if SliderRefs.jump then task.defer(function() SliderRefs.jump(50) end) end
    AntiBan.safe = true
    if ToggleRefs.safeMode then task.defer(function() ToggleRefs.safeMode(true) end) end
    notify("Panic — tout coupé, safe mode ON")
end, true)

-- SHIELD -------------------------------------------------------------
local pageShield = addTab("SHIELD")
makeToggle(pageShield, "abHook", "Installer le hook anti-ban", false, function(v)
    if v then
        if not installAntiBanHook() then
            notify("Hook indisponible chez cet exécuteur")
            revert("abHook")
        else
            notify("Hook namecall installé")
        end
    end
end)
makeToggle(pageShield, "kickShield", "Bouclier Kick (local)", false, function(v)
    AntiBan.kickShield = v
end)
makeToggle(pageShield, "remoteGuard", "Remote Guard (bloque les reports)", false, function(v)
    AntiBan.remoteGuard = v
end)
makeButton(pageShield, "Tuer les scripts de détection", killDetectionScripts)
makeToggle(pageShield, "safeMode", "Safe mode (caps + danger off)", false, function(v)
    AntiBan.safe = v
    if v then
        if SliderRefs.speed then
            task.defer(function() SliderRefs.speed(math.min(Config.speed or 60, 60)) end)
        end
        if SliderRefs.jump then
            task.defer(function() SliderRefs.jump(math.min(Config.jump or 120, 120)) end)
        end
        Danger.orbit, Danger.trap, Danger.promptSpam, Danger.fuzzer = false, false, false, false
        stopSpin()
        for _, k in ipairs({ "flingAura", "spinFling", "ragdollFling", "orbit", "trap", "promptSpam", "fuzzer" }) do
            if ToggleRefs[k] then task.defer(function() ToggleRefs[k](false) end) end
        end
        notify("Safe mode ON")
    else
        notify("Safe mode OFF")
    end
end)
makeToggle(pageShield, "jitter", "Jitter (variation aléatoire)", false, function(v)
    AntiBan.jitter = v
end)
makeButton(pageShield, "Couper le hook (redémarrer le jeu)", function()
    notify("Le hook ne se retire pas proprement — relance le jeu")
end)

local statusRow = new("Frame", {
    Size = UDim2.new(1, -14, 0, 58),
    BackgroundColor3 = P.card,
    BorderSizePixel = 0,
    LayoutOrder = nextOrder(pageShield),
}, pageShield)
corner(statusRow, 10)
stroke(statusRow)
local statusLbl = label(statusRow, "…", UDim2.new(1, -20, 1, 0), P.muted, Enum.Font.GothamMedium, 11)
statusLbl.Position = UDim2.fromOffset(10, 0)

-- OUTILS -------------------------------------------------------------
local pageTools = addTab("OUTILS")
makeButton(pageTools, "Cacher l'interface", hidePanel)
makeButton(pageTools, "Sauvegarder la config", saveConfig)
makeButton(pageTools, "Charger la config", loadConfig)
makeButton(pageTools, "Fermer lolpanel", function()
    if getgenv then getgenv().lolpanel_loaded = false end
    gui:Destroy()
end, true)

--=====================================================================
--  FLOTTANT + LAYOUT
--=====================================================================
floating = new("TextButton", {
    Size = UDim2.fromOffset(56, 56),
    Position = UDim2.new(1, -72, 1, -150),
    BackgroundColor3 = P.accent,
    Text = "L",
    TextColor3 = P.bg,
    Font = Enum.Font.GothamBlack,
    TextSize = 22,
    AutoButtonColor = false,
    Visible = false,
    BorderSizePixel = 0,
    ZIndex = 60,
}, gui)
corner(floating, 28)
stroke(floating, P.accentDim, 2)
floating.Activated:Connect(showPanel)
makeDraggable(floating, floating, function() end)

local function relayout()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(720, 1280)
    local w = math.clamp(math.floor(vp.X * 0.94), 300, 460)
    local h = math.clamp(math.floor(vp.Y * 0.78), 420, 680)
    panel.Size = UDim2.fromOffset(w, h)
    if not userMoved then
        panel.Position = UDim2.fromOffset(
            math.floor((vp.X - w) / 2),
            math.floor((vp.Y - h) / 2)
        )
    end
end

relayout()
task.spawn(function()
    task.wait(0.25)
    relayout()
end)

pcall(function()
    local cam = workspace.CurrentCamera
    if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout) end
end)

--=====================================================================
--  LOOPS FINAUX
--=====================================================================
task.spawn(function()
    local frames, acc = 0, 0
    RunService.RenderStepped:Connect(function(dt)
        frames = frames + 1
        acc = acc + dt
        if acc >= 0.5 then
            fpsLbl.Text = "FPS " .. tostring(math.floor(frames / acc + 0.5))
            local ping = 0
            pcall(function() ping = math.floor(LP:GetNetworkPing() * 1000 + 0.5) end)
            pingLbl.Text = tostring(ping) .. " ms"
            frames, acc = 0, 0
        end
    end)
end)

task.spawn(function()
    while gui.Parent do
        task.wait(0.25)
        if Flags.follow then
            local candidates = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    table.insert(candidates, p)
                end
            end
            if #candidates > 0 then
                local target = candidates[math.random(1, #candidates)]
                local hrp = getHRP()
                local thrp = target.Character:FindFirstChild("HumanoidRootPart")
                if hrp and thrp then hrp.CFrame = thrp.CFrame * CFrame.new(0, 3, 3) end
            end
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(1)
        statusLbl.Text = string.format(
            "Hook: %s   Bloqués: %d   Scripts: %d   Safe: %s",
            AntiBan.hook and "ON" or "OFF",
            AntiBan.blocked,
            AntiBan.scripts,
            AntiBan.safe and "ON" or "OFF"
        )
    end
end)

print("[lolpanel] v1.2 chargé — 80+ mods · parent UI: "
    .. tostring(gui.Parent and gui.Parent:GetFullName() or "?"))
