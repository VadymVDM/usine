--!strict
-- Construit l'arbre d'un etage pour un niveau (serveur, appele par TreeService). Donnees et regles :
-- Config/Tree (taille par palier, theme de chaque etage, niveau ou chaque partie change de theme).
-- Le modele rendu s'appelle "Body", son pivot est le pied du tronc (CFrame.identity) : TreeService le
-- pose sur Tree.TreeRoot. Avant (2026-11-20 et avant) : 5 modeles ServerStorage.TreeStages agrandis.
-- Regles :
--   * aucune piece en forme de fruit (les joueurs essayaient de les ramasser) ;
--   * rien ne bloque ni ne touche : CanCollide / CanTouch / CanQuery = false (on traverse l'arbre,
--     le rayon de chute des fruits ne s'arrete pas dessus) ;
--   * feuillage marque Leaf = true (animation TreeFxController) ;
--   * meme palier = meme arbre, au stud pres (pas de hasard : petites variations calculees).
-- Repere : y = hauteur au-dessus de l'herbe, l'avant de l'arbre (vers l'entree) est -Z.
-- Doc : docs/systems/fruits.md (section Arbre qui grandit)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tree"))

type Theme = TreeConfig.Theme
type Growth = TreeConfig.Growth

export type Metrics = {
	tier: number, -- palier (1..TreeConfig.MaxTier())
	dropRadius: number, -- studs : les fruits tombent dans ce rayon autour du tronc
	fallHeight: number, -- studs : hauteur d'ou tombe un fruit (bas du feuillage)
	labelHeight: number, -- studs : hauteur du texte "Tree full!" / nom de l'arbre
	trunkClear: number, -- studs : pas de fruit plus pres du centre du tronc
	height: number, -- studs : haut de l'arbre (couronne comprise)
}

type Layer = { y: number, h: number, w: number }

local TreeBuilder = {}

local PLASTIC = Enum.Material.Plastic
-- Accents (ornements, couronne, anneaux, veines) : plastique lisse un peu reflechissant. JAMAIS de
-- Neon (utilisateur, 2026-11-20 : "pas de neon, c'est moche") ; l'eclat vient des effets (aura).
local SHINY = Enum.Material.SmoothPlastic
local SHINE = 0.25 -- Reflectance des accents
local GLASS = Enum.Material.Glass
local STUDS = Enum.SurfaceType.Studs
local INLET = Enum.SurfaceType.Inlet
local SMOOTH = Enum.SurfaceType.Smooth
local CYLINDER = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball

local WOOD = Color3.fromRGB(205, 160, 108)
local SOIL = Color3.fromRGB(116, 84, 58)
local ROPE = Color3.fromRGB(230, 215, 170)
local STEM = Color3.fromRGB(92, 64, 42)
local HIVE = { Color3.fromRGB(255, 196, 60), Color3.fromRGB(240, 165, 40) }
local DARK = Color3.fromRGB(30, 22, 18)
local RED = Color3.fromRGB(215, 60, 55)

