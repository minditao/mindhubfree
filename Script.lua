local NEXTUI_URL = "https://diser.me/nextui/source.lua"
local NEXTUI_LOCAL_FILE = "MINDHUB_NextUI.lua"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local Teams = game:GetService("Teams")

local LP = Players.LocalPlayer
local function getCamera() return Workspace.CurrentCamera end

local genv = getgenv and getgenv() or nil
if genv and genv.__MINDHUB_RUNNING then warn("[MINDHUB] Already running.") return end
if genv then genv.__MINDHUB_RUNNING = true end

local Unloaded = false
local UIReady = false
local Connections = {}
local PlayerConns = {}
local ESPData = {}
local OriginalCollision = {}
local OriginalLighting = nil
local OriginalFogEnd = nil
local OriginalAtmosphere = {}
local OrigWalk, OrigJump, OrigFOV
local FlyWanted = false
local CharToken = 0
local warned = {}

local Char, Hum, HRP
local FlyAtt, FlyLV, FlyAO
local FlyConnection, NoclipConnection, InfJumpConnection
local SpinConnection, SpeedConnection, VisualsConnection, AntiAFKConnection
local SpeedHum, SpeedOriginal
local AimCircle
local AimActive = false
local Window, watermark

local S = {
    WalkSpeed = 16, WalkSpeedSet = false,
    JumpPower = 50, JumpSet = false,
    SpeedHack = false, SpeedValue = 60,
    Fly = false, FlySpeed = 50,
    Noclip = false, InfJump = false,

    ESP = false, ESPTeamCheck = false, ESPMaxDist = 1500,
    ESPBox = true, ESPBoxColor = Color3.fromRGB(255, 255, 255), ESPBoxRainbow = false,
    ESPName = true, ESPNameColor = Color3.fromRGB(255, 255, 255), ESPNameRainbow = false, ESPNameSize = 13,
    ESPDistance = true, ESPHealth = true, ESPHealthColor = Color3.fromRGB(65, 230, 130), ESPHealthRainbow = false,
    ESPSkeleton = false, ESPSkeletonColor = Color3.fromRGB(255, 255, 255), ESPSkeletonRainbow = false,
    ESPThickness = 1.5, ESPBoxStyle = "Corner", ESPBoxFilled = false, ESPFillAlpha = 0.15,
    ESPOutline = true, ESPRoles = true, ESPRoleColors = true, ESPHPText = true,
    ESPHealthGradient = true, ESPTracers = false, ESPTracerOrigin = "Bottom",
    ESPTracerColor = Color3.fromRGB(255, 255, 255), ESPCornerLen = 0.3,
    ESPFont = "Plex", ESPHealthSide = "Left", ESPVisCheck = false,
    ESPVisibleColor = Color3.fromRGB(80, 255, 120), ESPHiddenColor = Color3.fromRGB(255, 80, 80),

    Aimbot = false, AimFOV = 120, AimSmooth = 0.2,
    AimMode = "Hold RMB", AimTeamCheck = true, AimWallCheck = true, AimShowFOV = false,
    AimFOVColor = Color3.fromRGB(255, 255, 255), AimPart = "Head", AimPriority = "Crosshair",
    AimPrediction = false, AimPredictionAmount = 0.12, AimSticky = true,
    AimMaxDist = 1500, AimIgnoreFF = true,

    SpinBot = false, SpinSpeed = 15,
    Fullbright = false, NoFog = false, CamFOV = 70, FOVSet = false,
    AntiAFK = false,
    Theme = "Onyx", AccentColor = Color3.fromRGB(170, 90, 255), AccentSet = false,
}

