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
