-- =============================================================
-- Plague Doctor Simulator — АВТОУСТАНОВЩИК
-- Сгенерирован tools/build_installer.py, вручную не редактировать.
--
-- Как использовать:
--   1. Roblox Studio -> вкладка View -> Command Bar
--   2. Вставьте ВЕСЬ этот файл в Command Bar и нажмите Enter
--   3. Все папки, парты и скрипты появятся в Explorer
--
-- Повторный запуск безопасен: недостающее создаётся, код скриптов
-- обновляется до актуальной версии, ничего не дублируется.
-- Отменить установку: Ctrl+Z.
-- =============================================================

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local recording = ChangeHistoryService:TryBeginRecording("Install Plague Doctor Simulator")
local created, updated = 0, 0
local N = {} -- созданные объекты (таблица, а не locals: у Luau лимит 200 локальных)

local function ensure(parent: Instance, name: string, className: string, props: { [string]: any }?): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		warn(`[Installer] {existing:GetFullName()} имеет тип {existing.ClassName}, нужен {className}. Старый объект переименован в {name}_old`)
		existing.Name = name .. "_old"
	end
	local instance = Instance.new(className)
	instance.Name = name
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	instance.Parent = parent
	created += 1
	return instance
end

local function setSource(script: Instance, source: string)
	local luaScript = script :: LuaSourceContainer
	if (luaScript :: any).Source == source then
		return
	end
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(luaScript, function()
			return source
		end)
	end)
	if not ok then
		(luaScript :: any).Source = source
	end
	updated += 1
end

