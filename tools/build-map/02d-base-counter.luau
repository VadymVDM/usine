--!strict
-- FloorTemplate (un etage, phase 1b), morceau 4/7 : comptoir de vente dans la fenetre de la facade (les clients sont
-- dehors, le joueur dedans), auvent raye, table a argent (liasses de billets), pad Robux "Auto
-- Collect". A lancer apres 02a. Recree le dossier Counter.
-- Zones pour le code (invisibles) : CounterTopArea, CounterLabelAnchor, MoneyPile (billets),
-- MoneyLabelAnchor, JuiceDropPad.PadZone, CashPad.PadZone, AutoCollectPad.PadZone.
-- Doc : docs/systems/carte-bases.md, docs/systems/clients.md

local WOOD_TOP = Color3.fromRGB(226, 190, 140)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local STRIPES = { Color3.fromRGB(255, 132, 40), Color3.fromRGB(255, 246, 228) }
local COUNTER_FRONT = { Color3.fromRGB(255, 186, 60), Color3.fromRGB(255, 132, 40) }
local ROBUX_PURPLE = Color3.fromRGB(150, 70, 255)
local FELT = Color3.fromRGB(150, 30, 45) -- velours rouge : les billets verts ressortent
local GOLD = Color3.fromRGB(255, 206, 60)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)

-- Tout le bloc est decale de OFFSET (usine agrandie le 2026-11-19) : comptoir x 48 -> 80,
-- table a argent x 82 -> 92, pad Auto Collect x 95 -> 101.
local OFFSET = Vector3.new(16, 0, 0)

local STUDS = Enum.SurfaceType.Studs
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
local MARKER = table.clone(SMOOTH)
MARKER.Transparency = 1
MARKER.CanCollide = false
MARKER.CanQuery = false
MARKER.CanTouch = false
MARKER.CastShadow = false
local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
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

