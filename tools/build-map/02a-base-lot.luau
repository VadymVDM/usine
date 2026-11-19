--!strict
-- BaseTemplate, morceau 1/6 : modele, origine, dossiers, terrain, chemins, cloture, haie, fleurs.
-- Cree ServerStorage.BaseTemplate (detruit l'ancien). Lancer ensuite 02b ... 02f dans l'ordre.
-- Repere local : origine = bord avant (cote route) a la limite zone 1 / zones 2-3, au sol (y = 0).
--   +Z = de la route vers le fond (0 -> 80). Zone 1 : x 0 -> 70. Zones 2-3 fermees : x -44 -> 0.
--   Le terrain de la base est a y = 0.3.
-- Doc : docs/systems/carte-bases.md

local LOT = Color3.fromRGB(116, 176, 84)
local LOCKED_GROUND = Color3.fromRGB(98, 150, 72)
local PATH = Color3.fromRGB(206, 194, 168)
local PATH_EDGE = Color3.fromRGB(172, 160, 136)
local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local WOOD_CAP = Color3.fromRGB(186, 146, 102)
local HEDGE = Color3.fromRGB(70, 128, 58)
local HEDGE_LIGHT = Color3.fromRGB(84, 142, 66)
local SOIL = Color3.fromRGB(116, 84, 58)
local LEAF = Color3.fromRGB(80, 140, 62)
local FLOWERS = {
	Color3.fromRGB(226, 120, 150),
	Color3.fromRGB(246, 236, 220),
	Color3.fromRGB(240, 204, 84),
	Color3.fromRGB(190, 120, 210),
}

local STUDS = Enum.SurfaceType.Studs

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

local function box(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, props: { [string]: any }?): BasePart
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, props)
end

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }
local rng = Random.new(11)

local ServerStorage = game:GetService("ServerStorage")
local old = ServerStorage:FindFirstChild("BaseTemplate")
if old then
	old:Destroy()
end

local model = Instance.new("Model")
model.Name = "BaseTemplate"
local origin = part(model, "Origin", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0), Color3.new(1, 0, 1), {
	Transparency = 1,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
})
model.PrimaryPart = origin
for _, folderName in { "Lot", "Tree", "Production", "Counter", "Entrance", "Staff", "Upgrades", "ZoneLocks", "Markers", "Dynamic" } do
	local f = Instance.new("Folder")
	f.Name = folderName
	f.Parent = model
end
local lot = model:FindFirstChild("Lot") :: Folder

-- Terrain (dessus a 0.3)
box(lot, "Ground", 0, 70, -0.7, 0.3, 0, 80, LOT)
box(lot, "LockedGround", -44, 0, -0.7, 0.3, 0, 80, LOCKED_GROUND)

