--!strict
-- Chute et effets d'apparition des fruits, cote client seulement (rien n'est decide ici).
-- Le serveur (TreeService) pose le fruit a sa place finale avec les attributs DropStart (heure
-- serveur), DropHeight, DropTime et NewFruit. Ici :
--   1. Feuilles voxel qui tombent du feuillage quand le fruit se detache.
--   2. Chute fluide : le fruit tombe en tournant et rebondit (Bounce), image par image.
--   3. Atterrissage : petits cubes qui sautent (couleur du fruit + herbe), onde au sol, et selon la
--      rarete : anneau de couleur (Uncommon+), colonne de lumiere (Rare+), gerbe d'etincelles
--      (Legendary+). Le fruit fait un petit "pop" (grossit puis revient).
--   4. Fruit decouvert pour la premiere fois : etiquette "NEW!" qui monte + effet plus gros.
-- Loin de la camera (> FX_DISTANCE) : rien (le fruit est deja a sa place).
-- Doc : docs/systems/fruits.md (section Effets)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any

local FX_DISTANCE = 150
local GRAVITY = 55
local GRASS = { Color3.fromRGB(96, 156, 70), Color3.fromRGB(116, 178, 74) }
local LEAF = { Color3.fromRGB(62, 124, 50), Color3.fromRGB(92, 156, 64), Color3.fromRGB(116, 178, 74) }
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local FONT = PackStyle.FONT -- police commune de l'interface

local FruitFxController = {}

type Fall = {
	model: Model,
	final: CFrame,
	start: number, -- heure serveur du depart
	duration: number,
	height: number,
	spin: Vector3,
	landed: boolean,
	fruitId: string,
	rarity: number,
	isNew: boolean,
}

type Bit = {
	part: BasePart,
	velocity: Vector3,
	spin: Vector3,
	angle: Vector3,
	life: number,
	maxLife: number,
	size: Vector3,
	gravity: number,
	sway: number?,
}

local falls: { [Model]: Fall } = {}
local bits: { Bit } = {}
local connection: RBXScriptConnection? = nil
local fxFolder: Folder? = nil
local rng = Random.new()

local function getFolder(): Folder
	local folder = fxFolder
	if folder == nil or folder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "FruitFx"
		f.Parent = workspace
		fxFolder = f
		return f
	end
	return folder
end

local function camDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

local function newPart(size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Rebond "Bounce Out" (meme courbe que Enum.EasingStyle.Bounce). Premier contact a 1/2.75.
local function bounceOut(x: number): number
	local n1, d1 = 7.5625, 2.75
	if x < 1 / d1 then
		return n1 * x * x
	elseif x < 2 / d1 then
		x -= 1.5 / d1
		return n1 * x * x + 0.75
	elseif x < 2.5 / d1 then
		x -= 2.25 / d1
		return n1 * x * x + 0.9375
	end
	x -= 2.625 / d1
	return n1 * x * x + 0.984375
end

local FIRST_IMPACT = 1 / 2.75

local function rarityColor(rarity: number): Color3
	local r = Fruits.Rarities[rarity]
	return if r then r.color else Color3.new(1, 1, 1)
end

---------------------------------------------------------------------------------------------
-- Petits cubes (feuilles, debris)

local function addBit(position: Vector3, size: number, color: Color3, velocity: Vector3, life: number, gravity: number, sway: number?)
	local part = newPart(Vector3.new(size, size, size), color)
	part.CFrame = CFrame.new(position)
	part.Parent = getFolder()
	table.insert(bits, {
		part = part,
		velocity = velocity,
		spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)),
		angle = Vector3.zero,
		life = life,
		maxLife = life,
		size = part.Size,
		gravity = gravity,
		sway = sway,
	})
end

