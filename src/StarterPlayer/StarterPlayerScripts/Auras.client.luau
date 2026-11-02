-- LocalScript: StarterPlayer -> StarterPlayerScripts -> Auras
-- Окно выбора ауры. Список открытых аур и надетую присылает сервер, клиент только просит надеть.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local auraRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AuraRequest") :: RemoteFunction

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BG = Color3.fromRGB(20, 17, 26)
local ROW = Color3.fromRGB(38, 34, 46)
local TEXT = Color3.fromRGB(235, 235, 235)
local MUTED = Color3.fromRGB(170, 160, 185)
local EQUIP = Color3.fromRGB(110, 70, 170)
local LOCKED = Color3.fromRGB(60, 58, 66)

type AuraState = { Owned: { string }, Equipped: string }
local state: AuraState = { Owned = { Config.Auras.Starter }, Equipped = Config.Auras.Starter }

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font?): TextLabel
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

local function button(parent: Instance, name: string, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	return b
end

----------------------------------------------------------------
-- Построение
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Auras"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12

local openButton = button(gui, "OpenButton", "Ауры [O]", EQUIP)
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 16, 1, -260)
openButton.Size = UDim2.fromOffset(160, 40)

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromScale(0.92, 0.9)
window.BackgroundColor3 = BG
window.Visible = false
window.Parent = gui
corner(window, 12)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(620, 460)
limit.Parent = window

local title = label(window, "Title", UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 10), TEXT)
title.Text = "Ауры"
local info = label(window, "Info", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 44), MUTED, Enum.Font.GothamMedium)

local list = Instance.new("Frame")
list.Name = "List"
list.Position = UDim2.fromOffset(12, 70)
list.Size = UDim2.new(1, -24, 1, -132)
list.BackgroundTransparency = 1
list.Parent = window
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local closeButton = button(window, "Close", "Закрыть", Color3.fromRGB(70, 60, 75))
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -12)
closeButton.Size = UDim2.new(1, -24, 0, 44)

type Row = { Button: TextButton, Source: TextLabel, Stroke: UIStroke }
local rows: { [string]: Row } = {}
local busy = false
local render

local function request(action: string, name: string?)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return auraRequest:InvokeServer(action, name)
	end)
	busy = false
	if ok and type(result) == "table" and result.State then
		state = result.State
		render()
	end
end

for index, name in Config.Auras.Order do
	local aura = Config.Auras.Kinds[name]
	local rarity = Config.Rarities[aura.Rarity]
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = index
	row.Size = UDim2.new(1, 0, 1 / #Config.Auras.Order, -6)
	row.BackgroundColor3 = ROW
	row.Parent = list
	corner(row, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Parent = row

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 8, 0.5, 0)
	swatch.Size = UDim2.new(0, 10, 0.7, 0)
	swatch.BackgroundColor3 = rarity.Color
	swatch.Parent = row
	corner(swatch, 4)

	local name_ = label(row, "Title", UDim2.new(0.6, -28, 0.45, 0), UDim2.new(0, 26, 0.08, 0), TEXT)
	name_.Text = aura.Title
	local source = label(row, "Source", UDim2.new(0.6, -28, 0.32, 0), UDim2.new(0, 26, 0.58, 0), MUTED, Enum.Font.GothamMedium)

	local action = button(row, "Action", "", EQUIP)
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -8, 0.5, 0)
	action.Size = UDim2.new(0.34, 0, 0.72, 0)
	action.Activated:Connect(function()
		if table.find(state.Owned, name) and state.Equipped ~= name then
			request("equip", name)
		end
	end)
	rows[name] = { Button = action, Source = source, Stroke = stroke }
end

gui.Parent = playerGui

----------------------------------------------------------------
-- Обновление
----------------------------------------------------------------
function render()
	info.Text = `Эликсиры: {player:GetAttribute("Elixirs") or 0} · Ауро-склянка в Деревне: {Config.Auras.FlaskCost} эликсиров`
	for name, row in rows do
		local aura = Config.Auras.Kinds[name]
		local rarity = Config.Rarities[aura.Rarity]
		local owned = table.find(state.Owned, name) ~= nil
		local equipped = state.Equipped == name

		if name == Config.Auras.Starter then
			row.Source.Text = `{rarity.Title} · стартовая`
		else
			row.Source.Text = `{rarity.Title} · за {aura.Rebirth}-е перерождение или склянка ({aura.Chance}%)`
		end
		row.Stroke.Thickness = if equipped then 3 else 1
		if equipped then
			row.Button.Text = "Надета"
			row.Button.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
			row.Button.AutoButtonColor = false
		elseif owned then
			row.Button.Text = "Надеть"
			row.Button.BackgroundColor3 = EQUIP
			row.Button.AutoButtonColor = true
		else
			row.Button.Text = "Закрыта"
			row.Button.BackgroundColor3 = LOCKED
			row.Button.AutoButtonColor = false
		end
	end
end

local function setOpen(open: boolean)
	window.Visible = open
	if open then
		for _, other in playerGui:GetChildren() do
			local otherWindow = other ~= gui and other:FindFirstChild("Window")
			if otherWindow and otherWindow:IsA("GuiObject") then
				otherWindow.Visible = false
			end
		end
		render()
		request("list")
	end
end

openButton.Activated:Connect(function()
	setOpen(not window.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.O then
		setOpen(not window.Visible)
	end
end)
player:GetAttributeChangedSignal("Elixirs"):Connect(function()
	if window.Visible then
		render()
	end
end)
-- Новая аура (за перерождение/склянку) — обновим список при следующем открытии
player:GetAttributeChangedSignal("Aura"):Connect(function()
	state.Equipped = player:GetAttribute("Aura") or state.Equipped
	if window.Visible then
		render()
	end
end)
