--!strict
-- FloorTemplate (un etage, phase 1b), morceau 3/6 : production. Etagere a fruits (1 rangee de 10 caisses) devant le mur du
-- fond, plancher de depot, tapis roulant qui monte puis longe la rangee des 4 MIXEURS
-- (Production.Blenders.Blender1..4, fonction buildBlender), table a jus devant la rangee.
-- A lancer apres 02a. Recree le dossier Production.
-- Bacs : Bin1..10 = les 10 fruits de la rarete de l'etage (tour d'etages, 2026-11-20 : une seule
-- rangee de 10 caisses au lieu de 3 x 10, moins de pieces par etage).
-- Zones pour le code (invisibles) : FruitDropPad.PadZone (pad "Drop Fruits"), TakeJuicePad.PadZone
-- (pad "Take Juices"), JuicePile (gobelets de la table a jus), JuiceLabelAnchor, ConveyorStart / ConveyorTurn. Etagere, caisses et plancher : coordonnees
-- AVANT le miroir et le decalage de place() (voir plus bas). Tapis, mixeurs et table (refonte du
-- 2026-11-19) : coordonnees FINALES (MIRROR = false), voir le bloc "A PARTIR D'ICI".
-- Doc : docs/systems/carte-bases.md, docs/systems/chaine-production.md

local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_LIGHT = Color3.fromRGB(196, 156, 108)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local CRATE = Color3.fromRGB(206, 160, 104)
local CRATE_INSIDE = Color3.fromRGB(140, 100, 64)
local METAL = Color3.fromRGB(186, 192, 200)
local METAL_DARK = Color3.fromRGB(96, 102, 114)
local BELT = Color3.fromRGB(52, 54, 62)
local RAIL = Color3.fromRGB(255, 196, 40)
local BLENDER = Color3.fromRGB(232, 62, 80)
local BLENDER_DARK = Color3.fromRGB(184, 40, 58)
local CREAM = Color3.fromRGB(255, 244, 222)
local GLASS = Color3.fromRGB(200, 236, 250)
local JUICE = Color3.fromRGB(255, 150, 40)
local MAT = Color3.fromRGB(255, 232, 160)
local DROP_MAT = Color3.fromRGB(255, 160, 60)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)