local function track(conn, bucket) if conn then table.insert(bucket or Connections, conn) end return conn end
local function disconnect(conn) if conn then pcall(function() conn:Disconnect() end) end end
local function safeDestroy(obj) if obj then pcall(function() obj:Destroy() end) end end
local function safeRemoveDrawing(obj) if obj then pcall(function() obj:Remove() end) end end
local function safeCall(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not warned[name] then
        warned[name] = true
        warn("[MINDHUB] " .. name .. " error: " .. tostring(err))
    end
end
local function rainbow() return Color3.fromHSV((os.clock() % 5) / 5, 1, 1) end

local function refreshCharacter()
    Char = LP.Character
    Hum = Char and Char:FindFirstChildOfClass("Humanoid")
    HRP = Char and Char:FindFirstChild("HumanoidRootPart")
    return Char, Hum, HRP
end
local function clearCharacter() Char, Hum, HRP = nil, nil, nil end
local function originPos()
    if HRP and HRP.Parent then return HRP.Position end
    local cam = getCamera()
    return cam and cam.CFrame.Position or nil
end
local function isValidPlayer(player)
    if not player or player == LP then return false end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return character ~= nil and humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end
local function sameTeam(player)
    return player.Team ~= nil and LP.Team ~= nil and player.Team == LP.Team
end

local function resetRunFlag() if genv then genv.__MINDHUB_RUNNING = nil end end
local ok, NextUI = pcall(function()
    local source
    if isfile and readfile then
        local has = false
        pcall(function() has = isfile(NEXTUI_LOCAL_FILE) end)
        if has then source = readfile(NEXTUI_LOCAL_FILE) end
    end
    if not source then source = game:HttpGet(NEXTUI_URL) end
    return loadstring(source)()
end)
if not ok or not NextUI then warn("[MINDHUB] NextUI failed to load: " .. tostring(NextUI)) resetRunFlag() return end
local function notify(title, message, kind) pcall(function() local method = NextUI[kind or "Info"] if method then method(NextUI, title, message) end end) end

local clearPlayerESP, createPlayerESP, clearESP, refreshESP, updateESP
local getRoleInfo = function() return nil, nil end

do
    local HEALTH_LOW = Color3.fromRGB(255, 70, 70)
    local HEALTH_HIGH = Color3.fromRGB(70, 235, 120)
    local BLACK = Color3.new(0, 0, 0)
    local GRAY = Color3.fromRGB(200, 200, 200)
    local FONT_IDS = { UI = 0, System = 1, Plex = 2, Monospace = 3 }

    local VisParams = RaycastParams.new()
    VisParams.FilterType = Enum.RaycastFilterType.Exclude
    VisParams.IgnoreWater = true

    local function isVisible(cam, targetPart, character)
        local filter = { cam }
        if LP.Character then table.insert(filter, LP.Character) end
        VisParams.FilterDescendantsInstances = filter
        local origin = cam.CFrame.Position
        local result = Workspace:Raycast(origin, targetPart.Position - origin, VisParams)
        return result == nil or result.Instance:IsDescendantOf(character)
    end

    local NullDrawing = setmetatable({ Remove = function() end }, { __newindex = function() end })

    local function newDrawing(kind, props)
        if not Drawing then return NullDrawing end
        local okNew, obj = pcall(Drawing.new, kind)
        if not okNew or not obj then return NullDrawing end
        obj.Visible = false
        for key, value in pairs(props or {}) do pcall(function() obj[key] = value end) end
        return obj
    end

    local function snap(value) return math.floor(value + 0.5) end

    local function setLine(line, from, to, color, thickness)
        line.From = from line.To = to line.Color = color line.Thickness = thickness line.Visible = true
    end

    function clearPlayerESP(player)
        local data = ESPData[player] if not data then return end
        safeDestroy(data.billboard)
        for _, drawing in ipairs(data.all) do safeRemoveDrawing(drawing) end
        ESPData[player] = nil
    end

    function clearESP() for player in pairs(ESPData) do clearPlayerESP(player) end end

    local function createFallbackBillboard(player, head, data)
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "MINDHUB_ESP" billboard.Adornee = head billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(220, 70) billboard.StudsOffset = Vector3.new(0, 3.2, 0)
        billboard.Enabled = false billboard.Parent = head
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1 label.Size = UDim2.fromScale(1, 1) label.Font = Enum.Font.GothamBold
        label.TextStrokeTransparency = 0.3 label.TextYAlignment = Enum.TextYAlignment.Bottom
        label.Text = player.Name label.Parent = billboard
        data.billboard = billboard data.label = label
    end

    function createPlayerESP(player)
        if Unloaded or not S.ESP or player == LP or ESPData[player] then return end
        local character = player.Character
        local head = character and character:FindFirstChild("Head")
        if not head then return end

        local data = { all = {} }
        if Drawing then
            local function mk(kind, props)
                local obj = newDrawing(kind, props)
                table.insert(data.all, obj)
                return obj
            end
            local textProps = { Center = true, Outline = true, OutlineColor = BLACK, Font = 2 }
            data.fill = mk("Square", { Filled = true })
            data.boxOutline = mk("Square", { Filled = false, Color = BLACK })
            data.box = mk("Square", { Filled = false })
            data.corners, data.cornersOutline = {}, {}
            for i = 1, 8 do
                data.cornersOutline[i] = mk("Line", { Color = BLACK })
                data.corners[i] = mk("Line", {})
            end
            data.hpOutline = mk("Square", { Filled = true, Color = BLACK })
            data.hpFill = mk("Square", { Filled = true })
            data.nameText = mk("Text", textProps)
            data.roleText = mk("Text", textProps)
            data.hpText = mk("Text", textProps)
            data.infoText = mk("Text", textProps)
            data.tracer = mk("Line", {})
        else
            createFallbackBillboard(player, head, data)
        end
        ESPData[player] = data
    end

    function refreshESP()
        clearESP()
        if not S.ESP then return end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP then createPlayerESP(player) end
        end
    end

    local function hideESPData(data)
        if data.billboard then data.billboard.Enabled = false end
        for _, drawing in ipairs(data.all) do drawing.Visible = false end
    end

    local function drawFallback(data, info)
        local lines = {}
        if info.roleText then table.insert(lines, info.roleText) end
        if S.ESPName then table.insert(lines, info.name) end
        if S.ESPHPText then table.insert(lines, info.hp .. " | HP") end
        if S.ESPDistance then table.insert(lines, info.distance .. " studs") end
        data.label.Text = table.concat(lines, "\n")
        data.label.TextColor3 = info.boxColor
        data.label.TextSize = S.ESPNameSize
        data.billboard.Enabled = #lines > 0
    end

    local function drawESP(data, viewport, info)
        local x, y, w, h = info.x, info.y, info.w, info.h
        local cx = x + w / 2
        local thickness = S.ESPThickness
        local outline = S.ESPOutline
        local boxColor = info.boxColor
        local cornerStyle = S.ESPBoxStyle == "Corner"

        local fontId = FONT_IDS[S.ESPFont] or 2
        if data.fontId ~= fontId then
            data.fontId = fontId
            data.nameText.Font = fontId
            data.roleText.Font = fontId
            data.hpText.Font = fontId
            data.infoText.Font = fontId
        end

        local fillOn = S.ESPBox and S.ESPBoxFilled
        data.fill.Visible = fillOn
        if fillOn then
            data.fill.Position = Vector2.new(x, y)
            data.fill.Size = Vector2.new(w, h)
            data.fill.Color = boxColor
            data.fill.Transparency = S.ESPFillAlpha
        end

        local fullOn = S.ESPBox and not cornerStyle
        data.boxOutline.Visible = fullOn and outline
        if fullOn and outline then
            data.boxOutline.Position = Vector2.new(x, y)
            data.boxOutline.Size = Vector2.new(w, h)
            data.boxOutline.Thickness = thickness + 2
        end
        data.box.Visible = fullOn
        if fullOn then
            data.box.Position = Vector2.new(x, y)
            data.box.Size = Vector2.new(w, h)
            data.box.Color = boxColor
            data.box.Thickness = thickness
        end

        if S.ESPBox and cornerStyle then
            local len = math.max(6, math.floor(math.min(w, h) * S.ESPCornerLen))
            local x2, y2 = x + w, y + h
            local pts = {
                { Vector2.new(x, y), Vector2.new(x + len, y) },
                { Vector2.new(x, y), Vector2.new(x, y + len) },
                { Vector2.new(x2, y), Vector2.new(x2 - len, y) },
                { Vector2.new(x2, y), Vector2.new(x2, y + len) },
                { Vector2.new(x, y2), Vector2.new(x + len, y2) },
                { Vector2.new(x, y2), Vector2.new(x, y2 - len) },
                { Vector2.new(x2, y2), Vector2.new(x2 - len, y2) },
                { Vector2.new(x2, y2), Vector2.new(x2, y2 - len) },
            }
            for i = 1, 8 do
                if outline then
                    setLine(data.cornersOutline[i], pts[i][1], pts[i][2], BLACK, thickness + 2)
                else
                    data.cornersOutline[i].Visible = false
                end
                setLine(data.corners[i], pts[i][1], pts[i][2], boxColor, thickness)
            end
        else
            for i = 1, 8 do
                data.cornersOutline[i].Visible = false
                data.corners[i].Visible = false
            end
        end

        data.hpOutline.Visible = S.ESPHealth
        data.hpFill.Visible = S.ESPHealth
        if S.ESPHealth then
            local barW = 3
            local barX = (S.ESPHealthSide == "Right") and (x + w + 4) or (x - 7)
            local fillH = math.max(1, snap(h * info.ratio))
            data.hpOutline.Position = Vector2.new(barX - 1, y - 1)
            data.hpOutline.Size = Vector2.new(barW + 2, h + 2)
            data.hpFill.Position = Vector2.new(barX, y + h - fillH)
            data.hpFill.Size = Vector2.new(barW, fillH)
            data.hpFill.Color = info.healthColor
        end

        local nameSize = S.ESPNameSize
        local cursor = y - 3
        data.nameText.Visible = S.ESPName
        if S.ESPName then
            cursor = cursor - nameSize - 1
            data.nameText.Text = info.name
            data.nameText.Size = nameSize
            data.nameText.Color = info.nameColor
            data.nameText.Outline = outline
            data.nameText.Position = Vector2.new(cx, cursor)
        end
        data.roleText.Visible = info.roleText ~= nil
        if info.roleText then
            local roleSize = math.max(nameSize - 2, 9)
            cursor = cursor - roleSize - 1
            data.roleText.Text = info.roleText
            data.roleText.Size = roleSize
            data.roleText.Color = info.roleColor or GRAY
            data.roleText.Outline = outline
            data.roleText.Position = Vector2.new(cx, cursor)
        end

        local small = math.max(nameSize - 1, 10)
        local below = y + h + 3
        data.hpText.Visible = S.ESPHPText
        if S.ESPHPText then
            data.hpText.Text = info.hp .. " | HP"
            data.hpText.Size = small
            data.hpText.Color = info.healthColor
            data.hpText.Outline = outline
            data.hpText.Position = Vector2.new(cx, below)
            below = below + small + 1
        end
        data.infoText.Visible = S.ESPDistance
        if S.ESPDistance then
            data.infoText.Text = info.distance .. " studs"
            data.infoText.Size = small
            data.infoText.Color = GRAY
            data.infoText.Outline = outline
            data.infoText.Position = Vector2.new(cx, below)
        end

        data.tracer.Visible = S.ESPTracers
        if S.ESPTracers then
            local startY = viewport.Y
            if S.ESPTracerOrigin == "Center" then startY = viewport.Y / 2
            elseif S.ESPTracerOrigin == "Top" then startY = 0 end
            setLine(data.tracer, Vector2.new(viewport.X / 2, startY), Vector2.new(cx, y + h), S.ESPTracerColor, 1)
        end
    end

    function updateESP()
        if not S.ESP then return end
        local cam = getCamera()
        local origin = originPos()
        if not cam or not origin then
            for _, data in pairs(ESPData) do hideESPData(data) end
            return
        end
        local viewport = cam.ViewportSize

        for player, data in pairs(ESPData) do
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")

            if not player.Parent or not humanoid or humanoid.Health <= 0 or not root or not head then
                hideESPData(data) continue
            end
            local distance = (root.Position - origin).Magnitude
            if distance > S.ESPMaxDist or (S.ESPTeamCheck and sameTeam(player)) then
                hideESPData(data) continue
            end
            local _, onScreen = cam:WorldToViewportPoint(root.Position)
            local topV = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
            local bottomV = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
            if not onScreen or topV.Z <= 0 or bottomV.Z <= 0 then hideESPData(data) continue end

            local h = math.max(snap(math.abs(bottomV.Y - topV.Y)), 6)
            local w = snap(h * 0.55)
            local x = snap((topV.X + bottomV.X) / 2 - w / 2)
            local y = snap(math.min(topV.Y, bottomV.Y))

            local roleText, roleColor
            if S.ESPRoles then roleText, roleColor = getRoleInfo(player) end
            local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
            local baseColor = S.ESPBoxRainbow and rainbow() or S.ESPBoxColor
            if S.ESPVisCheck then
                baseColor = isVisible(cam, head, character) and S.ESPVisibleColor or S.ESPHiddenColor
            end
            local healthColor
            if S.ESPHealthGradient then healthColor = HEALTH_LOW:Lerp(HEALTH_HIGH, ratio)
            else healthColor = S.ESPHealthRainbow and rainbow() or S.ESPHealthColor end

            local info = {
                x = x, y = y, w = w, h = h, name = player.Name,
                nameColor = S.ESPNameRainbow and rainbow() or S.ESPNameColor,
                roleText = roleText, roleColor = roleColor,
                hp = math.max(math.floor(humanoid.Health + 0.5), 0),
                ratio = ratio, healthColor = healthColor,
                distance = math.floor(distance),
                boxColor = (S.ESPRoleColors and roleColor) or baseColor,
            }
            if data.billboard then drawFallback(data, info)
            else drawESP(data, viewport, info) end
        end
    end
end

local function stopFly()
    disconnect(FlyConnection) FlyConnection = nil
    safeDestroy(FlyLV) safeDestroy(FlyAO) safeDestroy(FlyAtt)
    FlyLV, FlyAO, FlyAtt = nil, nil, nil
    if Hum and Hum.Parent then pcall(function() Hum.PlatformStand = false end) end
    S.Fly = false
end

local function startFly()
    refreshCharacter()
    local cam = getCamera()
    if not HRP or not Hum or not cam then return false end
    stopFly() S.Fly = true
    FlyAtt = Instance.new("Attachment") FlyAtt.Name = "MINDHUB_FlyAttachment" FlyAtt.Parent = HRP
    FlyLV = Instance.new("LinearVelocity") FlyLV.Name = "MINDHUB_FlyVelocity" FlyLV.Attachment0 = FlyAtt
    FlyLV.RelativeTo = Enum.ActuatorRelativeTo.World FlyLV.MaxForce = math.huge FlyLV.VectorVelocity = Vector3.zero
    FlyLV.Parent = HRP
    FlyAO = Instance.new("AlignOrientation") FlyAO.Name = "MINDHUB_FlyOrientation"
    FlyAO.Mode = Enum.OrientationAlignmentMode.OneAttachment FlyAO.Attachment0 = FlyAtt
    FlyAO.MaxTorque = math.huge FlyAO.Responsiveness = 100 FlyAO.CFrame = cam.CFrame FlyAO.Parent = HRP
    Hum.PlatformStand = true
    FlyConnection = RunService.Heartbeat:Connect(function()
        local camera = getCamera()
        if Unloaded or not S.Fly or not camera or not HRP or not HRP.Parent or not FlyLV or not FlyLV.Parent then stopFly() return end
        local move = Vector3.zero
        if not UIS:GetFocusedTextBox() then
            if UIS:IsKeyDown(Enum.KeyCode.W) then move += camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then move -= camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then move -= camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then move += camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
        end
        if move.Magnitude > 0 then move = move.Unit end
        FlyLV.VectorVelocity = move * S.FlySpeed
        if FlyAO then FlyAO.CFrame = camera.CFrame end
    end)
    return true
end

local function setFly(enabled)
    FlyWanted = enabled and true or false
    if not enabled then stopFly() return end
    if not startFly() then notify("MINDHUB", "Персонаж не готов. Полёт включится после спавна.", "Warning") end
end

local function restoreNoclip()
    for part, oldValue in pairs(OriginalCollision) do
        if part and part.Parent then pcall(function() part.CanCollide = oldValue end) end
    end
    table.clear(OriginalCollision)
end

local function setNoclip(enabled)
    S.Noclip = enabled disconnect(NoclipConnection) NoclipConnection = nil
    if not enabled then restoreNoclip() return end
    NoclipConnection = RunService.Stepped:Connect(function()
        if Unloaded then return end
        local character = LP.Character if not character then return end
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                if OriginalCollision[part] == nil then OriginalCollision[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
    end)
end

local function setInfJump(enabled)
    S.InfJump = enabled disconnect(InfJumpConnection) InfJumpConnection = nil
    if enabled then InfJumpConnection = UIS.JumpRequest:Connect(function() if S.InfJump and Hum and Hum.Parent and Hum.Health > 0 then Hum:ChangeState(Enum.HumanoidStateType.Jumping) end end) end
end

local function setSpeedHack(enabled)
    local was = S.SpeedHack S.SpeedHack = enabled
    disconnect(SpeedConnection) SpeedConnection = nil
    if enabled then
        SpeedHum, SpeedOriginal = nil, nil
        SpeedConnection = RunService.Heartbeat:Connect(function()
            if Hum and Hum.Parent and Hum.Health > 0 then
                if SpeedHum ~= Hum then SpeedHum = Hum SpeedOriginal = Hum.WalkSpeed end
                Hum.WalkSpeed = S.SpeedValue
            end
        end)
    elseif was then
        if Hum and Hum.Parent then Hum.WalkSpeed = (S.WalkSpeedSet and S.WalkSpeed) or SpeedOriginal or 16 end
        SpeedHum, SpeedOriginal = nil, nil
    end
end

local function applyJump(value)
    if not Hum then return end
    pcall(function()
        if Hum.UseJumpPower then Hum.JumpPower = value
        else Hum.JumpHeight = (value * value) / (2 * Workspace.Gravity) end
    end)
end

local function applyMovementOverrides()
    if not Hum then return end
    if S.WalkSpeedSet and not S.SpeedHack then Hum.WalkSpeed = S.WalkSpeed end
    if S.JumpSet then applyJump(S.JumpPower) end
end

local TPTarget = nil
local playerDropdown = nil

local function playerNames()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP then table.insert(list, player.Name) end
    end
    table.sort(list, function(a, b) return string.lower(a) < string.lower(b) end)
    return list
end

local function teleportToPlayer(player)
    refreshCharacter()
    if not Char or not HRP or not HRP.Parent then notify("Телепорт", "Твой персонаж ещё не готов.", "Warning") return end
    local targetChar = player.Character
    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not targetRoot then notify("Телепорт", "У игрока " .. player.Name .. " сейчас нет персонажа.", "Warning") return end
    Char:PivotTo(targetRoot.CFrame * CFrame.new(0, 2, 5))
    pcall(function() HRP.AssemblyLinearVelocity = Vector3.zero HRP.AssemblyAngularVelocity = Vector3.zero end)
    notify("Телепорт", "Телепорт к " .. player.Name .. ".", "Success")
end

local function teleportByName(name)
    local player = name and Players:FindFirstChild(name)
    if not player or not player:IsA("Player") then notify("Телепорт", "Сначала выбери игрока.", "Warning") return end
    teleportToPlayer(player)
end

local function teleportNext()
    local names = playerNames()
    if #names == 0 then notify("Телепорт", "На сервере нет других игроков.", "Warning") return end
    local index = table.find(names, TPTarget) or 0
    index = index % #names + 1
    TPTarget = names[index]
    if playerDropdown then pcall(function() playerDropdown:Set(TPTarget) end) end
    teleportByName(TPTarget)
end

local function refreshPlayerList()
    local names = playerNames()
    if #names == 0 then names = { "(нет игроков)" } end
    if not table.find(names, TPTarget) then TPTarget = names[1] end
    if playerDropdown then
        for _, method in ipairs({ "Refresh", "SetValues", "UpdateValues", "SetOptions" }) do
            local done = pcall(function() playerDropdown[method](playerDropdown, names, TPTarget) end)
            if done then return true end
        end
    end
    return false
end

local updateCameraFeatures
do
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    RayParams.IgnoreWater = true
    local LOCK_COLOR = Color3.fromRGB(255, 80, 80)
    local AimLock = nil
    local AimLastTick = os.clock()

    local function hasLineOfSight(cam, part, character)
        local filter = { cam }
        if LP.Character then table.insert(filter, LP.Character) end
        RayParams.FilterDescendantsInstances = filter
        local origin = cam.CFrame.Position
        local result = Workspace:Raycast(origin, part.Position - origin, RayParams)
        return result == nil or result.Instance:IsDescendantOf(character)
    end

    local function torsoOf(character)
        return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
    end

    local function candidateParts(character)
        local mode = S.AimPart
        if mode == "Head" then
            local part = character:FindFirstChild("Head")
            return part and { part } or {}
        elseif mode == "Torso" then
            local part = torsoOf(character)
            return part and { part } or {}
        end
        local list = {}
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then table.insert(list, part) end
        end
        return list
    end

    local function evaluatePlayer(cam, player, center, fovLimit)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return nil end
        if S.AimIgnoreFF and character:FindFirstChildOfClass("ForceField") then return nil end
        local camPos = cam.CFrame.Position
        local bestPart, bestScreenDist
        for _, part in ipairs(candidateParts(character)) do
            local point, onScreen = cam:WorldToViewportPoint(part.Position)
            if onScreen then
                local screenDist = (Vector2.new(point.X, point.Y) - center).Magnitude
                if screenDist <= fovLimit and (not bestScreenDist or screenDist < bestScreenDist)
                    and (part.Position - camPos).Magnitude <= S.AimMaxDist
                    and (not S.AimWallCheck or hasLineOfSight(cam, part, character)) then
                    bestPart, bestScreenDist = part, screenDist
                end
            end
        end
        if not bestPart then return nil end
        local score
        if S.AimPriority == "Distance" then score = (bestPart.Position - camPos).Magnitude
        elseif S.AimPriority == "Lowest HP" then score = humanoid.Health
        else score = bestScreenDist end
        return bestPart, score
    end

    local function getAimTarget(cam)
        local center = cam.ViewportSize / 2
        if S.AimSticky and AimLock and isValidPlayer(AimLock) then
            local part = evaluatePlayer(cam, AimLock, center, S.AimFOV * 1.5)
            if part then return part end
        end
        AimLock = nil
        local bestPart, bestPlayer, bestScore
        for _, player in ipairs(Players:GetPlayers()) do
            if isValidPlayer(player) and (not S.AimTeamCheck or not sameTeam(player)) then
                local part, score = evaluatePlayer(cam, player, center, S.AimFOV)
                if part and (not bestScore or score < bestScore) then bestPart, bestPlayer, bestScore = part, player, score end
            end
        end
        AimLock = bestPlayer
        return bestPart
    end

    local function aimPosition(part)
        local position = part.Position
        if S.AimPrediction then
            local velocity = part.AssemblyLinearVelocity
            if velocity.Magnitude > 120 then velocity = velocity.Unit * 120 end
            position += velocity * S.AimPredictionAmount
        end
        return position
    end

    function updateCameraFeatures()
        local cam = getCamera() if not cam then return end
        local now = os.clock() local dt = math.min(now - AimLastTick, 0.1) AimLastTick = now
        local aiming = S.Aimbot and (S.AimMode == "Always On" or AimActive)
        local target = nil
        if aiming then target = getAimTarget(cam) else AimLock = nil end

        if S.Aimbot and S.AimShowFOV then
            if not AimCircle and Drawing then pcall(function() AimCircle = Drawing.new("Circle") AimCircle.NumSides = 64 AimCircle.Thickness = 1 AimCircle.Filled = false end) end
            if AimCircle then
                AimCircle.Position = cam.ViewportSize / 2
                AimCircle.Radius = S.AimFOV
                AimCircle.Color = target and LOCK_COLOR or S.AimFOVColor
                AimCircle.Visible = true
            end
        elseif AimCircle then AimCircle.Visible = false end

        if target and target.Parent then
            local goal = CFrame.new(cam.CFrame.Position, aimPosition(target))
            local alpha = 1 - (1 - math.clamp(S.AimSmooth, 0.01, 1)) ^ (dt * 60)
            cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
        end
        if S.FOVSet then cam.FieldOfView = S.CamFOV end
    end

    track(UIS.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then AimActive = true
        elseif input.KeyCode == Enum.KeyCode.ButtonL2 then AimActive = true end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then AimActive = false end
    end))
end

local function setSpinBot(enabled)
    S.SpinBot = enabled disconnect(SpinConnection) SpinConnection = nil
    if enabled then SpinConnection = RunService.Heartbeat:Connect(function(dt)
        if FlyAO then return end
        if HRP and HRP.Parent then HRP.CFrame = HRP.CFrame * CFrame.Angles(0, math.rad(S.SpinSpeed) * dt * 60, 0) end
    end) end
end

local function applyVisuals()
    if S.Fullbright then
        Lighting.Ambient = Color3.new(1, 1, 1) Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.GlobalShadows = false
    end
    if S.NoFog then
        Lighting.FogEnd = 1000000
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Atmosphere") then
                if OriginalAtmosphere[child] == nil then OriginalAtmosphere[child] = { Density = child.Density, Haze = child.Haze } end
                child.Density = 0 child.Haze = 0
            end
        end
    end
end

local function updateVisualsConnection()
    local needed = S.Fullbright or S.NoFog
    if needed and not VisualsConnection then VisualsConnection = RunService.Heartbeat:Connect(function() if Unloaded then return end safeCall("visuals", applyVisuals) end)
    elseif not needed and VisualsConnection then disconnect(VisualsConnection) VisualsConnection = nil end
end

local function setFullbright(enabled)
    S.Fullbright = enabled
    if enabled then if not OriginalLighting then OriginalLighting = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, GlobalShadows = Lighting.GlobalShadows } end
    elseif OriginalLighting then for property, value in pairs(OriginalLighting) do pcall(function() Lighting[property] = value end) end OriginalLighting = nil end
    updateVisualsConnection()
