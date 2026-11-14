--[[ RC1 CAR+OREHUB v3.0 — Refinery Caves 1 (8726743209)
     • Слайдеры: плавный drag (ПК/тач), мгновенная реакция, применение на лету
     • Дизайн: тёмная тема, секции, акцент, ховеры
     • Сворачивание в компактную иконку (не исчезает, а именно сворачивается)
     • НАСТРОЙКИ И СОСТОЯНИЯ СОХРАНЯЮТСЯ (getgenv) — не сбрасываются
     • Ноуклип / Без урона (игрок+машина) / Флай / Буст машины / ТП руды
]]

local Players = game:GetService("Players")
local RunS    = game:GetService("RunService")
local TweenS  = game:GetService("TweenService")
local UIS     = game:GetService("UserInputService")
local LP      = Players.LocalPlayer

local GENV = (getgenv and getgenv()) or _G
GENV.RC1H = GENV.RC1H or {}
local ST = GENV.RC1H

--=== ХРАНИЛИЩЕ НАСТРОЕК (живёт между запусками) ===========
ST.cfg = ST.cfg or {}
ST.ui  = ST.ui  or {}
ST.state = ST.state or {}   -- состояния тумблеров переживают перезапуск скрипта

local CFG = ST.cfg
-- дефолты (применяются только если значения ещё не сохранены)
local function def(k, v) if CFG[k] == nil then CFG[k] = v end end
def("torqueMult",   3.0)
def("maxSpeedMult", 2.5)
def("stiffSusp",    true)
def("grabRadius",   60)
def("tpSpeed",      0.08)
def("perTick",      12)
def("flySpeed",     50)
def("godPlayer",    false)
def("godVehicle",   false)
def("flyKeys",      true)   -- Space/Ctrl управление флайем

local UI = ST.ui
if UI.locked == nil then UI.locked = false end
if UI.snap   == nil then UI.snap   = false end
if UI.scale  == nil then UI.scale  = 1.0 end

local guiRef = nil

--=== ТЕМА =================================================
local T = {
    bg      = Color3.fromRGB(16, 17, 22),
    bg2     = Color3.fromRGB(24, 26, 33),
    bg3     = Color3.fromRGB(32, 35, 44),
    accent  = Color3.fromRGB(255, 170, 60),
    accent2 = Color3.fromRGB(120, 170, 255),
    ok      = Color3.fromRGB(60, 130, 80),
    text    = Color3.fromRGB(235, 235, 235),
    dim     = Color3.fromRGB(150, 155, 165),
}

--=== ХЕЛПЕР ===============================================
local function new(c, p, parent)
    local o = Instance.new(c)
    if p then for k, v in pairs(p) do o[k] = v end end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function stroke(o, col, th)
    new("UIStroke", { Color = col or T.bg3, Thickness = th or 1 }, o)
end

--=== ЛОГ ==================================================
local logScroll, logLines, dirty = nil, {}, false

local LCOL = {
    sys  = T.accent2, info = T.dim, ok  = Color3.fromRGB(120, 230, 140),
    warn = Color3.fromRGB(255, 200, 90), err = Color3.fromRGB(255, 120, 120),
    point = Color3.fromRGB(200, 130, 255),
}

