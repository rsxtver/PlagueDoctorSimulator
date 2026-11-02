-- LocalScript: StarterPlayer -> StarterPlayerScripts -> Shop
-- Окно апгрейдов: кнопка «Улучшения» и карточки Маски, Ланцета и Плаща.
-- Клиент только показывает цены и отправляет запрос — покупку проверяет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteFunction

local player = Players.LocalPlayer

local BG = Color3.fromRGB(20, 22, 18)
local CARD = Color3.fromRGB(38, 40, 34)
local GOLD = Color3.fromRGB(255, 210, 80)
local BUY = Color3.fromRGB(70, 150, 60)
local BUY_DISABLED = Color3.fromRGB(70, 70, 70)
local TEXT = Color3.fromRGB(235, 235, 235)
local MUTED = Color3.fromRGB(170, 170, 160)

local EFFECT_FORMAT = {
	Mask = function(v: number) return `{v} миазмов` end,
	Tool = function(v: number) return `{v} за клик` end,
	Cloak = function(v: number) return `скорость {v}` end,
}

----------------------------------------------------------------
-- Утилиты UI
----------------------------------------------------------------
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

----------------------------------------------------------------
-- Построение
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Shop"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10 -- окно поверх HUD

-- Кнопка над панелью статистики (левый нижний угол)
local openButton = Instance.new("TextButton")
openButton.Name = "OpenButton"
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 16, 1, -116)
openButton.Size = UDim2.fromOffset(160, 40)
openButton.BackgroundColor3 = Color3.fromRGB(120, 85, 40)
openButton.Font = Enum.Font.GothamBold
openButton.TextScaled = true
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.Text = "Улучшения [E]"
openButton.Parent = gui
corner(openButton, 8)
local buttonPadding = Instance.new("UIPadding")
buttonPadding.PaddingTop = UDim.new(0, 8)
buttonPadding.PaddingBottom = UDim.new(0, 8)
buttonPadding.Parent = openButton

-- Окно по центру
local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0.92, 0, 0, 330)
window.BackgroundColor3 = BG
window.BackgroundTransparency = 0.05
window.Visible = false
window.Parent = gui
corner(window, 12)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(640, 330)
sizeLimit.Parent = window

local title = text(window, "Title", UDim2.new(1, -80, 0, 32), UDim2.fromOffset(16, 12), TEXT)
title.Text = "Снаряжение доктора"

local goldLabel = text(window, "Gold", UDim2.new(0.5, 0, 0, 22), UDim2.fromOffset(16, 48), GOLD, Enum.Font.GothamMedium)

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Size = UDim2.fromOffset(36, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 45)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 20
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.Parent = window
corner(closeButton, 8)

local cards = Instance.new("Frame")
cards.Name = "Cards"
cards.Position = UDim2.fromOffset(12, 82)
cards.Size = UDim2.new(1, -24, 1, -94)
cards.BackgroundTransparency = 1
cards.Parent = window

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = cards

type Card = { Level: TextLabel, Effect: TextLabel, Button: TextButton }
local cardByName: { [string]: Card } = {}

for index, name in Config.Upgrades.Order do
	local info = Config.Upgrades[name]
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = index
	card.Size = UDim2.new(1, 0, 0, 70)
	card.BackgroundColor3 = CARD
	card.Parent = cards
	corner(card, 8)

	local cardTitle = text(card, "Title", UDim2.new(0.6, -12, 0, 24), UDim2.fromOffset(12, 8), TEXT)
	cardTitle.Text = info.Title
	local level = text(card, "Level", UDim2.new(0.6, -12, 0, 16), UDim2.fromOffset(12, 32), MUTED, Enum.Font.GothamMedium)
	local effect = text(card, "Effect", UDim2.new(0.6, -12, 0, 16), UDim2.fromOffset(12, 48), MUTED, Enum.Font.GothamMedium)

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0.38, 0, 0, 46)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = card
	corner(button, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = button

	cardByName[name] = { Level = level, Effect = effect, Button = button }

	local busy = false
	button.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		pcall(function()
			buyRemote:InvokeServer(name) -- результат покажет всплывающее сообщение HUD
		end)
		busy = false
	end)
end

gui.Parent = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- Обновление
----------------------------------------------------------------
local function refresh()
	local gold = player:GetAttribute("Gold") or 0
	goldLabel.Text = `Золото: {gold}`

	for name, card in cardByName do
		local info = Config.Upgrades[name]
		local level = player:GetAttribute(`Upgrade_{name}`) or 1
		local cost = Config.GetUpgradeCost(name, level)
		local format = EFFECT_FORMAT[name]
		local current = format(Config.GetUpgradeValue(name, level))

		card.Level.Text = `{info.Description} · ур. {level}/{info.MaxLevel}`
		if cost then
			card.Effect.Text = `{current} → {format(Config.GetUpgradeValue(name, level + 1))}`
			card.Button.Text = `Купить: {cost}`
			card.Button.BackgroundColor3 = if gold >= cost then BUY else BUY_DISABLED
			card.Button.AutoButtonColor = gold >= cost
		else
			card.Effect.Text = current
			card.Button.Text = "Максимум"
			card.Button.BackgroundColor3 = BUY_DISABLED
			card.Button.AutoButtonColor = false
		end
	end
end

player:GetAttributeChangedSignal("Gold"):Connect(refresh)
for _, name in Config.Upgrades.Order do
	player:GetAttributeChangedSignal(`Upgrade_{name}`):Connect(refresh)
end
refresh()

local function setOpen(open: boolean)
	window.Visible = open
	if open then
		refresh()
	end
end

openButton.Activated:Connect(function()
	setOpen(not window.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.E then
		setOpen(not window.Visible)
	end
end)