-- Feuilles qui tombent doucement du feuillage (le fruit vient de se detacher).
local function leafBurst(position: Vector3)
	for _ = 1, rng:NextInteger(3, 5) do
		local v = Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(0.5, 2.5), rng:NextNumber(-2.5, 2.5))
		addBit(position + v * 0.3, rng:NextNumber(0.22, 0.34), LEAF[rng:NextInteger(1, #LEAF)], v, rng:NextNumber(0.9, 1.4), 9, rng:NextNumber(0, math.pi * 2))
	end
end

-- Cubes qui sautent a l'atterrissage.
local function debrisBurst(position: Vector3, bodyColor: Color3, count: number, power: number)
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local out = rng:NextNumber(3, 6) * power
		local v = Vector3.new(math.cos(a) * out, rng:NextNumber(7, 12) * power, math.sin(a) * out)
		local color = if i % 3 == 0 then GRASS[rng:NextInteger(1, #GRASS)] else bodyColor:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.25))
		addBit(position + Vector3.new(0, 0.3, 0), rng:NextNumber(0.16, 0.28), color, v, rng:NextNumber(0.45, 0.7), GRAVITY, nil)
	end
end

---------------------------------------------------------------------------------------------
-- Onde, anneau, colonne de lumiere, etincelles, "NEW!"

local function groundRing(position: Vector3, color: Color3, fromSize: number, toSize: number, seconds: number, neon: boolean)
	local ring = newPart(Vector3.new(0.12, fromSize, fromSize), color, if neon then Enum.Material.Neon else nil)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = if neon then 0.15 else 0.35
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = getFolder()
	local tween = TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, toSize, toSize),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		ring:Destroy()
	end)
	tween:Play()
end

local function lightPillar(position: Vector3, color: Color3, height: number, width: number)
	local pillar = newPart(Vector3.new(height, width, width), color, Enum.Material.Neon)
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Transparency = 0.25
	pillar.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = getFolder()
	local tween = TweenService:Create(pillar, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(height * 1.15, width * 0.15, width * 0.15),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		pillar:Destroy()
	end)
	tween:Play()
end

local function sparkleBurst(position: Vector3, color: Color3, count: number)
	local holder = newPart(Vector3.new(0.2, 0.2, 0.2), color)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position + Vector3.new(0, 0.8, 0))
	holder.Parent = getFolder()
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(6, 12)
	e.Drag = 4
	e.Acceleration = Vector3.new(0, -6, 0)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	task.delay(1.4, function()
		holder:Destroy()
	end)
end

local function newTag(model: Model, color: Color3)
	local body = model.PrimaryPart
	if body == nil then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NewTag"
	gui.Size = UDim2.fromScale(4, 1.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = body
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = FONT
	label.Text = "NEW!"
	label.TextScaled = true
	label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = PackStyle.TEXT_STROKE
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	gui.Parent = getFolder()
	-- Monte, grossit un peu, puis s'efface
	TweenService:Create(gui, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
		Size = UDim2.fromScale(5, 2),
	}):Play()
	task.delay(1.6, function()
		TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	end)
	task.delay(2.5, function()
		gui:Destroy()
	end)
end

-- Petit "pop" du fruit qui touche le sol (grossit puis revient a sa taille exacte).
local function landPop(model: Model)
	task.spawn(function()
		local steps = 8
		for i = 1, steps do
			if model.Parent == nil then
				return
			end
			local t = i / steps
			pcall(function()
				model:ScaleTo(1 + 0.22 * math.sin(t * math.pi))
			end)
			task.wait(0.022)
		end
		if model.Parent ~= nil then
			pcall(function()
				model:ScaleTo(1)
			end)
		end
	end)
end

local function onLanded(fall: Fall)
	local position = fall.final.Position
	if camDistance(position) > FX_DISTANCE then
		return
	end
	local okColor, bodyColor = pcall(FruitModels.GetBodyColor, fall.fruitId)
	local color = if okColor then bodyColor else Color3.fromRGB(220, 60, 60)
	local rarity = fall.rarity
	local power = 1 + math.min(rarity - 1, 6) * 0.08
	debrisBurst(position, color, 5 + math.min(rarity, 8), power)
	groundRing(position, Color3.new(1, 1, 1), 0.8, 3.2, 0.35, false)
	if rarity >= 2 then
		groundRing(position, rarityColor(rarity), 1, 4 + rarity * 0.6, 0.55, true)
	end
	if rarity >= 3 then
		lightPillar(position, rarityColor(rarity), 7 + rarity * 1.5, 0.9 + rarity * 0.12)
	end
	if rarity >= 5 then
		sparkleBurst(position, rarityColor(rarity), 18 + rarity * 2)
		task.delay(0.12, function()
			groundRing(position, rarityColor(rarity), 1, 7 + rarity, 0.8, true)
		end)
	end
	if fall.isNew then
		newTag(fall.model, rarityColor(rarity))
		sparkleBurst(position, rarityColor(rarity), 24)
		SoundFx.PlayAt("NewFruit", position)
	elseif rarity >= 3 then
		SoundFx.PlayAt("TreeChime", position)
	end
	SoundFx.PlayAt("FruitLand", position)
	landPop(fall.model)
end

---------------------------------------------------------------------------------------------
-- Boucle

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	for model, fall in falls do
		if model.Parent == nil then
			falls[model] = nil
			continue
		end
		local alpha = math.clamp((now - fall.start) / fall.duration, 0, 1)
		if alpha >= 1 then
			model:PivotTo(fall.final)
			falls[model] = nil
			if not fall.landed then
				fall.landed = true
				onLanded(fall)
			end
			continue
		end
		local offset = fall.height * (1 - bounceOut(alpha))
		local turn = 1 - math.min(alpha / FIRST_IMPACT, 1) -- la rotation s'arrete au 1er contact
		turn = turn * turn
		local spin = fall.spin * turn
		model:PivotTo((fall.final + Vector3.new(0, offset, 0)) * CFrame.Angles(spin.X, spin.Y, spin.Z))
		if not fall.landed and alpha >= FIRST_IMPACT then
			fall.landed = true
			onLanded(fall)
		end
	end

	for i = #bits, 1, -1 do
		local bit = bits[i]
		bit.life -= dt
		if bit.life <= 0 then
			bit.part:Destroy()
			table.remove(bits, i)
			continue
		end
		bit.velocity -= Vector3.new(0, bit.gravity * dt, 0)
		local sway = bit.sway
		local drift = Vector3.zero
		if sway then
			-- les feuilles se balancent en tombant
			bit.sway = sway + dt * 6
			drift = Vector3.new(math.cos(sway) * 1.5, 0, math.sin(sway * 0.7) * 1.5) * dt
			bit.velocity *= 0.96
		end
		bit.angle += bit.spin * dt
		local pos = bit.part.Position + bit.velocity * dt + drift
		local k = bit.life / bit.maxLife
		bit.part.Size = bit.size * math.clamp(k * 1.6, 0.05, 1)
		bit.part.CFrame = CFrame.new(pos) * CFrame.Angles(bit.angle.X, bit.angle.Y, bit.angle.Z)
	end

	if next(falls) == nil and #bits == 0 then
		local conn = connection
		if conn then
			conn:Disconnect()
			connection = nil
		end
	end
end

local function ensureLoop()
	if connection == nil then
		connection = RunService.RenderStepped:Connect(step)
	end
end

-- Un fruit vient d'apparaitre au sol (replication) : chute + effets s'il est en train de tomber.
local function onFruitAdded(model: Model)
	local start = model:GetAttribute("DropStart")
	local duration = model:GetAttribute("DropTime")
	local height = model:GetAttribute("DropHeight")
	if type(start) ~= "number" or type(duration) ~= "number" or type(height) ~= "number" or duration <= 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - start >= duration then
		return -- deja tombe (arrive en retard)
	end
	local final = model:GetPivot()
	if camDistance(final.Position) > FX_DISTANCE then
		return
	end
	local fruitId = model:GetAttribute("FruitId")
	local fruit = if type(fruitId) == "string" then Fruits.ById[fruitId] else nil
	local fall: Fall = {
		model = model,
		final = final,
		start = start,
		duration = duration,
		height = height,
		spin = Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-4, 4), rng:NextNumber(-2.5, 2.5)),
		landed = false,
		fruitId = if fruit then fruit.id else Fruits.List[1].id,
		rarity = if fruit then fruit.rarity else 1,
		isNew = model:GetAttribute("NewFruit") == true,
	}
	falls[model] = fall
	-- Tout de suite en haut (avant l'affichage) pour ne pas voir le fruit "sauter" du sol
	model:PivotTo((final + Vector3.new(0, height, 0)) * CFrame.Angles(fall.spin.X, fall.spin.Y, fall.spin.Z))
	leafBurst(final.Position + Vector3.new(0, height + 0.8, 0))
	ensureLoop()
end

function FruitFxController:Init() end

function FruitFxController:Start()
	task.spawn(function()
		local bases = workspace:WaitForChild("Bases", 60)
		if bases == nil then
			return
		end
		bases.DescendantAdded:Connect(function(item: Instance)
			if item:IsA("Model") and item.Parent and item.Parent.Name == "GroundFruits" then
				onFruitAdded(item)
			end
		end)
	end)
end

return FruitFxController
