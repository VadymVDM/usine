--!strict
-- FloorTemplate (un etage, phase 1b), morceau 8/8 : l'escalier et ce qui change d'un etage a l'autre.
-- A lancer apres 02a (qui laisse vides les 2 voies d'escalier de la dalle et du sol de zone).
-- Cree FloorTemplate.Stairs et FloorTemplate.Building.Balcony / Elevator (detruits et recrees).
--
-- Zone STAIRS x 60 -> 108, z 50 -> 84. Voies (Config/Floors.Lanes) : A z 57-65, B z 70-78.
-- L'escalier qui monte de l'etage n est sur la voie A si n est impair, B si n est pair : il part du
-- milieu (x 64, sol) et monte a 45 degres vers le mur (x 100, +36). Le palier x 100 -> 108 est le sol
-- de l'etage du dessus. Variantes (dossiers "Only<Tag>", resolus par FloorAssembly au clonage) :
--   OnlyStairA / OnlyStairB : l'escalier (corps visible + 24 marches sans collision, rampe invisible
--     = la collision, garde-corps et murs invisibles sur les cotes).
--   OnlySolidA / OnlySolidB : la dalle + le sol de zone de la voie (quand il n'y a pas de trou).
--   OnlyHoleA / OnlyHoleB   : le trou (arrivee de l'escalier du dessous) : garde-corps vitres tout
--     autour, et OnlyClosed (etage a acheter) : vitre rouge d'achat au
--     palier + murs invisibles autour du trou.
--   Building.Balcony / Building.Elevator (OnlyUpper) : balcon des clients (z 0 -> 14) et cage vitree
--     de l'ascenseur (x -9 -> -1, z 3 -> 11). Plus de panneaux FLOORS (2026-11-20).
-- Attribut Shell = garde dans la coque bleue de l'etage ferme ; KeepLook = pas teinte (vitre rouge).
-- Doc : docs/systems/tour-etages.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local FloorsConfig = freshRequire(ReplicatedStorage.Shared.Config.Floors)
local Fruits = freshRequire(ReplicatedStorage.Shared.Config.Fruits)

local H = FloorsConfig.FloorHeight -- 36
local X0, X1 = FloorsConfig.StairStartX, FloorsConfig.StairEndX -- 64, 100 (palier jusqu a LandingEndX = 108)
local LANES = FloorsConfig.Lanes
local FLOOR_TOP = 0.5 -- dessus du sol de l'etage

local FLOOR = Color3.fromRGB(74, 80, 93) -- = 02a
local CONCRETE = Color3.fromRGB(150, 158, 176)
local STEP = Color3.fromRGB(196, 202, 216)
local STEP_EDGE = Color3.fromRGB(250, 206, 40) -- nez de marche jaune (signal d'usine)
local TRIM = Color3.fromRGB(124, 136, 162)
local RAIL = Color3.fromRGB(110, 120, 144)
local GLASS = Color3.fromRGB(176, 208, 228)
local BARRIER = Color3.fromRGB(255, 70, 80)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)

local STUDS = Enum.SurfaceType.Studs
local SMOOTH_SURF = Enum.SurfaceType.Smooth

local function apply(p: BasePart, color: Color3, props: { [string]: any }?)
	p.Anchored = true
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
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	apply(p, color, props)
	p.Parent = parent
	return p
end

local function box(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, props: { [string]: any }?): BasePart
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, props)
end

local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
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
local INVISIBLE = with(SMOOTH, { Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false })
local GLASS_PROPS = with(SMOOTH, { Material = Enum.Material.Glass, Transparency = 0.6, CastShadow = false, CanQuery = false })
-- Cage de l'ascenseur : plastique lisse transparent, PAS le materiau Glass (2026-11-20 : en haut de
-- l'ascenseur, les avatars etaient caches ; le Glass de Roblox masque ce qui est transparent derriere)
local SHAFT_GLASS_PROPS = with(SMOOTH, { Material = Enum.Material.SmoothPlastic, Transparency = 0.7, CastShadow = false, CanQuery = false })
local MARKER = with(SMOOTH, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })

