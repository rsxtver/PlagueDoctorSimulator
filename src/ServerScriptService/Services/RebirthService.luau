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