end

local function setNoFog(enabled)
    S.NoFog = enabled
    if enabled then if OriginalFogEnd == nil then OriginalFogEnd = Lighting.FogEnd end
    else if OriginalFogEnd ~= nil then Lighting.FogEnd = OriginalFogEnd OriginalFogEnd = nil end
        for atmosphere, values in pairs(OriginalAtmosphere) do if atmosphere.Parent then pcall(function() atmosphere.Density = values.Density atmosphere.Haze = values.Haze end) end end
        table.clear(OriginalAtmosphere) end
    updateVisualsConnection()
end

local function setAntiAFK(enabled)
    S.AntiAFK = enabled disconnect(AntiAFKConnection) AntiAFKConnection = nil
    if enabled then AntiAFKConnection = LP.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end) end
end

local MM2 = { Enabled = false, RoleESP = true, Box = true, Name = true, Distance = true, HeldItem = true, Skeleton = false, MaxDistance = 1500, Thickness = 2, Data = {} }
local SkeletonData = {}

local function mm2Role(player)
    local character = player.Character local backpack = player:FindFirstChildOfClass("Backpack")
    local function inspect(container)
        if not container then return nil end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                local n = string.lower(item.Name)
                if string.find(n, "knife", 1, true) then return "Murderer" end
                if string.find(n, "gun", 1, true) or string.find(n, "revolver", 1, true) then return "Sheriff" end
            end
        end
        return nil
    end
    return inspect(character) or inspect(backpack) or "Unknown"
