-- LocalScript: StarterPlayer -> StarterPlayerScripts -> PetsUI
-- Инвентарь питомцев (Надеть/Снять) и анимация вылупления из яйца.
-- Клиент только показывает состояние, которое прислал сервер, и отправляет просьбы.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Models = require(Shared:WaitForChild("Models"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local petRequest = Remotes:WaitForChild("PetRequest") :: RemoteFunction
local eggHatched = Remotes:WaitForChild("EggHatched") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BG = Color3.fromRGB(18, 22, 24)
local CARD = Color3.fromRGB(34, 40, 42)
local TEXT = Color3.fromRGB(235, 235, 235)
local MUTED = Color3.fromRGB(165, 175, 175)
local EQUIP = Color3.fromRGB(70, 150, 60)
local UNEQUIP = Color3.fromRGB(150, 60, 55)

type PetState = { Pets: { { Id: string, Kind: string } }, Equipped: { string }, MaxEquipped: number, MaxInventory: number }
local state: PetState = { Pets = {}, Equipped = {}, MaxEquipped = Config.Pets.MaxEquipped, MaxInventory = Config.Pets.MaxInventory }

----------------------------------------------------------------
-- Утилиты UI
----------------------------------------------------------------
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

-- 3D-превью модели в ViewportFrame, камера смотрит в «перед» модели (-Z)
local function viewport(parent: Instance, modelName: string): (ViewportFrame, Model?)
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Ambient = Color3.fromRGB(170, 170, 170)
	frame.LightColor = Color3.fromRGB(255, 255, 255)
	frame.LightDirection = Vector3.new(-1, -1, -1)
	frame.Parent = parent
	local model = Models.Build(modelName)
	if model then
		model:PivotTo(CFrame.new())
		model.Parent = frame
		local center, size = model:GetBoundingBox()
		local distance = math.max(size.X, size.Y, size.Z) * 1.6
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(distance * 0.35, distance * 0.3, -distance), center.Position)
		camera.Parent = frame
		frame.CurrentCamera = camera
	end
	return frame, model
end

-- Одно окно за раз: закрываем окна других интерфейсов
local function closeOtherWindows(except: ScreenGui)
	for _, other in playerGui:GetChildren() do
		local window = other ~= except and other:FindFirstChild("Window")
		if window and window:IsA("GuiObject") then
			window.Visible = false
		end
	end
end

----------------------------------------------------------------
-- Окно инвентаря
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Pets"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12

local openButton = button(gui, "OpenButton", "Питомцы [P]", Color3.fromRGB(40, 110, 110))
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 16, 1, -212)
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
limit.MaxSize = Vector2.new(720, 460)
limit.Parent = window

local title = label(window, "Title", UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 10), TEXT)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Питомцы"
local info = label(window, "Info", UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 44), MUTED, Enum.Font.GothamMedium)
info.TextXAlignment = Enum.TextXAlignment.Left

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "List"
scroll.Position = UDim2.fromOffset(12, 70)
scroll.Size = UDim2.new(1, -24, 1, -132)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = window
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(130, 170)
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local empty = label(window, "Empty", UDim2.new(1, -32, 0, 24), UDim2.new(0, 16, 0.4, 0), MUTED, Enum.Font.GothamMedium)
empty.Text = "Питомцев пока нет — вылупи их из «Чумной склянки» в Деревне"

local closeButton = button(window, "Close", "Закрыть", Color3.fromRGB(70, 60, 60))
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -12)
closeButton.Size = UDim2.new(1, -24, 0, 44)

gui.Parent = playerGui

local busy = false
local render -- объявлено заранее: кнопки карточек перерисовывают список

local function request(action: string, id: string?)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return petRequest:InvokeServer(action, id)
	end)
	busy = false
	if ok and type(result) == "table" and result.State then
		state = result.State
		render()
	end
end

local function rarityRank(kind: string): number
	return table.find(Config.Pets.Order, kind) or 0
end

