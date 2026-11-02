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
N[3] = ensure(N[1], "Shared", "Folder")
N[4] = game:GetService("ServerScriptService")
N[5] = ensure(N[4], "MainServer", "Script")
setSource(N[5], [[
-- Script: ServerScriptService -> MainServer
-- Точка входа сервера: запускает все сервисы по порядку.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))

DataService.Init()

print("[MainServer] Plague Doctor Simulator: сервер запущен")
]])
N[6] = ensure(N[4], "Services", "Folder")
N[7] = ensure(N[6], "DataService", "ModuleScript")
setSource(N[7], [[
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
]])
N[8] = game:GetService("ServerStorage")
N[9] = ensure(N[8], "NPCTemplates", "Folder")
N[10] = ensure(N[8], "PetModels", "Folder")
N[11] = game:GetService("Workspace")
N[12] = ensure(N[11], "Zones", "Folder")
N[13] = ensure(N[12], "Village", "Folder")
N[14] = ensure(N[13], "Infected", "Folder")
N[15] = ensure(N[13], "Pharmacy", "Folder")
N[16] = ensure(N[15], "SellPart", "Part", { Anchored = true, CanCollide = false, Transparency = 0.5, Size = Vector3.new(12, 1, 12), Position = Vector3.new(0, 0.5, 30), Color = Color3.new(0.25, 0.85, 0.35), Material = Enum.Material.Neon })

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(`[Installer] Готово! Создано объектов: {created}, обновлено скриптов: {updated}`)
print("[Installer] Не забудьте: Game Settings -> Security -> Enable Studio Access to API Services")
