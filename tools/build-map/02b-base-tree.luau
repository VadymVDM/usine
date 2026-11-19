--!strict
-- BaseTemplate, morceau 2/6 : l'arbre (racines, tronc, branches, feuillage en grappes, pommes),
-- son rond d'herbe fleuri, la zone de chute des fruits. A lancer apres 02a.
-- Doc : docs/systems/carte-bases.md

local TX, TZ = 52, 64 -- centre de l'arbre (repere local de la base)

local TRUNK = Color3.fromRGB(112, 78, 52)
local TRUNK_DARK = Color3.fromRGB(96, 66, 44)
local LEAVES = { Color3.fromRGB(62, 124, 50), Color3.fromRGB(76, 140, 56), Color3.fromRGB(92, 156, 64) }
local ORCHARD = { Color3.fromRGB(96, 156, 70), Color3.fromRGB(102, 162, 74), Color3.fromRGB(108, 168, 78) }
local APPLE = Color3.fromRGB(200, 48, 42)
local STEM = Color3.fromRGB(92, 64, 42)
local ROCK = Color3.fromRGB(150, 150, 146)
local FLOWERS = { Color3.fromRGB(226, 120, 150), Color3.fromRGB(246, 236, 220), Color3.fromRGB(240, 204, 84) }

local STUDS = Enum.SurfaceType.Studs
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
local rng = Random.new(5)

local model = game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
assert(model, "Lancer 02a d'abord")
local oldTree = model:FindFirstChild("Tree")
if oldTree then
	oldTree:Destroy()
end
local tree = Instance.new("Folder")
tree.Name = "Tree"

local function at(x: number, y: number, z: number, yawDeg: number?): CFrame
	return CFrame.new(TX + x, y, TZ + z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

-- Rond d'herbe "en escalier" (3 dalles a des hauteurs differentes : pas de z-fighting)
part(tree, "GrassA", Vector3.new(24, 0.1, 13), at(0, 0.33, 0), ORCHARD[1], { TopSurface = STUDS })
part(tree, "GrassB", Vector3.new(13, 0.1, 24), at(0, 0.35, 0), ORCHARD[2])
part(tree, "GrassC", Vector3.new(19.5, 0.1, 19.5), at(0, 0.37, 0), ORCHARD[3])

-- Fleurs et cailloux autour
for i = 1, 14 do
	local angle = (i / 14) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
	local r = rng:NextNumber(6.5, 9)
	local x, z = math.cos(angle) * r, math.sin(angle) * r
	local yaw = rng:NextNumber(0, 90)
	part(tree, "FlowerLeaves", Vector3.new(0.9, 0.25, 0.9), at(x, 0.545, z, yaw), LEAVES[2], DECOR)
	part(tree, "Flower", Vector3.new(0.55, 0.55, 0.55), at(x, 0.95, z, yaw), FLOWERS[(i % #FLOWERS) + 1], DECOR)
end
part(tree, "Rock", Vector3.new(1.8, 1, 1.4), at(-8, 0.8, 5, 25), ROCK)
part(tree, "Rock", Vector3.new(1.1, 0.7, 1), at(-7, 0.65, 6.3, -10), ROCK)
part(tree, "Rock", Vector3.new(1.4, 0.8, 1.2), at(7.5, 0.7, -6, 40), ROCK)
task.wait()

-- Racines
for i = 0, 3 do
	local yaw = i * 90 + 45
	local cf = at(0, 0.8, 0, yaw) * CFrame.new(0, 0, -2.4) * CFrame.Angles(math.rad(12), 0, 0)
	part(tree, "Root", Vector3.new(1.4, 1.1, 3.2), cf, TRUNK_DARK)
end

-- Tronc en 3 blocs de plus en plus fins, legerement tournes
part(tree, "Trunk", Vector3.new(4, 5, 4), at(0, 2.8, 0), TRUNK)
part(tree, "TrunkMid", Vector3.new(3.4, 4, 3.4), at(0, 7.3, 0, 10), TRUNK)
part(tree, "TrunkTop", Vector3.new(2.8, 3, 2.8), at(0, 10.8, 0, -6), TRUNK_DARK)

-- Branches vers les grappes laterales
for _, yaw in { 35, 215 } do
	local cf = at(0, 9.5, 0, yaw) * CFrame.Angles(math.rad(45), 0, 0) * CFrame.new(0, 0, -3)
	part(tree, "Branch", Vector3.new(1.4, 1.4, 6), cf, TRUNK)
end

-- Feuillage : grappes de tailles et d'angles differents (aucune face au meme endroit)
local clusters = {
	{ Vector3.new(0, 15, 0), Vector3.new(15, 6, 15), 0, 1 },
	{ Vector3.new(6, 14, 4), Vector3.new(8, 5, 8), 25, 2 },
	{ Vector3.new(-6, 14.6, -3), Vector3.new(8, 5, 8), -20, 2 },
	{ Vector3.new(-4, 13.5, 6), Vector3.new(7, 4.5, 7), 40, 3 },
	{ Vector3.new(5, 13.8, -6), Vector3.new(7, 4.5, 7), 15, 3 },
	{ Vector3.new(1, 19, 0), Vector3.new(10, 4, 10), 12, 2 },
	{ Vector3.new(-1, 22, 1), Vector3.new(6, 3, 6), -15, 3 },
	-- petites grappes au bord pour casser la silhouette carree
	{ Vector3.new(9, 15.5, -1), Vector3.new(5, 4, 5), 30, 1 },
	{ Vector3.new(-8.5, 16.5, -1), Vector3.new(5, 4, 5), -25, 2 },
	{ Vector3.new(0, 15.8, -9), Vector3.new(6, 4, 4.5), 10, 3 },
	{ Vector3.new(2, 14.8, 9), Vector3.new(6, 3.6, 5), -8, 1 },
}
for i, c in clusters do
	local pos: Vector3, size: Vector3 = c[1], c[2]
	part(tree, "Leaves" .. i, size, at(pos.X, pos.Y, pos.Z, c[3]), LEAVES[c[4]])
end
task.wait()

-- Pommes qui pendent sous le feuillage et sur les cotes
local apples = {
	Vector3.new(7.5, 11, 2), Vector3.new(-7, 11.6, -5), Vector3.new(3, 11.5, -7.4),
	Vector3.new(-3, 11.5, 7.4), Vector3.new(8, 10.9, 6), Vector3.new(-8.6, 12, 1),
	Vector3.new(1, 11.5, 7.6), Vector3.new(-1.5, 11.5, -7.6), Vector3.new(7.8, 15.5, -2),
	Vector3.new(-7.8, 16, 3), Vector3.new(2, 16.5, 7.8), Vector3.new(-3, 20, -5.2),
}
for _, a in apples do
	local yaw = rng:NextNumber(0, 90)
	part(tree, "Apple", Vector3.new(1, 1, 1), at(a.X, a.Y, a.Z, yaw), APPLE, DECOR)
	part(tree, "AppleStem", Vector3.new(0.2, 0.45, 0.2), at(a.X, a.Y + 0.7, a.Z, yaw), STEM, DECOR)
end

-- Zone ou tombent les fruits (le code choisit un point dans ce carre, hors du tronc)
part(tree, "FruitArea", Vector3.new(20, 1, 20), at(0, 0.9, 0), Color3.new(1, 0, 0), MARKER)
-- Point d'accroche du texte "Tree full!"
part(tree, "TreeLabelAnchor", Vector3.new(1, 1, 1), at(0, 26, 0), Color3.new(1, 0, 0), MARKER)

tree.Parent = model
return "Tree OK: " .. #tree:GetDescendants()
