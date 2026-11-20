--!strict
-- Coin des dons (rez-de-chaussee seulement) : BaseTemplate.Donations. A lancer apres 02a (qui
-- recree BaseTemplate) ; relancable seul (detruit et recree Donations).
-- Mur de gauche de la salle (vu de l'entree : mur x 0 -> 1), entre la porte de la terrasse
-- (z 28 -> 40) et le bar a jus (z 64) :
--   Board : grand panneau en bois "TOP DONORS" (z 43 -> 57), 8 lignes Rows.Row1..Row8
--           (Rank, Avatar, PlayerName, RobuxIcon, Amount) remplies par DonationService ;
--   Table + Jar : petite table en bois et urne en verre pleine de billets (z 58 -> 62.5) ;
--           Jar.PromptAnchor porte le prompt E "Donations / Leave a tip" (cree par DonationService) ;
--   Rug : tapis violet a bord dore (couleur des choses en Robux, docs/style.md).
-- Repere : celui de la base (origine bord avant, sol de la salle a y = 0.55, +X vers la gauche vu de la route).
-- Doc : docs/systems/dons.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Donations = freshRequire(ReplicatedStorage.Shared.Config.Donations)
local Icons = freshRequire(ReplicatedStorage.Shared.Config.Icons)

local FLOOR_Y = 0.55
local WOOD = Color3.fromRGB(196, 116, 56)
local WOOD_DARK = Color3.fromRGB(132, 74, 36)
local WOOD_CAP = Color3.fromRGB(186, 146, 102)
local SIGN_BG = Color3.fromRGB(196, 108, 52)
local PURPLE = Color3.fromRGB(140, 60, 220)
local PURPLE_DARK = Color3.fromRGB(96, 34, 160)
local GOLD = Color3.fromRGB(255, 196, 40)
local GLASS = Color3.fromRGB(200, 230, 240)
local CASH = Color3.fromRGB(70, 190, 84)
local CASH_DARK = Color3.fromRGB(40, 140, 60)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)
local RANK_COLORS = { Color3.fromRGB(255, 214, 64), Color3.fromRGB(220, 228, 240), Color3.fromRGB(236, 150, 84) }

local STUDS = Enum.SurfaceType.Studs
local INLET = Enum.SurfaceType.Inlet
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
	p.BottomSurface = INLET
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
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }

local function stroke(parent: Instance, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Color = color or TEXT_STROKE
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, color: Color3, strokePx: number, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = value
	t.TextScaled = true
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	stroke(t, strokePx)
	t.Parent = parent
	return t
end

local function surfaceGui(target: BasePart, face: Enum.NormalId, ppu: number): SurfaceGui
	(target :: any)[face.Name .. "Surface"] = STUDS -- panneaux : studs aussi, derriere le texte
	local g = Instance.new("SurfaceGui")
	g.Name = "Display"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = ppu
	g.LightInfluence = 0
	g.Parent = target
	return g
end

local function robuxIcon(parent: Instance, name: string, pos: UDim2, size: UDim2): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Position = pos
	img.Size = size
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = Icons.Robux
	img.ImageColor3 = Color3.fromRGB(235, 200, 255)
	img.Parent = parent
	return img
end

local base = ServerStorage:FindFirstChild("BaseTemplate")
assert(base, "Lancer 02a d'abord")
local old = base:FindFirstChild("Donations")
if old then
	old:Destroy()
end
local donations = Instance.new("Model")
donations.Name = "Donations"

-- Mur : face interieure a x = 1. Le panneau est colle contre (x 1.05 ->), face +X (Right).
local Z0, Z1 = 43, 57

-- ===== Tapis violet a bord dore =====
local rug = Instance.new("Folder")
rug.Name = "Rug"
-- Finit a x 7.5 (2026-11-20) : la porte d'entree commence a x 8, l'allee Entry (02k) prend toute sa largeur.
box(rug, "RugBorder", 1.1, 7.5, FLOOR_Y, FLOOR_Y + 0.12, 42, 63, GOLD, with(DECOR, { TopSurface = INLET }))
box(rug, "RugTop", 1.6, 7, FLOOR_Y + 0.12, FLOOR_Y + 0.24, 42.5, 62.5, PURPLE, with(DECOR, { TopSurface = INLET }))
rug.Parent = donations

-- ===== Panneau TOP DONORS =====
local board = Instance.new("Model")
board.Name = "Board"
box(board, "Back", 1.05, 1.85, FLOOR_Y + 0.25, 16.4, Z0, Z1, WOOD_DARK)
box(board, "Cap", 1.05, 2.75, 16.4, 17.0, Z0 - 0.5, Z1 + 0.5, WOOD_CAP)
box(board, "PostL", 1.85, 2.65, FLOOR_Y + 0.25, 16.4, Z0, Z0 + 0.8, WOOD_DARK)
box(board, "PostR", 1.85, 2.65, FLOOR_Y + 0.25, 16.4, Z1 - 0.8, Z1, WOOD_DARK)

-- En-tete orange : logo Robux + TOP DONORS
local header = box(board, "Header", 1.85, 2.45, 13.0, 16.0, Z0 + 0.8, Z1 - 0.8, SIGN_BG)
local headerGui = surfaceGui(header, Enum.NormalId.Right, 40)
robuxIcon(headerGui, "Logo", UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.16, 0.76))
text(headerGui, "Title", Donations.BoardTitle, UDim2.fromScale(0.2, 0.1), UDim2.fromScale(0.76, 0.8), Color3.new(1, 1, 1), 5)

