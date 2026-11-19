--!strict
-- BaseTemplate, morceau 4/6 : etal de vente (plancher, comptoir, auvent raye, enseigne, caisse),
-- plateau a argent, arche d'entree avec le panneau du proprietaire. A lancer apres 02a.
-- Textes au style de notre interface (police ComicNeue grasse, blanc + contour fonce, PackStyle).
-- Le texte du panneau (OwnerText) est remis par BaseService depuis Config/Map.luau.
-- Zones pour le code (invisibles) : CounterPad, CounterTopArea, MoneyPile, + ancres des textes.
-- Doc : docs/systems/carte-bases.md

local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_LIGHT = Color3.fromRGB(196, 156, 108)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local WOOD_TOP = Color3.fromRGB(214, 180, 130)
local FABRIC = { Color3.fromRGB(190, 70, 62), Color3.fromRGB(238, 226, 204) }
local STONE = Color3.fromRGB(170, 165, 155)
local METAL_DARK = Color3.fromRGB(70, 74, 82)
local METAL = Color3.fromRGB(96, 100, 110)
local SCREEN = Color3.fromRGB(150, 220, 170)
local FELT = Color3.fromRGB(86, 150, 90)
local LEAF = Color3.fromRGB(80, 140, 62)

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
local MARKER = table.clone(SMOOTH)
MARKER.Transparency = 1
MARKER.CanCollide = false
MARKER.CanQuery = false
MARKER.CanTouch = false
MARKER.CastShadow = false
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }

