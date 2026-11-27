--!strict
-- Decor de la carte : arbres ronds et sapins en blocs (studs partout), buissons, fleurs, rochers,
-- collines vertes en gradins. Purement visuel (pas de collision sur les petits objets).
-- Positions fixes (graines 42 et 2027).
--
-- Deux parties :
--   1. Le coeur (comme avant) : arbres des couloirs entre les bases, foret derriere les bases,
--      arbres du spawn. Bases : 3 au nord (z 30..168) et 3 au sud, x de -278 a 278.
--   2. Les alentours (2026-11-27) : les murs invisibles ont recule de 300 studs (01-ground-road,
--      zone 1380 x 1060). La bande en plus (entre l'ancien coeur et les murs) recoit une foret a
--      explorer : grands arbres (plus gros pres des murs), collines a grimper (marches de 5 studs
--      au plus : on monte en sautant), rochers, buissons, fleurs, mares. L'ancien anneau de collines
--      (z +-220, x +-396) est retire : il aurait ferme l'acces a la bande.
--      Dossiers Decor.Trees.Outskirts (cache en Low Quality avec Decor.Trees, vu par CameraFade) et
--      Decor.Hills.Outskirts (collines, rochers, mares : toujours visibles).
--
-- Tout est sans ombre et sans CanTouch (comme apres 05-shadows et 06-no-touch).
-- Ce qui est derriere les murs (crete, montagnes, volcan) : 09-mountains.luau.
--
-- SAMPLE_NORTH = true : echantillon. Ne reconstruit PAS le coeur ; retire la rangee nord de
-- l'ancien anneau et ne pose que les alentours du nord (z >= 200). Meme tirage que la carte
-- complete : le nord de l'echantillon = le nord de la version finale.
-- SAMPLE_NORTH = false : detruit et recree tout Workspace.Map.Decor.
-- Doc : docs/systems/carte-bases.md

local SAMPLE_NORTH = true

local ZONE_HX, ZONE_HZ = 690, 530 -- murs invisibles (01-ground-road : GROUND_SIZE / 2)
local CORE_HX, CORE_HZ = 384, 214 -- ancien coeur de carte (decor d'origine)
local SAMPLE_Z = 200

local TRUNK = Color3.fromRGB(112, 78, 52)
local LEAVES = { Color3.fromRGB(46, 160, 52), Color3.fromRGB(58, 176, 58), Color3.fromRGB(74, 190, 64) } -- vert vif (2026-11-19)
local PINE = { Color3.fromRGB(36, 140, 70), Color3.fromRGB(44, 154, 76), Color3.fromRGB(54, 166, 80) }
local BUSH = { Color3.fromRGB(56, 170, 56), Color3.fromRGB(70, 186, 64) }
local HILL = { Color3.fromRGB(64, 160, 58), Color3.fromRGB(70, 166, 62), Color3.fromRGB(78, 174, 66) } -- adoucies (2026-11-19 nuit)
local ROCK = Color3.fromRGB(150, 150, 146)
local ROCKS = { Color3.fromRGB(150, 150, 146), Color3.fromRGB(128, 130, 136), Color3.fromRGB(166, 164, 158) }
local FLOWERS = { Color3.fromRGB(226, 120, 150), Color3.fromRGB(246, 236, 220), Color3.fromRGB(240, 204, 84), Color3.fromRGB(190, 120, 210) }
local SAND = Color3.fromRGB(226, 208, 160)
local WATER = Color3.fromRGB(86, 176, 232)
local LILY = Color3.fromRGB(64, 168, 70)

local STUDS = Enum.SurfaceType.Studs
local SMOOTH = Enum.SurfaceType.Smooth

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CastShadow = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = STUDS
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.FrontSurface = STUDS
	p.BackSurface = STUDS
	p.LeftSurface = STUDS
	p.RightSurface = STUDS
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }
local LIQUID = {
	CanCollide = false,
	CanQuery = false,
	Material = Enum.Material.SmoothPlastic,
	TopSurface = SMOOTH,
	BottomSurface = SMOOTH,
	FrontSurface = SMOOTH,
	BackSurface = SMOOTH,
	LeftSurface = SMOOTH,
	RightSurface = SMOOTH,
}

-- Feuillage des arbres et buissons du decor : surface Universal (stud en creux + bosse),
-- demandee par l'utilisateur le 2026-11-19 (voir docs/style.md, regle des studs).
local function universal(extra: { [string]: any }?): { [string]: any }
	local u = Enum.SurfaceType.Universal
	local t: { [string]: any } = { TopSurface = u, BottomSurface = u, FrontSurface = u, BackSurface = u, LeftSurface = u, RightSurface = u }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local LEAF = universal()
local BUSH_LEAF = universal(DECOR)

local map = workspace:FindFirstChild("Map")
assert(map, "Lancer 01 d'abord")

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- Arbre rond : tronc + grappes de feuilles tournees. `lite` : une grappe en moins (alentours).
local function roundTree(parent: Instance, r: Random, x: number, z: number, s: number, lite: boolean?, y0: number?): Model
	local m = Instance.new("Model")
	m.Name = "RoundTree"
	local rot = r:NextNumber(0, 90)
	local y = y0 or 0
	part(m, "Trunk", Vector3.new(1.8, 6, 1.8) * s, CFrame.new(x, y + 3 * s, z) * yaw(rot), TRUNK)
	part(m, "Leaves1", Vector3.new(8, 5, 8) * s, CFrame.new(x, y + 8 * s, z) * yaw(rot + 10), LEAVES[1], LEAF)
	part(m, "Leaves2", Vector3.new(5.5, 3.5, 5.5) * s, CFrame.new(x + 0.6 * s, y + 11.6 * s, z - 0.4 * s) * yaw(rot + 35), LEAVES[2], LEAF)
	part(m, "Leaves3", Vector3.new(4, 3, 4) * s, CFrame.new(x - 3.2 * s, y + 8.6 * s, z + 2 * s) * yaw(rot - 20), LEAVES[3], LEAF)
	if not lite then
		part(m, "Leaves4", Vector3.new(3.6, 2.6, 3.6) * s, CFrame.new(x + 3 * s, y + 7.4 * s, z + 2.4 * s) * yaw(rot + 50), LEAVES[2], LEAF)
	end
	m.Parent = parent
	return m
end

-- Sapin : 3 etages un peu tournes. `lite` : sans la pointe.
local function pine(parent: Instance, r: Random, x: number, z: number, s: number, lite: boolean?, y0: number?): Model
	local m = Instance.new("Model")
	m.Name = "Pine"
	local rot = r:NextNumber(0, 90)
	local y = y0 or 0
	part(m, "Trunk", Vector3.new(1.6, 4, 1.6) * s, CFrame.new(x, y + 2 * s, z) * yaw(rot), TRUNK)
	part(m, "Leaves1", Vector3.new(7, 4, 7) * s, CFrame.new(x, y + 6 * s, z) * yaw(rot + 15), PINE[1], LEAF)
	part(m, "Leaves2", Vector3.new(5.2, 3.5, 5.2) * s, CFrame.new(x, y + 9.6 * s, z) * yaw(rot + 35), PINE[2], LEAF)
	part(m, "Leaves3", Vector3.new(3.2, 3, 3.2) * s, CFrame.new(x, y + 12.8 * s, z) * yaw(rot + 5), PINE[3], LEAF)
	if not lite then
		part(m, "Tip", Vector3.new(1.4, 1.6, 1.4) * s, CFrame.new(x, y + 15 * s, z) * yaw(rot + 25), PINE[3], LEAF)
	end
	m.Parent = parent
	return m
end

local function bush(parent: Instance, r: Random, x: number, z: number, s: number): Model
	local m = Instance.new("Model")
	m.Name = "Bush"
	part(m, "A", Vector3.new(3.4, 2.6, 3.4) * s, CFrame.new(x, 1.3 * s, z) * yaw(r:NextNumber(0, 90)), BUSH[1], BUSH_LEAF)
	part(m, "B", Vector3.new(2.4, 2, 2.4) * s, CFrame.new(x + 1.6 * s, 1 * s, z + 0.8 * s) * yaw(r:NextNumber(0, 90)), BUSH[2], BUSH_LEAF)
	m.Parent = parent
	return m
end

local function flowers(parent: Instance, r: Random, x: number, z: number, count: number, spread: number)
	for _ = 1, count do
		local fx, fz = x + r:NextNumber(-spread, spread), z + r:NextNumber(-spread, spread)
		local rot = yaw(r:NextNumber(0, 90))
		part(parent, "FlowerLeaves", Vector3.new(0.9, 0.25, 0.9), CFrame.new(fx, 0.125, fz) * rot, BUSH[2], DECOR)
		part(parent, "Flower", Vector3.new(0.55, 0.55, 0.55), CFrame.new(fx, 0.52, fz) * rot, FLOWERS[r:NextInteger(1, #FLOWERS)], DECOR)
	end
end

---------------------------------------------------------------------------------------------
-- 1. Le coeur de la carte

local decor: Instance
local trees: Instance
local hills: Instance

if SAMPLE_NORTH then
	-- Echantillon : on garde le coeur tel quel, on ouvre seulement le nord
	local existing = map:FindFirstChild("Decor")
	assert(existing, "Echantillon : Map.Decor doit deja exister (sinon SAMPLE_NORTH = false)")
	decor = existing
	trees = decor:FindFirstChild("Trees") :: Instance
	hills = decor:FindFirstChild("Hills") :: Instance
	assert(trees and hills, "Map.Decor.Trees / Hills absents")
	for _, folder in { trees, hills } do
		local old = folder:FindFirstChild("Outskirts")
		if old then
			old:Destroy()
		end
	end
	for _, h in hills:GetChildren() do
		if h:IsA("Model") and h.Name == "Hill" and h:GetPivot().Position.Z > SAMPLE_Z then
			h:Destroy()
		end
	end
else
	local old = map:FindFirstChild("Decor")
	if old then
		old:Destroy()
	end
	local rng = Random.new(42)
	local newDecor = Instance.new("Folder")
	newDecor.Name = "Decor"
	newDecor.Parent = map
	decor = newDecor

	local newTrees = Instance.new("Folder")
	newTrees.Name = "Trees"
	newTrees.Parent = decor
	trees = newTrees
	for _, side in { 1, -1 } do
		-- Couloirs entre les bases (x = -100 et 100) et bords exterieurs (x = +-296)
		for _, gx in { -100, 100 } do
			roundTree(trees, rng, gx - 4, side * 70, 1.1)
			pine(trees, rng, gx + 6, side * 92, 1.2)
			roundTree(trees, rng, gx + 3, side * 48, 0.9)
			bush(trees, rng, gx - 6, side * 34, 1)
			bush(trees, rng, gx + 7, side * 37, 0.8)
			flowers(trees, rng, gx, side * 58, 8, 3)
		end
		for _, gx in { -296, 296 } do
			roundTree(trees, rng, gx, side * 55, 1.2)
			pine(trees, rng, gx + 8, side * 85, 1.3)
			bush(trees, rng, gx - 5, side * 30, 1)
		end
		-- Foret derriere les bases (z de 178 a 208), melange sapins / arbres ronds
		local x = -360
		while x < 360 do
			local z = side * rng:NextNumber(178, 208)
			local s = rng:NextNumber(0.9, 1.5)
			if rng:NextNumber() < 0.55 then
				pine(trees, rng, x + rng:NextNumber(-4, 4), z, s)
			else
				roundTree(trees, rng, x + rng:NextNumber(-4, 4), z, s)
			end
			x += rng:NextNumber(9, 16)
		end
		task.wait()
	end
	-- Autour de la place du spawn
	for _, p in { Vector2.new(-340, 30), Vector2.new(-340, -30), Vector2.new(-360, 6), Vector2.new(-296, 38), Vector2.new(-296, -38) } do
		roundTree(trees, rng, p.X, p.Y, 1.1)
	end
	bush(trees, rng, -338, 18, 1)
	bush(trees, rng, -338, -18, 1)
	task.wait()

	-- Quelques rochers derriere les bases (l'anneau de collines est parti dans les alentours)
	local newHills = Instance.new("Folder")
	newHills.Name = "Hills"
	newHills.Parent = decor
	hills = newHills
	for _ = 1, 14 do
		local rx, rz = rng:NextNumber(-340, 340), rng:NextNumber(178, 206) * (if rng:NextNumber() < 0.5 then 1 else -1)
		part(hills, "Rock", Vector3.new(rng:NextNumber(2, 4), rng:NextNumber(1.2, 2.4), rng:NextNumber(2, 3.5)), CFrame.new(rx, 0.7, rz) * yaw(rng:NextNumber(0, 90)), ROCK)
	end
end

---------------------------------------------------------------------------------------------
-- 2. Les alentours (bande entre l'ancien coeur et les murs)

local orng = Random.new(2027)

local outTrees = Instance.new("Folder")
outTrees.Name = "Outskirts"
outTrees.Parent = trees
local outHills = Instance.new("Folder")
outHills.Name = "Outskirts"
outHills.Parent = hills

-- Echantillon : meme tirage que la carte complete, mais on ne garde que le nord.
local function place(m: Instance, z: number)
	if SAMPLE_NORTH and z < SAMPLE_Z then
		m:Destroy()
	end
end

-- Dans la bande ? (marge = distance mini aux murs et au coeur)
local function inBand(x: number, z: number, margin: number): boolean
	if math.abs(x) > ZONE_HX - margin or math.abs(z) > ZONE_HZ - margin then
		return false
	end
	return math.abs(x) > CORE_HX + margin or math.abs(z) > CORE_HZ + margin
end

-- Places deja prises (collines, mares, et ce que 09-mountains pose dans la zone)
type Blob = { x: number, z: number, r: number }
local blocked: { Blob } = {
	{ x = 100, z = 510, r = 50 }, -- bassin de la cascade (09-mountains)
	{ x = -520, z = 380, r = 24 }, -- fruit geant ou rochers (09-mountains)
	{ x = 520, z = -380, r = 24 },
}
local function isFree(x: number, z: number, r: number): boolean
	for _, b in blocked do
		local dx, dz = x - b.x, z - b.z
		local reach = r + b.r
		if dx * dx + dz * dz < reach * reach then
			return false
		end
	end
	return true
end

-- Colline a grimper : 2 a 4 gradins, chaque marche fait 5 studs au plus (saut du joueur : 7).
local function climbHill(cx: number, cz: number, w: number, d: number, tiers: number, withTree: boolean)
	local m = Instance.new("Model")
	m.Name = "Hill"
	local base = CFrame.new(cx, 0, cz) * yaw(orng:NextNumber(0, 180))
	local y = 0
	local cw, cd = w, d
	local ox, oz = 0, 0
	for i = 1, tiers do
		local h = orng:NextNumber(4.1, 5)
		part(m, "Tier" .. i, Vector3.new(cw, h, cd), base * CFrame.new(ox, y + h / 2, oz) * yaw(orng:NextNumber(-7, 7)), HILL[((i - 1) % #HILL) + 1])
		y += h
		ox += orng:NextNumber(-0.07, 0.07) * cw
		oz += orng:NextNumber(-0.07, 0.07) * cd
		cw *= orng:NextNumber(0.6, 0.72)
		cd *= orng:NextNumber(0.6, 0.72)
	end
	m.Parent = outHills
	place(m, cz)
	if withTree then
		local top = base * CFrame.new(ox, 0, oz)
		local s = orng:NextNumber(1.2, 1.7)
		local t = if orng:NextNumber() < 0.5 then pine(outTrees, orng, top.X, top.Z, s, true, y - 0.3) else roundTree(outTrees, orng, top.X, top.Z, s, true, y - 0.3)
		place(t, cz)
	end
end

for _ = 1, 44 do
	local w, d = orng:NextNumber(44, 92), orng:NextNumber(34, 70)
	local radius = math.max(w, d) * 0.6
	local x, z = orng:NextNumber(-ZONE_HX, ZONE_HX), orng:NextNumber(-ZONE_HZ, ZONE_HZ)
	local tiers = orng:NextInteger(2, 4)
	local withTree = orng:NextNumber() < 0.4
	if inBand(x, z, radius + 8) and isFree(x, z, radius + 14) then
		climbHill(x, z, w, d, tiers, withTree)
		table.insert(blocked, { x = x, z = z, r = radius })
	end
end
task.wait()

-- Mare : rive de sable en 2 dalles (dessus ecartes de 0.15), eau opaque, nenuphars.
local function pond(cx: number, cz: number)
	local m = Instance.new("Model")
	m.Name = "Pond"
	local base = CFrame.new(cx, 0, cz) * yaw(orng:NextNumber(0, 180))
	local ax, az = orng:NextNumber(36, 48), orng:NextNumber(24, 32)
	local bx, bz = orng:NextNumber(22, 30), orng:NextNumber(32, 42)
	local off = CFrame.new(orng:NextNumber(-7, 7), 0, orng:NextNumber(-5, 5))
	part(m, "Sand", Vector3.new(ax, 0.6, az), base * CFrame.new(0, 0, 0), SAND)
	part(m, "Sand", Vector3.new(bx, 0.9, bz), base * off, SAND)
	part(m, "Water", Vector3.new(ax - 7, 0.6, az - 7), base * CFrame.new(0, 0.32, 0), WATER, LIQUID)
	part(m, "Water", Vector3.new(bx - 7, 0.6, bz - 7), base * off * CFrame.new(0, 0.32, 0), WATER, LIQUID)
	for _ = 1, 3 do
		local lx, lz = orng:NextNumber(-ax / 2 + 6, ax / 2 - 6), orng:NextNumber(-az / 2 + 6, az / 2 - 6)
		part(m, "LilyPad", Vector3.new(2.6, 0.2, 2.6), base * CFrame.new(lx, 0.75, lz) * yaw(orng:NextNumber(0, 90)), LILY, DECOR)
	end
	m.Parent = outHills
	place(m, cz)
end
do
	local made = 0
	for _ = 1, 30 do
		local x, z = orng:NextNumber(-ZONE_HX, ZONE_HX), orng:NextNumber(-ZONE_HZ, ZONE_HZ)
		if made < 4 and inBand(x, z, 40) and isFree(x, z, 44) then
			pond(x, z)
			table.insert(blocked, { x = x, z = z, r = 30 })
			made += 1
		end
	end
end

-- Rochers : un gros bloc + 1 ou 2 petits (on peut monter dessus)
local function rockCluster(cx: number, cz: number)
	local m = Instance.new("Model")
	m.Name = "Rocks"
	local s = orng:NextNumber(0.8, 2)
	local rot = orng:NextNumber(0, 90)
	local h = orng:NextNumber(3.5, 5.5) * s
	part(m, "Rock", Vector3.new(orng:NextNumber(5, 7) * s, h, orng:NextNumber(4.5, 6) * s), CFrame.new(cx, h / 2 - 0.4, cz) * yaw(rot), ROCKS[orng:NextInteger(1, #ROCKS)])
	local h2 = h * orng:NextNumber(0.4, 0.62)
	part(m, "Rock", Vector3.new(3.6 * s, h2, 3.2 * s), CFrame.new(cx + 3.4 * s, h2 / 2 - 0.3, cz + 1.8 * s) * yaw(rot + orng:NextNumber(15, 60)), ROCKS[orng:NextInteger(1, #ROCKS)])
	if orng:NextNumber() < 0.5 then
		local h3 = h * orng:NextNumber(0.22, 0.36)
		part(m, "Rock", Vector3.new(2.4 * s, h3, 2.2 * s), CFrame.new(cx - 2.6 * s, h3 / 2 - 0.2, cz - 3 * s) * yaw(rot + orng:NextNumber(20, 70)), ROCKS[orng:NextInteger(1, #ROCKS)])
	end
	m.Parent = outHills
	place(m, cz)
end
for _ = 1, 90 do
	local x, z = orng:NextNumber(-ZONE_HX, ZONE_HX), orng:NextNumber(-ZONE_HZ, ZONE_HZ)
	if inBand(x, z, 12) and isFree(x, z, 12) then
		rockCluster(x, z)
		table.insert(blocked, { x = x, z = z, r = 7 })
	end
end
task.wait()

-- Foret : un arbre possible par case de 30 studs, plus ou moins selon un bruit (bosquets et
-- clairieres), plus dense et plus grand pres des murs, clairseme pres des usines.
local CELL = 30
local treeCount = 0
for gx = -ZONE_HX + 10, ZONE_HX - 10 - CELL, CELL do
	for gz = -ZONE_HZ + 10, ZONE_HZ - 10 - CELL, CELL do
		local x = gx + orng:NextNumber(0, CELL - 6)
		local z = gz + orng:NextNumber(0, CELL - 6)
		local roll = orng:NextNumber()
		local sizeRoll = orng:NextNumber()
		local kindRoll = orng:NextNumber()
		if inBand(x, z, 9) then
			local wallDist = math.min(ZONE_HX - math.abs(x), ZONE_HZ - math.abs(z))
			local coreDist = math.max(math.abs(x) - CORE_HX, math.abs(z) - CORE_HZ)
			local chance = 0.36 + math.noise(x / 150, z / 150, 11.3) * 0.95
			if wallDist < 110 then
				chance += 0.28
			end
			if coreDist < 60 then
				chance -= 0.16
			end
			if roll < chance and isFree(x, z, 6) then
				local s = if wallDist < 110 then 1.7 + sizeRoll * 0.9 else 1.15 + sizeRoll * 0.8
				local t = if kindRoll < 0.5 then pine(outTrees, orng, x, z, s, true) else roundTree(outTrees, orng, x, z, s, true)
				place(t, z)
				treeCount += 1
			end
		end
	end
	if (gx + ZONE_HX) % (CELL * 6) < CELL then
		task.wait()
	end
end

-- Buissons et fleurs dans les clairieres
for _ = 1, 230 do
	local x, z = orng:NextNumber(-ZONE_HX, ZONE_HX), orng:NextNumber(-ZONE_HZ, ZONE_HZ)
	local s = orng:NextNumber(0.9, 1.6)
	if inBand(x, z, 8) and isFree(x, z, 4) then
		place(bush(outTrees, orng, x, z, s), z)
	end
end
for _ = 1, 40 do
	local x, z = orng:NextNumber(-ZONE_HX, ZONE_HX), orng:NextNumber(-ZONE_HZ, ZONE_HZ)
	if inBand(x, z, 10) and isFree(x, z, 6) then
		local m = Instance.new("Model")
		m.Name = "Flowers"
		flowers(m, orng, x, z, 6, 4.5)
		m.Parent = outTrees
		place(m, z)
	end
end
task.wait()

---------------------------------------------------------------------------------------------
-- Anti z-fighting : decor place au hasard, un dessus de feuillage peut tomber au meme niveau qu'un
-- autre dessus (vu le 2026-11-19 : RoundTree vers x -348, z -205). Si deux dessus de couleurs
-- differentes sont a moins de 0.05 stud et se recouvrent, on monte le second de 0.06 en le
-- grandissant (le bas ne bouge pas). Toutes les pieces ici ne tournent qu'autour de Y.
-- Grille de 64 studs : chaque piece n'est comparee qu'a ses voisines (les grandes : a toutes).
do
	local GRID = 64
	local cells: { [number]: { BasePart } } = {}
	local big: { BasePart } = {}
	local small: { BasePart } = {}
	local function key(ix: number, iz: number): number
		return ix * 4096 + iz
	end
	for _, p in decor:GetDescendants() do
		if p:IsA("BasePart") then
			if math.max(p.Size.X, p.Size.Z) > GRID / 2 then
				table.insert(big, p)
			else
				table.insert(small, p)
				local k = key(math.floor(p.Position.X / GRID), math.floor(p.Position.Z / GRID))
				local list = cells[k]
				if not list then
					list = {}
					cells[k] = list
				end
				table.insert(list, p)
			end
		end
	end
	local fixed = 0
	local function check(a: BasePart, b: BasePart)
		if a == b or a.Color == b.Color then
			return
		end
		local topA = a.Position.Y + a.Size.Y / 2
		local topB = b.Position.Y + b.Size.Y / 2
		if math.abs(topA - topB) >= 0.05 then
			return
		end
		local ra = math.max(a.Size.X, a.Size.Z) * 0.71
		local rb = math.max(b.Size.X, b.Size.Z) * 0.71
		local flat = Vector3.new(a.Position.X - b.Position.X, 0, a.Position.Z - b.Position.Z).Magnitude
		if flat < ra + rb then
			-- le dessus de b finit 0.08 au-dessus de celui de a (avant : +0.06 fixe, qui laissait
			-- un ecart de 0.03 quand b partait d'un peu plus bas que a)
			local lift = topA + 0.08 - topB
			b.Size += Vector3.new(0, lift, 0)
			b.CFrame += Vector3.new(0, lift / 2, 0)
			fixed += 1
		end
	end
	for _, a in small do
		local ix, iz = math.floor(a.Position.X / GRID), math.floor(a.Position.Z / GRID)
		for dx = -1, 1 do
			for dz = -1, 1 do
				local list = cells[key(ix + dx, iz + dz)]
				if list then
					for _, b in list do
						-- chaque paire une seule fois
						if a.Position.X < b.Position.X or (a.Position.X == b.Position.X and a.Position.Z < b.Position.Z) then
							check(a, b)
						end
					end
				end
			end
		end
	end
	task.wait()
	for i, a in big do
		for j = i + 1, #big do
			check(a, big[j])
		end
		for _, b in small do
			check(a, b)
		end
	end
	local count = 0
	for _, d in decor:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return ("Decor OK%s : %d pieces (alentours : %d arbres tires, %d modeles Trees, %d modeles Hills), %d dessus decales"):format(
		if SAMPLE_NORTH then " (echantillon nord)" else "",
		count,
		treeCount,
		#outTrees:GetChildren(),
		#outHills:GetChildren(),
		fixed
	)
end
