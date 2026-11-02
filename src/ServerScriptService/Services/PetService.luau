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