-- Placement du bloc : les coordonnees ecrites plus bas sont retournees en X (miroir x' = MIRROR_X - x)
-- puis decalees de DZ en Z. Plan du 2026-11-19 (soir) : le bar a jus passe a DROITE (vu de la route),
-- dans l'espace vide, et ne chevauche plus le verger. Resultat :
--   etagere x 30 -> 54, z 131 -> 134.7 (contre le mur) ; plancher de depot z 118 -> 131.2. Toutes les pieces sont
--   alignees sur les axes : le miroir ne change que leur position.
local MIRROR_X = 58
local DZ = 20

local MIRROR = true -- faux pour les blocs ecrits en coordonnees finales (tapis, mixeurs, table)

local function place(cf: CFrame): CFrame
	if not MIRROR then
		return cf
	end
	local p = cf.Position
	return CFrame.new(MIRROR_X - p.X, p.Y, p.Z + DZ) * cf.Rotation
end

local STUDS = Enum.SurfaceType.Studs
local SMOOTH_SURF = Enum.SurfaceType.Smooth

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = place(cf)
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
local GLASS_PROPS = with(SMOOTH, { Material = Enum.Material.Glass, Transparency = 0.5, CastShadow = false })
local NEON = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
local GOLD = Color3.fromRGB(255, 196, 48)
local RAIL_BLUE = Color3.fromRGB(60, 150, 255)

-- Piece de decor d'un niveau (2026-11-19 soir, "on doit voir l'usine s'ameliorer") : visible
-- seulement si LookLevel <= niveau de `id` <= LookMaxLevel (LevelLookController, client). Sans
-- collision, sauf `keepCollide` (table a jus : chaque taille de table garde la sienne).
local function look(p: BasePart, id: string, level: number, maxLevel: number?, keepCollide: boolean?): BasePart
	p:SetAttribute("LookId", id)
	p:SetAttribute("LookLevel", level)
	if maxLevel then
		p:SetAttribute("LookMaxLevel", maxLevel)
	end
	if not keepCollide then
		p.CanCollide = false
		p.CanTouch = false
	end
	return p
end

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

local function label(parent: Instance, name: string, text: string, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.05, 0.1)
	t.Size = UDim2.fromScale(0.9, 0.8)
	t.FontFace = FONT
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT_STROKE
	stroke.Thickness = strokePx
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = t
	t.Parent = parent
	return t
end

local model = game:GetService("ServerStorage"):FindFirstChild("FloorTemplate")
assert(model, "Lancer 02a d'abord")
local old = model:FindFirstChild("Production")
if old then
	old:Destroy()
end
local production = Instance.new("Folder")
production.Name = "Production"

-- ===== ETAGERE A FRUITS (x 4..28, z 111.5..114.3 : UNE rangee de caisses, 10 fruits par etage) =====
-- 2026-11-20 : avant, 8 studs de profondeur (prevu pour 3 rangees) dont 6 vides derriere la rangee.
-- 2026-11-20 (soir) : etagere + caisses reculees de SHELF_DZ contre le mur du fond (final z 135 ;
-- le rebord de la fenetre depasse a 134.8, le dos s'arrete a 134.7). Bin10 (le plus rare) reste
-- au bout cote tapis (boite d'alimentation), Bin1 (pommes...) a l'autre bout.
local SHELF_DZ = 5.5
local RACK_BACK = 108.8 + SHELF_DZ -- dos de l'etagere, juste derriere les caisses (cz + 1 + marge)
local rack = Instance.new("Model")
rack.Name = "FruitRack"
box(rack, "SideLeft", 3.4, 4, 0.5, 6.6, 105.6 + SHELF_DZ, RACK_BACK + 0.4, WOOD_DARK)
box(rack, "SideRight", 28, 28.6, 0.5, 6.6, 105.6 + SHELF_DZ, RACK_BACK + 0.4, WOOD_DARK)
box(rack, "Back", 4, 28, 0.5, 5.6, RACK_BACK, RACK_BACK + 0.4, WOOD)
for i = 0, 0 do
	local top = 1.4 + i * 1.4
	local z0 = 106 + SHELF_DZ + i * 2.6
	box(rack, "Tier" .. i, 4, 28, 0.5, top, z0, RACK_BACK, if i % 2 == 0 then WOOD_LIGHT else WOOD)
	box(rack, "TierLip" .. i, 4, 28, top - 0.35, top + 0.1, z0 - 0.1, z0 + 0.15, WOOD_DARK)
end
local rackSign = box(rack, "SignBoard", 8, 24, 5.6, 8.4, RACK_BACK - 0.1, RACK_BACK + 0.4, Color3.fromRGB(255, 160, 60))
label(surfaceGui(rackSign, Enum.NormalId.Front), "Text", "FRUIT SHELF", 4)
rack.Parent = production
task.wait()

-- Caisses : fond (BinN, ou se posent les fruits) + 4 rebords
local bins = Instance.new("Folder")
bins.Name = "Bins"
local rims = Instance.new("Folder")
rims.Name = "BinRims"
for i = 0, 0 do
	local base = 1.4 + i * 1.4 -- dessus du gradin
	local cz = 107.3 + SHELF_DZ + i * 2.6
	for c = 0, 9 do
		local cx = 5.2 + c * 2.4
		local n = i * 10 + c + 1
		box(bins, "Bin" .. n, cx - 0.85, cx + 0.85, base, base + 0.45, cz - 0.85, cz + 0.85, CRATE_INSIDE)
		box(rims, "Rim", cx - 1, cx + 1, base, base + 0.95, cz - 1, cz - 0.85, CRATE)
		box(rims, "Rim", cx - 1, cx + 1, base, base + 0.95, cz + 0.85, cz + 1, CRATE)
		box(rims, "Rim", cx - 1, cx - 0.85, base, base + 0.95, cz - 0.85, cz + 0.85, CRATE)
		box(rims, "Rim", cx + 0.85, cx + 1, base, base + 0.95, cz - 0.85, cz + 0.85, CRATE)
	end
	task.wait()
end
bins.Parent = production
rims.Parent = production

-- Plancher devant l'etagere (le pad "Drop Fruits" est pose dessus, plus bas en coordonnees finales).
-- Va jusqu'au devant de l'etagere (105.6 + SHELF_DZ ; 105.8 avant le recul).
local deck = Instance.new("Model")
deck.Name = "BinsDeck"
for i = 0, 11 do
	local x0 = 4 + i * 2
	-- sol ou l'on marche : studs "creux" (Inlet), regle des 2 studs (docs/style.md)
	box(deck, "Plank", x0 + 0.05, x0 + 1.95, 0.5, 0.7, 98.2, 111.2, if i % 2 == 0 then WOOD else WOOD_LIGHT, { TopSurface = Enum.SurfaceType.Inlet })
end
deck.Parent = production
task.wait()

-- =====================================================================================
-- A PARTIR D'ICI : COORDONNEES FINALES de la base (pas de miroir, pas de DZ). Refonte du mixeur
-- (2026-11-19) : 4 mixeurs en rangee, tapis qui longe la rangee, table a jus elargie.
--   Mixeurs : x 8 -> 48.5 (centres 12.5, 23, 33.5, 44 ; meuble 9 x 9, ecart 1.5), z 90 -> 99,
--             panneau (bouton vert + bec) tourne vers la table (-Z).
--   Allee devant les panneaux : z 83 -> 90 (joueur + operateur, pad de l'operateur 5 x 5).
--   Table a jus : x 9 -> 35, z 74 -> 83 (les gobelets sautent du bec jusqu'a la table).
--   Tapis : monte de la boite (x 26, z 130) jusqu'a la rangee (z 101.5, y 16.5), puis longe la
--           rangee derriere les bols (x 6.5 -> 50) ; une goulotte par bol.
--   Chemin du joueur : etagere -> contourne la rangee par l'est (x 48.5 -> 64) -> allee / table.
--   La porte du bar a cocktails (mur x 0-1, z 96-108) reste libre (rangee a partir de x 8).
MIRROR = false

-- ===== PADS D'ACTION (2026-11-19) : on se tient dessus, pas de touche E =====
-- Production.<Nom> : PadBase, PadTop (+ BillboardGui Tag : Title), PadGlow (neon), PadZone (zone
-- testee par ProductionService). 7 x 7, meme forme que les pads d'employes.
--   FruitDropPad "Drop Fruits" (orange) : au milieu du plancher de l'etagere (x 38.5-45.5, z 118.5-125.5)
--   TakeJuicePad "Take Juices" (rose) : devant la table a jus (x 18.5-25.5, z 66.5-73.5)
local function actionPad(name: string, title: string, cx: number, cz: number, floorY: number, baseColor: Color3, topColor: Color3, glowColor: Color3)
	local h = 3.5
	local pad = Instance.new("Model")
	pad.Name = name
	box(pad, "PadBase", cx - h, cx + h, floorY, floorY + 0.5, cz - h, cz + h, baseColor, { CastShadow = false })
	local top = box(pad, "PadTop", cx - h + 0.55, cx + h - 0.55, floorY + 0.5, floorY + 0.8, cz - h + 0.55, cz + h - 0.55, topColor, {
		CastShadow = false,
	})
	local glow = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
	local g0, g1, gy0, gy1 = h - 0.3, h - 0.08, floorY + 0.5, floorY + 0.62
	box(pad, "PadGlow", cx - g1, cx + g1, gy0, gy1, cz - g1, cz - g0, glowColor, glow)
	box(pad, "PadGlow", cx - g1, cx + g1, gy0, gy1, cz + g0, cz + g1, glowColor, glow)
	box(pad, "PadGlow", cx - g1, cx - g0, gy0, gy1, cz - g0, cz + g0, glowColor, glow)
	box(pad, "PadGlow", cx + g0, cx + g1, gy0, gy1, cz - g0, cz + g0, glowColor, glow)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(10, 2.2)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	tag.MaxDistance = 70
	tag.LightInfluence = 0
	tag.Adornee = top
	local t = label(tag, "Title", title, 3)
	t.Position = UDim2.fromScale(0, 0)
	t.Size = UDim2.fromScale(1, 1)
	tag.Parent = top
	box(pad, "PadZone", cx - h, cx + h, floorY - 0.2, floorY + 5, cz - h, cz + h, Color3.new(1, 0, 0), MARKER)
	pad.PrimaryPart = top
	pad.Parent = production
end
actionPad("FruitDropPad", "Drop Fruits", 42, 122, 0.7, Color3.fromRGB(200, 96, 20), DROP_MAT, Color3.fromRGB(255, 130, 0))
actionPad("TakeJuicePad", "Take Juices", 22, 70, 0.5, Color3.fromRGB(196, 40, 110), Color3.fromRGB(255, 130, 190), Color3.fromRGB(255, 40, 160))

local BLENDER_X = { 12.5, 23, 33.5, 44 }
local BLENDER_FRONT_Z = 90
local BELT_Y = 16.5 -- dessus du tapis qui longe la rangee
local BELT_Z = 101.5
local PAD_BASE = Color3.fromRGB(38, 128, 52)
local PAD_TOP = Color3.fromRGB(100, 204, 78)
local PAD_GLOW = Color3.fromRGB(110, 236, 84)

-- ===== TAPIS ROULANT : boite au bout de l'etagere -> monte -> longe la rangee =====
-- Look par niveau de Conveyor Speed (2026-11-19 soir) : 2 = baguettes neon sous les rails,
-- 4 = moteur turbo sur la boite, 6 = rails bleus, 8 = panneau TURBO, 10 = rails et coins dores +
-- etincelles. Les lattes defilent plus vite a chaque niveau (LevelLookController).
local CONVEYOR = "ConveyorSpeed"
local conveyor = Instance.new("Model")
conveyor.Name = "Conveyor"
-- Boite d'alimentation au bout de l'etagere (x 23.4 -> 28.6, z 127.5 -> 133.5)
box(conveyor, "Feeder", 23.4, 28.6, 0.5, 4.2, 127.5, 133.5, METAL_DARK)
box(conveyor, "FeederTop", 23.2, 28.8, 4.2, 4.6, 127.3, 133.7, RAIL)
-- Niveau 4 : moteur turbo sur le cote de la boite (cote panneau Conveyor)
look(box(conveyor, "TurboMotor", 21.9, 23.4, 1.1, 3.7, 128.6, 132.4, Color3.fromRGB(70, 74, 86)), CONVEYOR, 4)
look(box(conveyor, "TurboStripe", 21.85, 23.4, 2.2, 2.6, 128.55, 132.45, Color3.fromRGB(230, 50, 50)), CONVEYOR, 4)
for _, z in { 129.4, 131.6 } do
	look(box(conveyor, "TurboPipe", 22.3, 22.9, 3.7, 5.4, z - 0.3, z + 0.3, METAL), CONVEYOR, 4)
end
-- Niveau 8 : panneau TURBO sur la face avant de la boite
local turboSign = look(box(conveyor, "TurboSign", 23.8, 28.2, 1.4, 3.6, 127.32, 127.5, Color3.fromRGB(30, 30, 40)), CONVEYOR, 8)
label(surfaceGui(turboSign, Enum.NormalId.Front), "Text", "TURBO", 3).TextColor3 = Color3.fromRGB(255, 220, 60)
-- Niveau 10 : coins dores + etincelles
for _, c in { { 23.2, 127.3 }, { 28.8, 127.3 }, { 23.2, 133.7 }, { 28.8, 133.7 } } do
	local corner = look(box(conveyor, "GoldCorner", c[1] - 0.35, c[1] + 0.35, 4.2, 4.95, c[2] - 0.35, c[2] + 0.35, GOLD, SMOOTH), CONVEYOR, 10)
	if c[1] < 25 and c[2] < 130 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		sparkle.Size = NumberSequence.new(0.6, 0)
		sparkle.Lifetime = NumberRange.new(0.8, 1.2)
		sparkle.Rate = 6
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.LightEmission = 1
		sparkle.Parent = corner
	end
end
local A = Vector3.new(26, 4.8, 130) -- debut du tapis (dessus de la boite)
local T = Vector3.new(26, BELT_Y, BELT_Z) -- haut de la montee = sur le tapis de la rangee
local function beltBetween(name: string, from: Vector3, to: Vector3, width: number)
	local dir = (to - from).Unit
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	part(conveyor, name, Vector3.new(width, 0.4, length), cf * CFrame.new(0, -0.2, 0), BELT, SMOOTH)
	for _, side in { -1, 1 } do
		-- Rails : jaunes (niveaux 1-5), bleus (6-9), dores (10)
		local railSize = Vector3.new(0.3, 0.9, length)
		local railCf = cf * CFrame.new(side * (width / 2 + 0.15), 0.1, 0)
		look(part(conveyor, "Rail", railSize, railCf, RAIL), CONVEYOR, 0, 5)
		look(part(conveyor, "Rail", railSize, railCf, RAIL_BLUE), CONVEYOR, 6, 9)
		look(part(conveyor, "Rail", railSize, railCf, GOLD, SMOOTH), CONVEYOR, 10)
		-- Niveau 2 : baguette neon verte sous le rail
		local glowCf = cf * CFrame.new(side * (width / 2 + 0.15), -0.45, 0)
		look(part(conveyor, "RailGlow", Vector3.new(0.2, 0.18, length - 0.4), glowCf, Color3.fromRGB(80, 255, 120), NEON), CONVEYOR, 2)
	end
	local slats = math.floor(length / 2)
	for i = 1, slats - 1 do
		local p = from + dir * (i * 2)
		part(conveyor, "Slat", Vector3.new(width - 0.2, 0.06, 0.3), CFrame.lookAt(p, p + dir) * CFrame.new(0, 0.02, 0), Color3.fromRGB(80, 84, 94), with(SMOOTH, DECOR))
	end
end
beltBetween("Belt", A, T + Vector3.new(0, 0, 1.3), 3)
-- Pieds de la montee
for _, t in { 0.35, 0.7 } do
	local p = A + (T - A) * t
	for _, side in { -1, 1 } do
		local x = p.X + side * 1.4
		box(conveyor, "Leg", x - 0.25, x + 0.25, 0.5, p.Y - 0.45, p.Z - 0.25, p.Z + 0.25, METAL_DARK)
	end
end
-- Tapis de la rangee, derriere les bols (les fruits roulent jusqu'a la goulotte de leur bol)
local rowA = Vector3.new(6.5, BELT_Y, BELT_Z)
local rowB = Vector3.new(50, BELT_Y, BELT_Z)
beltBetween("RowBelt", rowA, rowB, 2.6)
for _, x in { 7, 17.75, 28.25, 38.75, 49.5 } do
	box(conveyor, "RowLeg", x - 0.3, x + 0.3, 0.5, BELT_Y - 0.4, BELT_Z - 0.3, BELT_Z + 0.3, METAL_DARK)
	box(conveyor, "RowLegFoot", x - 0.7, x + 0.7, 0.5, 0.8, BELT_Z - 0.7, BELT_Z + 0.7, METAL_DARK)
end
-- Embouts jaunes aux deux bouts du tapis
for _, x in { 6.2, 50.3 } do
	box(conveyor, "BeltCap", x - 0.3, x + 0.3, BELT_Y - 0.5, BELT_Y + 0.6, BELT_Z - 1.6, BELT_Z + 1.6, RAIL)
end
conveyor.Parent = production
box(production, "ConveyorStart", A.X - 0.5, A.X + 0.5, A.Y + 0.2, A.Y + 1.2, A.Z - 0.5, A.Z + 0.5, Color3.new(1, 0, 0), MARKER)
box(production, "ConveyorTurn", T.X - 0.5, T.X + 0.5, T.Y + 0.2, T.Y + 1.2, T.Z - 0.5, T.Z + 0.5, Color3.new(1, 0, 0), MARKER)
task.wait()

-- ===== MIXEURS : un modele reutilisable, 4 exemplaires en rangee =====
-- Production.Blenders.BlenderN (Model) :
--   Build : les pieces de la machine (fantome bleu tant que le mixeur 2-4 n'est pas achete ;
--           animees par BlenderFxController). Panel (prompt E "Blend"), ButtonGo (l'operateur
--           appuie dessus), Spout / SpoutTip (les gobelets sautent de la), Juice (cache au repos),
--           Blade, BowlFloor (marqueur invisible : fond du bol, les fruits s'y empilent).
--   Chute : goulotte du tapis jusqu'au bol (decor, hors Build).
--   FeedPoint (au-dessus de la goulotte, sur le tapis), BowlLabelAnchor ("3/5"),
--   BlenderNOperator (place de l'operateur, bas = sol) : marqueurs invisibles.
--   Operator : pad vert de l'operateur (UpgradeId OperatorN, marcher dessus = embaucher).
--   Attribut UpgradeId "BlenderN" pour les mixeurs 2 a 4 (le 1 est offert).
-- `origin` = milieu du bas de la facade (au sol), face avant vers -Z.
local blendersFolder = Instance.new("Folder")
blendersFolder.Name = "Blenders"

local function padTag(parent: BasePart, title: string, price: string)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(9, 3.6)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	tag.Adornee = parent
	local t = label(tag, "Title", title, 3)
	t.Position = UDim2.fromScale(0, 0)
	t.Size = UDim2.fromScale(1, 0.55)
	local p = label(tag, "Price", price, 3)
	p.Position = UDim2.fromScale(0.15, 0.55)
	p.Size = UDim2.fromScale(0.7, 0.45)
	p.TextColor3 = Color3.fromRGB(120, 255, 90)
	tag.Parent = parent
end

local function buildBlender(index: number, origin: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "Blender" .. index
	-- Tous les mixeurs ont un id (2026-11-19 soir : 5 niveaux chacun ; le 1 est offert au niveau 1)
	local id = "Blender" .. index
	m:SetAttribute("UpgradeId", id)
	local b = Instance.new("Model")
	b.Name = "Build"
	b.Parent = m
	local ox, oy, oz = origin.X, origin.Y, origin.Z
	-- Boite en coordonnees locales : x par rapport au centre, z depuis la facade (0 -> 9)
	local function lbox(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, props: { [string]: any }?): BasePart
		return box(parent, name, ox + x0, ox + x1, oy + y0, oy + y1, oz + z0, oz + z1, color, props)
	end
	for _, f in { { -3.9, 0.6 }, { 3.9, 0.6 }, { -3.9, 8.4 }, { 3.9, 8.4 } } do
		lbox(b, "Foot", f[1] - 0.6, f[1] + 0.6, 0.05, 0.5, f[2] - 0.6, f[2] + 0.6, METAL_DARK)
	end
	local cabinet = lbox(b, "Cabinet", -4.5, 4.5, 0.5, 5.1, 0, 9, BLENDER)
	lbox(b, "CabinetStripe", -4.6, 4.6, 2.1, 2.7, -0.1, 9.1, BLENDER_DARK)
	-- Bandeau du meuble : creme (niveaux 0-3), dore (4-5)
	look(lbox(b, "Trim", -4.8, 4.8, 5.1, 5.6, -0.3, 9.3, CREAM), id, 0, 3)
	look(lbox(b, "Trim", -4.8, 4.8, 5.1, 5.6, -0.3, 9.3, GOLD), id, 4)
	-- Niveau 2 : montants chromes aux 4 coins du meuble
	for _, c in { { -4.5, 0 }, { 4.5, 0 }, { -4.5, 9 }, { 4.5, 9 } } do
		look(lbox(b, "ChromePost", c[1] - 0.22, c[1] + 0.22, 0.5, 5.1, c[2] - 0.22, c[2] + 0.22, METAL, SMOOTH), id, 2)
	end
	-- Panneau de commande en facade (vers la table a jus) : bouton vert a gauche (vu de face)
	local panel = lbox(b, "Panel", -3.3, 3.3, 2.9, 4.8, -0.3, 0, CREAM)
	label(surfaceGui(panel, Enum.NormalId.Front), "Text", "BLENDER " .. index, 3)
	lbox(b, "ButtonGo", 2.6, 3.8, 1.1, 1.9, -0.4, -0.1, Color3.fromRGB(80, 220, 90), with(SMOOTH, { Material = Enum.Material.Neon }))
	lbox(b, "ButtonStop", -3.8, -2.6, 1.1, 1.9, -0.4, -0.1, Color3.fromRGB(240, 60, 60), SMOOTH)
	-- Bec verseur au milieu de la facade, au-dessus de l'allee (les gobelets sautent vers la table)
	lbox(b, "Spout", -0.7, 0.7, 1.7, 2.7, -1.5, -0.1, METAL)
	lbox(b, "SpoutTip", -0.5, 0.5, 1.1, 1.7, -1.5, -0.9, METAL)
	-- Bol en verre
	lbox(b, "Collar", -3.2, 3.2, 5.6, 6.6, 1.3, 7.7, METAL)
	lbox(b, "JarBase", -3.5, 3.5, 6.6, 6.9, 1, 8, METAL_DARK)
	lbox(b, "BowlFloor", -3, 3, 6.9, 7, 1.5, 7.5, Color3.new(1, 0, 0), MARKER)
	-- Bol en verre : clair (niveaux 0-4), verre dore qui brille (5)
	local GOLD_GLASS = Color3.fromRGB(255, 226, 130)
	for variant, color in { GLASS, GOLD_GLASS } do
		local minLevel, maxLevel = if variant == 1 then 0 else 5, if variant == 1 then 4 else nil
		look(lbox(b, "JarWall", -3.5, 3.5, 6.9, 14.1, 1, 1.3, color, GLASS_PROPS), id, minLevel, maxLevel)
		look(lbox(b, "JarWall", -3.5, 3.5, 6.9, 14.1, 7.7, 8, color, GLASS_PROPS), id, minLevel, maxLevel)
		look(lbox(b, "JarWall", -3.5, -3.2, 6.9, 14.1, 1.3, 7.7, color, GLASS_PROPS), id, minLevel, maxLevel)
		look(lbox(b, "JarWall", 3.2, 3.5, 6.9, 14.1, 1.3, 7.7, color, GLASS_PROPS), id, minLevel, maxLevel)
	end
	-- Jus opaque (une piece transparente derriere du verre n'est pas dessinee par Roblox) ;
	-- le client le cache au repos et le fait monter pendant le mixage.
	lbox(b, "Juice", -3.15, 3.15, 6.9, 10.6, 1.35, 7.65, JUICE, with(SMOOTH, { CanCollide = false }))
	-- Rebord du bol : creme (niveaux 0-3), dore (4-5)
	for variant, color in { CREAM, GOLD } do
		local minLevel, maxLevel = if variant == 1 then 0 else 4, if variant == 1 then 3 else nil
		look(lbox(b, "RimFront", -3.7, 3.7, 14.1, 14.5, 0.8, 1.4, color), id, minLevel, maxLevel)
		look(lbox(b, "RimBack", -3.7, 3.7, 14.1, 14.5, 7.6, 8.2, color), id, minLevel, maxLevel)
		look(lbox(b, "RimLeft", -3.7, -3.1, 14.1, 14.5, 1.4, 7.6, color), id, minLevel, maxLevel)
		look(lbox(b, "RimRight", 3.1, 3.7, 14.1, 14.5, 1.4, 7.6, color), id, minLevel, maxLevel)
	end
	lbox(b, "Handle", -4.4, -3.5, 8.5, 13.1, 3.9, 5.1, BLENDER_DARK)
	lbox(b, "Blade", -1.8, 1.8, 7, 7.2, 4.2, 4.8, METAL, with(SMOOTH, DECOR))
	-- Niveau 3 : anneau neon bleu sous le bol (autour du col)
	local RING = Color3.fromRGB(60, 220, 255)
	look(lbox(b, "NeonRing", -3.45, 3.45, 5.6, 5.9, 1.05, 1.3, RING, NEON), id, 3)
	look(lbox(b, "NeonRing", -3.45, 3.45, 5.6, 5.9, 7.7, 7.95, RING, NEON), id, 3)
	look(lbox(b, "NeonRing", -3.45, -3.2, 5.6, 5.9, 1.3, 7.7, RING, NEON), id, 3)
	look(lbox(b, "NeonRing", 3.2, 3.45, 5.6, 5.9, 1.3, 7.7, RING, NEON), id, 3)
	-- Niveau 5 : etincelles dans le bol dore
	local sparkleHolder = look(lbox(b, "MaxSparkle", -0.3, 0.3, 12.5, 13.1, 4.2, 4.8, GOLD, with(SMOOTH, { Transparency = 1, CastShadow = false })), id, 5)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkle.Size = NumberSequence.new(0.7, 0)
	sparkle.Lifetime = NumberRange.new(0.8, 1.3)
	sparkle.Rate = 8
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Parent = sparkleHolder
	b.PrimaryPart = cabinet

	-- Goulotte : du tapis (z 101.5) au bord arriere du bol (decor, ne bouge pas)
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	local top = Vector3.new(ox, BELT_Y - 0.3, BELT_Z - 1.4)
	local low = Vector3.new(ox, oy + 14.9, oz + 7.4)
	local cf = CFrame.lookAt((top + low) / 2, low)
	local len = (top - low).Magnitude
	part(chute, "Slide", Vector3.new(1.8, 0.2, len), cf, METAL, SMOOTH)
	for _, side in { -1, 1 } do
		part(chute, "SlideRail", Vector3.new(0.2, 0.6, len), cf * CFrame.new(side * 1, 0.3, 0), RAIL)
	end
	chute.Parent = m

	-- Marqueurs invisibles
	box(m, "FeedPoint", ox - 0.5, ox + 0.5, BELT_Y + 0.2, BELT_Y + 1.2, BELT_Z - 0.5, BELT_Z + 0.5, Color3.new(1, 0, 0), MARKER)
	-- "3/5" au-dessus du panneau suspendu du mixeur (Boards.BlenderSignN, 02g : y 15.3 -> 21.8)
	lbox(m, "BowlLabelAnchor", -0.5, 0.5, 22.4, 23.4, 4, 5, Color3.new(1, 0, 0), MARKER)
	-- Operateur : devant le bouton vert, dans l'allee, tourne vers le panneau
	local opX, opZ = ox + 3.2, oz - 3.6
	part(m, "Blender" .. index .. "Operator", Vector3.new(2, 1, 2), CFrame.lookAt(Vector3.new(opX, oy + 0.5, opZ), Vector3.new(opX, oy + 0.5, oz)), Color3.new(0, 0.6, 1), MARKER)

	-- Pad vert de l'operateur (5 x 5 : il tient dans l'allee). Marcher dessus = embaucher
	local opModel = Instance.new("Model")
	opModel.Name = "Operator"
	opModel:SetAttribute("UpgradeId", "Operator" .. index)
	local pad = Instance.new("Model")
	pad.Name = "Pad"
	box(pad, "PadBase", opX - 2.5, opX + 2.5, oy, oy + 0.6, opZ - 2.5, opZ + 2.5, PAD_BASE, { CastShadow = false })
	local padTop = box(pad, "PadTop", opX - 2, opX + 2, oy + 0.6, oy + 0.95, opZ - 2, opZ + 2, PAD_TOP, { CastShadow = false })
	local GLOW = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
	box(pad, "PadGlow", opX - 2.25, opX + 2.25, oy + 0.6, oy + 0.72, opZ - 2.25, opZ - 2.05, PAD_GLOW, GLOW)
	box(pad, "PadGlow", opX - 2.25, opX + 2.25, oy + 0.6, oy + 0.72, opZ + 2.05, opZ + 2.25, PAD_GLOW, GLOW)
	box(pad, "PadGlow", opX - 2.25, opX - 2.05, oy + 0.6, oy + 0.72, opZ - 2.05, opZ + 2.05, PAD_GLOW, GLOW)
	box(pad, "PadGlow", opX + 2.05, opX + 2.25, oy + 0.6, oy + 0.72, opZ - 2.05, opZ + 2.05, PAD_GLOW, GLOW)
	padTag(padTop, "Blender Operator", "$0")
	box(pad, "PadZone", opX - 2.5, opX + 2.5, oy, oy + 5, opZ - 2.5, opZ + 2.5, Color3.new(1, 0, 0), MARKER)
	pad.PrimaryPart = padTop
	pad.Parent = opModel
	opModel.Parent = m

	m.PrimaryPart = cabinet
	return m
end

for index, x in BLENDER_X do
	local blender = buildBlender(index, Vector3.new(x, 0.5, BLENDER_FRONT_Z))
	blender.Parent = blendersFolder
	task.wait()
end
blendersFolder.Parent = production

-- ===== TABLE A JUS SURELEVEE (2026-11-19 soir ; avant : palette au sol, "c'est par terre") =====
-- Trois tailles selon Juice Table (JuiceLimit) : niveaux 1-3 (x 16.5 -> 27.5), 4-6 (14 -> 30, bandeau
-- rose + rebord), 7-9 (11.5 -> 32.5, bandeau et rebord dores + lampes). Une seule est visible
-- (LevelLookController) ; chacune garde sa collision. Dessus a TABLE_TOP ; les gobelets se posent
-- sur le bas de JuicePile (ProductionService : grille 6 / 9 / 12 colonnes x 4 rangs, centree).
local JUICE = "JuiceLimit"
local TABLE_TOP = 3.4
local TZ0, TZ1 = 75, 82
local TCX = 22
local pallet = Instance.new("Model")
pallet.Name = "JuicePallet"
pallet:SetAttribute("Raised", true)
local tiers = {
	{ half = 5.5, min = 0, max = 3, trim = WOOD },
	{ half = 8, min = 4, max = 6, trim = Color3.fromRGB(255, 120, 180) },
	{ half = 10.5, min = 7, max = nil, trim = GOLD },
}
for t, tier in tiers do
	local x0, x1 = TCX - tier.half, TCX + tier.half
	local function tl(p: BasePart, keepCollide: boolean?): BasePart
		return look(p, JUICE, tier.min, tier.max, keepCollide)
	end
	tl(box(pallet, "TableTop", x0, x1, TABLE_TOP - 0.4, TABLE_TOP, TZ0, TZ1, WOOD_LIGHT), true)
	tl(box(pallet, "Apron", x0 + 0.3, x1 - 0.3, TABLE_TOP - 1, TABLE_TOP - 0.4, TZ0 + 0.2, TZ0 + 0.5, tier.trim))
	tl(box(pallet, "Apron", x0 + 0.3, x1 - 0.3, TABLE_TOP - 1, TABLE_TOP - 0.4, TZ1 - 0.5, TZ1 - 0.2, tier.trim))
	for _, x in { x0 + 0.6, x1 - 0.6 } do
		for _, z in { TZ0 + 0.6, TZ1 - 0.6 } do
			tl(box(pallet, "Leg", x - 0.35, x + 0.35, 0.5, TABLE_TOP - 0.4, z - 0.35, z + 0.35, WOOD_DARK), true)
		end
	end
	if t >= 2 then
		-- Rebord colore autour du dessus (les gobelets restent au centre)
		tl(box(pallet, "Lip", x0, x1, TABLE_TOP, TABLE_TOP + 0.3, TZ0, TZ0 + 0.3, tier.trim))
		tl(box(pallet, "Lip", x0, x1, TABLE_TOP, TABLE_TOP + 0.3, TZ1 - 0.3, TZ1, tier.trim))
		tl(box(pallet, "Lip", x0, x0 + 0.3, TABLE_TOP, TABLE_TOP + 0.3, TZ0 + 0.3, TZ1 - 0.3, tier.trim))
		tl(box(pallet, "Lip", x1 - 0.3, x1, TABLE_TOP, TABLE_TOP + 0.3, TZ0 + 0.3, TZ1 - 0.3, tier.trim))
	end
	if t >= 3 then
		-- Lampes aux deux bouts, au fond de la table
		for _, x in { x0 + 0.5, x1 - 0.5 } do
			tl(box(pallet, "LampPost", x - 0.2, x + 0.2, TABLE_TOP, TABLE_TOP + 3.4, TZ1 - 0.7, TZ1 - 0.3, METAL_DARK))
			tl(box(pallet, "LampBulb", x - 0.45, x + 0.45, TABLE_TOP + 3.4, TABLE_TOP + 4.2, TZ1 - 0.95, TZ1 - 0.05, Color3.fromRGB(255, 236, 160), NEON))
		end
	end
end
pallet.Parent = production
-- Zone des gobelets : bas = dessus de la table, 14 x 6.4 (12 colonnes x 1.1 au plus grand)
box(production, "JuicePile", TCX - 7, TCX + 7, TABLE_TOP, TABLE_TOP + 5, TZ0 + 0.3, TZ1 - 0.3, Color3.new(1, 0, 0), MARKER)
box(production, "JuiceLabelAnchor", 21.5, 22.5, 8.6, 9.6, 78, 79, Color3.new(1, 0, 0), MARKER)

production.Parent = model
return "Production OK: " .. #production:GetDescendants() .. " objets, " .. #blendersFolder:GetChildren() .. " mixeurs"
