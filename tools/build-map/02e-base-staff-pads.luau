--!strict
-- BaseTemplate, morceau 5/6 : cabane du personnel + 9 pads d'amelioration avec leur carte flottante.
-- A lancer apres 02a. Titres, couleurs, icones et prix viennent de Config (Upgrades, Icons).
-- Carte = BillboardGui au style de notre interface (PackStyle) : degrade, liseret blanc, contour
-- fonce, bouton vert (prix) et violet (Robux, A VALIDER). Valeurs = niveau de depart (apercu) ;
-- le lot E les met a jour selon le joueur. Chaque pad : Model "Pad_<Id>" avec l'attribut UpgradeId.
-- Doc : docs/systems/carte-bases.md, docs/systems/ameliorations-employes.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- execute_luau garde les modules deja charges : on charge une copie pour avoir la Config a jour
local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Upgrades = freshRequire(ReplicatedStorage.Shared.Config.Upgrades)
local Icons = freshRequire(ReplicatedStorage.Shared.Config.Icons)

-- Position (x, z) de chaque pad dans le repere local de la base
local PAD_POSITIONS: { [string]: Vector2 } = {
	TreeSpeed = Vector2.new(33.5, 56),
	TreeLuck = Vector2.new(27, 56),
	JuiceLimit = Vector2.new(11, 47),
	CounterLimit = Vector2.new(50, 23),
	CustomerSpeed = Vector2.new(57, 23),
	CustomerCount = Vector2.new(64, 23),
	Collector = Vector2.new(5, 60),
	Presser = Vector2.new(11.5, 60),
	Server = Vector2.new(18, 60),
}

local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_LIGHT = Color3.fromRGB(196, 156, 108)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local STONE = Color3.fromRGB(170, 165, 155)
local PAD_STONE = Color3.fromRGB(214, 208, 194)
local ROOF = Color3.fromRGB(170, 74, 58)
local ROOF_CAP = Color3.fromRGB(140, 60, 48)
local WINDOW = Color3.fromRGB(170, 210, 228)
local FRAME = Color3.fromRGB(236, 232, 222)
local METAL = Color3.fromRGB(96, 100, 110)

local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)
local GREEN = { Color3.fromRGB(64, 252, 9), Color3.fromRGB(237, 255, 76), Color3.fromRGB(23, 74, 0) }
local PURPLE = { Color3.fromRGB(140, 0, 255), Color3.fromRGB(215, 120, 255), Color3.fromRGB(50, 0, 90) }

local STUDS = Enum.SurfaceType.Studs
local SMOOTH_SURF = Enum.SurfaceType.Smooth

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
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

