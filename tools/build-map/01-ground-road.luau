--!strict
-- Carte : sol, route, trottoirs, lampadaires, place du spawn (fontaine de jus), 6 emplacements de
-- base, limites invisibles. A lancer dans Studio (mode Edit) via MCP execute_luau.
-- Relancable : detruit et recree Workspace.Map (sauf Map.Decor, voir 03-decor.luau).
-- Couleurs naturelles, studs sur toutes les faces visibles.
-- Doc : docs/systems/carte-bases.md

local ROAD_HALF_LENGTH = 250 -- route le long de l'axe X, de -250 a 250
local ROAD_HALF_WIDTH = 12
local SIDEWALK_WIDTH = 5
local PLOT_FRONT_Z = 30 -- distance centre de la route -> bord avant d'une base
local BASE_SPACING = 150 -- distance entre les centres de deux bases
local PLOT_CENTER_X = 13 -- centre de la base dans son repere local (x de -44 a 70)
local GROUND_SIZE = Vector3.new(680, 2, 460) -- zone jouable (limites invisibles)
local GROUND_TILE = 2048 -- taille max d'une Part ; 3 x 3 dalles d'herbe : pas de vide a l'horizon
local PLAZA_X = -272

local GRASS = Color3.fromRGB(104, 164, 76)
local ASPHALT = Color3.fromRGB(84, 88, 98)
local DASH = Color3.fromRGB(232, 206, 118)
local SIDEWALK = Color3.fromRGB(198, 194, 184)
local CURB = Color3.fromRGB(168, 164, 154)
local STONE = Color3.fromRGB(206, 194, 168)
local STONE_DARK = Color3.fromRGB(176, 164, 140)
local BASIN = Color3.fromRGB(184, 178, 168)
local JUICE = Color3.fromRGB(240, 156, 52)
local LAMP_POST = Color3.fromRGB(66, 70, 80)
local LAMP_LIGHT = Color3.fromRGB(255, 232, 176)

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

local function box(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, props: { [string]: any }?): BasePart
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, props)
end

local SMOOTH = {
	TopSurface = SMOOTH_SURF,
	BottomSurface = SMOOTH_SURF,
	FrontSurface = SMOOTH_SURF,
	BackSurface = SMOOTH_SURF,
	LeftSurface = SMOOTH_SURF,
	RightSurface = SMOOTH_SURF,
}
local INVISIBLE = { Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false }

-- Anciens objets par defaut de la place vide
for _, name in { "Baseplate", "SpawnLocation" } do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local map = workspace:FindFirstChild("Map")
if not map then
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
end
assert(map)
for _, name in { "Ground", "Road", "Spawn", "BaseSlots", "Bounds" } do
	local old = map:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- Sol (herbe), dessus a y = 0
local ground = Instance.new("Folder")
ground.Name = "Ground"
for gx = -1, 1 do
	for gz = -1, 1 do
		part(ground, if gx == 0 and gz == 0 then "Grass" else "GrassFar", Vector3.new(GROUND_TILE, 2, GROUND_TILE), CFrame.new(gx * GROUND_TILE, -1, gz * GROUND_TILE), GRASS)
	end
end
ground.Parent = map
task.wait()

-- Route, tirets, trottoirs avec bordure, lampadaires
local road = Instance.new("Folder")
road.Name = "Road"
box(road, "Asphalt", -ROAD_HALF_LENGTH, ROAD_HALF_LENGTH, -0.95, 0.05, -ROAD_HALF_WIDTH, ROAD_HALF_WIDTH, ASPHALT)
local x = -ROAD_HALF_LENGTH + 8
while x < ROAD_HALF_LENGTH - 4 do
	box(road, "Dash", x - 3, x + 3, 0.05, 0.12, -0.5, 0.5, DASH, { CanCollide = false })
	x += 14