-- Liste : une ligne par donateur (textes ecrits par DonationService)
local panel = box(board, "Panel", 1.85, 2.25, 1.4, 12.8, Z0 + 0.8, Z1 - 0.8, WOOD)
local panelGui = surfaceGui(panel, Enum.NormalId.Right, 40)
local rows = Instance.new("Frame")
rows.Name = "Rows"
rows.BackgroundTransparency = 1
rows.Position = UDim2.fromScale(0.03, 0.02)
rows.Size = UDim2.fromScale(0.94, 0.96)
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0.012, 0)
layout.Parent = rows
local rowHeight = (1 - 0.012 * (Donations.BoardRows - 1)) / Donations.BoardRows
for i = 1, Donations.BoardRows do
	local row = Instance.new("Frame")
	row.Name = "Row" .. i
	row.LayoutOrder = i
	row.Size = UDim2.fromScale(1, rowHeight)
	row.BackgroundColor3 = if i <= 3 then Color3.fromRGB(110, 60, 30) else Color3.fromRGB(150, 86, 40)
	row.BackgroundTransparency = 0.25
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = row
	stroke(row, 3, Color3.fromRGB(70, 36, 16))
	text(row, "Rank", "#" .. i, UDim2.fromScale(0.015, 0.12), UDim2.fromScale(0.11, 0.76), RANK_COLORS[i] or Color3.new(1, 1, 1), 3)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Color3.fromRGB(240, 220, 190)
	avatar.Position = UDim2.fromScale(0.135, 0.08)
	avatar.Size = UDim2.fromScale(0.84, 0.84)
	avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
	avatar.Image = ""
	avatar.Visible = false
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = avatar
	stroke(avatar, 2, Color3.fromRGB(70, 36, 16))
	avatar.Parent = row
	text(row, "PlayerName", if i == 1 then Donations.EmptyRow else "---", UDim2.fromScale(0.25, 0.14), UDim2.fromScale(0.43, 0.72), Color3.new(1, 1, 1), 3, Enum.TextXAlignment.Left)
	local icon = robuxIcon(row, "RobuxIcon", UDim2.fromScale(0.69, 0.18), UDim2.fromScale(0.08, 0.64))
	icon.Visible = false
	text(row, "Amount", "", UDim2.fromScale(0.77, 0.14), UDim2.fromScale(0.21, 0.72), Color3.fromRGB(150, 255, 120), 3, Enum.TextXAlignment.Right)
	row.Parent = rows
end
rows.Parent = panelGui
board.Parent = donations

