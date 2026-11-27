--!strict
-- Decor de la cinematique d'ouverture : ReplicatedStorage.IntroSet (2026-11-22, fond de carte ajoute
-- le 2026-11-27). Relancable (detruit et recree). A lancer dans Studio (mode Edit) apres un Rojo
-- synchronise : require(game.ServerScriptService.DevTools.BuildMap["02m-intro-set"]:Clone())
-- puis sauvegarder la place. Le client (IntroController) le clone a Config/Intro.SetOrigin, chez lui
-- seulement, et le detruit a la fin.
-- Contenu (repere : pied du grand arbre = origine, sol a y = 0, la marche va vers +X) :
--   Ground (herbe a studs comme la carte, 2040 de cote : elle va jusqu'au pied des montagnes),
--   Clearing, Path (chemin de terre, de la crete a la clairiere), Forest (copies des arbres blocky de
--   Workspace.Map.Decor.Trees, loin du chemin et des cameras ; ombre seulement pres de l'action),
--   Props (buissons, fleurs, cailloux le long du chemin et autour de la clairiere), BigTree (arbre
--   niveau 10 de l'etage 1, Lib/TreeBuilder, + fruits Intro.TreeFruits accroches au feuillage), Sapling
--   (arbre niveau 1, reduit a Intro.SaplingScale : celui qu'on tient en main), Shovel (pelle blocky,
--   pivot = poignee, le manche descend vers -Y), Hole (trou de terre, cache au depart), DirtPile.
--   Backdrop (2026-11-27, "des montagnes en fond comme sur la map") : le fond de la carte
--   (09-mountains) en plus petit (x 0.4) et plus pres, pour qu'il ait la meme taille a l'ecran :
--   crete en gradins sur les 4 cotes, grands arbres simples (3 pieces) entre la foret et la crete,
--   montagnes a facettes en 2 anneaux (base verte, roche grise, neige), volcan de jus qui fume et
--   crache 5 fruits geants.
-- Jamais de Neon sauf les coulees du volcan (comme sur la carte). Rien ne bloque ni ne touche.
-- Doc : docs/systems/cinematique.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Intro = freshRequire(ReplicatedStorage.Shared.Config.Intro)
local TreeBuilder = freshRequire((ServerScriptService :: any).Server.Lib.TreeBuilder)

local GRASS = Color3.fromRGB(72, 170, 62) -- = herbe de la carte (GrassFar)
local CLEARING = Color3.fromRGB(110, 200, 80)
local DIRT = Color3.fromRGB(150, 105, 62)
local DIRT_DARK = Color3.fromRGB(110, 76, 46)
local WOOD = Color3.fromRGB(196, 140, 80)
local METAL = Color3.fromRGB(175, 182, 192)
local STUDS = Enum.SurfaceType.Studs
local UNIVERSAL = Enum.SurfaceType.Universal

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.TopSurface = STUDS
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.Parent = parent
	return p
end

local function quiet(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

local function setShadow(model: Instance, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = on
		end
	end
end

-- Distance (au sol) d'un point au segment a-b
local function distToSegment(x: number, z: number, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(x - a.X, z - a.Z)
	local k = if ab.Magnitude > 1e-3 then math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1) else 0
	return (ap - ab * k).Magnitude
end

for _, parent in { ReplicatedStorage, workspace } do
	local old = parent:FindFirstChild("IntroSet")
	if old then
		old:Destroy()
	end
end
local set = Instance.new("Model")
set.Name = "IntroSet"
set.Parent = workspace -- le temps de la construction (raycasts des fruits), range a la fin

local PATH_Z = Intro.ActorStart.Z
local RIDGE_HALF = 190 -- la crete commence a cette distance du grand arbre (4 cotes)

-- Sol ---------------------------------------------------------------------------------------------
-- Une seule grande plaque : elle va jusqu'au pied des montagnes (sinon on voit le bord du sol).
local ground = box(set, "Ground", Vector3.new(2040, 2, 2040), CFrame.new(0, -1, 0), GRASS)
ground.CastShadow = false
local clearing = box(set, "Clearing", Vector3.new(30, 0.2, 30), CFrame.new(0, 0.1, 0), CLEARING)
clearing.CastShadow = false
-- Chemin : de la crete (x = -RIDGE_HALF - 6) au bord de la clairiere (x = -15)
local pathFrom = -RIDGE_HALF - 6
local path = box(set, "Path", Vector3.new(-15 - pathFrom, 0.2, 6), CFrame.new((pathFrom - 15) / 2, 0.12, PATH_Z), DIRT)
path.CastShadow = false
path.TopSurface = Enum.SurfaceType.Smooth

-- Foret : copies des arbres blocky de la carte (graine fixe : toujours la meme foret) ---------------
local forest = Instance.new("Folder")
forest.Name = "Forest"
forest.Parent = set
local sources: { Model } = {}
local decor = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Decor")
local mapTrees = decor and decor:FindFirstChild("Trees")
for _, t in (if mapTrees then mapTrees:GetChildren() else {}) do
	if t:IsA("Model") and #sources < 12 then
		table.insert(sources, t)
	end
end
local rng = Random.new(20261122)
local placed = 0
local tries = 0
while placed < 230 and tries < 6000 and #sources > 0 do
	tries += 1
	local x = rng:NextNumber(-120, 120)
	local z = rng:NextNumber(-120, 120)
	local r = math.sqrt(x * x + z * z)
	local onPath = x < -8 and math.abs(z - PATH_Z) < 9
	-- Cote camera (+Z) pres du chemin et de la clairiere : garder la vue degagee
	local cameraSide = z > 0 and z < 45 and x > -60 and x < 25
	if r < 19 or onPath or cameraSide then
		continue
	end
	local tree = sources[rng:NextInteger(1, #sources)]:Clone()
	quiet(tree)
	local cf, size = tree:GetBoundingBox()
	local scale = rng:NextNumber(0.9, 1.35)
	tree:ScaleTo(tree:GetScale() * scale)
	cf, size = tree:GetBoundingBox()
	local pivot = tree:GetPivot()
	local footOffset = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
	tree:PivotTo(CFrame.new(x, footOffset, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	tree.Parent = forest
	placed += 1
end
task.wait()

-- Plan d'ouverture (2026-11-27) : la camera descend du ciel (1er plan de Intro.Shots, repere du
-- decor) jusqu'a cote du personnage. On retire les arbres qu'elle traverserait (sans toucher au
-- tirage : le reste de la foret ne bouge pas).
local openFrom: Vector3 = Intro.Shots[1].pos
local walker: Vector3 = Intro.ActorStart:Lerp(Intro.NoticeSpot, Intro.Times.open / Intro.Times.notice)
local openTo = Vector3.new(walker.X, 5, walker.Z + 13)
local cut = 0
for _, tree in forest:GetChildren() do
	if tree:IsA("Model") then
		local cf, size = tree:GetBoundingBox()
		local reach = math.max(size.X, size.Z) / 2 + 5
		local top = cf.Position.Y + size.Y / 2
		for i = 0, 16 do
			local p = openFrom:Lerp(openTo, i / 16)
			local flat = Vector2.new(cf.Position.X - p.X, cf.Position.Z - p.Z).Magnitude
			if flat < reach and top > p.Y - 4 then
				tree:Destroy()
				cut += 1
				break
			end
		end
	end
end

-- Ombres : seulement les arbres pres de l'action (chemin, clairiere). Les autres n'en projettent pas.
local shadowTrees = 0
local actionFrom = Vector3.new(Intro.ActorStart.X - 14, 0, PATH_Z)
for _, tree in forest:GetChildren() do
	if tree:IsA("Model") then
		local p = tree:GetPivot().Position
		local near = distToSegment(p.X, p.Z, actionFrom, Intro.TreeSpot) < 46
		setShadow(tree, near)
		if near then
			shadowTrees += 1
		end
	end
end

-- Grand arbre : niveau 10 de l'etage 1, charge de fruits de l'etage 1 ------------------------------
local big = TreeBuilder.Build(1, Intro.TreeLevel)
big.Name = "BigTree"
quiet(big)
big:PivotTo(CFrame.new(Intro.TreeSpot))
big.Parent = set
local leaves: { BasePart } = {}
for _, d in big:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Leaf") == true then
		table.insert(leaves, d)
	end
end
local fruitFolder = ReplicatedStorage:FindFirstChild("FruitAssets")
local hangList: { string } = {}
for _, id in Intro.TreeFruits do
	if fruitFolder and fruitFolder:FindFirstChild(id) then
		table.insert(hangList, id)
	end
end
local fruits = Instance.new("Model")
fruits.Name = "Fruits"
fruits.Parent = big
if fruitFolder and #leaves > 0 and #hangList > 0 then
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = leaves
	for _, leaf in leaves do
		leaf.CanQuery = true
	end
	local cf, size = big:GetBoundingBox()
	local low = cf.Position.Y - size.Y / 2 + size.Y * 0.35
	local high = cf.Position.Y + size.Y / 2 - 2
	local count = 0
	for i = 1, 160 do
		if count >= 34 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local y = rng:NextNumber(low, high)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local origin = Vector3.new(0, y, 0) + dir * 40
		local hit = workspace:Raycast(origin, -dir * 40, params)
		if hit == nil then
			continue
		end
		local asset = fruitFolder:FindFirstChild(hangList[((i - 1) % #hangList) + 1])
		if asset and asset:IsA("BasePart") then
			local fruit = asset:Clone()
			fruit.Anchored = true
			fruit.CanCollide = false
			fruit.CanTouch = false
			fruit.CanQuery = false
			local k = 2 / math.max(fruit.Size.X, fruit.Size.Y, fruit.Size.Z)
			fruit.Size *= k
			fruit.CFrame = CFrame.new(hit.Position + hit.Normal * 0.5) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			fruit.Parent = fruits
			count += 1
		end
	end
	for _, leaf in leaves do
		leaf.CanQuery = false
	end
end

-- Arbre niveau 1 (dans les mains) -----------------------------------------------------------------
local sapling = TreeBuilder.Build(1, Intro.SaplingLevel)
sapling.Name = "Sapling"
quiet(sapling)
sapling:PivotTo(CFrame.identity)
sapling:ScaleTo(Intro.SaplingScale)
sapling:PivotTo(CFrame.new(0, -500, 0)) -- range sous le sol (le client le deplace)
sapling.Parent = set

-- Pelle : pivot = poignee, manche vers -Y, lame en bas (devant = -Z) -------------------------------
local shovel = Instance.new("Model")
shovel.Name = "Shovel"
box(shovel, "Grip", Vector3.new(0.9, 0.25, 0.25), CFrame.new(0, 0, 0), WOOD)
box(shovel, "Shaft", Vector3.new(0.25, 3.4, 0.25), CFrame.new(0, -1.7, 0), WOOD)
box(shovel, "Neck", Vector3.new(0.4, 0.4, 0.3), CFrame.new(0, -3.5, 0), METAL, Enum.Material.SmoothPlastic)
box(shovel, "Blade", Vector3.new(1.1, 1.3, 0.15), CFrame.new(0, -4.3, -0.05), METAL, Enum.Material.SmoothPlastic)
box(shovel, "Tip", Vector3.new(0.7, 0.3, 0.15), CFrame.new(0, -5.05, -0.05), METAL, Enum.Material.SmoothPlastic)
for _, p in shovel:GetChildren() do
	(p :: BasePart).Reflectance = if p.Name == "Blade" or p.Name == "Tip" then 0.2 else 0
end
shovel.WorldPivot = CFrame.identity
shovel:PivotTo(CFrame.new(0, -500, 4))
shovel.Parent = set

-- Trou (grandit a chaque coup de pelle ; le client le replace depuis la Config) ------------------------------------------------------------
local hole = box(set, "Hole", Vector3.new(3.6, 0.3, 3.6), CFrame.new(Intro.DigSpot + Intro.HoleOffset + Vector3.new(0, 0.15, 0)), DIRT_DARK)
hole.Transparency = 1
hole.CastShadow = false
local pile = box(set, "DirtPile", Vector3.new(2.4, 0.8, 2.4), CFrame.new(Intro.DigSpot + Intro.PileOffset + Vector3.new(0, 0.4, 0)), DIRT)
pile.Transparency = 1
task.wait()

---------------------------------------------------------------------------------------------
-- Petits details pres de l'action (2026-11-27) : buissons, fleurs, cailloux. Graine a part : la
-- foret et les fruits ne changent pas.

local rng2 = Random.new(20261127)
local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = set

-- Places a laisser libres : cameras posees dans le decor, points de l'histoire
local keepClear: { { p: Vector3, r: number } } = {
	{ p = Intro.ShovelSpot, r = 4 },
	{ p = Intro.DigSpot, r = 5 },
	{ p = Intro.ActorStop, r = 4 },
}
for _, shot in Intro.Shots do
	if shot.space == "Set" then
		table.insert(keepClear, { p = shot.pos, r = 5 })
	end
end
local function isFree(x: number, z: number, margin: number): boolean
	if math.abs(x) < 16 + margin and math.abs(z) < 16 + margin then
		return false -- clairiere
	end
	if x > 0 and x < 30 and math.abs(z) < 13 then
		return false -- la ou l'arbre tombe et ou les fruits roulent
	end
	if x < -12 and math.abs(z - PATH_Z) < 3.4 + margin then
		return false -- chemin
	end
	for _, spot in keepClear do
		if Vector2.new(x - spot.p.X, z - spot.p.Z).Magnitude < spot.r + margin then
			return false
		end
	end
	return true
end

-- Buissons : derriere le chemin (cote -Z, jamais entre la camera et le personnage) et au bord de la clairiere
local bushSource = mapTrees and mapTrees:FindFirstChild("Bush")
local bushes = 0
if bushSource and bushSource:IsA("Model") then
	for _ = 1, 400 do
		if bushes >= 18 then
			break
		end
		local x, z
		if rng2:NextNumber() < 0.7 then
			x, z = rng2:NextNumber(-150, -18), PATH_Z - rng2:NextNumber(5.5, 15)
		else
			x, z = rng2:NextNumber(-22, 22), -rng2:NextNumber(17, 24)
		end
		if not isFree(x, z, 2) then
			continue
		end
		local bush = bushSource:Clone()
		quiet(bush)
		bush:ScaleTo(bush:GetScale() * rng2:NextNumber(0.85, 1.5))
		local cf, size = bush:GetBoundingBox()
		local footOffset = bush:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
		bush:PivotTo(CFrame.new(x, footOffset - 0.1, z) * CFrame.Angles(0, rng2:NextNumber(0, math.pi * 2), 0))
		setShadow(bush, true)
		bush.Parent = props
		bushes += 1
	end
end

-- Fleurs (comme sur la carte : un coeur de couleur sur des feuilles), par petits groupes
local FLOWERS = { Color3.fromRGB(226, 120, 150), Color3.fromRGB(190, 120, 210), Color3.fromRGB(240, 204, 84), Color3.fromRGB(250, 250, 245) }
local LEAF = Color3.fromRGB(70, 186, 64)
local flowers = 0
for _ = 1, 600 do
	if flowers >= 44 then
		break
	end
	-- un groupe : des deux cotes du chemin (bas : ne cache pas les pieds) ou autour de la clairiere
	local cx, cz
	local pickZone = rng2:NextNumber()
	if pickZone < 0.45 then
		cx, cz = rng2:NextNumber(-140, -18), PATH_Z - rng2:NextNumber(4.5, 13)
	elseif pickZone < 0.75 then
		-- cote camera : pres du chemin seulement (les cameras qui suivent le personnage passent plus loin)
		cx, cz = rng2:NextNumber(-90, -18), PATH_Z + rng2:NextNumber(5, 6.5)
	else
		local a = rng2:NextNumber(0, math.pi * 2)
		local r = rng2:NextNumber(18, 26)
		cx, cz = math.cos(a) * r, math.sin(a) * r
	end
	local color = FLOWERS[rng2:NextInteger(1, #FLOWERS)]
	for _ = 1, rng2:NextInteger(2, 4) do
		local x, z = cx + rng2:NextNumber(-1.6, 1.6), cz + rng2:NextNumber(-1.6, 1.6)
		if isFree(x, z, 0.5) then
			local rot = CFrame.Angles(0, rng2:NextNumber(0, math.pi / 2), 0)
			local leaf = box(props, "FlowerLeaves", Vector3.new(0.9, 0.25, 0.9), CFrame.new(x, 0.125, z) * rot, LEAF)
			leaf.CastShadow = false
			local head = box(props, "Flower", Vector3.new(0.55, 0.55, 0.55), CFrame.new(x, 0.52, z) * rot, color)
			head.CastShadow = false
			flowers += 1
		end
	end
end

-- Cailloux gris a studs, un peu enfonces
local ROCK_COLORS = { Color3.fromRGB(150, 150, 146), Color3.fromRGB(132, 134, 138) }
local rocks = 0
for _ = 1, 300 do
	if rocks >= 14 then
		break
	end
	-- Seulement derriere le chemin (cote -Z) : cote camera, un caillou pres de l'objectif cachait
	-- les jambes du personnage pendant la course (vu en capture le 2026-11-27).
	local x = rng2:NextNumber(-150, 24)
	local z = PATH_Z - rng2:NextNumber(4.5, 20)
	local s = rng2:NextNumber(1.4, 3.4)
	if not isFree(x, z, s / 2) then
		continue
	end
	local size = Vector3.new(s * rng2:NextNumber(0.9, 1.3), s * rng2:NextNumber(0.5, 0.75), s)
	box(props, "Rock", size, CFrame.new(x, size.Y / 2 - 0.2, z) * CFrame.Angles(0, rng2:NextNumber(0, math.pi), 0), ROCK_COLORS[rng2:NextInteger(1, 2)])
	rocks += 1
end
task.wait()

---------------------------------------------------------------------------------------------
-- Fond (2026-11-27) : le fond de la carte (09-mountains) en plus petit et plus pres. Meme recette :
-- crete en gradins, pics a facettes (4 CornerWedgeParts par pyramide), base verte, neige, volcan
-- de jus. Tout est ancre, sans collision ni ombre.

local RIDGE = { Color3.fromRGB(64, 160, 58), Color3.fromRGB(70, 166, 62), Color3.fromRGB(78, 174, 66) }
local CLIFF = { Color3.fromRGB(140, 142, 148), Color3.fromRGB(122, 124, 132) }
local TRUNK = Color3.fromRGB(112, 78, 52)
local LEAVES = { Color3.fromRGB(46, 160, 52), Color3.fromRGB(58, 176, 58), Color3.fromRGB(74, 190, 64) }
local PINE = { Color3.fromRGB(36, 140, 70), Color3.fromRGB(44, 154, 76), Color3.fromRGB(54, 166, 80) }
local FOOT = { Color3.fromRGB(62, 140, 60), Color3.fromRGB(74, 150, 64) }
local SLOPE = { Color3.fromRGB(58, 136, 64), Color3.fromRGB(68, 146, 62), Color3.fromRGB(50, 126, 62) }
local ROCK = { Color3.fromRGB(122, 124, 130), Color3.fromRGB(106, 108, 116), Color3.fromRGB(136, 136, 142) }
local SNOW = Color3.fromRGB(246, 249, 255)
local VOLCANO = { Color3.fromRGB(58, 44, 44), Color3.fromRGB(44, 34, 36) }
local JUICE = Color3.fromRGB(255, 116, 10) -- Neon : fonce, sinon il vire au jaune
local JUICES = {
	Color3.fromRGB(255, 112, 8), -- orange
	Color3.fromRGB(255, 84, 128), -- fraise
	Color3.fromRGB(168, 92, 240), -- raisin
	Color3.fromRGB(150, 232, 60), -- citron vert
	Color3.fromRGB(255, 224, 60), -- citron
}

local backdrop = Instance.new("Folder")
backdrop.Name = "Backdrop"
backdrop.Parent = set
-- Graine a part pour le fond : retoucher les petits details (buissons, fleurs, cailloux) ne
-- deplace pas les montagnes.
rng2 = Random.new(20261128)

local function pick<T>(list: { T }): T
	return list[rng2:NextInteger(1, #list)]
end

-- surface : nil = lisse, STUDS ou UNIVERSAL sur les 6 faces
local function make(className: string, parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, surface: Enum.SurfaceType?, material: Enum.Material?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or (if surface then Enum.Material.Plastic else Enum.Material.SmoothPlastic)
	local s = surface or Enum.SurfaceType.Smooth
	p.TopSurface = s
	p.BottomSurface = s
	if p:IsA("Part") then
		p.FrontSurface = s
		p.BackSurface = s
		p.LeftSurface = s
		p.RightSurface = s
	end
	p.Parent = parent
	return p
end

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- 1. Crete en gradins sur les 4 cotes. `a` = le long du cote, `o` = distance derriere le bord.
local RIDGE_DEPTH = 120
type Side = { name: string, a0: number, a1: number, world: (a: number, o: number) -> (number, number) }
local SIDES: { Side } = {
	{ name = "North", a0 = -RIDGE_HALF - RIDGE_DEPTH, a1 = RIDGE_HALF + RIDGE_DEPTH, world = function(a, o)
		return a, RIDGE_HALF + o
	end },
	{ name = "South", a0 = -RIDGE_HALF - RIDGE_DEPTH, a1 = RIDGE_HALF + RIDGE_DEPTH, world = function(a, o)
		return a, -RIDGE_HALF - o
	end },
	{ name = "East", a0 = -RIDGE_HALF, a1 = RIDGE_HALF, world = function(a, o)
		return RIDGE_HALF + o, a
	end },
	{ name = "West", a0 = -RIDGE_HALF, a1 = RIDGE_HALF, world = function(a, o)
		return -RIDGE_HALF - o, a
	end },
}

type Block = { x0: number, x1: number, z0: number, z1: number, top: number }
local blocks: { Block } = {}
local function topAt(x: number, z: number): number
	local best = 0
	for _, b in blocks do
		if b.top > best and x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 then
			best = b.top
		end
	end
	return best
end
local function groundAt(x: number, z: number, r: number): number
	return math.min(topAt(x, z), topAt(x - r, z), topAt(x + r, z), topAt(x, z - r), topAt(x, z + r))
end

local function slab(parent: Instance, side: Side, name: string, aA: number, aB: number, oA: number, oB: number, top: number, color: Color3, record: boolean)
	local xa, za = side.world(aA, oA)
	local xb, zb = side.world(aB, oB)
	local x0, x1 = math.min(xa, xb), math.max(xa, xb)
	local z0, z1 = math.min(za, zb), math.max(za, zb)
	make("Part", parent, name, Vector3.new(x1 - x0, top + 1, z1 - z0), CFrame.new((x0 + x1) / 2, (top - 1) / 2, (z0 + z1) / 2), color, STUDS)
	if record then
		table.insert(blocks, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, top = top })
	end
end

for _, side in SIDES do
	local m = Instance.new("Model")
	m.Name = "Ridge" .. side.name
	local a = side.a0
	local index = 0
	while a < side.a1 do
		index += 1
		-- fond decale d'un troncon a l'autre : pas deux faces arriere dans le meme plan (z-fighting)
		local back = RIDGE_DEPTH + (index % 4) * 1.3
		local b = math.min(a + rng2:NextNumber(60, 105), side.a1)
		local front = rng2:NextNumber(3, 10)
		local h1 = rng2:NextNumber(7, 12)
		local d1 = rng2:NextNumber(16, 26)
		local h2 = h1 + rng2:NextNumber(8, 13)
		local d2 = rng2:NextNumber(18, 28)
		local h3 = h2 + rng2:NextNumber(9, 16)
		local has3 = rng2:NextNumber() < 0.7
		local cliff = rng2:NextNumber() < 0.45
		local in2a, in2b = rng2:NextNumber(0, 9), rng2:NextNumber(0, 9)
		local in3a, in3b = rng2:NextNumber(5, 20), rng2:NextNumber(5, 20)
		local drop = rng2:NextNumber(1.5, 3.5)
		slab(m, side, "Tier1", a, b, front, back, h1, pick(RIDGE), true)
		slab(m, side, "Tier2", a + in2a, b - in2b, front + d1, back + 4, h2, pick(RIDGE), true)
		if has3 then
			slab(m, side, "Tier3", a + in3a, b - in3b, front + d1 + d2, back + 8, h3, pick(RIDGE), true)
		end
		if cliff then
			slab(m, side, "Cliff", a + in2a + 4, b - in2b - 4, front + d1 - 1.7, front + d1 + 2, h2 - drop, pick(CLIFF), false)
		end
		if b >= side.a1 then
			break
		end
		a = b - rng2:NextNumber(2, 6)
	end
	-- Coins : la crete est / ouest s'arrete au bord, la crete nord / sud commence un peu plus loin
	if side.name == "East" or side.name == "West" then
		for _, corner in { side.a0, side.a1 } do
			local out = math.sign(corner)
			slab(m, side, "Corner", corner - 3, corner + 3, 3, RIDGE_DEPTH, 9.2, RIDGE[2], false)
			slab(m, side, "Corner", corner + out * 1.5, corner + out * 12, 3.5, RIDGE_DEPTH - 1, 8.6, RIDGE[3], false)
		end
	end
	m.Parent = backdrop
	task.wait()
end

-- 2. Grands arbres simples (3 pieces) entre la foret et la crete, et sur la crete
local farForest = Instance.new("Model")
farForest.Name = "FarForest"
local farTrees = 0
for _ = 1, 3000 do
	if farTrees >= 180 then
		break
	end
	local limit = RIDGE_HALF + RIDGE_DEPTH - 12
	local x, z = rng2:NextNumber(-limit, limit), rng2:NextNumber(-limit, limit)
	if math.max(math.abs(x), math.abs(z)) < 126 then
		continue -- la foret de pres est deja la
	end
	if x < 0 and math.abs(z - PATH_Z) < 9 then
		continue -- chemin
	end
	local onRidge = math.max(math.abs(x), math.abs(z)) > RIDGE_HALF
	local s = if onRidge then rng2:NextNumber(1.3, 2.2) else rng2:NextNumber(1.1, 1.7)
	local y = groundAt(x, z, 3) - 0.5
	local rot = rng2:NextNumber(0, 90)
	if rng2:NextNumber() < 0.5 then
		make("Part", farForest, "Trunk", Vector3.new(1.6, 4, 1.6) * s, CFrame.new(x, y + 2 * s, z) * yaw(rot), TRUNK, STUDS)
		make("Part", farForest, "Leaves", Vector3.new(7, 4.4, 7) * s, CFrame.new(x, y + 6.2 * s, z) * yaw(rot + 15), PINE[1], UNIVERSAL)
		make("Part", farForest, "Leaves", Vector3.new(4.4, 4.6, 4.4) * s, CFrame.new(x, y + 10.7 * s, z) * yaw(rot + 35), PINE[rng2:NextInteger(2, 3)], UNIVERSAL)
	else
		make("Part", farForest, "Trunk", Vector3.new(1.8, 6, 1.8) * s, CFrame.new(x, y + 3 * s, z) * yaw(rot), TRUNK, STUDS)
		make("Part", farForest, "Leaves", Vector3.new(8, 5, 8) * s, CFrame.new(x, y + 8 * s, z) * yaw(rot + 10), LEAVES[1], UNIVERSAL)
		make("Part", farForest, "Leaves", Vector3.new(5.5, 3.5, 5.5) * s, CFrame.new(x + 0.6 * s, y + 11.6 * s, z - 0.4 * s) * yaw(rot + 35), LEAVES[rng2:NextInteger(2, 3)], UNIVERSAL)
	end
	farTrees += 1
end
farForest.Parent = backdrop
task.wait()

-- 3. Montagnes a facettes. Coin "haut" d'une CornerWedgePart en repere local : (+X, -Z) ; on tourne
-- chaque quart pour que ce coin pointe vers le centre de la pyramide.
local QUARTERS = { 0, 90, 180, 270 }
local function pyramid(parent: Instance, name: string, frame: CFrame, w: number, d: number, h: number, y0: number, color: Color3)
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local apex = rot:VectorToWorldSpace(Vector3.new(1, 0, -1))
		local swap = deg == 90 or deg == 270
		local size = if swap then Vector3.new(d / 2, h, w / 2) else Vector3.new(w / 2, h, d / 2)
		local offset = Vector3.new(-math.sign(apex.X) * w / 4, y0 + h / 2, -math.sign(apex.Z) * d / 4)
		make("CornerWedgePart", parent, name, size, frame * CFrame.new(offset) * rot, color)
	end
end

-- Volcan : du cote ou regardent les plans larges (derriere le grand arbre, un peu a gauche)
local VOLCANO_POS = Vector2.new(536, -475)
local V_W, V_T, V_H = 460, 104, 264 -- base, sommet plat, hauteur
local V_FRAME = CFrame.lookAt(Vector3.new(VOLCANO_POS.X, 0, VOLCANO_POS.Y), Vector3.new(0, 0, 0))
local V_SLOPE = (V_W - V_T) / 2
local V_TOP = V_H - 2

-- Base verte : pyramide plus large (x SLOPE_WIDE) et plus basse (x SLOPE_HIGH) autour de chaque pic
local SLOPE_WIDE, SLOPE_HIGH = 1.28, 0.72
local mountainIndex = 0
local mountains = 0
local function mountain(cx: number, cz: number, w: number, h: number, withFoot: boolean)
	mountainIndex += 1
	local m = Instance.new("Model")
	m.Name = "Mountain"
	local frame = CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.rad(rng2:NextNumber(0, 90)), 0)
	local rock = pick(ROCK)
	if withFoot then
		pyramid(m, "Foot", frame, w * 1.35, w * 1.2, h * 0.22, -2, pick(FOOT))
	end
	local peaks = {
		{ 0, 0, 1, 1 },
		{ rng2:NextNumber(0.3, 0.42), rng2:NextNumber(-0.15, 0.15), rng2:NextNumber(0.55, 0.7), rng2:NextNumber(0.55, 0.72) },
		{ -rng2:NextNumber(0.3, 0.42), rng2:NextNumber(-0.15, 0.15), rng2:NextNumber(0.5, 0.62), rng2:NextNumber(0.45, 0.62) },
	}
	for i, p in peaks do
		local pf = frame * CFrame.new(p[1] * w, 0, p[2] * w)
		local pw, pd, ph = w * p[3], w * p[3] * rng2:NextNumber(0.85, 1), h * p[4]
		pyramid(m, "Peak" .. i, pf, pw, pd, ph, -2, if i == 1 then rock else pick(ROCK))
		pyramid(m, "Slope" .. i, pf, pw * SLOPE_WIDE, pd * SLOPE_WIDE, ph * SLOPE_HIGH, -2, SLOPE[((mountainIndex + i) % #SLOPE) + 1])
		if ph > 160 then
			local f = 0.32
			pyramid(m, "Snow" .. i, pf, pw * f, pd * f, ph * f, ph - 2 - ph * f + ph * 0.012, SNOW)
		end
	end
	m.Parent = backdrop
	mountains += 1
end

local function ring(rx: number, rz: number, count: number, wMin: number, wMax: number, hMin: number, hMax: number, phase: number, withFoot: boolean)
	for i = 0, count - 1 do
		local a = (i + phase + rng2:NextNumber(-0.18, 0.18)) / count * math.pi * 2
		local x, z = math.cos(a) * rx, math.sin(a) * rz
		local w, h = rng2:NextNumber(wMin, wMax), rng2:NextNumber(hMin, hMax)
		if (Vector2.new(x, z) - VOLCANO_POS).Magnitude > 300 then
			mountain(x, z, w, h, withFoot)
		end
		if i % 3 == 2 then
			task.wait()
		end
	end
	task.wait()
end
ring(600, 560, 12, 270, 360, 200, 300, 0, true)
ring(880, 820, 11, 370, 480, 330, 450, 0.5, false)

-- 4. Volcan de jus (tronc de pyramide), coulees du cote du decor, fumee, 5 fruits geants craches
do
	local m = Instance.new("Model")
	m.Name = "Volcano"
	local t, h, s, y0 = V_T, V_H, V_SLOPE, -2
	make("Part", m, "Core", Vector3.new(t, h, t), V_FRAME * CFrame.new(0, y0 + h / 2, 0), VOLCANO[1])
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local outward = -rot:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local pos = outward * (t / 2 + s / 2) + Vector3.new(0, y0 + h / 2, 0)
		make("WedgePart", m, "Slope", Vector3.new(t, h, s), V_FRAME * CFrame.new(pos) * rot, VOLCANO[1])
	end
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local apex = rot:VectorToWorldSpace(Vector3.new(1, 0, -1))
		local pos = Vector3.new(-math.sign(apex.X) * (t / 2 + s / 2), y0 + h / 2, -math.sign(apex.Z) * (t / 2 + s / 2))
		make("CornerWedgePart", m, "Corner", Vector3.new(s, h, s), V_FRAME * CFrame.new(pos) * rot, VOLCANO[2])
	end
	make("Part", m, "Rim", Vector3.new(t * 0.92, 4, t * 0.92), V_FRAME * CFrame.new(0, V_TOP + 2, 0), VOLCANO[2])
	make("Part", m, "Pool", Vector3.new(t * 0.7, 4, t * 0.7), V_FRAME * CFrame.new(0, V_TOP + 2.4, 0), JUICE, nil, Enum.Material.Neon)
	-- coulees : dans le repere tourne, la pente descend vers -Z, du haut (z = -t/2) au bas (z = -(t/2+s))
	local index = 0
	local function flow(rotDeg: number, x: number, width: number, frac: number)
		index += 1
		local rot = V_FRAME * CFrame.Angles(0, math.rad(rotDeg), 0)
		local up = Vector3.new(0, V_TOP, -t / 2)
		local down = Vector3.new(0, y0, -(t / 2 + s))
		local finishPoint = up:Lerp(down, frac)
		local normal = Vector3.new(0, s, -h).Unit
		local a = Vector3.new(x, up.Y, up.Z) + normal * 0.6
		local b = Vector3.new(x, finishPoint.Y, finishPoint.Z) + normal * 0.6
		local cf = CFrame.lookAt((a + b) / 2, b, normal)
		make("Part", m, "Flow", Vector3.new(width, 1.2, (b - a).Magnitude + 1.6), rot * cf, JUICES[index], nil, Enum.Material.Neon)
	end
	flow(0, -t * 0.18, 12, 0.85)
	flow(0, t * 0.24, 9, 0.6)
	flow(0, t * 0.03, 7, 0.42)
	flow(90, t * 0.1, 10, 0.7)
	flow(-90, -t * 0.12, 10, 0.55)
	-- Fumee orangee : un seul emetteur, peu de particules, grosses et lentes. Le client pose des
	-- bouffees "deja vieilles" au debut de la cinematique pour que le panache soit deja la.
	local source = make("Part", m, "SmokeSource", Vector3.new(2, 2, 2), V_FRAME * CFrame.new(0, V_TOP + 8, 0), JUICE)
	source.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 190, 140), Color3.fromRGB(255, 236, 220))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 56), NumberSequenceKeypoint.new(1, 170) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(10, 13)
	smoke.Rate = 2
	smoke.Speed = NumberRange.new(14, 19)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Acceleration = Vector3.new(2, 0.5, 1)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-6, 6)
	smoke.LightInfluence = 0.3
	smoke.Parent = source
	-- fruits craches en eventail au-dessus du cratere : { fruit, x local, hauteur, z local, taille }
	local erupted = {
		{ "Orange", -132, 28, -60, 48 },
		{ "Strawberry", -68, 100, -28, 42 },
		{ "Grape", 4, 136, -8, 46 },
		{ "Lemon", 76, 96, -32, 38 },
		{ "Apple", 140, 24, -64, 44 },
	}
	for i, f in erupted do
		local source2 = fruitFolder and fruitFolder:FindFirstChild(f[1] :: string)
		if source2 and source2:IsA("BasePart") then
			local fruit = source2:Clone()
			fruit.Name = "Giant" .. (f[1] :: string)
			for _, child in fruit:GetChildren() do
				child:Destroy()
			end
			for _, tag in fruit:GetTags() do
				fruit:RemoveTag(tag)
			end
			fruit.Size = fruit.Size * ((f[5] :: number) / fruit.Size.Y)
			fruit.Anchored = true
			fruit.CanCollide = false
			fruit.CanQuery = false
			fruit.CanTouch = false
			fruit.CastShadow = false
			local p = (V_FRAME * CFrame.new(f[2] :: number, V_TOP + (f[3] :: number), f[4] :: number)).Position
			fruit.CFrame = CFrame.new(p) * yaw(i * 50) * CFrame.Angles(math.rad(-30 + i * 14), 0, math.rad(40 - i * 16))
			fruit.Parent = m
		end
	end
	m.Parent = backdrop
end
task.wait()

set.WorldPivot = CFrame.identity
set.Parent = ReplicatedStorage
local total = 0
local back = 0
for _, d in set:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
		if d:IsDescendantOf(backdrop) then
			back += 1
		end
	end
end
return `IntroSet : {placed - cut} arbres ({cut} retires pour la camera d'ouverture, {shadowTrees} avec ombre), `
	.. `{#fruits:GetChildren()} fruits, {bushes} buissons, {flowers} fleurs, {rocks} cailloux, `
	.. `fond : {mountains} montagnes + volcan + {farTrees} grands arbres ({back} pieces) ; total {total} pieces`