end

local function mm2HeldItem(player)
    local character = player.Character
    if character then for _, item in ipairs(character:GetChildren()) do if item:IsA("Tool") then return item.Name end end end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then for _, item in ipairs(backpack:GetChildren()) do if item:IsA("Tool") then return item.Name end end end
    return "None"
end

local function mm2Remove(player)
    local d = MM2.Data[player] if not d then return end
    safeRemoveDrawing(d.Box) safeRemoveDrawing(d.Text) MM2.Data[player] = nil
end
local function mm2Clear() for player in pairs(MM2.Data) do mm2Remove(player) end end
local function mm2Drawing(kind)
    if not Drawing then return nil end
    local drawOK, obj = pcall(function() return Drawing.new(kind) end)
    if not drawOK then return nil end
    return obj
end
local function mm2GetData(player)
    local d = MM2.Data[player] if d then return d end
    d = { Box = mm2Drawing("Square"), Text = mm2Drawing("Text") }
    if d.Box then d.Box.Filled = false d.Box.Thickness = MM2.Thickness d.Box.Visible = false end
    if d.Text then d.Text.Center = true d.Text.Outline = true d.Text.Size = 13 d.Text.Visible = false end
    MM2.Data[player] = d return d
end
local function mm2Hide(d) if d.Box then d.Box.Visible = false end if d.Text then d.Text.Visible = false end end
local function mm2Update()
    local cam = getCamera() if not MM2.Enabled or not cam then for _, d in pairs(MM2.Data) do mm2Hide(d) end return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP then
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")
            local d = mm2GetData(player)
            if humanoid and humanoid.Health > 0 and root and head then
                local distance = (cam.CFrame.Position - root.Position).Magnitude
                local top, topOn = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                local bottom, bottomOn = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 2.8, 0))
                if topOn and bottomOn and distance <= MM2.MaxDistance then
                    local height = math.max(2, math.abs(bottom.Y - top.Y)) local width = height * 0.55
                    local x = top.X - width / 2 local y = math.min(top.Y, bottom.Y)
                    local role = "Unknown" local color = Color3.fromRGB(190, 190, 190)
                    if MM2.RoleESP then role = mm2Role(player)
                        if role == "Murderer" then color = Color3.fromRGB(255, 65, 75)
                        elseif role == "Sheriff" then color = Color3.fromRGB(70, 155, 255) end
                    end
                    if d.Box then d.Box.Visible = MM2.Box d.Box.Position = Vector2.new(x, y) d.Box.Size = Vector2.new(width, height) d.Box.Color = color d.Box.Thickness = MM2.Thickness end
                    if d.Text then
                        local lines = {}
                        if MM2.Name then table.insert(lines, player.DisplayName or player.Name) end
                        if MM2.RoleESP then table.insert(lines, role) end
                        if MM2.Distance then table.insert(lines, tostring(math.floor(distance + 0.5)) .. " studs") end
                        if MM2.HeldItem then table.insert(lines, "Item: " .. mm2HeldItem(player)) end
                        d.Text.Text = table.concat(lines, " | ") d.Text.Position = Vector2.new(top.X, y - 17) d.Text.Color = color d.Text.Visible = #lines > 0
                    end
                else mm2Hide(d) end
            else mm2Hide(d) end
        end
    end
    for player in pairs(MM2.Data) do if not player.Parent then mm2Remove(player) end end
end

local function skeletonRemove(player)
    local d = SkeletonData[player] if not d then return end
    for _, line in ipairs(d.lines) do safeRemoveDrawing(line) end
    SkeletonData[player] = nil
end
local function skeletonClear() for player in pairs(SkeletonData) do skeletonRemove(player) end end
local function skeletonHideAll() for _, d in pairs(SkeletonData) do for _, line in ipairs(d.lines) do line.Visible = false end end end

local function skeletonJoints(character)
    local joints = {}
    for _, inst in ipairs(character:GetDescendants()) do
        if inst:IsA("Motor6D") and inst.Part0 and inst.Part1 and inst.Part0:IsA("BasePart") and inst.Part1:IsA("BasePart") then
            table.insert(joints, inst)
        end
    end
    return joints
end

local function skeletonNewLine()
    if not Drawing then return nil end
    local okLine, line = pcall(function() local l = Drawing.new("Line") l.Visible = false return l end)
    return okLine and line or nil
end

local function updateSkeletons()
    local useGeneral = S.ESPSkeleton
    local useMM2 = MM2.Enabled and MM2.Skeleton
    if not Drawing or not (useGeneral or useMM2) then skeletonHideAll() return end
    local cam = getCamera() local origin = originPos()
    if not cam or not origin then skeletonHideAll() return end
    local maxDist = math.max(useGeneral and S.ESPMaxDist or 0, useMM2 and MM2.MaxDistance or 0)
    local now = os.clock()

    for _, player in ipairs(Players:GetPlayers()) do
        local d = SkeletonData[player] local used = 0
        if player ~= LP and isValidPlayer(player) then
            local character = player.Character
            local root = character:FindFirstChild("HumanoidRootPart")
            local skipTeam = (not useMM2) and S.ESPTeamCheck and sameTeam(player)
            if root and not skipTeam and (root.Position - origin).Magnitude <= maxDist then
                if not d then d = { lines = {}, joints = {}, character = nil, refreshAt = 0 } SkeletonData[player] = d end
                if d.character ~= character or now >= d.refreshAt then
                    d.character = character d.joints = skeletonJoints(character) d.refreshAt = now + 1
                end
                local color
                if useMM2 then
                    color = Color3.fromRGB(190, 190, 190)
                    if MM2.RoleESP then
                        local role = mm2Role(player)
                        if role == "Murderer" then color = Color3.fromRGB(255, 65, 75)
                        elseif role == "Sheriff" then color = Color3.fromRGB(70, 155, 255) end
                    end
                else color = S.ESPSkeletonRainbow and rainbow() or S.ESPSkeletonColor end
                for _, joint in ipairs(d.joints) do
                    local p0, p1 = joint.Part0, joint.Part1
                    if p0 and p1 and p0.Parent and p1.Parent then
                        local a = cam:WorldToViewportPoint(p0.Position) local b = cam:WorldToViewportPoint(p1.Position)
                        if a.Z > 0 and b.Z > 0 then
                            used += 1 local line = d.lines[used]
                            if not line then line = skeletonNewLine() if not line then used -= 1 break end d.lines[used] = line end
                            line.From = Vector2.new(a.X, a.Y) line.To = Vector2.new(b.X, b.Y)
                            line.Color = color line.Thickness = S.ESPThickness line.Visible = true
                        end
                    end
                end
            end
        end
        if d then for i = used + 1, #d.lines do d.lines[i].Visible = false end end
    end
end