-- Cylindre vertical (diametre, hauteur)
local function cyl(parent: Instance, name: string, center: Vector3, diameter: number, height: number, color: Color3): BasePart
	local p = part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, SMOOTH);
	(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- ===== Interface (copie des briques de src/client/UI/PackStyle.luau, tailles en pixels fixes) =====
local function stroke(parent: Instance, thickness: number, color: Color3, mode: Enum.ApplyStrokeMode?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = value
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.ZIndex = 4
	stroke(t, strokePx, TEXT_STROKE)
	t.Parent = parent
	return t
end

-- Fond en degrade (bas -> haut) + liseret blanc + contour fonce, bords carres
local function gradientBox(parent: Instance, name: string, bottom: Color3, top: Color3, border: Color3, pos: UDim2, size: UDim2, borderPx: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.ZIndex = 2
	stroke(f, borderPx, border, Enum.ApplyStrokeMode.Border)
	local g = Instance.new("UIGradient")
	g.Rotation = -90
	g.Color = ColorSequence.new(bottom, top)
	g.Parent = f
	local inner = Instance.new("Frame")
	inner.Name = "Shine"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -5, 1, -5)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 2
	stroke(inner, 1.5, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border).Transparency = 0.35
	inner.Parent = f
	f.Parent = parent
	return f
end

local function valueText(upgrade: any, level: number): string
	if upgrade.kind == "Employee" then
		return "Hire!"
	end
	local a, b = Upgrades.GetValue(upgrade.id, level), Upgrades.GetValue(upgrade.id, level + 1)
	if upgrade.id == "TreeSpeed" or upgrade.id == "CustomerSpeed" then
		return string.format("%.1fs → %.1fs", a, b)
	end
	return string.format("%d → %d", math.floor(a + 0.5), math.floor(b + 0.5))
end

local function makeCard(adornee: BasePart, upgrade: any)
	local level = math.max(upgrade.startLevel, 1)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Card"
	bb.Size = UDim2.fromScale(5.4, 3.3)
	-- L'offset suit l'orientation de l'adornee : on l'attache a la plaque d'icone (non tournee)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4.1, 0)
	bb.MaxDistance = 32 -- visible seulement en approchant du pad (moins de boutons a l ecran)
	bb.LightInfluence = 0
	bb.Adornee = adornee
	local color: Color3 = upgrade.color
	local panel = gradientBox(bb, "Panel", color:Lerp(Color3.new(0, 0, 0), 0.18), color:Lerp(Color3.new(1, 1, 1), 0.3), TEXT_STROKE, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 3)
	text(panel, "Title", upgrade.title, UDim2.fromScale(0.5, 0.04), UDim2.fromScale(0.92, 0.25), 2.5)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Icons[upgrade.icon] or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Position = UDim2.fromScale(0.04, 0.3)
	icon.Size = UDim2.fromScale(0.3, 0.34)
	icon.ZIndex = 4
	icon.Parent = panel
	text(panel, "Value", valueText(upgrade, level), UDim2.fromScale(0.66, 0.32), UDim2.fromScale(0.62, 0.3), 2.5)
	local price = gradientBox(panel, "PriceButton", GREEN[1], GREEN[2], GREEN[3], UDim2.fromScale(0.05, 0.68), UDim2.fromScale(0.52, 0.26), 2.5)
	text(price, "Price", "$" .. Upgrades.GetPrice(upgrade.id, level), UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.9, 0.88), 2.5)
	local robux = gradientBox(panel, "RobuxButton", PURPLE[1], PURPLE[2], PURPLE[3], UDim2.fromScale(0.61, 0.68), UDim2.fromScale(0.34, 0.26), 2.5)
	local robuxIcon = Instance.new("ImageLabel")
	robuxIcon.Name = "RobuxIcon"
	robuxIcon.BackgroundTransparency = 1
	robuxIcon.Image = Icons.Robux
	robuxIcon.ScaleType = Enum.ScaleType.Fit
	robuxIcon.Position = UDim2.fromScale(0.06, 0.15)
	robuxIcon.Size = UDim2.fromScale(0.36, 0.7)
	robuxIcon.ZIndex = 4
	robuxIcon.Parent = robux
	text(robux, "Robux", tostring(Upgrades.GetRobuxPrice(upgrade.id, level)), UDim2.fromScale(0.7, 0.06), UDim2.fromScale(0.56, 0.88), 2.5)
	bb.Parent = adornee
end

local model = game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
assert(model, "Lancer 02a d'abord")
for _, name in { "Staff", "Upgrades" } do
	local old = model:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- CABANE DU PERSONNEL (x 4..20, z 66..76)
local staff = Instance.new("Folder")
staff.Name = "Staff"
local shed = Instance.new("Model")
shed.Name = "Shed"
box(shed, "Foundation", 3.5, 20.5, 0.3, 0.8, 65.5, 76.5, STONE)
box(shed, "WallBack", 4, 20, 0.8, 7, 75.4, 76, WOOD)
box(shed, "WallLeft", 4, 4.6, 0.8, 7, 66.6, 75.4, WOOD)
box(shed, "WallRight", 19.4, 20, 0.8, 7, 66.6, 75.4, WOOD)
box(shed, "WallFrontLeft", 4, 10.5, 0.8, 7, 66, 66.6, WOOD)
box(shed, "WallFrontRight", 13.5, 20, 0.8, 7, 66, 66.6, WOOD)
box(shed, "WallAboveDoor", 10.5, 13.5, 5.5, 7, 66, 66.6, WOOD)
for _, c in { { 4, 66 }, { 20, 66 }, { 4, 76 }, { 20, 76 } } do
	box(shed, "Corner", c[1] - 0.45, c[1] + 0.45, 0.8, 7.2, c[2] - 0.45, c[2] + 0.45, WOOD_DARK)
end
-- Porte (en retrait) + encadrement + poignee
box(shed, "Door", 10.5, 13.5, 0.8, 5.5, 66.2, 66.4, WOOD_DARK)
box(shed, "DoorFrameLeft", 10.2, 10.6, 0.8, 5.9, 65.9, 66.6, WOOD_LIGHT)
box(shed, "DoorFrameRight", 13.4, 13.8, 0.8, 5.9, 65.9, 66.6, WOOD_LIGHT)
box(shed, "DoorFrameTop", 10.2, 13.8, 5.4, 5.9, 65.9, 66.6, WOOD_LIGHT)
box(shed, "DoorKnob", 12.8, 13.1, 2.9, 3.2, 66, 66.2, METAL, SMOOTH)
-- Fenetres (vitre en retrait derriere un cadre)
for _, wx in { 6, 15 } do
	box(shed, "WindowGlass", wx + 0.1, wx + 2.9, 3.1, 5.3, 65.95, 66, WINDOW, SMOOTH)
	box(shed, "WindowTop", wx - 0.2, wx + 3.2, 5.3, 5.6, 65.85, 66, FRAME)
	box(shed, "WindowBottom", wx - 0.2, wx + 3.2, 2.8, 3.1, 65.85, 66, FRAME)
	box(shed, "WindowLeft", wx - 0.2, wx + 0.1, 3.1, 5.3, 65.85, 66, FRAME)
	box(shed, "WindowRight", wx + 2.9, wx + 3.2, 3.1, 5.3, 65.85, 66, FRAME)
	box(shed, "WindowCross", wx + 1.4, wx + 1.6, 3.1, 5.3, 65.88, 66, FRAME)
end
-- Toit a deux pans (WedgePart : le pan descend vers -Z), faitage
part(shed, "RoofFront", Vector3.new(17.6, 3, 6), CFrame.new(12, 8.5, 68), ROOF, nil, "WedgePart")
part(shed, "RoofBack", Vector3.new(17.6, 3, 6), CFrame.new(12, 8.5, 74) * CFrame.Angles(0, math.pi, 0), ROOF, nil, "WedgePart")
box(shed, "RoofRidge", 3, 21, 9.8, 10.3, 70.6, 71.4, ROOF_CAP)
-- Enseigne "STAFF"
box(shed, "SignFrame", 8.3, 15.7, 7, 9.4, 65.4, 65.75, WOOD_DARK)
local signBoard = box(shed, "SignBoard", 8.5, 15.5, 7.2, 9.2, 65.3, 65.85, WOOD_LIGHT, { FrontSurface = SMOOTH_SURF })
local signGui = Instance.new("SurfaceGui")
signGui.Name = "Display"
signGui.Face = Enum.NormalId.Front
signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
signGui.PixelsPerStud = 50
signGui.LightInfluence = 0
signGui.Parent = signBoard
local staffText = text(signGui, "Text", "STAFF", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.88, 0.84), 6)
local staffGradient = Instance.new("UIGradient")
staffGradient.Rotation = 90
staffGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 230, 255))
staffGradient.Parent = staffText
shed.Parent = staff
staff.Parent = model
task.wait()

