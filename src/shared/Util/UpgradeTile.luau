--!strict
-- Dessin d'une tuile d'amelioration sur un panneau en bois (style des captures de reference du
-- 2026-11-20) : fond colore (Part a surface Weld = traits en X) + voile de la meme couleur sans
-- eclairage dans la SurfaceGui (sinon la couleur parait sombre), contour noir epais, titre en haut,
-- grosse icone a gauche avec une fleche verte, "actuel -> suivant" a droite, puis un bouton vert
-- (prix) et un bouton violet (Robux) dessines dans la meme SurfaceGui.
-- On CLIQUE le bouton vert pour acheter (BuyController, simple clic) : Part invisible "BuyButton"
-- posee par l'outil sur BUY_RECT ; le bouton violet a sa Part invisible "RobuxButton" sur ROBUX_RECT.
-- Utilise par les outils tools/build-map/02g (panneaux d'etage) et 02j (panneau Elevator).
-- Libelles mis a jour par le serveur : "Value", "Price", "Robux" (noms uniques dans la tuile).
-- Doc : docs/systems/ameliorations-employes.md (section Panneaux)

local UpgradeTile = {}

export type Info = {
	title: string,
	color: Color3, -- couleur du fond (vive : pas d'eclairage dessus)
	icon: string?, -- id d'image (rbxassetid://...)
	value: string,
	price: string,
	robux: string?, -- nil = pas de bouton violet (panneau Elevator)
	robuxIcon: string?,
}

UpgradeTile.ARROW = " → " -- separateur "actuel -> suivant" (comme les captures)
UpgradeTile.PIXELS_PER_STUD = 50
-- Boutons en fraction de la tuile (x, y, largeur, hauteur), vus de face. Les outils posent une Part
-- invisible "BuyButton" / "RobuxButton" (ClickDetector) juste devant chaque bouton dessine : c'est
-- ELLE qu'on clique (2026-11-20 : "c'est les boutons qui doivent hover, pas toute l'interface").
UpgradeTile.ROBUX_RECT = table.freeze({ x = 0.75, y = 0.62, w = 0.21, h = 0.3 })
UpgradeTile.BUY_RECT = table.freeze({ x = 0.36, y = 0.62, w = 0.37, h = 0.3 }) -- avec bouton violet
UpgradeTile.BUY_RECT_WIDE = table.freeze({ x = 0.36, y = 0.62, w = 0.6, h = 0.3 }) -- sans (Elevator)

local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local BLACK = Color3.fromRGB(16, 14, 22)
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(64, 214, 64)
local GREEN_DARK = Color3.fromRGB(30, 150, 40)
local ARROW_GREEN = Color3.fromRGB(70, 220, 80)
local PURPLE = Color3.fromRGB(176, 60, 236)
local PURPLE_DARK = Color3.fromRGB(120, 30, 180)

local function stroke(parent: Instance, thickness: number, mode: Enum.ApplyStrokeMode?)
	local s = Instance.new("UIStroke")
	s.Color = BLACK
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
end

local function frame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, strokePx: number, z: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = WHITE
	t.ZIndex = z or 3
	local s = Instance.new("UIStroke")
	s.Color = BLACK
	s.Thickness = strokePx
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

-- Degrade vertical (haut clair, bas fonce) comme les boutons du pack UI
local function shade(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
end

-- Fleche verte vers le haut (triangle + tige, contour noir), dessinee en Frames : pas d'image a
-- mettre en ligne. Le triangle = un carre tourne de 45 degres, coupe a moitie par HeadClip.
local function arrow(parent: Instance, pos: UDim2, size: UDim2, z: number)
	local box = frame(parent, "Arrow", pos, size, nil, z)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.8
	ratio.Parent = box
	-- Tige (sous la tete : son contour du haut est cache par la tete)
	local stem = frame(box, "Stem", UDim2.fromScale(0.3, 0.38), UDim2.fromScale(0.4, 0.6), ARROW_GREEN, z)
	stroke(stem, 3)
	shade(stem, ARROW_GREEN, GREEN_DARK)
	-- Tete : moitie haute d'un losange (largeur = toute la boite, hauteur = la moitie de la largeur)
	local clip = frame(box, "HeadClip", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.4), nil, z + 1)
	clip.ClipsDescendants = true
	local diamond = frame(clip, "Head", UDim2.fromScale(0.5, 1), UDim2.fromScale(0.68, 0.68), ARROW_GREEN, z + 1)
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.SizeConstraint = Enum.SizeConstraint.RelativeXX
	diamond.Rotation = 45
	stroke(diamond, 3)
	-- Trait noir sous la tete, de chaque cote de la tige
	for _, x in { 0, 0.7 } do
		local bar = frame(clip, "HeadBase", UDim2.new(x, 0, 1, -3), UDim2.new(0.3, 0, 0, 3), BLACK, z + 2)
		bar.BorderSizePixel = 0
	end
end

-- Voile de couleur vive (sans eclairage) par-dessus la Part : la couleur ne parait plus sombre,
-- et les traits en X de la surface Weld de la Part restent visibles au travers (l'utilisateur
-- aime cette texture, 2026-11-20 : "c'etait juste la couleur qui va pas, c'est trop sombre").
-- Couleurs pures et saturees comme la capture de reference (2026-11-20) : voile presque opaque,
-- pas de blanc ajoute (le pastel ne plaisait pas). Les traits Weld restent visibles en filigrane.
local FILL_TRANSPARENCY = 0.15
local LIGHTEN = 0 -- part de blanc ajoutee a la couleur (fond et Part)
local WHITE_MIX = Color3.new(1, 1, 1)
local function fill(gui: SurfaceGui, color: Color3)
	local f = frame(gui, "Fill", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), color, 0)
	f.BackgroundTransparency = FILL_TRANSPARENCY
end

-- Construit la SurfaceGui "Display" de la tuile (sur la face `face` de `tile`).
function UpgradeTile.Build(tile: BasePart, face: Enum.NormalId, info: Info): SurfaceGui
	local old = tile:FindFirstChild("Display")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = UpgradeTile.PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bright = info.color:Lerp(WHITE_MIX, LIGHTEN)
	fill(gui, bright)
	tile.Color = bright

	-- Contour noir epais tout autour (dans la tuile : le bord exterieur serait coupe)
	local border = frame(gui, "Border", UDim2.fromOffset(4, 4), UDim2.new(1, -8, 1, -8), nil, 5)
	stroke(border, 7, Enum.ApplyStrokeMode.Border)

	label(gui, "Title", info.title, UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.92, 0.24), 3)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromScale(0.04, 0.31)
	icon.Size = UDim2.fromScale(0.27, 0.62)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = info.icon or ""
	icon.ZIndex = 2
	icon.Parent = gui
	arrow(gui, UDim2.fromScale(0.215, 0.26), UDim2.fromScale(0.14, 0.44), 3)

	label(gui, "Value", info.value, UDim2.fromScale(0.36, 0.3), UDim2.fromScale(0.6, 0.27), 3)

	-- Bouton vert du prix. Centre (AnchorPoint 0.5) + UIScale "Scale" : BoardFxController le fait
	-- grossir au survol et s'ecraser au clic autour de son centre.
	local b = if info.robux then UpgradeTile.BUY_RECT else UpgradeTile.BUY_RECT_WIDE
	local buy = frame(gui, "BuyBox", UDim2.fromScale(b.x + b.w / 2, b.y + b.h / 2), UDim2.fromScale(b.w, b.h), GREEN, 3)
	buy.AnchorPoint = Vector2.new(0.5, 0.5)
	local buyScale = Instance.new("UIScale")
	buyScale.Name = "Scale"
	buyScale.Parent = buy
	stroke(buy, 4, Enum.ApplyStrokeMode.Border)
	shade(buy, Color3.fromRGB(110, 240, 100), GREEN)
	label(buy, "Price", info.price, UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.8), 3, 4)

	if info.robux then
		local r = UpgradeTile.ROBUX_RECT
		local robux = frame(gui, "RobuxBox", UDim2.fromScale(r.x + r.w / 2, r.y + r.h / 2), UDim2.fromScale(r.w, r.h), PURPLE, 3)
		robux.AnchorPoint = Vector2.new(0.5, 0.5)
		local robuxScale = Instance.new("UIScale")
		robuxScale.Name = "Scale"
		robuxScale.Parent = robux
		stroke(robux, 4, Enum.ApplyStrokeMode.Border)
		shade(robux, Color3.fromRGB(200, 100, 250), PURPLE_DARK)
		local robuxIcon = Instance.new("ImageLabel")
		robuxIcon.Name = "RobuxIcon"
		robuxIcon.BackgroundTransparency = 1
		robuxIcon.Position = UDim2.fromScale(0.05, 0.15)
		robuxIcon.Size = UDim2.fromScale(0.4, 0.7)
		robuxIcon.ScaleType = Enum.ScaleType.Fit
		robuxIcon.Image = info.robuxIcon or ""
		robuxIcon.ZIndex = 4
		robuxIcon.Parent = robux
		label(robux, "Robux", info.robux, UDim2.fromScale(0.46, 0.12), UDim2.fromScale(0.5, 0.76), 2.5, 4)
	end

	gui.Parent = tile
	return gui
end

return UpgradeTile
