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