-- PADS D'AMELIORATION
local upgradesFolder = Instance.new("Folder")
upgradesFolder.Name = "Upgrades"
for _, upgrade in Upgrades.List do
	local pos = PAD_POSITIONS[upgrade.id]
	assert(pos, "Pas de position pour " .. upgrade.id)
	local pad = Instance.new("Model")
	pad.Name = "Pad_" .. upgrade.id
	pad:SetAttribute("UpgradeId", upgrade.id)
	local color: Color3 = upgrade.color
	cyl(pad, "Ring", Vector3.new(pos.X, 0.55, pos.Y), 5.4, 0.5, PAD_STONE)
	local button = cyl(pad, "Button", Vector3.new(pos.X, 0.95, pos.Y), 4.3, 0.4, color:Lerp(Color3.fromRGB(128, 128, 128), 0.25))
	cyl(pad, "ButtonTop", Vector3.new(pos.X, 1.18, pos.Y), 3.7, 0.06, color:Lerp(Color3.new(1, 1, 1), 0.2))
	local iconPlate = part(pad, "IconPlate", Vector3.new(2.6, 0.05, 2.6), CFrame.new(pos.X, 1.235, pos.Y), Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		TopSurface = SMOOTH_SURF,
	})
	local iconGui = Instance.new("SurfaceGui")
	iconGui.Name = "Icon"
	iconGui.Face = Enum.NormalId.Top
	iconGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	iconGui.PixelsPerStud = 60
	iconGui.LightInfluence = 0.3
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = Icons[upgrade.icon] or ""
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = iconGui
	iconGui.Parent = iconPlate
	pad.PrimaryPart = button
	makeCard(iconPlate, upgrade)
	pad.Parent = upgradesFolder
end
upgradesFolder.Parent = model

return "Staff + pads OK"
