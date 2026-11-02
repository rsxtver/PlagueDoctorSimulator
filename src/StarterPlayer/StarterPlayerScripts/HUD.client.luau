-- LocalScript: StarterPlayer -> StarterPlayerScripts -> HUD
-- Интерфейс: шкала миазмов в маске, золото, всплывающие сообщения.
-- Данные берутся из атрибутов игрока, которые выставляет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local notifyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent

local COLORS = {
	info = Color3.fromRGB(235, 235, 235),
	good = Color3.fromRGB(130, 235, 120),
	warn = Color3.fromRGB(255, 120, 90),
}
local MIASMA_COLOR = Color3.fromRGB(120, 200, 60)
local MIASMA_FULL_COLOR = Color3.fromRGB(230, 80, 60)

----------------------------------------------------------------
-- Построение интерфейса
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- Панель слева снизу
local panel = Instance.new("Frame")
panel.Name = "Stats"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(260, 92)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 18)
panel.BackgroundTransparency = 0.25
panel.Parent = gui
corner(panel, 10)

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = panel

local goldLabel = label(panel, "Gold", UDim2.new(0.55, 0, 0, 24), UDim2.new(), Color3.fromRGB(255, 210, 80))
local elixirLabel = label(panel, "Elixirs", UDim2.new(0.45, 0, 0, 20), UDim2.new(0.55, 0, 0, 2), Color3.fromRGB(190, 140, 255))
elixirLabel.TextXAlignment = Enum.TextXAlignment.Right
local maskTitle = label(panel, "MaskTitle", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 30), COLORS.info)
maskTitle.Font = Enum.Font.GothamMedium
maskTitle.Text = "Миазмы в маске"

local barBack = Instance.new("Frame")
barBack.Name = "MiasmaBack"
barBack.Position = UDim2.fromOffset(0, 52)
barBack.Size = UDim2.new(1, 0, 0, 22)
barBack.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
barBack.Parent = panel
corner(barBack, 6)

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = MIASMA_COLOR
barFill.Parent = barBack
corner(barFill, 6)

local barText = label(barBack, "Text", UDim2.fromScale(1, 1), UDim2.new(), Color3.new(1, 1, 1))
barText.TextXAlignment = Enum.TextXAlignment.Center
barText.ZIndex = 2

-- Сообщения сверху по центру
local toasts = Instance.new("Frame")
toasts.Name = "Toasts"
toasts.AnchorPoint = Vector2.new(0.5, 0)
toasts.Position = UDim2.new(0.5, 0, 0, 60)
toasts.Size = UDim2.new(0.9, 0, 0, 200)
toasts.BackgroundTransparency = 1
toasts.Parent = gui

local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = toasts

-- Подсказка сверху
local hint = label(gui, "Hint", UDim2.new(0.9, 0, 0, 22), UDim2.new(0.05, 0, 0, 16), COLORS.info)
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.Font = Enum.Font.GothamMedium

gui.Parent = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- Обновление
----------------------------------------------------------------
local function refresh()
	local miasma = player:GetAttribute("Miasma") or 0
	local capacity = player:GetAttribute("MaskCapacity") or 1
	local gold = player:GetAttribute("Gold") or 0
	elixirLabel.Text = `Эликсиры: {player:GetAttribute("Elixirs") or 0}`
	local ratio = math.clamp(miasma / capacity, 0, 1)

	goldLabel.Text = `Золото: {gold}`
	barText.Text = `{miasma} / {capacity}`
	barFill.BackgroundColor3 = if ratio >= 1 then MIASMA_FULL_COLOR else MIASMA_COLOR
	TweenService:Create(barFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(ratio, 1) }):Play()

	if ratio >= 1 then
		hint.Text = "Маска полна! Неси миазмы в Аптеку (зелёная площадка)"
		hint.TextColor3 = COLORS.warn
	else
		hint.Text = "Кликай по заражённым жителям, чтобы лечить их и собирать миазмы"
		hint.TextColor3 = COLORS.info
	end
end

for _, attr in { "Miasma", "MaskCapacity", "Gold", "Elixirs" } do
	player:GetAttributeChangedSignal(attr):Connect(refresh)
end
refresh()

local toastCount = 0
notifyRemote.OnClientEvent:Connect(function(text: string, kind: string)
	toastCount += 1
	local toast = label(toasts, "Toast", UDim2.new(1, 0, 0, 30), UDim2.new(), COLORS[kind] or COLORS.info)
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.LayoutOrder = toastCount
	toast.Text = text
	toast.TextStrokeTransparency = 0.2

	task.delay(2, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		toast:Destroy()
	end)
end)
