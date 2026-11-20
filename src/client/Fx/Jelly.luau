--!strict
-- Deformation "gelee" (squash & stretch) d'un groupe de pieces, cote client seulement.
-- On capture les pieces une fois (position, rotation et taille de depart dans le repere d'un
-- pivot), puis on les redessine a chaque image avec une pose :
--   * sy / sxz : etirement vertical / horizontal (1 = normal ; ecrase = sy < 1 et sxz > 1) ;
--   * bend : le haut se plie sur le cote (decalage en studs du sommet, le pied ne bouge pas,
--     courbe en h^2 : chaque piece s'incline le long de la courbe) ;
--   * pivot : pivot deplace ou tourne (vibrations) ;
--   * grow : multiplicateur de taille par piece (bouffee des feuilles...).
-- Restore() remet tout exactement comme au depart. Le serveur ne voit rien de tout ca.
-- Aussi : petits ressorts (Spring / Step) et Boing(), un "boing" tout fait sur n'importe quel groupe.
-- Doc : docs/systems/chaine-production.md (section Animations)

local RunService = game:GetService("RunService")

local Jelly = {}

export type Entry = {
	part: BasePart,
	baseCFrame: CFrame,
	baseSize: Vector3,
	rel: CFrame, -- position + rotation dans le repere du pivot
	height: number, -- 0 (pied) -> 1 (sommet)
	shape: string, -- "Block", "Ball" ou "Cylinder" (tailles imposees par Roblox)
}

export type Rig = {
	pivot: CFrame,
	entries: { Entry },
	top: number, -- hauteur du sommet au-dessus du pivot (studs)
	deformed: boolean,
}

export type Pose = {
	sy: number?,
	sxz: number?,
	pivot: CFrame?,
	bend: Vector3?,
	grow: ((Entry) -> number)?,
}

export type Spring = { x: number, v: number, target: number, k: number, c: number }

local MAX_STEP = 1 / 120
local MAX_DT = 1 / 15

function Jelly.Capture(parts: { BasePart }, pivot: CFrame): Rig
	local entries: { Entry } = {}
	local top = 0.5
	for _, part in parts do
		local rel = pivot:ToObjectSpace(part.CFrame)
		local shape = "Block"
		if part:IsA("Part") then
			if part.Shape == Enum.PartType.Ball then
				shape = "Ball"
			elseif part.Shape == Enum.PartType.Cylinder then
				shape = "Cylinder"
			end
		end
		table.insert(entries, {
			part = part,
			baseCFrame = part.CFrame,
			baseSize = part.Size,
			rel = rel,
			height = 0,
			shape = shape,
		})
		top = math.max(top, rel.Position.Y + part.Size.Y / 2)
	end
	for _, entry in entries do
		entry.height = math.clamp(entry.rel.Position.Y / top, 0, 1)
	end
	return { pivot = pivot, entries = entries, top = top, deformed = false }
end

-- Vrai si une piece capturee a disparu (streaming, reconstruction) : il faut recapturer.
function Jelly.IsBroken(rig: Rig): boolean
	for _, entry in rig.entries do
		if entry.part.Parent == nil then
			return true
		end
	end
	return false
end

-- Facteur d'etirement le long d'un axe de la piece (axe exprime dans le repere du pivot).
local function axisFactor(axis: Vector3, sxz: number, sy: number): number
	local x, y, z = axis.X * sxz, axis.Y * sy, axis.Z * sxz
	return math.sqrt(x * x + y * y + z * z)
end

local movedParts: { BasePart } = {}
local movedCFrames: { CFrame } = {}

function Jelly.Apply(rig: Rig, pose: Pose)
	local sy = pose.sy or 1
	local sxz = pose.sxz or 1
	local pivot = pose.pivot or rig.pivot
	local bend = pose.bend
	local grow = pose.grow
	table.clear(movedParts)
	table.clear(movedCFrames)
	for _, entry in rig.entries do
		local part = entry.part
		if part.Parent == nil then
			continue
		end
		local rel = entry.rel
		local p = rel.Position
		local rotation = rel.Rotation
		local position = Vector3.new(p.X * sxz, p.Y * sy, p.Z * sxz)
		if bend then
			local h = entry.height
			position += bend * (h * h)
			-- La piece suit la courbe : son "haut" s'aligne sur la pente (2 * bend * h / top)
			local slope = bend * (2 * h / rig.top)
			local magnitude = slope.Magnitude
			if magnitude > 1e-4 then
				local axis = Vector3.new(slope.Z, 0, -slope.X) / magnitude
				rotation = CFrame.fromAxisAngle(axis, math.atan(magnitude)) * rotation
			end
		end
		local base = entry.baseSize
		local fx = axisFactor(rel.RightVector, sxz, sy)
		local fy = axisFactor(rel.UpVector, sxz, sy)
		local fz = axisFactor(rel.LookVector, sxz, sy)
		local g = if grow then grow(entry) else 1
		local size = Vector3.new(base.X * fx, base.Y * fy, base.Z * fz) * g
		if entry.shape == "Ball" then
			local d = (size.X + size.Y + size.Z) / 3
			size = Vector3.new(d, d, d)
		elseif entry.shape == "Cylinder" then
			local d = (size.Y + size.Z) / 2
			size = Vector3.new(size.X, d, d)
		end
		part.Size = size
		table.insert(movedParts, part)
		table.insert(movedCFrames, pivot * CFrame.new(position) * rotation)
	end
	workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	rig.deformed = true
end

function Jelly.Restore(rig: Rig)
	if not rig.deformed then
		return
	end
	table.clear(movedParts)
	table.clear(movedCFrames)
	for _, entry in rig.entries do
		if entry.part.Parent ~= nil then
			entry.part.Size = entry.baseSize
			table.insert(movedParts, entry.part)
			table.insert(movedCFrames, entry.baseCFrame)
		end
	end
	workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	rig.deformed = false
end

---------------------------------------------------------------------------------------------
-- Ressorts : k = raideur (plus grand = plus rapide), c = amortissement (petit = plus de rebonds)

function Jelly.Spring(k: number, c: number): Spring
	return { x = 0, v = 0, target = 0, k = k, c = c }
end

function Jelly.Step(spring: Spring, dt: number)
	dt = math.min(dt, MAX_DT)
	local steps = math.max(1, math.ceil(dt / MAX_STEP))
	local h = dt / steps
	for _ = 1, steps do
		local accel = -spring.k * (spring.x - spring.target) - spring.c * spring.v
		spring.v += accel * h
		spring.x += spring.v * h
	end
end

function Jelly.Resting(spring: Spring, epsilon: number?): boolean
	local e = epsilon or 0.002
	return math.abs(spring.x - spring.target) < e and math.abs(spring.v) < e * 10
end

---------------------------------------------------------------------------------------------
-- Boing tout fait : le groupe s'ecrase puis rebondit comme de la gelee (machine achetee...).
-- key = l'objet qui possede l'effet (un 2e boing sur la meme cle relance le ressort).

type BoingState = { rig: Rig, squash: Spring, bendX: Spring, bendZ: Spring }

local boings: { [Instance]: BoingState } = {}
local boingConnection: RBXScriptConnection? = nil

local function stepBoings(dt: number)
	for key, state in boings do
		Jelly.Step(state.squash, dt)
		Jelly.Step(state.bendX, dt)
		Jelly.Step(state.bendZ, dt)
		if Jelly.Resting(state.squash) and Jelly.Resting(state.bendX, 0.01) and Jelly.Resting(state.bendZ, 0.01) then
			Jelly.Restore(state.rig)
			boings[key] = nil
			continue
		end
		local sy = 1 + state.squash.x
		Jelly.Apply(state.rig, {
			sy = sy,
			sxz = 1 / math.sqrt(math.max(sy, 0.2)),
			bend = Vector3.new(state.bendX.x, 0, state.bendZ.x),
		})
	end
	if next(boings) == nil and boingConnection then
		boingConnection:Disconnect()
		boingConnection = nil
	end
end

-- strength 1 = boing normal (ecrase d'environ 15 %, puis 2-3 rebonds en ~1 s).
function Jelly.Boing(key: Instance, parts: { BasePart }, pivot: CFrame, strength: number?)
	local s = strength or 1
	local state = boings[key]
	if state == nil then
		if #parts == 0 then
			return
		end
		state = {
			rig = Jelly.Capture(parts, pivot),
			squash = Jelly.Spring(260, 9),
			bendX = Jelly.Spring(140, 6),
			bendZ = Jelly.Spring(140, 6),
		}
		boings[key] = state
	end
	local angle = math.random() * math.pi * 2
	state.squash.v -= 2.6 * s
	state.bendX.v += math.cos(angle) * 5 * s
	state.bendZ.v += math.sin(angle) * 5 * s
	if boingConnection == nil then
		boingConnection = RunService.RenderStepped:Connect(stepBoings)
	end
end

function Jelly.IsBusy(key: Instance): boolean
	return boings[key] ~= nil
end

return Jelly