local function log(m, cat)
    m = tostring(m)
    print("[HUB]", m)
    logLines[#logLines + 1] = { t = m, c = LCOL[cat or "info"] }
    while #logLines > 40 do table.remove(logLines, 1) end
    dirty = true
end

RunS.Heartbeat:Connect(function()
    if not dirty or not logScroll then return end
    dirty = false
    logScroll:ClearAllChildren()
    local y = 4
    local n = #logLines
    for idx = math.max(1, n - 39), n do
        local e = logLines[idx]
        new("TextLabel", {
            Size = UDim2.new(1, -10, 0, 14), Position = UDim2.fromOffset(5, y),
            BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.Code, TextSize = 10, TextColor3 = e.c,
            Text = e.t, TextTruncate = Enum.TextTruncate.AtEnd,
        }, logScroll)
        y += 14
    end
    logScroll.CanvasSize = UDim2.fromOffset(0, y + 4)
    logScroll.CanvasPosition = Vector2.new(0, math.max(0, y - 140))
end)

--=== МАШИНА ===============================================
local saved = {}
local function saveOrig(o, k, v)
    saved[o] = saved[o] or {}
    if saved[o][k] == nil then saved[o][k] = v end
end

local function myVehicle()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        return hum.SeatPart:FindFirstAncestorOfClass("Model")
    end
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestD, n = nil, math.huge, 0
    for _, o in ipairs(workspace:GetDescendants()) do
        n += 1
        if n > 4000 then break end
        if o:IsA("VehicleSeat") then
            local m = o:FindFirstAncestorOfClass("Model")
            if m then
                local rp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
                if rp then
                    local d = (rp.Position - hrp.Position).Magnitude
                    if d < bestD and d <= 200 then best, bestD = m, d end
                end
            end
        end
    end
    return best
end

local function boostVehicle(v)
    if not v then return log("Машина не найдена — сядь в неё", "warn") end
    local changed = 0
    for _, w in ipairs(v:GetDescendants()) do
        if w:IsA("VehicleSeat") then
            if typeof(w.Torque) == "number" then
                saveOrig(w, "torque", w.Torque)
                w.Torque = saved[w].torque * CFG.torqueMult
                changed += 1
            end
            if typeof(w.MaxSpeed) == "number" and w.MaxSpeed > 0 then
                saveOrig(w, "maxSpeed", w.MaxSpeed)
                w.MaxSpeed = saved[w].maxSpeed * CFG.maxSpeedMult
                changed += 1
            end
        end
        if w:IsA("HingeConstraint") or w:IsA("CylindricalConstraint") then
            if typeof(w.MotorMaxTorque) == "number" then
                saveOrig(w, "torque", w.MotorMaxTorque)
                w.MotorMaxTorque = saved[w].torque * CFG.torqueMult
                changed += 1
            end
            if typeof(w.AngularVelocity) == "number" then
                saveOrig(w, "angular", w.AngularVelocity)
                w.AngularVelocity = saved[w].angular * CFG.maxSpeedMult
                changed += 1
            end
        end
        if CFG.stiffSusp and (w:IsA("SpringConstraint") or w:IsA("SuspensionConstraint")) then
            if typeof(w.Stiffness) == "number" then
                saveOrig(w, "stiff", w.Stiffness)
                w.Stiffness = saved[w].stiff * 1.5
                changed += 1
            end
            if typeof(w.Damping) == "number" then
                saveOrig(w, "damp", w.Damping)
                w.Damping = saved[w].damp * 1.5
                changed += 1
            end
        end
    end
    log(("Машина «%s»: x%.1f торк / x%.1f скорость (%d)"):format(
        v.Name, CFG.torqueMult, CFG.maxSpeedMult, changed),
        changed > 0 and "ok" or "warn")
end

local function restoreVehicle()
    local n = 0
    for obj, props in pairs(saved) do
        if obj and obj.Parent then
            if props.torque then
                if obj:IsA("VehicleSeat") then obj.Torque = props.torque
                else obj.MotorMaxTorque = props.torque end
                n += 1
            end
            if props.maxSpeed then obj.MaxSpeed = props.maxSpeed end
            if props.angular then obj.AngularVelocity = props.angular end
            if props.stiff then obj.Stiffness = props.stiff end
            if props.damp then obj.Damping = props.damp end
        end
    end
    saved = {}
    log("Сток восстановлен: " .. n, "ok")
end

-- перебуст на лету при смене слайдера
local reboostScheduled = false
local function scheduleReboost()
    if reboostScheduled or not next(saved) then return end
    reboostScheduled = true
    task.delay(0.25, function()
        reboostScheduled = false
        if not next(saved) then return end
        for obj, props in pairs(saved) do
            if obj and obj.Parent then
                if props.torque then
                    if obj:IsA("VehicleSeat") then obj.Torque = props.torque
                    else obj.MotorMaxTorque = props.torque end
                end
                if props.maxSpeed then obj.MaxSpeed = props.maxSpeed end
                if props.angular then obj.AngularVelocity = props.angular end
                if props.stiff then obj.Stiffness = props.stiff end
                if props.damp then obj.Damping = props.damp end
            end
        end
        saved = {}
        boostVehicle(myVehicle())
    end)
end

--=== ТОЧКА СБОРА ==========================================
local hubPoint = ST.hubPoint   -- CFrame сохраняется между запусками
local tpOn, marker, accum = false, nil, 0

local function placeMarker()
    if marker then marker:Destroy() marker = nil end
    if not hubPoint then return end
    marker = new("Part", {
        Size = Vector3.new(2, 0.4, 2), Anchored = true, CanCollide = false,
        Transparency = 0.45, Color = Color3.fromRGB(200, 130, 255),
        Material = Enum.Material.Neon, CFrame = hubPoint,
    })
    marker.Parent = workspace
end
if hubPoint then task.defer(placeMarker) end

local function charPos()
    local c = LP.Character
    local h = c and c:FindFirstChild("HumanoidRootPart")
    return h and h.Position or nil
end

local function isExcluded(name)
    for _, s in ipairs({ "HumanoidRootPart", "Baseplate", "Terrain" }) do
        if name == s then return true end
    end
    return false
end

local function tpRoot(o)
    local root, cur = o, o
    while cur and cur ~= workspace do
        if cur:IsA("Model") then root = cur end
        cur = cur.Parent
    end
    return root
end

local function isPhysical(target)
    local parts = target:IsA("Model") and target:GetDescendants() or { target }
    local any = false
    for _, p in ipairs(parts) do
        if p:IsA("BasePart") then
            any = true
            if p.Anchored then return false end
        end
    end
    return any
end

local function tpObject(root, slot)
    local drop = hubPoint.Position + Vector3.new(
        math.random(-3, 3), 3 + slot * 0.8, math.random(-3, 3))
    local cf = CFrame.new(drop)
    if root:IsA("Model") then
        root:PivotTo(cf)
        for _, p in ipairs(root:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    else
        root.CFrame = cf
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

local grabConn = nil

local function grabTick(dt)
    if not (tpOn and hubPoint) then return end
    accum += dt
    if accum < CFG.tpSpeed then return end
    accum = 0

    local pos = charPos()
    if not pos then return end

    local slot, done = 0, {}
    local myChar = LP.Character

    for _, o in ipairs(workspace:GetPartBoundsInRadius(pos, CFG.grabRadius, nil)) do
        if slot >= CFG.perTick then break end
        if o:IsA("BasePart") and not o.Anchored
            and not o:IsDescendantOf(myChar) and not done[o]
            and not isExcluded(o.Name) then
            local mdl = o:FindFirstAncestorOfClass("Model")
            if mdl and mdl:FindFirstChildOfClass("Humanoid") then
                done[o] = true
                continue
            end
            local root = tpRoot(o)
            if not root or done[root] or root:IsDescendantOf(myChar) then
                done[o] = true
                continue
            end
            if isPhysical(root) then
                tpObject(root, slot)
                done[root] = true
                if root:IsA("Model") then
                    for _, p in ipairs(root:GetDescendants()) do done[p] = true end
                end
                slot += 1
            else
                done[o] = true
            end
        end
    end
end

local function startGrab()
    if grabConn then return end
    grabConn = RunS.Heartbeat:Connect(grabTick)
    log("ТП-цикл запущен", "ok")
end
local function stopGrab()
    if grabConn then grabConn:Disconnect() grabConn = nil end
end

--=== НОКЛИП ===============================================
local noclipOn = ST.state.noclip or false

local function stripCollisions()
    local c = LP.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
    end
end

RunS.Stepped:Connect(function()
    if noclipOn then stripCollisions() end
end)

LP.CharacterAdded:Connect(function(ch)
    ch:WaitForChild("Humanoid", 5)
    for _ = 1, 6 do
        task.wait(0.1)
        if noclipOn then stripCollisions() end
    end
end)

--=== БЕЗ УРОНА (игрок) ====================================
local godOn = ST.state.god or false

local function applyGod(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum.BreakJointsOnDeath = false
        if godOn then hum.Health = hum.MaxHealth end
    end)
    hum:GetPropertyChangedSignal("Health"):Connect(function()
        if godOn and hum.Health < hum.MaxHealth then
            hum.Health = hum.MaxHealth
        end
    end)
end

RunS.Heartbeat:Connect(function()
    if not godOn then return end
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health < hum.MaxHealth then
        hum.Health = hum.MaxHealth
    end
end)

LP.CharacterAdded:Connect(function(ch)
    task.wait(0.2)
    if godOn then applyGod(ch) end
end)

--=== БЕЗ УРОНА (машина) ===================================
local godVehConn = nil

local function startGodVeh()
    if godVehConn then return end
    godVehConn = RunS.Heartbeat:Connect(function()
        if not CFG.godVehicle then return end
        local v = myVehicle()
        if v then
            for _, d in ipairs(v:GetDescendants()) do
                if d:IsA("Humanoid") then
                    pcall(function() d.Health = d.MaxHealth end)
                end
            end
        end
    end)
end
local function stopGodVeh()
    if godVehConn then godVehConn:Disconnect() godVehConn = nil end
end

--=== ФЛАЙ =================================================
local flying = false
local flyConn, flyBodyVel, flyBodyGyro = nil, nil, nil
local touchDown, kbDown, jumpHeld = false, false, false
local downBtn, upBtn = nil, nil

local function makeFlyBtns()
    if downBtn then downBtn:Destroy() downBtn = nil end
    if upBtn then upBtn:Destroy() upBtn = nil end
    local parent = guiRef or LP:WaitForChild("PlayerGui")

    upBtn = new("TextButton", {
        Size = UDim2.fromOffset(90, 60), Position = UDim2.new(0.5, -45, 1, -270),
        BackgroundColor3 = T.bg2, BackgroundTransparency = 0.2,
        Text = "▲", TextColor3 = T.accent,
        Font = Enum.Font.GothamBold, TextSize = 22,
        AutoButtonColor = false, ZIndex = 50,
    }, parent)
    corner(upBtn, 12)

    downBtn = new("TextButton", {
        Size = UDim2.fromOffset(90, 60), Position = UDim2.new(0.5, -45, 1, -200),
        BackgroundColor3 = T.bg2, BackgroundTransparency = 0.2,
        Text = "▼", TextColor3 = T.accent,
        Font = Enum.Font.GothamBold, TextSize = 22,
        AutoButtonColor = false, ZIndex = 50,
    }, parent)
    corner(downBtn, 12)

    upBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then jumpHeld = true end
    end)
    upBtn.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then jumpHeld = false end
    end)
    downBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then touchDown = true end
    end)
    downBtn.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch
            or i.UserInputType == Enum.UserInputType.MouseButton1 then touchDown = false end
    end)
