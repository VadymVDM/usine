--!strict
-- Morceau 1 : l'usine. Depuis la tour d'etages (phase 1b, 2026-11-20), DEUX modeles :
--   ServerStorage.BaseTemplate  : ce qui n'existe qu'une fois par base (rez-de-chaussee) : terrain,
--     cour avant, annexe ouest (murs + sol ; contenu dans 02f), panneau du proprietaire, enseigne.
--   ServerStorage.FloorTemplate : UN etage, copie tous les 36 studs (FloorAssembly) : sol (dalle),
--     murs, piliers, poutres, lampes, zones. 02b ... 02h y ajoutent leur contenu.
--   Dossiers "Only<Tag>" = variantes gardees selon l'etage (Config/Floors.Tags), attribut Shell =
--   garde dans la coque bleue de l'etage ferme. Voir docs/systems/tour-etages.md.
-- Detruit et recree les deux modeles. Lancer ensuite 02b ... 02h dans l'ordre.
-- Repere local : origine = bord avant (cote route), au sol (y = 0). +Z = de la route vers le fond.
--   Terrain de la base : x -46 -> 110, z 0 -> 138, dessus a y = 0.3.
--   Salle principale (zone 1) : x 1 -> 109, z 15 -> 135, sol a y = 0.5. Murs de 36 de haut
--   (doubles le 2026-11-19 : plafond 2 fois plus haut) : rangee du bas (portes, fenetres) jusqu'a
--   18, corniche, rangee du haut (hautes fenetres) ; poutres a 34.6 -> 35.8.
--   Annexe ouest (BaseTemplate) : salle du Rebirth x -45 -> 0, z 72 -> 135 ; terrasse x -45 -> 0, z 0 -> 71.
--   Zones (panneau suspendu ; plus de sol de couleur depuis le 2026-11-20) : verger, etagere a fruits, bar a jus, vente, escalier.
--   Voies d'escalier (Config/Floors.Lanes) : dalle et sol de zone y sont laisses vides ; 02h les
--   remplit selon la variante (SolidA/B) ou y met le trou (HoleA/B).
--   Vu de la route, +X est a GAUCHE.
-- Doc : docs/systems/carte-bases.md

local H = 36 -- hauteur des murs (18 avant le 2026-11-19 : plafond double)
local SPLIT = 18 -- separation rangee du bas / rangee du haut (corniche)
local BEAM_Y0, BEAM_Y1 = H - 1.4, H - 0.2 -- poutres du plafond
local BAND = 3.5 -- hauteur de la bande coloree en bas des murs

-- Palette "usine a studs" (2026-11-19, captures de reference de l'utilisateur) : murs gris-bleu tres
-- clair a studs, bas de mur en tole (DiamondPlate), sol ardoise fonce, structure en acier gris-bleu,
-- neons blancs, vitres cyan, poteaux jaune / noir, chemins orange dehors, herbe vert vif.
local LOT = Color3.fromRGB(72, 170, 62) -- = herbe (01-ground-road)
local PAVING = Color3.fromRGB(226, 134, 66)
local PAVING_DARK = Color3.fromRGB(198, 112, 52)
local FLOOR = Color3.fromRGB(74, 80, 93) -- 2026-11-20 : plus fonce (avant 104, 110, 128), cale en jeu sur la reference
local WALL = Color3.fromRGB(238, 242, 250) -- 2026-11-20 : cale en jeu sur la reference (avec l'eclairage de 04)
local WALL_BAND = Color3.fromRGB(146, 156, 178) -- avant 162, 172, 192
local TRIM = Color3.fromRGB(124, 136, 162)
local BEAM = Color3.fromRGB(110, 120, 144)
local GLASS = Color3.fromRGB(176, 208, 228) -- bleu pale (2026-11-19 nuit, avant cyan 110,200,245)
local HAZARD_YELLOW = Color3.fromRGB(250, 206, 40)
local HAZARD_BLACK = Color3.fromRGB(36, 38, 46)
local NEON_WHITE = Color3.fromRGB(236, 246, 255)
local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local WOOD_CAP = Color3.fromRGB(186, 146, 102)
local SOIL = Color3.fromRGB(116, 84, 58)
local LEAF = Color3.fromRGB(80, 140, 62)
local SIGN_BG = Color3.fromRGB(196, 108, 52) -- panneau en bois orange (texte blanc a contour)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)

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
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }
local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
end
local GLASS_PROPS = table.clone(SMOOTH)
GLASS_PROPS.Material = Enum.Material.Glass
GLASS_PROPS.Transparency = 0.6
GLASS_PROPS.CastShadow = false

