-- ModuleScript: ServerScriptService -> Services -> PharmacyService
-- Аптека: встал на зелёную площадку — миазмы из маски обменялись на золото.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
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

	local multiplier = Config.GetGoldMultiplier(data.Rebirths)
	local gold = math.floor(data.Miasma * Config.Pharmacy.GoldPerMiasma * multiplier)
	DataService.Set(player, "Miasma", 0)
	DataService.Increment(player, "Gold", gold)
	local bonus = if multiplier > 1 then ` (x{multiplier})` else ""
	notify(player, `Аптека: +{gold} золота{bonus}`, "good")
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