end
for _, side in { 1, -1 } do
	local inner = side * ROAD_HALF_WIDTH
	local outer = side * (ROAD_HALF_WIDTH + SIDEWALK_WIDTH)
	box(road, "Sidewalk", -ROAD_HALF_LENGTH, ROAD_HALF_LENGTH, -0.6, 0.4, math.min(inner, outer), math.max(inner, outer), SIDEWALK)
	-- bordure cote route : 0.05 plus haute et 0.01 plus pres de la route que le trottoir,
	-- un peu plus courte en x (aucune face au meme endroit que celle du trottoir)
	local c0, c1 = inner - side * 0.01, inner + side * 0.8
	box(road, "Curb", -ROAD_HALF_LENGTH + 0.1, ROAD_HALF_LENGTH - 0.1, -0.55, 0.45, math.min(c0, c1), math.max(c0, c1), CURB)
	-- Lampadaires (bras tourne vers la route)
	local lx = -225
	while lx <= 225 do
		local z = side * (ROAD_HALF_WIDTH + SIDEWALK_WIDTH - 1.2)
		local lamp = Instance.new("Model")
		lamp.Name = "StreetLamp"
		box(lamp, "Foot", lx - 0.8, lx + 0.8, 0.4, 1, z - 0.8, z + 0.8, LAMP_POST)
		box(lamp, "Post", lx - 0.4, lx + 0.4, 1, 10.5, z - 0.4, z + 0.4, LAMP_POST)
		local armZ0, armZ1 = z, z - side * 2.6
		box(lamp, "Arm", lx - 0.3, lx + 0.3, 10, 10.6, math.min(armZ0, armZ1), math.max(armZ0, armZ1), LAMP_POST)
		local hz = z - side * 2.6
		box(lamp, "Head", lx - 0.8, lx + 0.8, 9.6, 10.4, hz - 0.8, hz + 0.8, LAMP_POST)
		box(lamp, "Bulb", lx - 0.55, lx + 0.55, 9.35, 9.6, hz - 0.55, hz + 0.55, LAMP_LIGHT, {
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		lamp.Parent = road
		lx += 50
	end
end
road.Parent = map
task.wait()

-- Place du spawn au bout ouest de la route, avec une fontaine de jus
local spawn = Instance.new("Folder")
spawn.Name = "Spawn"
local px0, px1 = PLAZA_X - 22, -ROAD_HALF_LENGTH
box(spawn, "PlazaBorder", px0, px1, -0.6, 0.4, -22, 22, STONE_DARK)
box(spawn, "Plaza", px0 + 1.5, px1 - 0.05, -0.55, 0.45, -20.5, 20.5, STONE)
-- Fontaine : bassin, jus, colonne, grosse orange
local fx = PLAZA_X - 4
box(spawn, "BasinFloor", fx - 6, fx + 6, 0.45, 0.8, -6, 6, BASIN)
box(spawn, "BasinNorth", fx - 6.5, fx + 6.5, 0.45, 2.2, 5.5, 6.5, BASIN)
box(spawn, "BasinSouth", fx - 6.5, fx + 6.5, 0.45, 2.2, -6.5, -5.5, BASIN)
box(spawn, "BasinEast", fx + 5.5, fx + 6.5, 0.45, 2.2, -5.5, 5.5, BASIN)
box(spawn, "BasinWest", fx - 6.5, fx - 5.5, 0.45, 2.2, -5.5, 5.5, BASIN)
-- Rebord en cadre (4 bandes) : le jus reste visible
box(spawn, "RimNorth", fx - 6.8, fx + 6.8, 2.2, 2.6, 5.3, 6.8, STONE_DARK)
box(spawn, "RimSouth", fx - 6.8, fx + 6.8, 2.2, 2.6, -6.8, -5.3, STONE_DARK)
box(spawn, "RimEast", fx + 5.3, fx + 6.8, 2.2, 2.6, -5.3, 5.3, STONE_DARK)
box(spawn, "RimWest", fx - 6.8, fx - 5.3, 2.2, 2.6, -5.3, 5.3, STONE_DARK)
box(spawn, "Juice", fx - 5.5, fx + 5.5, 0.8, 1.7, -5.5, 5.5, JUICE, SMOOTH)
box(spawn, "Column", fx - 1, fx + 1, 1.7, 6.5, -1, 1, BASIN)
box(spawn, "ColumnTop", fx - 1.6, fx + 1.6, 6.5, 7.1, -1.6, 1.6, STONE_DARK)
box(spawn, "Orange", fx - 1.4, fx + 1.4, 7.1, 9.9, -1.4, 1.4, Color3.fromRGB(236, 140, 40))
box(spawn, "OrangeLeaf", fx - 0.2, fx + 1.2, 9.9, 10.3, -0.4, 0.4, Color3.fromRGB(90, 150, 62))

-- Joints du dallage (bandes un peu plus hautes) et bacs a fleurs aux coins
for i = 1, 6 do
	local jx = px0 + 1.5 + i * 6
	box(spawn, "JointX", jx - 0.2, jx + 0.2, -0.5, 0.5, -20.5, -7.2, STONE_DARK)
	box(spawn, "JointX", jx - 0.2, jx + 0.2, -0.5, 0.5, 7.2, 20.5, STONE_DARK)
end
for _, jz in { -14, 14 } do
	box(spawn, "JointZ", px0 + 1.5, fx - 7.2, -0.5, 0.48, jz - 0.2, jz + 0.2, STONE_DARK)
	box(spawn, "JointZ", fx + 7.2, px1 - 0.05, -0.5, 0.48, jz - 0.2, jz + 0.2, STONE_DARK)
end
local FLOWER_COLORS = { Color3.fromRGB(226, 120, 150), Color3.fromRGB(246, 236, 220), Color3.fromRGB(240, 204, 84) }
for _, c in { Vector2.new(px0 + 5, -17), Vector2.new(px0 + 5, 17), Vector2.new(px1 - 5, -17), Vector2.new(px1 - 5, 17) } do
	box(spawn, "Planter", c.X - 2, c.X + 2, 0.45, 1.6, c.Y - 2, c.Y + 2, STONE_DARK)
	box(spawn, "PlanterSoil", c.X - 1.6, c.X + 1.6, 1.6, 1.75, c.Y - 1.6, c.Y + 1.6, Color3.fromRGB(116, 84, 58))
	for k = 0, 3 do
		local ox, oz = if k % 2 == 0 then -0.8 else 0.8, if k < 2 then -0.8 else 0.8
		box(spawn, "Flower", c.X + ox - 0.3, c.X + ox + 0.3, 1.75, 2.35, c.Y + oz - 0.3, c.Y + oz + 0.3, FLOWER_COLORS[(k % 3) + 1], { CanCollide = false })
	end
end

local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "SpawnLocation"
spawnLocation.Anchored = true
spawnLocation.Size = Vector3.new(8, 1, 8)
spawnLocation.CFrame = CFrame.new(PLAZA_X + 12, -0.06, 0) -- dessus a 0.44, juste sous le dallage
spawnLocation.Transparency = 1
spawnLocation.CanCollide = false
spawnLocation.CanQuery = false
spawnLocation.CastShadow = false
spawnLocation.Duration = 0 -- pas de bouclier
spawnLocation.Neutral = true
spawnLocation.Parent = spawn
spawn.Parent = map

-- Emplacements des 6 bases. Origine d'une base = bord avant, x local 0 = limite zone 1 / zones 2-3,
-- au niveau du sol ; +Z local = de la route vers le fond. Bases 1-3 au nord, 4-6 en face (180 deg).
local slots = Instance.new("Folder")
slots.Name = "BaseSlots"
for i = 1, 6 do
	local column = (i - 1) % 3
	local cx = (column - 1) * BASE_SPACING
	local cf = if i <= 3
		then CFrame.new(cx - PLOT_CENTER_X, 0, PLOT_FRONT_Z)
		else CFrame.new(cx + PLOT_CENTER_X, 0, -PLOT_FRONT_Z) * CFrame.Angles(0, math.pi, 0)
	part(slots, "BaseSlot" .. i, Vector3.new(2, 1, 2), cf, Color3.new(1, 0, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end
slots.Parent = map

-- Limites invisibles autour du sol
local bounds = Instance.new("Folder")
bounds.Name = "Bounds"
local hx, hz = GROUND_SIZE.X / 2, GROUND_SIZE.Z / 2
part(bounds, "North", Vector3.new(GROUND_SIZE.X, 80, 2), CFrame.new(0, 40, hz + 1), Color3.new(), INVISIBLE)
part(bounds, "South", Vector3.new(GROUND_SIZE.X, 80, 2), CFrame.new(0, 40, -hz - 1), Color3.new(), INVISIBLE)
part(bounds, "East", Vector3.new(2, 80, GROUND_SIZE.Z), CFrame.new(hx + 1, 40, 0), Color3.new(), INVISIBLE)
part(bounds, "West", Vector3.new(2, 80, GROUND_SIZE.Z), CFrame.new(-hx - 1, 40, 0), Color3.new(), INVISIBLE)
bounds.Parent = map

return "Map OK"