N[1] = game:GetService("ReplicatedStorage")
N[2] = ensure(N[1], "Remotes", "Folder")
N[3] = ensure(N[2], "Notify", "RemoteEvent")
N[4] = ensure(N[1], "Shared", "Folder")
N[5] = ensure(N[4], "Config", "ModuleScript")
setSource(N[5], [[
-- ModuleScript: ReplicatedStorage -> Shared -> Config
-- Все игровые числа в одном месте (читают и сервер, и клиент).

local Config = {}

-- Маска: сколько миазмов вмещает на каждом уровне улучшения
Config.Mask = {
	BaseCapacity = 50,
	CapacityPerLevel = 1.6, -- множитель за каждый уровень выше первого
}

-- Инструмент (ланцет): сколько заражения снимает один удар
Config.Tool = {
	BasePower = 2,
	PowerPerLevel = 1.5,
	Cooldown = 0.2, -- секунд между ударами (защита от автокликеров)
	MaxDistance = 20, -- дальше этого лечить нельзя
}

-- Заражённые жители деревни
Config.Infected = {
	MaxCount = 8, -- сколько одновременно в деревне
	Infection = 10, -- «здоровье» болезни
	CureBonus = 5, -- доп. миазмы за полное исцеление
	RespawnDelay = 4, -- секунд до появления нового больного
	SpawnCenter = Vector3.new(0, 0, -25),
	SpawnSize = Vector2.new(70, 30), -- ширина по X и глубина по Z
	MinSpacing = 6,
}

-- Аптека: обмен миазмов на золото
Config.Pharmacy = {
	GoldPerMiasma = 1,
}

local function scaled(base: number, perLevel: number, level: number): number
	return math.floor(base * perLevel ^ (math.max(level, 1) - 1) + 0.5)
end

function Config.GetMaskCapacity(level: number): number
	return scaled(Config.Mask.BaseCapacity, Config.Mask.CapacityPerLevel, level)
end

function Config.GetToolPower(level: number): number
	return scaled(Config.Tool.BasePower, Config.Tool.PowerPerLevel, level)
end

return Config
]])
N[6] = game:GetService("ServerScriptService")
N[7] = ensure(N[6], "MainServer", "Script")
setSource(N[7], [[
-- Script: ServerScriptService -> MainServer
-- Точка входа сервера: запускает все сервисы по порядку.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local InfectedService = require(Services:WaitForChild("InfectedService"))
local PharmacyService = require(Services:WaitForChild("PharmacyService"))

DataService.Init()
InfectedService.Init()
PharmacyService.Init()

print("[MainServer] Plague Doctor Simulator: сервер запущен")
]])
N[8] = ensure(N[6], "Services", "Folder")
N[9] = ensure(N[8], "DataService", "ModuleScript")
setSource(N[9], [[
-- ModuleScript: ServerScriptService -> Services -> DataService
-- Загрузка, хранение в памяти и сохранение данных игроков (только сервер).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}

----------------------------------------------------------------
-- Настройки
----------------------------------------------------------------
local DATASTORE_NAME = "PlagueDoctor_PlayerData_v1" -- смена имени = «вайп» всех данных
local KEY_PREFIX = "Player_"
local AUTOSAVE_INTERVAL = 120 -- секунд между автосохранениями
local MAX_RETRIES = 5

----------------------------------------------------------------
-- Шаблон данных нового игрока
----------------------------------------------------------------
export type PlayerData = {
	Version: number,
	Miasma: number, -- миазмы в маске (сейчас)
	Gold: number, -- основная валюта
	Elixirs: number, -- вторая валюта из Аптеки
	Rebirths: number, -- «Новые эпидемии»
	Skulls: number, -- Чумные черепа (за перерождения)
	LivesSaved: number, -- для лидерборда «Спасено жизней»
	Upgrades: { Mask: number, Tool: number, Cloak: number },
	Pets: { [string]: any }, -- [petId] = { Name, Tier, ... }
	EquippedPets: { string },
}

local TEMPLATE: PlayerData = {
	Version = 1,
	Miasma = 0,
	Gold = 0,
	Elixirs = 0,
	Rebirths = 0,
	Skulls = 0,
	LivesSaved = 0,
	Upgrades = { Mask = 1, Tool = 1, Cloak = 1 },
	Pets = {},
	EquippedPets = {},
}

-- Что показывать в таблице игроков: ключ в данных -> подпись
local LEADERSTATS = {
	{ Key = "Gold", Name = "Золото" },
	{ Key = "LivesSaved", Name = "Спасено" },
	{ Key = "Rebirths", Name = "Перерождения" },
}

----------------------------------------------------------------
-- Внутреннее состояние
----------------------------------------------------------------
type Profile = {
	Data: PlayerData,
	Stats: { [string]: IntValue },
}

local IS_STUDIO = RunService:IsStudio()

-- В неопубликованном месте или без «Enable Studio Access to API Services»
-- DataStore недоступен. В Studio тогда играем без сохранений, на живом сервере — ошибка.
local store: DataStore? = nil
local memoryMode = false
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	elseif IS_STUDIO then
		memoryMode = true
		warn(`[DataService] DataStore недоступен ({result}). Studio: игра без сохранений.`)
	else
		error(result)
	end
end

local profiles: { [Player]: Profile } = {}
local activeSaves = 0
local initialized = false

----------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------
local function deepCopy(original: any): any
	if type(original) ~= "table" then
		return original
	end
	local copy = {}
	for key, value in original do
		copy[key] = deepCopy(value)
	end
	return copy
end

-- Дописывает в старые сохранения поля, добавленные в шаблон позже
local function reconcile(data: any, template: any)
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

-- Повторяет запрос к DataStore с паузами 1, 2, 4, 8 сек
local function withRetries(label: string, callback: () -> any, maxRetries: number?): (boolean, any)
	local attempts = maxRetries or MAX_RETRIES
	local lastError
	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		warn(`[DataService] {label}: попытка {attempt}/{attempts} не удалась — {result}`)
		if attempt < attempts then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

----------------------------------------------------------------
-- Загрузка / сохранение
----------------------------------------------------------------
local function loadData(player: Player): PlayerData?
	if memoryMode then
		return deepCopy(TEMPLATE)
	end
	local key = KEY_PREFIX .. player.UserId
	local ok, stored = withRetries(`Загрузка {player.Name}`, function()
		return (store :: DataStore):GetAsync(key)
	end, if IS_STUDIO then 1 else nil)
	if not ok then
		if IS_STUDIO then
			-- Скорее всего выключен доступ к API. Не сохраняем, чтобы не затереть прогресс.
			memoryMode = true
			warn("[DataService] Studio: загрузка не удалась, играем без сохранений. Включите Game Settings -> Security -> Enable Studio Access to API Services")
			return deepCopy(TEMPLATE)
		end
		return nil
	end

	local data = if type(stored) == "table" then stored else deepCopy(TEMPLATE)
	reconcile(data, TEMPLATE)
	return data
end

local function saveData(userId: number, name: string, data: PlayerData): boolean
	if memoryMode then
		return true
	end
	activeSaves += 1
	local ok = withRetries(`Сохранение {name}`, function()
		return (store :: DataStore):UpdateAsync(KEY_PREFIX .. userId, function()
			return data, { userId } -- userId привязывается к ключу (для GDPR-запросов)
		end)
	end)
	activeSaves -= 1
	return ok
end

-- Убирает профиль из памяти и сохраняет его. Повторный вызов ничего не делает,
-- поэтому PlayerRemoving и BindToClose не сохранят игрока дважды.
local function releaseProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	saveData(player.UserId, player.Name, profile.Data)
end

----------------------------------------------------------------
-- Leaderstats и атрибуты (клиент читает атрибуты для UI)
----------------------------------------------------------------
local function syncKey(player: Player, profile: Profile, key: string)
	local value = (profile.Data :: any)[key]
	if type(value) ~= "number" then
		return
	end
	player:SetAttribute(key, value)
	local stat = profile.Stats[key]
	if stat then
		stat.Value = value
	end
end

local function createLeaderstats(player: Player, profile: Profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats" -- имя строго в нижнем регистре
	for _, entry in LEADERSTATS do
		local stat = Instance.new("IntValue")
		stat.Name = entry.Name
		stat.Parent = folder
		profile.Stats[entry.Key] = stat
	end
	folder.Parent = player
end

----------------------------------------------------------------
-- События игроков
----------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local data = loadData(player)

	if player.Parent == nil then
		return -- игрок вышел, пока грузились данные
	end
	if not data then
		-- Не пускаем играть «с нуля», иначе пустые данные перезапишут прогресс
		player:Kick("Не удалось загрузить сохранение. Перезайдите — ваш прогресс в безопасности.")
		return
	end

	local profile: Profile = { Data = data, Stats = {} }
	profiles[player] = profile
	createLeaderstats(player, profile)
	for key in data do
		syncKey(player, profile, key)
	end
	player:SetAttribute("DataLoaded", true)
end

----------------------------------------------------------------
-- Публичный API для других серверных скриптов
----------------------------------------------------------------

-- Вся таблица данных (nil, если ещё не загружена). Не храните ссылку надолго.
function DataService.Get(player: Player): PlayerData?
	local profile = profiles[player]
	return profile and profile.Data
end

-- Ждёт загрузки данных игрока. nil — если игрок вышел или истёк таймаут.
function DataService.WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] do
		if player.Parent == nil or os.clock() > deadline then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player].Data
end

function DataService.Set(player: Player, key: string, value: any)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data: any = profile.Data
	data[key] = value
	syncKey(player, profile, key)
end

-- Прибавляет delta к числовому полю. Возвращает новое значение или nil.
function DataService.Increment(player: Player, key: string, delta: number): number?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local data: any = profile.Data
	local current = data[key]
	if type(current) ~= "number" then
		warn(`[DataService] Поле "{key}" не числовое`)
		return nil
	end
	local newValue = current + delta
	data[key] = newValue
	syncKey(player, profile, key)
	return newValue
end

function DataService.Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do -- игроки, зашедшие до Init
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(releaseProfile)

	-- Автосохранение
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				task.spawn(saveData, player.UserId, player.Name, profile.Data)
				task.wait(0.5) -- разносим запросы, чтобы не упереться в лимиты
			end
		end
	end)

	-- Сохранение при выключении сервера (до 30 сек)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(releaseProfile, player)
		end
		while activeSaves > 0 do
			task.wait()
		end
	end)
