--!strict
-- FloorTemplate (un etage, phase 1b), morceau 2/6 : le verger dans l'usine. Jardiniere (bordure + herbe), cailloux, zone
-- de chute des fruits, et l'ARBRE EN 5 STADES (il grandit avec les ameliorations de l'arbre) :
--   ServerStorage.TreeStages.Stage1..Stage5 (Models, pivot = pied du tronc), et le stade 1 pose
--   dans le modele de base sous le nom Tree.Body (TreeService le remplace par le bon stade).
-- Feuillage : attribut Leaf = true (animation TreeFxController). PAS DE FRUITS DE DECO dans l'arbre
-- (2026-11-20 : les joueurs essayaient de ramasser les pommes accrochees ; ne pas en remettre).
-- Arbre SANS COLLISION (2026-11-20) : on le traverse a pied, la camera passe au travers.
-- A lancer apres 02a. L'arbre depasse des murs, sous le puits de lumiere (plus haut < 32 au-dessus
-- de l'herbe : les poutres du puits sont a 34.6).
-- Doc : docs/systems/carte-bases.md, docs/systems/fruits.md

local ServerStorage = game:GetService("ServerStorage")

local TX, TZ = 87, 116 -- centre de l'arbre (repere local de la base)
local PX0, PX1, PZ0, PZ1 = 68, 106, 98, 133.9 -- jardiniere (verger) : 38 x 36, contre le mur du fond ; 133.9 et pas 134 : bord du sol de zone (z-fighting)
local DY = 0.7 -- l'herbe de la jardiniere est 0.7 plus haut que l'ancien terrain (dessus a 1.0)
local GROUND = 1.0 -- pied du tronc (hauteur de l'herbe de la jardiniere)
local BORDER = Color3.fromRGB(196, 110, 70) -- briques de la jardiniere
local BORDER_CAP = Color3.fromRGB(226, 150, 96)
local SOIL = Color3.fromRGB(116, 84, 58)

local TRUNK = Color3.fromRGB(112, 78, 52)
local TRUNK_DARK = Color3.fromRGB(96, 66, 44)
local TRUNK_LIGHT = Color3.fromRGB(132, 94, 62)
local LEAVES = { Color3.fromRGB(62, 124, 50), Color3.fromRGB(76, 140, 56), Color3.fromRGB(92, 156, 64) }
local LEAF_TOP = Color3.fromRGB(116, 178, 74) -- dessus clair des grappes (relief)
local ORCHARD = { Color3.fromRGB(96, 156, 70), Color3.fromRGB(102, 162, 74), Color3.fromRGB(108, 168, 78) }
local STEM = Color3.fromRGB(92, 64, 42)
local ROCK = Color3.fromRGB(150, 150, 146)
local WOOD = Color3.fromRGB(205, 160, 108)
local HIVE = { Color3.fromRGB(255, 196, 60), Color3.fromRGB(240, 165, 40) }

local STUDS = Enum.SurfaceType.Studs
local INLET = Enum.SurfaceType.Inlet
local SMOOTH_SURF = Enum.SurfaceType.Smooth

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = STUDS
	p.BottomSurface = INLET
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

local MARKER = {
	Transparency = 1,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
	TopSurface = SMOOTH_SURF,
	BottomSurface = SMOOTH_SURF,
}
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }
local SMALL = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local model = ServerStorage:FindFirstChild("FloorTemplate")
assert(model, "Lancer 02a d'abord")
local oldTree = model:FindFirstChild("Tree")
if oldTree then
	oldTree:Destroy()
end
local tree = Instance.new("Folder")
tree.Name = "Tree"