end

local function killFlyBtns()
    touchDown, jumpHeld = false, false
    if downBtn then downBtn:Destroy() downBtn = nil end
    if upBtn then upBtn:Destroy() upBtn = nil end
end

local function startFly()
    local c = LP.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then
        log("Персонаж не найден — флай не включить", "err")
        return false
    end

    flyBodyVel = new("BodyVelocity", {
        MaxForce = Vector3.new(1e9, 1e9, 1e9), Velocity = Vector3.zero,
    }, hrp)
    flyBodyGyro = new("BodyGyro", {
        MaxTorque = Vector3.new(1e9, 1e9, 1e9), P = 1e4, CFrame = hrp.CFrame,
    }, hrp)

    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    end)

    makeFlyBtns()
    flying = true

    flyConn = RunS.RenderStepped:Connect(function()
        local ch = LP.Character
        local h = ch and ch:FindFirstChild("HumanoidRootPart")
        local hu = ch and ch:FindFirstChildOfClass("Humanoid")
        if not (h and hu and flyBodyVel and flyBodyVel.Parent) then return end

        local camera = workspace.CurrentCamera
        local dir = Vector3.zero

        local md = hu.MoveDirection
        if md.Magnitude > 0.05 then dir += md.Unit end

        local up = 0
        if CFG.flyKeys then
            if jumpHeld or UIS:IsKeyDown(Enum.KeyCode.Space) then up += 1 end
            if touchDown or kbDown or UIS:IsKeyDown(Enum.KeyCode.LeftControl) then up -= 1 end
        else
            if jumpHeld then up += 1 end
            if touchDown then up -= 1 end
        end
        if up ~= 0 then dir += Vector3.new(0, up, 0) end

        flyBodyVel.Velocity = (dir.Magnitude > 0)
            and dir.Unit * CFG.flySpeed or Vector3.zero

        if flyBodyGyro and flyBodyGyro.Parent and camera then
            flyBodyGyro.CFrame = CFrame.new(h.Position, h.Position + camera.CFrame.LookVector)
        end
    end)

    log("Флай ВКЛ, скорость " .. math.floor(CFG.flySpeed), "ok")
    return true