local roleCache = setmetatable({}, { __mode = "k" })
getRoleInfo = function(player)
    local now = os.clock() local cached = roleCache[player]
    if cached and now - cached.t < 0.25 then return cached.text, cached.color end
    local text, color local role = mm2Role(player)
    if role == "Murderer" then text, color = "Murderer", Color3.fromRGB(255, 65, 75)
    elseif role == "Sheriff" then text, color = "Sheriff", Color3.fromRGB(70, 155, 255)
    elseif player.Team and #Teams:GetTeams() > 1 then text, color = player.Team.Name, player.TeamColor.Color end
    roleCache[player] = { t = now, text = text, color = color }
    return text, color
end

local MM2InnocentIndex = 0
local function mm2PlayersByRole(role)
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if isValidPlayer(player) and mm2Role(player) == role then table.insert(list, player) end
    end
    table.sort(list, function(a, b) return string.lower(a.Name) < string.lower(b.Name) end)
    return list
end

local function mm2TeleportToRole(role, ruName, cycle)
    local list = mm2PlayersByRole(role)
    if #list == 0 then notify("Телепорт", ruName .. ": никого не найдено.", "Warning") return end
    local target
    if cycle then MM2InnocentIndex = MM2InnocentIndex % #list + 1 target = list[MM2InnocentIndex]
    else
        local origin = originPos() local best = math.huge
        for _, player in ipairs(list) do
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if root then local dist = origin and (root.Position - origin).Magnitude or 0 if dist < best then best = dist target = player end end
        end
    end
    if target then teleportToPlayer(target) end
end

local MM2Action = { KillRunning = false }
local function mm2FindOwnKnife()
    local function find(container)
        if not container then return nil end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and string.find(string.lower(item.Name), "knife", 1, true) then return item end
        end
        return nil
    end
    return find(LP.Character) or find(LP:FindFirstChildOfClass("Backpack"))
end

local function mm2KillAll()
    if MM2Action.KillRunning then notify("MM2", "Kill All уже выполняется.", "Info") return end
    refreshCharacter() if not Char or not Hum or not HRP or not HRP.Parent or Hum.Health <= 0 then notify("MM2", "Твой персонаж не готов.", "Warning") return end
    local knife = mm2FindOwnKnife() if not knife then notify("MM2", "Нож не найден: ты не убийца.", "Warning") return end
    MM2Action.KillRunning = true
    task.spawn(function()
        local attacked, killed = 0, 0 local home = HRP.CFrame
        local okRun, errRun = pcall(function()
            local function equip() if Char and Hum and knife.Parent ~= Char then pcall(function() Hum:EquipTool(knife) end) task.wait(0.15) end end
            equip()
            for _, player in ipairs(Players:GetPlayers()) do
                if Unloaded then break end
                if player ~= LP and isValidPlayer(player) then
                    local targetChar = player.Character local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart") local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
                    if targetRoot and targetHum then
                        attacked += 1 local tries = 0
                        while tries < 6 and not Unloaded and targetHum.Health > 0 and targetRoot.Parent and HRP and HRP.Parent and Hum and Hum.Health > 0 do
                            equip() if not Char or not HRP or not HRP.Parent then break end
                            local behind = targetRoot.Position - targetRoot.CFrame.LookVector * 2
                            Char:PivotTo(CFrame.lookAt(behind, targetRoot.Position)) pcall(function() knife:Activate() end)
                            task.wait(0.12) tries += 1
                        end
                        if targetHum.Health <= 0 then killed += 1 end
                    end
                end
            end
        end)
        if not okRun then warn("[MINDHUB] Kill All error: " .. tostring(errRun)) end
        if Char and Char.Parent and HRP and HRP.Parent then pcall(function() Char:PivotTo(home) end) end
        MM2Action.KillRunning = false
        notify("MM2", "Kill All: целей " .. attacked .. ", убито " .. killed .. ".", killed > 0 and "Success" or "Warning")
    end)
end

local function holderPos(inst)
    if inst:IsA("BasePart") then return inst.Position, inst
    elseif inst:IsA("Tool") then local handle = inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true) if handle then return handle.Position, handle end
    elseif inst:IsA("Model") then local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) local okPivot, cf = pcall(inst.GetPivot, inst) if okPivot then return cf.Position, part end end
    return nil, nil
end

local function mm2InsidePlayerStuff(inst)
    local p = inst.Parent
    while p and p ~= Workspace do
        if p:IsA("Backpack") then return true end
        if p:IsA("Model") and Players:GetPlayerFromCharacter(p) then return true end
        p = p.Parent
    end
    return false
end

local function mm2FindDroppedGun()
    local origin = originPos() local primary, primaryDist = nil, math.huge local secondary, secondaryDist = nil, math.huge local count = 0
    for _, inst in ipairs(Workspace:GetDescendants()) do
        count += 1 if count % 2000 == 0 then task.wait() if Unloaded then return nil end end
        if inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Tool") then
            local name = string.lower(inst.Name)
            local isDrop = string.find(name, "gundrop", 1, true) or string.find(name, "gun drop", 1, true) or string.find(name, "droppedgun", 1, true) or string.find(name, "dropped gun", 1, true)
            local isGun = not isDrop and (string.find(name, "gun", 1, true) or string.find(name, "revolver", 1, true))
            if (isDrop or isGun) and not mm2InsidePlayerStuff(inst) then
                local pos, part = holderPos(inst)
                if pos then
                    local dist = origin and (pos - origin).Magnitude or 0
                    if isDrop then if dist < primaryDist then primary, primaryDist = { inst = inst, pos = pos, part = part }, dist end
                    elseif dist < secondaryDist then secondary, secondaryDist = { inst = inst, pos = pos, part = part }, dist end
                end
            end
        end
    end
    local found = primary or secondary if not found then return nil end
    return { pos = found.pos, part = found.part, name = found.inst.Name, path = found.inst:GetFullName() }
end

local function mm2TeleportToGun()
    refreshCharacter() if not Char or not HRP or not HRP.Parent then notify("MM2", "Твой персонаж не готов.", "Warning") return end
    notify("MM2", "Ищу пистолет...", "Info")
    task.spawn(function()
        local okFind, found = pcall(mm2FindDroppedGun)
        if not okFind then warn("[MINDHUB] Поиск пистолета: " .. tostring(found)) end
        if not okFind or not found then notify("MM2", "Пистолет не найден.", "Warning") return end
        refreshCharacter() if not Char or not HRP or not HRP.Parent then return end
        Char:PivotTo(CFrame.new(found.pos + Vector3.new(0, 3, 0)))
        if firetouchinterest and found.part then pcall(function() firetouchinterest(HRP, found.part, 0) firetouchinterest(HRP, found.part, 1) end) end
        notify("MM2", "Телепорт к пистолету: " .. found.name, "Success")
    end)
end

local function mm2FindOwnGun()
    local function find(container)
        if not container then return nil end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then local n = string.lower(item.Name) if string.find(n, "gun", 1, true) or string.find(n, "revolver", 1, true) then return item end end
        end
        return nil
    end
    return find(LP.Character) or find(LP:FindFirstChildOfClass("Backpack"))
end

local function mm2KillMurderer()
    if MM2Action.KillRunning then notify("MM2", "Действие уже выполняется.", "Info") return end
    refreshCharacter() local cam = getCamera()
    if not Char or not Hum or not HRP or not HRP.Parent or Hum.Health <= 0 or not cam then notify("MM2", "Твой персонаж не готов.", "Warning") return end
    local gun = mm2FindOwnGun() if not gun then notify("MM2", "Пистолет не найден: ты не шериф.", "Warning") return end
    local target, bestDist = nil, nil
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and isValidPlayer(player) and mm2Role(player) == "Murderer" then
            local root = player.Character:FindFirstChild("HumanoidRootPart") local d = (root.Position - HRP.Position).Magnitude
            if not bestDist or d < bestDist then target, bestDist = player, d end
        end
    end
    if not target then notify("MM2", "Убийца не найден.", "Warning") return end
    MM2Action.KillRunning = true
    task.spawn(function()
        local home = HRP.CFrame local origCameraType = cam.CameraType local shots, killed = 0, false
        local okRun, errRun = pcall(function()
            local targetChar = target.Character local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart") local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
            if not targetRoot or not targetHum then return end
            if gun.Parent ~= Char then pcall(function() Hum:EquipTool(gun) end) task.wait(0.2) end
            cam.CameraType = Enum.CameraType.Scriptable
            while shots < 6 and not Unloaded and targetHum.Health > 0 and targetRoot.Parent and Char and HRP and HRP.Parent and Hum and Hum.Health > 0 do
                local behind = targetRoot.Position - targetRoot.CFrame.LookVector * 7 + Vector3.new(0, 1, 0)
                Char:PivotTo(CFrame.lookAt(behind, targetRoot.Position))
                cam.CFrame = CFrame.lookAt(HRP.Position + Vector3.new(0, 1.5, 0), targetRoot.Position)
                RunService.RenderStepped:Wait()
                if mousemoveabs then local center = cam.ViewportSize / 2 pcall(mousemoveabs, center.X, center.Y) end
                pcall(function() gun:Activate() end) shots += 1 task.wait(0.6)
            end
            killed = targetHum.Health <= 0
        end)
        if not okRun then warn("[MINDHUB] Kill Murder error: " .. tostring(errRun)) end
        pcall(function() cam.CameraType = origCameraType end)
        if Char and Char.Parent and HRP and HRP.Parent then pcall(function() Char:PivotTo(home) end) end
        MM2Action.KillRunning = false
        notify("MM2", killed and "Убийца убит." or ("Выстрелов: " .. shots .. ", убийца ещё жив."), killed and "Success" or "Warning")
    end)
end

