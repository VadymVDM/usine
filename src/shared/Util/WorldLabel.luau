--!strict
-- Petits textes 3D au-dessus des piles ("12/20", "Tree full!") au style du jeu (blanc, contour noir epais).
-- Aucune attente ; l'appelant choisit le parent.
-- Doc : docs/systems/chaine-production.md

local WorldLabel = {}

export type Options = { maxDistance: number?, size: UDim2?, offset: Vector3?, alwaysOnTop: boolean? }

local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local WHITE = Color3.new(1, 1, 1)
local FULL_COLOR = Color3.fromRGB(255, 110, 110)
local ALERT_COLOR = Color3.fromRGB(235, 40, 40)
local ALERT_STROKE = Color3.fromRGB(110, 10, 10)
local STROKE_RATIO = 0.06 -- epaisseur du contour / hauteur du texte (comme les textes du pack UI)

local function makeLabel(name: string, position: UDim2, size: UDim2, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.FontFace = FONT
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	-- Contour proportionnel a la taille du texte a l'ecran : il ne noircit plus tout de loin
	-- et ne disparait plus de pres (un contour en pixels fixes ne suit pas la distance).
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = STROKE_RATIO
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

-- Pastille "!" : rond rouge, point d'exclamation blanc epais, contour fonce (lisible de loin).
local function makeAlert(): Frame
	local badge = Instance.new("Frame")
	badge.Name = "Alert"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.9, 0.5)
	badge.Size = UDim2.fromScale(0.82, 0.82)
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	badge.BackgroundColor3 = ALERT_COLOR
	badge.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = badge
	local ring = Instance.new("UIStroke")
	ring.Color = ALERT_STROKE
	ring.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	ring.Thickness = 0.08
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = badge
	local mark = makeLabel("Mark", UDim2.fromScale(0.1, 0.08), UDim2.fromScale(0.8, 0.84), "!", WHITE)
	mark.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	mark.Parent = badge
	return badge
end

function WorldLabel.Create(parent: Instance, adornee: BasePart, name: string, options: Options?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = adornee
	gui.AlwaysOnTop = options ~= nil and options.alwaysOnTop == true
	gui.LightInfluence = 0
	gui.MaxDistance = if options and options.maxDistance then options.maxDistance else 60
	gui.Size = if options and options.size then options.size else UDim2.fromScale(6, 2)
	gui.StudsOffset = if options and options.offset then options.offset else Vector3.zero
	gui.DistanceLowerLimit = 10 -- de tout pres, le texte ne grossit plus

	local text = makeLabel("Text", UDim2.fromScale(0, 0), UDim2.fromScale(0.8, 1), "", WHITE)
	text.Parent = gui

	makeAlert().Parent = gui

	gui.Parent = parent
	return gui
end

local function findLabel(gui: BillboardGui, name: string): TextLabel?
	local child = gui:FindFirstChild(name)
	if child and child:IsA("TextLabel") then
		return child
	end
	return nil
end

function WorldLabel.SetText(gui: BillboardGui, text: string, color: Color3?)
	local label = findLabel(gui, "Text")
	if label == nil then
		return
	end
	local newColor = color or WHITE
	if label.Text ~= text then
		label.Text = text
	end
	if label.TextColor3 ~= newColor then
		label.TextColor3 = newColor
	end
end

-- Texte seul sur toute la largeur (pas de pastille), ex. "x12", "$1.2K", "Tree full!".
function WorldLabel.SetPlainText(gui: BillboardGui, text: string, color: Color3?)
	local label = findLabel(gui, "Text")
	if label and label.Size.X.Scale ~= 1 then
		label.Size = UDim2.fromScale(1, 1)
	end
	WorldLabel.SetText(gui, text, color)
end

function WorldLabel.SetCount(gui: BillboardGui, count: number, max: number)
	local label = findLabel(gui, "Text")
	local alert = gui:FindFirstChild("Alert")
	local full = count >= max
	if label then
		local text = `{count}/{max}`
		if label.Text ~= text then
			label.Text = text
		end
		local color = if full then FULL_COLOR else WHITE
		if label.TextColor3 ~= color then
			label.TextColor3 = color
		end
	end
	if alert and alert:IsA("GuiObject") and alert.Visible ~= full then
		alert.Visible = full
	end
end

function WorldLabel.SetVisible(gui: BillboardGui, visible: boolean)
	if gui.Enabled ~= visible then
		gui.Enabled = visible
	end
end

return WorldLabel
