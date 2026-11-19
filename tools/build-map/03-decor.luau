--!strict
-- Decor de la carte : arbres ronds et sapins en blocs (studs partout), buissons, fleurs,
-- collines vertes en gradins au loin. Purement visuel (pas de collision sur les petits objets).
-- Relancable : detruit et recree Workspace.Map.Decor. Positions fixes (graine 42).
-- Bases : 3 au nord (z 30..110) et 3 au sud (z -30..-110), x de -207 a 207, couloirs a x = +-75.
-- Doc : docs/systems/carte-bases.md

local TRUNK = Color3.fromRGB(112, 78, 52)
local LEAVES = { Color3.fromRGB(62, 124, 50), Color3.fromRGB(76, 140, 56), Color3.fromRGB(92, 156, 64) }
local PINE = { Color3.fromRGB(46, 104, 52), Color3.fromRGB(56, 118, 58), Color3.fromRGB(66, 130, 62) }
local BUSH = { Color3.fromRGB(70, 128, 58), Color3.fromRGB(84, 142, 66) }
local HILL = { Color3.fromRGB(92, 146, 70), Color3.fromRGB(100, 154, 74), Color3.fromRGB(108, 162, 80) }
local ROCK = Color3.fromRGB(150, 150, 146)
local FLOWERS = { Color3.fromRGB(226, 120, 150), Color3.fromRGB(246, 236, 220), Color3.fromRGB(240, 204, 84), Color3.fromRGB(190, 120, 210) }

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

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }

local map = workspace:FindFirstChild("Map")
assert(map, "Lancer 01 d'abord")
local old = map:FindFirstChild("Decor")
if old then
	old:Destroy()
end
local decor = Instance.new("Folder")
decor.Name = "Decor"
local rng = Random.new(42)

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- Arbre rond : tronc + grappes de feuilles tournees
local function roundTree(parent: Instance, x: number, z: number, s: number)
	local m = Instance.new("Model")
	m.Name = "RoundTree"
	local r = rng:NextNumber(0, 90)
	part(m, "Trunk", Vector3.new(1.8, 6, 1.8) * s, CFrame.new(x, 3 * s, z) * yaw(r), TRUNK)
	part(m, "Leaves1", Vector3.new(8, 5, 8) * s, CFrame.new(x, 8 * s, z) * yaw(r + 10), LEAVES[1])
	part(m, "Leaves2", Vector3.new(5.5, 3.5, 5.5) * s, CFrame.new(x + 0.6 * s, 11.6 * s, z - 0.4 * s) * yaw(r + 35), LEAVES[2])
	part(m, "Leaves3", Vector3.new(4, 3, 4) * s, CFrame.new(x - 3.2 * s, 8.6 * s, z + 2 * s) * yaw(r - 20), LEAVES[3])
	part(m, "Leaves4", Vector3.new(3.6, 2.6, 3.6) * s, CFrame.new(x + 3 * s, 7.4 * s, z + 2.4 * s) * yaw(r + 50), LEAVES[2])
	m.Parent = parent
end

-- Sapin : 3 etages un peu tournes
local function pine(parent: Instance, x: number, z: number, s: number)
	local m = Instance.new("Model")
	m.Name = "Pine"
	local r = rng:NextNumber(0, 90)
	part(m, "Trunk", Vector3.new(1.6, 4, 1.6) * s, CFrame.new(x, 2 * s, z) * yaw(r), TRUNK)
	part(m, "Leaves1", Vector3.new(7, 4, 7) * s, CFrame.new(x, 6 * s, z) * yaw(r + 15), PINE[1])
	part(m, "Leaves2", Vector3.new(5.2, 3.5, 5.2) * s, CFrame.new(x, 9.6 * s, z) * yaw(r + 35), PINE[2])
	part(m, "Leaves3", Vector3.new(3.2, 3, 3.2) * s, CFrame.new(x, 12.8 * s, z) * yaw(r + 5), PINE[3])
	part(m, "Tip", Vector3.new(1.4, 1.6, 1.4) * s, CFrame.new(x, 15 * s, z) * yaw(r + 25), PINE[3])
	m.Parent = parent
end

local function bush(parent: Instance, x: number, z: number, s: number)
	local m = Instance.new("Model")
	m.Name = "Bush"
	part(m, "A", Vector3.new(3.4, 2.6, 3.4) * s, CFrame.new(x, 1.3 * s, z) * yaw(rng:NextNumber(0, 90)), BUSH[1], DECOR)
	part(m, "B", Vector3.new(2.4, 2, 2.4) * s, CFrame.new(x + 1.6 * s, 1 * s, z + 0.8 * s) * yaw(rng:NextNumber(0, 90)), BUSH[2], DECOR)
	m.Parent = parent
