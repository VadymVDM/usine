--!strict
-- Morceau 6 : annexe ouest (BaseTemplate.Annex, rez-de-chaussee seulement) et marqueurs (FloorTemplate).
-- Tour d'etages (phase 1b, 2026-11-20) : l'ancien bar a cocktails devient la salle du Rebirth
-- (vitre rouge "Reach Floor 10", machine doree), la terrasse devient le hall de l'ascenseur des
-- clients (fermee jusqu'a l'achat de l'etage 2 : vitre rouge dans la porte + portail cote rue), avec
-- le bas de la cage vitree de l'ascenseur. Plus de ZoneLocks / Rooms. A lancer apres 02a.
-- Markers (un jeu par etage) : apparition, clients (OnlyGround : trottoir ; OnlyUpper : balcon),
-- postes et trajets des employes R6.
-- Doc : docs/systems/carte-bases.md, docs/systems/tour-etages.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local FloorsConfig = freshRequire(ReplicatedStorage.Shared.Config.Floors)

local BARRIER = Color3.fromRGB(255, 70, 80)

local DECK = { Color3.fromRGB(190, 140, 92), Color3.fromRGB(176, 128, 84) }
local POT = Color3.fromRGB(200, 110, 70)
local LEAF = Color3.fromRGB(80, 160, 70)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)