end

local function stopFly()
    flying = false
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBodyVel then flyBodyVel:Destroy() flyBodyVel = nil end
    if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
    local c = LP.Character
    local h = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if h then h.AssemblyLinearVelocity = Vector3.zero end
    if hum then
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        end)
    end
    killFlyBtns()
    log("Флай ВЫКЛ", "info")
end

UIS.InputBegan:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.LeftControl then kbDown = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.LeftControl then kbDown = false end
    if i.KeyCode == Enum.KeyCode.Space then jumpHeld = false end
end)

--=== GUI ==================================================
local cam = workspace.CurrentCamera
local vp  = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
local BASE_W, BASE_H = 340, 560

local pg  = LP:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("RC1_HUB")
if old then old:Destroy() end

local gui = new("ScreenGui", {
    Name = "RC1_HUB", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 9997,
}, pg)
guiRef = gui

local root = new("Frame", {
    Size = UDim2.fromOffset(BASE_W, BASE_H),
    Position = UDim2.fromOffset((UI.panel and UI.panel.X) or 8, (UI.panel and UI.panel.Y) or 60),
    BackgroundTransparency = 1, Visible = true,
}, gui)
local rootScale = new("UIScale", { Scale = UI.scale }, root)

-- ПАНЕЛЬ
local panel = new("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg,
    BorderSizePixel = 0, ClipsDescendants = true, Active = true,
}, root)
corner(panel, 14)
stroke(panel, T.bg3, 1)

