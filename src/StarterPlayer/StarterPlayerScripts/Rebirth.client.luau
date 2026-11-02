-- LocalScript: StarterPlayer -> StarterPlayerScripts -> Rebirth
-- Окно «Новая эпидемия»: что сбросится, что получишь, подтверждение.
-- Проверку цены и сам сброс делает сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local rebirthRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Rebirth") :: RemoteFunction

local player = Players.LocalPlayer

local BG = Color3.fromRGB(22, 18, 26)
local ACCENT = Color3.fromRGB(150, 90, 200)
local CONFIRM = Color3.fromRGB(160, 50, 70)
local DISABLED = Color3.fromRGB(70, 70, 70)
local TEXT = Color3.fromRGB(235, 235, 235)
local MUTED = Color3.fromRGB(175, 165, 185)
local GOLD = Color3.fromRGB(255, 210, 80)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, name: string, height: number, y: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = UDim2.new(1, -32, 0, height)
	l.Position = UDim2.fromOffset(16, y)
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamMedium
	l.TextScaled = true
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, label: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.Parent = parent
	corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	return b
end

----------------------------------------------------------------
-- Построение
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Rebirth"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11 -- поверх HUD и магазина

-- Кнопка над «Улучшениями»
local openButton = button(gui, "OpenButton", "Новая эпидемия", ACCENT)
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 16, 1, -164)
openButton.Size = UDim2.fromOffset(160, 40)

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0.92, 0, 0, 300)
window.BackgroundColor3 = BG
window.Visible = false
window.Parent = gui
corner(window, 12)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(480, 300)
limit.Parent = window
local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT
stroke.Thickness = 2
stroke.Parent = window

local title = text(window, "Title", 32, 12, TEXT, Enum.Font.GothamBold)
title.Text = "Новая эпидемия"

local countLabel = text(window, "Count", 20, 54, MUTED)
local multiplierLabel = text(window, "Multiplier", 22, 86, GOLD)
local skullsLabel = text(window, "Skulls", 22, 114, TEXT)
local resetLabel = text(window, "Reset", 18, 146, Color3.fromRGB(255, 140, 120))
resetLabel.Text = "Сбросятся: золото, миазмы и все апгрейды"
local costLabel = text(window, "Cost", 22, 180, TEXT, Enum.Font.GothamBold)

-- Кнопки внизу: правый верхний угол экрана занят таблицей игроков Roblox
local confirmButton = button(window, "Confirm", "", CONFIRM)
confirmButton.AnchorPoint = Vector2.new(0, 1)
confirmButton.Position = UDim2.new(0, 16, 1, -16)
confirmButton.Size = UDim2.new(0.66, -24, 0, 50)

local closeButton = button(window, "Close", "Отмена", Color3.fromRGB(70, 60, 80))
closeButton.AnchorPoint = Vector2.new(1, 1)
closeButton.Position = UDim2.new(1, -16, 1, -16)
closeButton.Size = UDim2.new(0.34, -8, 0, 50)

gui.Parent = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- Обновление
----------------------------------------------------------------
local function refresh()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local skulls = player:GetAttribute("Skulls") or 0
	local gold = player:GetAttribute("Gold") or 0
	local cost = Config.GetRebirthCost(rebirths)
	local enough = gold >= cost

	countLabel.Text = `Перерождений: {rebirths}`
	multiplierLabel.Text = `Золото в Аптеке: x{Config.GetGoldMultiplier(rebirths)} → x{Config.GetGoldMultiplier(rebirths + 1)}`
	skullsLabel.Text = `Чумные черепа: {skulls} → {skulls + Config.Rebirth.SkullsPerRebirth}`
	costLabel.Text = `Нужно золота: {gold} / {cost}`
	confirmButton.Text = if enough then "Начать новую эпидемию" else "Не хватает золота"
	confirmButton.BackgroundColor3 = if enough then CONFIRM else DISABLED
	confirmButton.AutoButtonColor = enough
end

for _, attr in { "Rebirths", "Skulls", "Gold" } do
	player:GetAttributeChangedSignal(attr):Connect(refresh)
end
refresh()

local busy = false
confirmButton.Activated:Connect(function()
	if busy then
		return
	end
	busy = true
	local ok, success = pcall(function()
		return rebirthRemote:InvokeServer() -- сообщение покажет HUD
	end)
	if ok and success then
		window.Visible = false
	end
	busy = false
end)

openButton.Activated:Connect(function()
	window.Visible = not window.Visible
	refresh()
	-- Одно окно за раз: закрываем магазин
	local other = player.PlayerGui:FindFirstChild("Shop")
	local otherWindow = other and other:FindFirstChild("Window")
	if window.Visible and otherWindow then
		(otherWindow :: Frame).Visible = false
	end
end)
closeButton.Activated:Connect(function()
	window.Visible = false
end)
