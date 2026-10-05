-- =======================================================
-- 重複載入防護 (Prevent Duplicate Execution)
-- =======================================================
if getgenv().UnloadMobileHub then
    getgenv().UnloadMobileHub()
end

-- 載入 Rayfield UI 框架
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- 取得常用系統服務
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("CurrentCamera")

-- 變數設定
local AimbotEnabled = false
local WallCheck = true
local TeamCheck = true
local Smoothness = 0.25
local MaxFOV = 150
local AimKey = Enum.UserInputType.MouseButton2
local AimAlwaysActive = false
local ESPEnabled = false
local CustomSpeed = 16
local LockSpeed = false

-- 管理員偵測配置
local AutoLeaveOnAdmin = true
local AdminUserIds = { [12345678] = true }
local AdminGroupConfig = { GroupId = 0, MinRank = 100 }

-- 快取與資源管理
local AdminCache = {}
local Highlights = {}
local PlayerConnections = {}
local ScriptConnections = {}

-- 複用 RaycastParams 與 Filter Table (優化 GC 垃圾回收)
local SharedRaycastParams = RaycastParams.new()
SharedRaycastParams.FilterType = RaycastFilterType.Exclude
SharedRaycastParams.IgnoreWater = true
local RaycastFilterBuffer = table.create(2)

-- FOV Drawing 圈圈
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1.5
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Filled = false
FOVCircle.Transparency = 0.7
FOVCircle.Visible = false
FOVCircle.Radius = MaxFOV

-- 卸載清理腳本
local function UnloadScript()
    FOVCircle:Remove()
    
    for player, highlight in pairs(Highlights) do
        if highlight and highlight.Parent then highlight:Destroy() end
    end
    table.clear(Highlights)
    
    for _, conn in ipairs(ScriptConnections) do
        if conn and conn.Connected then conn:Disconnect() end
    end
    table.clear(ScriptConnections)
    
    for player, conns in pairs(PlayerConnections) do
        for _, conn in ipairs(conns) do
            if conn and conn.Connected then conn:Disconnect() end
        end
    end
    table.clear(PlayerConnections)

    getgenv().MobileHubLoaded = nil
    getgenv().UnloadMobileHub = nil
end
getgenv().UnloadMobileHub = UnloadScript
getgenv().MobileHubLoaded = true

-- 取得當前瞄準參考點
local function GetTargetAimPosition()
    if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
        return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    end
    return UserInputService:GetMouseLocation()
end

-- =======================================================
-- 0. 管理員偵測邏輯 (防止重複網路請求)
-- =======================================================
local function CheckAdminStatusAsync(player, callback)
    if not player or player == LocalPlayer then return end
    
    if AdminCache[player] ~= nil then
        if AdminCache[player] ~= "Pending" then
            callback(AdminCache[player])
        end
        return
    end

    if AdminUserIds[player.UserId] then
        AdminCache[player] = true
        callback(true)
        return
    end

    if AdminGroupConfig.GroupId > 0 then
        AdminCache[player] = "Pending" -- 標記為查詢中，防止重複觸發請求
        task.spawn(function()
            local success, rank = pcall(function()
                return player:GetRankInGroup(AdminGroupConfig.GroupId)
            end)
            local isAdmin = success and (rank >= AdminGroupConfig.MinRank)
            AdminCache[player] = isAdmin
            callback(isAdmin)
        end)
    else
        AdminCache[player] = false
        callback(false)
    end
end

local function HandleAdminDetection(player)
    if not AutoLeaveOnAdmin or player == LocalPlayer then return end
    CheckAdminStatusAsync(player, function(isAdmin)
        if isAdmin then
            Rayfield:Notify({
                Title = "⚠️ 警報：管理員進場",
                Content = "偵測到管理員: " .. player.Name .. "！正在自動離開...",
                Duration = 3,
                Image = 4483362458,
            })
            task.wait(0.5)
            LocalPlayer:Kick("\n[防護系統] 偵測到管理員 (" .. player.Name .. ") 加入伺服器，已自動斷開連線。")
        end
    end)
end

-- =======================================================
-- 1. ESP 功能優化 (Highlight 物件池化重用)
-- =======================================================
local function CleanupHighlight(player)
    if Highlights[player] then
        Highlights[player].Enabled = false
    end
end

local function ApplyESP(player)
    if player == LocalPlayer or not ESPEnabled then return end
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        CleanupHighlight(player)
        return
    end

    if TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
        CleanupHighlight(player)
        return
    end

    local highlight = Highlights[player]
    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.Name = "ESPHighlight"
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Parent = character
        Highlights[player] = highlight
    else
        highlight.Adornee = character
        highlight.Parent = character
    end

    local teamColor = player.TeamColor and player.TeamColor.Color or Color3.fromRGB(255, 50, 50)
    highlight.FillColor = teamColor
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Enabled = true
end

