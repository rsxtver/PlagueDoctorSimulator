-- ModuleScript: ServerScriptService -> Services -> InfectedService
-- Заражённые жители: R15-риги со стандартными анимациями idle/walk. Бродят по зоне,
-- кашляют, лечатся кликом (миазмы в маску), при выздоровлении светятся и убегают.
-- Всё считает сервер; клиенту уходит только событие TreatFeedback для эффектов.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))
local PetService = require(script.Parent:WaitForChild("PetService"))

local InfectedService = {}

local SKIN_SICK = Color3.fromRGB(140, 170, 95)
local SKIN_HEALTHY = Color3.fromRGB(234, 190, 150)
local SHIRT = Color3.fromRGB(105, 85, 65)
local PANTS = Color3.fromRGB(70, 60, 50)
local FULL_WARN_INTERVAL = 2

-- Стандартные анимации Roblox для R15 (принадлежат Roblox, работают в любой игре)
local ANIM_IDLE = "rbxassetid://507766666"
local ANIM_WALK = "rbxassetid://507777826"
local ANIM_RUN = "rbxassetid://507767714"

local WANDER_SPEED = 5
local RUN_AWAY_SPEED = 22

local treatFeedback = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TreatFeedback") :: RemoteEvent

local folder: Folder
local template: Model? = nil
local alive: { [Model]: boolean } = {}
local lastHit: { [Player]: number } = {}
local lastFullWarn: { [Player]: number } = {}
local initialized = false
local random = Random.new()

----------------------------------------------------------------
-- Шаблон рига (создаётся один раз, дальше клонируется)
----------------------------------------------------------------
local function buildTemplate(): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN_SICK
	description.LeftArmColor = SKIN_SICK
	description.RightArmColor = SKIN_SICK
	description.TorsoColor = SHIRT
	description.LeftLegColor = PANTS
	description.RightLegColor = PANTS
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		error(`[InfectedService] Не удалось создать R15-риг: {rig}`)
	end
	rig.Name = "Infected"
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = WANDER_SPEED
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	-- Стандартный скрипт Animate нам не нужен: анимации включаем сами
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("Skin", part.Color == SKIN_SICK)
		end
	end
	return rig
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

local function decorate(model: Model)
	local head = model:FindFirstChild("Head") :: BasePart
	local torso = model:FindFirstChild("UpperTorso") :: BasePart

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

	-- Облачко кашля (выпускается порциями через Emit)
	local mouth = Instance.new("Attachment")
	mouth.Name = "Mouth"
	mouth.Position = Vector3.new(0, -0.1, -0.7)
	mouth.Parent = head
	local cough = Instance.new("ParticleEmitter")
	cough.Name = "Cough"
	cough.Texture = "rbxasset://textures/particles/smoke_main.dds"
	cough.Enabled = false
	cough.Color = ColorSequence.new(Color3.fromRGB(130, 220, 70), Color3.fromRGB(80, 150, 40))
	cough.Transparency = NumberSequence.new(0.3, 1)
	cough.Size = NumberSequence.new(0.4, 1.8)
	cough.Lifetime = NumberRange.new(0.8, 1.4)
	cough.Speed = NumberRange.new(3, 5)
	cough.SpreadAngle = Vector2.new(25, 25)
	cough.EmissionDirection = Enum.NormalId.Front
	cough.Parent = mouth

	-- Полоска заражения над головой
	local gui = Instance.new("BillboardGui")
	gui.Name = "InfectionGui"
	gui.Size = UDim2.fromOffset(120, 34)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
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
end

----------------------------------------------------------------
-- Анимации и поведение
----------------------------------------------------------------
local function loadTrack(animator: Animator, id: string, priority: Enum.AnimationPriority): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = true
	return track
end

local function randomPointNear(position: Vector3): Vector3
	local cfg = Config.Infected
	local half = Vector3.new(cfg.SpawnSize.X / 2, 0, cfg.SpawnSize.Y / 2)
	local target = position + Vector3.new(random:NextNumber(-12, 12), 0, random:NextNumber(-12, 12))
	local min, max = cfg.SpawnCenter - half, cfg.SpawnCenter + half
	return Vector3.new(math.clamp(target.X, min.X, max.X), position.Y, math.clamp(target.Z, min.Z, max.Z))
end

-- Сустав рига: у Motor6D двигаем C0, у новых AnimationConstraint — CFrame их Attachment0.
-- Возвращает (объект, имя свойства) или nil.
local function jointHandle(model: Instance, name: string): (Instance?, string?)
	local joint = model:FindFirstChild(name, true)
	if joint and joint:IsA("Motor6D") then
		return joint, "C0"
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint.Attachment0, "CFrame"
	end
	return nil, nil
end

-- Кашель: наклон вперёд в поясе и зелёное облачко
local function cough(model: Model)
	local waist, prop = jointHandle(model, "Waist")
	local emitter = model:FindFirstChild("Cough", true) :: ParticleEmitter?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not waist or not prop or not emitter or not humanoid then
		return
	end
	local base = waist:GetAttribute("BasePose") :: CFrame? or (waist :: any)[prop]
	waist:SetAttribute("BasePose", base)
	humanoid:MoveTo((model.PrimaryPart :: BasePart).Position) -- остановиться
	local bend = TweenService:Create(waist, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { [prop] = base * CFrame.Angles(math.rad(-30), 0, 0) })
	bend:Play()
	bend.Completed:Wait()
	if alive[model] then
		emitter:Emit(14)
	end
	task.wait(0.35)
	TweenService:Create(waist, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { [prop] = base }):Play()
