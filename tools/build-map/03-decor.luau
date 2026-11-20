--!strict
-- Decor de la carte : arbres ronds et sapins en blocs (studs partout), buissons, fleurs,
-- collines vertes en gradins au loin. Purement visuel (pas de collision sur les petits objets).
-- Relancable : detruit et recree Workspace.Map.Decor. Positions fixes (graine 42).
-- Bases : 3 au nord (z 30..168) et 3 au sud (z -30..-168), x de -278 a 278, couloirs a x = +-100.
-- Doc : docs/systems/carte-bases.md

local TRUNK = Color3.fromRGB(112, 78, 52)
local LEAVES = { Color3.fromRGB(46, 160, 52), Color3.fromRGB(58, 176, 58), Color3.fromRGB(74, 190, 64) } -- vert vif (2026-11-19)
local PINE = { Color3.fromRGB(36, 140, 70), Color3.fromRGB(44, 154, 76), Color3.fromRGB(54, 166, 80) }
local BUSH = { Color3.fromRGB(56, 170, 56), Color3.fromRGB(70, 186, 64) }
local HILL = { Color3.fromRGB(64, 160, 58), Color3.fromRGB(70, 166, 62), Color3.fromRGB(78, 174, 66) } -- adoucies (2026-11-19 nuit)
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
	part(m, "Leaves1", Vector3.new(8, 5, 8) * s, CFrame.new(x, 8 * s, z) * yaw(r + 10), LEAVES[1], LEAF)
	part(m, "Leaves2", Vector3.new(5.5, 3.5, 5.5) * s, CFrame.new(x + 0.6 * s, 11.6 * s, z - 0.4 * s) * yaw(r + 35), LEAVES[2], LEAF)
	part(m, "Leaves3", Vector3.new(4, 3, 4) * s, CFrame.new(x - 3.2 * s, 8.6 * s, z + 2 * s) * yaw(r - 20), LEAVES[3], LEAF)
	part(m, "Leaves4", Vector3.new(3.6, 2.6, 3.6) * s, CFrame.new(x + 3 * s, 7.4 * s, z + 2.4 * s) * yaw(r + 50), LEAVES[2], LEAF)
	m.Parent = parent
end

-- Sapin : 3 etages un peu tournes
local function pine(parent: Instance, x: number, z: number, s: number)
	local m = Instance.new("Model")
	m.Name = "Pine"
	local r = rng:NextNumber(0, 90)
	part(m, "Trunk", Vector3.new(1.6, 4, 1.6) * s, CFrame.new(x, 2 * s, z) * yaw(r), TRUNK)
	part(m, "Leaves1", Vector3.new(7, 4, 7) * s, CFrame.new(x, 6 * s, z) * yaw(r + 15), PINE[1], LEAF)
	part(m, "Leaves2", Vector3.new(5.2, 3.5, 5.2) * s, CFrame.new(x, 9.6 * s, z) * yaw(r + 35), PINE[2], LEAF)
	part(m, "Leaves3", Vector3.new(3.2, 3, 3.2) * s, CFrame.new(x, 12.8 * s, z) * yaw(r + 5), PINE[3], LEAF)
	part(m, "Tip", Vector3.new(1.4, 1.6, 1.4) * s, CFrame.new(x, 15 * s, z) * yaw(r + 25), PINE[3], LEAF)
	m.Parent = parent
end