-- верхняя полоса-акцент
new("Frame", {
    Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.accent,
    BorderSizePixel = 0, ZIndex = 6,
}, panel)

-- заголовок
new("TextLabel", {
    Size = UDim2.new(1, -140, 0, 36), Position = UDim2.fromOffset(14, 4),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 15,
    TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Left,
    Text = "RC1 HUB", ZIndex = 5,
}, panel)
new("TextLabel", {
    Size = UDim2.fromOffset(50, 36), Position = UDim2.new(1, -130, 0, 4),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
    TextColor3 = T.dim, Text = "v3.0", ZIndex = 5,
}, panel)

local dragHandle = new("TextButton", {
    Size = UDim2.new(1, -96, 0, 40), BackgroundTransparency = 1,
    Text = "", AutoButtonColor = false, Active = true, ZIndex = 5,
}, panel)

local dragging, dragStart, startPos = false, nil, nil
dragHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        if UI.locked then return end
        dragging = true
        dragStart = input.Position
        startPos = root.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        local newX = startPos.X.Offset + delta.X
        local newY = startPos.Y.Offset + delta.Y
        root.Position = UDim2.fromOffset(newX, newY)
        UI.panel = UI.panel or {}
        UI.panel.X, UI.panel.Y = newX, newY
    end
end)