local function surfaceGui(target: BasePart, face: Enum.NormalId): SurfaceGui
	(target :: any)[face.Name .. "Surface"] = STUDS -- panneaux et textes : studs aussi (style brique)
	local g = Instance.new("SurfaceGui")
	g.Name = "Display" .. face.Name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = target
	return g
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = text
	t.TextScaled = true
	t.TextWrapped = true
	t.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT_STROKE
	stroke.Thickness = strokePx
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = t
	t.Parent = parent
	return t
end

local rng = Random.new(17)

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local FloorsConfig = freshRequire(ReplicatedStorage.Shared.Config.Floors)
local LANES = FloorsConfig.Lanes
local SX0, SX1 = FloorsConfig.StairStartX, FloorsConfig.StairEndX -- voies : trou / escalier

for _, name in { "BaseTemplate", "FloorTemplate" } do
	local old = ServerStorage:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local function newModel(name: string, folders: { string }): Model
	local m = Instance.new("Model")
	m.Name = name
	local origin = part(m, "Origin", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0), Color3.new(1, 0, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	m.PrimaryPart = origin
	for _, folderName in folders do
		local f = Instance.new("Folder")
		f.Name = folderName
		f.Parent = m
	end
	return m
end
-- Base (une fois) : Floors = les etages clones en jeu (FloorService)
local model = newModel("BaseTemplate", { "Lot", "Annex", "Entrance", "Floors", "Dynamic" })
-- Un etage
local floorModel = newModel("FloorTemplate", { "Building", "Tree", "Production", "Counter", "Machines", "Markers", "Dynamic" })
local lot = model:FindFirstChild("Lot") :: Folder

-- Rectangle (x0..x1, z0..z1) moins des trous rectangulaires : liste de rectangles qui le couvrent.
type Rect = { number }
local function rectMinus(r: Rect, holes: { Rect }): { Rect }
	local xs, zs = { r[1], r[2] }, { r[3], r[4] }
	for _, h in holes do
		for _, x in { h[1], h[2] } do
			if x > r[1] and x < r[2] then
				table.insert(xs, x)
			end
		end
		for _, z in { h[3], h[4] } do
			if z > r[3] and z < r[4] then
				table.insert(zs, z)
			end
		end
	end
	table.sort(xs)
	table.sort(zs)
	-- cellules de la grille hors trous, puis fusion le long de X (moins de pieces)
	local out: { Rect } = {}
	for j = 1, #zs - 1 do
		local run: Rect? = nil
		for i = 1, #xs - 1 do
			local cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
			local inHole = false
			for _, h in holes do
				if cx > h[1] and cx < h[2] and cz > h[3] and cz < h[4] then
					inHole = true
				end
			end
			if inHole or xs[i + 1] - xs[i] < 1e-6 then
				if run then
					table.insert(out, run)
					run = nil
				end
			elseif run then
				run[2] = xs[i + 1]
			else
				run = { xs[i], xs[i + 1], zs[j], zs[j + 1] }
			end
		end
		if run then
			table.insert(out, run)
		end
	end
	return out
end
local LANE_HOLES: { Rect } = {
	{ SX0, SX1, LANES.A.z0, LANES.A.z1 },
	{ SX0, SX1, LANES.B.z0, LANES.B.z1 },
}

-- ===== Terrain et cour avant =====
-- Herbe du terrain decoupee AUTOUR des sols du batiment (pas de pelouse cachee 0.2 sous le sol gris :
-- vue de loin, les deux dessus clignotaient = z-fighting, 2026-11-19). Trou : salle principale
-- x 1 -> 109, z 15 -> 135 ; seuil x 8 -> 18, z 14 -> 15 ; bar a cocktails x -45 -> 0, z 72 -> 135.
for _, r in {
	{ -46, 110, 0, 14 }, -- devant
	{ -46, 8, 14, 15 }, -- de part et d'autre du seuil
	{ 18, 110, 14, 15 },
	{ -46, 1, 15, 72 }, -- terrasse et cote gauche
	{ -46, -45, 72, 135 }, -- bord exterieur du bar a cocktails
	{ 0, 1, 72, 135 }, -- entre bar a cocktails et salle principale
	{ 109, 110, 15, 135 }, -- bord droit
	{ -46, 110, 135, 138 }, -- fond
} do
	box(lot, "Ground", r[1], r[2], -0.7, 0.3, r[3], r[4], LOT)
end
box(lot, "YardPlaza", 42, 86, -0.6, 0.45, 0.05, 13.95, PAVING) -- devant le comptoir (clients)
box(lot, "YardPath", 7, 19, -0.6, 0.45, 0.05, 13.95, PAVING) -- chemin vers la porte
for i = 0, 4 do -- dalles plus foncees sous la file des clients
	local x0 = 52 + i * 5
	box(lot, "YardTile", x0, x0 + 3.5, -0.55, 0.6, 6, 12, PAVING_DARK) -- 0.15 au-dessus de la place (anti z-fighting)
end

-- Cloture basse en bois le long de la route (passages : chemin et place des clients)
local fence = Instance.new("Folder")
fence.Name = "Fence"
local function fencePost(p: Vector3)
	box(fence, "Post", p.X - 0.5, p.X + 0.5, 0.3, 3.6, p.Z - 0.5, p.Z + 0.5, WOOD_DARK)
	box(fence, "Cap", p.X - 0.65, p.X + 0.65, 3.6, 3.95, p.Z - 0.65, p.Z + 0.65, WOOD_CAP)
end
local function fenceRun(a: Vector3, b: Vector3)
	local dir = b - a
	local n = math.max(1, math.ceil(dir.Magnitude / 5))
	for i = 0, n do
		fencePost(a + dir * (i / n))
	end
	for i = 1, n do
		local p0, p1 = a + dir * ((i - 1) / n), a + dir * (i / n)
		for _, y in { 1.4, 2.7 } do
			local mid = (p0 + p1) / 2 + Vector3.new(0, y, 0)
			part(fence, "Rail", Vector3.new(0.35, 0.5, (p1 - p0).Magnitude), CFrame.lookAt(mid, mid + dir.Unit), WOOD)
		end
	end
end
fenceRun(Vector3.new(1.5, 0, 0.6), Vector3.new(6.4, 0, 0.6))
fenceRun(Vector3.new(19.6, 0, 0.6), Vector3.new(41.4, 0, 0.6))
fenceRun(Vector3.new(86.6, 0, 0.6), Vector3.new(109.5, 0, 0.6))
fence.Parent = lot

-- Haies basses dans la cour (vertes seulement : plus de fleurs de couleur qu'on prendrait pour des
-- fruits, demande utilisateur du 2026-11-19 soir)
local function hedge(name: string, x0: number, x1: number, z0: number, z1: number)
	local bed = Instance.new("Model")
	bed.Name = name
	box(bed, "Soil", x0, x1, 0.3, 0.7, z0, z1, SOIL, DECOR)
	box(bed, "Hedge", x0 + 0.3, x1 - 0.3, 0.7, 2.2, z0 + 0.3, z1 - 0.3, LEAF, DECOR)
	local yaw = CFrame.Angles(0, math.rad(rng:NextNumber(10, 35)), 0)
	part(bed, "HedgeTop", Vector3.new(math.min(x1 - x0, z1 - z0) - 1.4, 0.8, math.min(x1 - x0, z1 - z0) - 1.4), CFrame.new((x0 + x1) / 2, 2.5, (z0 + z1) / 2) * yaw, LEAF:Lerp(Color3.new(1, 1, 1), 0.08), DECOR)
	bed.Parent = lot
end
hedge("HedgeLeft", 1.5, 6.5, 3, 12.5)
hedge("HedgeRight", 19.5, 25.5, 3, 12.5)
hedge("HedgeMiddle", 30, 38, 3, 12.5)
task.wait()

-- ===== Batiment =====
-- Salle principale x 1 -> 109, z 15 -> 135 (108 x 120) : FloorTemplate. Annexe (salle du Rebirth
-- x -45 -> 0, z 72 -> 135) : BaseTemplate.Annex.
local building = floorModel:FindFirstChild("Building") :: Folder
local annex = model:FindFirstChild("Annex") :: Folder
-- Dalle de l'etage (= plafond de l'etage du dessous), sans les 2 voies d'escalier (02h)
for _, r in rectMinus({ 1, 109, 15, 135 }, LANE_HOLES) do
	box(building, "Floor", r[1], r[2], -0.2, 0.5, r[3], r[4], FLOOR):SetAttribute("Shell", true)
