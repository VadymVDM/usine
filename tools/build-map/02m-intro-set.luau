--!strict
-- Decor de la cinematique d'ouverture : ReplicatedStorage.IntroSet (2026-11-22). Relancable (detruit
-- et recree). A lancer dans Studio (mode Edit, MCP execute_luau) apres un Rojo synchronise, puis
-- sauvegarder la place. Le client (IntroController) le clone a Config/Intro.SetOrigin, chez lui
-- seulement, et le detruit a la fin.
-- Contenu (repere : pied du grand arbre = origine, sol a y = 0, la marche va vers +X) :
--   Ground (herbe a studs comme la carte), Clearing, Path (chemin de terre), Forest (copies des arbres
--   blocky de Workspace.Map.Decor.Trees, loin du chemin et des cameras), BigTree (arbre niveau 10 de
--   l'etage 1, Lib/TreeBuilder, + fruits Intro.TreeFruits accroches au feuillage), Sapling (arbre niveau 1,
--   reduit a Intro.SaplingScale : celui qu'on tient en main), Shovel (pelle blocky, pivot = poignee,
--   le manche descend vers -Y), Hole (trou de terre, cache au depart).
-- Jamais de Neon (regle du ressenti). Rien ne bloque ni ne touche (CanCollide / CanTouch / CanQuery faux).
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

for _, parent in { ReplicatedStorage, workspace } do
	local old = parent:FindFirstChild("IntroSet")
	if old then
		old:Destroy()
	end
end
local set = Instance.new("Model")
set.Name = "IntroSet"
set.Parent = workspace -- le temps de la construction (raycasts des fruits), range a la fin

-- Sol ---------------------------------------------------------------------------------------------
local ground = box(set, "Ground", Vector3.new(320, 2, 320), CFrame.new(0, -1, 0), GRASS)
ground.CastShadow = false
local clearing = box(set, "Clearing", Vector3.new(30, 0.2, 30), CFrame.new(0, 0.1, 0), CLEARING)
clearing.CastShadow = false
local path = box(set, "Path", Vector3.new(70, 0.2, 6), CFrame.new(-50, 0.12, Intro.ActorStart.Z), DIRT)
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
	local onPath = x < -8 and math.abs(z - Intro.ActorStart.Z) < 9
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

set.WorldPivot = CFrame.identity
set.Parent = ReplicatedStorage
return `IntroSet : {placed} arbres, {#fruits:GetChildren()} fruits, {#set:GetDescendants()} instances`