local STUDS = Enum.SurfaceType.Studs
local OFFSET = Vector3.zero -- decalage du bloc en cours (usine agrandie le 2026-11-19)
local SMOOTH_SURF = Enum.SurfaceType.Smooth

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf + OFFSET
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
local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
end
local MARKER = with(SMOOTH, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, color: Color3, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = value
	t.TextScaled = true
	t.TextColor3 = color
	local s = Instance.new("UIStroke")
	s.Color = TEXT_STROKE
	s.Thickness = strokePx
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

local function surfaceGui(target: BasePart, face: Enum.NormalId, ppu: number, surface: Enum.SurfaceType?): SurfaceGui
	-- panneaux et textes : studs aussi (style brique) ; la barriere transparente reste lisse
	(target :: any)[face.Name .. "Surface"] = surface or STUDS
	local g = Instance.new("SurfaceGui")
	g.Name = "Display" .. face.Name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = ppu
	g.LightInfluence = 0
	g.Parent = target
	return g
end

local base = game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
local model = game:GetService("ServerStorage"):FindFirstChild("FloorTemplate")
assert(base and model, "Lancer 02a d'abord")
local annex = base:FindFirstChild("Annex") :: Folder
for _, old in { annex:FindFirstChild("Terrace"), annex:FindFirstChild("RebirthRoom"), annex:FindFirstChild("ElevatorBase"), model:FindFirstChild("Markers") } do
	if old then
		old:Destroy()
	end
end

local GOLD = Color3.fromRGB(255, 196, 40)
local GOLD_DARK = Color3.fromRGB(214, 150, 20)
local TRIM = Color3.fromRGB(124, 136, 162)
local GLASS = Color3.fromRGB(176, 208, 228)
local GLASS_PROPS = with(SMOOTH, { Material = Enum.Material.Glass, Transparency = 0.6, CastShadow = false, CanQuery = false })
-- Cage de l'ascenseur : plastique lisse transparent, PAS le materiau Glass (2026-11-20 : en haut de
-- l'ascenseur, les avatars etaient caches ; le Glass de Roblox masque ce qui est transparent derriere)
local SHAFT_GLASS_PROPS = with(SMOOTH, { Material = Enum.Material.SmoothPlastic, Transparency = 0.7, CastShadow = false, CanQuery = false })
local H = FloorsConfig.FloorHeight

-- Vitre rouge transparente dans une porte du mur x 0 (on voit la salle derriere), cadenas, nom, texte.
local function lockedGate(parent: Instance, name: string, z0: number, z1: number, title: string, status: string): Model
	local gate = Instance.new("Model")
	gate.Name = name
	local barrier = box(gate, "Barrier", 0.15, 0.85, 0.5, 12, z0, z1, BARRIER, with(SMOOTH, {
		Transparency = 0.55,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	}))
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local g = surfaceGui(barrier, face, 30, SMOOTH_SURF)
		text(g, "Lock", "\u{1F512}", UDim2.fromScale(0.35, 0.16), UDim2.fromScale(0.3, 0.2), Color3.fromRGB(255, 214, 80), 0)
		text(g, "ZoneName", title, UDim2.fromScale(0.05, 0.4), UDim2.fromScale(0.9, 0.14), Color3.new(1, 1, 1), 3)
		text(g, "Status", status, UDim2.fromScale(0.05, 0.56), UDim2.fromScale(0.9, 0.12), Color3.fromRGB(255, 226, 90), 3)
	end
	gate.PrimaryPart = barrier
	gate.Parent = parent
	return gate
end

-- ===== TERRASSE (x -45 -> 0, z 0 -> 71) : hall de l'ascenseur des clients =====
-- Fermee jusqu'a l'achat de l'etage 2 (FloorService) : vitre rouge dans la porte de l'usine et
-- portail ferme cote rue (Gate*). Ensuite les clients de la rue y font la queue et montent.
local terrace = Instance.new("Model")
terrace.Name = "Terrace"
for i = 0, 14 do
	local x0 = -45 + i * 3
	box(terrace, "Deck", x0 + 0.05, x0 + 2.95, -0.2, 0.5, 0.5, 70.9, DECK[(i % 2) + 1], { TopSurface = Enum.SurfaceType.Inlet }) -- sol : Inlet
end
-- Plantes : dans le couloir libre a l'est (x -15 -> 0), hors de la file
for _, p in { Vector2.new(-13, 67), Vector2.new(-3, 67), Vector2.new(-3, 18) } do
	box(terrace, "Pot", p.X - 1, p.X + 1, 0.5, 2, p.Y - 1, p.Y + 1, POT)
	part(terrace, "Plant", Vector3.new(2.2, 2.2, 2.2), CFrame.new(p.X, 3, p.Y) * CFrame.Angles(0, math.rad(25), 0), LEAF)
end
-- File d'attente en SERPENTIN dans la longueur de la terrasse (retour de test du 2026-11-20 :
-- "la file doit occuper toute la terrasse") : 4 allees le long de Z entre des cordes rouges, du
-- portail cote rue (x -44 -> -37) jusqu'a la porte de la cabine (x -9, z 7) :
--   allee 1 (x -45.5 -> -36.5) : sud -> nord ; demi-tour au nord (z 62 -> 71)
--   allee 2 (x -36.5 -> -29.5) : nord -> sud ; demi-tour au sud (z 0 -> 9)
--   allee 3 (x -29.5 -> -22.5) : sud -> nord ; demi-tour au nord
--   allee 4 (x -22.5 -> -15.5) : nord -> sud, puis vers l'est jusqu'a la cabine
-- Le couloir x -15 -> 0 reste libre pour le joueur (porte de l'usine z 28 -> 40). Plus la file
-- est longue (niveau Customers), plus elle remplit la terrasse (CustomerController).
-- Points de passage des clients : Terrace.QueuePath.Point1..8 (client, CustomerController).
local QUEUE = Color3.fromRGB(230, 60, 70)
local function rope(axis: string, a0: number, a1: number, t: number)
	local n = math.max(1, math.ceil((a1 - a0) / 6))
	for i = 0, n do
		local a = a0 + (a1 - a0) * i / n
		if axis == "X" then
			box(terrace, "QueuePost", a - 0.25, a + 0.25, 0.5, 3.4, t - 0.25, t + 0.25, GOLD_DARK)
		else
			box(terrace, "QueuePost", t - 0.25, t + 0.25, 0.5, 3.4, a - 0.25, a + 0.25, GOLD_DARK)
		end
	end
	if axis == "X" then
		box(terrace, "QueueRope", a0 + 0.25, a1 - 0.25, 2.9, 3.2, t - 0.1, t + 0.1, QUEUE, with(SMOOTH, DECOR))
	else
		box(terrace, "QueueRope", t - 0.1, t + 0.1, 2.9, 3.2, a0 + 0.25, a1 - 0.25, QUEUE, with(SMOOTH, DECOR))
	end
end
rope("Z", 1.5, 62, -36.5) -- entre allee 1 et 2 (ouverte au nord)
rope("Z", 9, 70, -29.5) -- entre allee 2 et 3 (ouverte au sud)
rope("Z", 1.5, 62, -22.5) -- entre allee 3 et 4 (ouverte au nord)
rope("Z", 12, 70, -15.5) -- bord est de l'allee 4 (ouvert au sud : sortie vers la cabine)
-- (au nord du dernier bout : le panneau ELEVATOR colle sur la cage, 02j)
local path = Instance.new("Folder")
path.Name = "QueuePath"
for i, q in {
	Vector2.new(-40.5, 2.75),
	Vector2.new(-40.5, 66),
	Vector2.new(-33, 66),
	Vector2.new(-33, 5),
	Vector2.new(-26, 5),
	Vector2.new(-26, 66),
	Vector2.new(-19, 66),
	Vector2.new(-19, 7),
} do
	part(path, "Point" .. i, Vector3.new(1, 1, 1), CFrame.new(q.X, 1, q.Y), Color3.new(0, 1, 0), MARKER)
end
path.Parent = terrace
-- 2026-11-20 (demande : "retire les murs autour qu'on puisse passer") : plus de barriere blanche,
-- de murs invisibles (Blocker*) ni de portail cote rue. La terrasse est ouverte sur la rue et la cour.
-- 2026-11-23 : plus de vitre rouge "TerraceGate" ("Opens with Floor 2") dans la porte de l'usine,
-- elle ne servait a rien (demande utilisateur).
terrace.Parent = annex
task.wait()

-- ===== BAS DE LA CAGE D'ASCENSEUR (x -9 -> -1, z 3 -> 11), vide jusqu'a l'etage 2 =====
-- Meme cage que FloorTemplate.Building.Elevator (02h) mais ouverte cote terrasse (-X) : les clients
-- entrent par la. La cabine apparait a l'achat de l'etage 2 (lot 5).
local shaft = Instance.new("Model")
shaft.Name = "ElevatorBase"
local EX0, EX1, EZ0, EZ1 = -9, -1, 3, 11
for _, c in { Vector2.new(EX0, EZ0), Vector2.new(EX1, EZ0), Vector2.new(EX0, EZ1), Vector2.new(EX1, EZ1) } do
	box(shaft, "ShaftPost", c.X - 0.35, c.X + 0.35, 0.5, H - 0.2, c.Y - 0.35, c.Y + 0.35, TRIM)
end
box(shaft, "ShaftPit", EX0 + 0.35, EX1 - 0.35, 0.5, 0.7, EZ0 + 0.35, EZ1 - 0.35, Color3.fromRGB(70, 74, 86), { TopSurface = Enum.SurfaceType.Inlet })
box(shaft, "ShaftGlass", EX0 + 0.35, EX1 - 0.35, 0.5, H - 0.2, EZ0 - 0.1, EZ0 + 0.1, GLASS, SHAFT_GLASS_PROPS)
box(shaft, "ShaftGlass", EX0 + 0.35, EX1 - 0.35, 0.5, H - 0.2, EZ1 - 0.1, EZ1 + 0.1, GLASS, SHAFT_GLASS_PROPS)
box(shaft, "ShaftGlass", EX1 - 0.1, EX1 + 0.1, 0.5, H - 0.2, EZ0 + 0.35, EZ1 - 0.35, GLASS, SHAFT_GLASS_PROPS)
box(shaft, "DoorFrame", EX0 - 0.3, EX0 + 0.3, 9, 9.6, EZ0 + 0.35, EZ1 - 0.35, TRIM)
box(shaft, "ShaftGlass", EX0 - 0.1, EX0 + 0.1, 9.6, H - 0.2, EZ0 + 0.35, EZ1 - 0.35, GLASS, SHAFT_GLASS_PROPS)
local liftSign = box(shaft, "Sign", EX0 - 0.5, EX0 - 0.3, 10, 12.4, EZ0 + 0.6, EZ1 - 0.6, Color3.fromRGB(70, 130, 220))
text(surfaceGui(liftSign, Enum.NormalId.Left, 30), "Text", "ELEVATOR", UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.92, 0.76), Color3.new(1, 1, 1), 3)
-- Marqueur : porte de la cabine cote terrasse (fin de la file d'attente des clients)
part(shaft, "ElevatorEntry", Vector3.new(2, 1, 2), CFrame.new(-11, 1, 7), Color3.new(0, 1, 0), MARKER)
shaft.Parent = annex

-- ===== SALLE DU REBIRTH (ancien bar a cocktails, x -45 -> 0, z 72 -> 135) =====
-- Vitre rouge "Reach Floor 10" dans la porte (z 96 -> 108). Dedans, visible des le debut par la
-- vitre et les fenetres : une grande machine doree qui brille (le but a long terme).
local room = Instance.new("Model")
room.Name = "RebirthRoom"
local CX, CZ = -22, 104
local NEON = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false })
box(room, "Rug", CX - 13, CX + 13, 0.5, 0.65, CZ - 13, CZ + 13, Color3.fromRGB(150, 40, 60), { TopSurface = Enum.SurfaceType.Inlet })
box(room, "Pedestal", CX - 7, CX + 7, 0.65, 2.4, CZ - 7, CZ + 7, Color3.fromRGB(70, 74, 86))
box(room, "PedestalTop", CX - 6.4, CX + 6.4, 2.4, 3.6, CZ - 6.4, CZ + 6.4, GOLD_DARK)
box(room, "PedestalGlow", CX - 7.1, CX + 7.1, 2.3, 2.5, CZ - 7.1, CZ + 7.1, Color3.fromRGB(255, 220, 90), NEON)
-- Machine : socle, grand bol vitre de jus dore, couvercle, etoile
local machine = Instance.new("Model")
machine.Name = "RebirthMachine"
box(machine, "Base", CX - 4.5, CX + 4.5, 3.6, 9, CZ - 4.5, CZ + 4.5, GOLD)
box(machine, "BaseBand", CX - 4.7, CX + 4.7, 5.6, 6.6, CZ - 4.7, CZ + 4.7, GOLD_DARK)
local button = box(machine, "Button", CX + 4.5, CX + 5, 6.6, 8.4, CZ - 1.2, CZ + 1.2, Color3.fromRGB(255, 60, 90), NEON)
box(machine, "Jar", CX - 3.8, CX + 3.8, 9, 21, CZ - 3.8, CZ + 3.8, Color3.fromRGB(255, 236, 160), with(SMOOTH, { Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }))
box(machine, "Juice", CX - 3.3, CX + 3.3, 9.1, 16.5, CZ - 3.3, CZ + 3.3, Color3.fromRGB(255, 200, 40), NEON)
box(machine, "Lid", CX - 4.2, CX + 4.2, 21, 22.4, CZ - 4.2, CZ + 4.2, GOLD)
box(machine, "LidTop", CX - 2, CX + 2, 22.4, 23.6, CZ - 2, CZ + 2, GOLD_DARK)
local star = part(machine, "Star", Vector3.new(3.2, 3.2, 0.8), CFrame.new(CX, 26, CZ) * CFrame.Angles(0, math.rad(90), math.rad(45)), Color3.fromRGB(255, 240, 120), NEON)
local light = Instance.new("PointLight")
light.Color = Color3.fromRGB(255, 210, 90)
light.Range = 30
light.Brightness = 2
light.Parent = star
local sparkle = Instance.new("ParticleEmitter")
sparkle.Name = "Sparkle"
sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
sparkle.Size = NumberSequence.new(0.6)
sparkle.Rate = 6
sparkle.Lifetime = NumberRange.new(1.2, 2)
sparkle.Speed = NumberRange.new(1, 2)
sparkle.SpreadAngle = Vector2.new(180, 180)
sparkle.LightEmission = 1
sparkle.Parent = star
machine.PrimaryPart = button
machine.Parent = room
-- Point du ProximityPrompt (E : "Rebirth: coming soon!", FloorService)
part(room, "PromptAnchor", Vector3.new(1, 1, 1), CFrame.new(CX + 7.5, 4, CZ), Color3.new(0, 1, 0), MARKER)
-- Grand panneau au mur du fond de la salle : "???" (nom cache, Config/Floors.RebirthRoomTitle)
local sign = box(room, "Sign", CX - 10, CX + 10, 26, 31, 134.4, 135, Color3.fromRGB(60, 30, 90))
text(surfaceGui(sign, Enum.NormalId.Front, 30), "Text", FloorsConfig.RebirthRoomTitle, UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8), GOLD, 4)
lockedGate(room, "RebirthGate", 96, 108, FloorsConfig.RebirthRoomTitle, FloorsConfig.RebirthLockedText)
-- Plafond de la salle (demande utilisateur du 2026-11-20), juste sous le chapeau des murs, avec
-- 2 neons dessous. Les poutres de l'annexe (34.6 -> 35.8) restent visibles en dessous.
box(room, "RoomCeiling", -45, 0, 35.8, 36.2, 72, 135, Color3.fromRGB(238, 242, 250)) -- = WALL de 02a
local LAMP = with(SMOOTH, { Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
for _, lz in { 88, 120 } do
	box(room, "LampHousing", CX - 4, CX + 4, 34, 34.6, lz - 1.4, lz + 1.4, Color3.fromRGB(124, 136, 162), DECOR)
	box(room, "LampTube", CX - 3.6, CX + 3.6, 33.8, 34, lz - 1, lz + 1, Color3.fromRGB(236, 246, 255), LAMP)
end
room.Parent = annex
task.wait()

-- ===== MARQUEURS (FloorTemplate : un jeu par etage) =====
local markers = Instance.new("Folder")
markers.Name = "Markers"
-- Apparition du joueur : juste apres la porte (en haut : la porte du balcon), tourne vers l'interieur
part(markers, "SpawnPoint", Vector3.new(2, 1, 2), CFrame.lookAt(Vector3.new(13, 1, 21), Vector3.new(55, 1, 85)), Color3.new(0, 1, 0), MARKER)
-- Arrivee des clients : rez-de-chaussee = trottoir ; etages 2+ = sortie de l'ascenseur sur le balcon
local mGround = Instance.new("Folder")
mGround.Name = "OnlyGround"
mGround.Parent = markers
local mUpper = Instance.new("Folder")
mUpper.Name = "OnlyUpper"
mUpper.Parent = markers
part(mGround, "CustomerEntry", Vector3.new(2, 1, 2), CFrame.new(64, 0.9, -16), Color3.new(0, 1, 0), MARKER)
part(mUpper, "CustomerEntry", Vector3.new(2, 1, 2), CFrame.new(1.5, 1, 7), Color3.new(0, 1, 0), MARKER)
-- Places devant le comptoir (dehors : la cour au rez-de-chaussee, le balcon en haut, meme hauteur)
for i = 1, 5 do
	local x = 49 + i * 5
	part(markers, "CustomerSpot" .. i, Vector3.new(2, 1, 2), CFrame.lookAt(Vector3.new(x, 0.9, 10.5), Vector3.new(x, 0.9, 20)), Color3.new(0, 1, 0), MARKER)
end
-- Postes et trajets des employes R6 (WorkerService). Le bas du marqueur = le sol.
local function spot(name: string, x: number, floorY: number, z: number)
	part(markers, name, Vector3.new(2, 1, 2), CFrame.new(x, floorY + 0.5, z), Color3.new(0, 0.6, 1), MARKER)
end
-- Plan du 2026-11-19 (soir) : etagere x 30-54 (z 126-134, plancher z 118-126), boite du tapis x 23-29,
-- table a jus x 9-35 (z 74-83), mixeurs x 8-48.5 (z 90-99), comptoir x 48-80 (z 14-18). Chemins sans obstacle.
spot("CollectorHome", 70, 0.5, 92) -- Fruit Picker : sur son poste, devant le verger
spot("ShelfDrop", 48, 0.7, 121) -- ou il pose les fruits (devant l'etagere, cote verger)
-- Operateurs des mixeurs : marqueurs BlenderNOperator dans Production.Blenders.BlenderN (02c).
spot("ServerHome", 30, 0.5, 66) -- Waiter : attend a cote de la table a jus (de retour le 2026-11-20)
spot("ServerPallet", 22, 0.5, 71.5) -- il prend les jus devant la table a jus (x 9-35, z 74-83)
spot("ServerCounter", 60, 0.5, 21.5) -- il les pose derriere le comptoir
markers.Parent = model

return "Annex + markers OK: base " .. #base:GetDescendants() .. ", etage " .. #model:GetDescendants()