end
box(annex, "AnnexFloor", -45, 0, -0.2, 0.5, 72, 135, Color3.fromRGB(150, 104, 80))
-- Seuil de la porte (meme hauteur que le sol) ; en haut : porte du balcon
box(building, "DoorStepFront", 8, 18, -0.2, 0.5, 14, 15, FLOOR):SetAttribute("Shell", true)

local walls = Instance.new("Folder")
walls.Name = "Walls"
walls:SetAttribute("Shell", true)
local hallWalls = walls
local annexWalls = Instance.new("Folder")
annexWalls.Name = "Walls"

-- Un morceau de mur, coupe en deux couleurs (bande en bas). axis "X" : le mur court le long de X.
local function wallPiece(axis: string, a0: number, a1: number, t0: number, t1: number, y0: number, y1: number)
	local function mk(name: string, ya: number, yb: number, color: Color3, props: { [string]: any }?)
		if yb - ya < 0.01 then
			return
		end
		if axis == "X" then
			box(walls, name, a0, a1, ya, yb, t0, t1, color, props)
		else
			box(walls, name, t0, t1, ya, yb, a0, a1, color, props)
		end
	end
	if y0 < BAND then
		-- Bas de mur en tole (motif de losanges, comme les usines de reference)
		mk("WallBand", y0, math.min(y1, BAND), WALL_BAND, { Material = Enum.Material.DiamondPlate })
	end
	if y1 > BAND then
		mk("Wall", math.max(y0, BAND), y1, WALL)
	end
