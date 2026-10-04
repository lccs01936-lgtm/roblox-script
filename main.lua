-- =======================================================
-- 載入 Rayfield UI 框架
-- =======================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- 取得常用系統服務 (Services)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- 變數開關狀態 (States)
local AimbotEnabled = false
local ESPEnabled = false
local AimKey = Enum.UserInputType.MouseButton2 -- 預設右鍵鎖頭

-- =======================================================
-- 1. ESP (透視功能) 邏輯
-- =======================================================
local Highlights = {}

local function ApplyESP(player)
    if player == LocalPlayer then return end
    
    local function AddHighlight(character)
        if not character then return end
        if not character:FindFirstChildOfClass("Highlight") then
            local highlight = Instance.new("Highlight")
            highlight.Name = "ESPHighlight"
            highlight.Adornee = character
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.FillTransparency = 0.5
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.OutlineTransparency = 0
            highlight.Parent = character
            Highlights[player] = highlight
        end
    end

    if player.Character then
        AddHighlight(player.Character)
    end
    
    player.CharacterAdded:Connect(function(newCharacter)
        if ESPEnabled then
            task.wait(0.5)
            AddHighlight(newCharacter)
        end
    end)
end

local function ToggleESP(state)
    ESPEnabled = state
    if ESPEnabled then
        for _, player in ipairs(Players:GetPlayers()) do
            ApplyESP(player)
        end
    else
        for player, highlight in pairs(Highlights) do
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
        end
        table.clear(Highlights)
    end
end

-- 新玩家加入時自動套用 ESP
Players.PlayerAdded:Connect(function(player)
    if ESPEnabled then
        ApplyESP(player)
    end
end)

-- =======================================================
-- 2. Aimbot (鎖頭功能) 邏輯
-- =======================================================
local function GetClosestPlayer()
    local closestPlayer = nil
    local shortestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
            local head = player.Character.Head
            local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
            
            if onScreen then
                local mousePos = UserInputService:GetMouseLocation()
                local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                
                if distance < shortestDistance and distance < 300 then -- 鎖頭範圍 (FOV)
                    shortestDistance = distance
                    closestPlayer = player
                end
            end
        end
    end
    return closestPlayer
end

RunService.RenderStepped:Connect(function()
    if AimbotEnabled and UserInputService:IsMouseButtonPressed(AimKey) then
        local target = GetClosestPlayer()
        if target and target.Character and target.Character:FindFirstChild("Head") then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, target.Character.Head.Position)
        end
    end
end)

-- =======================================================
-- 3. UI 選單介面建立
-- =======================================================
local Window = Rayfield:CreateWindow({
    Name = "Mobile Hub | 全功能選單",
    LoadingTitle = "腳本載入中...",
    LoadingSubtitle = "by Roblox Developer",
    ConfigurationSaving = { Enabled = false }
})

-- 分頁 1：主要戰鬥功能 (Lock & ESP)
local CombatTab = Window:CreateTab("戰鬥功能", 4483362458)

CombatTab:CreateToggle({
    Name = "自動鎖頭 (Aimbot - 按住右鍵/瞄準)",
    CurrentValue = false,
    Flag = "AimbotToggle",
    Callback = function(Value)
        AimbotEnabled = Value
    end,
})

CombatTab:CreateToggle({
    Name = "玩家透視 (ESP Highlight)",
    CurrentValue = false,
    Flag = "ESPToggle",
    Callback = function(Value)
        ToggleESP(Value)
    end,
})

-- 分頁 2：角色移動與傳送 (Speed / Anti-Flash / TP)
local MovementTab = Window:CreateTab("移動與傳送", 4483362458)

MovementTab:CreateSlider({
    Name = "移動速度 (Speed / 防閃光高速移動)",
    Range = {16, 150},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "SpeedSlider",
    Callback = function(Value)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = Value
        end
    end,
})

MovementTab:CreateButton({
    Name = "傳送至最近玩家 (TP to Nearest Player)",
    Callback = function()
        local target = GetClosestPlayer()
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
                Rayfield:Notify({
                    Title = "傳送成功",
                    Content = "已傳送至玩家: " .. target.Name,
                    Duration = 2,
                    Image = 4483362458,
                })
            end
        else
            Rayfield:Notify({
                Title = "傳送失敗",
                Content = "附近沒有找到可傳送的玩家！",
                Duration = 2,
                Image = 4483362458,
            })
        end
    end,
})