function render()
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local equippedKinds = {}
	for _, id in state.Equipped do
		for _, pet in state.Pets do
			if pet.Id == id then
				table.insert(equippedKinds, pet.Kind)
			end
		end
	end
	local petMult = Config.GetPetMultiplier(equippedKinds)
	local goldMult = Config.GetGoldMultiplier(player:GetAttribute("Rebirths") or 0)
	info.Text = `Надето {#state.Equipped}/{state.MaxEquipped} · Инвентарь {#state.Pets}/{state.MaxInventory} · `
		.. `Миазмы x{math.floor(petMult * 100 + 0.5) / 100} · Перерождения x{goldMult} · `
		.. `Итого x{math.floor(petMult * goldMult * 100 + 0.5) / 100}`
	empty.Visible = #state.Pets == 0

	-- Сначала надетые, потом по редкости
	local pets = table.clone(state.Pets)
	table.sort(pets, function(a, b)
		local ea, eb = table.find(state.Equipped, a.Id) ~= nil, table.find(state.Equipped, b.Id) ~= nil
		if ea ~= eb then
			return ea
		end
		return rarityRank(a.Kind) > rarityRank(b.Kind)
	end)

	for order, pet in pets do
		local kind = Config.Pets.Kinds[pet.Kind]
		if not kind then
			continue
		end
		local rarity = Config.Rarities[kind.Rarity]
		local equipped = table.find(state.Equipped, pet.Id) ~= nil

		local card = Instance.new("Frame")
		card.Name = pet.Id
		card.LayoutOrder = order
		card.BackgroundColor3 = CARD
		card.Parent = scroll
		corner(card, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = rarity.Color
		stroke.Thickness = if equipped then 3 else 1.5
		stroke.Parent = card

		local view = viewport(card, pet.Kind)
		view.Size = UDim2.new(1, -8, 0, 78)
		view.Position = UDim2.fromOffset(4, 4)

		local name = label(card, "Name", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(4, 84), TEXT)
		name.Text = kind.Title
		local sub = label(card, "Rarity", UDim2.new(1, -8, 0, 14), UDim2.fromOffset(4, 103), rarity.Color, Enum.Font.GothamMedium)
		sub.Text = `{rarity.Title} · x{kind.Multiplier}`

		local action = button(card, "Action", if equipped then "Снять" else "Надеть", if equipped then UNEQUIP else EQUIP)
		action.Position = UDim2.fromOffset(6, 124)
		action.Size = UDim2.new(1, -12, 0, 38)
		action.Activated:Connect(function()
			request(if equipped then "unequip" else "equip", pet.Id)
		end)
	end
end

local function setOpen(open: boolean)
	window.Visible = open
	if open then
		closeOtherWindows(gui)
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
	if not processed and input.KeyCode == Enum.KeyCode.P then
		setOpen(not window.Visible)
	end
end)

----------------------------------------------------------------
-- Анимация вылупления: яйцо трясётся → вспышка → карточка питомца
----------------------------------------------------------------
local hatchGui = Instance.new("ScreenGui")
hatchGui.Name = "Hatch"
hatchGui.ResetOnSpawn = false
hatchGui.DisplayOrder = 20
hatchGui.IgnoreGuiInset = true
hatchGui.Enabled = false
hatchGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.4
backdrop.Parent = hatchGui

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.ZIndex = 5
flash.Parent = hatchGui

local hatchQueue: { string } = {}
local hatching = false

local function playHatch(kind: string)
	local info = Config.Pets.Kinds[kind]
	local rarity = Config.Rarities[info.Rarity]
	hatchGui.Enabled = true

	-- 1. Яйцо трясётся всё сильнее
	local eggView, egg = viewport(hatchGui, "Egg")
	eggView.AnchorPoint = Vector2.new(0.5, 0.5)
	eggView.Position = UDim2.fromScale(0.5, 0.5)
	eggView.Size = UDim2.fromScale(0.5, 0.6)
	local start = os.clock()
	local SHAKE_TIME = 1.4
	while os.clock() - start < SHAKE_TIME do
		local t = (os.clock() - start) / SHAKE_TIME
		local angle = math.sin(os.clock() * (18 + 30 * t)) * math.rad(4 + 22 * t)
		if egg then
			egg:PivotTo(CFrame.Angles(0, 0, angle))
		else
			eggView.Rotation = math.deg(angle)
		end
		RunService.RenderStepped:Wait()
	end

	-- 2. Вспышка
	flash.BackgroundTransparency = 0
	eggView:Destroy()
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()

	-- 3. Карточка питомца с цветом редкости
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(0, 0)
	card.BackgroundColor3 = BG
	card.Parent = hatchGui
	corner(card, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Thickness = 4
	stroke.Parent = card

	local petView, pet = viewport(card, kind)
	petView.Size = UDim2.new(1, -20, 0.55, 0)
	petView.Position = UDim2.fromOffset(10, 10)
	local rarityLabel = label(card, "Rarity", UDim2.new(1, -20, 0.09, 0), UDim2.new(0, 10, 0.57, 0), rarity.Color)
	rarityLabel.Text = rarity.Title:upper()
	local nameLabel = label(card, "Name", UDim2.new(1, -20, 0.11, 0), UDim2.new(0, 10, 0.67, 0), TEXT)
	nameLabel.Text = info.Title
	local multLabel = label(card, "Mult", UDim2.new(1, -20, 0.07, 0), UDim2.new(0, 10, 0.79, 0), MUTED, Enum.Font.GothamMedium)
	multLabel.Text = `Миазмы x{info.Multiplier}`
	local ok = button(card, "Ok", "Отлично!", rarity.Color)
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -10)
	ok.Size = UDim2.new(0.7, 0, 0.1, 0)

	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(260, 340) }):Play()

	local closed = false
	ok.Activated:Connect(function()
		closed = true
	end)
	local shown = os.clock()
	while not closed and os.clock() - shown < 4 do
		if pet then
			pet:PivotTo(CFrame.Angles(0, (os.clock() - shown) * 1.5, 0))
		end
		RunService.RenderStepped:Wait()
	end
	card:Destroy()
	hatchGui.Enabled = false
end

eggHatched.OnClientEvent:Connect(function(kind: string, _id: string, newState: PetState)
	if type(newState) == "table" then
		state = newState
		if window.Visible then
			render()
		end
	end
	table.insert(hatchQueue, kind)
	if hatching then
		return
	end
	hatching = true
	while #hatchQueue > 0 do
		playHatch(table.remove(hatchQueue, 1) :: string)
	end
	hatching = false
end)
