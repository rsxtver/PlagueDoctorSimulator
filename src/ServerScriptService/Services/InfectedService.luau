-- ModuleScript: ServerScriptService -> Services -> InfectedService
-- Заражённые жители: появление в деревне, лечение кликом, сбор миазмов в маску.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local InfectedService = {}

local SKIN_SICK = Color3.fromRGB(140, 165, 95)
local SKIN_HEALTHY = Color3.fromRGB(234, 190, 150)
local CLOTH = Color3.fromRGB(105, 85, 65)
local FULL_WARN_INTERVAL = 2

local folder: Folder
local alive: { [Model]: boolean } = {}
local lastHit: { [Player]: number } = {}
local lastFullWarn: { [Player]: number } = {}
local initialized = false
local random = Random.new()

----------------------------------------------------------------
-- Снаряжение игрока (атрибуты читает HUD)
----------------------------------------------------------------
function InfectedService.RefreshEquipment(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("MaskCapacity", Config.GetMaskCapacity(data.Upgrades.Mask))
	player:SetAttribute("ToolPower", Config.GetToolPower(data.Upgrades.Tool))
end

----------------------------------------------------------------
-- Модель больного
----------------------------------------------------------------
local function part(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = CFrame.new(offset)
	p:SetAttribute("Skin", color == SKIN_SICK)
	p.Parent = model
	return p
end

local function setBar(model: Model)
	local bar = model:FindFirstChild("Bar", true) :: Frame?
	local label = model:FindFirstChild("BarText", true) :: TextLabel?
	local infection = model:GetAttribute("Infection") :: number
	local max = model:GetAttribute("MaxInfection") :: number
	if bar then
		bar.Size = UDim2.fromScale(math.clamp(infection / max, 0, 1), 1)
	end
	if label then
		label.Text = `Заражение {infection}/{max}`
	end
end

local function buildInfected(): Model
	local model = Instance.new("Model")
	model.Name = "Infected"

	local torso = part(model, "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), CLOTH)
	local head = part(model, "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), SKIN_SICK)
	part(model, "LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), SKIN_SICK)
	part(model, "RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), SKIN_SICK)
	part(model, "LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), CLOTH)
	part(model, "RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), CLOTH)
	model.PrimaryPart = torso

	-- Зелёные миазмы вокруг больного
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Miasma"
	particles.Color = ColorSequence.new(Color3.fromRGB(120, 200, 60))
	particles.Transparency = NumberSequence.new(0.4, 1)
	particles.Size = NumberSequence.new(0.6, 1.4)
	particles.Lifetime = NumberRange.new(1.5, 2.5)
	particles.Speed = NumberRange.new(0.5, 1.5)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rate = 4
	particles.Parent = torso

	-- Полоска заражения над головой
	local gui = Instance.new("BillboardGui")
	gui.Name = "InfectionGui"
	gui.Size = UDim2.fromOffset(120, 34)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = true
	gui.Parent = head

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 0, 10)
	back.Position = UDim2.fromScale(0, 1)
	back.AnchorPoint = Vector2.new(0, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	Instance.new("UICorner").Parent = back

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromRGB(120, 200, 60)
	bar.BorderSizePixel = 0
	bar.Parent = back
	Instance.new("UICorner").Parent = bar

	local text = Instance.new("TextLabel")
	text.Name = "BarText"
	text.Size = UDim2.new(1, 0, 1, -12)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Parent = gui

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = Config.Tool.MaxDistance
	click.Parent = model

	model:SetAttribute("Infection", Config.Infected.Infection)
	model:SetAttribute("MaxInfection", Config.Infected.Infection)
	setBar(model)
	return model
end

----------------------------------------------------------------
-- Появление
----------------------------------------------------------------
local function pickSpawnPosition(): Vector3
	local cfg = Config.Infected
	local best = cfg.SpawnCenter
	for _ = 1, 15 do
		local candidate = cfg.SpawnCenter
			+ Vector3.new(
				random:NextNumber(-0.5, 0.5) * cfg.SpawnSize.X,
				0,
				random:NextNumber(-0.5, 0.5) * cfg.SpawnSize.Y
			)
		local free = true
		for other in alive do
			local pos = other:GetPivot().Position
			if (Vector3.new(pos.X, 0, pos.Z) - candidate).Magnitude < cfg.MinSpacing then
				free = false
				break
			end
		end
		best = candidate
		if free then
			break
		end
	end
	return best
end

local spawnInfected -- объявлено заранее: cure() вызывает его через таймер

local function onClicked(player: Player, model: Model)
	InfectedService.Treat(player, model)
end

function spawnInfected()
	local model = buildInfected()
	local yaw = random:NextNumber(0, math.pi * 2)
	-- Пивот модели — центр торса, поднимаем его так, чтобы ноги стояли на земле
	local height = model:GetPivot().Position.Y
	model:PivotTo(CFrame.new(pickSpawnPosition() + Vector3.new(0, height, 0)) * CFrame.Angles(0, yaw, 0))
	alive[model] = true;
	(model:FindFirstChildOfClass("ClickDetector") :: ClickDetector).MouseClick:Connect(function(player)
		onClicked(player, model)
	end)
	model.Parent = folder
	return model
end

local function cure(model: Model)
	alive[model] = nil
	local click = model:FindFirstChildOfClass("ClickDetector")
	if click then
		click:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") and d:GetAttribute("Skin") then
			d.Color = SKIN_HEALTHY
		end
	end
	task.delay(1.5, function()
		model:Destroy()
	end)
	task.delay(Config.Infected.RespawnDelay, function()
		if initialized then
			spawnInfected()
		end
	end)
end

----------------------------------------------------------------
-- Лечение
----------------------------------------------------------------

-- Один удар ланцетом. Возвращает, сколько миазмов получил игрок (0 — удар не засчитан).
function InfectedService.Treat(player: Player, model: Model): number
	if not alive[model] then
		return 0
	end
	local data = DataService.Get(player)
	if not data then
		return 0
	end

	local now = os.clock()
	if now - (lastHit[player] or 0) < Config.Tool.Cooldown then
		return 0
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - model:GetPivot().Position).Magnitude > Config.Tool.MaxDistance + 5 then
		return 0
	end

	local capacity = Config.GetMaskCapacity(data.Upgrades.Mask)
	local space = capacity - data.Miasma
	if space <= 0 then
		if now - (lastFullWarn[player] or 0) > FULL_WARN_INTERVAL then
			lastFullWarn[player] = now
			notify(player, "Маска полна! Отнеси миазмы в Аптеку", "warn")
		end
		return 0
	end
	lastHit[player] = now

	local infection = model:GetAttribute("Infection") :: number
	local damage = math.min(Config.GetToolPower(data.Upgrades.Tool), infection)
	infection -= damage
	model:SetAttribute("Infection", infection)
	setBar(model)

	local gained = math.min(damage, space)
	if infection <= 0 then
		local bonus = math.min(Config.Infected.CureBonus, space - gained)
		gained += bonus
		DataService.Increment(player, "LivesSaved", 1)
		notify(player, `Исцелён! +{bonus} миазмов в награду`, "good")
		cure(model)
	end
	DataService.Increment(player, "Miasma", gained)
	return gained
end

-- Список живых больных (для тестов и будущих систем)
function InfectedService.GetAlive(): { Model }
	local list = {}
	for model in alive do
		table.insert(list, model)
	end
	return list
end

function InfectedService.Init()
	if initialized then
		return
	end
	initialized = true

	folder = workspace:WaitForChild("Zones"):WaitForChild("Village"):WaitForChild("Infected") :: Folder
	folder:ClearAllChildren()

	local function onPlayerAdded(player: Player)
		if DataService.WaitForData(player) then
			InfectedService.RefreshEquipment(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		lastFullWarn[player] = nil
	end)

	for _ = 1, Config.Infected.MaxCount do
		spawnInfected()
	end
end

return InfectedService
