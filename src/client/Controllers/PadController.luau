--!strict
-- Pads d'action (Drop Fruits, Take Juices, Drop Juices, Collect Cash) : detection LOCALE de
-- l'arrivee du joueur sur un pad de SA base, chaque frame. Des qu'il monte dessus, remote PadEnter
-- (nom du pad) : le serveur agit tout de suite au lieu d'attendre que la position du personnage
-- lui arrive puis sa boucle des pads (gros delai avant l'animation). Le serveur reverifie tout
-- (sa base, position avec marge, delai) et sa boucle continue tant que le joueur reste dessus.
-- Effet local (2026-11-19) : en montant sur un pad, le dessus s'enfonce avec un rebond, le contour
-- flashe blanc, un cadre lumineux s'agrandit et s'efface, petit "clic" (Sounds.PadStep). Tant qu'on
-- reste dessus, le contour pulse. Seulement chez le joueur (pieces ancrees, pas repliquees).
-- Pads verts (2026-11-20 ; achat : Machines.<id>.Pad, BlenderN.Operator.Pad, Upgrade Tree) : le
-- serveur gere l'achat (UpgradeService) ; ici seulement l'effet : le bloc (PadTop seul, le neon ne
-- bouge pas) descend doucement (sans rebond) tant qu'on est dessus, remonte doucement apres, son Sounds.GreenPadStep.
-- Tour d'etages : on ne regarde que l'etage ouvert de SA base ou se trouve le joueur (hauteur),
-- chaque etage a son pad Cash (un tas d'argent par etage depuis le 2026-11-20) ; AutoCollect : serveur seul.
-- Doc : docs/systems/chaine-production.md, docs/systems/clients.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gameplay = require(Shared:WaitForChild("Config"):WaitForChild("Gameplay"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local PadController = {}

-- Nom envoye au serveur -> chemin de la zone dans l'etage
local PADS: { { name: string, folder: string, pad: string } } = {
	{ name = "FruitDrop", folder = "Production", pad = "FruitDropPad" },
	{ name = "TakeJuice", folder = "Production", pad = "TakeJuicePad" },
	{ name = "JuiceDrop", folder = "Counter", pad = "JuiceDropPad" },
	{ name = "Cash", folder = "Counter", pad = "CashPad" },
}

local player = Players.LocalPlayer
local started = false
local onPad: { [string]: boolean } = {}

-- Meme test que le serveur (PlayerCheck.IsOver), sans marge.
local function isOver(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Z) <= half.Z
		and localPos.Y >= -half.Y - 1
		and localPos.Y <= half.Y + Gameplay.PadHeightAbove
end

-- Deja dessus : on reste "dessus" avec une marge (bord, saut), sinon ca reclique en boucle
local function isStillOver(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local margin = Gameplay.PadExitMargin
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Z) <= half.Z + margin
		and localPos.Y >= -half.Y - 1 - margin
		and localPos.Y <= half.Y + Gameplay.PadExitHeight
end

local function findZone(floor: Model, folderName: string, padName: string): BasePart?
	local folder = floor:FindFirstChild(folderName)
	local pad = folder and folder:FindFirstChild(padName)
	local zone = pad and pad:FindFirstChild("PadZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end


---------------------------------------------------------------------------------------------
-- Effet visuel du pad

local PRESS_DEPTH = 0.16 -- studs : le dessus s'enfonce de ca quand on est dessus
local SPRING_SPEED = 38 -- raideur du ressort (plus grand = plus rapide)
local SPRING_DAMP = 0.42 -- amortissement (petit = plus de rebond)
local FLASH_SECONDS = 0.35 -- contour blanc qui revient a sa couleur
local WAVE_SECONDS = 0.5 -- cadre lumineux qui s'agrandit
local WAVE_SCALE = 1.7 -- taille finale du cadre (x la taille du pad)
local PULSE_AMOUNT = 0.3 -- part de blanc dans le contour qui pulse (joueur dessus)
local WHITE = Color3.new(1, 1, 1)

type Glow = { part: BasePart, color: Color3, rel: CFrame }
type PadFx = {
	top: BasePart,
	topCFrame: CFrame, -- position de repos du dessus (relue a chaque arrivee si le pad est au repos)
	glows: { Glow },
	pressed: boolean,
	depth: number,
	velocity: number,
	flash: number, -- 1 -> 0
	active: boolean, -- vrai tant que l'effet bouge quelque chose
}

local padFx: { [BasePart]: PadFx } = {} -- cle : PadZone
local waves: { { parts: { { part: BasePart, rel: CFrame, size: Vector3, long: string } }, center: CFrame, t: number } } =
	{}

-- Lit (ou relit) le pad au repos : position du dessus, couleurs et positions du contour.
local function readPad(zone: BasePart): PadFx?
	local model = zone.Parent
	local top = model and model:FindFirstChild("PadTop")
	if top == nil or not top:IsA("BasePart") then
		return nil
	end
	local fx = padFx[zone]
	if fx and fx.active then
		return fx
	end
	local glows: { Glow } = {}
	for _, child in (model :: Instance):GetChildren() do
		if child.Name == "PadGlow" and child:IsA("BasePart") then
			table.insert(glows, { part = child, color = child.Color, rel = top.CFrame:ToObjectSpace(child.CFrame) })
		end
	end
	local fresh: PadFx = {
		top = top,
		topCFrame = top.CFrame,
		glows = glows,
		pressed = if fx then fx.pressed else false,
		depth = 0,
		velocity = 0,
		flash = 0,
		active = false,
	}
	padFx[zone] = fresh
	return fresh
end

-- Cadre lumineux : copies du contour qui s'ecartent du centre et s'effacent.
local function spawnWave(fx: PadFx)
	local parts = {}
	for _, glow in fx.glows do
		local copy = glow.part:Clone()
		for _, child in copy:GetChildren() do
			child:Destroy()
		end
		copy.Name = "PadWaveFx"
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Color = WHITE
		copy.Parent = workspace.CurrentCamera
		local size = copy.Size
		table.insert(parts, { part = copy, rel = glow.rel, size = size, long = if size.X >= size.Z then "X" else "Z" })
	end
	table.insert(waves, { parts = parts, center = fx.topCFrame, t = 0 })
end

local function onEnterFx(zone: BasePart)
	local fx = readPad(zone)
	if fx == nil then
		return
	end
	fx.pressed = true
	fx.active = true
	fx.velocity += 4 -- petit coup vers le bas (profondeur positive = enfonce) : le ressort fait le rebond
	fx.flash = 1
	spawnWave(fx)
	SoundFx.PlayAt("PadStep", fx.topCFrame.Position)
end

local function stepFx(dt: number, clock: number)
	for zone, fx in padFx do
		if not fx.active then
			continue
		end
		if fx.top.Parent == nil then
			padFx[zone] = nil
			continue
		end
		-- Ressort : le dessus descend vers sa cible (enfonce ou au repos) avec un rebond
		local target = if fx.pressed then PRESS_DEPTH else 0
		local accel = (target - fx.depth) * SPRING_SPEED * SPRING_SPEED
			- fx.velocity * 2 * SPRING_DAMP * SPRING_SPEED
		fx.velocity += accel * dt
		fx.depth += fx.velocity * dt
		fx.flash = math.max(0, fx.flash - dt / FLASH_SECONDS)
		local pulse = if fx.pressed then PULSE_AMOUNT * (0.5 + 0.5 * math.sin(clock * 6)) else 0
		local white = math.max(fx.flash, pulse)
		local settled = not fx.pressed and math.abs(fx.depth) < 0.002 and math.abs(fx.velocity) < 0.01 and fx.flash <= 0
		if settled then
			-- Retour exact a l'etat d'origine, puis plus rien a faire
			fx.top.CFrame = fx.topCFrame
			for _, glow in fx.glows do
				glow.part.CFrame = fx.topCFrame * glow.rel
				glow.part.Color = glow.color
			end
			fx.active = false
			continue
		end
		local down = fx.topCFrame * CFrame.new(0, -fx.depth, 0)
		fx.top.CFrame = down
		for _, glow in fx.glows do
			glow.part.CFrame = down * glow.rel
			glow.part.Color = glow.color:Lerp(WHITE, white)
		end
	end
	-- Cadres lumineux
	for i = #waves, 1, -1 do
		local wave = waves[i]
		wave.t += dt / WAVE_SECONDS
		local t = math.min(wave.t, 1)
		local ease = 1 - (1 - t) ^ 3
		local scale = 1 + (WAVE_SCALE - 1) * ease
		for _, info in wave.parts do
			local rel = info.rel
			local offset = rel.Position
			info.part.CFrame = wave.center
				* CFrame.new(offset.X * scale, offset.Y + 0.15 + 0.6 * ease, offset.Z * scale)
				* rel.Rotation
			info.part.Size = if info.long == "X"
				then Vector3.new(info.size.X * scale, info.size.Y, info.size.Z)
				else Vector3.new(info.size.X, info.size.Y, info.size.Z * scale)
			info.part.Transparency = t
		end
		if wave.t >= 1 then
			for _, info in wave.parts do
				info.part:Destroy()
			end
			table.remove(waves, i)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Pads verts : le bloc (PadTop seul ; le contour neon reste en place) descend doucement

local GREEN_DEPTH = 0.2 -- studs
local GREEN_SPEED = 9 -- vitesse du lissage (plus grand = plus rapide)
local GREEN_REFRESH = 3 -- secondes entre deux recherches des pads verts de l'etage

type GreenPad = {
	zone: BasePart,
	top: BasePart,
	parts: { { part: BasePart, rest: CFrame } }, -- dessus (PadTop), position de repos
	pressed: boolean,
	depth: number,
	active: boolean,
}

local greenPads: { [BasePart]: GreenPad } = {} -- cle : PadZone

-- Pads verts = modeles "Pad" avec PadZone + PadTop (les 4 pads d'action ont d'autres noms).
local function scanGreenPads(floor: Model)
	local seen: { [BasePart]: boolean } = {}
	for _, item in floor:GetDescendants() do
		if item.Name ~= "Pad" or not item:IsA("Model") then
			continue
		end
		local zone = item:FindFirstChild("PadZone")
		local top = item:FindFirstChild("PadTop")
		if zone and zone:IsA("BasePart") and top and top:IsA("BasePart") then
			seen[zone] = true
			if greenPads[zone] == nil then
				greenPads[zone] = { zone = zone, top = top, parts = {}, pressed = false, depth = 0, active = false }
			end
		end
	end
	for zone, pad in greenPads do
		if not seen[zone] and not pad.active then
			greenPads[zone] = nil
		end
	end
end

local function onGreenEnter(pad: GreenPad)
	if pad.top.Transparency >= 1 or pad.top.LocalTransparencyModifier >= 1 then
		return -- pad cache (deja achete, ou pad Auto Sell avant le Waiter) : rien
	end
	if not pad.active then
		-- Position de repos relue a chaque arrivee (le pad ne bouge pas, mais on reste sur)
		table.clear(pad.parts)
		local model = pad.top.Parent
		for _, child in (if model then model:GetChildren() else {}) do
			if child:IsA("BasePart") and child.Name == "PadTop" then
				table.insert(pad.parts, { part = child, rest = child.CFrame })
			end
		end
	end
	pad.pressed = true
	pad.active = true
	SoundFx.PlayAt("GreenPadStep", pad.top.Position)
end

local function stepGreen(dt: number)
	local alpha = math.min(1, dt * GREEN_SPEED)
	for zone, pad in greenPads do
		if not pad.active then
			continue
		end
		if pad.top.Parent == nil then
			greenPads[zone] = nil
			continue
		end
		local target = if pad.pressed then GREEN_DEPTH else 0
		pad.depth += (target - pad.depth) * alpha
		if not pad.pressed and pad.depth < 0.002 then
			for _, info in pad.parts do
				info.part.CFrame = info.rest
			end
			pad.depth = 0
			pad.active = false
			continue
		end
		local offset = CFrame.new(0, -pad.depth, 0)
		for _, info in pad.parts do
			info.part.CFrame = offset * info.rest
		end
	end
end

function PadController.Init() end

function PadController.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local event = Remotes.WaitClientEvent("PadEnter")
		if event == nil then
			return
		end
		local floor: Model? = nil -- etage de SA base ou se trouve le joueur
		local zones: { [string]: BasePart } = {}
		local nextBaseCheck = 0
		local nextGreenScan = 0
		RunService.Heartbeat:Connect(function(dt: number)
			local now = os.clock()
			stepFx(dt, now)
			stepGreen(dt)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			-- Etage du joueur et zones : recherches 2 fois par seconde (la base est attribuee apres
			-- l'arrivee, les etages changent quand on monte / achete)
			if now >= nextBaseCheck then
				nextBaseCheck = now + 0.5
				local base = FloorWatch.MyBase()
				local found = if base and root and root:IsA("BasePart") then FloorWatch.FloorAt(base, root.Position.Y) else nil
				if found ~= floor or found == nil or found.Parent == nil then
					floor = found
					table.clear(zones)
					table.clear(onPad)
					for _, fx in padFx do
						fx.pressed = false
					end
					nextGreenScan = 0
				end
				if found and now >= nextGreenScan then
					nextGreenScan = now + GREEN_REFRESH
					scanGreenPads(found)
				end
				if found then
					for _, info in PADS do
						local zone = zones[info.name]
						if zone == nil or not zone:IsDescendantOf(found) then
							local fresh = findZone(found, info.folder, info.pad)
							if fresh then
								zones[info.name] = fresh
							else
								zones[info.name] = nil
							end
						end
					end
				end
			end
			if floor == nil or root == nil or not root:IsA("BasePart") then
				table.clear(onPad)
				for _, fx in padFx do
					fx.pressed = false
				end
				for _, pad in greenPads do
					pad.pressed = false
				end
				return
			end
			local position = root.Position
			for _, info in PADS do
				local zone = zones[info.name]
				local inside = zone ~= nil
					and (if onPad[info.name] then isStillOver(zone :: BasePart, position) else isOver(zone :: BasePart, position))
				if inside and not onPad[info.name] then
					event:FireServer(info.name)
					if zone then
						onEnterFx(zone)
					end
				elseif not inside and onPad[info.name] and zone then
					local fx = padFx[zone]
					if fx then
						fx.pressed = false -- le dessus remonte avec un rebond
					end
				end
				onPad[info.name] = inside or nil
			end
			-- Pads verts
			for _, pad in greenPads do
				local inside = if pad.pressed then isStillOver(pad.zone, position) else isOver(pad.zone, position)
				if inside and not pad.pressed then
					onGreenEnter(pad)
				elseif not inside and pad.pressed then
					pad.pressed = false -- le bloc remonte doucement
				end
			end
		end)
	end)
end

return PadController