end

type Hole = { a: number, b: number, y0: number, y1: number, glass: boolean? }

-- Une rangee de mur (yBottom -> yTop) avec des trous (portes, fenetres) ; t0..t1 = epaisseur.
local function wallRow(axis: string, a0: number, a1: number, t0: number, t1: number, yBottom: number, yTop: number, holes: { Hole })
	table.sort(holes, function(p: Hole, q: Hole)
		return p.a < q.a
	end)
	local cursor = a0
	for _, h in holes do
		if h.a > cursor then
			wallPiece(axis, cursor, h.a, t0, t1, yBottom, yTop)
		end
		wallPiece(axis, h.a, h.b, t0, t1, yBottom, h.y0)
		wallPiece(axis, h.a, h.b, t0, t1, h.y1, yTop)
		-- Cadre (menthe fonce) qui deborde de 0.2 de chaque cote, 0.1 dans l'ouverture
		local f0, f1 = t0 - 0.2, t1 + 0.2
		local function frame(name: string, b0: number, b1: number, ya: number, yb: number)
			if axis == "X" then
				box(walls, name, b0, b1, ya, yb, f0, f1, TRIM)
			else
				box(walls, name, f0, f1, ya, yb, b0, b1, TRIM)
			end
		end
		frame("FrameSide", h.a - 0.5, h.a + 0.1, math.max(0.3, h.y0 - 0.5), h.y1 + 0.5)
		frame("FrameSide", h.b - 0.1, h.b + 0.5, math.max(0.3, h.y0 - 0.5), h.y1 + 0.5)
		frame("FrameTop", h.a - 0.5, h.b + 0.5, h.y1 - 0.1, h.y1 + 0.5)
		if h.y0 > 0.31 then
			frame("FrameSill", h.a - 0.5, h.b + 0.5, h.y0 - 0.5, h.y0 + 0.1)
		end
		if h.glass then
			local m0, m1 = (t0 + t1) / 2 - 0.1, (t0 + t1) / 2 + 0.1
			if axis == "X" then
				box(walls, "Glass", h.a + 0.1, h.b - 0.1, h.y0 + 0.1, h.y1 - 0.1, m0, m1, GLASS, GLASS_PROPS)
				box(walls, "Mullion", (h.a + h.b) / 2 - 0.2, (h.a + h.b) / 2 + 0.2, h.y0 + 0.1, h.y1 - 0.1, m0 - 0.1, m1 + 0.1, TRIM)
			else
				box(walls, "Glass", m0, m1, h.y0 + 0.1, h.y1 - 0.1, h.a + 0.1, h.b - 0.1, GLASS, GLASS_PROPS)
				box(walls, "Mullion", m0 - 0.1, m1 + 0.1, h.y0 + 0.1, h.y1 - 0.1, (h.a + h.b) / 2 - 0.2, (h.a + h.b) / 2 + 0.2, TRIM)
			end
		end
		cursor = h.b
	end
	if cursor < a1 then
		wallPiece(axis, cursor, a1, t0, t1, yBottom, yTop)
	end