-- ===== Table + urne =====
local TX0, TX1, TZ0, TZ1 = 1.6, 5.6, 58.4, 62.4
local TOP_Y = 3.6
local tableModel = Instance.new("Model")
tableModel.Name = "Table"
box(tableModel, "Top", TX0, TX1, TOP_Y - 0.5, TOP_Y, TZ0, TZ1, WOOD_CAP)
for _, corner in { { TX0 + 0.2, TZ0 + 0.2 }, { TX1 - 0.9, TZ0 + 0.2 }, { TX0 + 0.2, TZ1 - 0.9 }, { TX1 - 0.9, TZ1 - 0.9 } } do
	box(tableModel, "Leg", corner[1], corner[1] + 0.7, FLOOR_Y + 0.24, TOP_Y - 0.5, corner[2], corner[2] + 0.7, WOOD_DARK)
end
tableModel.Parent = donations

local jar = Instance.new("Model")
jar.Name = "Jar"
local JX, JZ = (TX0 + TX1) / 2, (TZ0 + TZ1) / 2
local JAR_H, JAR_D = 3.4, 2.8
local UP = CFrame.Angles(0, 0, math.pi / 2) -- l'axe d'un cylindre est X : on le met debout
local function cylinder(name: string, y0: number, y1: number, diameter: number, color: Color3, props: { [string]: any }?): BasePart
	local p = part(jar, name, Vector3.new(y1 - y0, diameter, diameter), CFrame.new(JX, (y0 + y1) / 2, JZ) * UP, color, with(SMOOTH, props or {})) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- Billets a l'interieur (petits blocs verts lisses, en vrac)
local rng = Random.new(42)
local cashY = TOP_Y + 0.05
for layer = 1, 4 do
	for _ = 1, 3 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(0, 0.5)
		local cf = CFrame.new(JX + math.cos(angle) * radius, cashY + 0.13, JZ + math.sin(angle) * radius)
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25))
		part(jar, "Bill", Vector3.new(1.3, 0.22, 0.65), cf, if layer % 2 == 0 then CASH_DARK else CASH, with(SMOOTH, DECOR))
	end
	cashY += 0.32
end
cylinder("Glass", TOP_Y + 0.02, TOP_Y + JAR_H, JAR_D, GLASS, {
	Material = Enum.Material.Glass,
	Transparency = 0.55,
	CastShadow = false,
	CanQuery = false,
})
cylinder("Neck", TOP_Y + JAR_H, TOP_Y + JAR_H + 0.25, JAR_D - 0.5, GLASS, { Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false, CanQuery = false })
cylinder("Lid", TOP_Y + JAR_H + 0.25, TOP_Y + JAR_H + 0.6, JAR_D - 0.3, PURPLE_DARK)
box(jar, "Slot", JX - 0.08, JX + 0.08, TOP_Y + JAR_H + 0.6, TOP_Y + JAR_H + 0.66, JZ - 0.5, JZ + 0.5, Color3.fromRGB(30, 20, 40), with(SMOOTH, DECOR))
local anchor = box(jar, "PromptAnchor", JX - 0.5, JX + 0.5, TOP_Y + 1, TOP_Y + 2, JZ - 0.5, JZ + 0.5, Color3.new(), with(SMOOTH, {
	Transparency = 1,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}))
-- Texte flottant "Donations!" (fixe : construit ici, comme les panneaux)
local label = Instance.new("BillboardGui")
label.Name = "Label"
label.Adornee = anchor
label.Size = UDim2.fromScale(6, 1.4)
label.StudsOffsetWorldSpace = Vector3.new(0, JAR_H + 0.6, 0)
label.MaxDistance = 60
label.LightInfluence = 0
local labelText = Instance.new("TextLabel")
labelText.Name = "Text"
labelText.BackgroundTransparency = 1
labelText.Size = UDim2.fromScale(1, 1)
labelText.FontFace = FONT
labelText.Text = Donations.JarLabel
labelText.TextScaled = true
labelText.TextColor3 = Color3.new(1, 1, 1)
local labelStroke = Instance.new("UIStroke")
labelStroke.Color = Color3.new(0, 0, 0)
labelStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
labelStroke.Thickness = 0.06
labelStroke.LineJoinMode = Enum.LineJoinMode.Round
labelStroke.Parent = labelText
labelText.Parent = label
label.Parent = anchor
jar.Parent = donations

donations.Parent = base
print("[02i] BaseTemplate.Donations construit (panneau TOP DONORS, table, urne)")
