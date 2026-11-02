-- LocalScript: StarterPlayer -> StarterPlayerScripts -> Effects
-- Только визуал по событиям сервера:
--   TreatFeedback(model, gained, cured) — взмах ланцетом, «+N миазмов», частицы лечения
--   SellFeedback(gold)                  — монеты в Аптеке

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local treatFeedback = Remotes:WaitForChild("TreatFeedback") :: RemoteEvent
local sellFeedback = Remotes:WaitForChild("SellFeedback") :: RemoteEvent

local player = Players.LocalPlayer
local random = Random.new()

----------------------------------------------------------------
-- Взмах ланцетом: поворот плеча кодом (анимации Animate эту «надстройку» не сбрасывают)
----------------------------------------------------------------
-- Сустав рига: у Motor6D двигаем C0, у новых AnimationConstraint — CFrame их Attachment0.
-- Возвращает (объект, имя свойства) или nil.
local function jointHandle(model: Instance, name: string): (Instance?, string?)
	local joint = model:FindFirstChild(name, true)
	if joint and joint:IsA("Motor6D") then
		return joint, "C0"
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint.Attachment0, "CFrame"
	end
	return nil, nil
end

local swinging = false
local function swing()
	local character = player.Character
	local shoulder, prop = jointHandle(character or workspace, "RightShoulder")
	if not character or not shoulder or not prop or swinging then
		return
	end
	swinging = true
	local base = shoulder:GetAttribute("BasePose") :: CFrame? or (shoulder :: any)[prop]
	shoulder:SetAttribute("BasePose", base)
	local up = TweenService:Create(shoulder, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		[prop] = base * CFrame.Angles(math.rad(120), 0, math.rad(-15)),
	})
	local down = TweenService:Create(shoulder, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		[prop] = base * CFrame.Angles(math.rad(-25), 0, math.rad(10)),
	})
	local back = TweenService:Create(shoulder, TweenInfo.new(0.15), { [prop] = base })
	up:Play()
	up.Completed:Wait()
	down:Play()
	down.Completed:Wait()
	back:Play()
	back.Completed:Wait()
	swinging = false
end

----------------------------------------------------------------
-- «+N миазмов» над головой
----------------------------------------------------------------
local function popup(text: string, color: Color3)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Popup"
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffset = Vector3.new(random:NextNumber(-0.8, 0.8), 2.2, 0)
	gui.Adornee = head
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(1, Enum.EasingStyle.Quad), { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(gui, 1.1)
end

----------------------------------------------------------------
-- Частицы лечения на больном
----------------------------------------------------------------
local function healBurst(model: Model, cured: boolean)
	local torso = model:FindFirstChild("UpperTorso") or model.PrimaryPart
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = torso
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Color = if cured
		then ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 255, 255))
		else ColorSequence.new(Color3.fromRGB(150, 255, 140), Color3.fromRGB(230, 255, 230))
	emitter.Parent = attachment
	emitter:Emit(if cured then 40 else 14)
	Debris:AddItem(attachment, 1.5)
end

treatFeedback.OnClientEvent:Connect(function(model: Model, gained: number, cured: boolean)
	task.spawn(swing)
	if gained > 0 then
		popup(`+{gained} миазмов`, Color3.fromRGB(150, 240, 100))
	end
	if typeof(model) == "Instance" and model.Parent then
		healBurst(model, cured)
	end
end)

----------------------------------------------------------------
-- Монеты в Аптеке
----------------------------------------------------------------
local function coin(): Part
	local c = Instance.new("Part")
	c.Name = "Coin"
	c.Shape = Enum.PartType.Cylinder
	c.Size = Vector3.new(0.15, 0.9, 0.9)
	c.Color = Color3.fromRGB(255, 200, 50)
	c.Material = Enum.Material.Neon
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	return c
end

sellFeedback.OnClientEvent:Connect(function(gold: number)
	local pharmacy = workspace:FindFirstChild("Zones") and workspace.Zones:FindFirstChild("Village")
	local sellPart = pharmacy and pharmacy:FindFirstChild("Pharmacy") and pharmacy.Pharmacy:FindFirstChild("SellPart") :: BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not sellPart or not root then
		return
	end
	popup(`+{gold} золота`, Color3.fromRGB(255, 210, 80))
	local count = math.clamp(math.floor(gold / 5) + 4, 4, 18)
	for i = 1, count do
		task.delay(i * 0.04, function()
			local c = coin()
			local start = sellPart.Position + Vector3.new(random:NextNumber(-4, 4), 1, random:NextNumber(-4, 4))
			c.CFrame = CFrame.new(start) * CFrame.Angles(0, 0, math.rad(90))
			c.Parent = workspace
			local peak = start + Vector3.new(random:NextNumber(-2, 2), random:NextNumber(4, 7), random:NextNumber(-2, 2))
			local up = TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(peak) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0),
			})
			up:Play()
			up.Completed:Wait()
			local target = if root.Parent then root.Position else peak
			local fly = TweenService:Create(c, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(target),
				Size = Vector3.new(0.05, 0.3, 0.3),
			})
			fly:Play()
			fly.Completed:Wait()
			c:Destroy()
		end)
	end
end)