local function onCharacterAdded(character)
    CharToken += 1 local token = CharToken
    stopFly() disconnect(NoclipConnection) NoclipConnection = nil restoreNoclip() clearCharacter()
    local hum = character:WaitForChild("Humanoid", 10) local root = character:WaitForChild("HumanoidRootPart", 10)
    if Unloaded or token ~= CharToken or LP.Character ~= character or not hum or not root then return end
    refreshCharacter() applyMovementOverrides()
    if S.Noclip then setNoclip(true) end
    if FlyWanted then startFly() end
end
track(LP.CharacterAdded:Connect(onCharacterAdded))
track(LP.CharacterRemoving:Connect(function() stopFly() restoreNoclip() clearCharacter() end))
refreshCharacter()

local function onPlayerCharacter(player, character)
    task.spawn(function()
        local head = character:WaitForChild("Head", 10) if not head then return end
        character:WaitForChild("HumanoidRootPart", 10)
        if Unloaded or not player.Parent or player.Character ~= character then return end
        if S.ESP then clearPlayerESP(player) createPlayerESP(player) end
    end)
end
local function hookPlayer(player)
    if player == LP or PlayerConns[player] then return end
    local conns = {} PlayerConns[player] = conns
    table.insert(conns, player.CharacterAdded:Connect(function(character) onPlayerCharacter(player, character) end))
    if player.Character then onPlayerCharacter(player, player.Character) end
end
local function unhookPlayer(player)
    local conns = PlayerConns[player]
    if conns then for _, conn in ipairs(conns) do disconnect(conn) end PlayerConns[player] = nil end
    clearPlayerESP(player) mm2Remove(player) skeletonRemove(player)
end
track(Players.PlayerAdded:Connect(hookPlayer))
track(Players.PlayerRemoving:Connect(unhookPlayer))
for _, player in ipairs(Players:GetPlayers()) do hookPlayer(player) end

local ThemeAPI = {}
do
    local function callUI(methodNames, ...)
        local args = table.pack(...) local owners = {}
        if Window then table.insert(owners, Window) end table.insert(owners, NextUI)
        for _, owner in ipairs(owners) do
            for _, name in ipairs(methodNames) do
                local okCall = pcall(function() local fn = owner[name] if type(fn) ~= "function" then error("no method " .. name) end fn(owner, table.unpack(args, 1, args.n)) end)
                if okCall then return true, name end
            end
        end
        return false
    end
    function ThemeAPI.applyTheme(name) S.Theme = name return (callUI({ "SetTheme", "ChangeTheme", "SetThemeName", "ApplyTheme" }, name)) end
    function ThemeAPI.applyAccent(color)
        S.AccentColor = color
        local applied = callUI({ "SetAccentColor", "SetAccent", "SetAccentColour", "SetMainColor", "SetThemeColor" }, color)
        if not applied then pcall(function() local theme = NextUI.Theme or NextUI.CurrentTheme or (Window and Window.Theme) if type(theme) == "table" then for _, key in ipairs({ "Accent", "AccentColor", "Main", "Primary" }) do if theme[key] ~= nil then theme[key] = color applied = true end end end end) end
        return applied
    end
end

local CONFIG_DIR = "MINDHUB_Configs"
local CONFIG_SLOTS = { "default", "CFG | 1", "CFG | 2", "CFG | 3", "CFG | 4", "CFG | 5" }
local SelectedSlot = "default"
local FS_OK = writefile ~= nil and readfile ~= nil and isfile ~= nil
local Registry = {}
local UIBuilt = false

local function reg(tbl, key, element) if element ~= nil then table.insert(Registry, { tbl = tbl, key = key, elem = element }) end end
local function isValidSlot(slot) for _, name in ipairs(CONFIG_SLOTS) do if name == slot then return true end end return false end
local function configPath(slot) return CONFIG_DIR .. "/" .. slot .. ".json" end

local function encodeTable(tbl)
    local out = {}
    for key, value in pairs(tbl) do
        local kind = typeof(value)
        if kind == "boolean" or kind == "number" or kind == "string" then out[key] = value
        elseif kind == "Color3" then out[key] = { __color = true, r = value.R, g = value.G, b = value.B } end
    end
    return out
end

local function collectConfig()
    local s = encodeTable(S) s.Fly = FlyWanted
    return { version = 1, S = s, MM2 = encodeTable(MM2) }
end

local function decodeValue(current, raw)
    local kind = typeof(current)
    if kind == "Color3" then
        if type(raw) == "table" and raw.__color and type(raw.r) == "number" and type(raw.g) == "number" and type(raw.b) == "number" then
            return Color3.new(math.clamp(raw.r, 0, 1), math.clamp(raw.g, 0, 1), math.clamp(raw.b, 0, 1))
        end
        return nil
    end
    if typeof(raw) == kind then return raw end
    return nil
end

local ConfigSetters = {
    S = {
        Fly = setFly, Noclip = setNoclip, InfJump = setInfJump,
        SpeedHack = setSpeedHack, SpinBot = setSpinBot, Fullbright = setFullbright,
        NoFog = setNoFog, AntiAFK = setAntiAFK,
        ESP = function(v) S.ESP = v refreshESP() end,
        Theme = function(v) ThemeAPI.applyTheme(v) end,
        AccentColor = function(v) S.AccentColor = v if S.AccentSet then ThemeAPI.applyAccent(v) end end,
    },
    MM2 = { Enabled = function(v) MM2.Enabled = v if not v then mm2Clear() end end },
}

local function applyConfig(data)
    if type(data) ~= "table" then return false end
    local tables = { S = S, MM2 = MM2 }
    local pending = {}
    for name, tbl in pairs(tables) do
        local saved = data[name]
        if type(saved) == "table" then
            for key, raw in pairs(saved) do
                local current = tbl[key]
                if current ~= nil then
                    local value = decodeValue(current, raw)
                    if value ~= nil then
                        local setter = ConfigSetters[name] and ConfigSetters[name][key]
                        if setter then table.insert(pending, { setter, value }) else tbl[key] = value end
                    end
                end
            end
        end
    end
    refreshCharacter()
    if S.WalkSpeedSet and OrigWalk == nil then OrigWalk = Hum and Hum.WalkSpeed or 16 end
    if S.JumpSet and OrigJump == nil and Hum then OrigJump = { Power = Hum.JumpPower, Height = Hum.JumpHeight } end
    if S.FOVSet and OrigFOV == nil then local cam = getCamera() OrigFOV = cam and cam.FieldOfView or 70 end
    for _, entry in ipairs(pending) do pcall(entry[1], entry[2]) end
    applyMovementOverrides()
    return true
end

local function syncUI()
    UIReady = false
    for _, item in ipairs(Registry) do
        local value = item.tbl[item.key]
        if item.tbl == S and item.key == "Fly" then value = FlyWanted end
        if value ~= nil then
            local done = pcall(function() item.elem:Set(value) end)
            if not done then pcall(function() item.elem:SetValue(value) end) end
        end
    end
    task.defer(function() UIReady = true end)
end

local function saveConfig(slot)
    if not FS_OK then notify("Конфиг", "Нет файловых функций.", "Warning") return false end
    if not isValidSlot(slot) then return false end
    local okEncode, json = pcall(function() return HttpService:JSONEncode(collectConfig()) end)
    if not okEncode then notify("Конфиг", "Ошибка кодирования.", "Warning") return false end
    pcall(function() if makefolder and not (isfolder and isfolder(CONFIG_DIR)) then makefolder(CONFIG_DIR) end end)
    local okWrite = pcall(writefile, configPath(slot), json)
    notify("Конфиг", okWrite and ("Сохранено: '" .. slot .. "'.") or "Ошибка записи.", okWrite and "Success" or "Warning")
    return okWrite
end

local function loadConfig(slot, silent)
    if not FS_OK or not isValidSlot(slot) then if not silent then notify("Конфиг", "Файловые функции недоступны.", "Warning") end return false end
    local path = configPath(slot) local okExists, exists = pcall(isfile, path)
    if not (okExists and exists) then if not silent then notify("Конфиг", "Слот '" .. slot .. "' пуст.", "Warning") end return false end
    local okRead, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not okRead or not applyConfig(data) then if not silent then notify("Конфиг", "Файл повреждён.", "Warning") end return false end
    if UIBuilt then syncUI() end
    if not silent then notify("Конфиг", "Загружено: '" .. slot .. "'.", "Success") end
    return true
end

local function deleteConfig(slot)
    if not FS_OK or not isValidSlot(slot) or not delfile then notify("Конфиг", "Нельзя удалить.", "Warning") return end
    local okDel = pcall(delfile, configPath(slot))
    notify("Конфиг", okDel and ("Удалено: '" .. slot .. "'.") or "Нечего удалять.", okDel and "Success" or "Warning")
end

local function setAutoload(slot)
    if not FS_OK or not isValidSlot(slot) then return end
    pcall(function() if makefolder and not (isfolder and isfolder(CONFIG_DIR)) then makefolder(CONFIG_DIR) end end)
    local okWrite = pcall(writefile, CONFIG_DIR .. "/autoload.txt", slot)
    notify("Конфиг", okWrite and ("Автозагрузка: '" .. slot .. "'") or "Ошибка записи.", okWrite and "Success" or "Warning")
end

local function clearAutoload()
    if not FS_OK then return end
    pcall(function() if delfile then delfile(CONFIG_DIR .. "/autoload.txt") end end)
    notify("Конфиг", "Автозагрузка очищена.", "Info")
end