local function label(parent: Instance, text: string, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "Text"
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
local old = model:FindFirstChild("Counter")
if old then
	old:Destroy()
end
local counter = Instance.new("Folder")
counter.Name = "Counter"
-- Tour d'etages : un tas d'argent PAR ETAGE (2026-11-20, demande : "a chaque etage, un truc pour
-- recuperer l'argent, comme au premier") : table a argent et pad Collect Cash sur tous les etages.
-- Pad Robux Auto Collect aussi sur tous les etages depuis le 2026-11-21 (avant : OnlyGround, etage 1
-- seulement ; demande : "les pads payants du premier etage, la aux prochains etages aussi").

-- ===== COMPTOIR dans la fenetre de la facade (x 32..64, mur a z 14..15) =====
local stall = Instance.new("Model")
stall.Name = "SalesCounter"
box(stall, "CounterBody", 32, 64, 0.3, 4.2, 14.2, 18, WOOD_DARK)
for i = 0, 15 do -- planches colorees cote clients
	local x0 = 32.1 + i * 2
	box(stall, "FrontPlank", x0, x0 + 1.8, 0.7, 3.9, 14.05, 14.2, COUNTER_FRONT[(i % 2) + 1])
end
box(stall, "Kick", 31.8, 64.2, 0.3, 0.7, 13.9, 18.2, WOOD_DARK)
local top = box(stall, "CounterTop", 31.6, 64.4, 4.2, 4.8, 13.4, 18.6, WOOD_TOP)
-- Auvent raye au-dessus de la fenetre, cote rue (incline vers la rue)
local angle = math.atan(1.4 / 5)
for i = 0, 15 do
	local x0 = 32 + i * 2
	local color = STRIPES[(i % 2) + 1]
	-- (bandes du bord : 0.1 plus etroites cote mur, sinon face confondue avec le mur au-dessus de la fenetre)
	local w = if i == 0 or i == 15 then 1.9 else 2
	local cx = if i == 0 then x0 + 1.05 elseif i == 15 then x0 + 0.95 else x0 + 1
	part(stall, "Awning" .. i, Vector3.new(w, 0.3, 5.4), CFrame.new(cx, 11.6, 11.4) * CFrame.Angles(-angle, 0, 0), color, SMOOTH)
	box(stall, "AwningFlap" .. i, x0, x0 + 2, 10.2, 10.9, 8.75, 8.95, color, SMOOTH)
end
-- (plus de petits fruits decoratifs sur le comptoir : on les prenait pour de vrais fruits)
stall.PrimaryPart = top
stall.Parent = counter

-- Zones pour le code
box(counter, "CounterTopArea", 33, 55, 4.8, 5.8, 14.3, 17.7, Color3.new(1, 0, 0), MARKER) -- ou poser les gobelets
box(counter, "CounterLabelAnchor", 43.5, 44.5, 8.5, 9.5, 18.5, 19.5, Color3.new(1, 0, 0), MARKER)

-- ===== PADS D'ACTION (2026-11-19) : on se tient dessus, pas de touche E =====
-- Meme forme que les pads d'employes (dalle epaisse + dessus a studs + baguettes neon), 7 x 7,
-- couleur propre a chaque action. PadZone = zone testee par CustomerService.
local GLOW = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
local function actionPad(name: string, title: string, cx: number, cz: number, baseColor: Color3, topColor: Color3, glowColor: Color3, parent: Instance)
	local h, floorY = 3.5, 0.5
	local m = Instance.new("Model")
	m.Name = name
	box(m, "PadBase", cx - h, cx + h, floorY, floorY + 0.5, cz - h, cz + h, baseColor, { CastShadow = false })
	local padTop = box(m, "PadTop", cx - h + 0.55, cx + h - 0.55, floorY + 0.5, floorY + 0.8, cz - h + 0.55, cz + h - 0.55, topColor, {
		CastShadow = false,
	})
	local g0, g1, gy0, gy1 = h - 0.3, h - 0.08, floorY + 0.5, floorY + 0.62
	box(m, "PadGlow", cx - g1, cx + g1, gy0, gy1, cz - g1, cz - g0, glowColor, GLOW)
	box(m, "PadGlow", cx - g1, cx + g1, gy0, gy1, cz + g0, cz + g1, glowColor, GLOW)
	box(m, "PadGlow", cx - g1, cx - g0, gy0, gy1, cz - g0, cz + g0, glowColor, GLOW)
	box(m, "PadGlow", cx + g0, cx + g1, gy0, gy1, cz - g0, cz + g0, glowColor, GLOW)
	local padTag = Instance.new("BillboardGui")
	padTag.Name = "Tag"
	padTag.Size = UDim2.fromScale(10, 2.2)
	padTag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	padTag.MaxDistance = 70
	padTag.LightInfluence = 0
	padTag.Adornee = padTop
	local t = label(padTag, title, 3)
	t.Name = "Title"
	t.Position = UDim2.fromScale(0, 0)
	t.Size = UDim2.fromScale(1, 1)
	padTag.Parent = padTop
	box(m, "PadZone", cx - h, cx + h, floorY - 0.2, floorY + 5, cz - h, cz + h, Color3.new(1, 0, 0), MARKER)
	m.PrimaryPart = padTop
	m.Parent = parent
end
-- Derriere le milieu du comptoir (final x 56.5-63.5, z 19.5-26.5) : les jus des mains -> comptoir
actionPad("JuiceDropPad", "Drop Juices", 44, 23, Color3.fromRGB(20, 110, 200), Color3.fromRGB(90, 200, 255), Color3.fromRGB(0, 170, 255), counter)
-- Devant la table a argent (final x 83.5-90.5, z 24.5-31.5) : le tas d'argent -> joueur
actionPad("CashPad", "Collect Cash", 71, 28, Color3.fromRGB(196, 140, 16), Color3.fromRGB(255, 214, 64), Color3.fromRGB(255, 190, 0), counter)

-- ===== TABLE A ARGENT (dedans, a cote du comptoir) : les liasses s'empilent sur le tapis vert =====
local tray = Instance.new("Model")
tray.Name = "MoneyTray"
for _, leg in { { 66.6, 17.1 }, { 75.4, 17.1 }, { 66.6, 22.9 }, { 75.4, 22.9 } } do
	box(tray, "Leg", leg[1] - 0.4, leg[1] + 0.4, 0.5, 3.2, leg[2] - 0.4, leg[2] + 0.4, WOOD_DARK)
end
box(tray, "Apron", 66.2, 75.8, 2.4, 3.2, 16.7, 23.3, WOOD_DARK)
box(tray, "Top", 66, 76, 3.2, 3.6, 16.5, 23.5, WOOD_TOP)
box(tray, "Felt", 66.6, 75.4, 3.6, 3.7, 17.1, 22.9, FELT, SMOOTH)
box(tray, "RimFront", 66, 76, 3.6, 4, 16.5, 17.1, GOLD)
box(tray, "RimBack", 66, 76, 3.6, 4, 22.9, 23.5, GOLD)
box(tray, "RimLeft", 66, 66.6, 3.6, 4, 17.1, 22.9, GOLD)
box(tray, "RimRight", 75.4, 76, 3.6, 4, 17.1, 22.9, GOLD)
-- Panneau "CASH" sur le mur de la facade, au-dessus de la table
local cashSign = box(tray, "SignBoard", 67.5, 74.5, 8.5, 11, 15.05, 15.45, GOLD)
local cashGui = surfaceGui(cashSign, Enum.NormalId.Back)
label(cashGui, "$ CASH $", 4)
tray.Parent = counter
-- Billets poses sur le tapis (CustomerService) ; le pad "Collect Cash" devant la table = encaisser
box(counter, "MoneyPile", 66.6, 75.4, 3.7, 6.5, 17.1, 22.9, Color3.new(1, 0, 0), MARKER)
box(counter, "MoneyLabelAnchor", 70.5, 71.5, 8, 9, 19.5, 20.5, Color3.new(1, 0, 0), MARKER)

-- ===== PAD ROBUX "AUTO COLLECT" : l'argent des ventes va directement au joueur =====
-- Meme forme que les pads d'employes (dalle epaisse + dessus a studs + baguettes neon), en
-- couleurs "payant" : bord dore, dessus violet, neon rose (2026-11-19, captures de reference).
local pad = Instance.new("Model")
pad.Name = "AutoCollectPad"
box(pad, "PadBase", 79, 85, 0.5, 1.1, 17, 23, Color3.fromRGB(226, 160, 36), { CastShadow = false })
local padTop = box(pad, "PadTop", 79.55, 84.45, 1.1, 1.45, 17.55, 22.45, ROBUX_PURPLE, { CastShadow = false })
local PINK = Color3.fromRGB(255, 70, 215) -- sature : le neon pale devient blanc
box(pad, "PadGlow", 79.25, 84.75, 1.1, 1.22, 17.25, 17.45, PINK, GLOW)
box(pad, "PadGlow", 79.25, 84.75, 1.1, 1.22, 22.55, 22.75, PINK, GLOW)
box(pad, "PadGlow", 79.25, 79.45, 1.1, 1.22, 17.45, 22.55, PINK, GLOW)
box(pad, "PadGlow", 84.55, 84.75, 1.1, 1.22, 17.45, 22.55, PINK, GLOW)
local tag = Instance.new("BillboardGui")
tag.Name = "Tag"
tag.Size = UDim2.fromScale(9, 3.6)
tag.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
tag.MaxDistance = 60
tag.LightInfluence = 0
tag.Adornee = padTop
local title = label(tag, "Auto Collect", 3)
title.Name = "Title"
title.Position = UDim2.fromScale(0, 0)
title.Size = UDim2.fromScale(1, 0.55)
local price = label(tag, "R$ 149", 3)
price.Name = "Price"
price.Position = UDim2.fromScale(0.15, 0.55)
price.Size = UDim2.fromScale(0.7, 0.45)
price.TextColor3 = Color3.fromRGB(120, 255, 90)
tag.Parent = padTop
box(pad, "PadZone", 79, 85, 0.5, 5.5, 17, 23, Color3.new(1, 0, 0), MARKER)
pad.PrimaryPart = padTop
-- Style des pads Robux (2026-11-20) : forme des pads verts, en violet (Util/RobuxPad)
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local util = ReplicatedStorage.Shared.Util.RobuxPad:Clone()
	util.Parent = ReplicatedStorage.Shared.Util
	local RobuxPad = require(util) :: any
	util:Destroy()
	RobuxPad.Style(pad, "Auto Collect", 149)
	-- ===== PAD ROBUX "INSTANT SELL" (2026-11-21) : juste a droite du pad Drop Juices, sur CHAQUE
	-- etage (final x 64.5-70.5, z 20-26). Les jus poses sont vendus tout de suite (PassPadService,
	-- CustomerService). Copie du pad Auto Collect deplacee de (-30.5, 0, +3).
	local instant = pad:Clone()
	instant.Name = "InstantSellPad"
	instant:PivotTo(instant:GetPivot() + Vector3.new(-30.5, 0, 3))
	RobuxPad.Style(instant, "Instant Sell", 199)
	instant.Parent = counter
end
pad.Parent = counter

-- ===== PANNEAU "MONEY / HOUR" au-dessus du comptoir (2026-11-19 soir) =====
-- Sur le mur au-dessus de la fenetre, cote interieur (final x 54 -> 74, y 11.8 -> 16.6). Le texte
-- Board.Display.Value ("$12.5K") est remis a jour par CustomerService : ventes des 2 dernieres
-- minutes ramenees a une heure.
local income = Instance.new("Model")
income.Name = "IncomeSign"
box(income, "Frame", 37.6, 58.4, 11.5, 16.9, 15.05, 15.45, WOOD_DARK)
local incomeBoard = box(income, "Board", 38, 58, 11.8, 16.6, 15.1, 15.6, Color3.fromRGB(255, 248, 230))
local incomeGui = surfaceGui(incomeBoard, Enum.NormalId.Back)
incomeGui.Name = "Display"
local incomeTitle = label(incomeGui, "MONEY / HOUR", 3)
incomeTitle.Name = "Title"
incomeTitle.Position = UDim2.fromScale(0.05, 0.05)
incomeTitle.Size = UDim2.fromScale(0.9, 0.3)
incomeTitle.TextColor3 = Color3.fromRGB(255, 196, 48)
local incomeValue = label(incomeGui, "$0", 4)
incomeValue.Name = "Value"
incomeValue.Position = UDim2.fromScale(0.05, 0.36)
incomeValue.Size = UDim2.fromScale(0.9, 0.6)
incomeValue.TextColor3 = Color3.fromRGB(110, 235, 80)
income.PrimaryPart = incomeBoard
income.Parent = counter

-- ===== DECOR "FASTER CUSTOMERS" (CustomerSpeed) : le comptoir s'equipe a chaque palier =====
-- 3 = sonnette, 5 = caisse enregistreuse, 12 = guirlande
-- lumineuse, 15 = bord dore du comptoir. Pieces visibles selon LookId / LookLevel (LevelLookController).
local SPEED = "CustomerSpeed"
local NEON = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false })
local function look(p: BasePart, level: number): BasePart
	p:SetAttribute("LookId", SPEED)
	p:SetAttribute("LookLevel", level)
	p.CanCollide = false
	p.CanTouch = false
	return p