-- Chemins en dalles (dessus 0.35) + bordures (dessus 0.42) seulement sur les cotes non relies
box(lot, "PathMain", 18, 26, -0.6, 0.35, 0.05, 28, PATH)
box(lot, "PathCross", 6, 66, -0.6, 0.35, 28, 32, PATH)
box(lot, "PathTree", 36, 42, -0.6, 0.35, 32, 52, PATH)
local edges = {
	{ 17.4, 18, 0.05, 28 }, -- chemin principal, gauche
	{ 26, 26.6, 0.05, 28 }, -- chemin principal, droite
	{ 5.4, 6, 27.4, 32.6 }, -- traverse, bout
	{ 66, 66.6, 27.4, 32.6 }, -- traverse, bout
	{ 6, 17.4, 27.4, 28 }, -- traverse, devant (gauche du chemin principal)
	{ 26.6, 66, 27.4, 28 }, -- traverse, devant (droite)
	{ 6, 35.4, 32, 32.6 }, -- traverse, fond (gauche du chemin de l'arbre)
	{ 42.6, 66, 32, 32.6 }, -- traverse, fond (droite)
	{ 35.4, 36, 32, 52 }, -- chemin de l'arbre
	{ 42, 42.6, 32, 52 },
}
for i, e in edges do
	box(lot, "PathEdge" .. i, e[1], e[2], -0.55, 0.42, e[3], e[4], PATH_EDGE)
end
task.wait()

-- Cloture en bois (poteaux tous les 5 studs au plus, 2 traverses)
local fence = Instance.new("Folder")
fence.Name = "Fence"
local function fencePost(p: Vector3)
	box(fence, "Post", p.X - 0.5, p.X + 0.5, 0.3, 3.9, p.Z - 0.5, p.Z + 0.5, WOOD_DARK)
	box(fence, "Cap", p.X - 0.65, p.X + 0.65, 3.9, 4.25, p.Z - 0.65, p.Z + 0.65, WOOD_CAP)
end
local function fenceRun(a: Vector3, b: Vector3, skipFirstPost: boolean)
	local dir = b - a
	local n = math.max(1, math.ceil(dir.Magnitude / 5))
	for i = 0, n do
		if not (i == 0 and skipFirstPost) then
			fencePost(a + dir * (i / n))
		end
	end
	for i = 1, n do
		local p0, p1 = a + dir * ((i - 1) / n), a + dir * (i / n)
		local len = (p1 - p0).Magnitude
		for _, y in { 1.5, 2.9 } do
			local mid = (p0 + p1) / 2 + Vector3.new(0, y, 0)
			part(fence, "Rail", Vector3.new(0.35, 0.5, len), CFrame.lookAt(mid, mid + dir.Unit), WOOD)
		end
	end
end
-- Devant : passage a l'entree (x 15 -> 28.8) et devant le comptoir (x 32 -> 58)
fenceRun(Vector3.new(0.5, 0, 0.5), Vector3.new(15, 0, 0.5), false)
fenceRun(Vector3.new(28.8, 0, 0.5), Vector3.new(32, 0, 0.5), false)
fenceRun(Vector3.new(58, 0, 0.5), Vector3.new(69.5, 0, 0.5), false)
-- Cotes jusqu'a la haie du fond
fenceRun(Vector3.new(0.5, 0, 0.5), Vector3.new(0.5, 0, 77), true)
fenceRun(Vector3.new(69.5, 0, 0.5), Vector3.new(69.5, 0, 77), true)
fence.Parent = lot
task.wait()

-- Haie au fond, avec des bosses tournees
local hedge = Instance.new("Folder")
hedge.Name = "Hedge"
box(hedge, "Hedge", 1, 69, 0.3, 3.6, 77.2, 79.4, HEDGE)
local hx = 3
local index = 0
while hx < 68 do
	index += 1
	local c = Vector3.new(hx + rng:NextNumber(-0.5, 0.5), 4.2, 78.3)
	part(hedge, "Bump", Vector3.new(3.4, 1.4, 2.6), CFrame.new(c) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0), if index % 2 == 0 then HEDGE_LIGHT else HEDGE)
	hx += 4
end
hedge.Parent = lot

-- Massifs de fleurs
local function flowerBed(name: string, x0: number, x1: number, z0: number, z1: number)
	local bed = Instance.new("Model")
	bed.Name = name
	box(bed, "Soil", x0, x1, 0.3, 0.6, z0, z1, SOIL)
	local x = x0 + 0.9
	local i = 0
	while x < x1 - 0.6 do
		i += 1
		local z = (z0 + z1) / 2 + rng:NextNumber(-0.4, 0.4)
		local yaw = CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0)
		part(bed, "Leaves", Vector3.new(1, 0.3, 1), CFrame.new(x, 0.75, z) * yaw, LEAF, DECOR)
		part(bed, "Flower", Vector3.new(0.6, 0.6, 0.6), CFrame.new(x, 1.2, z) * yaw, FLOWERS[(i % #FLOWERS) + 1], DECOR)
		x += 1.5
	end
	bed.Parent = lot
end
flowerBed("FlowerBedFront", 3, 13, 2.2, 4.4)
flowerBed("FlowerBedBack", 22, 36, 74.6, 76.6)

-- Buisson au coin du fond
local bush = Instance.new("Model")
bush.Name = "Bush"
part(bush, "A", Vector3.new(3.6, 2.8, 3.6), CFrame.new(66, 1.7, 73) * CFrame.Angles(0, math.rad(20), 0), HEDGE)
part(bush, "B", Vector3.new(2.6, 2.2, 2.6), CFrame.new(64.2, 1.4, 74.4) * CFrame.Angles(0, math.rad(-15), 0), HEDGE_LIGHT)
part(bush, "C", Vector3.new(2.2, 1.6, 2.2), CFrame.new(66.6, 3.3, 72.6) * CFrame.Angles(0, math.rad(40), 0), HEDGE_LIGHT)
bush.Parent = lot

model.Parent = ServerStorage
return "Lot OK: " .. #model:GetDescendants()