-- свернуть: панель прячется, остаётся компактная таблетка
local pill = new("TextButton", {
    Size = UDim2.fromOffset(64, 30),
    Position = UDim2.fromOffset((UI.pill and UI.pill.X) or 8,
        (UI.pill and UI.pill.Y) or 8),
    BackgroundColor3 = T.bg2, Text = "▾ HUB",
    TextColor3 = T.accent, Font = Enum.Font.GothamBold, TextSize = 13,
    AutoButtonColor = false, Visible = false, ZIndex = 10,
}, gui)
corner(pill, 15)
stroke(pill, T.accent, 1)

local folded = false
local foldB = new("TextButton", {
    Size = UDim2.fromOffset(40, 32), Position = UDim2.new(1, -88, 0, 4),
    BackgroundColor3 = T.bg2, Text = "—",
    TextColor3 = T.text, Font = Enum.Font.GothamBold, TextSize = 14,
    AutoButtonColor = false, ZIndex = 5,
}, panel)
corner(foldB, 8)

local closeB = new("TextButton", {
    Size = UDim2.fromOffset(40, 32), Position = UDim2.new(1, -44, 0, 4),
    BackgroundColor3 = Color3.fromRGB(60, 28, 28), Text = "✕",
    TextColor3 = Color3.fromRGB(255, 120, 120),
    Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = false, ZIndex = 5,
}, panel)
corner(closeB, 8)

foldB.MouseButton1Click:Connect(function()
    folded = true
    TweenS:Create(panel, TweenInfo.new(0.18), {
        Size = UDim2.fromScale(1, 0), BackgroundTransparency = 1
    }):Play()
    task.delay(0.2, function()
        root.Visible = false
        pill.Visible = true
    end)
end)

pill.MouseButton1Click:Connect(function()
    pill.Visible = false
    panel.Size = UDim2.fromScale(1, 0)
    panel.BackgroundTransparency = 1
    root.Visible = true
    TweenS:Create(panel, TweenInfo.new(0.2), {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0
    }):Play()
end)

closeB.MouseButton1Click:Connect(function()
    gui.Enabled = false
    ST.ui.guiDisabled = true
end)

pill.MouseButton2Click:Connect(function()
    gui.Enabled = true
    ST.ui.guiDisabled = false
end)
if ST.ui.guiDisabled then gui.Enabled = false end

--=== КОНТЕНТ: скролл + секции =============================
local scroll = new("ScrollingFrame", {
    Size = UDim2.new(1, -12, 1, -56), Position = UDim2.fromOffset(6, 46),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0), ScrollBarThickness = 4,
    ScrollBarImageColor3 = T.accent, ZIndex = 3,
}, panel)
local listL = new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
local pad = new("UIPadding", { PaddingRight = UDim.new(0, 6) }, scroll)

local order = 0
local function nextOrder() order += 1 return order end

local function section(title)
    local f = new("Frame", {
        Size = UDim2.new(1, -6, 0, 22), BackgroundTransparency = 1,
        LayoutOrder = nextOrder(), ZIndex = 3,
    }, scroll)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.accent2,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "  " .. string.upper(title), ZIndex = 3,
    }, f)
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = T.bg3, BorderSizePixel = 0, ZIndex = 3,
    }, f)
end