-- Face lisse pour y poser un SurfaceGui (les studs ne genent pas, mais c'est plus propre)
local function smoothFace(p: BasePart, face: Enum.NormalId)
	local prop = face.Name .. "Surface"
	(p :: any)[prop] = SMOOTH_SURF
end

local function surfaceGui(target: BasePart, face: Enum.NormalId): SurfaceGui
	smoothFace(target, face)
	local g = Instance.new("SurfaceGui")
	g.Name = "Display" .. face.Name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 50
	g.LightInfluence = 0
	g.Parent = target
	return g
end

-- Texte au style de l'interface : blanc, contour fonce arrondi, taille auto
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

local function gradientText(t: TextLabel, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = t
end

local model = game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
assert(model, "Lancer 02a d'abord")
for _, name in { "Counter", "Entrance" } do
	local old = model:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- ETAL (comptoir x 34..56, face a la route)
local counter = Instance.new("Folder")
counter.Name = "Counter"
local stall = Instance.new("Model")
stall.Name = "Stall"
-- Plancher en planches (avec un petit espace entre elles)
for i = 0, 8 do
	local z0 = 3.5 + i * 1.4
	box(stall, "Deck", 32, 58, 0.3, 0.6, z0 + 0.05, z0 + 1.35, if i % 2 == 0 then WOOD else WOOD_LIGHT)
end
-- Comptoir : caisson, planches verticales devant, plinthe, plateau epais
box(stall, "CounterBody", 34, 56, 0.6, 3.6, 5, 8.5, WOOD_DARK)
for i = 0, 10 do
	local x0 = 34.1 + i * 2
	box(stall, "CounterPlank", x0, x0 + 1.8, 0.95, 3.4, 4.85, 5, if i % 2 == 0 then WOOD else WOOD_LIGHT)
end
box(stall, "Kick", 33.8, 56.2, 0.6, 0.95, 4.7, 8.7, WOOD_DARK)
box(stall, "CounterTop", 33.6, 56.4, 3.6, 4.2, 4.5, 9, WOOD_TOP)
-- Poteaux
box(stall, "PostFL", 33.9, 34.7, 0.6, 9.8, 4.4, 5.2, WOOD_DARK)
box(stall, "PostFR", 55.3, 56.1, 0.6, 9.8, 4.4, 5.2, WOOD_DARK)
box(stall, "PostBL", 33.9, 34.7, 0.6, 11.2, 13.1, 13.9, WOOD_DARK)
box(stall, "PostBR", 55.3, 56.1, 0.6, 11.2, 13.1, 13.9, WOOD_DARK)
task.wait()
-- Auvent raye incline (fond plus haut) + lambrequin festonne devant
local canopyAngle = math.atan(1.6 / 11)
for i = 0, 11 do
	local x0 = 33 + i * 2
	local color = FABRIC[(i % 2) + 1]
	part(stall, "Canopy" .. i, Vector3.new(2, 0.35, 11.4), CFrame.new(x0 + 1, 10.4, 8.7) * CFrame.Angles(-canopyAngle, 0, 0), color, SMOOTH)
	box(stall, "Valance" .. i, x0, x0 + 2, 8.6, 9.4, 2.9, 3.15, color, SMOOTH)
	box(stall, "ValancePoint" .. i, x0 + 0.5, x0 + 1.5, 8.2, 8.6, 2.9, 3.15, color, SMOOTH)
end
-- Enseigne "JUICE" sur l'arriere de l'auvent, avec des fruits aux coins
box(stall, "SignFrame", 38.2, 51.8, 11.3, 14.9, 13.8, 14.3, WOOD_DARK)
local signBoard = box(stall, "SignBoard", 38.5, 51.5, 11.6, 14.6, 13.7, 14.4, WOOD_LIGHT)
local juiceText = label(surfaceGui(signBoard, Enum.NormalId.Front), "Text", "JUICE", UDim2.fromScale(0.06, 0.08), UDim2.fromScale(0.88, 0.84), 7)
gradientText(juiceText, Color3.fromRGB(255, 236, 130), Color3.fromRGB(255, 150, 40))
part(stall, "SignOrange", Vector3.new(1.4, 1.4, 1.4), CFrame.new(38, 15.3, 14) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(236, 140, 40), DECOR)
part(stall, "SignOrangeLeaf", Vector3.new(0.9, 0.3, 0.5), CFrame.new(38.2, 16.15, 14) * CFrame.Angles(0, math.rad(20), 0), LEAF, DECOR)
part(stall, "SignLemon", Vector3.new(1.3, 1.2, 1.2), CFrame.new(52, 15.2, 14) * CFrame.Angles(0, math.rad(-15), 0), Color3.fromRGB(236, 212, 72), DECOR)
part(stall, "SignApple", Vector3.new(1, 1, 1), CFrame.new(50.6, 15.1, 14) * CFrame.Angles(0, math.rad(30), 0), Color3.fromRGB(200, 48, 42), DECOR)
-- Caisse enregistreuse au bout du comptoir
box(stall, "Register", 52.6, 55.4, 4.2, 5, 5.6, 8.2, METAL_DARK)
box(stall, "RegisterDrawer", 52.8, 55.2, 4.3, 4.8, 5.45, 5.6, METAL)
box(stall, "RegisterScreen", 53.3, 54.7, 5, 6.2, 7.4, 7.7, METAL_DARK)
box(stall, "RegisterGlow", 53.45, 54.55, 5.3, 6, 7.35, 7.4, SCREEN, { Material = Enum.Material.Neon, CanCollide = false })
stall.Parent = counter

-- Zones pour le code
box(counter, "CounterTopArea", 34.5, 51.5, 4.2, 5.2, 5, 8.5, Color3.new(1, 0, 0), MARKER) -- ou poser les gobelets
box(counter, "CounterPad", 34, 56, 0.3, 4.3, 9.2, 15, Color3.new(1, 0, 0), MARKER) -- marcher ici = poser les jus
box(counter, "CounterLabelAnchor", 44.5, 45.5, 16.5, 17.5, 13.5, 14.5, Color3.new(1, 0, 0), MARKER)

-- PLATEAU A ARGENT (x 59..66, z 5..12)
local tray = Instance.new("Model")
tray.Name = "MoneyTray"
box(tray, "Felt", 59.5, 65.5, 0.3, 0.55, 5.5, 11.5, FELT)
box(tray, "EdgeFront", 59, 66, 0.3, 0.9, 5, 5.5, WOOD_DARK)
box(tray, "EdgeBack", 59, 66, 0.3, 0.9, 11.5, 12, WOOD_DARK)
box(tray, "EdgeLeft", 59, 59.5, 0.3, 0.9, 5.5, 11.5, WOOD_DARK)
box(tray, "EdgeRight", 65.5, 66, 0.3, 0.9, 5.5, 11.5, WOOD_DARK)
tray.Parent = counter
box(counter, "MoneyPile", 59, 66, 0.3, 4.3, 5, 12, Color3.new(1, 0, 0), MARKER)
box(counter, "MoneyLabelAnchor", 62, 63, 6, 7, 8, 9, Color3.new(1, 0, 0), MARKER)
counter.Parent = model
task.wait()

-- ARCHE D'ENTREE (chemin x 18..26) avec le panneau du proprietaire
local entrance = Instance.new("Folder")
entrance.Name = "Entrance"
local arch = Instance.new("Model")
arch.Name = "Arch"
for _, cx in { 16.4, 27.6 } do
	box(arch, "StoneBase", cx - 0.9, cx + 0.9, 0.3, 1.5, 0.3, 2.1, STONE)
	box(arch, "Log", cx - 0.6, cx + 0.6, 1.5, 11.2, 0.6, 1.8, WOOD_DARK)
	box(arch, "LogCap", cx - 0.8, cx + 0.8, 11.2, 11.6, 0.4, 2, WOOD_LIGHT)
end
box(arch, "Beam", 15, 29, 10.4, 11.4, 0.7, 1.7, WOOD)
box(arch, "ChainLeft", 18.6, 18.8, 9, 10.4, 1.1, 1.3, METAL_DARK, SMOOTH)
box(arch, "ChainRight", 25.2, 25.4, 9, 10.4, 1.1, 1.3, METAL_DARK, SMOOTH)
box(arch, "SignFrame", 17.2, 26.8, 6.4, 9.2, 1, 1.4, WOOD_DARK)
local ownerBoard = box(arch, "SignBoard", 17.45, 26.55, 6.65, 8.95, 0.95, 1.45, WOOD_LIGHT)
for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
	label(surfaceGui(ownerBoard, face), "OwnerText", "Free Stand", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84), 5)
end
part(arch, "BeamOrange", Vector3.new(1.3, 1.3, 1.3), CFrame.new(22, 12.05, 1.2) * CFrame.Angles(0, math.rad(25), 0), Color3.fromRGB(236, 140, 40), DECOR)
part(arch, "BeamOrangeLeaf", Vector3.new(0.9, 0.3, 0.5), CFrame.new(22.2, 12.85, 1.2) * CFrame.Angles(0, math.rad(25), 0), LEAF, DECOR)
part(arch, "BeamApple", Vector3.new(1, 1, 1), CFrame.new(19.6, 11.9, 1.2) * CFrame.Angles(0, math.rad(-20), 0), Color3.fromRGB(200, 48, 42), DECOR)
part(arch, "BeamLemon", Vector3.new(1.1, 1, 1), CFrame.new(24.4, 11.9, 1.2) * CFrame.Angles(0, math.rad(10), 0), Color3.fromRGB(236, 212, 72), DECOR)
arch.PrimaryPart = ownerBoard
arch.Parent = entrance
entrance.Parent = model

return "Stall + entrance OK"