local function folder(parent: Instance, name: string, shell: boolean?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	if shell then
		f:SetAttribute("Shell", true)
	end
	f.Parent = parent
	return f
end

local function surfaceGui(target: BasePart, face: Enum.NormalId, ppu: number, surface: Enum.SurfaceType?): SurfaceGui
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
	if strokePx > 0 then
		local s = Instance.new("UIStroke")
		s.Color = TEXT_STROKE
		s.Thickness = strokePx
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = t
	end
	t.Parent = parent
	return t
end

local model = ServerStorage:FindFirstChild("FloorTemplate")
assert(model, "Lancer 02a d'abord")
local building = model:FindFirstChild("Building") :: Folder
for _, old in { model:FindFirstChild("Stairs"), building:FindFirstChild("Balcony"), building:FindFirstChild("Elevator") } do
	if old then
		old:Destroy()
	end
end
local stairs = Instance.new("Folder")
stairs.Name = "Stairs"

-- ===== Garde-corps droit : poteaux + main courante + vitre (collision : la vitre) =====
-- Le long de X (z fixe) ou de Z (x fixe), de a0 a a1, au sol y0.
local function railing(parent: Instance, axis: string, a0: number, a1: number, t: number, y0: number)
	local RH = 3.6 -- hauteur
	local n = math.max(1, math.ceil((a1 - a0) / 4))
	local function b(name: string, p0: number, p1: number, ya: number, yb: number, th: number, color: Color3, props: { [string]: any }?)
		if axis == "X" then
			box(parent, name, p0, p1, ya, yb, t - th, t + th, color, props)
		else
			box(parent, name, t - th, t + th, ya, yb, p0, p1, color, props)
		end
	end
	for i = 0, n do
		local a = a0 + (a1 - a0) * i / n
		b("RailPost", a - 0.2, a + 0.2, y0, y0 + RH, 0.2, RAIL)
	end
	b("RailTop", a0 - 0.25, a1 + 0.25, y0 + RH, y0 + RH + 0.35, 0.25, TRIM)
	b("RailGlass", a0 + 0.2, a1 - 0.2, y0 + 0.4, y0 + RH - 0.1, 0.06, GLASS, GLASS_PROPS)
end

-- Morceau oblique (le long de X, a 45 degres) : centre au point (x, y, z) de la pente, longueur L.
local SLOPE = CFrame.Angles(0, 0, math.rad(45))
local function slopePart(parent: Instance, name: string, x: number, y: number, z: number, size: Vector3, color: Color3, props: { [string]: any }?): BasePart
	return part(parent, name, size, CFrame.new(x, y, z) * SLOPE, color, props)
end

-- ===== L'escalier d'une voie =====
local function buildStair(lane: string)
	local L = LANES[lane]
	local z0, z1 = L.z0, L.z1
	local zc, w = (z0 + z1) / 2, z1 - z0
	local f = folder(stairs, "OnlyStair" .. lane)
	local m = Instance.new("Model")
	m.Name = "Stair"
	-- Corps visible (beton) sous les marches : coin de x 64 (sol) a x 100 (+36), sans collision
	local body = Instance.new("WedgePart")
	body.Name = "StairBody"
	body.Size = Vector3.new(w, H, X1 - X0)
	body.CFrame = CFrame.new((X0 + X1) / 2, FLOOR_TOP + H / 2, zc) * CFrame.Angles(0, math.rad(90), 0)
	apply(body, CONCRETE, with(DECOR, { CanQuery = true }))
	body.Parent = m
	-- 24 marches de 1.5 x 1.5 (visuelles, sans collision) + nez de marche jaune
	local n = math.floor((X1 - X0) / 1.5 + 0.5)
	for i = 0, n - 1 do
		local xa = X0 + i * 1.5
		local top = FLOOR_TOP + 1.5 * (i + 1)
		box(m, "Step", xa, xa + 1.5, top - 1.5, top, z0 + 0.3, z1 - 0.3, STEP, with(DECOR, { TopSurface = Enum.SurfaceType.Inlet }))
		box(m, "StepNose", xa - 0.08, xa + 0.25, top - 0.12, top + 0.08, z0 + 0.4, z1 - 0.4, STEP_EDGE, with(SMOOTH, DECOR))
	end
	-- Collision : rampe invisible qui passe au milieu de chaque marche (decalee de 0.75 vers le bas
	-- de l'escalier) : le personnage monte sans buter ni sauter.
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Size = Vector3.new(w, H, X1 - X0)
	ramp.CFrame = CFrame.new((X0 + X1) / 2 - 0.75, FLOOR_TOP + H / 2, zc) * CFrame.Angles(0, math.rad(90), 0)
	apply(ramp, Color3.new(1, 1, 1), INVISIBLE)
	ramp.Parent = m
	box(m, "RampTop", X1 - 0.75, X1, FLOOR_TOP + H - 1, FLOOR_TOP + H, z0, z1, Color3.new(1, 1, 1), INVISIBLE)
	-- Garde-corps obliques des deux cotes (poteaux + main courante) + murs invisibles (pas de chute)
	local len = (X1 - X0) * math.sqrt(2)
	-- (poteaux au bord de la voie, a cote des marches et pas dedans : pas de faces confondues)
	for _, side in { z0 + 0.1, z1 - 0.1 } do
		for i = 0, 12 do
			local x = X0 + 1 + i * (X1 - X0 - 2) / 12
			local y = FLOOR_TOP + (x - X0) + 0.75
			box(m, "RailPost", x - 0.2, x + 0.2, y - 1.6, y + 3.3, side - 0.12, side + 0.12, RAIL, DECOR)
		end
		slopePart(m, "RailTop", (X0 + X1) / 2, FLOOR_TOP + H / 2 + 0.75 + 3.4, side, Vector3.new(len, 0.35, 0.34), TRIM, DECOR)
		slopePart(m, "RailGuard", (X0 + X1) / 2 - 0.75, FLOOR_TOP + H / 2 + 2.5, side, Vector3.new(len, 5, 0.3), Color3.new(1, 1, 1), INVISIBLE)
	end
	m.Parent = f
end
buildStair("A")
buildStair("B")
task.wait()

-- ===== Dalle pleine d'une voie (pas de trou) =====
for lane, L in LANES do
	local f = folder(stairs, "OnlySolid" .. lane, true)
	box(f, "Floor", X0, X1, -0.2, FLOOR_TOP, L.z0, L.z1, FLOOR, { TopSurface = Enum.SurfaceType.Inlet })
	-- (plus de sol de zone teinte depuis le 2026-11-20 : sol uni, voir 02a)
end

-- ===== Trou (arrivee de l'escalier du dessous) =====
for lane, L in LANES do
	local f = folder(stairs, "OnlyHole" .. lane, true)
	-- Garde-corps tout autour, sur la dalle juste au bord du trou (pas dans la voie : la main courante
	-- de l'escalier du dessous y passe), sauf cote palier (x 100) : on arrive par la
	railing(f, "X", X0 - 0.3, X1, L.z0 - 0.3, FLOOR_TOP)
	railing(f, "X", X0 - 0.3, X1, L.z1 + 0.3, FLOOR_TOP)
	railing(f, "Z", L.z0 - 0.3, L.z1 + 0.3, X0 - 0.3, FLOOR_TOP)
	-- (plus de panneau FLOORS au palier depuis le 2026-11-20 : selecteur en haut de l'ecran)
	-- Etage a acheter : vitre rouge au palier + murs invisibles autour du trou (on ne passe pas a
	-- cote de la vitre en sautant depuis le haut de l'escalier). Etage ouvert : pas de murs
	-- invisibles autour du trou (2026-11-20 : sauter dans le trou ramene juste a l'etage du dessous).
	local closed = folder(f, "OnlyClosed", true)
	box(closed, "Blocker", X0 - 0.6, X1, FLOOR_TOP, H - 0.2, L.z0 - 0.6, L.z0 - 0.4, Color3.new(), INVISIBLE)
	box(closed, "Blocker", X0 - 0.6, X1, FLOOR_TOP, H - 0.2, L.z1 + 0.4, L.z1 + 0.6, Color3.new(), INVISIBLE)
	box(closed, "Blocker", X0 - 0.6, X0 - 0.4, FLOOR_TOP, H - 0.2, L.z0 - 0.4, L.z1 + 0.4, Color3.new(), INVISIBLE)
	local gate = Instance.new("Model")
	gate.Name = "BuyGate"
	gate:SetAttribute("KeepLook", true)
	local barrier = box(gate, "Barrier", X1 + 0.2, X1 + 0.8, FLOOR_TOP, 12.5, L.z0, L.z1, BARRIER, with(SMOOTH, {
		Transparency = 0.55,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	}))
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local g = surfaceGui(barrier, face, 30, SMOOTH_SURF)
		text(g, "Lock", "\u{1F512}", UDim2.fromScale(0.35, 0.12), UDim2.fromScale(0.3, 0.2), Color3.fromRGB(255, 214, 80), 0)
		text(g, "FloorName", "FLOOR ?", UDim2.fromScale(0.04, 0.36), UDim2.fromScale(0.92, 0.16), Color3.new(1, 1, 1), 3)
		text(g, "Status", "$?", UDim2.fromScale(0.12, 0.54), UDim2.fromScale(0.76, 0.14), Color3.fromRGB(120, 255, 90), 3)
	end
	-- Point du ProximityPrompt (achat, FloorService)
	part(gate, "PromptAnchor", Vector3.new(1, 1, 1), CFrame.new(X1 - 1, FLOOR_TOP + 3, (L.z0 + L.z1) / 2), Color3.new(0, 1, 0), MARKER)
	gate.PrimaryPart = barrier
	gate.Parent = closed
	-- au-dessus de la vitre, jusqu'au plafond ; et les murs du trou prolonges jusqu'a la vitre
	box(closed, "Blocker", X1 + 0.2, X1 + 0.8, 12.5, H - 0.2, L.z0, L.z1, Color3.new(), INVISIBLE)
	box(closed, "Blocker", X1, X1 + 0.8, FLOOR_TOP, H - 0.2, L.z0 - 0.6, L.z0 - 0.4, Color3.new(), INVISIBLE)
	box(closed, "Blocker", X1, X1 + 0.8, FLOOR_TOP, H - 0.2, L.z1 + 0.4, L.z1 + 0.6, Color3.new(), INVISIBLE)
end
-- Texte d'exemple sur les vitres du modele (FloorService ecrit le vrai : etage, rarete, prix)
for _, d in stairs:GetDescendants() do
	if d:IsA("TextLabel") and d.Name == "FloorName" then
		d.Text = string.format(FloorsConfig.TitleFormat, 2, string.upper(Fruits.Rarities[2].name))
	end
end

stairs.Parent = model
task.wait()

-- ===== Balcon des clients (etages 2+) : z 0 -> 14 devant la facade, au-dessus de la cour =====
local balcony = folder(building, "Balcony", true)
local bUpper = folder(balcony, "OnlyUpper")
box(bUpper, "BalconyFloor", 0, 110, -0.2, FLOOR_TOP, 0, 14, FLOOR, { TopSurface = Enum.SurfaceType.Inlet })
box(bUpper, "BalconyEdge", -0.15, 110.15, -0.9, -0.2, -0.15, 14, TRIM) -- chant sous la dalle
box(bUpper, "BalconyBridge", -1, 0, -0.2, FLOOR_TOP, 3, 11, FLOOR, { TopSurface = Enum.SurfaceType.Inlet }) -- vers l'ascenseur
railing(bUpper, "X", 0.3, 109.7, 0.3, FLOOR_TOP)
railing(bUpper, "Z", 0.6, 13.7, 109.7, FLOOR_TOP)
railing(bUpper, "Z", 0.6, 2.8, 0.3, FLOOR_TOP)
railing(bUpper, "Z", 11.2, 13.7, 0.3, FLOOR_TOP)
-- (plus de murs invisibles au balcon depuis le 2026-11-20 : "pas besoin de nous bloquer", sauter
-- dans la cour ne gene pas)

-- ===== Cage vitree de l'ascenseur (etages 2+ ; le bas est dans BaseTemplate.Annex, 02f) =====
-- x -9 -> -1, z 3 -> 11. Ouverte cote balcon (+X) ; la cabine (phase 1b lot 5) monte dedans.
local elevator = folder(building, "Elevator", true)
local eUpper = folder(elevator, "OnlyUpper")
local EX0, EX1, EZ0, EZ1 = -9, -1, 3, 11
for _, c in { Vector2.new(EX0, EZ0), Vector2.new(EX1, EZ0), Vector2.new(EX0, EZ1), Vector2.new(EX1, EZ1) } do
	box(eUpper, "ShaftPost", c.X - 0.35, c.X + 0.35, -0.2, H - 0.2, c.Y - 0.35, c.Y + 0.35, TRIM)
end
box(eUpper, "ShaftRing", EX0 + 0.35, EX1 - 0.35, -0.2, 0.5, EZ0 - 0.3, EZ0 + 0.3, TRIM)
box(eUpper, "ShaftRing", EX0 + 0.35, EX1 - 0.35, -0.2, 0.5, EZ1 - 0.3, EZ1 + 0.3, TRIM)
box(eUpper, "ShaftRing", EX0 - 0.3, EX0 + 0.3, -0.2, 0.5, EZ0 + 0.35, EZ1 - 0.35, TRIM)
box(eUpper, "ShaftGlass", EX0 + 0.35, EX1 - 0.35, 0.5, H - 0.2, EZ0 - 0.1, EZ0 + 0.1, GLASS, SHAFT_GLASS_PROPS)
box(eUpper, "ShaftGlass", EX0 + 0.35, EX1 - 0.35, 0.5, H - 0.2, EZ1 - 0.1, EZ1 + 0.1, GLASS, SHAFT_GLASS_PROPS)
box(eUpper, "ShaftGlass", EX0 - 0.1, EX0 + 0.1, 0.5, H - 0.2, EZ0 + 0.35, EZ1 - 0.35, GLASS, SHAFT_GLASS_PROPS)
box(eUpper, "DoorFrame", EX1 - 0.3, EX1 + 0.3, 9, 9.6, EZ0 + 0.35, EZ1 - 0.35, TRIM) -- linteau de la porte du balcon
-- (cote balcon : pas de vitre en dessous du linteau = sortie ; au-dessus, vitre)
box(eUpper, "ShaftGlass", EX1 - 0.1, EX1 + 0.1, 9.6, H - 0.2, EZ0 + 0.35, EZ1 - 0.35, GLASS, SHAFT_GLASS_PROPS)
-- Marqueur : sortie de l'ascenseur sur le balcon (clients des etages 2+, CustomerService)
part(eUpper, "ElevatorExit", Vector3.new(2, 1, 2), CFrame.new(1.5, 1, 7), Color3.new(0, 1, 0), MARKER):SetAttribute("Shell", false)

return "Stairs OK: " .. #stairs:GetDescendants() .. " objets ; FloorTemplate " .. #model:GetDescendants()