local function btn(text, onClick)
    local b = new("TextButton", {
        Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = T.bg2,
        Text = "  " .. text, TextColor3 = T.text,
        Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false,
        LayoutOrder = nextOrder(), ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left,
    }, scroll)
    corner(b, 8)
    b.MouseEnter:Connect(function()
        TweenS:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = T.bg3 }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenS:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = T.bg2 }):Play()
    end)
    b.MouseButton1Click:Connect(onClick)
    return b
end

-- тумблер: цветной переключатель-капсула справа
local function toggle(text, key, get, set)
    local b = new("TextButton", {
        Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = T.bg2,
        Text = "", AutoButtonColor = false,
        LayoutOrder = nextOrder(), ZIndex = 3,
    }, scroll)
    corner(b, 8)

    new("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = text, ZIndex = 4,
    }, b)

    local knobBg = new("Frame", {
        Size = UDim2.fromOffset(40, 20), Position = UDim2.new(1, -50, 0.5, -10),
        BackgroundColor3 = T.bg3, ZIndex = 4, BorderSizePixel = 0,
    }, b)
    corner(knobBg, 10)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = T.dim, ZIndex = 5, BorderSizePixel = 0,
    }, knobBg)
    corner(knob, 8)

    local function refresh()
        local on = get()
        TweenS:Create(knobBg, TweenInfo.new(0.15),
            { BackgroundColor3 = on and T.ok or T.bg3 }):Play()
        TweenS:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
            BackgroundColor3 = on and T.text or T.dim,
        }):Play()
    end

    b.MouseEnter:Connect(function()
        TweenS:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = T.bg3 }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenS:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = T.bg2 }):Play()
    end)
    b.MouseButton1Click:Connect(function()
        set(not get())
        ST.state[key] = get()
        refresh()
        log(text .. (get() and " ВКЛ" or " ВЫКЛ"), "ok")
    end)
    refresh()
    return b
end

-- СЛАЙДЕР: плавный drag через глобальный InputChanged/Ended,
-- значение применяется сразу при движении, отпустить можно где угодно
local function slider(text, min, max, step, get, set, fmt)
    local container = new("Frame", {
        Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = T.bg2,
        LayoutOrder = nextOrder(), ZIndex = 3, BorderSizePixel = 0,
    }, scroll)
    corner(container, 8)

    local label = new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(10, 3),
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = T.text, Text = "", ZIndex = 4,
    }, container)

    local bar = new("TextButton", {
        Size = UDim2.new(1, -20, 0, 12), Position = UDim2.new(0, 10, 0, 28),
        BackgroundColor3 = T.bg3, Text = "", AutoButtonColor = false,
        ZIndex = 4, BorderSizePixel = 0,
    }, container)
    corner(bar, 6)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent,
        ZIndex = 5, BorderSizePixel = 0,
    }, bar)
    corner(fill, 6)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, -7, 0.5, -7),
        BackgroundColor3 = T.text, ZIndex = 6, BorderSizePixel = 0,
    }, bar)
    corner(knob, 7)

    local function fmtVal(v)
        if fmt then return fmt(v) end
        return string.format("%.1f", v)
    end

    local function refresh()
        local v = get()
        label.Text = ("%s   %s"):format(text, fmtVal(v))
        local a = math.clamp((v - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, -7, 0.5, -7)
    end

    local draggingS = false
    local function applyFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = min + rel * (max - min)
        if step then v = math.floor(v / step + 0.5) * step end
        v = math.clamp(v, min, max)
        set(v)
        refresh()
    end

    -- drag начинается на полосе ИЛИ на ползунке
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            draggingS = true
            applyFromX(i.Position.X)
        end
    end)
    -- завершение ЛОВИМ ГЛОБАЛЬНО: отпустил где угодно — слайдер отпустился
    UIS.InputEnded:Connect(function(i)
        if draggingS and (i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch) then
            draggingS = false
        end
    end)
    -- движение ЛОВИМ ГЛОБАЛЬНО: тянешь даже чуть мимо полосы — работает
    UIS.InputChanged:Connect(function(i)
        if draggingS and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            applyFromX(i.Position.X)
        end
    end)

    refresh()
    return container