end

-- Mur complet : rangee du bas (holes : portes, fenetres, y1 <= SPLIT), corniche, rangee du haut
-- (highHoles : hautes fenetres). Les murs le long de Z ont leur corniche et leur chapeau un peu plus
-- fins : pas de face commune aux coins (les piliers cachent les coins).
local function wall(axis: string, a0: number, a1: number, t0: number, t1: number, holes: { Hole }, highHoles: { Hole }?)
	wallRow(axis, a0, a1, t0, t1, 0.3, SPLIT, holes)
	wallRow(axis, a0, a1, t0, t1, SPLIT, H, highHoles or {})
	local ledge = if axis == "X" then 0.3 else 0.25
	local capTop = if axis == "X" then H + 0.6 else H + 0.55
	if axis == "X" then
		box(walls, "Ledge", a0 - 0.25, a1 + 0.25, SPLIT - ledge, SPLIT + ledge, t0 - 0.25, t1 + 0.25, TRIM)
		box(walls, "Cap", a0 - 0.15, a1 + 0.15, H, capTop, t0 - 0.15, t1 + 0.15, TRIM)
	else
		box(walls, "Ledge", t0 - 0.25, t1 + 0.25, SPLIT - ledge, SPLIT + ledge, a0 - 0.25, a1 + 0.25, TRIM)
		box(walls, "Cap", t0 - 0.15, t1 + 0.15, H, capTop, a0 - 0.15, a1 + 0.15, TRIM)
	end
end

-- Hautes fenetres (rangee du haut), toutes a la meme hauteur
local function high(a: number, b: number): Hole
	return { a = a, b = b, y0 = 22, y1 = 31, glass = true }
end

