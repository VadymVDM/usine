--!strict
-- Fond de carte, derriere les murs invisibles (v3, 2026-11-27). Demande : "recule les Bounds et
-- ajoute des montagnes, volcan, arbres... dans le theme de Roblox et de notre jeu", decor geant au
-- fond.
--
-- Historique : v1 (blocs empiles a 600-1000 studs, 120-320 de haut) refusee : "moches, trop proches,
-- pas assez grandes". v2 : pics a facettes geants, loin. v3 = v2 + ce qui manquait entre les murs et
-- les montagnes, + la touche fruitee (au choix).
--
-- Trois plans, du plus pres au plus loin (zone jouable : 1380 x 1060, 01-ground-road) :
--   1. Crete : talus en gradins a studs (meme style que les collines) juste derriere les murs,
--      170 studs de profondeur, 10 a 55 de haut, avec quelques falaises grises. Elle montre la
--      limite (on est dans une vallee) et cache l'horizon plat. Grands arbres dessus et derriere.
--      Rocher de la cascade au nord (x 100), bassin a cheval sur le mur.
--   2. Montagnes : pics a facettes (4 CornerWedgeParts par pyramide), neige, pied vert, en deux
--      anneaux (1500 et 2150 studs), 480 a 1100 de haut.
--   3. Volcan au nord-ouest (tronc de pyramide), 660 de haut.
-- Deux reglages (2026-11-27, choix de l'utilisateur apres l'echantillon : "garde le volcan fruits
-- et pour le reste garde le naturel") :
--   FRUITY_VOLCANO = true  : volcan de jus (coulees orange / fraise / raisin / citron vert /
--                            citron, brume orangee) qui crache 5 fruits du jeu en geant
--                            (ReplicatedStorage.FruitAssets agrandis : 1 piece par fruit).
--                    false : lave et fumee grise.
--   FRUITY_REST    = false : naturel. Cascade d'eau, gros rochers comme reperes dans la foret.
--                    true  : cascade de jus + paille + glacons, fruits geants sur la crete, au pied
--                            des montagnes et dans la foret.
-- Tout ce qui depend de ces reglages est dans le modele Backdrop.Details.
--
-- Leger : tout est Anchored, sans collision / requete / toucher / ombre (sauf la rive du bassin et
-- les 2 reperes de la foret, ou l'on marche). Modeles "Persistent" : toujours envoyes au client
-- meme loin du joueur (StreamingEnabled, rayon 1024), sinon le fond disparaitrait.
-- Low Quality (SettingsController) eteint deja les particules (fumee, ecume).
-- Relancable : detruit et recree Workspace.Map.Backdrop (et l'ancien Map.Mountains).
-- SAMPLE_NORTH = true : echantillon, seulement le cote nord (meme tirage que la version complete).
-- Doc : docs/systems/carte-bases.md (section Alentours et fond de carte)

local SAMPLE_NORTH = false
local FRUITY_VOLCANO = true
local FRUITY_REST = false

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZONE_HX, ZONE_HZ = 690, 530 -- murs invisibles (01-ground-road : GROUND_SIZE / 2)
local SAMPLE_Z = 300
local RIDGE_DEPTH = 175

local RIDGE = { Color3.fromRGB(64, 160, 58), Color3.fromRGB(70, 166, 62), Color3.fromRGB(78, 174, 66) }
local CLIFF = { Color3.fromRGB(140, 142, 148), Color3.fromRGB(122, 124, 132) }
local TRUNK = Color3.fromRGB(112, 78, 52)
local LEAVES = { Color3.fromRGB(46, 160, 52), Color3.fromRGB(58, 176, 58), Color3.fromRGB(74, 190, 64) }
local PINE = { Color3.fromRGB(36, 140, 70), Color3.fromRGB(44, 154, 76), Color3.fromRGB(54, 166, 80) }
local FOOT = { Color3.fromRGB(62, 140, 60), Color3.fromRGB(74, 150, 64) }
local ROCK = { Color3.fromRGB(112, 116, 134), Color3.fromRGB(96, 100, 120), Color3.fromRGB(128, 128, 142) }
local SNOW = Color3.fromRGB(246, 249, 255)
local VOLCANO = { Color3.fromRGB(58, 44, 44), Color3.fromRGB(44, 34, 36) }
local LAVA = Color3.fromRGB(255, 96, 24)
local LAVA_HOT = Color3.fromRGB(255, 170, 46)
local SAND = Color3.fromRGB(226, 208, 160)
local WATER = Color3.fromRGB(86, 176, 232)
local JUICE = Color3.fromRGB(255, 116, 10) -- Neon : plus fonce que le jus de la fontaine, sinon il vire au jaune
local JUICES = {
	Color3.fromRGB(255, 112, 8), -- orange
	Color3.fromRGB(255, 84, 128), -- fraise
	Color3.fromRGB(168, 92, 240), -- raisin
	Color3.fromRGB(150, 232, 60), -- citron vert
	Color3.fromRGB(255, 224, 60), -- citron
}

local STUDS = Enum.SurfaceType.Studs
local UNIVERSAL = Enum.SurfaceType.Universal

local rng = Random.new(7)

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
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

-- Boite alignee sur le monde, du sol (y0) au dessus (y1)
local function box(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, surface: Enum.SurfaceType?, material: Enum.Material?): BasePart
	return make("Part", parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, surface, material)
end

local function newModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return m
end

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

local map = workspace:FindFirstChild("Map")
assert(map, "Lancer 01 d'abord")
for _, name in { "Backdrop", "Mountains" } do
	local old = map:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
local root = Instance.new("Folder")
root.Name = "Backdrop"
root.Parent = map

-- Echantillon : on construit tout (meme tirage), on ne garde que le nord.
local function keep(z: number): boolean
	return not SAMPLE_NORTH or z >= SAMPLE_Z
end
local function finish(m: Instance, z: number, parent: Instance?)
	if keep(z) then
		m.Parent = parent or root
	else
		m:Destroy()
	end
end

---------------------------------------------------------------------------------------------
-- 1. Crete en gradins + grands arbres

-- Un cote : `a` = position le long du mur, `o` = distance derriere le mur
type Side = { name: string, a0: number, a1: number, z: number, world: (a: number, o: number) -> (number, number) }
local SIDES: { Side } = {
	{ name = "North", a0 = -ZONE_HX - 170, a1 = ZONE_HX + 170, z = ZONE_HZ, world = function(a, o)
		return a, ZONE_HZ + o
	end },
	{ name = "South", a0 = -ZONE_HX - 170, a1 = ZONE_HX + 170, z = -ZONE_HZ, world = function(a, o)
		return a, -ZONE_HZ - o
	end },
	{ name = "East", a0 = -ZONE_HZ, a1 = ZONE_HZ, z = 0, world = function(a, o)
		return ZONE_HX + o, a
	end },
	{ name = "West", a0 = -ZONE_HZ, a1 = ZONE_HZ, z = 0, world = function(a, o)
		return -ZONE_HX - o, a
	end },
}

-- Dessus des blocs de la crete : sert a poser arbres et fruits a la bonne hauteur
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
-- Hauteur du sol sous un objet large : le plus bas autour (le pied s'enfonce au lieu de flotter)
local function groundAt(x: number, z: number, r: number): number
	return math.min(topAt(x, z), topAt(x - r, z), topAt(x + r, z), topAt(x, z - r), topAt(x, z + r))
end

local function slab(parent: Instance, side: Side, name: string, aA: number, aB: number, oA: number, oB: number, top: number, color: Color3, record: boolean)
	local xa, za = side.world(aA, oA)
	local xb, zb = side.world(aB, oB)
	local x0, x1 = math.min(xa, xb), math.max(xa, xb)
	local z0, z1 = math.min(za, zb), math.max(za, zb)
	box(parent, name, x0, x1, -1, top, z0, z1, color, STUDS)
	if record then
		table.insert(blocks, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, top = top })
	end
end

-- Rocher de la cascade (nord) : la crete le contourne, les arbres l'evitent
local CASCADE_X = 100
local function nearCascade(x: number, z: number): boolean
	return math.abs(x - CASCADE_X) < 70 and z > ZONE_HZ and z < ZONE_HZ + 95
end

local function ridge(side: Side): Model
	local m = newModel("Ridge" .. side.name)
	local a = side.a0
	local index = 0
	while a < side.a1 do
		index += 1
		-- fond decale d'un troncon a l'autre : deux troncons voisins se chevauchent, leurs faces
		-- arriere ne doivent pas tomber dans le meme plan (z-fighting vu par check-zfighting)
		local back = RIDGE_DEPTH + (index % 4) * 1.3
		local b = math.min(a + rng:NextNumber(90, 150), side.a1)
		local front = rng:NextNumber(5, 15)
		local h1 = rng:NextNumber(10, 16)
		local d1 = rng:NextNumber(24, 38)
		local h2 = h1 + rng:NextNumber(11, 18)
		local d2 = rng:NextNumber(26, 42)
		local h3 = h2 + rng:NextNumber(12, 22)
		local has3 = rng:NextNumber() < 0.7
		local cliff = rng:NextNumber() < 0.45
		local in2a, in2b = rng:NextNumber(0, 14), rng:NextNumber(0, 14)
		local in3a, in3b = rng:NextNumber(8, 30), rng:NextNumber(8, 30)
		local drop = rng:NextNumber(2, 5)
		slab(m, side, "Tier1", a, b, front, back, h1, pick(RIDGE), true)
		slab(m, side, "Tier2", a + in2a, b - in2b, front + d1, back + 6, h2, pick(RIDGE), true)
		if has3 then
			slab(m, side, "Tier3", a + in3a, b - in3b, front + d1 + d2, back + 12, h3, pick(RIDGE), true)
		end
		if cliff then
			-- falaise grise devant le 2e gradin
			slab(m, side, "Cliff", a + in2a + 6, b - in2b - 6, front + d1 - 2.5, front + d1 + 3, h2 - drop, pick(CLIFF), false)
		end
		if b >= side.a1 then
			break
		end
		a = b - rng:NextNumber(3, 9)
	end
	return m
end

-- Grand arbre du fond : 3 ou 4 pieces, pas de collision
local function farTree(parent: Instance, isPine: boolean, x: number, y: number, z: number, s: number, rot: number)
	if isPine then
		make("Part", parent, "Trunk", Vector3.new(1.6, 4, 1.6) * s, CFrame.new(x, y + 2 * s, z) * yaw(rot), TRUNK, STUDS)
		make("Part", parent, "Leaves", Vector3.new(7, 4, 7) * s, CFrame.new(x, y + 6 * s, z) * yaw(rot + 15), PINE[1], UNIVERSAL)
		make("Part", parent, "Leaves", Vector3.new(5.2, 3.5, 5.2) * s, CFrame.new(x, y + 9.6 * s, z) * yaw(rot + 35), PINE[2], UNIVERSAL)
		make("Part", parent, "Leaves", Vector3.new(3.2, 3.4, 3.2) * s, CFrame.new(x, y + 12.9 * s, z) * yaw(rot + 5), PINE[3], UNIVERSAL)
	else
		make("Part", parent, "Trunk", Vector3.new(1.8, 6, 1.8) * s, CFrame.new(x, y + 3 * s, z) * yaw(rot), TRUNK, STUDS)
		make("Part", parent, "Leaves", Vector3.new(8, 5, 8) * s, CFrame.new(x, y + 8 * s, z) * yaw(rot + 10), LEAVES[1], UNIVERSAL)
		make("Part", parent, "Leaves", Vector3.new(5.5, 3.5, 5.5) * s, CFrame.new(x + 0.6 * s, y + 11.6 * s, z - 0.4 * s) * yaw(rot + 35), LEAVES[2], UNIVERSAL)
	end
end

local function farForest(m: Model, side: Side)
	local a = side.a0 + 10
	while a < side.a1 - 10 do
		local o = if rng:NextNumber() < 0.62 then rng:NextNumber(14, RIDGE_DEPTH - 14) else rng:NextNumber(RIDGE_DEPTH + 12, RIDGE_DEPTH + 100)
		local s = rng:NextNumber(2.2, 3.8)
		local isPine = rng:NextNumber() < 0.5
		local rot = rng:NextNumber(0, 90)
		local x, z = side.world(a, o)
		if not nearCascade(x, z) then
			farTree(m, isPine, x, groundAt(x, z, 5) - 0.6, z, s, rot)
		end
		a += rng:NextNumber(22, 36)
	end
end

-- Rocher de la cascade (commun aux deux variantes) + rive du bassin (dans la zone : on marche dessus)
local function cascadeRock(m: Model)
	local z = ZONE_HZ
	local function rock(x0: number, x1: number, z0: number, z1: number, top: number, color: Color3)
		box(m, "CascadeRock", x0, x1, -1, top, z + z0, z + z1, color, STUDS)
		table.insert(blocks, { x0 = x0, x1 = x1, z0 = z + z0, z1 = z + z1, top = top })
	end
	-- chaque bloc de roche porte un chapeau d'herbe (2.2 studs) : on lit une falaise, pas un mur
	local function rock(x0: number, x1: number, z0: number, z1: number, top: number, color: Color3)
		box(m, "CascadeRock", x0, x1, -1, top - 2.2, z + z0, z + z1, color, STUDS)
		box(m, "CascadeGrass", x0 - 0.6, x1 + 0.6, top - 2.2, top, z + z0 - 0.6, z + z1 + 0.6, pick(RIDGE), STUDS)
		table.insert(blocks, { x0 = x0, x1 = x1, z0 = z + z0, z1 = z + z1, top = top })
	end
	rock(CASCADE_X - 30, CASCADE_X + 30, 11, 75, 62, CLIFF[1])
	rock(CASCADE_X - 20, CASCADE_X + 20, 22, 78, 84, CLIFF[2])
	rock(CASCADE_X - 50, CASCADE_X - 22, 16, 66, 44, CLIFF[2])
	rock(CASCADE_X + 24, CASCADE_X + 48, 18, 70, 35, CLIFF[1])
	rock(CASCADE_X - 62, CASCADE_X - 40, 13, 52, 22, CLIFF[1])
	rock(CASCADE_X + 38, CASCADE_X + 60, 14, 56, 18, CLIFF[2])
	-- eboulis au pied (dans la zone : on peut monter dessus)
	for _, r in { { -31, 2, 7, 6 }, { -24, 6, 4.5, 3.5 }, { 30, 3, 6, 5 }, { 25, 7, 3.6, 2.6 } } do
		local stone = make("Part", m, "CascadeStone", Vector3.new(r[3] * 1.3, r[4], r[3]), CFrame.new(CASCADE_X + r[1], r[4] / 2 - 0.3, z + r[2]) * yaw(rng:NextNumber(0, 90)), pick(CLIFF), STUDS)
		stone.CanCollide = true
	end
	local sand = box(m, "CascadeSand", CASCADE_X - 40, CASCADE_X + 40, -0.3, 0.3, z - 44, z + 11, SAND, STUDS)
	sand.CanCollide = true
end

local ridgeModels: { [string]: Model } = {}
for _, side in SIDES do
	local m = ridge(side)
	if side.name == "North" then
		cascadeRock(m)
	end
	farForest(m, side)
	-- Coins : la crete est / ouest s'arrete a z +-530 et la crete nord / sud commence 5 a 15 studs
	-- plus loin. Deux blocs fixes bouchent la fente (pas de tirage : le reste ne bouge pas).
	if side.name == "East" or side.name == "West" then
		for _, corner in { side.a0, side.a1 } do
			local out = math.sign(corner)
			slab(m, side, "Corner", corner - 4, corner + 4, 5, RIDGE_DEPTH, 13.2, RIDGE[2], false)
			slab(m, side, "Corner", corner + out * 2, corner + out * 18, 5.5, RIDGE_DEPTH - 1, 12.6, RIDGE[3], false)
		end
	end
	ridgeModels[side.name] = m
	if SAMPLE_NORTH and side.name ~= "North" then
		m:Destroy()
	else
		m.Parent = root
	end
	task.wait()
end

---------------------------------------------------------------------------------------------
-- 2. Montagnes a facettes

-- Coin "haut" d'une CornerWedgePart en repere local : (+X, -Z). On tourne chaque quart pour que ce
-- coin pointe vers le centre de la pyramide.
local QUARTERS = { 0, 90, 180, 270 }

-- Pyramide a facettes : base w x d posee a y = y0 (repere `frame`), sommet a y0 + h.
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

-- Montagne : pied vert, pic principal, 2 pics secondaires, neige sur les pics assez hauts.
local function mountain(cx: number, cz: number, w: number, h: number)
	local m = newModel("Mountain")
	local frame = CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0)
	local rock = pick(ROCK)
	-- pied : large et bas (foret au loin)
	pyramid(m, "Foot", frame, w * 1.35, w * 1.2, h * 0.22, -2, pick(FOOT))
	-- pics : { decalage x, decalage z, largeur, hauteur } relatifs
	local peaks = {
		{ 0, 0, 1, 1 },
		{ rng:NextNumber(0.3, 0.42), rng:NextNumber(-0.15, 0.15), rng:NextNumber(0.55, 0.7), rng:NextNumber(0.55, 0.72) },
		{ -rng:NextNumber(0.3, 0.42), rng:NextNumber(-0.15, 0.15), rng:NextNumber(0.5, 0.62), rng:NextNumber(0.45, 0.62) },
	}
	for i, p in peaks do
		local pf = frame * CFrame.new(p[1] * w, 0, p[2] * w)
		local pw, pd, ph = w * p[3], w * p[3] * rng:NextNumber(0.85, 1), h * p[4]
		pyramid(m, "Peak" .. i, pf, pw, pd, ph, -2, if i == 1 then rock else pick(ROCK))
		-- neige : meme pente, legerement au-dessus de la roche (pas de z-fighting)
		if ph > 400 then
			local f = 0.32
			local lift = ph * 0.012
			pyramid(m, "Snow" .. i, pf, pw * f, pd * f, ph * f, ph - 2 - ph * f + lift, SNOW)
		end
	end
	finish(m, cz)
end

-- Volcan au nord-ouest, visible depuis le spawn (x -340) et les bases du nord. Repere local :
-- -Z regarde le centre de la carte (les coulees sont du cote des joueurs).
local VOLCANO_POS = Vector2.new(-900, 1700)
local V_W, V_T, V_H = 1150, 260, 660 -- base, sommet plat, hauteur
local V_FRAME = CFrame.lookAt(Vector3.new(VOLCANO_POS.X, 0, VOLCANO_POS.Y), Vector3.new(0, 0, 0))
local V_SLOPE = (V_W - V_T) / 2
local V_TOP = V_H - 2

do
	local m = newModel("Volcano")
	local t, h, s, y0 = V_T, V_H, V_SLOPE, -2
	make("Part", m, "Core", Vector3.new(t, h, t), V_FRAME * CFrame.new(0, y0 + h / 2, 0), VOLCANO[1])
	-- 4 pentes (WedgePart : cote haut en +Z local)
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local outward = -rot:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local pos = outward * (t / 2 + s / 2) + Vector3.new(0, y0 + h / 2, 0)
		make("WedgePart", m, "Slope", Vector3.new(t, h, s), V_FRAME * CFrame.new(pos) * rot, VOLCANO[1])
	end
	-- 4 coins (CornerWedgePart, coin haut vers le centre)
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local apex = rot:VectorToWorldSpace(Vector3.new(1, 0, -1))
		local pos = Vector3.new(-math.sign(apex.X) * (t / 2 + s / 2), y0 + h / 2, -math.sign(apex.Z) * (t / 2 + s / 2))
		make("CornerWedgePart", m, "Corner", Vector3.new(s, h, s), V_FRAME * CFrame.new(pos) * rot, VOLCANO[2])
	end
	-- rebord du cratere
	make("Part", m, "Rim", Vector3.new(t * 0.92, 10, t * 0.92), V_FRAME * CFrame.new(0, V_TOP + 5, 0), VOLCANO[2])
	finish(m, VOLCANO_POS.Y)
end

-- Deux rangees en anneau (ellipse) : devant plus basses, derriere plus grandes.
local function ring(rx: number, rz: number, count: number, wMin: number, wMax: number, hMin: number, hMax: number, phase: number)
	for i = 0, count - 1 do
		local a = (i + phase + rng:NextNumber(-0.18, 0.18)) / count * math.pi * 2
		local x, z = math.cos(a) * rx, math.sin(a) * rz
		local w, h = rng:NextNumber(wMin, wMax), rng:NextNumber(hMin, hMax)
		if (Vector2.new(x, z) - VOLCANO_POS).Magnitude > 760 then
			mountain(x, z, w, h)
		end
	end
	task.wait()
end
ring(1500, 1330, 14, 650, 900, 480, 720, 0)
ring(2150, 1950, 12, 900, 1200, 800, 1100, 0.5)

---------------------------------------------------------------------------------------------
-- 3. Details selon les reglages (volcan, cascade, reperes)

-- Lac du cratere, coulees et fumee. `flows` : une couleur par coulee (5).
local function volcanoLiquids(m: Model, pool: Color3, flows: { Color3 }, smokeA: Color3, smokeB: Color3)
	local t, s, h = V_T, V_SLOPE, V_H
	local top, y0 = V_TOP, -2
	make("Part", m, "Pool", Vector3.new(t * 0.7, 10, t * 0.7), V_FRAME * CFrame.new(0, top + 6, 0), pool, nil, Enum.Material.Neon)
	local index = 0
	local function flow(rotDeg: number, x: number, widthStud: number, frac: number)
		index += 1
		local rot = V_FRAME * CFrame.Angles(0, math.rad(rotDeg), 0)
		-- dans ce repere, la pente descend vers -Z : du haut (z = -t/2, y = top) au bas (z = -(t/2+s), y = y0)
		local up = Vector3.new(0, top, -t / 2)
		local down = Vector3.new(0, y0, -(t / 2 + s))
		local finishPoint = up:Lerp(down, frac)
		local normal = Vector3.new(0, s, -h).Unit
		local a = Vector3.new(x, up.Y, up.Z) + normal * 1.5
		local b = Vector3.new(x, finishPoint.Y, finishPoint.Z) + normal * 1.5
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b, normal)
		make("Part", m, "Flow", Vector3.new(widthStud, 3, len + 4), rot * cf, flows[index], nil, Enum.Material.Neon)
	end
	flow(0, -t * 0.18, 30, 0.85)
	flow(0, t * 0.24, 22, 0.6)
	flow(0, t * 0.03, 18, 0.42)
	flow(90, t * 0.1, 26, 0.7)
	flow(-90, -t * 0.12, 24, 0.55)

	-- Fumee : un seul emetteur, peu de particules, grosses et lentes ; opaque car la brume de
	-- l'Atmosphere eclaircit tout ce qui est loin
	local source = make("Part", m, "SmokeSource", Vector3.new(4, 4, 4), V_FRAME * CFrame.new(0, top + 20, 0), pool)
	source.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(smokeA, smokeB)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 140), NumberSequenceKeypoint.new(1, 420) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(18, 24)
	smoke.Rate = 1.2
	smoke.Speed = NumberRange.new(25, 35)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Acceleration = Vector3.new(4, 1, 2)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-6, 6)
	smoke.LightInfluence = 0.3
	smoke.Parent = source
