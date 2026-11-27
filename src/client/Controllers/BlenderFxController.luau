--!strict
-- Animation des mixeurs (Production.Blenders.Blender1..4), cote client seulement : le serveur
-- decide de tout (ProductionService) et pose des attributs sur chaque BlenderN ; ce module montre :
-- 1. Pulse / PulseFruit : un fruit part de ConveyorStart, monte le tapis jusqu'a ConveyorTurn, longe
--    la rangee jusqu'a FeedPoint (au-dessus de la goulotte de CE mixeur) puis saute dans le bol.
-- 2. BowlFruits ("Apple;Orange") : les fruits restent empiles dans le bol (grille 3 x 3 par couche).
--    Petit "plop" a chaque fruit ; bol plein (BowlCount = BowlMax) = rebond plus fort.
-- 3. BlendStamp : gros demarrage en "gelee" (Fx/Jelly), le jus monte avec la couleur melangee des
--    fruits, la lame tourne, moteur ; la machine se plie / se deplie pendant BlendSeconds.
-- 4. PopStamp : "pop" (la machine s'etire vers le haut), le jus redescend ; les gobelets (attributs
--    PopFrom / PopIndex / PopAt) sautent tous du bec jusqu'a leur place sur la table a jus.
-- Une seule animation par mixeur ; rien au-dela de FX_DISTANCE ; sons coupes si le reglage est off.
-- Doc : docs/systems/chaine-production.md (section Animations)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local Gameplay = require(Shared:WaitForChild("Config"):WaitForChild("Gameplay")) :: any
local Sounds = require(Shared:WaitForChild("Config"):WaitForChild("Sounds")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local FX_DISTANCE = 150 -- au-dela, rien n'est anime (economie)
local HOP_SECONDS = 0.35 -- saut de la goulotte jusque dans le bol (compris dans ConveyorTravelSeconds)
local HOP_HEIGHT = 2.2
local HOP_FORWARD = 1.2 -- le saut part dans le prolongement du tapis
local HOP_SPIN = 9 -- rad / s : le fruit continue de tourner vers l'avant en l'air
local HOP_GROW = 0.15 -- il gonfle un peu en haut du saut
local SPAWN_SECONDS = 0.28 -- apparition "pop" a la sortie de la boite d'alimentation
local SPAWN_SCALE = 0.25
local SPAWN_DROP = 1.2 -- petite chute sur le tapis a l'apparition
local BELT_RAMP = 0.15 -- part du trajet ou le fruit accelere au depart
local BUMP_SPACING = 1.1 -- les lattes : un petit sautillement tous les ~1 stud
local BUMP_HEIGHT = 0.12
local CORNER_RADIUS = 1.8 -- virages arrondis du tapis
local CORNER_STEPS = 6
local COLOR_SECONDS = 0.7 -- le jus prend la couleur du melange
local FILL_SECONDS = 0.55 -- le jus monte dans le bol au demarrage
local DRAIN_SECONDS = 0.35 -- et redescend au "pop"
local BUILD_QUIET_SECONDS = 4 -- apres l'achat d'un mixeur : on laisse MachineFx le construire
local CUP_POP_SECONDS = 0.5 -- saut d'un gobelet du bec a la table
local CUP_POP_STAGGER = 0.06
local CUP_POP_HEIGHT = 4.5
local CUP_POP_MAX_AGE = 1.5 -- gobelets sortis il y a plus longtemps (arrivee dans la partie) : pas d'animation
local STACK_SPACING = 2 -- ecart entre deux fruits empiles (grille 3 x 3)
local STACK_LAYER = 1.6 -- hauteur d'une couche de fruits
local MOTOR_VOLUME = 1

-- Ordre de remplissage d'une couche (centre, coins, cotes) : le bol se remplit joliment
local SLOTS = {
	Vector2.new(0, 0),
	Vector2.new(-1, -1),
	Vector2.new(1, 1),
	Vector2.new(-1, 1),
	Vector2.new(1, -1),
	Vector2.new(0, -1),
	Vector2.new(0, 1),
	Vector2.new(-1, 0),
	Vector2.new(1, 0),
}

local BlenderFxController = {}

local started = false
local fxFolder: Folder? = nil

type Traveler = {
	model: Model,
	fruitId: string,
	t: number,
	points: { Vector3 }, -- chemin sur le tapis (bas du fruit), coins arrondis
	length: number,
	beltSeconds: number,
	radius: number,
	scale: number, -- echelle actuelle du modele (ScaleTo)
	dist: number, -- distance deja parcourue sur le tapis
	hop: boolean,
	hopFrom: Vector3,
	hopDir: Vector3, -- direction du tapis au moment du saut
	rot: CFrame, -- rotation de roulement a la fin du tapis
	axis: Vector3, -- axe de roulement
}

type Blender = {
	model: Model,
	production: Instance,
	rig: Jelly.Rig?,
	juice: BasePart?,
	juiceBaseSize: Vector3?,
	juiceGuard: RBXScriptConnection?, -- recache le jus si un autre script le rend visible, bol vide
	guardedJuice: BasePart?,
	blade: BasePart?,
	squash: Jelly.Spring,
	bendX: Jelly.Spring,
	bendZ: Jelly.Spring,
	intensity: number,
	runUntil: number,
	clock: number,
	bladeAngle: number,
	colorFrom: Color3,
	colorTo: Color3,
	colorT: number,
	fill: number, -- hauteur du jus 0 -> 1
	fillTarget: number,
	side: number,
	travelers: { Traveler },
	stack: { Model },
	stackIds: { string },
	splash: ParticleEmitter?,
	splashHolder: BasePart?,
	motor: Sound?,
	asleep: boolean,
	quietUntil: number,
}

local blenders: { [Model]: Blender } = {}

local function camDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

local function split(text: any): { string }
	local list: { string } = {}
	if type(text) == "string" and text ~= "" then
		for id in string.gmatch(text, "[^;]+") do
			table.insert(list, id)
		end
	end
	return list
end

local function fruitColor(fruitId: string): Color3
	local ok, color = pcall(FruitModels.GetBodyColor, fruitId)
	return if ok and typeof(color) == "Color3" then color else Color3.fromRGB(255, 150, 40)
end

-- Couleur du melange : moyenne des couleurs des fruits du mixage.
local function mixColor(ids: { string }): Color3
	if #ids == 0 then
		return Color3.fromRGB(255, 150, 40)
	end
	local r, g, b = 0, 0, 0
	for _, id in ids do
		local c = fruitColor(id)
		r += c.R
		g += c.G
		b += c.B
	end
	return Color3.new(r / #ids, g / #ids, b / #ids)
end

-- Trajet d'un fruit sur le tapis (attribut ConveyorTravel de Production, ProductionService).
local function travelSeconds(b: Blender): number
	local value = b.production:GetAttribute("ConveyorTravel")
	return if type(value) == "number" and value > 0 then value else Gameplay.ConveyorTravelSeconds
end

local function findPart(b: Blender, name: string): BasePart?
	local found = b.model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function isBuilt(b: Blender): boolean
	-- Mixeur sans UpgradeId : toujours construit. Sinon attribut Built (UpgradeService / SetupService).
	return b.model:GetAttribute("UpgradeId") == nil or b.model:GetAttribute("Built") == true
end

-- Bol vide d'un mixeur construit : la piece Juice doit rester cachee.
local function juiceHidden(b: Blender): boolean
	return isBuilt(b) and b.fill <= 0.01
end

-- La piece Juice a d'autres ecrivains de LocalTransparencyModifier (Fx/Reveal a la construction
-- par SetupController, GhostVisibilityController, CameraFadeController) qui la remettent a 0 a la
-- fin de leur effet. Bug du 2026-11-27 : mixeur vide avec un jus orange. Ce module a le dernier
-- mot : bol vide = cache, quel que soit l'ordre des scripts.
local function guardJuice(b: Blender)
	local juice = b.model:FindFirstChild("Juice", true)
	local part: BasePart? = if juice and juice:IsA("BasePart") then juice else nil
	b.juice = part
	if part == b.guardedJuice then
		return
	end
	if b.juiceGuard then
		b.juiceGuard:Disconnect()
		b.juiceGuard = nil
	end
	b.guardedJuice = part
	if part == nil then
		return
	end
	local guarded: BasePart = part
	local function enforce()
		if guarded.LocalTransparencyModifier < 1 and juiceHidden(b) then
			guarded.LocalTransparencyModifier = 1
		end
	end
	b.juiceGuard = guarded:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(enforce)
	enforce()
end

---------------------------------------------------------------------------------------------
-- Pieces du mixeur

local function pivotOf(b: Blender): CFrame?
	local cabinet = findPart(b, "Cabinet")
	if cabinet then
		-- Bas du meuble : les pieds ne bougent pas, tout le reste plie au-dessus
		return cabinet.CFrame * CFrame.new(0, -cabinet.Size.Y / 2, 0)
	end
	return nil
end

-- Capture les pieces de Build (une seule fois, quand rien n'est deforme ; recommence si le
-- streaming ou une reconstruction a enleve une piece).
local function ensureRig(b: Blender): Jelly.Rig?
	local rig = b.rig
	if rig and not Jelly.IsBroken(rig) then
		return rig
	end
	if rig then
		Jelly.Restore(rig)
	end
	local pivot = pivotOf(b)
	local build = b.model:FindFirstChild("Build")
	if pivot == nil or build == nil then
		return nil
	end
	local parts: { BasePart } = {}
	for _, item in build:GetDescendants() do
		if item:IsA("BasePart") and item.Name ~= "Foot" then
			table.insert(parts, item)
		end
	end
	local newRig = Jelly.Capture(parts, pivot)
	b.rig = newRig
	guardJuice(b)
	b.juiceBaseSize = if b.juice then b.juice.Size else nil
	b.blade = findPart(b, "Blade")
	return newRig
end

-- Fond du bol (marqueur BowlFloor, suit la machine quand elle se deforme).
local function bowlFloor(b: Blender): CFrame?
	local floor = findPart(b, "BowlFloor")
	return if floor then floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0) else nil
