--!strict
-- Logo du proprietaire au sommet de sa tour (demande du 2026-11-20 : "en haut des bases on doit
-- avoir le logo du joueur") : grosse photo ronde de l'avatar (AvatarHeadShot), son nom, et juste
-- dessous, en jaune et plus petit, son nombre de rebirths ("0 Rebirths" : sans fond ni icone).
-- BillboardGui pose juste au-dessus du toit de l'etage le plus haut (etage ferme a acheter compris),
-- a la taille de l'usine. Pas AlwaysOnTop (choix utilisateur : le logo ne doit pas passer a travers
-- les murs).
-- Base libre : rien. Le Model est Persistent (StreamingEnabled) pour etre vu de loin, depuis la route.
-- Appele par FloorService a chaque changement de proprietaire, du nombre d'etages ou apres un rebirth.
-- Doc : docs/systems/carte-bases.md (ligne OwnerBadge)

local Config = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")
local Floors = require(Config:WaitForChild("Floors"))
local Rebirth = require(Config:WaitForChild("Rebirth"))

local OwnerBadge = {}

local NAME = "OwnerBadge"
local CENTER = Vector3.new(50.5, 0, 32) -- milieu de l'usine en largeur, avant du toit (cote route)
local ROOF_TOP = 41 -- haut du toit d'un etage au-dessus de son sol (studs)
local WIDTH = 100 -- studs : la largeur de l'usine (~110, retour de test 2026-11-20)
local HEIGHT = 66 -- studs
local GAP = 3 -- espace entre le haut du toit et le bas du logo (studs)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local THUMB = "rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420"
local DARK = Color3.fromRGB(16, 14, 22)

-- Texte vu par le joueur (anglais)
local function rebirthsText(n: number): string
	return if n == 1 then "1 Rebirth" else `{n} Rebirths`
end

type Badge = {
	model: Model,
	anchor: BasePart,
	gui: BillboardGui,
	image: ImageLabel,
	name: TextLabel,
	rebirths: TextLabel,
}

local badges: { [Model]: Badge } = {}

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = parent
end

-- Contour en pixels pour ~25 px/stud : BillboardStrokeController le rend proportionnel
local function stroke(parent: Instance, thickness: number, border: boolean)
	local s = Instance.new("UIStroke")
	s.Color = DARK
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

local function text(parent: Instance, name: string, color: Color3, thickness: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = ""
	stroke(label, thickness, false)
	label.Parent = parent
	return label
end

local function build(base: Model): Badge
	local model = Instance.new("Model")
	model.Name = NAME
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = model
	model.PrimaryPart = anchor

	local gui = Instance.new("BillboardGui")
	gui.Name = "Badge"
	gui.Size = UDim2.fromScale(WIDTH, HEIGHT) -- studs (grandit avec la distance comme le reste du decor)
	gui.LightInfluence = 0
	gui.MaxDistance = 2000
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = anchor

	-- Rond bleu, contour noir, photo de l'avatar dedans (en haut, 36 studs de diametre)
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0)
	ring.Position = UDim2.fromScale(0.5, 0)
	ring.Size = UDim2.fromScale(0.36, 0.36)
	ring.SizeConstraint = Enum.SizeConstraint.RelativeXX
	ring.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(ring)
	stroke(ring, 22, true)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(40, 140, 240))
	gradient.Parent = ring
	ring.Parent = gui

	local image = Instance.new("ImageLabel")
	image.Name = "Avatar"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0.92, 0.92)
	image.ScaleType = Enum.ScaleType.Crop
	corner(image)
	image.Parent = ring

	-- Nom (sous la photo, ~16 studs de haut)
	local name = text(gui, "OwnerName", Color3.new(1, 1, 1), 10)
	name.Position = UDim2.fromScale(0.5, 0.57)
	name.Size = UDim2.fromScale(1, 0.24)

	-- Rebirths : jaune, plus petit (~10 studs), juste sous le nom
	local rebirths = text(gui, "Rebirths", Rebirth.TitleColor, 8)
	rebirths.Position = UDim2.fromScale(0.5, 0.82)
	rebirths.Size = UDim2.fromScale(1, 0.16)

	model.Parent = base
	return { model = model, anchor = anchor, gui = gui, image = image, name = name, rebirths = rebirths }
end

-- Met a jour le logo de `base`. `player` nil = base libre (logo cache). `topFloor` = numero de
-- l'etage le plus haut dessine (etage ferme compris) ; `rebirths` = nombre affiche.
function OwnerBadge.Update(base: Model, player: Player?, topFloor: number, rebirths: number)
	local badge = badges[base]
	if badge == nil or badge.model.Parent ~= base then
		badge = build(base)
		badges[base] = badge
	end
	if player == nil then
		badge.gui.Enabled = false
		return
	end
	local y = Floors.FloorHeight * (math.max(topFloor, 1) - 1) + ROOF_TOP + GAP + HEIGHT / 2
	badge.anchor.CFrame = base:GetPivot() * CFrame.new(CENTER.X, y, CENTER.Z)
	badge.image.Image = string.format(THUMB, player.UserId)
	badge.name.Text = player.DisplayName
	badge.rebirths.Text = rebirthsText(math.max(rebirths, 0))
	badge.gui.Enabled = true
end

return OwnerBadge