end

-- Cascade en 2 chutes sur le rocher du nord + bassin (liquide sans collision) + ecume
-- `material` : Neon pour le jus (couleur vive meme a l'ombre), rien pour l'eau.
local function cascadeLiquid(m: Model, color: Color3, foam: Color3, material: Enum.Material?)
	local z = ZONE_HZ
	local x = CASCADE_X
	box(m, "PoolTop", x - 11, x + 11, 83.6, 84.6, z + 22.5, z + 50, color, nil, material)
	box(m, "Fall2", x - 9, x + 9, 62.3, 84.6, z + 20, z + 23, color, nil, material)
	box(m, "PoolMid", x - 15, x + 15, 61.7, 62.6, z + 11.5, z + 23, color, nil, material)
	box(m, "Fall1", x - 13, x + 13, 0.4, 62.6, z + 9, z + 12, color, nil, material)
	box(m, "Basin", x - 35, x + 35, 0, 0.55, z - 39, z + 10.5, color, nil, material)
	local source = box(m, "FoamSource", x - 13, x + 13, 0.6, 1.6, z + 6, z + 9, foam)
	source.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Name = "Foam"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(foam)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.2, 1.9)
	e.Rate = 7
	e.Speed = NumberRange.new(4, 8)
	e.SpreadAngle = Vector2.new(50, 50)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -5, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 0.6
	e.Parent = source