end

local function runBehaviour(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local idle = loadTrack(animator, ANIM_IDLE, Enum.AnimationPriority.Idle)
	local walk = loadTrack(animator, ANIM_WALK, Enum.AnimationPriority.Movement)
	idle:Play()

	humanoid.Running:Connect(function(speed)
		if not alive[model] then
			-- Выздоровевший бежит со своей анимацией бега
			if walk.IsPlaying then
				walk:Stop(0.1)
			end
			return
		end
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.2)
			end
			walk:AdjustSpeed(speed / 12)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)

	task.spawn(function()
		task.wait(random:NextNumber(0, 3))
		while alive[model] and model.Parent do
			if random:NextNumber() < 0.3 then
				cough(model)
				task.wait(random:NextNumber(1, 2))
			else
				humanoid:MoveTo(randomPointNear((model.PrimaryPart :: BasePart).Position))
				task.wait(random:NextNumber(3, 6))
			end
		end
	end)
end

----------------------------------------------------------------
-- Появление
----------------------------------------------------------------
local function pickSpawnPosition(): Vector3
	local cfg = Config.Infected
	local best = cfg.SpawnCenter
	for _ = 1, 15 do
		local candidate = cfg.SpawnCenter
			+ Vector3.new(random:NextNumber(-0.5, 0.5) * cfg.SpawnSize.X, 0, random:NextNumber(-0.5, 0.5) * cfg.SpawnSize.Y)
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

function spawnInfected()
	if not template then
		return nil
	end
	local model = template:Clone()
	decorate(model)
	model:SetAttribute("Infection", Config.Infected.Infection)
	model:SetAttribute("MaxInfection", Config.Infected.Infection)
	setBar(model)

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local rootHeight = humanoid.HipHeight + (model.PrimaryPart :: BasePart).Size.Y / 2
	local yaw = random:NextNumber(0, math.pi * 2)
	model:PivotTo(CFrame.new(pickSpawnPosition() + Vector3.new(0, rootHeight, 0)) * CFrame.Angles(0, yaw, 0))

	alive[model] = true;
	(model:FindFirstChildOfClass("ClickDetector") :: ClickDetector).MouseClick:Connect(function(player)
		InfectedService.Treat(player, model)
	end)
	model.Parent = folder
	pcall(function()
		(model.PrimaryPart :: BasePart):SetNetworkOwner(nil) -- физику NPC считает сервер
	end)
	runBehaviour(model)
	return model
end

-- Выздоровление: выпрямиться, засветиться, радостно убежать
local function cure(model: Model, player: Player)
	alive[model] = nil
	local click = model:FindFirstChildOfClass("ClickDetector")
	if click then
		click:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BillboardGui") or (d:IsA("ParticleEmitter") and d.Name == "Miasma") then
			d:Destroy()
		elseif d:IsA("BasePart") and d:GetAttribute("Skin") then
			d.Color = SKIN_HEALTHY
		end
	end
	-- Выпрямляется
	local waist, prop = jointHandle(model, "Waist")
	if waist and prop and waist:GetAttribute("BasePose") then
		TweenService:Create(waist, TweenInfo.new(0.2), { [prop] = waist:GetAttribute("BasePose") }):Play()
	end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 240, 170)
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Color3.fromRGB(255, 255, 220)
	highlight.Parent = model
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 180)
	light.Brightness = 2
	light.Range = 10
	light.Parent = model.PrimaryPart

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0.1)
	end
	humanoid.Jump = true
	task.delay(0.5, function()
		if not model.Parent then
			return
		end
		loadTrack(animator, ANIM_RUN, Enum.AnimationPriority.Movement):Play(0.1)
		humanoid.WalkSpeed = RUN_AWAY_SPEED
		-- Убегает прочь от доктора
		local from = model:GetPivot().Position
		local character = player.Character
		local doctor = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local away = if doctor then (from - doctor.Position) * Vector3.new(1, 0, 1) else Vector3.new(0, 0, -1)
		if away.Magnitude < 0.1 then
			away = Vector3.new(0, 0, -1)
		end
		humanoid:MoveTo(from + away.Unit * 45)
	end)
	task.delay(3, function()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(highlight, TweenInfo.new(0.6), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		task.wait(0.7)
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

	-- Миазмы удара с множителем питомцев (бонус за исцеление — без множителя)
	local gained = math.min(PetService.ApplyMultiplier(player, damage), space)
	local cured = infection <= 0
	if cured then
		local bonus = math.min(Config.Infected.CureBonus, space - gained)
		gained += bonus
		DataService.Increment(player, "LivesSaved", 1)
		notify(player, `Исцелён! +{bonus} миазмов в награду`, "good")
		cure(model, player)
	end
	DataService.Increment(player, "Miasma", gained)
	-- Только визуал: взмах, «+N миазмов», частицы лечения
	treatFeedback:FireClient(player, model, gained, cured)
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

	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		lastFullWarn[player] = nil
	end)

	-- Создание рига ждёт загрузку ассетов — не задерживаем запуск остальных сервисов
	task.spawn(function()
		template = buildTemplate()
		for _ = 1, Config.Infected.MaxCount do
			spawnInfected()
		end
	end)
end

return InfectedService
