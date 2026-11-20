--!strict
-- Morceau 02j (tour d'etages, lot 5, 2026-11-20) : dans BaseTemplate.Annex (rez-de-chaussee) :
--   * Terrace.ElevatorBoard : panneau "ELEVATOR" VERTICAL en bois colle SUR la cage de l'ascenseur, face nord
--     (z 11.35 -> 12.1, face vers +Z, x -8.8 -> -1.2, y 1.5 -> 13.7 : titre, tuile 1, tuile 2 de haut
--     en bas ; avant horizontal x -13.5 -> 0.5, il depassait de la cage), cote couloir ou arrive le joueur (retour de
--     test du 2026-11-20 : "le panneau de l'ascenseur est sur la terrasse, on ne comprend pas").
--     Avant : contre le mur de l'usine (x -1, z 46 -> 60). 2 tuiles : ElevatorSpeed / ElevatorCabin (attribut
--     TowerUpgradeId). Chaque tuile : Tile + SurfaceGui "Display" dessinee par Shared/Util/UpgradeTile
--     (Title, Icon, Value, Price) + BuyButton (Part invisible + ClickDetector devant le bouton vert :
--     CLIQUER = acheter, FloorService).
--     Plus de prompt E (2026-11-20 : "on doit CLIQUER dessus et pas avec E").
--   * ElevatorBase.Cabin : la cabine vitree (Model, PrimaryPart CabinFloor), en bas de la cage
--     (x -8.6 -> -1.4, z 3.4 -> 10.6), ouverte cote terrasse (-X) et cote balcon (+X). Retiree par
--     FloorService tant que la tour a 1 etage ; animee cote client (CustomerController).
-- A lancer apres 02f. Relancable (remplace l'ancien panneau et l'ancienne cabine).
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
local Icons = freshRequire(ReplicatedStorage.Shared.Config.Icons)
local UpgradeTile = freshRequire(ReplicatedStorage.Shared.Util.UpgradeTile)
local TILE_ICONS = { ElevatorSpeed = "Shoe", ElevatorCabin = "Customers" }

local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)
local WOOD = Color3.fromRGB(196, 116, 56)
local WOOD_DARK = Color3.fromRGB(132, 74, 36)
local TILE_COLORS = { Color3.fromRGB(35, 190, 245), Color3.fromRGB(180, 50, 235) } -- vives (captures du 2026-11-20)
local TRIM = Color3.fromRGB(124, 136, 162)
local GLASS = Color3.fromRGB(176, 208, 228)
local STUDS = Enum.SurfaceType.Studs
local SMOOTH = Enum.SurfaceType.Smooth
local WELD = Enum.SurfaceType.Weld

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
	for _, face in { "Front", "Back", "Left", "Right" } do
		(p :: any)[face .. "Surface"] = STUDS
	end
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

