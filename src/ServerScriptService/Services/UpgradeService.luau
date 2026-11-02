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
