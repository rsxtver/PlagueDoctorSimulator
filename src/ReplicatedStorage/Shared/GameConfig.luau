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
}

-- Перерождение «Новая эпидемия»: сброс золота, миазмов и апгрейдов
-- в обмен на Чумные черепа и постоянный множитель золота
Config.Rebirth = {
	BaseCost = 500, -- золото за первое перерождение
	CostGrowth = 2.5, -- каждое следующее дороже во столько раз
	GoldBonusPerRebirth = 0.5, -- +50% золота в Аптеке за каждое перерождение
	SkullsPerRebirth = 1,
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
