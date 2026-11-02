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