end

return DataService
]])
N[10] = ensure(N[8], "InfectedService", "ModuleScript")
setSource(N[10], [[
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
]])
N[11] = ensure(N[8], "Notify", "ModuleScript")
setSource(N[11], [[
-- ModuleScript: ServerScriptService -> Services -> Notify
-- Всплывающие сообщения игроку (показывает HUD на клиенте).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent

-- kind: "info" | "good" | "warn" — влияет на цвет сообщения
return function(player: Player, text: string, kind: string?)
	remote:FireClient(player, text, kind or "info")
end
]])
N[12] = ensure(N[8], "PharmacyService", "ModuleScript")
setSource(N[12], [[
-- ModuleScript: ServerScriptService -> Services -> PharmacyService
-- Аптека: встал на зелёную площадку — миазмы из маски обменялись на золото.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local PharmacyService = {}

local SELL_COOLDOWN = 1
local lastSell: { [Player]: number } = {}
local initialized = false

-- Продаёт все миазмы игрока. Возвращает полученное золото (0 — нечего продавать).
function PharmacyService.Sell(player: Player): number
	local data = DataService.Get(player)
	if not data or data.Miasma <= 0 then
		return 0
	end
	local now = os.clock()
	if now - (lastSell[player] or 0) < SELL_COOLDOWN then
		return 0
	end
	lastSell[player] = now

	local gold = math.floor(data.Miasma * Config.Pharmacy.GoldPerMiasma)
	DataService.Set(player, "Miasma", 0)
	DataService.Increment(player, "Gold", gold)
	notify(player, `Аптека: +{gold} золота`, "good")
	return gold
end

local function decorate(sellPart: BasePart)
	if sellPart:FindFirstChild("Sign") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.MaxDistance = 150
	gui.Parent = sellPart

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Fantasy
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(120, 230, 120)
	title.TextStrokeTransparency = 0.2
	title.Text = "АПТЕКА"
	title.Parent = gui

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(1, 0.4)
	hint.Position = UDim2.fromScale(0, 0.6)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextScaled = true
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextStrokeTransparency = 0.3
	hint.Text = "Встань сюда, чтобы продать миазмы"
	hint.Parent = gui
end

function PharmacyService.Init()
	if initialized then
		return
	end
	initialized = true

	local pharmacy = workspace:WaitForChild("Zones"):WaitForChild("Village"):WaitForChild("Pharmacy")
	local sellPart = pharmacy:WaitForChild("SellPart") :: BasePart
	decorate(sellPart)

	sellPart.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			PharmacyService.Sell(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSell[player] = nil
	end)
end

return PharmacyService
]])
N[13] = game:GetService("StarterPlayer")
N[14] = ensure(N[13], "StarterPlayerScripts", "StarterPlayerScripts")
N[15] = ensure(N[14], "HUD", "LocalScript")
setSource(N[15], [[
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

local goldLabel = label(panel, "Gold", UDim2.new(1, 0, 0, 24), UDim2.new(), Color3.fromRGB(255, 210, 80))
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

for _, attr in { "Miasma", "MaskCapacity", "Gold" } do
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
]])
N[16] = game:GetService("ServerStorage")
N[17] = ensure(N[16], "NPCTemplates", "Folder")
N[18] = ensure(N[16], "PetModels", "Folder")
N[19] = game:GetService("Workspace")
N[20] = ensure(N[19], "Zones", "Folder")
N[21] = ensure(N[20], "Village", "Folder")
N[22] = ensure(N[21], "Infected", "Folder")
N[23] = ensure(N[21], "Pharmacy", "Folder")
N[24] = ensure(N[23], "SellPart", "Part", { Anchored = true, CanCollide = false, Transparency = 0.5, Size = Vector3.new(12, 1, 12), Position = Vector3.new(0, 0.5, 30), Color = Color3.new(0.25, 0.85, 0.35), Material = Enum.Material.Neon })

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(`[Installer] Готово! Создано объектов: {created}, обновлено скриптов: {updated}`)
print("[Installer] Не забудьте: Game Settings -> Security -> Enable Studio Access to API Services")