local function ToggleESP(state)
    ESPEnabled = state
    for _, player in ipairs(Players:GetPlayers()) do
        if state then 
            ApplyESP(player) 
        else 
            CleanupHighlight(player) 
        end
    end
end

-- 玩家監聽事件
local function SetupPlayerListeners(player)
    if player == LocalPlayer then return end
    PlayerConnections[player] = {}

    local charAddedConn = player.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid", 5)
        if ESPEnabled then ApplyESP(player) end
    end)

    local teamConn = player:GetPropertyChangedSignal("Team"):Connect(function()
        if ESPEnabled then ApplyESP(player) end
    end)

    table.insert(PlayerConnections[player], charAddedConn)
    table.insert(PlayerConnections[player], teamConn)

    if player.Character then ApplyESP(player) end
    HandleAdminDetection(player)
end

for _, player in ipairs(Players:GetPlayers()) do
    SetupPlayerListeners(player)
end

table.insert(ScriptConnections, Players.PlayerAdded:Connect(SetupPlayerListeners))
table.insert(ScriptConnections, Players.PlayerRemoving:Connect(function(player)
    if Highlights[player] then
        Highlights[player]:Destroy()
        Highlights[player] = nil
    end
    AdminCache[player] = nil
    if PlayerConnections[player] then
        for _, conn in ipairs(PlayerConnections[player]) do
            if conn and conn.Connected then conn:Disconnect() end
        end
        PlayerConnections[player] = nil
    end
end))

-- =======================================================
-- 2. Aimbot (鎖頭邏輯：極致效能優化版)
-- =======================================================
local function IsVisible(targetHead)
    if not WallCheck then return true end
    if not targetHead or not LocalPlayer.Character then return false end
    
    local origin = Camera.CFrame.Position
    local direction = targetHead.Position - origin
    
    -- 重用緩衝區避免每幀分配 Table 產生垃圾
    RaycastFilterBuffer[1] = LocalPlayer.Character
    RaycastFilterBuffer[2] = targetHead.Parent
    SharedRaycastParams.FilterDescendantsInstances = RaycastFilterBuffer
    
    local result = Workspace:Raycast(origin, direction, SharedRaycastParams)
    return result == nil
end

local function IsValidBasicTarget(player)
    if not player or player == LocalPlayer then return false end
    if TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then return false end
    local char = player.Character
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local head = char:FindFirstChild("Head")
    return humanoid and humanoid.Health > 0 and head ~= nil
end

-- 優化：先比對平方距離，選出唯一候選人後「僅執行 1 次 Raycast」
local function GetClosestPlayer(aimPos)
    local closestPlayer = nil
    local shortestDistanceSq = MaxFOV * MaxFOV -- 使用平方距離避免 math.sqrt 計算
    local candidateHead = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if IsValidBasicTarget(player) then
            local head = player.Character.Head
            local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
            if onScreen then
                local deltaX = screenPos.X - aimPos.X
                local deltaY = screenPos.Y - aimPos.Y
                local distSq = deltaX * deltaX + deltaY * deltaY
                
                if distSq < shortestDistanceSq then
                    shortestDistanceSq = distSq
                    closestPlayer = player
                    candidateHead = head
                end
            end
        end
    end

    -- 僅對最終最接近的玩家執行 1 次牆壁檢查
    if closestPlayer and candidateHead then
        if IsVisible(candidateHead) then
            return closestPlayer
        end
    end

    return nil
end

-- 主 Loop (RenderStepped)
table.insert(ScriptConnections, RunService.RenderStepped:Connect(function(deltaTime)
    local aimPos = GetTargetAimPosition()
    FOVCircle.Position = aimPos
    FOVCircle.Radius = MaxFOV
    FOVCircle.Visible = AimbotEnabled

    local isAiming = false
    if AimbotEnabled then
        if AimAlwaysActive then
            isAiming = true
        elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
            isAiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        else
            isAiming = UserInputService:IsMouseButtonPressed(AimKey)
        end
    end

    if isAiming then
        local target = GetClosestPlayer(aimPos)
        if target and target.Character and target.Character:FindFirstChild("Head") then
            local targetPos = target.Character.Head.Position
            local currentCFrame = Camera.CFrame
            local targetCFrame = CFrame.new(currentCFrame.Position, targetPos)
            
            -- Frame-rate independent lerp
            local factor = math.clamp(1 - math.pow(1 - Smoothness, deltaTime * 60), 0.01, 1)
            Camera.CFrame = currentCFrame:Lerp(targetCFrame, factor)
        end
    end
end))

