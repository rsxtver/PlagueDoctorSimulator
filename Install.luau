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
local created, updated, removed = 0, 0, 0
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

local function removeObsolete(path: string)
	local instance: Instance? = game
	for _, name in string.split(path, "/") do
		instance = instance and instance:FindFirstChild(name)
	end
	if instance then
		instance.Parent = nil -- через Parent, а не Destroy: так работает Ctrl+Z
		removed += 1
	end
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
N[4] = ensure(N[2], "BuyUpgrade", "RemoteFunction")
N[5] = ensure(N[2], "Rebirth", "RemoteFunction")
N[6] = ensure(N[2], "PetRequest", "RemoteFunction")
N[7] = ensure(N[2], "EggHatched", "RemoteEvent")
N[8] = ensure(N[2], "AuraRequest", "RemoteFunction")
N[9] = ensure(N[2], "TreatFeedback", "RemoteEvent")
N[10] = ensure(N[2], "SellFeedback", "RemoteEvent")
N[11] = ensure(N[1], "Shared", "Folder")
N[12] = ensure(N[11], "AuraEffects", "ModuleScript")
setSource(N[12], [[
-- ModuleScript: ReplicatedStorage -> Shared -> AuraEffects
-- Внешний вид аур: Attachment в HumanoidRootPart + ParticleEmitter-ы + PointLight.
-- Вызывает сервер (эффект реплицируется всем игрокам); клиент может звать Apply для превью.

local AuraEffects = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local ATTACHMENT_NAME = "AuraAttachment"

type EmitterDef = { [string]: any }
type AuraDef = { Light: { Color: Color3, Brightness: number, Range: number }, Emitters: { EmitterDef } }

local function seq(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local points = {}
	for i, v in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(points)
end

local DEFS: { [string]: AuraDef } = {
	GreenFog = {
		Light = { Color = Color3.fromRGB(110, 220, 90), Brightness = 0.8, Range = 8 },
		Emitters = {
			{
				Texture = SMOKE, Rate = 14, Lifetime = NumberRange.new(1.5, 2.5),
				Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(180, 20),
				Size = seq(1.2, 2.6), Transparency = seq(0.6, 0.75, 1),
				Color = ColorSequence.new(Color3.fromRGB(90, 200, 70), Color3.fromRGB(50, 120, 40)),
				Offset = Vector3.new(0, -2.5, 0),
			},
		},
	},
	CrowFeathers = {
		Light = { Color = Color3.fromRGB(120, 100, 160), Brightness = 0.5, Range = 7 },
		Emitters = {
			{
				Texture = SPARKLE, Rate = 10, Lifetime = NumberRange.new(2, 3),
				Speed = NumberRange.new(0.5, 1.2), SpreadAngle = Vector2.new(180, 180),
				Size = seq(0.35, 0.3), Squash = seq(-1.2), Transparency = seq(0.1, 0.2, 1),
				Color = ColorSequence.new(Color3.fromRGB(25, 25, 35), Color3.fromRGB(60, 50, 80)),
				Acceleration = Vector3.new(0, -1.5, 0), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-90, 90),
				Offset = Vector3.new(0, 1, 0),
			},
		},
	},
	PoisonBubbles = {
		Light = { Color = Color3.fromRGB(170, 240, 60), Brightness = 1, Range = 9 },
		Emitters = {
			{
				Texture = SPARKLE, Rate = 12, Lifetime = NumberRange.new(1.5, 2.5),
				Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(25, 25),
				Size = seq(0.2, 0.6, 0.1), Transparency = seq(0.2, 0.4, 1),
				Color = ColorSequence.new(Color3.fromRGB(190, 250, 60), Color3.fromRGB(80, 200, 40)),
				LightEmission = 0.6,
				Offset = Vector3.new(0, -2.5, 0), EmissionDirection = Enum.NormalId.Top,
			},
		},
	},
	GhostFlame = {
		Light = { Color = Color3.fromRGB(90, 220, 255), Brightness = 1.6, Range = 10 },
		Emitters = {
			{
				Texture = FIRE, Rate = 22, Lifetime = NumberRange.new(0.8, 1.3),
				Speed = NumberRange.new(2, 3.5), SpreadAngle = Vector2.new(10, 10),
				Size = seq(1.2, 0.6, 0), Transparency = seq(0.3, 0.6, 1),
				Color = ColorSequence.new(Color3.fromRGB(150, 240, 255), Color3.fromRGB(40, 120, 255)),
				LightEmission = 1,
				Offset = Vector3.new(0, -2.5, 0), EmissionDirection = Enum.NormalId.Top,
			},
		},
	},
	RainbowPlague = {
		Light = { Color = Color3.fromRGB(255, 160, 255), Brightness = 1.8, Range = 11 },
		Emitters = {
			{
				Texture = SPARKLE, Rate = 25, Lifetime = NumberRange.new(1.2, 2),
				Speed = NumberRange.new(0.8, 1.6), SpreadAngle = Vector2.new(180, 180),
				Size = seq(0.6, 0.2), Transparency = seq(0, 1),
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
					ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 90)),
					ColorSequenceKeypoint.new(0.75, Color3.fromRGB(70, 140, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
				}),
				LightEmission = 1, RotSpeed = NumberRange.new(-180, 180), SpreadAngle = Vector2.new(180, 180),
			},
			{
				Texture = SMOKE, Rate = 6, Lifetime = NumberRange.new(2, 3),
				Speed = NumberRange.new(0.2, 0.5), Size = seq(1.5, 3), Transparency = seq(0.75, 1),
				Color = ColorSequence.new(Color3.fromRGB(120, 230, 100), Color3.fromRGB(190, 110, 255)),
				Offset = Vector3.new(0, -2.5, 0),
			},
		},
	},
}

-- Снимает ауру с персонажа
function AuraEffects.Remove(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local old = root and root:FindFirstChild(ATTACHMENT_NAME)
	if old then
		old:Destroy()
	end
end

-- Надевает ауру на персонажа (старая снимается). Неизвестное имя — просто снимает.
function AuraEffects.Apply(character: Model, auraName: string)
	AuraEffects.Remove(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local def = DEFS[auraName]
	if not root or not def then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment:SetAttribute("Aura", auraName)

	for _, e in def.Emitters do
		local holder: Instance = attachment
		if e.Offset then
			local sub = Instance.new("Attachment")
			sub.Name = "Offset"
			sub.Position = e.Offset
			sub.Parent = attachment
			holder = sub
		end
		local emitter = Instance.new("ParticleEmitter")
		for key, value in e do
			if key == "Offset" then
				continue
			end
			(emitter :: any)[key] = value
		end
		emitter.LockedToPart = false
		emitter.Parent = holder
	end

	local light = Instance.new("PointLight")
	light.Color = def.Light.Color
	light.Brightness = def.Light.Brightness
	light.Range = def.Light.Range
	light.Shadows = false
	light.Parent = attachment

	attachment.Parent = root
end

return AuraEffects
]])
N[13] = ensure(N[11], "GameConfig", "ModuleScript")
setSource(N[13], [[
-- ModuleScript: ReplicatedStorage -> Shared -> GameConfig
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
	MiasmaPerElixir = 25, -- 1 Эликсир за каждые 25 проданных миазмов
}

-- Перерождение «Новая эпидемия»: сброс золота, миазмов и апгрейдов
-- в обмен на Чумные черепа и постоянный множитель золота
Config.Rebirth = {
	BaseCost = 500, -- золото за первое перерождение
	CostGrowth = 2.5, -- каждое следующее дороже во столько раз
	GoldBonusPerRebirth = 0.5, -- +50% золота в Аптеке за каждое перерождение
	SkullsPerRebirth = 1,
}

-- Редкости: подпись и цвет (рамки карточек, вылупление)
Config.Rarities = {
	Common = { Title = "Обычный", Color = Color3.fromRGB(180, 180, 170) },
	Uncommon = { Title = "Необычный", Color = Color3.fromRGB(110, 200, 90) },
	Rare = { Title = "Редкий", Color = Color3.fromRGB(80, 150, 240) },
	Epic = { Title = "Эпический", Color = Color3.fromRGB(180, 90, 230) },
	Legendary = { Title = "Легендарный", Color = Color3.fromRGB(250, 190, 50) },
}

-- Питомцы из яйца «Чумная склянка». Chance — проценты (в сумме 100),
-- Multiplier — множитель миазмов за удар (надетые перемножаются)
Config.Pets = {
	EggCost = 100,
	MaxEquipped = 3,
	MaxInventory = 50,
	EggPosition = Vector3.new(-22, 0, 22), -- подставка с яйцом в Деревне
	Order = { "Raven", "Rat", "Bat", "Ghost", "Cat" },
	Kinds = {
		Raven = { Title = "Ворон", Chance = 50, Multiplier = 1.1, Rarity = "Common" },
		Rat = { Title = "Крыса-фамильяр", Chance = 30, Multiplier = 1.2, Rarity = "Uncommon" },
		Bat = { Title = "Летучая мышь", Chance = 13, Multiplier = 1.5, Rarity = "Rare" },
		Ghost = { Title = "Призрак", Chance = 6, Multiplier = 2, Rarity = "Epic" },
		Cat = { Title = "Чёрный кот", Chance = 1, Multiplier = 3, Rarity = "Legendary" },
	},
}

-- Ауры: косметика вокруг персонажа (вид — в Shared/AuraEffects). Надета одна.
-- Источники: стартовая, за N-е перерождение (Rebirth), из «Ауро-склянки» за Эликсиры (Chance, %).
-- VIP-аура за геймпасс появится позже.
Config.Auras = {
	Starter = "GreenFog",
	FlaskCost = 20, -- Эликсиров за одну Ауро-склянку
	DuplicateRefund = 5, -- Эликсиров назад, если выпала уже имеющаяся аура
	FlaskPosition = Vector3.new(22, 0, 22),
	Order = { "GreenFog", "CrowFeathers", "PoisonBubbles", "GhostFlame", "RainbowPlague" },
	Kinds = {
		GreenFog = { Title = "Зелёный туман", Rarity = "Common" },
		CrowFeathers = { Title = "Вороньи перья", Rarity = "Uncommon", Rebirth = 1, Chance = 45 },
		PoisonBubbles = { Title = "Ядовитые пузыри", Rarity = "Rare", Rebirth = 3, Chance = 33 },
		GhostFlame = { Title = "Призрачное пламя", Rarity = "Epic", Rebirth = 5, Chance = 17 },
		RainbowPlague = { Title = "Радужная чума", Rarity = "Legendary", Rebirth = 10, Chance = 5 },
	},
}

-- Плащ: скорость ходьбы
Config.Cloak = {
	BaseWalkSpeed = 16,
	WalkSpeedPerLevel = 2, -- прибавка за каждый уровень выше первого
}

-- Апгрейды за золото. Цена перехода с уровня L на L+1 = BaseCost * CostGrowth^(L-1)
Config.Upgrades = {
	Order = { "Mask", "Tool", "Cloak" }, -- порядок в магазине
	Mask = { Title = "Маска", Description = "Вместимость миазмов", BaseCost = 30, CostGrowth = 2.2, MaxLevel = 10 },
	Tool = { Title = "Ланцет", Description = "Сила лечения за клик", BaseCost = 40, CostGrowth = 2.4, MaxLevel = 10 },
	Cloak = { Title = "Плащ", Description = "Скорость ходьбы", BaseCost = 25, CostGrowth = 2.0, MaxLevel = 8 },
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

function Config.GetWalkSpeed(level: number): number
	return Config.Cloak.BaseWalkSpeed + Config.Cloak.WalkSpeedPerLevel * (math.max(level, 1) - 1)
end

-- Цена следующего перерождения при текущем числе перерождений
function Config.GetRebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths + 0.5)
end

-- Множитель золота в Аптеке (1 = без бонуса)
function Config.GetGoldMultiplier(rebirths: number): number
	return 1 + Config.Rebirth.GoldBonusPerRebirth * rebirths
end

-- Произведение множителей надетых питомцев (список видов)
function Config.GetPetMultiplier(kinds: { string }): number
	local multiplier = 1
	for _, kind in kinds do
		local info = Config.Pets.Kinds[kind]
		if info then
			multiplier *= info.Multiplier
		end
	end
	return multiplier
end

-- Значение эффекта апгрейда на уровне level (для магазина и сервера)
function Config.GetUpgradeValue(name: string, level: number): number
	if name == "Mask" then
		return Config.GetMaskCapacity(level)
	elseif name == "Tool" then
		return Config.GetToolPower(level)
	elseif name == "Cloak" then
		return Config.GetWalkSpeed(level)
	end
	error(`Неизвестный апгрейд: {name}`)
end

-- Цена следующего уровня или nil, если уровень максимальный
function Config.GetUpgradeCost(name: string, level: number): number?
	local info = Config.Upgrades[name]
	if not info or level >= info.MaxLevel then
		return nil
	end
	return math.floor(info.BaseCost * info.CostGrowth ^ (level - 1) + 0.5)
end

return Config
]])
N[14] = ensure(N[11], "Models", "ModuleScript")
setSource(N[14], [[
-- ModuleScript: ReplicatedStorage -> Shared -> Models
-- Выдаёт копии 3D-моделей (питомцы, яйцо) из папки ReplicatedStorage.Models.
-- Модели сгенерированы в Studio (generate_procedural_model) и хранятся в репозитории
-- как assets/Models.rbxm. Если папки нет (её не вставили), Build вернёт nil и код
-- покажет простую запасную фигуру.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = {}

local function getFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("Models")
end

-- Копия модели. Все детали заякорены и без коллизий, PrimaryPart — невидимый Root в центре,
-- «перед» модели смотрит в -Z (как у персонажа). nil, если такой модели нет.
function Models.Build(name: string): Model?
	local folder = getFolder()
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	return template:Clone()
end

function Models.Has(name: string): boolean
	local folder = getFolder()
	return folder ~= nil and folder:FindFirstChild(name) ~= nil
end

return Models
]])
if not N[1]:FindFirstChild("Models") then warn(`[Installer] Нет Models: ПКМ по {N[1]:GetFullName()} -> Insert from File -> assets/Models.rbxm`) end
N[15] = game:GetService("ServerScriptService")
N[16] = ensure(N[15], "MainServer", "Script")
setSource(N[16], [[
-- Script: ServerScriptService -> MainServer
-- Точка входа сервера: запускает все сервисы по порядку.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local InfectedService = require(Services:WaitForChild("InfectedService"))
local PharmacyService = require(Services:WaitForChild("PharmacyService"))
local UpgradeService = require(Services:WaitForChild("UpgradeService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local PetService = require(Services:WaitForChild("PetService"))
local AuraService = require(Services:WaitForChild("AuraService"))
local DoctorService = require(Services:WaitForChild("DoctorService"))

DataService.Init()
InfectedService.Init()
PharmacyService.Init()
UpgradeService.Init()
RebirthService.Init()
PetService.Init()
AuraService.Init()
DoctorService.Init()

print("[MainServer] Plague Doctor Simulator: сервер запущен")
]])
N[17] = ensure(N[15], "Services", "Folder")
N[18] = ensure(N[17], "AuraService", "ModuleScript")
setSource(N[18], [[
-- ModuleScript: ServerScriptService -> Services -> AuraService
-- Ауры: выдача (стартовая, за перерождения, из Ауро-склянки за Эликсиры), выбор одной,
-- показ эффекта на персонаже. Всё решает сервер; клиент только просит надеть.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local AuraEffects = require(Shared:WaitForChild("AuraEffects"))
local Models = require(Shared:WaitForChild("Models"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local AuraService = {}

local REQUEST_COOLDOWN = 0.2
local FLASK_COOLDOWN = 1
local auraRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AuraRequest") :: RemoteFunction

local lastRequest: { [Player]: number } = {}
local lastFlask: { [Player]: number } = {}
local initialized = false
local random = Random.new()

----------------------------------------------------------------
-- Внутреннее
----------------------------------------------------------------
local function snapshot(data: any)
	local owned = {}
	for name in data.Auras do
		if Config.Auras.Kinds[name] then
			table.insert(owned, name)
		end
	end
	return { Owned = owned, Equipped = data.EquippedAura }
end

-- Эффект на персонаже + атрибут Aura (его читает GUI)
local function applyVisual(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Aura", data.EquippedAura)
	if player.Character then
		AuraEffects.Apply(player.Character, data.EquippedAura)
	end
end

----------------------------------------------------------------
-- Публичное API
----------------------------------------------------------------

-- Выдаёт ауру. false — уже была или неизвестна.
function AuraService.Grant(player: Player, name: string): boolean
	if not Config.Auras.Kinds[name] then
		return false
	end
	local granted = DataService.Update(player, function(d)
		if d.Auras[name] then
			return false
		end
		d.Auras[name] = true
		return true
	end)
	return granted == true
end

-- Вызывается после перерождения: выдаёт все ауры за достигнутые перерождения
function AuraService.OnRebirth(player: Player, rebirths: number)
	for _, name in Config.Auras.Order do
		local info = Config.Auras.Kinds[name]
		if info.Rebirth and rebirths >= info.Rebirth and AuraService.Grant(player, name) then
			notify(player, `Новая аура за перерождение: {info.Title}!`, "good")
		end
	end
end

function AuraService.Equip(player: Player, name: any): (boolean, string)
	if type(name) ~= "string" or not Config.Auras.Kinds[name] then
		return false, "Неизвестная аура"
	end
	local ok, message = DataService.Update(player, function(d)
		if not d.Auras[name] then
			return false, "Эта аура ещё не открыта"
		end
		d.EquippedAura = name
		return true, `Аура «{Config.Auras.Kinds[name].Title}» надета`
	end)
	if ok == nil then
		return false, "Данные ещё загружаются"
	end
	if ok then
		applyVisual(player)
	end
	return ok, message
end

-- Ауро-склянка: случайная аура (по Chance) за Эликсиры, дубликат возвращает часть Эликсиров
function AuraService.OpenFlask(player: Player): (boolean, string)
	local now = os.clock()
	if now - (lastFlask[player] or 0) < FLASK_COOLDOWN then
		return false, "Склянка ещё бурлит…"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Данные ещё загружаются"
	end
	if data.Elixirs < Config.Auras.FlaskCost then
		return false, `Нужно {Config.Auras.FlaskCost} эликсиров (их даёт Аптека)`
	end
	lastFlask[player] = now

	local total = 0
	for _, name in Config.Auras.Order do
		total += Config.Auras.Kinds[name].Chance or 0
	end
	local roll = random:NextNumber(0, total)
	local picked = Config.Auras.Order[#Config.Auras.Order]
	local sum = 0
	for _, name in Config.Auras.Order do
		sum += Config.Auras.Kinds[name].Chance or 0
		if roll < sum then
			picked = name
			break
		end
	end

	DataService.Increment(player, "Elixirs", -Config.Auras.FlaskCost)
	local title = Config.Auras.Kinds[picked].Title
	if AuraService.Grant(player, picked) then
		return true, `Ауро-склянка: новая аура «{title}»!`
	end
	DataService.Increment(player, "Elixirs", Config.Auras.DuplicateRefund)
	return true, `Ауро-склянка: «{title}» уже есть, +{Config.Auras.DuplicateRefund} эликсиров назад`
end

local function onRequest(player: Player, action: any, name: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return { Ok = false, Message = "Слишком часто" }
	end
	lastRequest[player] = now

	local data = DataService.Get(player)
	if not data then
		return { Ok = false, Message = "Данные ещё загружаются" }
	end
	local ok, message = true, nil
	if action == "equip" then
		ok, message = AuraService.Equip(player, name)
		notify(player, message, if ok then "good" else "warn")
	elseif action ~= "list" then
		return { Ok = false, Message = "Неизвестное действие" }
	end
	return { Ok = ok, Message = message, State = snapshot(DataService.Get(player)) }
end

----------------------------------------------------------------
-- Ауро-склянка в Деревне (фиолетовая копия модели яйца)
----------------------------------------------------------------
local function buildFlaskStand()
	local village = workspace:WaitForChild("Zones"):WaitForChild("Village")
	local old = village:FindFirstChild("AuraFlask")
	if old then
		old:Destroy()
	end
	local stand = Models.Build("Egg") or Instance.new("Model")
	stand.Name = "AuraFlask"
	if not stand.PrimaryPart then
		local glass = Instance.new("Part")
		glass.Name = "Root"
		glass.Shape = Enum.PartType.Ball
		glass.Size = Vector3.new(3, 3, 3)
		glass.Material = Enum.Material.Glass
		glass.Transparency = 0.3
		glass.Anchored = true
		glass.Parent = stand
		stand.PrimaryPart = glass
	end
	-- Перекрашиваем зелёное зелье в фиолетовое
	for _, part in stand:GetDescendants() do
		if part:IsA("BasePart") then
			local h, s, v = part.Color:ToHSV()
			if h > 0.2 and h < 0.45 and s > 0.3 then
				part.Color = Color3.fromHSV(0.78, s, v)
			end
			part.CanCollide = true
			part.CanQuery = true
		end
	end
	local _, size = stand:GetBoundingBox()
	stand:PivotTo(CFrame.new(Config.Auras.FlaskPosition + Vector3.new(0, size.Y / 2, 0)))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = `Открыть ({Config.Auras.FlaskCost} эликсиров)`
	prompt.ObjectText = "Ауро-склянка"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand.PrimaryPart

	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(220, 50)
	sign.StudsOffset = Vector3.new(0, size.Y / 2 + 1.5, 0)
	sign.MaxDistance = 120
	sign.Parent = stand.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(200, 150, 255)
	label.TextStrokeTransparency = 0.2
	label.Text = `АУРО-СКЛЯНКА · {Config.Auras.FlaskCost} эликс.`
	label.Parent = sign

	stand.Parent = village
	prompt.Triggered:Connect(function(player)
		local ok, message = AuraService.OpenFlask(player)
		notify(player, message, if ok then "good" else "warn")
	end)
end

function AuraService.Init()
	if initialized then
		return
	end
	initialized = true

	auraRequest.OnServerInvoke = onRequest
	buildFlaskStand()

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			applyVisual(player)
		end)
		local data = DataService.WaitForData(player)
		if not data then
			return
		end
		-- Стартовая аура всегда есть; надетая должна быть открыта; догоняем ауры за перерождения
		DataService.Update(player, function(d)
			d.Auras[Config.Auras.Starter] = true
			if not d.Auras[d.EquippedAura] then
				d.EquippedAura = Config.Auras.Starter
			end
		end)
		AuraService.OnRebirth(player, data.Rebirths)
		applyVisual(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastFlask[player] = nil
	end)
end

return AuraService
]])
N[19] = ensure(N[17], "DataService", "ModuleScript")
setSource(N[19], [[
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
	Auras: { [string]: boolean }, -- [auraId] = true
	EquippedAura: string,
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
	Auras = { GreenFog = true },
	EquippedAura = "GreenFog",
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

-- Уровни апгрейдов -> атрибуты Upgrade_Mask, Upgrade_Tool, ... (для магазина в UI)
local function syncUpgrades(player: Player, profile: Profile)
	for name, level in profile.Data.Upgrades do
		player:SetAttribute(`Upgrade_{name}`, level)
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
	syncUpgrades(player, profile)
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

-- Меняет данные игрока функцией callback(data) и синхронизирует атрибуты.
-- Для вложенных полей (Pets, EquippedPets, Auras...). Возвращает всё, что вернул callback.
function DataService.Update(player: Player, callback: (PlayerData) -> ...any): ...any
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local results = table.pack(callback(profile.Data))
	for key in profile.Data do
		syncKey(player, profile, key)
	end
	syncUpgrades(player, profile)
	return table.unpack(results, 1, results.n)
end

-- Ставит уровень апгрейда (Mask/Tool/Cloak). Проверки цены — на вызывающем сервисе.
function DataService.SetUpgradeLevel(player: Player, name: string, level: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	(profile.Data.Upgrades :: any)[name] = level
	syncUpgrades(player, profile)
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
N[20] = ensure(N[17], "DoctorService", "ModuleScript")
setSource(N[20], [[
-- ModuleScript: ServerScriptService -> Services -> DoctorService
-- Внешний вид доктора: ланцет в правой руке (его видят все игроки).
-- Взмах при ударе рисует клиент (Effects), здесь только сам инструмент.

local Players = game:GetService("Players")

local DoctorService = {}

local initialized = false

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false -- иначе ланцет перехватывал бы клики по больным
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	b.CFrame = a.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Ланцет: тёмная рукоять, серебряное лезвие, зелёная склянка у гарды
local function buildLancet(hand: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "Lancet"

	local handle = makePart("Handle", Vector3.new(0.22, 1.4, 0.22), Color3.fromRGB(55, 35, 25), Enum.Material.Wood)
	handle.CFrame = hand.CFrame * CFrame.new(0, -0.35, -0.55) * CFrame.Angles(math.rad(-90), 0, 0)
	handle.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = handle
	w.Parent = handle

	local guard = makePart("Guard", Vector3.new(0.5, 0.12, 0.5), Color3.fromRGB(150, 130, 90), Enum.Material.Metal)
	weld(handle, guard, CFrame.new(0, 0.7, 0))
	guard.Parent = model

	local blade = makePart("Blade", Vector3.new(0.12, 1.3, 0.06), Color3.fromRGB(210, 215, 225), Enum.Material.Metal)
	weld(handle, blade, CFrame.new(0, 1.4, 0))
	blade.Parent = model

	local vial = makePart("Vial", Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(110, 230, 80), Enum.Material.Neon)
	vial.Shape = Enum.PartType.Ball
	weld(handle, vial, CFrame.new(0.25, 0.55, 0))
	vial.Parent = model

	model.PrimaryPart = handle
	return model
end

local function onCharacterAdded(character: Model)
	local hand = character:WaitForChild("RightHand", 10) :: BasePart?
	if not hand or character:FindFirstChild("Lancet") then
		return
	end
	buildLancet(hand).Parent = character
end

function DoctorService.Init()
	if initialized then
		return
	end
	initialized = true

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			task.spawn(onCharacterAdded, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return DoctorService
]])
N[21] = ensure(N[17], "InfectedService", "ModuleScript")
setSource(N[21], [[
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
]])
N[22] = ensure(N[17], "Notify", "ModuleScript")
setSource(N[22], [[
-- ModuleScript: ServerScriptService -> Services -> Notify
-- Всплывающие сообщения игроку (показывает HUD на клиенте).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent

-- kind: "info" | "good" | "warn" — влияет на цвет сообщения
return function(player: Player, text: string, kind: string?)
	remote:FireClient(player, text, kind or "info")
end
]])
N[23] = ensure(N[17], "PetService", "ModuleScript")
setSource(N[23], [=[
-- ModuleScript: ServerScriptService -> Services -> PetService
-- Питомцы: вылупление из яйца «Чумная склянка», инвентарь, надеть/снять, множитель миазмов.
-- Всё решает сервер. Клиент получает только список питомцев и рисует их полёт.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Models = require(Shared:WaitForChild("Models"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local PetService = {}

local REQUEST_COOLDOWN = 0.15
local HATCH_COOLDOWN = 1.5 -- дольше анимации вылупления

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local petRequest = Remotes:WaitForChild("PetRequest") :: RemoteFunction
local eggHatched = Remotes:WaitForChild("EggHatched") :: RemoteEvent

local lastRequest: { [Player]: number } = {}
local lastHatch: { [Player]: number } = {}
local carry: { [Player]: number } = {} -- дробная часть миазмов между ударами
local initialized = false
local random = Random.new()

----------------------------------------------------------------
-- Внутреннее
----------------------------------------------------------------
local function equippedKinds(data: any): { string }
	local kinds = {}
	for _, id in data.EquippedPets do
		local pet = data.Pets[id]
		if pet then
			table.insert(kinds, pet.Kind)
		end
	end
	return kinds
end

local function rollKind(): string
	local roll = random:NextNumber(0, 100)
	local sum = 0
	for _, kind in Config.Pets.Order do
		sum += Config.Pets.Kinds[kind].Chance
		if roll < sum then
			return kind
		end
	end
	return Config.Pets.Order[1]
end

local function countPets(data: any): number
	local n = 0
	for _ in data.Pets do
		n += 1
	end
	return n
end

-- Состояние для клиента: список питомцев и надетые id
local function snapshot(data: any)
	local list = {}
	for id, pet in data.Pets do
		table.insert(list, { Id = id, Kind = pet.Kind })
	end
	return {
		Pets = list,
		Equipped = table.clone(data.EquippedPets),
		MaxEquipped = Config.Pets.MaxEquipped,
		MaxInventory = Config.Pets.MaxInventory,
	}
end

-- Атрибуты для всех клиентов: какие питомцы летают за игроком и его множитель
local function sync(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local kinds = equippedKinds(data)
	player:SetAttribute("EquippedPetKinds", table.concat(kinds, ","))
	player:SetAttribute("PetMultiplier", math.floor(Config.GetPetMultiplier(kinds) * 1000 + 0.5) / 1000)
end

----------------------------------------------------------------
-- Публичное API
----------------------------------------------------------------

-- Множитель миазмов от надетых питомцев
function PetService.GetMultiplier(player: Player): number
	local data = DataService.Get(player)
	return if data then Config.GetPetMultiplier(equippedKinds(data)) else 1
end

-- Переводит «сырые» миазмы удара в миазмы с множителем питомцев.
-- Дробная часть копится, чтобы x1.1 не терялся при маленьких числах.
function PetService.ApplyMultiplier(player: Player, amount: number): number
	local total = (carry[player] or 0) + amount * PetService.GetMultiplier(player)
	local whole = math.floor(total + 1e-6)
	carry[player] = total - whole
	return whole
end

-- Вылупление. Возвращает (успех, сообщение, вид питомца?)
function PetService.Hatch(player: Player): (boolean, string, string?)
	local now = os.clock()
	if now - (lastHatch[player] or 0) < HATCH_COOLDOWN then
		return false, "Склянка ещё бурлит…"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Данные ещё загружаются"
	end
	if countPets(data) >= Config.Pets.MaxInventory then
		return false, `Инвентарь полон ({Config.Pets.MaxInventory})`
	end
	if data.Gold < Config.Pets.EggCost then
		return false, `Нужно {Config.Pets.EggCost} золота`
	end
	lastHatch[player] = now

	local kind = rollKind()
	local id = HttpService:GenerateGUID(false)
	DataService.Increment(player, "Gold", -Config.Pets.EggCost)
	DataService.Update(player, function(d)
		d.Pets[id] = { Kind = kind }
	end)
	sync(player)
	eggHatched:FireClient(player, kind, id, snapshot(DataService.Get(player)))
	return true, `Вылупился {Config.Pets.Kinds[kind].Title}!`, kind
end

function PetService.Equip(player: Player, id: any): (boolean, string)
	if type(id) ~= "string" then
		return false, "Неверный питомец"
	end
	return DataService.Update(player, function(d)
		if not d.Pets[id] then
			return false, "Такого питомца нет"
		end
		if table.find(d.EquippedPets, id) then
			return false, "Уже надет"
		end
		if #d.EquippedPets >= Config.Pets.MaxEquipped then
			return false, `Можно надеть не больше {Config.Pets.MaxEquipped}`
		end
		table.insert(d.EquippedPets, id)
		return true, "Питомец надет"
	end)
end

function PetService.Unequip(player: Player, id: any): (boolean, string)
	if type(id) ~= "string" then
		return false, "Неверный питомец"
	end
	return DataService.Update(player, function(d)
		local index = table.find(d.EquippedPets, id)
		if not index then
			return false, "Питомец не надет"
		end
		table.remove(d.EquippedPets, index)
		return true, "Питомец снят"
	end)
end

local function onRequest(player: Player, action: any, id: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return { Ok = false, Message = "Слишком часто" }
	end
	lastRequest[player] = now

	local data = DataService.Get(player)
	if not data then
		return { Ok = false, Message = "Данные ещё загружаются" }
	end

	local ok, message = true, nil
	if action == "equip" then
		ok, message = PetService.Equip(player, id)
	elseif action == "unequip" then
		ok, message = PetService.Unequip(player, id)
	elseif action ~= "list" then
		return { Ok = false, Message = "Неизвестное действие" }
	end
	if ok == nil then
		ok, message = false, "Данные ещё загружаются"
	end
	sync(player)
	if message and not ok then
		notify(player, message, "warn")
	end
	return { Ok = ok, Message = message, State = snapshot(DataService.Get(player)) }
end

----------------------------------------------------------------
-- Яйцо в Деревне
----------------------------------------------------------------
local function buildEggStand()
	local village = workspace:WaitForChild("Zones"):WaitForChild("Village")
	local old = village:FindFirstChild("PetEgg")
	if old then
		old:Destroy()
	end

	local stand = Models.Build("Egg") or Instance.new("Model")
	stand.Name = "PetEgg"
	if not stand.PrimaryPart then
		-- Запасной вариант, если модели нет: простая зелёная склянка
		local glass = Instance.new("Part")
		glass.Name = "Root"
		glass.Shape = Enum.PartType.Ball
		glass.Size = Vector3.new(3, 3, 3)
		glass.Color = Color3.fromRGB(90, 200, 70)
		glass.Material = Enum.Material.Glass
		glass.Transparency = 0.3
		glass.Anchored = true
		glass.Parent = stand
		stand.PrimaryPart = glass
	end
	local _, size = stand:GetBoundingBox()
	stand:PivotTo(CFrame.new(Config.Pets.EggPosition + Vector3.new(0, size.Y / 2, 0)))
	for _, part in stand:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = true
			part.CanQuery = true
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = `Вылупить ({Config.Pets.EggCost} золота)`
	prompt.ObjectText = "Чумная склянка"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand.PrimaryPart

	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(220, 50)
	sign.StudsOffset = Vector3.new(0, size.Y / 2 + 1.5, 0)
	sign.MaxDistance = 120
	sign.Parent = stand.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(150, 230, 110)
	label.TextStrokeTransparency = 0.2
	label.Text = `ЧУМНАЯ СКЛЯНКА · {Config.Pets.EggCost}`
	label.Parent = sign

	stand.Parent = village

	prompt.Triggered:Connect(function(player)
		local ok, message = PetService.Hatch(player)
		if not ok then
			notify(player, message, "warn")
		end
	end)
end

function PetService.Init()
	if initialized then
		return
	end
	initialized = true

	petRequest.OnServerInvoke = onRequest
	buildEggStand()

	local function onPlayerAdded(player: Player)
		if DataService.WaitForData(player) then
			-- Чистим надетых питомцев, которых нет в инвентаре (на случай битых сохранений)
			DataService.Update(player, function(d)
				for i = #d.EquippedPets, 1, -1 do
					if not d.Pets[d.EquippedPets[i]] then
						table.remove(d.EquippedPets, i)
					end
				end
			end)
			sync(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastHatch[player] = nil
		carry[player] = nil
	end)
end

return PetService
]=])
N[24] = ensure(N[17], "PharmacyService", "ModuleScript")
setSource(N[24], [[
-- ModuleScript: ServerScriptService -> Services -> PharmacyService
-- Аптека: встал на зелёную площадку — миазмы из маски обменялись на золото.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local sellFeedback = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellFeedback") :: RemoteEvent

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

	local multiplier = Config.GetGoldMultiplier(data.Rebirths)
	local gold = math.floor(data.Miasma * Config.Pharmacy.GoldPerMiasma * multiplier)
	local elixirs = math.floor(data.Miasma / Config.Pharmacy.MiasmaPerElixir)
	DataService.Set(player, "Miasma", 0)
	DataService.Increment(player, "Gold", gold)
	if elixirs > 0 then
		DataService.Increment(player, "Elixirs", elixirs)
	end
	local bonus = if multiplier > 1 then ` (x{multiplier})` else ""
	local elixirText = if elixirs > 0 then `, +{elixirs} эликсир.` else ""
	notify(player, `Аптека: +{gold} золота{bonus}{elixirText}`, "good")
	sellFeedback:FireClient(player, gold) -- только визуал: монеты
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
N[25] = ensure(N[17], "RebirthService", "ModuleScript")
setSource(N[25], [[
-- ModuleScript: ServerScriptService -> Services -> RebirthService
-- Перерождение «Новая эпидемия»: сброс золота, миазмов и апгрейдов
-- в обмен на Чумной череп и постоянный множитель золота.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local AuraService = require(script.Parent:WaitForChild("AuraService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local RebirthService = {}

local REQUEST_COOLDOWN = 1
local lastRequest: { [Player]: number } = {}
local initialized = false

-- Возвращает (успех, сообщение для игрока)
function RebirthService.Rebirth(player: Player): (boolean, string)
	local data = DataService.Get(player)
	if not data then
		return false, "Данные ещё загружаются"
	end
	local cost = Config.GetRebirthCost(data.Rebirths)
	if data.Gold < cost then
		return false, `Для новой эпидемии нужно {cost} золота`
	end

	DataService.Set(player, "Gold", 0)
	DataService.Set(player, "Miasma", 0)
	for _, name in Config.Upgrades.Order do
		DataService.SetUpgradeLevel(player, name, 1)
	end
	local rebirths = DataService.Increment(player, "Rebirths", 1) :: number
	DataService.Increment(player, "Skulls", Config.Rebirth.SkullsPerRebirth)
	UpgradeService.Refresh(player)
	AuraService.OnRebirth(player, rebirths)

	return true, `Новая эпидемия #{rebirths}! Золото теперь x{Config.GetGoldMultiplier(rebirths)}`
end

local function onRequest(player: Player): (boolean, string)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return false, "Слишком часто"
	end
	lastRequest[player] = now

	local ok, message = RebirthService.Rebirth(player)
	notify(player, message, if ok then "good" else "warn")
	return ok, message
end

function RebirthService.Init()
	if initialized then
		return
	end
	initialized = true

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Rebirth") :: RemoteFunction
	remote.OnServerInvoke = onRequest
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return RebirthService
]])
N[26] = ensure(N[17], "UpgradeService", "ModuleScript")
setSource(N[26], [[
-- ModuleScript: ServerScriptService -> Services -> UpgradeService
-- Покупка апгрейдов (Маска, Ланцет, Плащ) за золото и применение их эффектов.
-- Клиент только просит купить по имени — цену, золото и уровень проверяет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local notify = require(script.Parent:WaitForChild("Notify"))

local UpgradeService = {}

local REQUEST_COOLDOWN = 0.25 -- не чаще 4 покупок в секунду
local lastRequest: { [Player]: number } = {}
local initialized = false

local VALID: { [string]: boolean } = {}
for _, name in Config.Upgrades.Order do
	VALID[name] = true
end

----------------------------------------------------------------
-- Эффекты
----------------------------------------------------------------
local function applyWalkSpeed(player: Player)
	local data = DataService.Get(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		humanoid.WalkSpeed = Config.GetWalkSpeed(data.Upgrades.Cloak)
	end
end

-- Пересчитывает атрибуты снаряжения (их читает HUD) и скорость персонажа
function UpgradeService.Refresh(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("MaskCapacity", Config.GetMaskCapacity(data.Upgrades.Mask))
	player:SetAttribute("ToolPower", Config.GetToolPower(data.Upgrades.Tool))
	player:SetAttribute("WalkSpeed", Config.GetWalkSpeed(data.Upgrades.Cloak))
	applyWalkSpeed(player)
end

----------------------------------------------------------------
-- Покупка
----------------------------------------------------------------

-- Возвращает (успех, сообщение для игрока)
function UpgradeService.Buy(player: Player, name: any): (boolean, string)
	if type(name) ~= "string" or not VALID[name] then
		return false, "Неизвестный апгрейд"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Данные ещё загружаются"
	end

	local info = Config.Upgrades[name]
	local level = (data.Upgrades :: any)[name] :: number
	local cost = Config.GetUpgradeCost(name, level)
	if not cost then
		return false, `{info.Title}: максимальный уровень`
	end
	if data.Gold < cost then
		return false, `Не хватает золота: нужно {cost}`
	end

	DataService.Increment(player, "Gold", -cost)
	DataService.SetUpgradeLevel(player, name, level + 1)
	UpgradeService.Refresh(player)
	return true, `{info.Title} улучшен до уровня {level + 1}!`
end

local function onBuyRequest(player: Player, name: any): (boolean, string)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return false, "Слишком часто"
	end
	lastRequest[player] = now

	local ok, message = UpgradeService.Buy(player, name)
	notify(player, message, if ok then "good" else "warn")
	return ok, message
end

function UpgradeService.Init()
	if initialized then
		return
	end
	initialized = true

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteFunction
	remote.OnServerInvoke = onBuyRequest

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			applyWalkSpeed(player)
		end)
		if DataService.WaitForData(player) then
			UpgradeService.Refresh(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return UpgradeService
]])
N[27] = game:GetService("StarterPlayer")
N[28] = ensure(N[27], "StarterPlayerScripts", "StarterPlayerScripts")
N[29] = ensure(N[28], "HUD", "LocalScript")
setSource(N[29], [[
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
]])
N[30] = ensure(N[28], "Shop", "LocalScript")
setSource(N[30], [[
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
openButton.Text = "Улучшения [U]"
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
window.Size = UDim2.fromScale(0.92, 0.9) -- на маленьком экране сжимается, карточки тоже
window.BackgroundColor3 = BG
window.BackgroundTransparency = 0.05
window.Visible = false
window.Parent = gui
corner(window, 12)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(640, 384)
sizeLimit.Parent = window

local title = text(window, "Title", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 12), TEXT)
title.Text = "Снаряжение доктора"

local goldLabel = text(window, "Gold", UDim2.new(0.5, 0, 0, 22), UDim2.fromOffset(16, 48), GOLD, Enum.Font.GothamMedium)

-- «Закрыть» внизу: правый верхний угол экрана занят таблицей игроков Roblox,
-- она перехватывает клики, поэтому крестик там не работает
local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -12)
closeButton.Size = UDim2.new(1, -24, 0, 44)
closeButton.BackgroundColor3 = Color3.fromRGB(90, 60, 55)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 20
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "Закрыть"
closeButton.Parent = window
corner(closeButton, 8)

local cards = Instance.new("Frame")
cards.Name = "Cards"
cards.Position = UDim2.fromOffset(12, 82)
cards.Size = UDim2.new(1, -24, 1, -150)
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
	card.Size = UDim2.new(1, 0, 1 / #Config.Upgrades.Order, -8)
	card.BackgroundColor3 = CARD
	card.Parent = cards
	corner(card, 8)

	local cardTitle = text(card, "Title", UDim2.new(0.6, -12, 0.34, 0), UDim2.new(0, 12, 0.1, 0), TEXT)
	cardTitle.Text = info.Title
	local level = text(card, "Level", UDim2.new(0.6, -12, 0.23, 0), UDim2.new(0, 12, 0.46, 0), MUTED, Enum.Font.GothamMedium)
	local effect = text(card, "Effect", UDim2.new(0.6, -12, 0.23, 0), UDim2.new(0, 12, 0.69, 0), MUTED, Enum.Font.GothamMedium)

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0.38, 0, 0.7, 0)
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
		-- Одно окно за раз: закрываем окна других интерфейсов
		for _, other in player.PlayerGui:GetChildren() do
			local otherWindow = other ~= gui and other:FindFirstChild("Window")
			if otherWindow and otherWindow:IsA("GuiObject") then
				otherWindow.Visible = false
			end
		end
	end
end

openButton.Activated:Connect(function()
	setOpen(not window.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.U then
		setOpen(not window.Visible)
	end
end)
]])
N[31] = ensure(N[28], "Rebirth", "LocalScript")
setSource(N[31], [[
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
	-- Одно окно за раз: закрываем окна других интерфейсов
	if window.Visible then
		for _, other in player.PlayerGui:GetChildren() do
			local otherWindow = other ~= gui and other:FindFirstChild("Window")
			if otherWindow and otherWindow:IsA("GuiObject") then
				otherWindow.Visible = false
			end
		end
	end
end)
closeButton.Activated:Connect(function()
	window.Visible = false
end)
]])
N[32] = ensure(N[28], "Pets", "LocalScript")
setSource(N[32], [[
-- LocalScript: StarterPlayer -> StarterPlayerScripts -> Pets
-- Полёт питомцев за игроками. Только визуал: какие питомцы надеты, решает сервер
-- (атрибут игрока EquippedPetKinds), а позицию и покачивание считает клиент.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))

-- Места питомцев относительно игрока (по бокам и над головой). Перед персонажа — это -Z.
-- Прямо за спиной не ставим: там питомец загораживает персонажа от камеры.
local SLOTS = {
	Vector3.new(-3.2, 2, 2.5),
	Vector3.new(3.2, 2, 2.5),
	Vector3.new(0, 5.2, 1.5),
}
local BOB_HEIGHT = 0.35
local BOB_SPEED = 2.2
local FOLLOW_SHARPNESS = 8 -- чем больше, тем плотнее держатся за игроком

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

type Follower = { Model: Model, Slot: number, Phase: number, Current: CFrame? }
local followers: { [Player]: { Kinds: string, List: { Follower } } } = {}

local function fallbackModel(): Model
	local model = Instance.new("Model")
	local ball = Instance.new("Part")
	ball.Name = "Root"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.5, 1.5, 1.5)
	ball.Color = Color3.fromRGB(60, 60, 70)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Parent = model
	model.PrimaryPart = ball
	return model
end

local function clear(player: Player)
	local entry = followers[player]
	if entry then
		for _, f in entry.List do
			f.Model:Destroy()
		end
	end
	followers[player] = nil
end

local function refresh(player: Player)
	local kinds = player:GetAttribute("EquippedPetKinds") or ""
	local entry = followers[player]
	if entry and entry.Kinds == kinds then
		return
	end
	clear(player)
	local list = {}
	for index, kind in string.split(kinds, ",") do
		if kind ~= "" and index <= #SLOTS then
			local model = Models.Build(kind) or fallbackModel()
			model.Name = `{player.Name}_{kind}`
			model.Parent = folder
			table.insert(list, { Model = model, Slot = index, Phase = index * 1.7 })
		end
	end
	followers[player] = { Kinds = kinds, List = list }
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("EquippedPetKinds"):Connect(function()
		refresh(player)
	end)
	refresh(player)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerRemoving:Connect(clear)

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local alpha = 1 - math.exp(-FOLLOW_SHARPNESS * dt)
	for player, entry in followers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for _, f in entry.List do
			if not root then
				f.Model.Parent = nil
				f.Current = nil
				continue
			end
			f.Model.Parent = folder
			local bob = math.sin(now * BOB_SPEED + f.Phase) * BOB_HEIGHT
			local tilt = math.sin(now * BOB_SPEED * 0.5 + f.Phase) * 0.08
			local target = root.CFrame * CFrame.new(SLOTS[f.Slot] + Vector3.new(0, bob, 0)) * CFrame.Angles(tilt, 0, tilt)
			f.Current = if f.Current then f.Current:Lerp(target, alpha) else target
			f.Model:PivotTo(f.Current :: CFrame)
		end
	end
end)
]])
N[33] = ensure(N[28], "PetsUI", "LocalScript")
setSource(N[33], [[
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
]])
N[34] = ensure(N[28], "Auras", "LocalScript")
setSource(N[34], [[
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
]])
N[35] = ensure(N[28], "Effects", "LocalScript")
setSource(N[35], [[
-- LocalScript: StarterPlayer -> StarterPlayerScripts -> Effects
-- Только визуал по событиям сервера:
--   TreatFeedback(model, gained, cured) — взмах ланцетом, «+N миазмов», частицы лечения
--   SellFeedback(gold)                  — монеты в Аптеке

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local treatFeedback = Remotes:WaitForChild("TreatFeedback") :: RemoteEvent
local sellFeedback = Remotes:WaitForChild("SellFeedback") :: RemoteEvent

local player = Players.LocalPlayer
local random = Random.new()

----------------------------------------------------------------
-- Взмах ланцетом: поворот плеча кодом (анимации Animate эту «надстройку» не сбрасывают)
----------------------------------------------------------------
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

local swinging = false
local function swing()
	local character = player.Character
	local shoulder, prop = jointHandle(character or workspace, "RightShoulder")
	if not character or not shoulder or not prop or swinging then
		return
	end
	swinging = true
	local base = shoulder:GetAttribute("BasePose") :: CFrame? or (shoulder :: any)[prop]
	shoulder:SetAttribute("BasePose", base)
	local up = TweenService:Create(shoulder, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		[prop] = base * CFrame.Angles(math.rad(120), 0, math.rad(-15)),
	})
	local down = TweenService:Create(shoulder, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		[prop] = base * CFrame.Angles(math.rad(-25), 0, math.rad(10)),
	})
	local back = TweenService:Create(shoulder, TweenInfo.new(0.15), { [prop] = base })
	up:Play()
	up.Completed:Wait()
	down:Play()
	down.Completed:Wait()
	back:Play()
	back.Completed:Wait()
	swinging = false
end

----------------------------------------------------------------
-- «+N миазмов» над головой
----------------------------------------------------------------
local function popup(text: string, color: Color3)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Popup"
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffset = Vector3.new(random:NextNumber(-0.8, 0.8), 2.2, 0)
	gui.Adornee = head
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(1, Enum.EasingStyle.Quad), { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(gui, 1.1)
end

----------------------------------------------------------------
-- Частицы лечения на больном
----------------------------------------------------------------
local function healBurst(model: Model, cured: boolean)
	local torso = model:FindFirstChild("UpperTorso") or model.PrimaryPart
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = torso
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Color = if cured
		then ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 255, 255))
		else ColorSequence.new(Color3.fromRGB(150, 255, 140), Color3.fromRGB(230, 255, 230))
	emitter.Parent = attachment
	emitter:Emit(if cured then 40 else 14)
	Debris:AddItem(attachment, 1.5)
end

treatFeedback.OnClientEvent:Connect(function(model: Model, gained: number, cured: boolean)
	task.spawn(swing)
	if gained > 0 then
		popup(`+{gained} миазмов`, Color3.fromRGB(150, 240, 100))
	end
	if typeof(model) == "Instance" and model.Parent then
		healBurst(model, cured)
	end
end)

----------------------------------------------------------------
-- Монеты в Аптеке
----------------------------------------------------------------
local function coin(): Part
	local c = Instance.new("Part")
	c.Name = "Coin"
	c.Shape = Enum.PartType.Cylinder
	c.Size = Vector3.new(0.15, 0.9, 0.9)
	c.Color = Color3.fromRGB(255, 200, 50)
	c.Material = Enum.Material.Neon
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	return c
end

sellFeedback.OnClientEvent:Connect(function(gold: number)
	local pharmacy = workspace:FindFirstChild("Zones") and workspace.Zones:FindFirstChild("Village")
	local sellPart = pharmacy and pharmacy:FindFirstChild("Pharmacy") and pharmacy.Pharmacy:FindFirstChild("SellPart") :: BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not sellPart or not root then
		return
	end
	popup(`+{gold} золота`, Color3.fromRGB(255, 210, 80))
	local count = math.clamp(math.floor(gold / 5) + 4, 4, 18)
	for i = 1, count do
		task.delay(i * 0.04, function()
			local c = coin()
			local start = sellPart.Position + Vector3.new(random:NextNumber(-4, 4), 1, random:NextNumber(-4, 4))
			c.CFrame = CFrame.new(start) * CFrame.Angles(0, 0, math.rad(90))
			c.Parent = workspace
			local peak = start + Vector3.new(random:NextNumber(-2, 2), random:NextNumber(4, 7), random:NextNumber(-2, 2))
			local up = TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(peak) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0),
			})
			up:Play()
			up.Completed:Wait()
			local target = if root.Parent then root.Position else peak
			local fly = TweenService:Create(c, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(target),
				Size = Vector3.new(0.05, 0.3, 0.3),
			})
			fly:Play()
			fly.Completed:Wait()
			c:Destroy()
		end)
	end
end)
]])
N[36] = game:GetService("ServerStorage")
N[37] = ensure(N[36], "NPCTemplates", "Folder")
N[38] = game:GetService("Workspace")
N[39] = ensure(N[38], "Zones", "Folder")
N[40] = ensure(N[39], "Village", "Folder")
N[41] = ensure(N[40], "Infected", "Folder")
N[42] = ensure(N[40], "Pharmacy", "Folder")
N[43] = ensure(N[42], "SellPart", "Part", { Anchored = true, CanCollide = false, Transparency = 0.5, Size = Vector3.new(12, 1, 12), Position = Vector3.new(0, 0.5, 30), Color = Color3.new(0.25, 0.85, 0.35), Material = Enum.Material.Neon })
removeObsolete("ReplicatedStorage/Shared/Config")
removeObsolete("ServerStorage/PetModels")

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(`[Installer] Готово! Создано объектов: {created}, обновлено скриптов: {updated}, удалено устаревших: {removed}`)
print("[Installer] Не забудьте: Game Settings -> Security -> Enable Studio Access to API Services")
