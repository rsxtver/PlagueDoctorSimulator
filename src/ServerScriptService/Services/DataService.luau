-- ModuleScript: ServerScriptService -> Services -> DataService
-- Загрузка, хранение в памяти и сохранение данных игроков (только сервер).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

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
	{ Key = "Rebirths", Name = "Перерождения" },
}

----------------------------------------------------------------
-- Внутреннее состояние
----------------------------------------------------------------
type Profile = {
	Data: PlayerData,
	Stats: { [string]: IntValue },
}

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
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
local function withRetries(label: string, callback: () -> any): (boolean, any)
	local lastError
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		warn(`[DataService] {label}: попытка {attempt}/{MAX_RETRIES} не удалась — {result}`)
		if attempt < MAX_RETRIES then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

----------------------------------------------------------------
-- Загрузка / сохранение
----------------------------------------------------------------
local function loadData(player: Player): PlayerData?
	local key = KEY_PREFIX .. player.UserId
	local ok, stored = withRetries(`Загрузка {player.Name}`, function()
		return store:GetAsync(key)
	end)
	if not ok then
		return nil
	end

	local data = if type(stored) == "table" then stored else deepCopy(TEMPLATE)
	reconcile(data, TEMPLATE)
	return data
end

local function saveData(userId: number, name: string, data: PlayerData): boolean
	activeSaves += 1
	local ok = withRetries(`Сохранение {name}`, function()
		return store:UpdateAsync(KEY_PREFIX .. userId, function()
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