local function autoloadConfig()
    if not FS_OK then return end
    local okRead, slot = pcall(function() local path = CONFIG_DIR .. "/autoload.txt" if isfile(path) then return readfile(path) end return nil end)
    if okRead and type(slot) == "string" then
        slot = slot:gsub("%s", "")
        if isValidSlot(slot) then SelectedSlot = slot loadConfig(slot, true) end
    end
end

local function unload()
    if Unloaded then return end
    Unloaded = true FlyWanted = false
    pcall(function() RunService:UnbindFromRenderStep("MINDHUB_Update") end)
    S.ESP = false S.Aimbot = false S.SpinBot = false S.Noclip = false S.InfJump = false S.AntiAFK = false
    stopFly() setNoclip(false) setInfJump(false) setSpeedHack(false) setSpinBot(false) setAntiAFK(false) setFullbright(false) setNoFog(false)
    clearESP() MM2.Enabled = false mm2Clear() skeletonClear() safeRemoveDrawing(AimCircle) AimCircle = nil
    if Hum and Hum.Parent then pcall(function() if S.WalkSpeedSet and OrigWalk then Hum.WalkSpeed = OrigWalk end if S.JumpSet and OrigJump then Hum.JumpPower = OrigJump.Power Hum.JumpHeight = OrigJump.Height end end) end
    local cam = getCamera() if cam and S.FOVSet and OrigFOV then pcall(function() cam.FieldOfView = OrigFOV end) end
    for _, conn in ipairs(Connections) do disconnect(conn) end table.clear(Connections)
    for player in pairs(PlayerConns) do unhookPlayer(player) end
    pcall(function() if watermark and watermark.Destroy then watermark:Destroy() end end)
    pcall(function() if Window and Window.Destroy then Window:Destroy() elseif NextUI.Destroy then NextUI:Destroy() end end)
    if genv then genv.__MINDHUB_UNLOAD = nil end
    resetRunFlag()
end
if genv then genv.__MINDHUB_UNLOAD = unload end