local function at(x: number, y: number, z: number, yawDeg: number?): CFrame
	return CFrame.new(TX + x, y + DY, TZ + z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

-- Jardiniere : bordure en briques (on l'enjambe), terre, herbe
local function pbox(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3)
	part(tree, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color)
end
pbox("Border", PX0, PX1, 0.5, 1.2, PZ0, PZ0 + 1, BORDER)
pbox("Border", PX0, PX1, 0.5, 1.2, PZ1 - 1, PZ1, BORDER)
pbox("Border", PX0, PX0 + 1, 0.5, 1.2, PZ0 + 1, PZ1 - 1, BORDER)
pbox("Border", PX1 - 1, PX1, 0.5, 1.2, PZ0 + 1, PZ1 - 1, BORDER)
pbox("BorderCap", PX0 - 0.2, PX1 + 0.2, 1.2, 1.45, PZ0 - 0.2, PZ0 + 1.2, BORDER_CAP)
pbox("BorderCap", PX0 - 0.2, PX1 + 0.2, 1.2, 1.45, PZ1 - 1.2, PZ1 + 0.2, BORDER_CAP)
pbox("BorderCap", PX0 - 0.2, PX0 + 1.2, 1.15, 1.4, PZ0 + 1.2, PZ1 - 1.2, BORDER_CAP)
pbox("BorderCap", PX1 - 1.2, PX1 + 0.2, 1.15, 1.4, PZ0 + 1.2, PZ1 - 1.2, BORDER_CAP)
-- Regle des 2 studs (docs/style.md) : dessus de la bordure en Inlet (studs creux), herbe en Studs
for _, cap in tree:GetChildren() do
	if cap.Name == "BorderCap" and cap:IsA("BasePart") then
		cap.TopSurface = INLET
	end
end
pbox("Soil", PX0 + 1, PX1 - 1, 0.5, 0.9, PZ0 + 1, PZ1 - 1, SOIL)
part(tree, "Lawn", Vector3.new(PX1 - PX0 - 2, 0.1, PZ1 - PZ0 - 2), CFrame.new((PX0 + PX1) / 2, 0.95, (PZ0 + PZ1) / 2), ORCHARD[1])
-- Rond d'herbe "en escalier" (3 dalles a des hauteurs differentes : pas de z-fighting)
part(tree, "GrassA", Vector3.new(24, 0.1, 13), at(0, 0.33, 0), ORCHARD[1], { TopSurface = STUDS })
part(tree, "GrassB", Vector3.new(13, 0.1, 24), at(0, 0.35, 0), ORCHARD[2])
part(tree, "GrassC", Vector3.new(19.5, 0.1, 19.5), at(0, 0.37, 0), ORCHARD[3])

-- Quelques cailloux gris autour (pas de fleurs de couleur : on les prenait pour des fruits,
-- demande utilisateur du 2026-11-19 soir ; ne pas en remettre)
part(tree, "Rock", Vector3.new(1.8, 1, 1.4), at(-8, 0.8, 5, 25), ROCK)
part(tree, "Rock", Vector3.new(1.1, 0.7, 1), at(-7, 0.65, 6.3, -10), ROCK)
part(tree, "Rock", Vector3.new(1.4, 0.8, 1.2), at(7.5, 0.7, -6, 40), ROCK)

-- Zone ou tombent les fruits (le code choisit un point dans ce carre, dans le rayon du stade).
-- 22 -> 26 le 2026-11-20 (zone un peu plus large, toujours dans la jardiniere 36 x 34)
part(tree, "FruitArea", Vector3.new(26, 1, 26), at(0, 0.9, 0), Color3.new(1, 0, 0), MARKER)
-- Texte "Tree full!" (TreeService le monte ou le descend selon le stade de l'arbre)
part(tree, "TreeLabelAnchor", Vector3.new(1, 1, 1), at(0, 17, 0), Color3.new(1, 0, 0), MARKER)
-- Pied du tronc : TreeService y pose le modele du stade actuel
part(tree, "TreeRoot", Vector3.new(1, 1, 1), CFrame.new(TX, GROUND, TZ), Color3.new(1, 0, 0), MARKER)
task.wait()

------------------------------------------------------------------------------------------------
-- Les 5 stades de l'arbre. Coordonnees relatives au pied du tronc (x, y au-dessus de l'herbe, z).
------------------------------------------------------------------------------------------------

local stageModel: Model
local function T(x: number, y: number, z: number, yawDeg: number?): CFrame
	return CFrame.new(TX + x, GROUND + y, TZ + z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

local function wood(name: string, size: Vector3, cf: CFrame, color: Color3?): BasePart
	return part(stageModel, name, size, cf, color or TRUNK)
end

-- Grappe de feuillage : bloc + dessus plus clair (relief "brique" des captures de reference).
local function leaves(size: Vector3, x: number, y: number, z: number, yaw: number, tone: number)
	local p = part(stageModel, "Leaves", size, T(x, y, z, yaw), LEAVES[tone], DECOR)
	p:SetAttribute("Leaf", true)
	if size.X >= 4 and size.Z >= 4 then
		local cap = part(
			stageModel,
			"LeavesTop",
			Vector3.new(size.X * 0.62, 0.6, size.Z * 0.62),
			T(x, y + size.Y / 2 + 0.28, z, yaw + 9),
			if tone == 3 then LEAF_TOP else LEAVES[tone + 1],
			DECOR
		)
		cap:SetAttribute("Leaf", true)
	end
end

local function roots(count: number, size: Vector3, dist: number, y: number)
	for i = 0, count - 1 do
		local yaw = i * (360 / count) + 45
		local cf = T(0, y, 0, yaw) * CFrame.new(0, 0, -dist) * CFrame.Angles(math.rad(14), 0, 0)
		wood("Root", size, cf, TRUNK_DARK)
	end
end

local function branch(yaw: number, y: number, len: number, thick: number, tilt: number)
	local cf = T(0, y, 0, yaw) * CFrame.Angles(math.rad(tilt), 0, 0) * CFrame.new(0, 0, -len / 2)
	wood("Branch", Vector3.new(thick, thick, len), cf)
end

local function newStage(n: number, name: string): Model
	local m = Instance.new("Model")
	m.Name = "Stage" .. n
	m:SetAttribute("TreeStage", n)
	m:SetAttribute("StageName", name)
	m.WorldPivot = CFrame.new(TX, GROUND, TZ)
	stageModel = m
	return m
end

local stages: { Model } = {}

-- Stade 1 : jeune pousse avec son tuteur (~8.5 de haut)
do
	local m = newStage(1, "Sapling")
	part(m, "Mound", Vector3.new(3.4, 0.3, 3.4), T(0, 0.24, 0, 20), SOIL, DECOR)
	wood("Trunk", Vector3.new(1.2, 4.8, 1.2), T(0, 2.4, 0, 8))
	wood("Stake", Vector3.new(0.4, 4.2, 0.4), T(1.25, 2.1, 0.3, 0), WOOD)
	wood("Tie", Vector3.new(1.9, 0.3, 0.6), T(0.65, 3.1, 0.15, 0), Color3.fromRGB(200, 60, 50))
	leaves(Vector3.new(5, 3.4, 5), 0, 5.6, 0, 12, 2)
	leaves(Vector3.new(3.6, 2.6, 3.6), 0.4, 7.4, -0.3, 35, 3)
	leaves(Vector3.new(2.6, 2, 2.6), -2, 5.1, 1, -20, 1)
	leaves(Vector3.new(2.6, 2, 2.6), 2, 4.9, -1.3, 25, 1)
	table.insert(stages, m)
end
task.wait()

-- Stade 2 : jeune arbre (~15 de haut)
do
	local m = newStage(2, "Young Tree")
	roots(3, Vector3.new(1, 0.8, 2.2), 1.6, 0.3)
	wood("Trunk", Vector3.new(2.2, 6, 2.2), T(0, 3, 0, 4))
	wood("TrunkTop", Vector3.new(1.7, 3.6, 1.7), T(0, 7.6, 0, 16), TRUNK_DARK)
	branch(40, 6.8, 3.6, 0.9, 40)
	branch(220, 7.2, 3.2, 0.8, 42)
	leaves(Vector3.new(10, 4.6, 10), 0, 10.2, 0, 8, 1)
	leaves(Vector3.new(6.5, 3, 6.5), 0.3, 13.2, -0.2, 26, 3)
	leaves(Vector3.new(5, 3.6, 5), 4.6, 9.6, 1.6, 20, 2)
	leaves(Vector3.new(5, 3.6, 5), -4.3, 10, -1.8, -15, 2)
	leaves(Vector3.new(4.4, 3.2, 4), 0.6, 9.4, 4.5, 5, 3)
	leaves(Vector3.new(4.5, 3.2, 4.2), -1, 9.6, -4.5, 30, 1)
	table.insert(stages, m)
end
task.wait()

-- Stade 3 : pommier (l'ancien arbre, ~24 de haut)
do
	local m = newStage(3, "Apple Tree")
	roots(4, Vector3.new(1.4, 1.1, 3.2), 2.4, 0.5)
	wood("Trunk", Vector3.new(4, 5, 4), T(0, 2.5, 0))
	wood("TrunkMid", Vector3.new(3.4, 4, 3.4), T(0, 7, 0, 10))
	wood("TrunkTop", Vector3.new(2.8, 3, 2.8), T(0, 10.5, 0, -6), TRUNK_DARK)
	branch(35, 9.2, 6, 1.4, 45)
	branch(215, 9.2, 6, 1.4, 45)
	local clusters = {
		{ Vector3.new(0, 14.7, 0), Vector3.new(15, 6, 15), 0, 1 },
		{ Vector3.new(6, 13.7, 4), Vector3.new(8, 5, 8), 25, 2 },
		{ Vector3.new(-6, 14.3, -3), Vector3.new(8, 5, 8), -20, 2 },
		{ Vector3.new(-4, 13.2, 6), Vector3.new(7, 4.5, 7), 40, 3 },
		{ Vector3.new(5, 13.5, -6), Vector3.new(7, 4.5, 7), 15, 3 },
		{ Vector3.new(1, 18.7, 0), Vector3.new(10, 4, 10), 12, 2 },
		{ Vector3.new(-1, 21.7, 1), Vector3.new(6, 3, 6), -15, 3 },
		{ Vector3.new(9, 15.2, -1), Vector3.new(5, 4, 5), 30, 1 },
		{ Vector3.new(-8.5, 16.2, -1), Vector3.new(5, 4, 5), -25, 2 },
		{ Vector3.new(0, 15.5, -9), Vector3.new(6, 4, 4.5), 10, 3 },
		{ Vector3.new(2, 14.5, 9), Vector3.new(6, 3.6, 5), -8, 1 },
	}
	for _, c in clusters do
		local pos: Vector3, size: Vector3 = c[1], c[2]
		leaves(size, pos.X, pos.Y, pos.Z, c[3], c[4])
	end
	table.insert(stages, m)
end
task.wait()

-- Stade 4 : grand arbre avec nichoir (~28 de haut)
do
	local m = newStage(4, "Big Tree")
	roots(6, Vector3.new(1.8, 1.4, 4), 3.2, 0.6)
	wood("Trunk", Vector3.new(5, 6, 5), T(0, 3, 0, 3))
	wood("TrunkMid", Vector3.new(4.2, 5, 4.2), T(0, 8.5, 0, 12))
	wood("TrunkTop", Vector3.new(3.4, 4, 3.4), T(0, 13, 0, -5), TRUNK_DARK)
	wood("Bark", Vector3.new(5.2, 0.6, 5.2), T(0, 5.6, 0, 3), TRUNK_LIGHT)
	branch(30, 11.5, 8, 1.6, 50)
	branch(150, 12, 7.5, 1.5, 48)
	branch(265, 11, 8, 1.6, 52)
	-- Nichoir rouge accroche au tronc (cote avant = -z, vers l'entree)
	local front = T(0, 9, 0) * CFrame.new(0, 0, -2)
	part(m, "Birdhouse", Vector3.new(1.6, 1.8, 1.2), front * CFrame.new(0, 0, -0.6), Color3.fromRGB(215, 60, 55), DECOR)
	part(m, "BirdhouseRoof", Vector3.new(2.1, 0.35, 1.6), front * CFrame.new(-0.5, 1.15, -0.6) * CFrame.Angles(0, 0, math.rad(32)), WOOD, DECOR)
	part(m, "BirdhouseRoof", Vector3.new(2.1, 0.35, 1.6), front * CFrame.new(0.5, 1.15, -0.6) * CFrame.Angles(0, 0, math.rad(-32)), WOOD, DECOR)
	part(m, "BirdhouseHole", Vector3.new(0.6, 0.6, 0.1), front * CFrame.new(0, 0.2, -1.23), Color3.fromRGB(30, 22, 18), SMALL)
	leaves(Vector3.new(19, 6.5, 19), 0, 18, 0, 6, 1)
	for i = 0, 8 do
		local a = i / 9 * math.pi * 2 + 0.3
		local r = 8.6
		local size = Vector3.new(7, 5, 7) * (if i % 2 == 0 then 1 else 0.85)
		leaves(size, math.cos(a) * r, 16.5 + (i % 3) * 0.6, math.sin(a) * r, i * 23, (i % 3) + 1)
	end
	leaves(Vector3.new(13, 4.5, 13), 0.5, 22.6, -0.4, 14, 2)
	leaves(Vector3.new(7, 3, 7), -0.6, 25.7, 0.5, -12, 3)
	table.insert(stages, m)
end
task.wait()

-- Stade 5 : arbre geant avec ruche et balancoire (~31.5 de haut)
do
	local m = newStage(5, "Giant Tree")
	roots(8, Vector3.new(2.2, 1.8, 5), 3.9, 0.7)
	wood("Trunk", Vector3.new(6.5, 7, 6.5), T(0, 3.5, 0, 5))
	wood("TrunkMid", Vector3.new(5.5, 6, 5.5), T(0, 10, 0, 14))
	wood("TrunkTop", Vector3.new(4.4, 5, 4.4), T(0, 15.5, 0, -8), TRUNK_DARK)
	wood("Bark", Vector3.new(6.7, 0.7, 6.7), T(0, 6.2, 0, 5), TRUNK_LIGHT)
	wood("Bark", Vector3.new(5.7, 0.6, 5.7), T(0, 12.6, 0, 14), TRUNK_LIGHT)
	branch(20, 14, 10, 2, 55)
	branch(110, 14.5, 9, 1.8, 52)
	branch(200, 13.5, 10, 2, 56)
	branch(290, 14, 9, 1.8, 54)
	-- Branche basse horizontale avec la balancoire (cote avant = -z)
	local swingBranch = T(0, 12.5, 0, 0) * CFrame.new(0, 0, -6)
	wood("SwingBranch", Vector3.new(1.4, 1.4, 9), swingBranch)
	local seatCf = T(0, 3.2, 0) * CFrame.new(0, 0, -8.5)
	part(m, "SwingRope", Vector3.new(0.18, 9, 0.18), seatCf * CFrame.new(-1.1, 4.6, 0), Color3.fromRGB(230, 215, 170), SMALL)
	part(m, "SwingRope", Vector3.new(0.18, 9, 0.18), seatCf * CFrame.new(1.1, 4.6, 0), Color3.fromRGB(230, 215, 170), SMALL)
	part(m, "SwingSeat", Vector3.new(2.8, 0.35, 1.1), seatCf, WOOD, DECOR)
	-- Ruche suspendue a une branche (anneaux jaunes, comme dans les captures de reference)
	local hive = T(0, 0, 0) * CFrame.new(-8.5, 13.6, 2)
	part(m, "HiveRope", Vector3.new(0.15, 3, 0.15), hive * CFrame.new(0, 2.1, 0), STEM, SMALL)
	local rings = { { 1.2, 0.6 }, { 1.8, 0.7 }, { 2.1, 0.7 }, { 1.8, 0.7 }, { 1.1, 0.5 } }
	local y = 0.6
	for i, r in rings do
		y -= r[2]
		part(m, "Hive", Vector3.new(r[1], r[2], r[1]), hive * CFrame.new(0, y + r[2] / 2, 0) * CFrame.Angles(0, math.rad(i * 20), 0), HIVE[(i % 2) + 1], DECOR)
	end
	part(m, "HiveHole", Vector3.new(0.5, 0.45, 0.1), hive * CFrame.new(0, -1.2, -1.06), Color3.fromRGB(40, 25, 15), SMALL)
	-- Feuillage
	leaves(Vector3.new(22, 7, 22), 0, 20.5, 0, 4, 1)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local r = 10.2
		local size = Vector3.new(8, 5.5, 8) * (if i % 2 == 0 then 1 else 0.88)
		leaves(size, math.cos(a) * r, 18.6 + (i % 3) * 0.7, math.sin(a) * r, i * 19, ((i + 1) % 3) + 1)
	end
	leaves(Vector3.new(16, 5, 16), 0.4, 25.5, -0.3, 12, 2)
	leaves(Vector3.new(10, 3.5, 10), -0.5, 29, 0.6, -10, 3)
	leaves(Vector3.new(5, 2.4, 5), 0.3, 31, -0.2, 20, 3)
	table.insert(stages, m)
end
task.wait()

-- Rangement : ServerStorage.TreeStages (modeles) + stade 1 dans le modele de base (Tree.Body)
local stageFolder = ServerStorage:FindFirstChild("TreeStages")
if stageFolder then
	stageFolder:Destroy()
end
stageFolder = Instance.new("Folder")
stageFolder.Name = "TreeStages"
stageFolder.Parent = ServerStorage
local counts = {}
for _, m in stages do
	-- Arbre sans collision : on le traverse, la camera ne bute plus dessus (CanQuery garde : la
	-- camera du client, CameraFadeController, le detecte pour le rendre transparent)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	m.Parent = stageFolder
	table.insert(counts, `{m.Name}={#m:GetDescendants()}`)
end

local body = stages[1]:Clone()
body.Name = "Body"
body.Parent = tree
tree:SetAttribute("TreeStage", 1)

tree.Parent = model
return "Tree OK: " .. #tree:GetDescendants() .. " | " .. table.concat(counts, " ")