end
local speedDecor = Instance.new("Model")
speedDecor.Name = "SpeedDecor"
-- Sonnette (a cote de la zone des gobelets, x 33 -> 55)
look(box(speedDecor, "BellBase", 55.8, 56.8, 4.8, 5, 16, 17, GOLD), 3)
look(box(speedDecor, "Bell", 55.95, 56.65, 5, 5.45, 16.15, 16.85, GOLD, SMOOTH), 3)
look(box(speedDecor, "BellKnob", 56.2, 56.4, 5.45, 5.65, 16.4, 16.6, Color3.fromRGB(70, 74, 86)), 3)
-- Caisse enregistreuse (l'ancienne "Fast Register", maintenant un decor)
look(box(speedDecor, "RegisterBody", 58, 63, 4.8, 6.2, 15, 17.6, Color3.fromRGB(70, 74, 86)), 5)
look(box(speedDecor, "RegisterDrawer", 58.2, 62.8, 5, 5.8, 14.85, 15, Color3.fromRGB(255, 206, 60)), 5)
look(box(speedDecor, "RegisterKeypad", 58.4, 62.6, 6.2, 6.45, 15.2, 16.4, Color3.fromRGB(200, 204, 214)), 5)
look(box(speedDecor, "RegisterScreenBack", 59, 62, 6.2, 8.4, 16.8, 17.3, Color3.fromRGB(70, 74, 86)), 5)
look(box(speedDecor, "RegisterScreen", 59.2, 61.8, 6.6, 8.2, 17.3, 17.35, Color3.fromRGB(120, 255, 140), NEON), 5)
-- (enseigne neon OPEN retiree le 2026-11-20 : "pas besoin")
-- Guirlande lumineuse le long du haut de la fenetre (cote interieur)
look(box(speedDecor, "LightWire", 32.4, 63.6, 10.75, 10.85, 15.2, 15.3, Color3.fromRGB(40, 40, 48)), 12)
local BULBS = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 170, 255) }
for i = 0, 12 do
	local x = 33 + i * 2.5
	look(box(speedDecor, "LightBulb", x - 0.2, x + 0.2, 10.25, 10.75, 15.05, 15.45, BULBS[(i % #BULBS) + 1], NEON), 12)
end
-- Bord dore du comptoir (cote interieur)
look(box(speedDecor, "GoldEdge", 31.6, 64.4, 4.25, 4.75, 18.6, 18.8, GOLD, SMOOTH), 15)
speedDecor.Parent = counter

counter.Parent = model
return "Counter OK: " .. #counter:GetDescendants()