local function smooth(extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = {
		TopSurface = SMOOTH,
		BottomSurface = SMOOTH,
		FrontSurface = SMOOTH,
		BackSurface = SMOOTH,
		LeftSurface = SMOOTH,
		RightSurface = SMOOTH,
	}
	for k, v in extra or {} do
		t[k] = v
	end
	return t
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
	local s = Instance.new("UIStroke")
	s.Color = TEXT_STROKE
	s.Thickness = strokePx
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

-- SurfaceGui sur la face +Z (Back : la face qui regarde le couloir nord)
local function displayOn(target: BasePart): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "Display"
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = target
	return g
end

local base = ServerStorage:FindFirstChild("BaseTemplate")
assert(base, "Lancer 02a d'abord")
local annex = base:FindFirstChild("Annex")
local terrace = annex and annex:FindFirstChild("Terrace")
local shaft = annex and annex:FindFirstChild("ElevatorBase")
assert(terrace and shaft, "Lancer 02f d'abord (Annex.Terrace / Annex.ElevatorBase)")
for _, old in { terrace:FindFirstChild("ElevatorBoard"), shaft:FindFirstChild("Cabin") } do
	if old then
		old:Destroy()
	end
end

-- ===== Panneau ELEVATOR (bois), colle sur la face nord de la cage (z 11), face vers +Z =====
local BZ = 11.35 -- dos du panneau (contre les poteaux de la cage)
local BF = BZ + 0.55 -- face avant du cadre
-- Vertical (2026-11-20 : "fait vertical avec les 2 offres en bas et en haut, sinon ca depasse") :
-- largeur de la cage (x -9 -> -1), titre en haut, tuile 1 au milieu, tuile 2 en bas.
local X0, X1, Y0, Y1 = -8.8, -1.2, 1.5, 13.7
local TILE_H, TILE_GAP = 4.6, 0.3
local boardModel = Instance.new("Model")
boardModel.Name = "ElevatorBoard"
box(boardModel, "Frame", X0, X1, Y0, Y1, BZ, BF, WOOD_DARK)
local header = box(boardModel, "Header", X0 + 0.4, X1 - 0.4, Y1 - 2, Y1 - 0.3, BF, BF + 0.15, WOOD, smooth())
text(displayOn(header), "Title", "ELEVATOR", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84), Color3.new(1, 1, 1), 3)
for i, upgrade in FloorsConfig.ElevatorUpgrades do
	local tileModel = Instance.new("Model")
	tileModel.Name = upgrade.id
	tileModel:SetAttribute("TowerUpgradeId", upgrade.id)
	-- tuile 1 en haut (sous le titre), tuile 2 en dessous
	local tx0 = X0 + 0.4
	local tx1 = X1 - 0.4
	local tileTop = Y1 - 2.3 - (i - 1) * (TILE_H + TILE_GAP)
	local tileBottom = tileTop - TILE_H
	local tile = box(tileModel, "Tile", tx0, tx1, tileBottom, tileTop, BF, BF + 0.2, TILE_COLORS[i], smooth({
		TopSurface = WELD,
		BackSurface = WELD,
		CanCollide = false,
	}))
	UpgradeTile.Build(tile, Enum.NormalId.Back, {
		title = upgrade.title,
		color = TILE_COLORS[i],
		icon = Icons[TILE_ICONS[upgrade.id] or "Plus"],
		value = "+0%" .. UpgradeTile.ARROW .. "+4%",
		price = "$?",
	})
	-- Bouton vert : Part invisible + ClickDetector devant le bouton dessine (BUY_RECT_WIDE). Face +Z :
	-- vu du couloir, la droite de la tuile est vers +X (verifie en jeu le 2026-11-20).
	local r = UpgradeTile.BUY_RECT_WIDE
	local bx = tx0 + (r.x + r.w / 2) * (tx1 - tx0)
	local tileH = TILE_H
	local by = tileTop - (r.y + r.h / 2) * tileH
	local buy = part(tileModel, "BuyButton", Vector3.new(r.w * (tx1 - tx0), r.h * tileH, 0.1), CFrame.new(bx, by, BF + 0.45), Color3.fromRGB(70, 220, 70), smooth({
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	}))
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 36
	click.Parent = buy
	tileModel.PrimaryPart = tile
	tileModel.Parent = boardModel
end
boardModel.Parent = terrace

-- ===== Cabine vitree de l'ascenseur (en bas de la cage x -9 -> -1, z 3 -> 11) =====
local CX0, CX1, CZ0, CZ1 = -8.6, -1.4, 3.4, 10.6
local cabin = Instance.new("Model")
cabin.Name = "Cabin"
local NOCOL = { CanCollide = false, CanQuery = false, CanTouch = false }
local floorPart = box(cabin, "CabinFloor", CX0, CX1, 0.7, 1.0, CZ0, CZ1, Color3.fromRGB(70, 74, 86), smooth({
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	TopSurface = Enum.SurfaceType.Inlet,
}))
box(cabin, "CabinRoof", CX0, CX1, 9.4, 9.8, CZ0, CZ1, TRIM, smooth(NOCOL))
for _, z in { CZ0, CZ1 } do
	box(cabin, "CabinGlass", CX0 + 0.3, CX1 - 0.3, 1.0, 9.4, z - 0.08, z + 0.08, GLASS, smooth({
		Material = Enum.Material.SmoothPlastic, -- pas Glass (masque ce qui est transparent derriere)
		Transparency = 0.65,
		CastShadow = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}))
	for _, x in { CX0, CX1 } do
		box(cabin, "CabinPost", x - 0.15, x + 0.15, 1.0, 9.4, z - 0.15, z + 0.15, TRIM, smooth(NOCOL))
	end
end
local lamp = box(cabin, "CabinLamp", -5.6, -4.4, 9.2, 9.4, 6.4, 7.6, Color3.fromRGB(255, 244, 210), smooth({
	Material = Enum.Material.Neon,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}))
local light = Instance.new("PointLight")
light.Range = 12
light.Brightness = 1.2
light.Parent = lamp
cabin.PrimaryPart = floorPart
cabin.Parent = shaft

print("[02j] ElevatorBoard + Cabin OK")
return true
