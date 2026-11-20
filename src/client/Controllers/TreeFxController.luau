--!strict
-- Animation de l'arbre qui s'ameliore, cote client seulement (rien n'est decide ici).
-- Declencheur : attribut "TreeLevel" du dossier Tree (achat sur le pad "Upgrade Tree" : le serveur
-- repose l'arbre du nouveau niveau, construit par Lib/TreeBuilder). Depuis le 2026-11-20 (soir)
-- l'attribut "TreeStage" = palier de l'arbre, il change a CHAQUE niveau : on joue toujours la grande
-- pousse ("stage"). Avant le 2026-11-19 soir : "Bought" des machines Tree Speed / Luck.
-- Deroule (~1.6 s), tout en "gelee" (Fx/Jelly) :
--   1. Elan (0.32 s) : l'arbre se tasse vers le bas et s'elargit, le feuillage s'eclaircit et frissonne.
--   2. Pop : il jaillit vers le haut (plus haut que sa taille), vague de feuillage qui gonfle du bas
--      vers le haut, feuilles qui volent, etincelles, onde au sol, eclair de lumiere, "boing".
--   3. Il se balance et rebondit de moins en moins, puis revient exactement a sa forme.
-- Nouveau niveau : pas d'elan (le modele vient d'etre remplace), il pousse depuis une taille plus
-- petite puis rebondit ; beaucoup plus petite quand le stade change (nouveau modele).
-- Pieces animees : Tree.Body (Model) s'il existe, sinon les pieces de Tree sauf le sol.
-- Un arbre par etage ouvert (Bases.BaseN.Floors.FloorK.Tree, via Util/FloorWatch).
-- Doc : docs/systems/chaine-production.md (section Animations)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local FX_DISTANCE = 170
local CHARGE_SECONDS = 0.32
local GLOW_COLOR = Color3.fromRGB(205, 255, 130)
local FLASH_COLOR = Color3.fromRGB(215, 255, 160)
local CONFETTI_COUNT = 16
local LEVEL_SHRINK = -0.2 -- nouveau niveau : part 20 % plus petit
local STAGE_SHRINK = -0.35 -- nouveau modele : part 35 % plus petit
-- Pieces du sol du verger (jamais animees)
local GROUND = {
	Border = true,
	BorderCap = true,
	Soil = true,
	Lawn = true,
	GrassA = true,
	GrassB = true,
	GrassC = true,
	Flower = true,
	FlowerLeaves = true,
	Rock = true,
	FruitArea = true,
	TreeLabelAnchor = true,
}

local TreeFxController = {}

local started = false
local fxFolder: Folder? = nil

type Confetti = { part: BasePart, velocity: Vector3, spin: Vector3, life: number, maxLife: number, size: Vector3, angle: Vector3 }

type Anim = {
	base: Model,
	rig: Jelly.Rig,
	leaves: { [BasePart]: Color3 },
	puffers: { [BasePart]: boolean },
	t: number,
	popped: boolean,
	squash: Jelly.Spring,
	scale: Jelly.Spring,
	bendX: Jelly.Spring,
	bendZ: Jelly.Spring,
	confetti: { Confetti },
	ring: BasePart?,
	holder: BasePart?,
	light: PointLight?,
	crown: Vector3,
	leafColors: { Color3 },
}

local anims: { [Model]: Anim } = {}
local connection: RBXScriptConnection? = nil

local function camDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

local function isLeaf(part: BasePart): boolean
	return part:GetAttribute("Leaf") == true or string.sub(part.Name, 1, 6) == "Leaves"
end

local function isPuffer(part: BasePart): boolean
	return isLeaf(part) or part.Name == "Apple" or part.Name == "AppleStem" or part.Name == "HangFruit"
end

-- Pieces de l'arbre (sans le sol), et pivot = pied du tronc.
local function collectTree(base: Model): ({ BasePart }, CFrame?)
	local tree = base:FindFirstChild("Tree")
	if tree == nil then
		return {}, nil
	end
	local parts: { BasePart } = {}
	local body = tree:FindFirstChild("Body")
	if body then
		for _, item in body:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(parts, item)
			end
		end
	else
		for _, item in tree:GetChildren() do
			if item:IsA("BasePart") and not GROUND[item.Name] then
				table.insert(parts, item)
			end
		end
	end
	if #parts == 0 then
		return parts, nil
	end
	local minY = math.huge
	local sum = Vector3.zero
	for _, part in parts do
		minY = math.min(minY, part.Position.Y - part.Size.Y / 2)
		sum += part.Position
	end
	local center = sum / #parts
	local trunk = (if body then body:FindFirstChild("Trunk", true) else nil) or tree:FindFirstChild("Trunk")
	if trunk and trunk:IsA("BasePart") then
		center = trunk.Position
	end
	return parts, CFrame.new(center.X, minY, center.Z) * base:GetPivot().Rotation
end

---------------------------------------------------------------------------------------------
-- Effets du pop

local function newPart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function sparkleBurst(position: Vector3)
	local folder = fxFolder
	if folder == nil then
		return
	end
	local holder = newPart("TreeSparkles", Vector3.new(8, 6, 8), Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(190, 255, 140))
	emitter.LightEmission = 0.9
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Drag = 1.5
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = folder
	emitter:Emit(50)
	task.delay(1.6, function()
		holder:Destroy()
	end)
end

local function pop(anim: Anim)
	anim.popped = true
	local folder = fxFolder
	-- Il jaillit, puis rebondit et se balance (ressorts souples)
	anim.squash.k, anim.squash.c = 150, 5.5
	anim.squash.target = 0
	anim.squash.v += 3.4
	local angle = math.random() * math.pi * 2
	anim.bendX.v += math.cos(angle) * 9
	anim.bendZ.v += math.sin(angle) * 9
	-- Ici, plus tard : changer le modele de l'arbre au "pop" si le niveau donne un nouveau stade.
	if folder == nil then
		return
	end
	local pivot = anim.rig.pivot
	-- Feuilles qui volent
	for i = 1, CONFETTI_COUNT do
		local color = anim.leafColors[((i - 1) % math.max(1, #anim.leafColors)) + 1] or Color3.fromRGB(80, 150, 60)
		local size = Vector3.new(0.5, 0.5, 0.5) * (0.8 + math.random() * 0.8)
		local part = newPart("LeafBit", size, color:Lerp(GLOW_COLOR, math.random() * 0.4))
		local a = math.random() * math.pi * 2
		local r = 2 + math.random() * 4
		part.CFrame = CFrame.new(anim.crown + Vector3.new(math.cos(a) * r, math.random() * 4 - 2, math.sin(a) * r))
		part.Parent = folder
		table.insert(anim.confetti, {
			part = part,
			velocity = Vector3.new(math.cos(a), 0, math.sin(a)) * (7 + math.random() * 7) + Vector3.new(0, 10 + math.random() * 8, 0),
			spin = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5),
			life = 0,
			maxLife = 1 + math.random() * 0.5,
			size = size,
			angle = Vector3.zero,
		})
	end
	sparkleBurst(anim.crown)
	-- Un 2e achat pendant l'animation : on remplace l'onde et la lumiere precedentes
	if anim.ring then
		anim.ring:Destroy()
	end
	if anim.holder then
		anim.holder:Destroy()
	end
	-- Onde au sol
	local ring = newPart("TreeRing", Vector3.new(0.2, 4, 4), GLOW_COLOR)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.CFrame = pivot * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	anim.ring = ring
	-- Eclair de lumiere dans le feuillage
	local holder = newPart("TreeFlash", Vector3.new(1, 1, 1), FLASH_COLOR)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(anim.crown)
	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Range = 30
	light.Brightness = 0
	light.Shadows = false
	light.Parent = holder
	holder.Parent = folder
	anim.holder = holder
	anim.light = light
	SoundFx.PlayAt("TreeBoing", anim.crown)
	SoundFx.PlayAt("TreeChime", anim.crown)
end

---------------------------------------------------------------------------------------------

local function finish(anim: Anim)
	Jelly.Restore(anim.rig)
	for part, color in anim.leaves do
		if part.Parent then
			part.Color = color
		end
	end
	for _, c in anim.confetti do
		c.part:Destroy()
	end
	if anim.ring then
		anim.ring:Destroy()
	end
	if anim.holder then
		anim.holder:Destroy()
	end
	anims[anim.base] = nil
end

local function updateAnim(anim: Anim, dt: number)
	anim.t += dt
	local t = anim.t
	if Jelly.IsBroken(anim.rig) then
		-- Le modele de l'arbre a change pendant l'animation : on arrete proprement
		finish(anim)
		return
	end
	if not anim.popped and t >= CHARGE_SECONDS then
		pop(anim)
	end
	Jelly.Step(anim.squash, dt)
	Jelly.Step(anim.scale, dt)
	Jelly.Step(anim.bendX, dt)
	Jelly.Step(anim.bendZ, dt)

	-- Feuillage : s'eclaircit pendant l'elan, revient apres le pop
	local glow = if t < CHARGE_SECONDS then t / CHARGE_SECONDS else math.max(0, 1 - (t - CHARGE_SECONDS) / 0.9)
	for part, color in anim.leaves do
		part.Color = color:Lerp(GLOW_COLOR, glow * 0.55)
	end
	-- Frisson pendant l'elan
	local shiver = if t < CHARGE_SECONDS then 0.18 * (t / CHARGE_SECONDS) * math.sin(t * 70) else 0

	local s = 1 + anim.scale.x
	local sy = (1 + anim.squash.x) * s
	local sxz = (1 / math.sqrt(math.max(1 + anim.squash.x, 0.3))) * s
	Jelly.Apply(anim.rig, {
		sy = sy,
		sxz = sxz,
		bend = Vector3.new(anim.bendX.x + shiver, 0, anim.bendZ.x),
		grow = function(entry: Jelly.Entry): number
			if not anim.puffers[entry.part] or not anim.popped then
				return 1
			end
			-- Vague qui monte : chaque grappe gonfle un peu apres celle du dessous
			local u = (t - CHARGE_SECONDS - entry.height * 0.3) / 0.32
			if u <= 0 or u >= 1 then
				return 1
			end
			return 1 + 0.24 * math.sin(math.pi * u)
		end,
	})

	-- Feuilles qui volent
	for i = #anim.confetti, 1, -1 do
		local c = anim.confetti[i]
		c.life += dt
		local k = c.life / c.maxLife
		if k >= 1 then
			c.part:Destroy()
			table.remove(anim.confetti, i)
			continue
		end
		c.velocity += Vector3.new(0, -38, 0) * dt
		c.velocity *= (1 - math.min(1, dt * 0.8))
		c.angle += c.spin * dt
		local position = c.part.Position + c.velocity * dt
		local shrink = if k > 0.6 then 1 - (k - 0.6) / 0.4 else 1
		c.part.Size = c.size * math.max(shrink, 0.05)
		c.part.CFrame = CFrame.new(position) * CFrame.Angles(c.angle.X, c.angle.Y, c.angle.Z)
	end
	-- Onde au sol et lumiere
	local after = t - CHARGE_SECONDS
	local ring = anim.ring
	if ring then
		local u = math.clamp(after / 0.7, 0, 1)
		local eased = 1 - (1 - u) * (1 - u)
		local d = 4 + 30 * eased
		ring.Size = Vector3.new(0.2, d, d)
		ring.Transparency = 0.35 + 0.65 * u
		if u >= 1 then
			ring:Destroy()
			anim.ring = nil
		end
	end
	local light = anim.light
	if light then
		light.Brightness = if after < 0.08 then 4 * after / 0.08 else math.max(0, 4 * (1 - (after - 0.08) / 0.7))
	end

	local resting = Jelly.Resting(anim.squash) and Jelly.Resting(anim.scale) and Jelly.Resting(anim.bendX, 0.015) and Jelly.Resting(anim.bendZ, 0.015)
	if anim.popped and after > 1 and resting and #anim.confetti == 0 and anim.ring == nil then
		finish(anim)
	end
end

local function step(dt: number)
	for _, anim in anims do
		updateAnim(anim, dt)
	end
	if next(anims) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- mode "upgrade" : elan + pop ; modes "stage" / "level" : nouveau modele qui pousse depuis plus petit.
local function play(base: Model, mode: string)
	local existing = anims[base]
	if existing then
		if mode == "stage" or mode == "level" then
			finish(existing)
		else
			-- Deja en cours : on relance l'elan sur les memes pieces
			existing.t = 0
			existing.popped = false
			existing.squash.k, existing.squash.c = 500, 45
			existing.squash.target = -0.17
			return
		end
	end
	local parts, pivot = collectTree(base)
	if pivot == nil or #parts == 0 then
		return
	end
	if camDistance(pivot.Position) > FX_DISTANCE then
		return
	end
	local rig = Jelly.Capture(parts, pivot)
	local leaves: { [BasePart]: Color3 } = {}
	local puffers: { [BasePart]: boolean } = {}
	local leafColors: { Color3 } = {}
	for _, part in parts do
		if isLeaf(part) then
			leaves[part] = part.Color
			table.insert(leafColors, part.Color)
		end
		if isPuffer(part) then
			puffers[part] = true
		end
	end
	local anim: Anim = {
		base = base,
		rig = rig,
		leaves = leaves,
		puffers = puffers,
		t = 0,
		popped = false,
		squash = Jelly.Spring(500, 45), -- elan : se tasse sans rebondir
		scale = Jelly.Spring(130, 7),
		bendX = Jelly.Spring(45, 2.6),
		bendZ = Jelly.Spring(45, 2.6),
		confetti = {},
		ring = nil,
		holder = nil,
		light = nil,
		crown = (pivot * CFrame.new(0, rig.top * 0.62, 0)).Position,
		leafColors = leafColors,
	}
	anim.squash.target = -0.17
	if mode == "stage" or mode == "level" then
		-- Le nouveau modele part plus petit et pousse tout de suite
		anim.t = CHARGE_SECONDS
		anim.squash.target = 0
		anim.scale.x = if mode == "stage" then STAGE_SHRINK else LEVEL_SHRINK
		pop(anim)
	end
	anims[base] = anim
	if connection == nil then
		connection = RunService.RenderStepped:Connect(step)
	end
end

---------------------------------------------------------------------------------------------

local function registerFloor(floor: Model)
	local tree = floor:FindFirstChild("Tree") or floor:WaitForChild("Tree", 10)
	if tree == nil or floor.Parent == nil then
		return
	end
	local lastStage = tree:GetAttribute("TreeStage")
	local lastLevel = tree:GetAttribute("TreeLevel")
	local levelConnection = tree:GetAttributeChangedSignal("TreeLevel"):Connect(function()
		local stage = tree:GetAttribute("TreeStage")
		local level = tree:GetAttribute("TreeLevel")
		-- Seulement quand l'arbre grandit (pas apres un rebirth ou le depart du joueur)
		local grew = type(level) == "number" and type(lastLevel) == "number" and level > lastLevel
		local mode = if stage ~= lastStage then "stage" else "level"
		lastStage, lastLevel = stage, level
		if grew then
			-- Laisse le temps au nouveau modele d'arriver chez le client
			task.delay(0.15, function()
				if floor.Parent ~= nil then
					play(floor, mode)
				end
			end)
		end
	end)
	-- Etage detruit : couper l'ecoute et terminer une animation en cours
	FloorWatch.OnRemoved(floor, function()
		levelConnection:Disconnect()
		local anim = anims[floor]
		if anim then
			finish(anim)
		end
	end)
end

function TreeFxController.Init() end

function TreeFxController.Start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "TreeFx"
	folder.Parent = workspace
	fxFolder = folder

	FloorWatch.Watch(function(floor)
		registerFloor(floor)
	end)
end

-- Pour tester dans Studio (barre de commande client) : TreeFxController.Play(floor)
function TreeFxController.Play(floor: Model)
	play(floor, "upgrade")
end

return TreeFxController