-- Forme du feuillage selon le nombre d'etages : { largeur relative, hauteur relative } par bloc,
-- du bas vers le haut. Les blocs se chevauchent (OVERLAP) puis tout est mis a la hauteur `canopy`.
local LAYER_SHAPES = {
	{ { 1.0, 0.62 }, { 0.6, 0.42 } },
	{ { 1.0, 0.46 }, { 0.72, 0.36 }, { 0.42, 0.26 } },
	{ { 1.0, 0.38 }, { 0.76, 0.3 }, { 0.52, 0.24 }, { 0.3, 0.18 } },
}
local OVERLAP = 0.72
local ORNAMENTS = 8 -- ornements dans le feuillage
local ORNAMENT_SCALE = 1.7 -- taille des ornements (1 = trop petits : on ne les voyait pas de loin)
local HALO_PIECES = 16 -- blocs du grand anneau
local CROWN_HEIGHT = 4 -- hauteur d'une couronne a la taille 1 (pour rester sous MaxHeight)
local CROWN_SCALE = 1.6 -- taille voulue des couronnes (reduite si l'arbre est trop haut)

local current: Model? = nil -- modele en construction

-- Piece de l'arbre : ancree, sans collision ni requete, studs sur le plastique (style du jeu).
local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	local mat = material or PLASTIC
	p.Material = mat
	if mat == PLASTIC then
		p.TopSurface = STUDS
		p.BottomSurface = INLET
		p.FrontSurface = STUDS
		p.BackSurface = STUDS
		p.LeftSurface = STUDS
		p.RightSurface = STUDS
	else
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
	end
	if mat == SHINY then
		p.Reflectance = SHINE
	end
	if size.X < 1 and size.Y < 1 and size.Z < 1 then
		p.CastShadow = false
	end
	p.Parent = current
	return p
end

local function shaped(shape: Enum.PartType, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(name, size, cf, color, material)
	p.Shape = shape
	return p
end

-- Nombre "au hasard" mais toujours le meme pour (i, salt) : 0..1.
local function hash(i: number, salt: number): number
	local x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function color(list: { Color3 }?, i: number, fallback: Color3): Color3
	if list == nil or #list == 0 then
		return fallback
	end
	return list[((i - 1) % #list) + 1]
end

-- Cylindre dont l'axe (X de la piece) pointe vers l'avant (-Z) du repere `cf` : disque face a `cf`.
local FACE = CFrame.Angles(0, math.pi / 2, 0)

---------------------------------------------------------------------------------------------
-- Tronc, branches, racines

type Trunk = { top: number, segments: { { cf: CFrame, w: number, h: number } } }

local function buildTrunk(g: Growth, canopyBottom: number, theme: Theme): Trunk
	local top = canopyBottom + g.canopy * 0.35 -- le tronc entre dans le feuillage
	local W = g.width
	local plan = if g.layers <= 1 and g.roots <= 2
		then { { 1, 1, 6 } }
		else { { 0.45, 1, 0 }, { 0.33, 0.84, 12 }, { 0.22, 0.68, -7 } }
	local trunk: Trunk = { top = top, segments = {} }
	local y = 0
	for i, s in plan do
		local h = top * s[1]
		local w = W * s[2]
		local cf = CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, math.rad(s[3]), 0)
		local c = if i == #plan and #plan > 1 then theme.trunkDark else theme.trunk
		part(if i == 1 then "Trunk" else "TrunkPart", Vector3.new(w, h + 0.2, w), cf, c, theme.trunkMaterial)
		table.insert(trunk.segments, { cf = cf, w = w, h = h })
		if g.bark and i < #plan then
			part("Bark", Vector3.new(w * 1.08, 0.6, w * 1.08), CFrame.new(0, y + h, 0) * CFrame.Angles(0, math.rad(s[3]), 0), theme.band, theme.trunkMaterial)
		end
		y += h
	end
	-- Branches : partent du tronc vers le feuillage
	for i = 1, g.branches do
		local yaw = (i - 1) / g.branches * 360 + 30 + hash(i, 3) * 20
		local by = canopyBottom - g.canopy * 0.05 - hash(i, 4) * 0.8
		local len = g.radius * 0.55
		local thick = math.max(0.6, W * 0.32)
		local tilt = 45 + hash(i, 5) * 10
		local cf = CFrame.new(0, by, 0) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(tilt), 0, 0) * CFrame.new(0, 0, -len / 2)
		part("Branch", Vector3.new(thick, thick, len), cf, theme.trunk, theme.trunkMaterial)
	end
	-- Racines : sortent du pied du tronc et s'enfoncent dans l'herbe
	for i = 1, g.roots do
		local yaw = (i - 1) * (360 / g.roots) + 45
		local cf = CFrame.new(0, W * 0.12, 0)
			* CFrame.Angles(0, math.rad(yaw), 0)
			* CFrame.new(0, 0, -W * 0.55)
			* CFrame.Angles(math.rad(-16), 0, 0)
		part("Root", Vector3.new(W * 0.38, W * 0.32, W * 0.7), cf, theme.trunkDark, theme.trunkMaterial)
	end
	return trunk
end

---------------------------------------------------------------------------------------------
-- Feuillage

local function canopyLayers(g: Growth, canopyBottom: number): { Layer }
	local shape = LAYER_SHAPES[math.clamp(g.layers, 1, #LAYER_SHAPES)]
	local bottoms: { number } = {}
	local b = 0
	for i, s in shape do
		bottoms[i] = b
		b += s[2] * OVERLAP
	end
	local total = bottoms[#shape] + shape[#shape][2]
	local k = g.canopy / total
	local layers: { Layer } = {}
	for i, s in shape do
		table.insert(layers, { y = canopyBottom + (bottoms[i] + s[2] / 2) * k, h = s[2] * k, w = 2 * g.radius * 0.78 * s[1] })
	end
	return layers
end

-- Grappe de feuillage : bloc + dessus (plus clair, ou lumineux quand la partie "tips" a un theme
-- avec glow).
local function cluster(size: Vector3, cf: CFrame, leafTheme: Theme, tone: number, tipTheme: Theme)
	local leaf = part("Leaves", size, cf, color(leafTheme.leaves, tone, leafTheme.leafTop), leafTheme.leafMaterial)
	leaf:SetAttribute("Leaf", true)
	if size.X >= 3 and size.Z >= 3 then
		local glow = tipTheme.glow
		local capColor = if glow then glow elseif tone >= 3 then leafTheme.leafTop else color(leafTheme.leaves, tone + 1, leafTheme.leafTop)
		local cap = part(
			"LeavesTop",
			Vector3.new(size.X * 0.62, 0.6, size.Z * 0.62),
			cf * CFrame.new(0, size.Y / 2 + 0.28, 0) * CFrame.Angles(0, math.rad(9), 0),
			capColor,
			if glow then SHINY else leafTheme.leafMaterial
		)
		cap:SetAttribute("Leaf", true)
	end
end

local function buildCanopy(g: Growth, layers: { Layer }, low: Theme, high: Theme, tips: Theme)
	local R = g.radius
	for i, layer in layers do
		local theme = if i == 1 then low else high
		local yaw = 6 + i * 11 + hash(i, 1) * 8
		local tone = if i == 1 then 1 else ((i % 2) + 2)
		cluster(Vector3.new(layer.w, layer.h, layer.w), CFrame.new(0, layer.y, 0) * CFrame.Angles(0, math.rad(yaw), 0), theme, tone, tips)
	end
	-- Couronne de grappes autour du bloc du bas (theme du bas)
	local first = layers[1]
	for i = 1, g.ring do
		local a = (i - 1) / g.ring * math.pi * 2 + 0.3
		local s = R * 0.5 * (if i % 2 == 0 then 1 else 0.86)
		-- hauteurs variees : le dessous du feuillage n'est pas tout plat
		local y = first.y - first.h * 0.24 + hash(i, 2) * first.h * 0.3
		local cf = CFrame.new(math.cos(a) * R * 0.66, y, math.sin(a) * R * 0.66) * CFrame.Angles(0, math.rad(i * 23), 0)
		cluster(Vector3.new(s, first.h * 0.8, s), cf, low, (i % 3) + 1, tips)
	end
	-- Deuxieme couronne autour du 2e bloc (grands arbres, theme du haut)
	local second = layers[2]
	if second and g.ring >= 6 and #layers >= 3 then
		local n = g.ring - 3
		for i = 1, n do
			local a = (i - 1) / n * math.pi * 2 + 0.9
			local s = R * 0.38 * (if i % 2 == 0 then 1 else 0.88)
			local cf = CFrame.new(math.cos(a) * R * 0.5, second.y - second.h * 0.1, math.sin(a) * R * 0.5) * CFrame.Angles(0, math.rad(i * 31), 0)
			cluster(Vector3.new(s, second.h * 0.8, s), cf, high, ((i + 1) % 3) + 1, tips)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Ornements (8 dans le feuillage). `cf` : sur le bord du feuillage, -Z = vers l'exterieur.

type OrnamentFn = (cf: CFrame, k: number, colors: { Color3 }, i: number) -> ()

local ornamentBuilders: { [string]: OrnamentFn } = {}

-- Trefle a 4 feuilles (Lucky)
ornamentBuilders.clover = function(cf, k, colors)
	local base = cf * CFrame.new(0, 0.2 * k, -0.4 * k)
	for j = 0, 3 do
		local a = j * math.pi / 2 + math.pi / 4
		local off = CFrame.new(math.cos(a) * 0.55 * k, math.sin(a) * 0.55 * k, 0)
		shaped(CYLINDER, "Clover", Vector3.new(0.25 * k, 1.3 * k, 1.3 * k), base * off * FACE, color(colors, 1, Color3.new(0, 1, 0)), SHINY)
	end
	part("CloverHeart", Vector3.new(0.5, 0.5, 0.4) * k, base * CFrame.new(0, 0, -0.1 * k), color(colors, 2, Color3.new(1, 1, 0)), SHINY)
end

-- Lingot d'or pose dans le feuillage (Golden)
ornamentBuilders.bar = function(cf, k, colors, i)
	local base = cf * CFrame.new(0, 0.1 * k, -0.3 * k) * CFrame.Angles(0, math.rad(20 + i * 15), math.rad(12))
	part("GoldBar", Vector3.new(1.8, 0.7, 0.9) * k, base, color(colors, 1, Color3.new(1, 0.8, 0)))
	part("GoldBarTop", Vector3.new(1.3, 0.35, 0.6) * k, base * CFrame.new(0, 0.5 * k, 0), color(colors, 2, Color3.new(1, 1, 0.6)), SHINY)
end

-- Pics de cristal qui sortent du feuillage (Crystal)
ornamentBuilders.crystal = function(cf, k, colors, i)
	local tilt = math.rad(30 + (i % 3) * 8)
	local big = cf * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 0, -1.1 * k) * CFrame.Angles(0, 0, math.rad(45))
	part("Crystal", Vector3.new(0.75 * k, 0.75 * k, 2.8 * k), big, color(colors, 1, Color3.new(0, 1, 1)), SHINY)
	local small = cf * CFrame.Angles(0, math.rad(35), 0) * CFrame.Angles(tilt * 0.5, 0, 0) * CFrame.new(0, 0, -0.8 * k) * CFrame.Angles(0, 0, math.rad(45))
	part("Crystal", Vector3.new(0.5 * k, 0.5 * k, 1.8 * k), small, color(colors, 2, Color3.new(1, 1, 1)), GLASS)
end

-- Rune lumineuse qui flotte devant le feuillage (Magic)
ornamentBuilders.rune = function(cf, k, colors)
	local base = cf * CFrame.new(0, 0.4 * k, -1.4 * k) * CFrame.Angles(0, 0, math.rad(45))
	part("Rune", Vector3.new(1.4 * k, 1.4 * k, 0.15 * k), base, color(colors, 1, Color3.new(1, 0, 1)), SHINY)
	part("RuneCore", Vector3.new(0.6 * k, 0.6 * k, 0.2 * k), base * CFrame.new(0, 0, -0.1 * k), color(colors, 2, Color3.new(0, 1, 1)), SHINY)
end

-- Gemme taillee (cube sur la pointe) sertie d'or (Royal)
ornamentBuilders.gem = function(cf, k, colors, i)
	local base = cf * CFrame.new(0, 0.2 * k, -0.6 * k)
	part("GemSetting", Vector3.new(1.5 * k, 1.5 * k, 0.2 * k), base * CFrame.Angles(0, 0, math.rad(45)), color(colors, 3, Color3.new(1, 0.8, 0)))
	part("Gem", Vector3.new(1, 1, 1) * k, base * CFrame.new(0, 0, -0.35 * k) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color(colors, ((i - 1) % 2) + 1, Color3.new(0, 0, 1)), GLASS)
end

-- Flamme spectrale (3 cubes lumineux de plus en plus petits) (Mystic)
ornamentBuilders.flame = function(cf, k, colors, i)
	local sizes = { 0.95, 0.68, 0.42 }
	for j, s in sizes do
		local c = if j == #sizes then color(colors, 2, Color3.new(1, 1, 1)) else color(colors, 1, Color3.new(0, 1, 0.8))
		local pcf = cf * CFrame.new(0, 0.3 * k + (j - 1) * 0.6 * k, -0.7 * k) * CFrame.Angles(math.rad(45), math.rad(j * 25 + i * 10), math.rad(45))
		part("Wisp", Vector3.new(s, s, s) * k, pcf, c, SHINY)
	end
end

-- Etoile scintillante (3 barres croisees) (Cosmic)
ornamentBuilders.star = function(cf, k, colors, i)
	local base = cf * CFrame.new(0, 0.3 * k, -1.1 * k) * CFrame.Angles(math.rad(35), math.rad(25 + i * 20), math.rad(20))
	local c = color(colors, 1, Color3.new(1, 1, 1))
	part("Star", Vector3.new(2.0, 0.3, 0.3) * k, base, c, SHINY)
	part("Star", Vector3.new(0.3, 2.0, 0.3) * k, base, c, SHINY)
	part("Star", Vector3.new(0.3, 0.3, 2.0) * k, base, c, SHINY)
	part("StarCore", Vector3.new(0.6, 0.6, 0.6) * k, base * CFrame.Angles(math.rad(45), 0, math.rad(45)), color(colors, 2, Color3.new(1, 1, 0)), SHINY)
end

-- Petit anneau en orbite (disque lumineux incline + coeur) (Galaxy)
ornamentBuilders.orbit = function(cf, k, colors, i)
	local base = cf * CFrame.new(0, 0.3 * k, -1.2 * k)
	local tilt = CFrame.Angles(math.rad(20 + (i % 3) * 15), math.rad(i * 40), math.rad(70))
	local disc = shaped(CYLINDER, "Orbit", Vector3.new(0.12 * k, 2.2 * k, 2.2 * k), base * tilt, color(colors, 1, Color3.new(1, 0, 1)), SHINY)
	disc.Transparency = 0.25
	part("OrbitCore", Vector3.new(0.6, 0.6, 0.6) * k, base * CFrame.Angles(math.rad(45), 0, math.rad(45)), color(colors, 2, Color3.new(0, 0.5, 1)), SHINY)
end

-- Paire de petites ailes (Divine)
ornamentBuilders.wing = function(cf, k, colors)
	local root = cf * CFrame.new(0, 0.3 * k, -0.5 * k)
	for _, side in { -1, 1 } do
		for j, len in { 1.8, 1.4, 1.0 } do
			local angle = math.rad(side * (15 + (j - 1) * 24))
			local fcf = root * CFrame.new(side * 0.2 * k, 0, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(side * len * k / 2, 0, 0)
			part("Feather", Vector3.new(len * k, 0.42 * k, 0.2 * k), fcf, color(colors, 1, Color3.new(1, 1, 1)))
		end
	end
	part("WingHeart", Vector3.new(0.5, 0.5, 0.3) * k, root * CFrame.Angles(0, 0, math.rad(45)), color(colors, 2, Color3.new(1, 0.8, 0)), SHINY)
end

local function buildOrnaments(g: Growth, layers: { Layer }, theme: Theme)
	local kind = theme.ornament
	local build = kind and ornamentBuilders[kind]
	if build == nil then
		return
	end
	local colors = theme.ornamentColors or {}
	local k = math.clamp(g.radius / 10, 0.85, 1.2) * ORNAMENT_SCALE
	for i = 1, ORNAMENTS do
		local a = (i - 1) / ORNAMENTS * math.pi * 2 + 0.35
		local upper = i % 2 == 0 and #layers >= 3
		local layer = if upper then layers[2] else layers[1]
		-- sur le bord exterieur du feuillage (sinon les grappes les cachent)
		local r = if upper then layer.w * 0.5 + 0.6 else g.radius * 1.0
		local y = layer.y + layer.h * (if upper then 0.05 else 0.15)
		local p = Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
		build(CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))), k, colors, i)
	end
end

---------------------------------------------------------------------------------------------
-- Veines lumineuses, aura, grand anneau

local function buildVeins(g: Growth, trunk: Trunk, theme: Theme)
	local glow = theme.glow
	if glow == nil then
		return
	end
	for s, seg in trunk.segments do
		if s > 2 then
			break
		end
		for f = 0, 3 do
			local cf = seg.cf * CFrame.Angles(0, f * math.pi / 2, 0) * CFrame.new(0, 0, -(seg.w / 2 + 0.03))
			part("Vein", Vector3.new(math.max(0.5, seg.w * 0.14), seg.h * 0.85, 0.2), cf, glow, SHINY)
		end
	end
	-- Anneau lumineux au pied du tronc (dans la zone sans fruit)
	local r = g.width * 0.5 + 0.9
	local n = 10
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		local len = 2 * math.pi * r / n * 1.05
		part("FootRing", Vector3.new(len, 0.4, 0.6), CFrame.Angles(0, a, 0) * CFrame.new(0, 0.2, -r), glow, SHINY)
	end
end

local function buildAura(g: Growth, layers: { Layer }, theme: Theme)
	local glow = theme.glow
	local aura = theme.aura
	if glow == nil or aura == nil then
		return
	end
	local first, last = layers[1], layers[#layers]
	local y0 = first.y - first.h / 2
	local y1 = last.y + last.h / 2
	local holder = part("Aura", Vector3.new(g.radius * 1.6, (y1 - y0) * 0.9, g.radius * 1.6), CFrame.new(0, (y0 + y1) / 2, 0), glow)
	holder.Transparency = 1
	holder.CastShadow = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraSparkles"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Color = ColorSequence.new(color(aura, 1, glow), color(aura, 2, glow))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.6) })
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Parent = holder
	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = glow
	light.Range = math.clamp(g.radius * 1.8, 10, 22)
	light.Brightness = 0.7 -- faible : plus fort, les feuilles paraissent fluo
	light.Shadows = false
	light.Parent = holder
end

local function buildHalo(g: Growth, layers: { Layer }, theme: Theme)
	local glow = theme.glow
	if glow == nil then
		return
	end
	local first = layers[1]
	local r = g.radius + 1.3
	local ring = CFrame.new(0, first.y + first.h * 0.35, 0) * CFrame.Angles(math.rad(8), 0, math.rad(4))
	for i = 1, HALO_PIECES do
		local a = (i - 1) / HALO_PIECES * math.pi * 2
		local len = 2 * math.pi * r / HALO_PIECES * 1.04
		part("Halo", Vector3.new(len, 0.7, 0.7), ring * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r), glow, SHINY)
	end
end

---------------------------------------------------------------------------------------------
-- Couronne (sommet de l'arbre). `top` : CFrame au sommet, face vers l'avant (-Z). Hauteur ~CROWN_HEIGHT x k.

type CrownFn = (top: CFrame, k: number, colors: { Color3 }, g: Growth, layers: { Layer }) -> ()

local crownBuilders: { [string]: CrownFn } = {}

-- Grand trefle a 4 feuilles face a l'entree (Lucky)
crownBuilders.clover = function(top, k, colors)
	local center = top * CFrame.new(0, 1.85 * k, 0)
	part("CrownStem", Vector3.new(0.45, 1.6, 0.45) * k, top * CFrame.new(0, 0.6 * k, 0), color(colors, 3, Color3.new(0, 0.5, 0.2)))
	for j = 0, 3 do
		local a = j * math.pi / 2 + math.pi / 4
		local off = CFrame.new(math.cos(a) * 0.95 * k, math.sin(a) * 0.95 * k, 0)
		shaped(CYLINDER, "CrownClover", Vector3.new(0.4 * k, 2.3 * k, 2.3 * k), center * off * FACE, color(colors, 1, Color3.new(0, 1, 0)))
	end
	part("CrownHeart", Vector3.new(0.9, 0.9, 0.6) * k, center * CFrame.new(0, 0, -0.15 * k) * CFrame.Angles(0, 0, math.rad(45)), color(colors, 2, Color3.new(1, 1, 0)), SHINY)
end

-- Grande etoile doree a 8 branches (Golden)
crownBuilders.star = function(top, k, colors)
	local center = top * CFrame.new(0, 2.0 * k, 0)
	local gold = color(colors, 1, Color3.new(1, 0.8, 0))
	part("CrownStar", Vector3.new(3.4, 0.6, 0.5) * k, center, gold, SHINY)
	part("CrownStar", Vector3.new(0.6, 3.8, 0.5) * k, center, gold, SHINY)
	part("CrownStar", Vector3.new(2.2, 0.4, 0.45) * k, center * CFrame.Angles(0, 0, math.rad(45)), gold, SHINY)
	part("CrownStar", Vector3.new(2.2, 0.4, 0.45) * k, center * CFrame.Angles(0, 0, math.rad(-45)), gold, SHINY)
	part("CrownStarCore", Vector3.new(1.2, 1.2, 0.7) * k, center * CFrame.Angles(0, 0, math.rad(45)), color(colors, 2, Color3.new(1, 1, 1)), SHINY)
end

-- Bouquet de grands cristaux (Crystal)
crownBuilders.crystal = function(top, k, colors)
	local main = color(colors, 1, Color3.new(0, 1, 1))
	local side = color(colors, 2, Color3.new(1, 1, 1))
	part("CrownCrystal", Vector3.new(1.1, 3.0, 1.1) * k, top * CFrame.new(0, 1.6 * k, 0) * CFrame.Angles(0, math.rad(45), 0), main, SHINY)
	part("CrownCrystal", Vector3.new(0.6, 1.0, 0.6) * k, top * CFrame.new(0, 3.5 * k, 0) * CFrame.Angles(0, math.rad(45), 0), side, SHINY)
	for _, s in { -1, 1 } do
		local cf = top * CFrame.new(s * 0.9 * k, 1.0 * k, 0) * CFrame.Angles(0, 0, math.rad(-s * 25)) * CFrame.new(0, 0.6 * k, 0) * CFrame.Angles(0, math.rad(45), 0)
		part("CrownCrystal", Vector3.new(0.8, 2.2, 0.8) * k, cf, side, GLASS)
	end
end

-- Orbe magique + anneau de petits cubes (Magic)
crownBuilders.orb = function(top, k, colors)
	local center = top * CFrame.new(0, 2.0 * k, 0)
	part("CrownBase", Vector3.new(0.9, 0.9, 0.9) * k, top * CFrame.new(0, 0.6 * k, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color(colors, 3, Color3.new(0.4, 0, 0.6)))
	shaped(BALL, "CrownOrb", Vector3.new(2.0, 2.0, 2.0) * k, center, color(colors, 1, Color3.new(1, 0, 1)), SHINY)
	local ring = center * CFrame.Angles(math.rad(25), 0, math.rad(10))
	for i = 1, 10 do
		local a = (i - 1) / 10 * math.pi * 2
		part("CrownOrbit", Vector3.new(0.35, 0.35, 0.35) * k, ring * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1.8 * k), color(colors, 2, Color3.new(0, 1, 1)), SHINY)
	end
end

-- Couronne royale : bandeau d'or, pointes, gemmes (Royal)
crownBuilders.crown = function(top, k, colors)
	local gold = color(colors, 1, Color3.new(1, 0.8, 0))
	local red = color(colors, 2, Color3.new(1, 0, 0))
	local blue = color(colors, 3, Color3.new(0, 0, 1))
	local base = top * CFrame.new(0, 0.6 * k, 0)
	part("CrownVelvet", Vector3.new(2.2, 1.0, 2.2) * k, base * CFrame.new(0, 0.2 * k, 0), red)
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		local band = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1.5 * k)
		part("CrownBand", Vector3.new(1.3, 0.9, 0.4) * k, band, gold)
		if i % 2 == 1 then
			part("CrownSpike", Vector3.new(0.4, 1.2, 0.4) * k, band * CFrame.new(0, 1.0 * k, 0) * CFrame.Angles(0, math.rad(45), 0), gold)
			part("CrownGem", Vector3.new(0.5, 0.5, 0.5) * k, band * CFrame.new(0, 1.8 * k, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), red, GLASS)
		else
			part("CrownGem", Vector3.new(0.45, 0.45, 0.2) * k, band * CFrame.new(0, 0, -0.25 * k) * CFrame.Angles(0, 0, math.rad(45)), blue, GLASS)
		end
	end
	part("CrownCross", Vector3.new(0.3, 1.2, 0.3) * k, base * CFrame.new(0, 1.5 * k, 0), gold)
	part("CrownCross", Vector3.new(0.8, 0.3, 0.3) * k, base * CFrame.new(0, 1.7 * k, 0), gold)
end

-- Oeil mystique dans un losange lumineux, face a l'entree (Mystic)
crownBuilders.eye = function(top, k, colors)
	local center = top * CFrame.new(0, 2.0 * k, 0)
	local glow = color(colors, 1, Color3.new(0, 1, 0.8))
	local d = 1.8 * k -- demi-diagonale du losange
	local side = d * math.sqrt(2)
	for j = 0, 3 do
		local a = j * math.pi / 2 + math.pi / 4
		local mid = CFrame.new(math.cos(a) * d / math.sqrt(2), math.sin(a) * d / math.sqrt(2), 0) -- milieu d'un cote
		part("CrownFrame", Vector3.new(side, 0.35 * k, 0.35 * k), center * mid * CFrame.Angles(0, 0, a + math.pi / 2), glow, SHINY)
	end
	shaped(CYLINDER, "CrownEye", Vector3.new(0.3 * k, 1.9 * k, 1.9 * k), center * FACE, color(colors, 2, Color3.new(1, 1, 1)))
	shaped(CYLINDER, "CrownIris", Vector3.new(0.32 * k, 1.1 * k, 1.1 * k), center * CFrame.new(0, 0, -0.05 * k) * FACE, glow, SHINY)
	shaped(CYLINDER, "CrownPupil", Vector3.new(0.34 * k, 0.5 * k, 0.5 * k), center * CFrame.new(0, 0, -0.1 * k) * FACE, color(colors, 3, Color3.new(0, 0, 0)))
end

-- Planete avec anneau (Cosmic)
crownBuilders.planet = function(top, k, colors)
	local center = top * CFrame.new(0, 1.7 * k, 0)
	shaped(BALL, "CrownPlanet", Vector3.new(2.4, 2.4, 2.4) * k, center, color(colors, 1, Color3.new(1, 0.5, 0.2)))
	local ring = shaped(CYLINDER, "CrownRing", Vector3.new(0.12 * k, 4.4 * k, 4.4 * k), center * CFrame.Angles(math.rad(-18), 0, math.rad(90)), color(colors, 3, Color3.new(0.5, 0.8, 1)), SHINY)
	ring.Transparency = 0.2
	part("CrownMoon", Vector3.new(0.5, 0.5, 0.5) * k, center * CFrame.new(1.9 * k, 1.1 * k, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color(colors, 2, Color3.new(1, 1, 0.6)), SHINY)
end

-- Galaxie : coeur blanc + 2 disques lumineux inclines vers l'entree (Galaxy)
crownBuilders.galaxy = function(top, k, colors)
	local center = top * CFrame.new(0, 1.8 * k, 0)
	local d1 = shaped(CYLINDER, "CrownGalaxy", Vector3.new(0.12 * k, 4.2 * k, 4.2 * k), center * CFrame.Angles(math.rad(-35), 0, math.rad(90)), color(colors, 1, Color3.new(1, 0, 1)), SHINY)
	d1.Transparency = 0.3
	local d2 = shaped(CYLINDER, "CrownGalaxy", Vector3.new(0.14 * k, 3.0 * k, 3.0 * k), center * CFrame.Angles(math.rad(-35), math.rad(40), math.rad(90)), color(colors, 2, Color3.new(0, 0.5, 1)), SHINY)
	d2.Transparency = 0.2
	shaped(BALL, "CrownCore", Vector3.new(1.1, 1.1, 1.1) * k, center, color(colors, 3, Color3.new(1, 1, 1)), SHINY)
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2 + 0.6
		part("CrownSpark", Vector3.new(0.35, 0.35, 0.35) * k, center * CFrame.new(math.cos(a) * 2.4 * k, 0.4 * k + math.sin(a) * 0.8 * k, math.sin(a) * 1.2 * k), color(colors, 3, Color3.new(1, 1, 1)), SHINY)
	end
end

-- Aureole doree au-dessus de l'arbre + grandes ailes de chaque cote du feuillage (Divine)
crownBuilders.halo = function(top, k, colors, g, layers)
	local gold = color(colors, 1, Color3.new(1, 0.8, 0))
	local white = color(colors, 2, Color3.new(1, 1, 1))
	local ring = top * CFrame.new(0, 1.8 * k, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	local r = 2.1 * k
	for i = 1, 12 do
		local a = (i - 1) / 12 * math.pi * 2
		part("CrownHalo", Vector3.new(2 * math.pi * r / 12 * 1.06, 0.35 * k, 0.45 * k), ring * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r), gold, SHINY)
	end
	part("CrownLight", Vector3.new(0.5, 0.5, 0.5) * k, top * CFrame.new(0, 0.9 * k, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), white, SHINY)
	-- Grandes ailes dorees (plumes en eventail) qui sortent des cotes du feuillage. Dorees : des ailes
	-- blanches ne se voyaient pas sur le feuillage blanc.
	local mid = layers[2] or layers[1]
	local kw = math.clamp(g.radius / 10, 0.8, 1.1)
	for _, side in { -1, 1 } do
		local root = CFrame.new(side * g.radius * 0.8, mid.y + mid.h * 0.3, g.radius * 0.2) * CFrame.Angles(0, math.rad(side * -25), 0)
		for j, len in { 7.5, 6.6, 5.6, 4.6, 3.6 } do
			local angle = math.rad(side * (10 + (j - 1) * 14))
			local fcf = root * CFrame.Angles(0, 0, angle) * CFrame.new(side * len * kw / 2, 0, 0)
			part("Wing", Vector3.new(len * kw, 1.1 * kw, 0.4 * kw), fcf, if j % 2 == 1 then gold else white, SHINY)
		end
	end
end

-- Eclat de la couronne : quelques etincelles qui scintillent autour (effet, pas de Neon).
local function crownShine(y: number, k: number, tint: Color3)
	local holder = part("CrownShine", Vector3.new(3, 3, 3) * k, CFrame.new(0, y, 0), tint)
	holder.Transparency = 1
	holder.CastShadow = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CrownSparkles"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), tint)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45 * k), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(0, 0.6)
	emitter.Rotation = NumberRange.new(0, 90)
	emitter.Parent = holder
end

---------------------------------------------------------------------------------------------
-- Details de l'etage 1 : tuteur, nichoir, ruche, balancoire

local function buildExtras(g: Growth, trunk: Trunk, canopyBottom: number)
	local W = g.width
	if g.stake then
		part("Mound", Vector3.new(W * 2.8, 0.3, W * 2.8), CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(20), 0), SOIL)
		local h = g.trunk * 0.9
		part("Stake", Vector3.new(0.4, h, 0.4), CFrame.new(W / 2 + 0.45, h / 2, 0.3), WOOD)
		part("Tie", Vector3.new(W / 2 + 0.9, 0.3, 0.6), CFrame.new(W / 4 + 0.3, h * 0.65, 0.15), RED)
	end
	local seg1 = trunk.segments[1]
	if g.birdhouse and seg1 then
		local y = math.min(seg1.h - 1.4, canopyBottom - 2)
		local front = CFrame.new(0, y, -seg1.w / 2)
		part("Birdhouse", Vector3.new(1.6, 1.8, 1.2), front * CFrame.new(0, 0, -0.6), RED)
		part("BirdhouseRoof", Vector3.new(2.1, 0.35, 1.6), front * CFrame.new(-0.5, 1.15, -0.6) * CFrame.Angles(0, 0, math.rad(32)), WOOD)
		part("BirdhouseRoof", Vector3.new(2.1, 0.35, 1.6), front * CFrame.new(0.5, 1.15, -0.6) * CFrame.Angles(0, 0, math.rad(-32)), WOOD)
		part("BirdhouseHole", Vector3.new(0.6, 0.6, 0.1), front * CFrame.new(0, 0.2, -1.23), DARK)
	end
	if g.hive then
		local hive = CFrame.new(-g.radius * 0.62, canopyBottom - 0.3, g.radius * 0.18)
		part("HiveRope", Vector3.new(0.15, 2.4, 0.15), hive * CFrame.new(0, 1.2, 0), STEM)
		local rings = { { 1.2, 0.6 }, { 1.8, 0.7 }, { 2.1, 0.7 }, { 1.8, 0.7 }, { 1.1, 0.5 } }
		local y = 0
		for i, r in rings do
			y -= r[2]
			part("Hive", Vector3.new(r[1], r[2], r[1]), hive * CFrame.new(0, y + r[2] / 2, 0) * CFrame.Angles(0, math.rad(i * 20), 0), HIVE[(i % 2) + 1])
		end
		part("HiveHole", Vector3.new(0.5, 0.45, 0.1), hive * CFrame.new(0, -1.8, -1.06), DARK)
	end
	if g.swing then
		-- Sur le cote avant-droit (pas devant le nichoir)
		local side = CFrame.Angles(0, math.rad(60), 0)
		local branchY = canopyBottom - 0.7
		local len = W / 2 + 6.5
		part("SwingBranch", Vector3.new(1.3, 1.3, len), side * CFrame.new(0, branchY, -len / 2), WOOD:Lerp(STEM, 0.75))
		local seatY = 2.4
		local seatZ = -(W / 2 + 4.6)
		local rope = branchY - seatY
		part("SwingRope", Vector3.new(0.18, rope, 0.18), side * CFrame.new(-1.1, seatY + rope / 2, seatZ), ROPE)
		part("SwingRope", Vector3.new(0.18, rope, 0.18), side * CFrame.new(1.1, seatY + rope / 2, seatZ), ROPE)
		part("SwingSeat", Vector3.new(2.8, 0.35, 1.1), side * CFrame.new(0, seatY, seatZ), WOOD)
	end
end

---------------------------------------------------------------------------------------------

-- Haut du feuillage, puis base et taille de la couronne (reduite pour rester sous MaxHeight).
local function canopyTop(layers: { Layer }): number
	local last = layers[#layers]
	return last.y + last.h / 2 + 0.6
end

local function crownPlace(g: Growth, layers: { Layer }): (number, number)
	local base = canopyTop(layers) - 0.4
	local wanted = CROWN_SCALE * math.clamp(g.radius / 10, 0.9, 1.15)
	local k = math.max(0.5, math.min(wanted, (TreeConfig.MaxHeight - base) / CROWN_HEIGHT))
	return base, k
end

-- Mesures de l'arbre de l'etage `floor` au niveau `level`, sans construire de pieces.
function TreeBuilder.Measure(floor: number, level: number): Metrics
	local tier = TreeConfig.Tier(floor, level)
	local g = TreeConfig.GrowthFor(tier)
	local canopyBottom = g.trunk
	local layers = canopyLayers(g, canopyBottom)
	local height = canopyTop(layers)
	if TreeConfig.SlotTheme(floor, level, "crown").crown ~= nil then
		local base, k = crownPlace(g, layers)
		height = base + CROWN_HEIGHT * k
	end
	return {
		tier = tier,
		dropRadius = math.clamp(g.radius + 2.6, 8, 12.8),
		fallHeight = canopyBottom + g.canopy * 0.12,
		labelHeight = canopyBottom + g.canopy * 0.45,
		trunkClear = math.max(1.8, g.width * 0.55 + 1.2 + (if g.roots > 0 then 0.4 else 0)),
		height = height,
	}
end

-- Construit l'arbre de l'etage `floor` au niveau `level`. Renvoie le modele "Body" (pas encore
-- range : a l'appelant de le poser et de le ranger) et ses mesures.
function TreeBuilder.Build(floor: number, level: number): (Model, Metrics)
	local tier = TreeConfig.Tier(floor, level)
	local g = TreeConfig.GrowthFor(tier)
	local function theme(slot: string): Theme
		return TreeConfig.SlotTheme(floor, level, slot)
	end

	local model = Instance.new("Model")
	model.Name = "Body"
	model:SetAttribute("TreeTier", tier)
	current = model

	local canopyBottom = g.trunk
	local layers = canopyLayers(g, canopyBottom)
	local trunk = buildTrunk(g, canopyBottom, theme("trunk"))
	buildExtras(g, trunk, canopyBottom)
	buildCanopy(g, layers, theme("leavesLow"), theme("leavesHigh"), theme("tips"))
	buildOrnaments(g, layers, theme("ornaments"))
	buildVeins(g, trunk, theme("veins"))
	buildAura(g, layers, theme("aura"))
	buildHalo(g, layers, theme("halo"))

	local crownTheme = theme("crown")
	local crownKind = crownTheme.crown
	local buildCrown = crownKind and crownBuilders[crownKind]
	if buildCrown then
		local base, k = crownPlace(g, layers)
		local colors = crownTheme.crownColors or {}
		buildCrown(CFrame.new(0, base, 0), k, colors, g, layers)
		crownShine(base + CROWN_HEIGHT * k * 0.5, k, color(colors, 1, Color3.new(1, 1, 1)))
	end

	current = nil
	model.WorldPivot = CFrame.identity
	return model, TreeBuilder.Measure(floor, level)
end

return TreeBuilder