end

local function slotCFrame(b: Blender, index: number): CFrame?
	local floor = bowlFloor(b)
	if floor == nil then
		return nil
	end
	local i = index - 1
	local layer = i // #SLOTS
	local slot = SLOTS[(i % #SLOTS) + 1]
	-- Les couches impaires sont un peu decalees et tournees : un vrai tas, pas une grille
	local shift = if layer % 2 == 1 then 0.45 else 0
	local yaw = math.rad((index * 47) % 360)
	return floor
		* CFrame.new(slot.X * STACK_SPACING + shift, layer * STACK_LAYER + FruitModels.FruitSize * 0.45, slot.Y * STACK_SPACING - shift)
		* CFrame.Angles(math.rad((index * 13) % 20 - 10), yaw, 0)
end

local function placeStack(b: Blender)
	for index, model in b.stack do
		local cf = slotCFrame(b, index)
		if cf and model.Parent then
			model:PivotTo(cf)
		end
	end
end

local function clearStack(b: Blender)
	for _, model in b.stack do
		model:Destroy()
	end
	table.clear(b.stack)
	table.clear(b.stackIds)
end

local function addToStack(b: Blender, fruitId: string)
	local folder = fxFolder
	if folder == nil then
		return
	end
	local ok, model = pcall(FruitModels.CreateFruit, fruitId, true)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	table.insert(b.stack, model)
	table.insert(b.stackIds, fruitId)
	local cf = slotCFrame(b, #b.stack)
	if cf then
		model:PivotTo(cf)
	end
	model.Parent = folder
end

local function ensureMotor(b: Blender): Sound?
	local motor = b.motor
	local cabinet = findPart(b, "Cabinet")
	if motor and motor.Parent == cabinet then
		return motor
	end
	local def = Sounds.BlenderMotor
	if cabinet == nil or def == nil then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "BlenderMotorFx"
	sound.SoundGroup = SoundFx.Group() -- curseur Sons (menu Settings)
	sound.SoundId = def.id
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 70
	sound.Parent = cabinet
	b.motor = sound
	return sound
end

local function splashAt(b: Blender, position: Vector3, color: Color3, count: number)
	local folder = fxFolder
	if folder == nil then
		return
	end
	local holder = b.splashHolder
	local emitter = b.splash
	if holder == nil or emitter == nil or holder.Parent == nil then
		holder = Instance.new("Part")
		holder.Name = "BlenderSplash"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		local newEmitter = Instance.new("ParticleEmitter")
		newEmitter.Rate = 0
		newEmitter.EmissionDirection = Enum.NormalId.Top
		newEmitter.SpreadAngle = Vector2.new(35, 35)
		newEmitter.Speed = NumberRange.new(9, 15)
		newEmitter.Lifetime = NumberRange.new(0.35, 0.6)
		newEmitter.Acceleration = Vector3.new(0, -55, 0)
		newEmitter.Drag = 1
		newEmitter.LightEmission = 0.15
		newEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.05) })
		newEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.6) })
		newEmitter.Parent = holder
		holder.Parent = folder
		b.splashHolder = holder
		b.splash = newEmitter
		emitter = newEmitter
	end
	(holder :: BasePart).CFrame = CFrame.new(position)
	local e = emitter :: ParticleEmitter
	e.Color = ColorSequence.new(color)
	e:Emit(count)