-- 移動速度處理
local function HandleCharacterAdded(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    humanoid.WalkSpeed = CustomSpeed
    
    local speedConn
    speedConn = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if LockSpeed and humanoid.WalkSpeed ~= CustomSpeed then
            humanoid.WalkSpeed = CustomSpeed
        end
    end)
    
    character.AncestryChanged:Connect(function(_, parent)
        if not parent and speedConn then
            speedConn:Disconnect()
            speedConn = nil
        end
    end)
end

if LocalPlayer.Character then HandleCharacterAdded(LocalPlayer.Character) end
table.insert(ScriptConnections, LocalPlayer.CharacterAdded:Connect(HandleCharacterAdded))

-- =======================================================
-- 3. UI 建構 (Rayfield)
-- =======================================================
local Window = Rayfield:CreateWindow({
    Name = "Mobile Hub | 效能優化完全版",
    LoadingTitle = "載入中...",
    LoadingSubtitle = "by Roblox Developer",
    ConfigurationSaving = { Enabled = false }
})

local ProtectionTab = Window:CreateTab("安全防護", 4483362458)
ProtectionTab:CreateToggle({
    Name = "偵測管理員自動退出",
    CurrentValue = AutoLeaveOnAdmin,
    Flag = "AutoLeaveToggle",
    Callback = function(Value) AutoLeaveOnAdmin = Value end,
})

local CombatTab = Window:CreateTab("戰鬥功能", 4483362458)
CombatTab:CreateToggle({
    Name = "自動鎖頭 (Aimbot)",
    CurrentValue = AimbotEnabled,
    Flag = "AimbotToggle",
    Callback = function(Value) AimbotEnabled = Value end,
})
CombatTab:CreateToggle({
    Name = "持續鎖頭 (適合移動端)",
    CurrentValue = AimAlwaysActive,
    Flag = "MobileAimToggle",
    Callback = function(Value) AimAlwaysActive = Value end,
})
CombatTab:CreateToggle({
    Name = "牆壁檢查 (Wall Check)",
    CurrentValue = WallCheck,
    Flag = "WallCheckToggle",
    Callback = function(Value) WallCheck = Value end,
})
CombatTab:CreateToggle({
    Name = "隊友檢查 (Team Check)",
    CurrentValue = TeamCheck,
    Flag = "TeamCheckToggle",
    Callback = function(Value)
        TeamCheck = Value
        if ESPEnabled then ToggleESP(true) end
    end,
})
CombatTab:CreateSlider({
    Name = "鎖頭範圍 (FOV Radius)",
    Range = {50, 800},
    Increment = 10,
    Suffix = "px",
    CurrentValue = MaxFOV,
    Flag = "FOVRadiusSlider",
    Callback = function(Value) MaxFOV = Value end,
})
CombatTab:CreateSlider({
    Name = "鎖頭平滑度 (Smoothness)",
    Range = {0.05, 1},
    Increment = 0.05,
    Suffix = "Speed",
    CurrentValue = Smoothness,
    Flag = "SmoothSlider",
    Callback = function(Value) Smoothness = Value end,
})
CombatTab:CreateToggle({
    Name = "玩家透視 (ESP)",
    CurrentValue = ESPEnabled,
    Flag = "ESPToggle",
    Callback = function(Value) ToggleESP(Value) end,
})

local MovementTab = Window:CreateTab("移動與傳送", 4483362458)
MovementTab:CreateSlider({
    Name = "移動速度 (WalkSpeed)",
    Range = {16, 150},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = CustomSpeed,
    Flag = "SpeedSlider",
    Callback = function(Value)
        CustomSpeed = Value
        local char = LocalPlayer.Character
        if char and char:FindFirstChildOfClass("Humanoid") then
            char:FindFirstChildOfClass("Humanoid").WalkSpeed = CustomSpeed
        end
    end,
})
MovementTab:CreateToggle({
    Name = "強制鎖定移速",
    CurrentValue = LockSpeed,
    Flag = "LockSpeedToggle",
    Callback = function(Value) LockSpeed = Value end,
})
MovementTab:CreateButton({
    Name = "傳送至最近敵人",
    Callback = function()
        local aimPos = GetTargetAimPosition()
        local target = GetClosestPlayer(aimPos)
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local localHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if localHRP then
                localHRP.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
                Rayfield:Notify({ Title = "傳送成功", Content = "已傳送至: " .. target.Name, Duration = 2 })
            end
        else
            Rayfield:Notify({ Title = "傳送失敗", Content = "未找到目標！", Duration = 2 })
        end
    end,
})
