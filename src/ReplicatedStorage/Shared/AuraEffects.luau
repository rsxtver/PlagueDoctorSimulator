-- ModuleScript: ReplicatedStorage -> Shared -> AuraEffects
-- Внешний вид аур: Attachment в HumanoidRootPart + ParticleEmitter-ы + PointLight.
-- Вызывает сервер (эффект реплицируется всем игрокам); клиент может звать Apply для превью.

local AuraEffects = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local ATTACHMENT_NAME = "AuraAttachment"

type EmitterDef = { [string]: any }
type AuraDef = { Light: { Color: Color3, Brightness: number, Range: number }, Emitters: { EmitterDef } }

local function seq(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local points = {}
	for i, v in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(points)
end

local DEFS: { [string]: AuraDef } = {
	GreenFog = {
		Light = { Color = Color3.fromRGB(110, 220, 90), Brightness = 0.8, Range = 8 },
		Emitters = {
			{
				Texture = SMOKE, Rate = 14, Lifetime = NumberRange.new(1.5, 2.5),
				Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(180, 20),
				Size = seq(1.2, 2.6), Transparency = seq(0.6, 0.75, 1),
				Color = ColorSequence.new(Color3.fromRGB(90, 200, 70), Color3.fromRGB(50, 120, 40)),
				Offset = Vector3.new(0, -2.5, 0),
			},
		},
	},
	CrowFeathers = {
		Light = { Color = Color3.fromRGB(120, 100, 160), Brightness = 0.5, Range = 7 },
		Emitters = {
			{
				Texture = SPARKLE, Rate = 10, Lifetime = NumberRange.new(2, 3),
				Speed = NumberRange.new(0.5, 1.2), SpreadAngle = Vector2.new(180, 180),
				Size = seq(0.35, 0.3), Squash = seq(-1.2), Transparency = seq(0.1, 0.2, 1),
				Color = ColorSequence.new(Color3.fromRGB(25, 25, 35), Color3.fromRGB(60, 50, 80)),
				Acceleration = Vector3.new(0, -1.5, 0), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-90, 90),
				Offset = Vector3.new(0, 1, 0),
			},
		},
	},
	PoisonBubbles = {
		Light = { Color = Color3.fromRGB(170, 240, 60), Brightness = 1, Range = 9 },
		Emitters = {
			{
				Texture = SPARKLE, Rate = 12, Lifetime = NumberRange.new(1.5, 2.5),
				Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(25, 25),
				Size = seq(0.2, 0.6, 0.1), Transparency = seq(0.2, 0.4, 1),
				Color = ColorSequence.new(Color3.fromRGB(190, 250, 60), Color3.fromRGB(80, 200, 40)),
				LightEmission = 0.6,
				Offset = Vector3.new(0, -2.5, 0), EmissionDirection = Enum.NormalId.Top,
			},
		},
	},
	GhostFlame = {
		Light = { Color = Color3.fromRGB(90, 220, 255), Brightness = 1.6, Range = 10 },
		Emitters = {
			{
				Texture = FIRE, Rate = 22, Lifetime = NumberRange.new(0.8, 1.3),
				Speed = NumberRange.new(2, 3.5), SpreadAngle = Vector2.new(10, 10),
				Size = seq(1.2, 0.6, 0), Transparency = seq(0.3, 0.6, 1),
				Color = ColorSequence.new(Color3.fromRGB(150, 240, 255), Color3.fromRGB(40, 120, 255)),
				LightEmission = 1,
				Offset = Vector3.new(0, -2.5, 0), EmissionDirection = Enum.NormalId.Top,
			},
		},
	},
	RainbowPlague = {
		Light = { Color = Color3.fromRGB(255, 160, 255), Brightness = 1.8, Range = 11 },
		Emitters = {
			{
				Texture = SPARKLE, Rate = 25, Lifetime = NumberRange.new(1.2, 2),
				Speed = NumberRange.new(0.8, 1.6), SpreadAngle = Vector2.new(180, 180),
				Size = seq(0.6, 0.2), Transparency = seq(0, 1),
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
					ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 90)),
					ColorSequenceKeypoint.new(0.75, Color3.fromRGB(70, 140, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
				}),
				LightEmission = 1, RotSpeed = NumberRange.new(-180, 180), SpreadAngle = Vector2.new(180, 180),
			},
			{
				Texture = SMOKE, Rate = 6, Lifetime = NumberRange.new(2, 3),
				Speed = NumberRange.new(0.2, 0.5), Size = seq(1.5, 3), Transparency = seq(0.75, 1),
				Color = ColorSequence.new(Color3.fromRGB(120, 230, 100), Color3.fromRGB(190, 110, 255)),
				Offset = Vector3.new(0, -2.5, 0),
			},
		},
	},
}

-- Снимает ауру с персонажа
function AuraEffects.Remove(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local old = root and root:FindFirstChild(ATTACHMENT_NAME)
	if old then
		old:Destroy()
	end
end

-- Надевает ауру на персонажа (старая снимается). Неизвестное имя — просто снимает.
function AuraEffects.Apply(character: Model, auraName: string)
	AuraEffects.Remove(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local def = DEFS[auraName]
	if not root or not def then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment:SetAttribute("Aura", auraName)

	for _, e in def.Emitters do
		local holder: Instance = attachment
		if e.Offset then
			local sub = Instance.new("Attachment")
			sub.Name = "Offset"
			sub.Position = e.Offset
			sub.Parent = attachment
			holder = sub
		end
		local emitter = Instance.new("ParticleEmitter")
		for key, value in e do
			if key == "Offset" then
				continue
			end
			(emitter :: any)[key] = value
		end
		emitter.LockedToPart = false
		emitter.Parent = holder
	end

	local light = Instance.new("PointLight")
	light.Color = def.Light.Color
	light.Brightness = def.Light.Brightness
	light.Range = def.Light.Range
	light.Shadows = false
	light.Parent = attachment

	attachment.Parent = root
end

return AuraEffects