end

local function wake(b: Blender)
	b.asleep = false
end

---------------------------------------------------------------------------------------------
-- Evenements du serveur (attributs)

-- Arrondit les coins du chemin (petits arcs) : le fruit tourne en douceur au lieu de casser net.
local function roundCorners(points: { Vector3 }): { Vector3 }
	local out = { points[1] }
	for i = 2, #points - 1 do
		local prev, here, nextP = points[i - 1], points[i], points[i + 1]
		local inLen = (here - prev).Magnitude
		local outLen = (nextP - here).Magnitude
		local r = math.min(CORNER_RADIUS, inLen * 0.45, outLen * 0.45)
		if r < 0.05 then
			table.insert(out, here)
			continue
		end
		local p0 = here + (prev - here).Unit * r
		local p2 = here + (nextP - here).Unit * r
		for k = 0, CORNER_STEPS do
			local u = k / CORNER_STEPS
			-- Courbe de Bezier quadratique : p0 -> (coin) -> p2
			table.insert(out, p0 * (1 - u) ^ 2 + here * 2 * u * (1 - u) + p2 * u ^ 2)
		end
	end
	table.insert(out, points[#points])
	return out
end

-- Un fruit part sur le tapis vers ce mixeur.
local function startTraveler(b: Blender, fruitId: string)
	local folder = fxFolder
	local function bottom(name: string, parent: Instance): Vector3?
		local p = parent:FindFirstChild(name, true)
		return if p and p:IsA("BasePart") then p.Position - Vector3.new(0, p.Size.Y / 2, 0) else nil
	end
	local a = bottom("ConveyorStart", b.production)
	local turn = bottom("ConveyorTurn", b.production)
	local feed = bottom("FeedPoint", b.model)
	if folder == nil or a == nil or turn == nil or feed == nil then
		return
	end
	local ok, model = pcall(FruitModels.CreateFruit, fruitId, true)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local _, size = model:GetBoundingBox()
	local points = roundCorners({ a, turn, Vector3.new(feed.X, turn.Y, feed.Z) })
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end
	local radius = math.max(size.Y / 2, 0.3)
	model:PivotTo(CFrame.new(a + Vector3.new(0, radius, 0)))
	model:ScaleTo(SPAWN_SCALE)
	model.Parent = folder
	table.insert(b.travelers, {
		model = model,
		fruitId = fruitId,
		t = 0,
		points = points,
		length = math.max(length, 0.1),
		-- Duree du trajet posee par le serveur (plus courte quand le tapis est ameliore)
		beltSeconds = math.max(0.3, travelSeconds(b) - HOP_SECONDS),
		radius = radius,
		scale = SPAWN_SCALE,
		dist = 0,
		hop = false,
		hopFrom = a,
		hopDir = Vector3.zAxis,
		rot = CFrame.identity,
		axis = Vector3.xAxis,
	})
	wake(b)
end

-- Position sur le chemin du tapis a la distance `d` (et direction du segment).
local function along(points: { Vector3 }, d: number): (Vector3, Vector3)
	local rest = d
	for i = 2, #points do
		local seg = points[i] - points[i - 1]
		local len = seg.Magnitude
		if rest <= len or i == #points then
			local u = if len > 1e-3 then math.clamp(rest / len, 0, 1) else 1
			return points[i - 1] + seg * u, if len > 1e-3 then seg / len else Vector3.zAxis
		end
		rest -= len
	end
	return points[#points], Vector3.zAxis
end

-- Avance sur le tapis (0 -> 1) : demarre doucement (le tapis "attrape" le fruit) puis vitesse
-- constante, en arrivant pile a 1 au bout de beltSeconds.
local function beltProgress(u: number): number
	local k = BELT_RAMP
	local v = 1 / (1 - k / 2)
	return if u < k then v * u * u / (2 * k) else v * (u - k / 2)
end

-- Depasse un peu puis revient (apparition "pop").
local function backOut(u: number): number
	local c = 2.2
	local x = u - 1
	return 1 + (c + 1) * x ^ 3 + c * x ^ 2
end

local function setScale(tr: Traveler, scale: number)
	if math.abs(scale - tr.scale) > 1e-3 then
		tr.scale = scale
		tr.model:ScaleTo(math.max(scale, 0.05))
	end
end

local function updateTravelers(b: Blender, dt: number)
	local list = b.travelers
	for i = #list, 1, -1 do
		local tr = list[i]
		tr.t += dt
		if tr.model.Parent == nil then
			table.remove(list, i)
			continue
		end
		if not tr.hop then
			-- Sur le tapis : il sort de la boite en "pop", accelere, roule et sautille sur les lattes
			local u = math.min(tr.t / tr.beltSeconds, 1)
			local d = tr.length * beltProgress(u)
			local pos, dir = along(tr.points, d)
			local flat = Vector3.new(dir.X, 0, dir.Z)
			local axis = Vector3.yAxis:Cross(flat)
			if axis.Magnitude > 1e-3 then
				tr.axis = axis.Unit
			end
			local spawnU = math.min(tr.t / SPAWN_SECONDS, 1)
			setScale(tr, SPAWN_SCALE + (1 - SPAWN_SCALE) * backOut(spawnU))
			-- Petite chute a la sortie de la boite, puis bosses des lattes
			local drop = SPAWN_DROP * (1 - spawnU) ^ 2
			local bump = math.abs(math.sin(d * math.pi / BUMP_SPACING)) * BUMP_HEIGHT * spawnU
			-- Le fruit roule (angle = distance / rayon), petit a petit : pas de saut dans les virages
			tr.rot = CFrame.fromAxisAngle(tr.axis, (d - tr.dist) / tr.radius) * tr.rot
			tr.dist = d
			tr.model:PivotTo(CFrame.new(pos + Vector3.new(0, tr.radius * tr.scale + drop + bump, 0)) * tr.rot)
			if u >= 1 then
				tr.hop = true
				tr.t = 0
				tr.hopFrom = pos + Vector3.new(0, tr.radius, 0)
				tr.hopDir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
				setScale(tr, 1)
			end
		else
			-- Saut en cloche dans le prolongement du tapis jusque dans le bol (la cible suit le bol
			-- qui bouge) ; il continue de tourner vers l'avant et gonfle un peu en l'air.
			local slot = slotCFrame(b, #b.stack + 1)
			local target = if slot then slot.Position else tr.hopFrom
			local u = math.min(tr.t / HOP_SECONDS, 1)
			local top = math.max(tr.hopFrom.Y, target.Y) + HOP_HEIGHT
			local mid = (tr.hopFrom + target) / 2 + tr.hopDir * HOP_FORWARD
			-- Point de controle place pour que le haut de la courbe soit a `top`
			local control = Vector3.new(mid.X, 2 * top - (tr.hopFrom.Y + target.Y) / 2, mid.Z)
			local pos = tr.hopFrom * (1 - u) ^ 2 + control * 2 * u * (1 - u) + target * u ^ 2
			setScale(tr, 1 + HOP_GROW * math.sin(u * math.pi))
			local tumble = CFrame.fromAxisAngle(tr.axis, tr.t * HOP_SPIN)
			tr.model:PivotTo(CFrame.new(pos) * tumble * tr.rot)
			if u >= 1 then
				-- Le fruit "empile" arrive par l'attribut BowlFruits du serveur (au meme moment)
				splashAt(b, target, fruitColor(tr.fruitId), 6)
				tr.model:Destroy()
				table.remove(list, i)
			end
		end
	end
end

local function clearTravelers(b: Blender)
	for _, tr in b.travelers do
		tr.model:Destroy()
	end
	table.clear(b.travelers)
end

-- Le contenu du bol a change (fruit arrive, ou bol vide au demarrage du mixage).
local function onBowlChanged(b: Blender)
	local ids = split(b.model:GetAttribute("BowlFruits"))
	local same = #ids >= #b.stackIds
	if same then
		for i, id in b.stackIds do
			if ids[i] ~= id then
				same = false
				break
			end
		end
	end
	if not same then
		clearStack(b)
	end
	local added = #ids - #b.stackIds
	for i = #b.stackIds + 1, #ids do
		addToStack(b, ids[i])
	end
	if added <= 0 then
		return
	end
	local pivot = pivotOf(b)
	if pivot == nil or camDistance(pivot.Position) > FX_DISTANCE then
		return
	end
	-- Petit plop a chaque fruit ; bol plein = rebond plus fort (la pastille "!" vient du serveur)
	local full = #ids >= (tonumber(b.model:GetAttribute("BowlMax")) or math.huge)
	b.squash.v -= if full then 3.2 else 1.1
	b.side = -b.side
	b.bendX.v += b.side * (if full then 5 else 2)
	wake(b)
	local top = slotCFrame(b, #ids)
	if top then
		SoundFx.PlayAt("BlenderPlop", top.Position)
	end
end

-- Le joueur (ou l'operateur) a appuye : gros demarrage.
local function onBlendStart(b: Blender)
	local pivot = pivotOf(b)
	if pivot == nil or camDistance(pivot.Position) > FX_DISTANCE then
		return
	end
	local ids = split(b.model:GetAttribute("BlendFruits"))
	local color = mixColor(ids)
	local juice = b.juice or findPart(b, "Juice")
	b.colorFrom = if juice then juice.Color else color
	b.colorTo = color
	b.colorT = 0
	b.fillTarget = 1
	b.runUntil = os.clock() + Gameplay.BlendSeconds
	-- Elan : la machine s'ecrase fort, se tord, puis part en rythme
	b.squash.v -= 5
	local angle = math.random() * math.pi * 2
	b.bendX.v += math.cos(angle) * 9
	b.bendZ.v += math.sin(angle) * 9
	local floor = bowlFloor(b)
	if floor then
		splashAt(b, floor.Position + Vector3.new(0, 2, 0), color, 22)
	end
	wake(b)
end

-- Hauteur du jus qui reste dans le mixeur quand la table est pleine (attribut HeldJuices du
-- serveur) : proportionnelle au bol, au moins un fond visible ; 0 = mixeur vide.
local function heldFill(b: Blender): number
	local held = tonumber(b.model:GetAttribute("HeldJuices")) or 0
	if held <= 0 then
		return 0
	end
	local max = math.max(tonumber(b.model:GetAttribute("BowlMax")) or held, 1)
	return math.clamp(held / max, 0.2, 1)
end

-- Fin du mixage : "pop" vers le haut, le jus redescend (les gobelets sautent, voir onCupAdded).
-- S'il reste du jus faute de place sur la table, il redescend seulement jusqu'a son niveau.
local function onPop(b: Blender)
	local pivot = pivotOf(b)
	b.runUntil = 0
	b.fillTarget = heldFill(b)
	if pivot == nil or camDistance(pivot.Position) > FX_DISTANCE then
		b.fill = 0
		return
	end
	b.squash.v += 5.5
	b.bendX.v += b.side * 3
	local floor = bowlFloor(b)
	if floor then
		splashAt(b, floor.Position + Vector3.new(0, 4, 0), b.colorTo, 16)
	end
	SoundFx.PlayAt("JuiceDone", pivot.Position)
	wake(b)
end

---------------------------------------------------------------------------------------------
-- Chaque image

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Le jus monte / descend (hauteur `fill`), pose apres Jelly.Apply (qui remet la taille de depart).
local function applyFill(b: Blender)
	local juice = b.juice
	if juice == nil or juice.Parent == nil then
		return
	end
	local f = smooth(b.fill)
	if f <= 0.01 then
		juice.LocalTransparencyModifier = 1
		return
	end
	juice.LocalTransparencyModifier = 0
	local size = juice.Size
	local newY = math.max(size.Y * f, 0.05)
	juice.Size = Vector3.new(size.X, newY, size.Z)
	juice.CFrame = juice.CFrame * CFrame.new(0, -(size.Y - newY) / 2, 0)
end

local function sleep(b: Blender)
	if b.rig then
		Jelly.Restore(b.rig)
	end
	placeStack(b)
	if b.motor then
		b.motor:Stop()
	end
	local juice = b.juice
	if juice and juice.Parent and isBuilt(b) then
		juice.LocalTransparencyModifier = if b.fill > 0.01 then 0 else 1
	end
	b.asleep = true
end

local function updateBlender(b: Blender, dt: number, now: number)
	local pivot = pivotOf(b)
	if pivot == nil then
		return
	end
	if camDistance(pivot.Position) > FX_DISTANCE then
		-- Trop loin : on remet la machine droite et on n'anime plus
		if not b.asleep then
			clearTravelers(b)
			b.intensity = 0
			b.fill = b.fillTarget
			sleep(b)
		end
		return
	end
	updateTravelers(b, dt)
	-- Achat du mixeur : MachineFx le construit piece par piece puis fait un boing : on attend
	if now < b.quietUntil or Jelly.IsBusy(b.model) or not isBuilt(b) then
		return
	end

	Jelly.Step(b.squash, dt)
	Jelly.Step(b.bendX, dt)
	Jelly.Step(b.bendZ, dt)
	local target = if now < b.runUntil then 1 else 0
	local rate = if target > b.intensity then 6 else 2.5
	b.intensity += (target - b.intensity) * math.min(1, dt * rate)
	if b.intensity < 0.003 then
		b.intensity = 0
	end
	local fillRate = if b.fillTarget > b.fill then 1 / FILL_SECONDS else 1 / DRAIN_SECONDS
	b.fill = if b.fillTarget > b.fill
		then math.min(b.fillTarget, b.fill + dt * fillRate)
		else math.max(b.fillTarget, b.fill - dt * fillRate)
	local i = b.intensity
	b.clock += dt * (0.4 + 0.8 * i)
	b.bladeAngle = (b.bladeAngle + dt * 50 * i) % (math.pi * 2)

	local resting = Jelly.Resting(b.squash) and Jelly.Resting(b.bendX, 0.01) and Jelly.Resting(b.bendZ, 0.01)
	-- Jus en attente a mi-hauteur : on reste eveille (au repos, la piece Juice reprend sa taille pleine)
	local partial = b.fill > 0.01 and b.fill < 0.99
	if i == 0 and resting and not partial and #b.travelers == 0 and b.colorT >= 1 and b.fill == b.fillTarget then
		if not b.asleep then
			sleep(b)
		end
		return
	end
	b.asleep = false

	local rig = ensureRig(b)
	if rig == nil then
		return
	end
	local t = b.clock
	-- Mixage : se plie / se deplie en 8 (plus fort qu'avant : c'est le moment cle), s'ecrase en
	-- rythme et tremble ; au repos les ressorts font juste les plops et le pop.
	local swayX = 0.8 * math.sin(t * 7) + 0.06 * math.sin(t * 61)
	local swayZ = 0.5 * math.sin(t * 4.7 + 1.1) + 0.06 * math.sin(t * 53 + 0.4)
	local pump = 0.07 * math.sin(t * 11)
	local sy = 1 + b.squash.x + pump * i
	Jelly.Apply(rig, {
		sy = sy,
		sxz = 1 / math.sqrt(math.max(sy, 0.3)),
		bend = Vector3.new(b.bendX.x + swayX * i, 0, b.bendZ.x + swayZ * i),
	})
	applyFill(b)
	placeStack(b)
	-- Detail : la lame tourne
	local blade = b.blade
	if blade and blade.Parent and i > 0 then
		blade.CFrame = blade.CFrame * CFrame.Angles(0, b.bladeAngle, 0)
	end
	-- Le jus prend la couleur du melange
	if b.colorT < 1 then
		b.colorT = math.min(1, b.colorT + dt / COLOR_SECONDS)
		local juice = b.juice
		if juice and juice.Parent then
			juice.Color = b.colorFrom:Lerp(b.colorTo, smooth(b.colorT))
		end
	end
	-- Moteur : volume et vitesse suivent l'intensite
	local motor = ensureMotor(b)
	if motor then
		if i > 0.02 and SoundFx.IsEnabled() then -- reglage Sons (menu Settings)
			local def = Sounds.BlenderMotor
			motor.Volume = (if def then def.volume else MOTOR_VOLUME) * i
			motor.PlaybackSpeed = 0.85 + 0.35 * i
			if not motor.IsPlaying then
				motor:Play()
			end
		elseif motor.IsPlaying then
			motor:Stop()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Gobelets qui sautent du bec jusqu'a la table (attributs poses par ProductionService)

type CupHop = { model: Model, from: Vector3, to: CFrame, t: number, delay: number }
local cupHops: { CupHop } = {}

local function onCupAdded(item: Instance)
	if not item:IsA("Model") then
		return
	end
	local from = item:GetAttribute("PopFrom")
	local index = item:GetAttribute("PopIndex")
	local at = item:GetAttribute("PopAt")
	if typeof(from) ~= "Vector3" or type(at) ~= "number" or workspace:GetServerTimeNow() - at > CUP_POP_MAX_AGE then
		return
	end
	local to = item:GetPivot()
	if camDistance(to.Position) > FX_DISTANCE then
		return
	end
	local k = if type(index) == "number" then index else 1
	-- Cache dans le bec jusqu'a son saut
	item:PivotTo(CFrame.new(from) * to.Rotation)
	table.insert(cupHops, { model = item, from = from, to = to, t = 0, delay = (k - 1) * CUP_POP_STAGGER })
	if k == 1 then
		SoundFx.PlayAt("CupPop", from)
	end
end

local function updateCups(dt: number)
	for i = #cupHops, 1, -1 do
		local hop = cupHops[i]
		if hop.model.Parent == nil then
			table.remove(cupHops, i)
			continue
		end
		hop.t += dt
		local u = math.clamp((hop.t - hop.delay) / CUP_POP_SECONDS, 0, 1)
		local pos = hop.from:Lerp(hop.to.Position, u) + Vector3.new(0, CUP_POP_HEIGHT * 4 * u * (1 - u), 0)
		local tumble = (1 - u) * math.pi * 2
		hop.model:PivotTo(CFrame.new(pos) * hop.to.Rotation * CFrame.Angles(tumble, 0, 0))
		if u >= 1 then
			hop.model:PivotTo(hop.to)
			table.remove(cupHops, i)
		end
	end
end

local function watchCups(floor: Model)
	local dynamic = floor:FindFirstChild("Dynamic") or floor:WaitForChild("Dynamic", 10)
	if dynamic == nil then
		return
	end
	local function watchFolder(folder: Instance)
		if folder.Name == "Production" and folder:IsA("Folder") then
			folder.ChildAdded:Connect(onCupAdded)
		end
	end
	dynamic.ChildAdded:Connect(watchFolder)
	for _, child in dynamic:GetChildren() do
		watchFolder(child)
	end
end

---------------------------------------------------------------------------------------------
-- Inscription des etages (un etage ouvert = sa Production, ses mixeurs, ses gobelets)

local function forgetBlender(b: Blender)
	if b.juiceGuard then
		b.juiceGuard:Disconnect()
		b.juiceGuard = nil
	end
	clearTravelers(b)
	clearStack(b)
	if b.splashHolder then
		b.splashHolder:Destroy()
		b.splashHolder = nil
	end
	blenders[b.model] = nil
end

local function registerBlender(production: Instance, model: Model)
	if blenders[model] then
		return
	end
	local b: Blender = {
		model = model,
		production = production,
		rig = nil,
		juice = nil,
		juiceBaseSize = nil,
		juiceGuard = nil,
		guardedJuice = nil,
		blade = nil,
		squash = Jelly.Spring(160, 6), -- ~2 rebonds par seconde, doux
		bendX = Jelly.Spring(70, 3.5), -- se plie / se deplie lentement
		bendZ = Jelly.Spring(70, 3.5),
		intensity = 0,
		runUntil = 0,
		clock = 0,
		bladeAngle = 0,
		colorFrom = Color3.new(1, 1, 1),
		colorTo = Color3.new(1, 1, 1),
		colorT = 1,
		fill = 0,
		fillTarget = 0,
		side = 1,
		travelers = {},
		stack = {},
		stackIds = {},
		splash = nil,
		splashHolder = nil,
		motor = nil,
		asleep = true,
		quietUntil = 0,
	}
	blenders[model] = b
	-- Bol vide au depart : pas de jus visible (il monte au demarrage du mixage), sauf jus en attente
	b.fill = heldFill(b)
	b.fillTarget = b.fill
	guardJuice(b)
	if b.juice and isBuilt(b) then
		b.juice.LocalTransparencyModifier = if b.fill > 0.01 then 0 else 1
	end
	-- StreamingEnabled / reconstruction : la piece Juice peut arriver apres l'inscription
	model.DescendantAdded:Connect(function(item: Instance)
		if item.Name == "Juice" and item:IsA("BasePart") then
			guardJuice(b)
		end
	end)
	model:GetAttributeChangedSignal("Pulse"):Connect(function()
		local fruitId = model:GetAttribute("PulseFruit")
		local pivot = pivotOf(b)
		if type(fruitId) ~= "string" or pivot == nil or camDistance(pivot.Position) > FX_DISTANCE then
			return
		end
		startTraveler(b, fruitId)
	end)
	model:GetAttributeChangedSignal("BowlFruits"):Connect(function()
		onBowlChanged(b)
	end)
	model:GetAttributeChangedSignal("BlendStamp"):Connect(function()
		onBlendStart(b)
	end)
	model:GetAttributeChangedSignal("PopStamp"):Connect(function()
		onPop(b)
	end)
	-- Jus en attente (table pleine) : le niveau baisse a mesure qu'il coule sur la table
	local lastHeld = tonumber(model:GetAttribute("HeldJuices")) or 0
	model:GetAttributeChangedSignal("HeldJuices"):Connect(function()
		local held = tonumber(model:GetAttribute("HeldJuices")) or 0
		local poured = held < lastHeld
		lastHeld = held
		if model:GetAttribute("Blending") == true then
			return -- pendant le mixage le bol reste plein (onPop fixera le niveau)
		end
		b.fillTarget = heldFill(b)
		if poured then
			b.squash.v += 1.5 -- petit hoquet a chaque versement
		end
		wake(b)
	end)
	model:GetAttributeChangedSignal("BuildStamp"):Connect(function()
		-- MachineFx deplace les pieces (construction) : on oublie l'ancienne capture
		b.rig = nil
		b.quietUntil = os.clock() + BUILD_QUIET_SECONDS
	end)
	model:GetAttributeChangedSignal("Built"):Connect(function()
		local juice = b.juice
		if juice and isBuilt(b) then
			juice.LocalTransparencyModifier = if b.fill > 0.01 then 0 else 1
		elseif juice then
			juice.LocalTransparencyModifier = 0 -- fantome : la machine entiere est teintee
		end
	end)
	model.Destroying:Connect(function()
		forgetBlender(b)
	end)
	onBowlChanged(b)
end

local function registerFloor(floor: Model)
	local production = floor:FindFirstChild("Production") or floor:WaitForChild("Production", 10)
	local folder = production and (production:FindFirstChild("Blenders") or production:WaitForChild("Blenders", 10))
	if production == nil or folder == nil or floor.Parent == nil then
		return
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			registerBlender(production, child)
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			registerBlender(production, child)
		end
	end
	-- Etage detruit (achat de l'etage suivant, depart du proprietaire) : oublier ses mixeurs
	FloorWatch.OnRemoved(floor, function()
		for _, b in blenders do
			if b.production == production then
				forgetBlender(b)
			end
		end
	end)
	task.spawn(watchCups, floor)
end

function BlenderFxController.Init() end

function BlenderFxController.Start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "BlenderFx"
	folder.Parent = workspace
	fxFolder = folder

	FloorWatch.Watch(function(floor)
		registerFloor(floor)
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		for _, b in blenders do
			updateBlender(b, dt, now)
		end
		updateCups(dt)
	end)
end

return BlenderFxController
