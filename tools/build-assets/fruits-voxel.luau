--!strict
-- Fruits voxel (petits cubes, comme les oeufs voxel des captures de reference du 2026-11-19).
-- Chaque fruit est dessine en petits cubes (forme + motif + ombrage 3 tons + reflet), les
-- cubes de meme couleur sont fusionnes en blocs, puis soudes en UNE UnionOperation
-- (GeometryService:UnionAsync, UsePartColor = false : chaque cube garde sa couleur).
-- Resultat : ReplicatedStorage.FruitAssets.<FruitId> (pivot = centre-bas du fruit, attribut
-- BodyColor). FruitModels.CreateFruit clone ces modeles (repli sur une boule si absent).
-- A lancer dans Studio, en edition (require d'une copie de ce fichier). Relancable : remplace
-- les anciens. Option : _G.FRUIT_ONLY = { "Apple", ... } pour ne refaire que ceux-la.
-- Doc : docs/systems/fruits.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GeometryService = game:GetService("GeometryService")
local Fruits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Fruits")) :: any

-- Le dessin est fait en "unites de dessin" (une pomme ~1.2 de large) puis agrandi de SCALE.
-- 2026-11-19 (soir, demande utilisateur : "plus comprehensibles, moins voxel, un peu plus gros") :
-- fruits 30 % plus gros, cubes plus petits (~16 de large au lieu de 10), moins de bruit.
local SCALE = 1.3
local VOX_WORLD = 0.1 -- taille d'un cube dans le jeu (studs)
local VOX = VOX_WORLD / SCALE -- taille d'un cube dans le dessin
local LIGHT = Vector3.new(-0.45, 0.8, 0.4).Unit -- lumiere "peinte" (haut, avant gauche)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Ligne de la grille la plus proche : centre d'un detail de 2 cubes d'epaisseur (queues, feuilles).
local function edge(v: number): number
	return math.floor(v / VOX + 0.5) * VOX
end

------------------------------------------------------------------------------------------------
-- Primitives : ellipsoide (E), boite (B), forme libre (F). Role "carve" = on retire les cubes.
------------------------------------------------------------------------------------------------

type Prim = {
	kind: string,
	c: Vector3,
	r: Vector3,
	role: string,
	fn: ((Vector3) -> boolean)?,
}

local function E(cx: number, cy: number, cz: number, rx: number, ry: number, rz: number, role: string): Prim
	return { kind = "ell", c = Vector3.new(cx, cy, cz), r = Vector3.new(rx, ry, rz), role = role }
end

local function B(cx: number, cy: number, cz: number, hx: number, hy: number, hz: number, role: string): Prim
	return { kind = "box", c = Vector3.new(cx, cy, cz), r = Vector3.new(hx, hy, hz), role = role }
end

local function F(cx: number, cy: number, cz: number, rx: number, ry: number, rz: number, role: string, fn: (Vector3) -> boolean): Prim
	return { kind = "fn", c = Vector3.new(cx, cy, cz), r = Vector3.new(rx, ry, rz), role = role, fn = fn }
end

-- Un seul cube a la position (x, y, z) arrondie a la grille.
local function dot(x: number, y: number, z: number, role: string): Prim
	return B(edge(x), edge(y), edge(z), VOX * 0.95, VOX * 0.95, VOX * 0.95, role) -- bloc de 2 x 2 x 2
end

-- Ligne de cubes de a vers b (queues de cerises, cornes...).
local function line(prims: { Prim }, a: Vector3, b: Vector3, role: string)
	local steps = math.max(1, math.ceil((b - a).Magnitude / (VOX * 0.5)))
	for s = 0, steps do
		local p = a:Lerp(b, s / steps)
		table.insert(prims, dot(p.X, p.Y, p.Z, role))
	end
end

local function inside(pr: Prim, p: Vector3): boolean
	local d = p - pr.c
	local r = pr.r
	if math.abs(d.X) > r.X or math.abs(d.Y) > r.Y or math.abs(d.Z) > r.Z then
		return false
	end
	if pr.kind == "ell" then
		local x, y, z = d.X / r.X, d.Y / r.Y, d.Z / r.Z
		return x * x + y * y + z * z <= 1
	elseif pr.kind == "box" then
		return true
	end
	local fn = pr.fn :: (Vector3) -> boolean
	return fn(d)
end

-- Points repartis sur une sphere (spirale de Fibonacci), deterministes.
local function fib(n: number): { Vector3 }
	local pts = {}
	local ga = math.pi * (3 - math.sqrt(5))
	for i = 0, n - 1 do
		local y = 1 - (i + 0.5) / n * 2
		local r = math.sqrt(1 - y * y)
		local a = ga * i
		table.insert(pts, Vector3.new(math.cos(a) * r, y, math.sin(a) * r))
	end
	return pts
end

------------------------------------------------------------------------------------------------
-- Familles de formes. s = echelle. Le sol est a y = 0, l'axe du fruit en x = z = 0.
------------------------------------------------------------------------------------------------

type Def = {
	id: string,
	shape: string,
	s: number,
	body: Color3,
	accent: Color3?,
	accent2: Color3?,
	pattern: string?,
	density: number?,
	count: number?,
	crease: boolean?,
	shift: boolean?, -- glitch : certaines couches decalees d'un cube
	roles: { [string]: Color3 },
	extras: { string }, -- "halo", "wings", "horn", "ring", "crown", "rays"
}

local function stemLeaf(prims: { Prim }, top: number, s: number, leafSide: number?)
	table.insert(prims, B(edge(0), top + 0.12 * s, edge(0), VOX * 0.95, 0.15 * s, VOX * 0.95, "stem"))
	local side = leafSide or 1
	table.insert(prims, E(edge(0.3 * s * side), edge(top + 0.1 * s), edge(0.04), 0.28 * s, VOX * 1.0, 0.15 * s, "leaf"))
end

local SHAPES: { [string]: (Def) -> { Prim } } = {}

SHAPES.apple = function(d)
	local s = d.s
	local p = {
		E(0, 0.56 * s, 0, 0.62 * s, 0.56 * s, 0.62 * s, "body"),
		E(0, 1.13 * s, 0, 0.2 * s, 0.1 * s, 0.2 * s, "carve"),
		E(0, -0.02, 0, 0.18 * s, 0.07, 0.18 * s, "carve"),
	}
	stemLeaf(p, 1.04 * s, s)
	return p
end

SHAPES.round = function(d) -- orange, pomegranate, coconut, lychee...
	local s = d.s
	local p = { E(0, 0.58 * s, 0, 0.6 * s, 0.58 * s, 0.6 * s, "body") }
	-- petit bouton vert en haut
	table.insert(p, E(edge(0), edge(1.17 * s), edge(0), 0.13, VOX * 1.0, 0.13, "leaf"))
	table.insert(p, dot(0, 1.17 * s + 0.12, 0, "stem"))
	return p
end

SHAPES.plum = function(d)
	local s = d.s
	local p = {
		E(0, 0.56 * s, 0, 0.52 * s, 0.56 * s, 0.5 * s, "body"),
		E(0, 1.12 * s, 0, 0.14 * s, 0.08 * s, 0.14 * s, "carve"),
	}
	table.insert(p, B(edge(0), 1.15 * s, edge(0), VOX * 0.95, 0.1 * s, VOX * 0.95, "stem"))
	return p
end

SHAPES.peach = function(d)
	local s = d.s
	local p = {
		E(0, 0.58 * s, 0, 0.6 * s, 0.58 * s, 0.6 * s, "body"),
		E(0, 1.15 * s, 0, 0.16 * s, 0.09 * s, 0.16 * s, "carve"),
	}
	stemLeaf(p, 1.06 * s, s, -1)
	return p
end

SHAPES.pear = function(d)
	local s = d.s
	local p = {
		E(0, 0.46 * s, 0, 0.52 * s, 0.46 * s, 0.52 * s, "body"),
		E(0, 0.95 * s, 0, 0.3 * s, 0.32 * s, 0.3 * s, "body"),
		E(0, 0.72 * s, 0, 0.4 * s, 0.25 * s, 0.4 * s, "body"),
	}
	stemLeaf(p, 1.22 * s, s)
	return p
end

SHAPES.lemon = function(d)
	local s = d.s
	return {
		E(0, 0.48 * s, 0, 0.6 * s, 0.46 * s, 0.46 * s, "body"),
		E(0.6 * s, 0.48 * s, 0, 0.14, 0.1, 0.1, "body"),
		E(-0.6 * s, 0.48 * s, 0, 0.1, 0.08, 0.08, "body"),
		dot(-0.72 * s, 0.48 * s, 0, "stem"),
	}
end

SHAPES.oval = function(d) -- mangue, papaye, finger lime : s = longueur
	local s = d.s
	local h = d.count or 1 -- epaisseur relative
	return {
		E(0, 0.46 * h, 0, 0.62 * s, 0.46 * h, 0.44 * h, "body"),
		E(0.4 * s, 0.56 * h, 0, 0.24 * h, 0.26 * h, 0.24 * h, "body"),
		dot(-0.6 * s, 0.6 * h, 0, "stem"),
	}
end

SHAPES.banana = function(d)
	local s = d.s
	local p: { Prim } = {}
	local R = 1.0 * s
	local yc = 1.22 * s
	local n = 11
	for i = 0, n - 1 do
		local t = math.rad(-58 + 116 * i / (n - 1))
		local x = R * math.sin(t)
		local y = yc - R * math.cos(t)
		local th = 0.24 * s * (1 - 0.45 * math.abs(t) / math.rad(58))
		table.insert(p, E(x, y, 0, th * 1.1, th, th, "body"))
	end
	-- bouts marron et queue
	local tA = math.rad(-60)
	local tB = math.rad(60)
	table.insert(p, E(R * math.sin(tA), yc - R * math.cos(tA), 0, 0.09, 0.09, 0.09, "tip"))
	local qx, qy = R * math.sin(tB), yc - R * math.cos(tB)
	line(p, Vector3.new(qx, qy, 0), Vector3.new(qx + 0.12 * s, qy + 0.22 * s, 0), "stem")
	return p
end

SHAPES.grapes = function(d)
	local s = d.s
	local p: { Prim } = {}
	local r = 0.19 * s
	local rows = {
		{ y = 0.2, n = 1, rad = 0 },
		{ y = 0.45, n = 3, rad = 0.2 },
		{ y = 0.7, n = 4, rad = 0.27 },
		{ y = 0.95, n = 5, rad = 0.31 },
	}
	for ri, row in rows do
		if row.n == 1 then
			table.insert(p, E(0, row.y * s, 0, r, r, r, "body"))
		else
			for i = 0, row.n - 1 do
				local a = i / row.n * math.pi * 2 + ri * 0.7
				table.insert(p, E(math.cos(a) * row.rad * s, row.y * s, math.sin(a) * row.rad * s, r, r, r, "body"))
			end
			if row.n >= 4 then
				table.insert(p, E(0, row.y * s, 0, r, r, r, "body"))
			end
		end
	end
	table.insert(p, B(edge(0), 1.25 * s, edge(0), VOX * 0.95, 0.14 * s, VOX * 0.95, "stem"))
	table.insert(p, E(edge(0.28 * s), edge(1.26 * s), edge(0), 0.3 * s, VOX * 1.0, 0.22 * s, "leaf"))
	return p
end

SHAPES.berry = function(d) -- myrtille, baies : couronne en haut
	local s = d.s
	local p = {
		E(0, 0.47 * s, 0, 0.5 * s, 0.47 * s, 0.5 * s, "body"),
		E(0, 0.95 * s, 0, 0.14 * s, 0.06, 0.14 * s, "carve"),
	}
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		table.insert(p, dot(math.cos(a) * 0.17 * s, 0.98 * s, math.sin(a) * 0.17 * s, "crown"))
	end
	return p
end

SHAPES.drupe = function(d) -- framboise, cloudberry : boule faite de petites boules
	local s = d.s
	local p = { E(0, 0.52 * s, 0, 0.4 * s, 0.48 * s, 0.4 * s, "body") }
	for _, n in fib(34) do
		if n.Y > -0.85 then
			local c = Vector3.new(n.X * 0.42 * s, 0.52 * s + n.Y * 0.5 * s, n.Z * 0.42 * s)
			table.insert(p, E(c.X, c.Y, c.Z, 0.13 * s, 0.13 * s, 0.13 * s, "body"))
		end
	end
	table.insert(p, E(edge(0), edge(1.06 * s), edge(0), 0.2 * s, VOX * 1.0, 0.2 * s, "leaf"))
	table.insert(p, dot(0, 1.06 * s + 0.12, 0, "stem"))
	return p
end

SHAPES.strawberry = function(d)
	local s = d.s
	local p: { Prim } = {
		F(0, 0.54 * s, 0, 0.62 * s, 0.54 * s, 0.62 * s, "body", function(v: Vector3): boolean
			local t = (v.Y + 0.54 * s) / (1.08 * s) -- 0 en bas, 1 en haut
			local rr = 0.6 * s * math.sqrt(math.clamp(t * 1.2, 0, 1))
			if t > 0.8 then
				rr *= 1 - ((t - 0.8) / 0.2) ^ 2 * 0.35
			end
			return v.X * v.X + v.Z * v.Z <= rr * rr
		end),
	}
	-- couronne de 5 feuilles a plat
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		table.insert(p, E(math.cos(a) * 0.24 * s, edge(1.1 * s), math.sin(a) * 0.24 * s, 0.17 * s, VOX * 1.0, 0.17 * s, "leaf"))
	end
	table.insert(p, B(edge(0), 1.25 * s, edge(0), VOX * 0.95, 0.12 * s, VOX * 0.95, "stem"))
	return p
end

SHAPES.cherry = function(d)
	local s = d.s
	local p: { Prim } = {}
	local n = d.count or 2
	local top = Vector3.new(0.02, 1.38 * s, 0)
	for i = 0, n - 1 do
		local a = if n == 2 then (if i == 0 then 0 else math.pi) else i / n * math.pi * 2
		local cx, cz = math.cos(a) * 0.32 * s, math.sin(a) * 0.32 * s
		table.insert(p, E(cx, 0.32 * s, cz, 0.32 * s, 0.32 * s, 0.32 * s, "body"))
		table.insert(p, E(cx, 0.64 * s, cz, 0.08, 0.05, 0.08, "carve"))
		line(p, Vector3.new(cx * 0.9, 0.62 * s, cz * 0.9), top, "stem")
	end
	table.insert(p, E(edge(0.24 * s), edge(1.36 * s), edge(0), 0.22 * s, VOX * 1.0, 0.12 * s, "leaf"))
	return p
end

SHAPES.kiwi = function(d) -- kiwi coupe en deux, face coupee vers le haut (lisible vu d'en haut)
	local s = d.s
	return {
		E(0, 0.62 * s, 0, 0.6 * s, 0.62 * s, 0.52 * s, "body"),
		B(0, 1.4 * s, 0, 0.8 * s, 0.6 * s, 0.8 * s, "carve"),
	}
end

SHAPES.pineapple = function(d)
	local s = d.s
	local p = { E(0, 0.54 * s, 0, 0.46 * s, 0.54 * s, 0.46 * s, "body") }
	local leaves = {
		{ 0, 0, 0.5 },
		{ 0.13, 0, 0.36 },
		{ -0.13, 0, 0.34 },
		{ 0, 0.13, 0.4 },
		{ 0, -0.13, 0.32 },
		{ 0.2, 0.2, 0.22 },
		{ -0.2, -0.2, 0.24 },
		{ 0.2, -0.2, 0.2 },
		{ -0.2, 0.2, 0.26 },
	}
	for _, l in leaves do
		local h = l[3] * s
		table.insert(p, B(edge(l[1] * s), 1.06 * s + h / 2, edge(l[2] * s), VOX * 0.95, h / 2, VOX * 0.95, "leaf"))
	end
	return p
end

SHAPES.melon = function(d)
	local s = d.s
	return {
		E(0, 0.62 * s, 0, 0.66 * s, 0.62 * s, 0.66 * s, "body"),
		dot(0, 1.25 * s, 0, "stem"),
	}
end

SHAPES.watermelon = function(d)
	local s = d.s
	return { E(0, 0.54 * s, 0, 0.76 * s, 0.54 * s, 0.6 * s, "body") }
end

SHAPES.dragon = function(d)
	local s = d.s
	local p = { E(0, 0.56 * s, 0, 0.5 * s, 0.56 * s, 0.48 * s, "body") }
	for _, n in fib(16) do
		if n.Y > -0.6 then
			local c = Vector3.new(n.X * 0.52 * s, 0.56 * s + n.Y * 0.58 * s, n.Z * 0.5 * s)
			table.insert(p, dot(c.X, c.Y, c.Z, "body"))
			local t = c + Vector3.new(n.X, math.max(n.Y, 0.3), n.Z).Unit * 0.13
			table.insert(p, dot(t.X, t.Y, t.Z, "tip"))
		end
	end
	table.insert(p, E(edge(0), edge(1.16 * s), edge(0), 0.16, VOX * 1.0, 0.16, "tip"))
	return p
end

SHAPES.star = function(d)
	local s = d.s
	return {
		F(0, 0.46 * s, 0, 0.72 * s, 0.46 * s, 0.46 * s, "body", function(v: Vector3): boolean
			local r = math.sqrt(v.Y * v.Y + v.Z * v.Z)
			local a = math.atan2(v.Z, v.Y)
			local star = 0.2 * s + 0.26 * s * ((math.cos(5 * a) + 1) / 2) ^ 1.5
			local taper = 1 - (math.abs(v.X) / (0.72 * s)) ^ 2 * 0.55
			return r <= star * taper
		end),
		dot(-0.74 * s, 0.46 * s, 0, "stem"),
	}
end

SHAPES.teardrop = function(d) -- figue, salak, phoenix
	local s = d.s
	return {
		E(0, 0.44 * s, 0, 0.5 * s, 0.44 * s, 0.5 * s, "body"),
		F(0, 0.95 * s, 0, 0.32 * s, 0.3 * s, 0.32 * s, "body", function(v: Vector3): boolean
			local t = (v.Y + 0.3 * s) / (0.6 * s)
			local rr = 0.32 * s * (1 - t) + 0.05
			return v.X * v.X + v.Z * v.Z <= rr * rr
		end),
		B(edge(0), 1.3 * s, edge(0), VOX * 0.95, 0.08, VOX * 0.95, "stem"),
	}
end

SHAPES.spiky = function(d) -- ramboutan (poils), durian (piques), kiwano (cornes)
	local s = d.s
	local p = { E(0, 0.55 * s, 0, 0.5 * s, 0.5 * s, 0.5 * s, "body") }
	for _, n in fib(d.count or 26) do
		if n.Y > -0.7 then
			local base = Vector3.new(0, 0.55 * s, 0) + n * 0.52 * s
			local tip = base + n * 0.17
			table.insert(p, dot(base.X, base.Y, base.Z, "spike"))
			table.insert(p, dot(tip.X, tip.Y, tip.Z, "tip"))
		end
	end
	return p
end

SHAPES.hand = function(d) -- main de Bouddha
	local s = d.s
	local p = { E(0, 0.32 * s, 0, 0.46 * s, 0.32 * s, 0.4 * s, "body") }
	local fingers = { { 0.3, 0, 0.5 }, { 0.15, 0.22, 0.6 }, { -0.12, 0.25, 0.55 }, { -0.3, 0.02, 0.45 }, { -0.1, -0.24, 0.5 }, { 0.16, -0.22, 0.62 } }
	for _, f in fingers do
		local h = f[3] * s
		table.insert(p, E(f[1] * s, 0.45 * s + h / 2, f[2] * s, 0.11 * s, h / 2 + 0.1, 0.11 * s, "body"))
	end
	return p
end

SHAPES.cube = function(d) -- "404 Fruit" : un cube a texture manquante
	local s = d.s
	return {
		B(edge(0), 0.54 * s, edge(0), 0.48 * s, 0.48 * s, 0.48 * s, "body"),
		B(edge(0), 1.08 * s, edge(0), VOX * 0.95, 0.1, VOX * 0.95, "stem"),
	}
end

SHAPES.heart = function(d)
	local s = d.s
	return {
		E(0.25 * s, 0.82 * s, 0, 0.32 * s, 0.32 * s, 0.3 * s, "body"),
		E(-0.25 * s, 0.82 * s, 0, 0.32 * s, 0.32 * s, 0.3 * s, "body"),
		F(0, 0.42 * s, 0, 0.56 * s, 0.42 * s, 0.32 * s, "body", function(v: Vector3): boolean
			local t = (v.Y + 0.42 * s) / (0.84 * s)
			return math.abs(v.X) <= 0.56 * s * t + 0.04 and math.abs(v.Z) <= 0.3 * s * (0.45 + 0.55 * t)
		end),
		B(edge(0), 1.12 * s, edge(0), VOX * 0.95, 0.12, VOX * 0.95, "stem"),
	}
end

SHAPES.infinity = function(d)
	local s = d.s
	return {
		E(0.4 * s, 0.46 * s, 0, 0.42 * s, 0.44 * s, 0.4 * s, "body"),
		E(-0.4 * s, 0.46 * s, 0, 0.42 * s, 0.44 * s, 0.4 * s, "body"),
		E(0, 0.46 * s, 0, 0.25 * s, 0.2 * s, 0.2 * s, "body"),
	}
end

SHAPES.pod = function(d) -- ackee : cosse rouge ouverte, chair jaune, graines noires
	local s = d.s
	local p = {
		E(0, 0.5 * s, 0, 0.52 * s, 0.5 * s, 0.52 * s, "body"),
		B(0, 1.05 * s, 0, 0.6 * s, 0.25 * s, 0.6 * s, "carve"),
		E(0, 0.62 * s, 0, 0.36 * s, 0.32 * s, 0.36 * s, "flesh"),
	}
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		table.insert(p, E(math.cos(a) * 0.16 * s, 0.9 * s, math.sin(a) * 0.16 * s, 0.12, 0.12, 0.12, "seed"))
	end
	return p
end

SHAPES.cluster = function(d) -- jabuticaba : 3 baies collees
	local s = d.s
	local p: { Prim } = {}
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		table.insert(p, E(math.cos(a) * 0.28 * s, 0.32 * s, math.sin(a) * 0.28 * s, 0.32 * s, 0.32 * s, 0.32 * s, "body"))
	end
	table.insert(p, E(0, 0.75 * s, 0, 0.3 * s, 0.3 * s, 0.3 * s, "body"))
	table.insert(p, dot(0, 1.08 * s, 0, "stem"))
	return p
end

------------------------------------------------------------------------------------------------
-- Ajouts : aureole, ailes, corne, anneau, couronne, rayons (fruits rares)
------------------------------------------------------------------------------------------------

local function addExtras(p: { Prim }, d: Def)
	local s = d.s
	for _, extra in d.extras do
		if extra == "halo" then
			table.insert(p, F(0, edge(1.5), 0, 0.46, VOX * 1.0, 0.46, "halo", function(v: Vector3): boolean
				local r = math.sqrt(v.X * v.X + v.Z * v.Z)
				return r >= 0.26 and r <= 0.44
			end))
		elseif extra == "wings" then
			for _, side in { 1, -1 } do
				table.insert(p, F(side * 0.72, 0.85, edge(0), 0.34, 0.26, VOX * 1.0, "wing", function(v: Vector3): boolean
					-- aile en goutte : plus large vers le haut et l'exterieur
					local x = v.X * side / 0.34
					local y = v.Y / 0.26
					return x * x + y * y <= 1 and y > -0.9 + (x + 1) * 0.35
				end))
			end
		elseif extra == "horn" then
			table.insert(p, F(edge(0), 1.24 * s, edge(0), 0.14, 0.26, 0.14, "horn", function(v: Vector3): boolean
				local t = (v.Y + 0.26) / 0.52
				local rr = 0.13 * (1 - t) + 0.03
				return v.X * v.X + v.Z * v.Z <= rr * rr
			end))
		elseif extra == "ring" then
			table.insert(p, F(0, edge(0.58 * s), 0, 0.98, VOX * 1.0, 0.98, "ring", function(v: Vector3): boolean
				local r = math.sqrt(v.X * v.X + v.Z * v.Z)
				return r >= 0.72 and r <= 0.96
			end))
		elseif extra == "crown" then
			local y0 = 1.06 * s
			table.insert(p, F(0, y0 + 0.08, 0, 0.36, 0.08, 0.36, "crown", function(v: Vector3): boolean
				local r = math.sqrt(v.X * v.X + v.Z * v.Z)
				return r >= 0.18 and r <= 0.34
			end))
			for i = 0, 4 do
				local a = i / 5 * math.pi * 2
				local x, z = math.cos(a) * 0.28, math.sin(a) * 0.28
				table.insert(p, B(edge(x), y0 + 0.3, edge(z), VOX * 0.95, 0.1, VOX * 0.95, "crown"))
				table.insert(p, dot(x, y0 + 0.12, z, "gem"))
			end
		elseif extra == "rays" then
			for i = 0, 7 do
				local a = i / 8 * math.pi * 2
				local n = Vector3.new(math.cos(a), 0, math.sin(a))
				local c = Vector3.new(0, 0.58 * s, 0)
				table.insert(p, dot(c.X + n.X * 0.66 * s, c.Y, c.Z + n.Z * 0.66 * s, "ray"))
				table.insert(p, dot(c.X + n.X * 0.78 * s, c.Y, c.Z + n.Z * 0.78 * s, "ray"))
			end
		elseif extra == "pomcrown" then -- couronne de grenade
			for i = 0, 5 do
				local a = i / 6 * math.pi * 2
				local x, z = math.cos(a) * 0.14, math.sin(a) * 0.14
				table.insert(p, B(edge(x), 1.2 * s, edge(z), VOX * 0.95, 0.1, VOX * 0.95, "crown"))
			end
		elseif extra == "calyx" then -- mangoustan : grosse couronne verte
			for i = 0, 3 do
				local a = i / 4 * math.pi * 2 + 0.4
				table.insert(p, E(math.cos(a) * 0.2 * s, edge(1.0 * s), math.sin(a) * 0.2 * s, 0.17 * s, VOX * 1.0, 0.17 * s, "leaf"))
			end
			table.insert(p, B(edge(0), 1.12 * s, edge(0), VOX * 0.95, 0.1, VOX * 0.95, "stem"))
		elseif extra == "eyes" then -- noix de coco
			for i = 0, 2 do
				local a = i / 3 * math.pi * 2
				table.insert(p, dot(math.cos(a) * 0.12, 1.12 * d.s, math.sin(a) * 0.12, "eye"))
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Couleurs : ombrage 3 tons + reflet, motifs du corps
------------------------------------------------------------------------------------------------

local ROLE_DEFAULTS: { [string]: Color3 } = {
	stem = rgb(105, 70, 40),
	leaf = rgb(70, 175, 55),
	tip = rgb(95, 60, 30),
	crown = rgb(40, 40, 110),
	spike = rgb(120, 140, 50),
	flesh = rgb(255, 220, 90),
	seed = rgb(25, 20, 20),
	halo = rgb(255, 215, 60),
	wing = rgb(250, 250, 255),
	horn = rgb(255, 210, 70),
	ring = rgb(230, 200, 140),
	gem = rgb(230, 30, 60),
	ray = rgb(255, 230, 80),
	eye = rgb(60, 35, 20),
}

local function frac(x: number): number
	return x - math.floor(x)
end

-- Garde des couleurs franches (moins de couleurs = moins de blocs apres fusion).
local function quant(c: Color3): Color3
	local function q(v: number): number
		return math.floor(v * 255 / 6 + 0.5) * 6 / 255
	end
	return Color3.new(math.clamp(q(c.R), 0, 1), math.clamp(q(c.G), 0, 1), math.clamp(q(c.B), 0, 1))
end

local function tone(c: Color3, level: number): Color3
	-- level : -1 sombre, 0 normal, 1 clair, 2 reflet
	if level <= -1 then
		return c:Lerp(BLACK, 0.26)
	elseif level == 1 then
		return c:Lerp(WHITE, 0.2)
	elseif level >= 2 then
		return c:Lerp(WHITE, 0.6)
	end
	return c
end

type Ctx = {
	def: Def,
	rng: Random,
	cy: number, -- centre vertical du corps
	y0: number, -- bas du corps
	y1: number, -- haut du corps
	spots: { Vector3 },
}

-- Couleur de base d'un cube du corps selon le motif (avant ombrage). Renvoie aussi `flat`
-- (pas d'ombrage : lave, pixels, etoiles...).
local function bodyColor(ctx: Ctx, p: Vector3, n: Vector3, i: number, j: number, k: number): (Color3, boolean)
	local d = ctx.def
	local body = d.body
	local acc = d.accent or body:Lerp(BLACK, 0.3)
	local acc2 = d.accent2 or acc
	local pat = d.pattern
	local rng = ctx.rng
	local t = math.clamp((p.Y - ctx.y0) / math.max(ctx.y1 - ctx.y0, 0.01), 0, 1)

	if pat == "speckle" then
		if rng:NextNumber() < (d.density or 0.1) * 0.7 then
			return acc, false
		end
	elseif pat == "stripes" then -- rayures dans la longueur (pasteque)
		local a = math.atan2(p.Z, p.Y - ctx.cy)
		local band = a / (2 * math.pi) * (d.count or 8) + math.sin(p.X * 7) * 0.22
		if math.floor(band) % 2 == 0 then
			return acc, false
		end
	elseif pat == "net" then -- filet du melon
		local u = p.X * 4.5 + math.sin(p.Y * 7) * 0.5
		local v = p.Z * 4.5 + math.sin(p.Y * 6 + 1) * 0.5
		if math.abs(frac(u) - 0.5) < 0.13 or math.abs(frac(v) - 0.5) < 0.13 then
			return acc, false
		end
	elseif pat == "diamond" then -- ananas, salak, cherimole
		local a = math.atan2(p.Z, p.X)
		local u = a / (2 * math.pi) * (d.count or 8) + p.Y * 3.2
		local v = a / (2 * math.pi) * (d.count or 8) - p.Y * 3.2
		if frac(u) < 0.2 or frac(v) < 0.2 then
			return acc, false
		end
	elseif pat == "blush" then -- joue rouge d'un cote
		if n:Dot(Vector3.new(0.6, 0.3, 0.75).Unit) + (rng:NextNumber() - 0.5) * 0.35 > 0.3 then
			return acc, false
		end
	elseif pat == "gradient" then -- bas = body, milieu = accent, haut = accent2
		local tt = t + (rng:NextNumber() - 0.5) * 0.12
		if tt < 0.4 then
			return body, false
		elseif tt < 0.72 then
			return acc, false
		end
		return acc2, false
	elseif pat == "fire" then
		local tt = t + (rng:NextNumber() - 0.5) * 0.25
		if tt < 0.35 then
			return acc2, true
		elseif tt < 0.7 then
			return body, true
		end
		return acc, true
	elseif pat == "spots" then
		for _, sp in ctx.spots do
			if n:Dot(sp) > (d.density or 0.93) then
				return acc, false
			end
		end
	elseif pat == "cracks" then -- fissures de lave lumineuses
		local a = math.abs(math.sin(p.X * 9 + math.sin(p.Z * 7) * 1.3 + p.Y * 3))
		local b = math.abs(math.sin(p.Z * 8 + math.sin(p.X * 6) * 1.2 - p.Y * 4))
		if a < 0.16 or b < 0.14 then
			return acc, true
		end
		return body, false
	elseif pat == "stars" then
		local r = rng:NextNumber()
		if r < (d.density or 0.07) then
			return acc, true
		elseif r < (d.density or 0.07) * 1.6 then
			return acc2, true
		end
	elseif pat == "glitch" then
		local h = (math.floor(j / 2) * 7 + math.floor(i / 3) * 3 + math.floor(k / 2)) % 9
		local r = rng:NextNumber()
		if h == 0 or r < 0.1 then
			return acc, true
		elseif h == 4 or r < 0.16 then
			return acc2, true
		elseif r < 0.2 then
			return BLACK, true
		end
	elseif pat == "checker" then -- texture manquante
		if (math.floor(i / 3) + math.floor(j / 3) + math.floor(k / 3)) % 2 == 0 then
			return acc, true
		end
		return body, true
	elseif pat == "static" then -- neige de tele
		local r = rng:NextNumber()
		return body:Lerp(acc, math.floor(r * 4) / 3), true
	elseif pat == "binary" then
		if rng:NextNumber() < 0.3 then
			return acc, true
		end
		return body, true
	elseif pat == "rainbow" then
		local hue = frac(p.Y * 0.85 + math.atan2(p.Z, p.X) / (2 * math.pi) * 0.5)
		hue = math.floor(hue * 7) / 7
		return Color3.fromHSV(hue, 0.72, 1), false
	elseif pat == "zigzag" then -- eclairs
		local a = math.atan2(p.Z, p.X) / (2 * math.pi) * 4
		local z = a + math.abs(frac(p.Y * 3) - 0.5) * 0.8
		if math.abs(frac(z) - 0.5) < 0.08 then
			return acc, true
		end
	elseif pat == "half" then
		if p.X > 0.02 then
			return acc, false
		end
	elseif pat == "rim" then -- eclipse : bord dore du cote de la lumiere
		if n:Dot(LIGHT) > 0.55 then
			return acc, true
		end
		return body, false
	elseif pat == "radial" then -- big bang
		local r = n:Dot(Vector3.new(0.3, 0.9, 0.3).Unit)
		if r > 0.75 then
			return acc2, true
		elseif r > 0.35 then
			return acc, true
		end
	elseif pat == "equator" then
		if math.abs(p.Y - ctx.cy) < 0.1 then
			return acc, false
		end
	elseif pat == "swirl" then
		local a = math.atan2(p.Z, p.X) + p.Y * 4
		if math.abs(frac(a / (2 * math.pi) * 3) - 0.5) < 0.16 then
			return acc, true
		end
	end
	return body, false
end

------------------------------------------------------------------------------------------------
-- Construction d'un fruit
------------------------------------------------------------------------------------------------

local function key(i: number, j: number, k: number): number
	return ((i + 128) * 256 + (j + 128)) * 256 + (k + 128)
end

type Vox = { i: number, j: number, k: number, role: string }

local function rasterize(prims: { Prim }): ({ [number]: Vox }, number, number, number, number, number, number)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, pr in prims do
		if pr.role ~= "carve" then
			mn = mn:Min(pr.c - pr.r)
			mx = mx:Max(pr.c + pr.r)
		end
	end
	local i0, i1 = math.floor(mn.X / VOX) - 1, math.ceil(mx.X / VOX) + 1
	local j0, j1 = math.max(0, math.floor(mn.Y / VOX) - 1), math.ceil(mx.Y / VOX) + 1
	local k0, k1 = math.floor(mn.Z / VOX) - 1, math.ceil(mx.Z / VOX) + 1
	local grid: { [number]: Vox } = {}
	for i = i0, i1 do
		for j = j0, j1 do
			for k = k0, k1 do
				local p = Vector3.new((i + 0.5) * VOX, (j + 0.5) * VOX, (k + 0.5) * VOX)
				local role: string? = nil
				for _, pr in prims do
					if inside(pr, p) then
						role = if pr.role == "carve" then nil else pr.role
					end
				end
				if role then
					grid[key(i, j, k)] = { i = i, j = j, k = k, role = role }
				end
			end
		end
	end
	return grid, i0, i1, j0, j1, k0, k1
end

-- Normale approchee : somme des directions vers les cases vides autour (rayon 2).
local function normalAt(grid: { [number]: Vox }, v: Vox): Vector3
	local sum = Vector3.zero
	for di = -2, 2 do
		for dj = -2, 2 do
			for dk = -2, 2 do
				if (di ~= 0 or dj ~= 0 or dk ~= 0) and grid[key(v.i + di, v.j + dj, v.k + dk)] == nil then
					local off = Vector3.new(di, dj, dk)
					sum += off / off.Magnitude ^ 2
				end
			end
		end
	end
	return if sum.Magnitude > 1e-3 then sum.Unit else Vector3.yAxis
end

local function isSurface(grid: { [number]: Vox }, v: Vox): boolean
	return grid[key(v.i + 1, v.j, v.k)] == nil
		or grid[key(v.i - 1, v.j, v.k)] == nil
		or grid[key(v.i, v.j + 1, v.k)] == nil
		or grid[key(v.i, v.j - 1, v.k)] == nil
		or grid[key(v.i, v.j, v.k + 1)] == nil
		or grid[key(v.i, v.j, v.k - 1)] == nil
end

local function buildFruit(d: Def): (UnionOperation?, string)
	local prims = SHAPES[d.shape](d)
	addExtras(prims, d)
	local grid, i0, i1, j0, j1, k0, k1 = rasterize(prims)

	-- Glitch : decale certaines couches d'un cube (fruit "qui bugue")
	if d.shift then
		local shifted: { [number]: Vox } = {}
		for _, v in grid do
			local band = math.floor(v.j / 2)
			local off = if band % 4 == 1 then 2 elseif band % 5 == 3 then -2 else 0
			local nv = { i = v.i + off, j = v.j, k = v.k, role = v.role }
			shifted[key(nv.i, nv.j, nv.k)] = nv
		end
		grid = shifted
		i0 -= 2
		i1 += 2
	end

	-- Bornes du corps (pour les degrades)
	local y0, y1 = math.huge, -math.huge
	local sumY, nY = 0, 0
	for _, v in grid do
		if v.role == "body" then
			local y = (v.j + 0.5) * VOX
			y0 = math.min(y0, y)
			y1 = math.max(y1, y)
			sumY += y
			nY += 1
		end
	end
	local seed = 0
	for c = 1, #d.id do
		seed = (seed * 31 + string.byte(d.id, c)) % 2147483647
	end
	local ctx: Ctx = {
		def = d,
		rng = Random.new(seed),
		cy = if nY > 0 then sumY / nY else 0.5,
		y0 = y0,
		y1 = y1,
		spots = {},
	}
	local spotRng = Random.new(seed + 7)
	for _ = 1, d.count or 6 do
		table.insert(ctx.spots, spotRng:NextUnitVector())
	end

	-- Couleur de chaque cube
	local colors: { [number]: Color3 } = {}
	-- parcours dans un ordre fixe (meme resultat a chaque construction)
	for i = i0, i1 do
		for j = j0, j1 do
			for k = k0, k1 do
				local kk = key(i, j, k)
				local v = grid[kk]
				if v == nil then
					continue
				end
				if not isSurface(grid, v) then
					colors[kk] = d.body -- interieur (invisible)
					continue
				end
				local p = Vector3.new((i + 0.5) * VOX, (j + 0.5) * VOX, (k + 0.5) * VOX)
				local n = normalAt(grid, v)
				local base: Color3
				local flat = false
				if v.role == "body" then
					base, flat = bodyColor(ctx, p, n, i, j, k)
					if d.crease and math.abs(p.Z) < VOX and p.X > 0 and n.Y < 0.85 then
						base = base:Lerp(BLACK, 0.22)
						flat = true
					end
					if d.shape == "kiwi" and n.Y > 0.7 then
						-- face coupee : peau au bord, chair, anneau de graines, coeur clair
						local r = math.sqrt(p.X * p.X / 1.0 + p.Z * p.Z / 0.75)
						local rs = d.s
						local skin = d.roles.skin or rgb(140, 100, 55)
						if r > 0.47 * rs then
							base = skin
						elseif r < 0.12 * rs then
							base = d.roles.core or rgb(245, 240, 200)
						elseif r < 0.27 * rs and r > 0.16 * rs and (i + k) % 2 == 0 then
							base = d.roles.seed or rgb(25, 20, 20)
						else
							base = d.roles.flesh or rgb(130, 200, 50)
						end
						if ctx.rng:NextNumber() < 0.08 then
							base = base:Lerp(WHITE, 0.12)
						end
						flat = true
					end
				else
					base = d.roles[v.role] or ROLE_DEFAULTS[v.role] or d.body
				end
				local c = base
				if not flat then
					local l = n:Dot(LIGHT)
					local level = if l > 0.5 then 1 elseif l < -0.25 then -1 else 0
					local r = ctx.rng:NextNumber()
					if r < 0.03 then
						level = if level == 0 then (if r < 0.015 then 1 else -1) else 0
					end
					if l > 0.9 and v.role == "body" and r > 0.5 then
						level = 2
					end
					c = tone(base, level)
				end
				colors[kk] = quant(c)
			end
		end
	end

	-- Fusion des cubes de meme couleur en blocs (x puis z puis y)
	local used: { [number]: boolean } = {}
	local blocks: { Part } = {}
	local function same(i: number, j: number, k: number, hex: string): boolean
		local kk = key(i, j, k)
		local c = colors[kk]
		return c ~= nil and not used[kk] and c:ToHex() == hex
	end
	for j = j0, j1 do
		for k = k0, k1 do
			for i = i0, i1 do
				local kk = key(i, j, k)
				local c = colors[kk]
				if c == nil or used[kk] then
					continue
				end
				local hex = c:ToHex()
				local w = 1
				while same(i + w, j, k, hex) do
					w += 1
				end
				local dz = 1
				while true do
					local ok = true
					for x = i, i + w - 1 do
						if not same(x, j, k + dz, hex) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					dz += 1
				end
				local h = 1
				while true do
					local ok = true
					for x = i, i + w - 1 do
						for z = k, k + dz - 1 do
							if not same(x, j + h, z, hex) then
								ok = false
								break
							end
						end
						if not ok then
							break
						end
					end
					if not ok then
						break
					end
					h += 1
				end
				for x = i, i + w - 1 do
					for y = j, j + h - 1 do
						for z = k, k + dz - 1 do
							used[key(x, y, z)] = true
						end
					end
				end
				local part = Instance.new("Part")
				part.Anchored = true
				part.Material = Enum.Material.SmoothPlastic
				part.Color = c
				part.Size = Vector3.new(w * VOX, h * VOX, dz * VOX) * SCALE
				part.CFrame = CFrame.new(Vector3.new((i + w / 2) * VOX, (j + h / 2) * VOX, (k + dz / 2) * VOX) * SCALE)
				table.insert(blocks, part)
			end
		end
	end

	if #blocks == 0 then
		return nil, "aucun cube"
	end
	local first = table.remove(blocks, 1) :: Part
	local ok, result = pcall(function()
		return GeometryService:UnionAsync(first, blocks, {
			SplitApart = false,
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	local count = #blocks + 1
	first:Destroy()
	for _, b in blocks do
		b:Destroy()
	end
	if not ok or result == nil or result[1] == nil then
		return nil, "UnionAsync : " .. tostring(result)
	end
	local union = result[1] :: UnionOperation
	union.Name = d.id
	union.UsePartColor = false
	union.Anchored = true
	union.CanCollide = false
	union.CanQuery = false
	union.CanTouch = false
	union.CastShadow = false
	union.Material = Enum.Material.SmoothPlastic
	-- Pivot = origine du dessin = centre-bas du fruit
	union.PivotOffset = union.CFrame:Inverse()
	union:SetAttribute("FruitId", d.id)
	union:SetAttribute("BodyColor", d.body)
	return union, `{count} blocs, {union.TriangleCount} triangles`
end

------------------------------------------------------------------------------------------------
-- Les 100 fruits : forme, couleurs, motif
------------------------------------------------------------------------------------------------

type Opts = {
	s: number?,
	accent: Color3?,
	accent2: Color3?,
	pattern: string?,
	density: number?,
	count: number?,
	crease: boolean?,
	shift: boolean?,
	roles: { [string]: Color3 }?,
	extras: { string }?,
}

local DEFS: { [string]: Def } = {}
local function def(id: string, shape: string, body: Color3, o: Opts?)
	local opts: Opts = o or {}
	DEFS[id] = {
		id = id,
		shape = shape,
		s = opts.s or 1,
		body = body,
		accent = opts.accent,
		accent2 = opts.accent2,
		pattern = opts.pattern,
		density = opts.density,
		count = opts.count,
		crease = opts.crease,
		shift = opts.shift,
		roles = opts.roles or {},
		extras = opts.extras or {},
	}
end

local GOLD, GOLD_D = rgb(255, 200, 40), rgb(215, 140, 20)
local GLEAF = rgb(250, 220, 110)

-- Common
def("Apple", "apple", rgb(222, 36, 40), { pattern = "speckle", accent = rgb(240, 95, 80), density = 0.05 })
def("Orange", "round", rgb(255, 140, 18), { pattern = "speckle", accent = rgb(226, 112, 10), density = 0.14 })
def("Banana", "banana", rgb(255, 222, 50), { roles = { tip = rgb(90, 60, 30), stem = rgb(120, 140, 50) } })
def("Pear", "pear", rgb(186, 212, 72), { pattern = "speckle", accent = rgb(150, 160, 60), density = 0.07 })
def("Lemon", "lemon", rgb(255, 236, 44), { pattern = "speckle", accent = rgb(236, 206, 20), density = 0.1 })
def("Lime", "lemon", rgb(104, 200, 40), { s = 0.85, pattern = "speckle", accent = rgb(80, 165, 30), density = 0.1 })
def("Grape", "grapes", rgb(124, 46, 168), { roles = { leaf = rgb(80, 165, 60) } })
def("Plum", "plum", rgb(112, 36, 112), { pattern = "speckle", accent = rgb(150, 90, 165), density = 0.08, crease = true })
def("Peach", "peach", rgb(255, 178, 122), { pattern = "blush", accent = rgb(240, 96, 84), crease = true })
def("Apricot", "peach", rgb(255, 162, 52), { s = 0.86, pattern = "blush", accent = rgb(236, 110, 40), crease = true })

-- Uncommon
def("Strawberry", "strawberry", rgb(235, 36, 56), { pattern = "speckle", accent = rgb(255, 228, 110), density = 0.16 })
def("Cherry", "cherry", rgb(192, 16, 42), { roles = { stem = rgb(90, 120, 40) } })
def("Blueberry", "berry", rgb(62, 76, 200), { pattern = "speckle", accent = rgb(122, 140, 230), density = 0.1, roles = { crown = rgb(30, 34, 110) } })
def("Raspberry", "drupe", rgb(220, 30, 96), { roles = { leaf = rgb(90, 160, 60) } })
def("Kiwi", "kiwi", rgb(140, 100, 55), { pattern = "speckle", accent = rgb(110, 76, 40), density = 0.2 })
def("Pineapple", "pineapple", rgb(242, 190, 40), { pattern = "diamond", accent = rgb(190, 120, 30), roles = { leaf = rgb(60, 160, 60) } })
def("Mango", "oval", rgb(130, 185, 45), { pattern = "gradient", accent = rgb(255, 190, 40), accent2 = rgb(240, 92, 50) })
def("Coconut", "melon", rgb(120, 76, 40), { s = 0.88, pattern = "speckle", accent = rgb(160, 110, 62), density = 0.22, extras = { "eyes" } })
def("Melon", "melon", rgb(196, 202, 122), { pattern = "net", accent = rgb(238, 232, 192) })
def("Watermelon", "watermelon", rgb(36, 128, 52), { pattern = "stripes", accent = rgb(122, 200, 82), count = 9 })

-- Rare
def("DragonFruit", "dragon", rgb(255, 62, 152), { roles = { tip = rgb(130, 205, 60) } })
def("StarFruit", "star", rgb(255, 214, 50))
def("Lychee", "round", rgb(226, 62, 72), { s = 0.85, pattern = "speckle", accent = rgb(170, 30, 45), density = 0.3 })
def("PassionFruit", "round", rgb(112, 46, 122), { s = 0.92, pattern = "speckle", accent = rgb(172, 122, 182), density = 0.09 })
def("Papaya", "oval", rgb(120, 175, 50), { s = 1.15, pattern = "gradient", accent = rgb(255, 170, 40), accent2 = rgb(255, 130, 40) })
def("Pomegranate", "round", rgb(192, 26, 46), { pattern = "speckle", accent = rgb(150, 20, 40), density = 0.06, extras = { "pomcrown" }, roles = { crown = rgb(150, 22, 36) } })
def("Guava", "pear", rgb(152, 206, 92), { s = 0.92, pattern = "speckle", accent = rgb(110, 165, 60), density = 0.1 })
def("Fig", "teardrop", rgb(112, 52, 102), { pattern = "speckle", accent = rgb(150, 92, 140), density = 0.1 })
def("Rambutan", "spiky", rgb(230, 40, 52), { count = 34, roles = { spike = rgb(200, 30, 40), tip = rgb(130, 185, 60) } })
def("Durian", "spiky", rgb(152, 172, 62), { s = 1.08, count = 30, roles = { spike = rgb(120, 140, 45), tip = rgb(90, 105, 35) } })

-- Epic
def("Mangosteen", "round", rgb(92, 26, 72), { pattern = "speckle", accent = rgb(130, 50, 100), density = 0.08, extras = { "calyx" }, roles = { leaf = rgb(90, 145, 60) } })
def("Jabuticaba", "cluster", rgb(52, 22, 62), { pattern = "speckle", accent = rgb(110, 60, 130), density = 0.08 })
def("Cherimoya", "heart", rgb(152, 192, 92), { pattern = "diamond", accent = rgb(105, 145, 60), count = 10 })
def("SnakeFruit", "teardrop", rgb(120, 56, 32), { pattern = "diamond", accent = rgb(70, 30, 20), count = 12 })
def("HornedMelon", "spiky", rgb(255, 152, 34), { count = 18, pattern = "speckle", accent = rgb(255, 200, 80), density = 0.15, roles = { spike = rgb(255, 190, 70), tip = rgb(255, 235, 170) } })
def("BuddhasHand", "hand", rgb(255, 220, 64), { pattern = "speckle", accent = rgb(240, 196, 40), density = 0.1 })
def("MiracleBerry", "plum", rgb(212, 22, 42), { s = 0.8, roles = { stem = rgb(80, 130, 50) } })
def("Cloudberry", "drupe", rgb(250, 160, 62))
def("FingerLime", "oval", rgb(80, 122, 42), { s = 1.2, count = 0.62, pattern = "speckle", accent = rgb(120, 160, 60), density = 0.12 })
def("Ackee", "pod", rgb(222, 42, 32), { roles = { flesh = rgb(255, 230, 120) } })

-- Legendary : versions en metal ou en pierre precieuse
def("GoldenApple", "apple", GOLD, { pattern = "speckle", accent = rgb(255, 236, 140), density = 0.08, roles = { leaf = GLEAF, stem = GOLD_D } })
def("DiamondPear", "pear", rgb(170, 236, 255), { pattern = "diamond", accent = rgb(235, 252, 255), count = 6, roles = { leaf = rgb(120, 220, 255), stem = rgb(150, 200, 230) } })
def("RubyCherry", "cherry", rgb(225, 20, 62), { pattern = "speckle", accent = rgb(255, 120, 150), density = 0.12, roles = { stem = GOLD_D, leaf = GLEAF } })
def("EmeraldKiwi", "kiwi", rgb(30, 120, 70), { pattern = "speckle", accent = rgb(20, 90, 50), density = 0.2, roles = { skin = rgb(30, 120, 70), flesh = rgb(40, 210, 110), seed = rgb(10, 60, 30), core = rgb(200, 255, 220) } })
def("SapphireBerry", "berry", rgb(40, 82, 232), { pattern = "speckle", accent = rgb(140, 180, 255), density = 0.12, roles = { crown = GOLD_D } })
def("CrystalGrape", "grapes", rgb(202, 152, 255), { pattern = "speckle", accent = rgb(240, 225, 255), density = 0.15, roles = { leaf = rgb(170, 240, 255), stem = rgb(150, 120, 200) } })
def("PearlCoconut", "melon", rgb(246, 240, 236), { s = 0.88, pattern = "speckle", accent = rgb(255, 205, 225), accent2 = rgb(200, 235, 255), density = 0.12, extras = { "eyes" }, roles = { eye = rgb(220, 190, 200) } })
def("AmberPeach", "peach", rgb(255, 150, 20), { pattern = "blush", accent = rgb(220, 95, 10), crease = true, roles = { leaf = GLEAF } })
def("SilverPlum", "plum", rgb(200, 206, 218), { pattern = "speckle", accent = rgb(245, 248, 255), density = 0.1, crease = true, roles = { stem = rgb(130, 135, 150) } })
def("PlatinumBanana", "banana", rgb(226, 230, 238), { roles = { tip = rgb(150, 155, 170), stem = rgb(170, 175, 190) } })

-- Mythic : elements (feu, glace, foudre, lave...)
def("FireMango", "oval", rgb(255, 120, 20), { pattern = "fire", accent = rgb(255, 230, 60), accent2 = rgb(200, 30, 20), roles = { stem = rgb(60, 30, 20) } })
def("IceBerry", "berry", rgb(150, 222, 255), { pattern = "speckle", accent = rgb(250, 255, 255), density = 0.2, roles = { crown = rgb(90, 170, 230) } })
def("ThunderLemon", "lemon", rgb(255, 232, 40), { pattern = "zigzag", accent = rgb(90, 60, 170) })
def("LavaMelon", "melon", rgb(52, 36, 36), { pattern = "cracks", accent = rgb(255, 122, 20) })
def("StormGrape", "grapes", rgb(72, 82, 112), { pattern = "speckle", accent = rgb(185, 205, 255), density = 0.12, roles = { leaf = rgb(110, 120, 150) } })
def("ShadowPlum", "plum", rgb(32, 16, 46), { pattern = "speckle", accent = rgb(125, 52, 205), density = 0.12, roles = { stem = rgb(20, 10, 30) } })
def("FrostPeach", "peach", rgb(192, 236, 255), { pattern = "blush", accent = rgb(250, 255, 255), crease = true, roles = { leaf = rgb(140, 210, 240) } })
def("ToxicApple", "apple", rgb(124, 230, 40), { pattern = "spots", accent = rgb(40, 120, 20), count = 8, density = 0.9, roles = { leaf = rgb(150, 60, 170) } })
def("MagmaOrange", "round", rgb(90, 20, 16), { pattern = "cracks", accent = rgb(255, 160, 30), roles = { leaf = rgb(60, 40, 30) } })
def("VolcanoPineapple", "pineapple", rgb(60, 40, 36), { pattern = "diamond", accent = rgb(255, 110, 20), roles = { leaf = rgb(255, 80, 20) } })

-- Godly : creatures et lumiere
def("AngelApple", "apple", rgb(250, 250, 255), { pattern = "speckle", accent = rgb(255, 230, 150), density = 0.06, extras = { "halo", "wings" }, roles = { leaf = GLEAF, stem = GOLD_D } })
def("HolyGrape", "grapes", rgb(255, 244, 200), { pattern = "speckle", accent = rgb(255, 210, 80), density = 0.12, extras = { "halo" }, roles = { leaf = GLEAF } })
def("PhoenixFruit", "teardrop", rgb(255, 120, 20), { pattern = "fire", accent = rgb(255, 230, 60), accent2 = rgb(210, 30, 20), extras = { "wings" }, roles = { wing = rgb(255, 90, 20), stem = rgb(255, 210, 60) } })
def("DragonHeart", "heart", rgb(200, 20, 40), { pattern = "diamond", accent = rgb(130, 10, 25), count = 10 })
def("UnicornBerry", "berry", rgb(255, 225, 245), { pattern = "speckle", accent = rgb(150, 220, 255), accent2 = rgb(255, 160, 220), density = 0.18, extras = { "horn" }, roles = { crown = rgb(255, 170, 220) } })
def("KrakenMelon", "melon", rgb(86, 42, 128), { pattern = "spots", accent = rgb(255, 150, 200), count = 12, density = 0.94, roles = { stem = rgb(60, 30, 90) } })
def("TitanBanana", "banana", rgb(196, 152, 80), { s = 1.12, roles = { tip = rgb(110, 80, 40), stem = rgb(120, 90, 50) } })
def("GriffinPear", "pear", rgb(205, 152, 62), { pattern = "speckle", accent = rgb(150, 100, 40), density = 0.12, extras = { "wings" }, roles = { wing = rgb(250, 240, 220), leaf = GLEAF } })
def("PegasusPeach", "peach", rgb(255, 222, 236), { pattern = "blush", accent = rgb(255, 170, 205), crease = true, extras = { "wings" } })
def("HydraCherry", "cherry", rgb(36, 140, 112), { count = 3, pattern = "speckle", accent = rgb(20, 90, 70), density = 0.15, roles = { stem = rgb(30, 80, 60), leaf = rgb(40, 110, 80) } })

-- Celestial : lune, soleil, etoiles
def("MoonMelon", "melon", rgb(204, 208, 226), { pattern = "spots", accent = rgb(150, 155, 180), count = 9, density = 0.93 })
def("SunOrange", "round", rgb(255, 200, 40), { pattern = "speckle", accent = rgb(255, 240, 140), density = 0.12, extras = { "rays" } })
def("StarBerry", "star", rgb(255, 240, 150), { s = 0.9, pattern = "stars", accent = WHITE, accent2 = rgb(255, 200, 60), density = 0.1 })
def("CometCherry", "cherry", rgb(120, 200, 255), { pattern = "stars", accent = WHITE, accent2 = rgb(200, 240, 255), density = 0.1, roles = { stem = rgb(200, 240, 255) } })
def("MeteorMango", "oval", rgb(110, 80, 70), { pattern = "cracks", accent = rgb(255, 150, 40) })
def("NebulaGrape", "grapes", rgb(140, 60, 200), { pattern = "stars", accent = rgb(255, 150, 230), accent2 = WHITE, density = 0.12, roles = { leaf = rgb(90, 60, 170) } })
def("GalaxyPlum", "plum", rgb(26, 20, 62), { pattern = "stars", accent = WHITE, accent2 = rgb(170, 110, 255), density = 0.1 })
def("AuroraKiwi", "kiwi", rgb(30, 40, 80), { pattern = "stars", accent = WHITE, density = 0.08, roles = { skin = rgb(30, 40, 80), flesh = rgb(60, 230, 180), seed = rgb(170, 90, 255), core = rgb(200, 255, 250) } })
def("SaturnPeach", "peach", rgb(236, 200, 140), { pattern = "equator", accent = rgb(210, 160, 100), extras = { "ring" } })
def("EclipseApple", "apple", rgb(24, 22, 34), { pattern = "rim", accent = rgb(255, 196, 60), roles = { leaf = rgb(60, 50, 80) } })

-- Glitched : bugs, pixels, texture manquante
def("ErrorApple", "apple", rgb(222, 36, 40), { pattern = "glitch", accent = rgb(255, 40, 220), accent2 = rgb(40, 255, 240), shift = true })
def("PixelBerry", "berry", rgb(40, 230, 255), { pattern = "checker", accent = rgb(255, 50, 220) })
def("LagLemon", "lemon", rgb(255, 236, 44), { pattern = "glitch", accent = rgb(255, 40, 220), accent2 = rgb(60, 255, 120), shift = true })
def("BugBanana", "banana", rgb(255, 222, 50), { pattern = "glitch", accent = rgb(40, 255, 80), accent2 = BLACK, shift = true })
def("Fruit404", "cube", rgb(20, 20, 20), { pattern = "checker", accent = rgb(255, 0, 220) })
def("CorruptedGrape", "grapes", rgb(124, 46, 168), { pattern = "glitch", accent = rgb(40, 255, 120), accent2 = BLACK, shift = true })
def("NullMelon", "melon", rgb(30, 30, 34), { pattern = "static", accent = rgb(235, 235, 240) })
def("StaticCherry", "cherry", rgb(120, 120, 128), { pattern = "static", accent = rgb(245, 245, 250) })
def("BinaryMango", "oval", rgb(12, 24, 14), { pattern = "binary", accent = rgb(60, 255, 90) })
def("GlitchKiwi", "kiwi", rgb(140, 100, 55), { shift = true, roles = { flesh = rgb(255, 40, 220), seed = rgb(40, 255, 240), core = BLACK } })

-- Infinity
def("RainbowApple", "apple", rgb(255, 80, 80), { pattern = "rainbow" })
def("TimeBerry", "berry", rgb(60, 196, 222), { pattern = "equator", accent = GOLD, roles = { crown = GOLD } })
def("VoidFruit", "round", rgb(20, 8, 30), { pattern = "swirl", accent = rgb(160, 60, 255), roles = { leaf = rgb(90, 30, 140) } })
def("QuantumMango", "oval", rgb(40, 230, 255), { pattern = "half", accent = rgb(255, 50, 220) })
def("MultiverseMelon", "watermelon", rgb(255, 80, 80), { pattern = "rainbow" })
def("EternalPeach", "peach", rgb(255, 214, 196), { pattern = "stars", accent = GOLD, accent2 = WHITE, density = 0.08, crease = true, extras = { "halo" } })
def("BigBangBerry", "berry", rgb(255, 120, 30), { pattern = "radial", accent = rgb(255, 220, 60), accent2 = WHITE, roles = { crown = rgb(255, 255, 220) } })
def("OmegaFruit", "round", rgb(222, 60, 142), { pattern = "equator", accent = GOLD, extras = { "crown" }, roles = { crown = GOLD, leaf = GOLD } })
def("InfinityFruit", "infinity", rgb(180, 255, 255), { pattern = "rainbow" })
def("JuiceGodFruit", "apple", rgb(255, 196, 40), { s = 1.05, pattern = "speckle", accent = rgb(255, 240, 150), density = 0.1, extras = { "crown" }, roles = { crown = GOLD, leaf = GLEAF, stem = GOLD_D } })

------------------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------------------

local folder = ReplicatedStorage:FindFirstChild("FruitAssets")
if folder == nil then
	folder = Instance.new("Folder")
	folder.Name = "FruitAssets"
	folder.Parent = ReplicatedStorage
end
assert(folder, "FruitAssets introuvable")

local only: { [string]: boolean }? = nil
-- selene: allow(global_usage)
local onlyList = (_G :: any).FRUIT_ONLY
if type(onlyList) == "table" then
	only = {}
	for _, id in onlyList do
		(only :: any)[id] = true
	end
end

local report = {}
local built = 0
for _, fruit in Fruits.List do
	if only and not only[fruit.id] then
		continue
	end
	local d = DEFS[fruit.id]
	if d == nil then
		table.insert(report, fruit.id .. " : PAS DE DESSIN")
		continue
	end
	local t = os.clock()
	local ok, union, info = pcall(buildFruit, d)
	if ok and union then
		local old = folder:FindFirstChild(fruit.id)
		if old then
			old:Destroy()
		end
		union.Parent = folder
		built += 1
		table.insert(report, `{fruit.id} : {info} ({math.floor((os.clock() - t) * 1000)} ms)`)
	else
		table.insert(report, `{fruit.id} : ERREUR {if ok then info else union}`)
	end
	task.wait()
end

return `FruitAssets : {built} fruits construits\n` .. table.concat(report, "\n")