local function bush(parent: Instance, x: number, z: number, s: number)
	local m = Instance.new("Model")
	m.Name = "Bush"
	part(m, "A", Vector3.new(3.4, 2.6, 3.4) * s, CFrame.new(x, 1.3 * s, z) * yaw(rng:NextNumber(0, 90)), BUSH[1], BUSH_LEAF)
	part(m, "B", Vector3.new(2.4, 2, 2.4) * s, CFrame.new(x + 1.6 * s, 1 * s, z + 0.8 * s) * yaw(rng:NextNumber(0, 90)), BUSH[2], BUSH_LEAF)
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
	-- Couloirs entre les bases (x = -100 et 100) et bords exterieurs (x = +-296)
	for _, gx in { -100, 100 } do
		roundTree(trees, gx - 4, side * 70, 1.1)
		pine(trees, gx + 6, side * 92, 1.2)
		roundTree(trees, gx + 3, side * 48, 0.9)
		bush(trees, gx - 6, side * 34, 1)
		bush(trees, gx + 7, side * 37, 0.8)
		flowers(trees, gx, side * 58, 8)
	end
	for _, gx in { -296, 296 } do
		roundTree(trees, gx, side * 55, 1.2)
		pine(trees, gx + 8, side * 85, 1.3)
		bush(trees, gx - 5, side * 30, 1)
	end
	-- Foret derriere les bases (z de 178 a 208), melange sapins / arbres ronds
	local x = -360
	while x < 360 do
		local z = side * rng:NextNumber(178, 208)
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
for _, p in { Vector2.new(-340, 30), Vector2.new(-340, -30), Vector2.new(-360, 6), Vector2.new(-296, 38), Vector2.new(-296, -38) } do
	roundTree(trees, p.X, p.Y, 1.1)
end
bush(trees, -338, 18, 1)
bush(trees, -338, -18, 1)
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
	local x = -370
	while x < 380 do
		local w = rng:NextNumber(50, 85)
		hill(x, side * rng:NextNumber(214, 226), w, rng:NextNumber(26, 34), rng:NextNumber(7, 12))
		x += w * 0.75
	end
end
for _, side in { 1, -1 } do
	local z = -200
	while z < 210 do
		local d = rng:NextNumber(50, 80)
		hill(side * rng:NextNumber(392, 400), z, rng:NextNumber(24, 30), d, rng:NextNumber(7, 12))
		z += d * 0.75
	end
end
-- Quelques rochers
for _ = 1, 14 do
	local rx, rz = rng:NextNumber(-340, 340), rng:NextNumber(178, 206) * (if rng:NextNumber() < 0.5 then 1 else -1)
	part(hills, "Rock", Vector3.new(rng:NextNumber(2, 4), rng:NextNumber(1.2, 2.4), rng:NextNumber(2, 3.5)), CFrame.new(rx, 0.7, rz) * yaw(rng:NextNumber(0, 90)), ROCK)
end
hills.Parent = decor

-- Anti z-fighting : arbres et collines sont places au hasard, un dessus de feuillage peut tomber
-- au meme niveau qu'un dessus de colline (vu le 2026-11-19 : RoundTree vers x -348, z -205).
-- Si deux dessus de couleurs differentes sont a moins de 0.05 stud et se recouvrent, on monte
-- le dessus du second de 0.06 en le grandissant (le bas ne bouge pas : rien ne decolle du sol).
-- Toutes les pieces ici ne tournent qu'autour de Y.
do
	local tops = {}
	for _, p in decor:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(tops, p)
		end
	end
	for i = 1, #tops do
		local a = tops[i]
		local ra = math.max(a.Size.X, a.Size.Z) * 0.71
		for j = i + 1, #tops do
			local b = tops[j]
			local topA = a.Position.Y + a.Size.Y / 2
			local topB = b.Position.Y + b.Size.Y / 2
			local rb = math.max(b.Size.X, b.Size.Z) * 0.71
			local flat = Vector3.new(a.Position.X - b.Position.X, 0, a.Position.Z - b.Position.Z).Magnitude
			if math.abs(topA - topB) < 0.05 and flat < ra + rb and a.Color ~= b.Color then
				b.Size += Vector3.new(0, 0.06, 0)
				b.CFrame += Vector3.new(0, 0.03, 0)
			end
		end
	end
end

decor.Parent = map
return "Decor OK: " .. #decor:GetDescendants() .. " objets"