end

local function flowers(parent: Instance, x: number, z: number, count: number)
	for i = 1, count do
		local fx, fz = x + rng:NextNumber(-3, 3), z + rng:NextNumber(-3, 3)
		local r = yaw(rng:NextNumber(0, 90))
		part(parent, "FlowerLeaves", Vector3.new(0.9, 0.25, 0.9), CFrame.new(fx, 0.125, fz) * r, BUSH[2], DECOR)
		part(parent, "Flower", Vector3.new(0.55, 0.55, 0.55), CFrame.new(fx, 0.52, fz) * r, FLOWERS[rng:NextInteger(1, #FLOWERS)], DECOR)
	end
end

local trees = Instance.new("Folder")
trees.Name = "Trees"
for _, side in { 1, -1 } do
	-- Couloirs entre les bases (x = -75 et 75) et bords exterieurs (x = +-230)
	for _, gx in { -75, 75 } do
		roundTree(trees, gx - 4, side * 70, 1.1)
		pine(trees, gx + 6, side * 92, 1.2)
		roundTree(trees, gx + 3, side * 48, 0.9)
		bush(trees, gx - 6, side * 34, 1)
		bush(trees, gx + 7, side * 37, 0.8)
		flowers(trees, gx, side * 58, 8)
	end
	for _, gx in { -232, 232 } do
		roundTree(trees, gx, side * 55, 1.2)
		pine(trees, gx + 8, side * 85, 1.3)
		bush(trees, gx - 5, side * 30, 1)
	end
	-- Foret derriere les bases (z de 125 a 175), melange sapins / arbres ronds
	local x = -320
	while x < 320 do
		local z = side * rng:NextNumber(122, 176)
		local s = rng:NextNumber(0.9, 1.5)
		if rng:NextNumber() < 0.55 then
			pine(trees, x + rng:NextNumber(-4, 4), z, s)
		else
			roundTree(trees, x + rng:NextNumber(-4, 4), z, s)
		end
		x += rng:NextNumber(9, 16)
	end
	task.wait()
end
-- Autour de la place du spawn
for _, p in { Vector2.new(-300, 30), Vector2.new(-300, -30), Vector2.new(-320, 6), Vector2.new(-245, 34), Vector2.new(-245, -34) } do
	roundTree(trees, p.X, p.Y, 1.1)
end
bush(trees, -298, 18, 1)
bush(trees, -298, -18, 1)
trees.Parent = decor
task.wait()

-- Collines en gradins au loin (nord, sud et extremites est / ouest)
local hills = Instance.new("Folder")
hills.Name = "Hills"
local function hill(cx: number, cz: number, w: number, d: number, h: number)
	local m = Instance.new("Model")
	m.Name = "Hill"
	local r = rng:NextNumber(-8, 8)
	part(m, "Tier1", Vector3.new(w, h, d), CFrame.new(cx, h / 2, cz) * yaw(r), HILL[1])
	part(m, "Tier2", Vector3.new(w * 0.7, h * 0.8, d * 0.7), CFrame.new(cx + w * 0.05, h + h * 0.4, cz) * yaw(r + 6), HILL[2])
	part(m, "Tier3", Vector3.new(w * 0.4, h * 0.6, d * 0.45), CFrame.new(cx - w * 0.04, h * 1.8 + h * 0.3, cz) * yaw(r - 5), HILL[3])
	m.Parent = hills
end
for _, side in { 1, -1 } do
	local x = -330
	while x < 340 do
		local w = rng:NextNumber(50, 85)
		hill(x, side * rng:NextNumber(196, 208), w, rng:NextNumber(26, 34), rng:NextNumber(7, 12))
		x += w * 0.75
	end
end
for _, side in { 1, -1 } do
	local z = -180
	while z < 190 do
		local d = rng:NextNumber(50, 80)
		hill(side * rng:NextNumber(312, 320), z, rng:NextNumber(24, 30), d, rng:NextNumber(7, 12))
		z += d * 0.75
	end
end
-- Quelques rochers
for _ = 1, 14 do
	local rx, rz = rng:NextNumber(-300, 300), rng:NextNumber(118, 190) * (if rng:NextNumber() < 0.5 then 1 else -1)
	part(hills, "Rock", Vector3.new(rng:NextNumber(2, 4), rng:NextNumber(1.2, 2.4), rng:NextNumber(2, 3.5)), CFrame.new(rx, 0.7, rz) * yaw(rng:NextNumber(0, 90)), ROCK)
end
hills.Parent = decor

decor.Parent = map
return "Decor OK: " .. #decor:GetDescendants() .. " objets"