end

-- Fruit du jeu en geant : 1 seule piece (UnionOperation de ReplicatedStorage.FruitAssets agrandie).
-- `solid` : boite de collision invisible (reperes de la foret, ou l'on marche).
local fruitAssets = ReplicatedStorage:FindFirstChild("FruitAssets")
local missingFruits = 0
local function giantFruit(parent: Instance, id: string, x: number, baseY: number, z: number, height: number, rotDeg: number, tilt: CFrame?, solid: boolean?)
	local source = fruitAssets and fruitAssets:FindFirstChild(id)
	if not source or not source:IsA("BasePart") then
		missingFruits += 1
		return
	end
	local f = source:Clone()
	f.Name = "Giant" .. id
	for _, child in f:GetChildren() do
		child:Destroy()
	end
	for _, tag in f:GetTags() do
		f:RemoveTag(tag)
	end
	f.Size = f.Size * (height / f.Size.Y)
	f.Anchored = true
	f.CanCollide = false
	f.CanQuery = false
	f.CanTouch = false
	f.CastShadow = false
	f.CFrame = CFrame.new(x, baseY + f.Size.Y * 0.46, z) * yaw(rotDeg) * (tilt or CFrame.new())
	f.Parent = parent
	if solid then
		local c = make("Part", parent, "FruitCollider", f.Size * 0.72, CFrame.new(x, baseY + f.Size.Y * 0.4, z) * yaw(rotDeg), Color3.new(1, 1, 1))
		c.Transparency = 1
		c.CanCollide = true
	end
end

-- Reperes dans la foret (places reservees dans 03-decor)
local LANDMARKS = { Vector3.new(-520, 0, 380), Vector3.new(520, 0, -380) }

local details = newModel("Details")

-- Volcan
if keep(VOLCANO_POS.Y) then
	if FRUITY_VOLCANO then
		volcanoLiquids(details, JUICE, JUICES, Color3.fromRGB(255, 190, 140), Color3.fromRGB(255, 236, 220))
		-- le volcan crache des fruits, en eventail au-dessus du cratere :
		-- { fruit, x local, hauteur au-dessus du cratere, z local, taille }
		local erupted = {
			{ "Orange", -330, 70, -150, 120 },
			{ "Strawberry", -170, 250, -70, 105 },
			{ "Grape", 10, 340, -20, 115 },
			{ "Lemon", 190, 240, -80, 95 },
			{ "Apple", 350, 60, -160, 110 },
		}
		for i, f in erupted do
			local p = (V_FRAME * CFrame.new(f[2] :: number, V_TOP + (f[3] :: number), f[4] :: number)).Position
			giantFruit(details, f[1] :: string, p.X, p.Y, p.Z, f[5] :: number, i * 50, CFrame.Angles(math.rad(-30 + i * 14), 0, math.rad(40 - i * 16)))
		end
	else
		volcanoLiquids(details, LAVA_HOT, { LAVA, LAVA, LAVA, LAVA, LAVA }, Color3.fromRGB(62, 58, 58), Color3.fromRGB(120, 118, 120))
	end
end

-- Cascade, reperes de la foret, fruits geants
if FRUITY_REST then
	cascadeLiquid(details, JUICE, Color3.fromRGB(255, 226, 180), Enum.Material.Neon)
	-- paille geante et glacons dans le bassin de jus
	do
		local z = ZONE_HZ
		local straw = CFrame.new(CASCADE_X + 20, 14, z - 16) * CFrame.Angles(0, math.rad(25), math.rad(66))
		local s = make("Part", details, "Straw", Vector3.new(40, 4.2, 4.2), straw, Color3.fromRGB(255, 104, 150)) :: Part
		s.Shape = Enum.PartType.Cylinder
		for i = -1, 1 do
			local band = make("Part", details, "StrawBand", Vector3.new(3, 4.5, 4.5), straw * CFrame.new(i * 11, 0, 0), Color3.fromRGB(250, 250, 250)) :: Part
			band.Shape = Enum.PartType.Cylinder
		end
		for _, c in { CFrame.new(CASCADE_X - 14, 1.4, z - 20) * CFrame.Angles(0.3, 0.6, 0.2), CFrame.new(CASCADE_X - 4, 1.1, z - 30) * CFrame.Angles(-0.2, 1.1, 0.35) } do
			local ice = make("Part", details, "IceCube", Vector3.new(5.5, 5.5, 5.5), c, Color3.fromRGB(214, 240, 255))
			ice.Transparency = 0.25
		end
	end
	-- fruits geants : { nom, x, z, hauteur, rotation }. Sur la crete (hauteur du sol lue), sauf
	-- les 2 reperes de la foret (solides) et ceux poses au pied des montagnes.
	local onRidge = {
		{ "Orange", -390, 612, 74, 20 },
		{ "Watermelon", 345, 618, 62, -30 },
		{ "Pineapple", -110, 648, 98, 10 },
		{ "Peach", 62, 566, 46, 40 },
		{ "Apple", 250, -610, 72, 15 },
		{ "Banana", -300, -612, 52, 200 },
		{ "Strawberry", 30, -645, 78, 180 },
		{ "Grape", 765, 190, 84, -80 },
		{ "Lemon", 772, -220, 54, -100 },
		{ "Pear", -768, -170, 88, 95 },
		{ "Cherry", -772, 245, 84, 80 },
	}
	for _, f in onRidge do
		local id, x, z, height, rot = f[1] :: string, f[2] :: number, f[3] :: number, f[4] :: number, f[5] :: number
		if keep(z) then
			giantFruit(details, id, x, groundAt(x, z, height * 0.15), z, height, rot)
		end
	end
	local atFeet = {
		{ "Melon", 520, 1040, 190, 30 },
		{ "DragonFruit", 1090, 620, 180, -60 },
		{ "Coconut", -1080, -760, 170, 100 },
		{ "Mango", 300, -1020, 150, 200 },
	}
	for _, f in atFeet do
		local id, x, z, height, rot = f[1] :: string, f[2] :: number, f[3] :: number, f[4] :: number, f[5] :: number
		if keep(z) then
			giantFruit(details, id, x, 0, z, height, rot)
		end
	end
	if keep(LANDMARKS[1].Z) then
		giantFruit(details, "Orange", LANDMARKS[1].X, 0, LANDMARKS[1].Z, 26, 30, nil, true)
	end
	if keep(LANDMARKS[2].Z) then
		giantFruit(details, "Pineapple", LANDMARKS[2].X, 0, LANDMARKS[2].Z, 34, -20, nil, true)
	end
else
	cascadeLiquid(details, WATER, Color3.fromRGB(240, 248, 255))
	-- gros rochers comme reperes dans la foret (on peut monter dessus)
	for _, p in LANDMARKS do
		if keep(p.Z) then
			local b1 = box(details, "Boulder", p.X - 9, p.X + 9, -1, 13, p.Z - 8, p.Z + 8, CLIFF[1], STUDS)
			local b2 = box(details, "Boulder", p.X - 3, p.X + 12, -1, 7.5, p.Z + 3, p.Z + 14, CLIFF[2], STUDS)
			local b3 = box(details, "Boulder", p.X - 6, p.X + 4, 13, 19, p.Z - 5, p.Z + 4, CLIFF[2], STUDS)
			for _, b in { b1, b2, b3 } do
				b.CanCollide = true
			end
		end
	end
end
details.Parent = root

-- Reserve de l'echantillon (les deux variantes cote a cote) : plus utilisee
local variants = ServerStorage:FindFirstChild("MapVariants")
if variants then
	variants:Destroy()
end

local lines = {}
local total = 0
for _, child in root:GetChildren() do
	local n = 0
	for _, d in child:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	total += n
end
table.insert(lines, ("Backdrop%s : %d modeles, %d pieces, volcan %s, reste %s"):format(if SAMPLE_NORTH then " (echantillon nord)" else "", #root:GetChildren(), total, if FRUITY_VOLCANO then "fruite" else "lave", if FRUITY_REST then "fruite" else "naturel"))
if missingFruits > 0 then
	table.insert(lines, missingFruits .. " fruit(s) geant(s) introuvable(s) dans ReplicatedStorage.FruitAssets")
end
return table.concat(lines, "\n")