local function buildUI()
    local function addToggle(section, title, tbl, key, onChange, extra)
        local cfg = { Title = title, Default = tbl[key], Callback = function(v) if onChange then onChange(v) else tbl[key] = v end end }
        if extra then for k, v in pairs(extra) do cfg[k] = v end end
        local element = section:AddToggle(cfg) reg(tbl, key, element) return element
    end
    local function addSlider(section, title, min, max, step, tbl, key, onChange)
        local element = section:AddSlider({ Title = title, Min = min, Max = max, Default = tbl[key], Increment = step, Callback = function(v) if onChange then onChange(v) else tbl[key] = v end end })
        reg(tbl, key, element) return element
    end
    local function addColor(section, title, tbl, key)
        local element = section:AddColorPicker({ Title = title, Default = tbl[key], Callback = function(v) tbl[key] = v end })
        reg(tbl, key, element) return element
    end
    local function addDropdown(section, title, values, tbl, key, onChange)
        local element = section:AddDropdown({ Title = title, Values = values, Default = tbl[key], Callback = function(v) tbl[key] = v if onChange then onChange(v) end end })
        reg(tbl, key, element) return element
    end
    local function addButton(section, title, fn)
        local okButton = pcall(function() section:AddButton({ Title = title, Callback = fn }) end)
        if not okButton then pcall(function() section:AddToggle({ Title = title, Default = false, Callback = function(v) if v then fn() end end }) end) end
    end

    local function onWalkSpeed(v)
        if not UIReady then return end
        if not S.WalkSpeedSet then OrigWalk = Hum and Hum.WalkSpeed or 16 S.WalkSpeedSet = true end
        S.WalkSpeed = v if Hum and not S.SpeedHack then Hum.WalkSpeed = v end
    end
    local function onJumpPower(v)
        if not UIReady then return end
        if not S.JumpSet then if Hum then OrigJump = { Power = Hum.JumpPower, Height = Hum.JumpHeight } end S.JumpSet = true end
        S.JumpPower = v applyJump(v)
    end
    local function onFOV(v)
        if not UIReady then return end
        if not S.FOVSet then local cam = getCamera() OrigFOV = cam and cam.FieldOfView or 70 S.FOVSet = true end
        S.CamFOV = v
    end

    local function createWindow(themeName)
        return NextUI:CreateWindow({ Title = "MINDHUB", SubTitle = "v0.1 | Universal", Theme = themeName, Size = Vector2.new(900, 650), ToggleKeys = { Enum.KeyCode.RightShift }, ToggleKey = Enum.KeyCode.RightShift })
    end
    local okWindow, createdWindow = pcall(createWindow, S.Theme)
    if not okWindow or not createdWindow then warn("[MINDHUB] Тема не создалась, использую Onyx.") S.Theme = "Onyx" createdWindow = createWindow("Onyx") end
    Window = createdWindow
    pcall(function() watermark = NextUI:CreateWatermark({Title = "MINDHUB", Position = "TopRight"}) watermark:AddPlayer() end)

    local PlayerTab = Window:AddTab({Title = "Player", Icon = "user"})
    local MoveSec = PlayerTab:AddSection({Title = "Movement", Icon = "move", Collapsible = true})
    addSlider(MoveSec, "WalkSpeed", 0, 300, 1, S, "WalkSpeed", onWalkSpeed)
    addSlider(MoveSec, "JumpPower", 0, 300, 1, S, "JumpPower", onJumpPower)
    addToggle(MoveSec, "Speed Hack", S, "SpeedHack", setSpeedHack)
    addSlider(MoveSec, "Speed Value", 1, 500, 1, S, "SpeedValue")
    addToggle(MoveSec, "Infinite Jump", S, "InfJump", setInfJump)
    local FlySec = PlayerTab:AddSection({Title = "Fly & Collision", Icon = "wind", Collapsible = true})
    addToggle(FlySec, "Fly", S, "Fly", setFly, { Keybind = Enum.KeyCode.F, KeyMode = "Toggle", Default = FlyWanted })
    addSlider(FlySec, "Fly Speed", 1, 500, 1, S, "FlySpeed")
    addToggle(FlySec, "Noclip", S, "Noclip", setNoclip, { Keybind = Enum.KeyCode.N, KeyMode = "Toggle" })
    local TpSec = PlayerTab:AddSection({Title = "Телепорт", Icon = "map-pin", Collapsible = true})
    local tpNames = playerNames() if #tpNames == 0 then tpNames = { "(нет игроков)" } end
    if not table.find(tpNames, TPTarget) then TPTarget = tpNames[1] end
    playerDropdown = TpSec:AddDropdown({ Title = "Игрок", Values = tpNames, Default = TPTarget, Callback = function(value) TPTarget = value end })
    addButton(TpSec, "ТП к выбранному", function() teleportByName(TPTarget) end)
    addButton(TpSec, "ТП к следующему игроку", teleportNext)
    addButton(TpSec, "Обновить список игроков", function() refreshPlayerList() notify("Телепорт", "Список обновлён.", "Success") end)

    local EspTab = Window:AddTab({Title = "ESP", Icon = "eye"})
    local EspMain = EspTab:AddSection({ Title = "ESP — основное", Icon = "settings", Collapsible = true, Toggle = true, Default = S.ESP, Callback = function(enabled) S.ESP = enabled refreshESP() end })
    addSlider(EspMain, "Макс. дистанция", 100, 5000, 50, S, "ESPMaxDist")
    addToggle(EspMain, "Скрывать союзников", S, "ESPTeamCheck")
    local EspBoxSec = EspTab:AddSection({Title = "Рамка", Icon = "crosshair", Collapsible = true})
    addToggle(EspBoxSec, "Показывать рамку", S, "ESPBox")
    addDropdown(EspBoxSec, "Стиль рамки", {"Corner", "Full"}, S, "ESPBoxStyle")
    addColor(EspBoxSec, "Цвет рамки", S, "ESPBoxColor")
    addToggle(EspBoxSec, "Радужная рамка", S, "ESPBoxRainbow")
    addSlider(EspBoxSec, "Длина уголков", 0.15, 0.5, 0.05, S, "ESPCornerLen")
    addToggle(EspBoxSec, "Заливка", S, "ESPBoxFilled")
    addSlider(EspBoxSec, "Прозрачность заливки", 0.05, 0.8, 0.05, S, "ESPFillAlpha")
    addToggle(EspBoxSec, "Чёрная обводка", S, "ESPOutline")
    addSlider(EspBoxSec, "Толщина линий", 1, 5, 0.5, S, "ESPThickness")
    local EspTextSec = EspTab:AddSection({Title = "Имя и роль", Icon = "user", Collapsible = true})
    addToggle(EspTextSec, "Имя", S, "ESPName")
    addColor(EspTextSec, "Цвет имени", S, "ESPNameColor")
    addToggle(EspTextSec, "Радужное имя", S, "ESPNameRainbow")
    addToggle(EspTextSec, "Роль (над именем)", S, "ESPRoles")
    addToggle(EspTextSec, "Красить рамку по роли", S, "ESPRoleColors")
    addToggle(EspTextSec, "Дистанция", S, "ESPDistance")
    addSlider(EspTextSec, "Размер текста", 9, 22, 1, S, "ESPNameSize")
    addDropdown(EspTextSec, "Шрифт", {"Plex", "UI", "System", "Monospace"}, S, "ESPFont")
    local EspHpSec = EspTab:AddSection({Title = "Здоровье", Icon = "layers", Collapsible = true})
    addToggle(EspHpSec, "Полоска HP", S, "ESPHealth")
    addDropdown(EspHpSec, "Сторона полоски", {"Left", "Right"}, S, "ESPHealthSide")
    addToggle(EspHpSec, "Текст «100 | HP»", S, "ESPHPText")
    addToggle(EspHpSec, "Градиент (красный → зелёный)", S, "ESPHealthGradient")
    addColor(EspHpSec, "Цвет HP (без градиента)", S, "ESPHealthColor")
    addToggle(EspHpSec, "Радужное HP", S, "ESPHealthRainbow")
    local EspVisSec = EspTab:AddSection({Title = "Видимость", Icon = "search", Collapsible = true})
    addToggle(EspVisSec, "Проверка видимости (за стеной / на виду)", S, "ESPVisCheck")
    addColor(EspVisSec, "Цвет: на виду", S, "ESPVisibleColor")
    addColor(EspVisSec, "Цвет: за стеной", S, "ESPHiddenColor")
    local EspTracerSec = EspTab:AddSection({Title = "Трассеры", Icon = "move", Collapsible = true})
    addToggle(EspTracerSec, "Трассеры", S, "ESPTracers")
    addDropdown(EspTracerSec, "Откуда", {"Bottom", "Center", "Top"}, S, "ESPTracerOrigin")
    addColor(EspTracerSec, "Цвет трассеров", S, "ESPTracerColor")
    local EspSkelSec = EspTab:AddSection({Title = "Скелет", Icon = "wind", Collapsible = true})
    addToggle(EspSkelSec, "Скелет", S, "ESPSkeleton")
    addColor(EspSkelSec, "Цвет скелета", S, "ESPSkeletonColor")
    addToggle(EspSkelSec, "Радужный скелет", S, "ESPSkeletonRainbow")

    local MM2Tab = Window:AddTab({Title = "MM2", Icon = "crosshair"})
    local MM2Sec = MM2Tab:AddSection({Title = "Murder Mystery 2 ESP", Icon = "eye", Collapsible = true})
    addToggle(MM2Sec, "Enable MM2 ESP", MM2, "Enabled", function(v) MM2.Enabled = v if not v then mm2Clear() end if v and not Drawing then notify("MINDHUB", "Drawing API экзекутора недоступен.", "Warning") end end)
    addToggle(MM2Sec, "Role ESP (Murderer / Sheriff)", MM2, "RoleESP")
    addToggle(MM2Sec, "2D Box", MM2, "Box")
    addToggle(MM2Sec, "Nickname", MM2, "Name")
    addToggle(MM2Sec, "Distance", MM2, "Distance")
    addToggle(MM2Sec, "Held Item", MM2, "HeldItem")
    addToggle(MM2Sec, "Скелет (цвет по ролям)", MM2, "Skeleton")
    addSlider(MM2Sec, "Max Distance", 100, 5000, 50, MM2, "MaxDistance")
    addSlider(MM2Sec, "Box Thickness", 1, 5, 1, MM2, "Thickness")
    local MM2TpSec = MM2Tab:AddSection({Title = "Телепорт по ролям", Icon = "map-pin", Collapsible = true})
    addButton(MM2TpSec, "ТП к Шерифу", function() mm2TeleportToRole("Sheriff", "Шериф", false) end)
    addButton(MM2TpSec, "ТП к Убийце", function() mm2TeleportToRole("Murderer", "Убийца", false) end)
    addButton(MM2TpSec, "ТП к ближайшему мирному", function() mm2TeleportToRole("Unknown", "Мирные", false) end)
    addButton(MM2TpSec, "ТП к следующему мирному", function() mm2TeleportToRole("Unknown", "Мирные", true) end)
    local MM2KillSec = MM2Tab:AddSection({Title = "Убийца / Пистолет", Icon = "crosshair", Collapsible = true})
    addButton(MM2KillSec, "Kill All (только если ты убийца)", mm2KillAll)
    addButton(MM2KillSec, "Kill Murder (только если ты шериф)", mm2KillMurderer)
    addButton(MM2KillSec, "ТП к пистолету", mm2TeleportToGun)

    local VisualTab = Window:AddTab({Title = "Visuals", Icon = "sun"})
    local LightSec = VisualTab:AddSection({Title = "World Lighting", Icon = "sun", Collapsible = true})
    addToggle(LightSec, "Fullbright", S, "Fullbright", setFullbright)
    addToggle(LightSec, "No Fog", S, "NoFog", setNoFog)
    local CameraSec = VisualTab:AddSection({Title = "Camera", Icon = "camera", Collapsible = true})
    addSlider(CameraSec, "Field of View", 40, 120, 1, S, "CamFOV", onFOV)

    local CombatTab = Window:AddTab({Title = "Combat", Icon = "crosshair"})
    local AimSec = CombatTab:AddSection({Title = "Аимбот — основное", Icon = "crosshair", Collapsible = true})
    addToggle(AimSec, "Включить аимбот", S, "Aimbot")
    addDropdown(AimSec, "Режим", {"Hold RMB", "Always On"}, S, "AimMode")
    addDropdown(AimSec, "Часть тела", {"Head", "Torso", "Closest"}, S, "AimPart")
    addDropdown(AimSec, "Приоритет цели", {"Crosshair", "Distance", "Lowest HP"}, S, "AimPriority")
    addSlider(AimSec, "Радиус FOV", 10, 500, 5, S, "AimFOV")
    addSlider(AimSec, "Плавность", 0.01, 1, 0.01, S, "AimSmooth")
    local AimCheckSec = CombatTab:AddSection({Title = "Аимбот — проверки", Icon = "settings", Collapsible = true})
    addToggle(AimCheckSec, "Не целиться в союзников", S, "AimTeamCheck")
    addToggle(AimCheckSec, "Проверка стен", S, "AimWallCheck")
    addToggle(AimCheckSec, "Игнорировать ForceField", S, "AimIgnoreFF")
    addToggle(AimCheckSec, "Липкая цель", S, "AimSticky")
    addSlider(AimCheckSec, "Макс. дистанция", 50, 5000, 50, S, "AimMaxDist")
    local AimPredSec = CombatTab:AddSection({Title = "Аимбот — упреждение", Icon = "move", Collapsible = true})
    addToggle(AimPredSec, "Упреждение", S, "AimPrediction")
    addSlider(AimPredSec, "Упреждение (сек)", 0.01, 0.5, 0.01, S, "AimPredictionAmount")
    local AimFovSec = CombatTab:AddSection({Title = "Круг FOV", Icon = "eye", Collapsible = true})
    addToggle(AimFovSec, "Показывать круг", S, "AimShowFOV")
    addColor(AimFovSec, "Цвет круга", S, "AimFOVColor")
    local SpinSec = CombatTab:AddSection({Title = "Character Rotation", Icon = "refresh-cw", Collapsible = true})
    addToggle(SpinSec, "Spin Bot", S, "SpinBot", setSpinBot)
    addSlider(SpinSec, "Spin Speed", 1, 60, 1, S, "SpinSpeed")

    local MiscTab = Window:AddTab({Title = "Misc", Icon = "layers"})
    local MiscSec = MiscTab:AddSection({Title = "Utilities", Icon = "settings", Collapsible = true})
    addToggle(MiscSec, "Anti-AFK", S, "AntiAFK", setAntiAFK)
    addButton(MiscSec, "Unload MINDHUB", function() unload() end)

    local SettingsTab = Window:AddTab({Title = "Settings", Icon = "settings"})
    local ThemeSec = SettingsTab:AddSection({Title = "Appearance", Icon = "palette", Collapsible = true})
    local themeNames = {"Rose", "Crimson", "Onyx", "Dark", "Darker", "Light", "Aqua", "Lagoon", "Amethyst", "Emerald", "Toxic", "Noir"}
    addDropdown(ThemeSec, "Theme", themeNames, S, "Theme", function(value) if not UIReady then return end if not ThemeAPI.applyTheme(value) then notify("UI", "Не удалось сменить тему.", "Warning") end if S.AccentSet then ThemeAPI.applyAccent(S.AccentColor) end end)
    local accentPicker = ThemeSec:AddColorPicker({ Title = "Accent Color", Default = S.AccentColor, Callback = function(color) if not UIReady then return end S.AccentSet = true if not ThemeAPI.applyAccent(color) then notify("UI", "Не удалось применить акцент.", "Warning") end end })
    reg(S, "AccentColor", accentPicker)

    local CfgSec = SettingsTab:AddSection({Title = "Configs", Icon = "save", Collapsible = true})
    CfgSec:AddDropdown({ Title = "Config slot", Values = CONFIG_SLOTS, Default = SelectedSlot, Callback = function(value) SelectedSlot = value end })
    addButton(CfgSec, "Save config", function() saveConfig(SelectedSlot) end)
    addButton(CfgSec, "Load config", function() loadConfig(SelectedSlot, false) end)
    addButton(CfgSec, "Delete config", function() deleteConfig(SelectedSlot) end)
    addButton(CfgSec, "Set as autoload config", function() setAutoload(SelectedSlot) end)
    addButton(CfgSec, "Clear autoload", clearAutoload)

    UIBuilt = true
end

safeCall("autoload", autoloadConfig)

local uiOK, uiErr = pcall(buildUI)
if not uiOK then warn("[MINDHUB] UI build failed: " .. tostring(uiErr)) unload() return end

task.defer(function()
    UIReady = true
    if S.AccentSet then ThemeAPI.applyAccent(S.AccentColor) end
end)

pcall(function() RunService:UnbindFromRenderStep("MINDHUB_Update") end)
RunService:BindToRenderStep("MINDHUB_Update", Enum.RenderPriority.Camera.Value + 1, function()
    if Unloaded then return end
    safeCall("camera", updateCameraFeatures)
    if S.ESP then safeCall("esp", updateESP) end
    safeCall("mm2", mm2Update)
    safeCall("skeleton", updateSkeletons)
end)

notify("MINDHUB", "v0.1. Нажми RightShift, чтобы открыть меню.", "Success")