-- Salle principale (FloorTemplate, identique a chaque etage ; en haut la porte et la fenetre du
-- comptoir donnent sur le balcon)
walls = hallWalls
wall("X", 0, 110, 14, 15, { -- facade (cote route)
	{ a = 8, b = 18, y0 = 0.3, y1 = 12 }, -- porte du joueur
	{ a = 48, b = 80, y0 = 0.3, y1 = 11 }, -- fenetre du comptoir (le comptoir est dedans)
	{ a = 94, b = 106, y0 = 6, y1 = 12, glass = true },
}, { high(6, 20), high(34, 48), high(62, 76), high(90, 104) })
wall("X", 0, 110, 135, 136, { -- fond
	{ a = 52, b = 62, y0 = 5, y1 = 13, glass = true },
	{ a = 76, b = 100, y0 = 5, y1 = 15, glass = true },
}, { high(8, 24), high(36, 52), high(64, 80), high(88, 104) })
-- Mur x 109 (palier de l'escalier contre ce mur) : plus de fenetre basse en z 56-70 (phase 1b)
wall("Z", 15, 135, 109, 110, {
	{ a = 30, b = 44, y0 = 5, y1 = 12, glass = true },
	{ a = 106, b = 122, y0 = 5, y1 = 12, glass = true },
}, { high(24, 40), high(52, 68), high(80, 96), high(108, 124) })
-- Mur x 0 (cote annexe) : au rez-de-chaussee, portes de la terrasse et de la salle du Rebirth ;
-- en haut (pas d'annexe), des fenetres a la place.
local onlyGround = Instance.new("Folder")
onlyGround.Name = "OnlyGround"
onlyGround.Parent = hallWalls
local onlyUpper = Instance.new("Folder")
onlyUpper.Name = "OnlyUpper"
onlyUpper.Parent = hallWalls
walls = onlyGround
wall("Z", 15, 135, 0, 1, {
	{ a = 28, b = 40, y0 = 0.3, y1 = 12 }, -- porte de la terrasse
	{ a = 96, b = 108, y0 = 0.3, y1 = 12 }, -- porte de la salle du Rebirth
}, { high(26, 40), high(50, 64) })
walls = onlyUpper
wall("Z", 15, 135, 0, 1, {
	{ a = 28, b = 40, y0 = 5, y1 = 12, glass = true },
	{ a = 96, b = 108, y0 = 5, y1 = 12, glass = true },
}, { high(26, 40), high(50, 64) })
-- Annexe (BaseTemplate) : salle du Rebirth (ancien bar a cocktails)
walls = annexWalls
wall("X", -46, 0, 135, 136, { { a = -34, b = -14, y0 = 6, y1 = 12, glass = true } }, { high(-34, -14) })
wall("Z", 72, 135, -46, -45, { { a = 88, b = 114, y0 = 6, y1 = 12, glass = true } }, { high(84, 100), high(110, 126) })
wall("X", -46, 0, 71, 72, {}, { high(-38, -26), high(-20, -8) })
task.wait()

-- Piliers aux coins. Ceux de la salle principale ont le bas raye jaune / noir (signal d'usine).
-- Piliers de la salle : de 0.3 a H + 0.3 (= bas du pilier de l'etage du dessus, sans recouvrement
-- = sans z-fighting) ; piliers de l'annexe : comme avant.
local HAZARD_PILLARS = { [1] = true, [2] = true, [3] = true, [4] = true }
for i, c in { Vector2.new(0.5, 14.5), Vector2.new(109.5, 14.5), Vector2.new(109.5, 135.5), Vector2.new(0.5, 135.5), Vector2.new(-45.5, 135.5), Vector2.new(-45.5, 71.5), Vector2.new(0.5, 71.5) } do
	local y = 0.3
	walls = if HAZARD_PILLARS[i] then hallWalls else annexWalls
	if HAZARD_PILLARS[i] then
		local n = 0
		while y < SPLIT - 0.01 do
			local y1 = math.min(SPLIT, y + 2)
			box(walls, "PillarHazard", c.X - 0.9, c.X + 0.9, y, y1, c.Y - 0.9, c.Y + 0.9, if n % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK)
			y = y1
			n += 1
		end
	end
	box(walls, "Pillar", c.X - 0.9, c.X + 0.9, y, if HAZARD_PILLARS[i] then H + 0.3 else H + 1.2, c.Y - 0.9, c.Y + 0.9, TRIM)
end
hallWalls.Parent = building
annexWalls.Parent = annex

-- Poutres du plafond (decor, sans collision) ; au-dessus du verger (x 67.6 -> 106.4, z 97 -> 135) :
-- un puits de lumiere (pas de poutre : on voit l'arbre et son texte "Tree full!").
local beams = Instance.new("Folder")
beams.Name = "Beams"
for _, z in { 26, 38, 50, 86 } do
	box(beams, "Beam", 1, 109, BEAM_Y0, BEAM_Y1, z - 0.6, z + 0.6, BEAM, DECOR)
end
-- z 62 et 74 passent au-dessus des voies d'escalier : coupees avant la zone STAIRS (x 60)
for _, z in { 62, 74 } do
	box(beams, "Beam", 1, 60, BEAM_Y0, BEAM_Y1, z - 0.6, z + 0.6, BEAM, DECOR)
end
for _, z in { 98, 110, 122 } do
	box(beams, "Beam", 1, 66.4, BEAM_Y0, BEAM_Y1, z - 0.6, z + 0.6, BEAM, DECOR)
end
box(beams, "SkylightBeam", 66.4, 67.6, BEAM_Y0, BEAM_Y1, 96.4, 135, BEAM, DECOR)
box(beams, "SkylightBeam", 106.4, 107.6, BEAM_Y0, BEAM_Y1, 96.4, 135, BEAM, DECOR)
box(beams, "SkylightBeam", 67.6, 106.4, BEAM_Y0, BEAM_Y1, 96.4, 97.6, BEAM, DECOR)
beams.Parent = building
local annexBeams = Instance.new("Folder")
annexBeams.Name = "Beams"
box(annexBeams, "Beam", -45, 0, BEAM_Y0, BEAM_Y1, 92.4, 93.6, BEAM, DECOR)
box(annexBeams, "Beam", -45, 0, BEAM_Y0, BEAM_Y1, 114.4, 115.6, BEAM, DECOR)
annexBeams.Parent = annex

-- Neons d'usine (decor) : boitier gris + tube blanc, fixes sous les poutres (toutes les lampes sont
-- sur une ligne de poutre : z 38, 50, 62, 74, 86, 110). Avant le 2026-11-19 : lampes jaunes sur fils.
local lamps = Instance.new("Folder")
lamps.Name = "Lamps"
local NEON_PROPS = {
	Material = Enum.Material.Neon,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}
for _, p in { Vector2.new(22, 38), Vector2.new(52, 38), Vector2.new(82, 38), Vector2.new(100, 50), Vector2.new(10, 62), Vector2.new(56, 62), Vector2.new(100, 86), Vector2.new(56, 50), Vector2.new(12, 86), Vector2.new(44, 86), Vector2.new(8, 110), Vector2.new(58, 110) } do
	local lamp = Instance.new("Model")
	lamp.Name = "HangingLamp"
	box(lamp, "Housing", p.X - 4, p.X + 4, BEAM_Y0 - 0.6, BEAM_Y0, p.Y - 1.4, p.Y + 1.4, TRIM, DECOR)
	box(lamp, "Tube", p.X - 3.6, p.X + 3.6, BEAM_Y0 - 0.8, BEAM_Y0 - 0.6, p.Y - 1, p.Y + 1, NEON_WHITE, NEON_PROPS)
	lamp.Parent = lamps
end
lamps.Parent = building
task.wait()

-- ===== Zones : grand panneau suspendu (sols de couleur et bordures retires le 2026-11-20) =====
-- Le joueur voit tout de suite ou est chaque poste (verger, etagere, bar a jus, vente).
local zones = Instance.new("Folder")
zones.Name = "Zones"
local function zone(name: string, title: string, x0: number, x1: number, z0: number, z1: number, color: Color3, signX: number, signZ: number, _holes: { Rect }?)
	local m = Instance.new("Model")
	m.Name = name
	-- 2026-11-20 (demande : "tu retires les delimitations rose, vert, jaune, bleu") : plus de sol de
	-- zone teinte ni de bordure de couleur ; le sol reste uni et l'allee (02k) guide le joueur. On
	-- garde seulement le panneau suspendu. (_holes ne sert plus.)
	local border = color:Lerp(Color3.new(0, 0, 0), 0.35)
	-- Panneau suspendu aux poutres, lisible depuis l'entree (face vers la route : -Z)
	local w = math.max(10, #title * 1.15)
	for _, sx in { signX - w / 2 + 1, signX + w / 2 - 1 } do
		box(m, "SignChain", sx - 0.08, sx + 0.08, 14.6, BEAM_Y0, signZ - 0.08, signZ + 0.08, BEAM, DECOR)
	end
	local board = box(m, "SignBoard", signX - w / 2, signX + w / 2, 11.6, 14.6, signZ - 0.25, signZ + 0.25, color, DECOR)
	box(m, "SignTrim", signX - w / 2 - 0.2, signX + w / 2 + 0.2, 11.4, 11.6, signZ - 0.3, signZ + 0.3, border, DECOR)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = surfaceGui(board, face)
		label(gui, "Text", title, UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), 4)
	end
	m.Parent = zones
end
-- Les sols de zone sont juste au-dessus du sol de l'usine (y 0.5 -> 0.65, bordure -> 0.75). Ils ne se chevauchent
-- JAMAIS (deux sols au meme niveau = z-fighting : bug du bar a jus sur le verger, 2026-11-19 soir).
-- Plan en U, dans l'ordre de la chaine : verger (fond gauche) -> etagere (fond) -> bar a jus
-- (droite, vu de la route) -> vente (devant) -> argent.
-- Chaque zone CONTIENT tout son poste (revu le 2026-11-19 : mixeur 4, panneau Juice et pad du
-- Fruit Picker depassaient), avec des allees libres entre les zones :
--   Verger    x 62-108, z 84-134 (jardiniere, machines de l'arbre, panneau Tree, pad Fruit Picker)
--   Etagere   x 14-60,  z 108-134 (etagere, plancher + pad Drop Fruits, boite du tapis)
--   Bar a jus x 4-54,   z 64-105 (4 mixeurs + allee, table a jus + pad Take Juices, Juice Cooler,
--             panneau Juice)
--   Vente     x 36-108, z 15-54 (comptoir, pad Drop Juices, table a argent, pad Collect Cash,
--             pad Auto Collect, panneau Shop, pad Auto Sell)
-- Allees : x 54-62 entre le bar a jus et le verger, z 54-64 entre la vente et le bar a jus.
zone("OrchardZone", "ORCHARD", 62, 108, 84, 134, Color3.fromRGB(104, 178, 92), 85, 86)
zone("ShelfZone", "FRUIT SHELF", 14, 60, 108, 134, Color3.fromRGB(234, 172, 74), 41, 110)
zone("JuiceZone", "JUICE BAR", 4, 54, 64, 105, Color3.fromRGB(222, 116, 152), 36, 66)
zone("SalesZone", "SALES", 36, 108, 15, 50, Color3.fromRGB(84, 148, 222), 72, 50) -- z 54 -> 50 (phase 1b)
-- Escalier (phase 1b) : x 60 -> 108, z 50 -> 84 (le verger commence a 84). Les 2 voies restent vides
-- (02h). Panneau a cote de SALES, sur la poutre z 50 (hors des voies).
local SZ = FloorsConfig.StairsZone
zone("StairsZone", "STAIRS", SZ.x0, SZ.x1, SZ.z0, SZ.z1, Color3.fromRGB(150, 160, 178), 84, 50, LANE_HOLES)
zones.Parent = building
task.wait()

-- ===== Entree : panneau du proprietaire au-dessus de la porte, enseigne au-dessus du comptoir =====
local entrance = model:FindFirstChild("Entrance") :: Folder -- BaseTemplate (rez-de-chaussee)
local sign = Instance.new("Model")
sign.Name = "OwnerSign"
box(sign, "SignFrame", 2.6, 23.4, 12.6, 17.4, 13.45, 13.95, TRIM)
local ownerBoard = box(sign, "SignBoard", 2.9, 23.1, 12.9, 17.1, 13.4, 13.9, SIGN_BG)
label(surfaceGui(ownerBoard, Enum.NormalId.Front), "OwnerText", "Free Factory", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), 4)
-- Petite plaque a l'interieur, au-dessus de la porte
local inner = box(sign, "InnerBoard", 6, 20, 12.9, 15.6, 15.05, 15.45, SIGN_BG)
label(surfaceGui(inner, Enum.NormalId.Back), "OwnerText", "Free Factory", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), 3)
sign.PrimaryPart = ownerBoard
sign.Parent = entrance

local brand = Instance.new("Model")
brand.Name = "FactorySign"
box(brand, "BrandFrame", 47.6, 80.4, 11.9, 17.6, 13.45, 13.95, TRIM)
local brandBoard = box(brand, "BrandBoard", 47.9, 80.1, 12.2, 17.3, 13.4, 13.9, Color3.fromRGB(255, 120, 60))
local brandText = label(surfaceGui(brandBoard, Enum.NormalId.Front), "Text", "JUICE FACTORY", UDim2.fromScale(0.03, 0.08), UDim2.fromScale(0.94, 0.84), 6)
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(Color3.fromRGB(255, 246, 160), Color3.fromRGB(255, 196, 60))
gradient.Parent = brandText
-- Fruits sur l'enseigne
part(brand, "Orange", Vector3.new(1.8, 1.8, 1.8), CFrame.new(48.4, 18.4, 13.7) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(255, 150, 30), DECOR)
part(brand, "Apple", Vector3.new(1.6, 1.6, 1.6), CFrame.new(79.6, 18.3, 13.7) * CFrame.Angles(0, math.rad(-25), 0), Color3.fromRGB(220, 40, 44), DECOR)
part(brand, "Leaf", Vector3.new(1, 0.3, 0.6), CFrame.new(48.6, 19.45, 13.7) * CFrame.Angles(0, math.rad(20), 0), LEAF, DECOR)
brand.Parent = entrance

-- Regle "2 studs" (docs/style.md) : Inlet (carres en creux) sur les sols et chemins ou l'on marche,
-- Studs sur les murs et les objets.
-- Murs (2026-11-20, reference de l'utilisateur) : faces en Inlet (carres en creux), pas en Studs
-- (bosses blanches qui chargeaient l'image).
for _, d in floorModel:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Wall" then
		d.FrontSurface = Enum.SurfaceType.Inlet
		d.BackSurface = Enum.SurfaceType.Inlet
		d.LeftSurface = Enum.SurfaceType.Inlet
		d.RightSurface = Enum.SurfaceType.Inlet
	end
end
local WALKABLE = { Ground = true, YardPlaza = true, YardPath = true, YardTile = true, Floor = true, AnnexFloor = true, DoorStepFront = true }
for _, m in { model, floorModel } do
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and WALKABLE[d.Name] then
			d.TopSurface = Enum.SurfaceType.Inlet
		end
	end
end

model.Parent = ServerStorage
floorModel.Parent = ServerStorage
return "Shell OK: base " .. #model:GetDescendants() .. ", etage " .. #floorModel:GetDescendants()