end

--=== РАЗМЕТКА =============================================
section("машина")
btn("🚗  БУСТ МАШИНЫ", function() boostVehicle(myVehicle()) end)
btn("↩  СТОК МАШИНЫ", restoreVehicle)

section("фарм")
btn("📍  ТОЧКА = Я", function()
    local p = charPos()
    if p then
        hubPoint = CFrame.new(p)
        ST.hubPoint = hubPoint
        placeMarker()
        log("Точка установлена", "point")
    end
end)

section("передвижение и защита")
toggle("ТП руды", "tp", function() return tpOn end, function(v)
    tpOn = v
    if v then startGrab() else stopGrab() end
end)
toggle("Флай", "fly", function() return flying end, function(v)
    if v then
        if not startFly() then flying = false end
    else
        stopFly()
    end
end)
toggle("Ноуклип", "noclip", function() return noclipOn end,
    function(v) noclipOn = v end)
toggle("Без урона (игрок)", "god", function() return godOn end, function(v)
    godOn = v
    if v then applyGod(LP.Character) end
end)
toggle("Без урона (машина)", "godv", function() return CFG.godVehicle end, function(v)
    CFG.godVehicle = v
    if v then startGodVeh() else stopGodVeh() end
end)
toggle("Жёсткая подвеска", "stiff", function() return CFG.stiffSusp end, function(v)
    CFG.stiffSusp = v
    scheduleReboost()
end)

section("настройки")
slider("Торк машины", 0.5, 10, 0.5,
    function() return CFG.torqueMult end,
    function(v) CFG.torqueMult = v scheduleReboost() end)

slider("Скорость машины", 0.5, 10, 0.5,
    function() return CFG.maxSpeedMult end,
    function(v) CFG.maxSpeedMult = v scheduleReboost() end)

slider("Скорость флая", 10, 300, 5,
    function() return CFG.flySpeed end,
    function(v) CFG.flySpeed = v end,
    function(v) return tostring(math.floor(v)) end)

slider("Радиус захвата руды", 10, 200, 5,
    function() return CFG.grabRadius end,
    function(v) CFG.grabRadius = v end,
    function(v) return tostring(math.floor(v)) .. " st" end)

slider("Руды за тик", 1, 50, 1,
    function() return CFG.perTick end,
    function(v) CFG.perTick = math.floor(v) end,
    function(v) return tostring(math.floor(v)) end)

--=== ЛОГ ==================================================
local logFrame = new("Frame", {
    Size = UDim2.new(1, -12, 0, 104), Position = UDim2.new(1, -6, 1, -6),
    AnchorPoint = Vector2.new(1, 1), BackgroundColor3 = Color3.fromRGB(10, 11, 14),
    BorderSizePixel = 0, ZIndex = 3,
}, panel)
corner(logFrame, 8)
logScroll = new("ScrollingFrame", {
    Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = T.accent, ZIndex = 4,
}, logFrame)

task.defer(function()
    scroll.CanvasSize = UDim2.fromOffset(0, listL.AbsoluteContentSize.Y + 10)
end)

--=== ВОССТАНОВЛЕНИЕ СОСТОЯНИЙ =============================
-- тумблеры, сохранённые в прошлый запуск, включаем заново
task.defer(function()
    if ST.state.tp then
        tpOn = true startGrab()
        log("ТП руды восстановлен", "ok")
    end
    if ST.state.god then
        applyGod(LP.Character)
        log("Без урона восстановлен", "ok")
    end
    if ST.state.godv or CFG.godVehicle then
        startGodVeh()
    end
    if ST.state.noclip then
        log("Ноуклип активен", "ok")
    end
end)

log("RC1 HUB v3.0 загружен", "sys")
log("Настройки сохраняются между запусками", "ok")
