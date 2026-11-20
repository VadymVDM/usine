--!strict
-- Briques d'interface au style du pack UI (texte, boutons en degrade, logo Robux avec contour).
-- SOURCE UNIQUE du style de l'interface : toute nouvelle interface prend ses couleurs, sa police et
-- ses boutons ici (regle "une seule apparence", demande utilisateur du 2026-11-19).
-- Doc : docs/systems/interface.md (section "Charte de l'interface")

local PackStyle = {}

-- Une seule police pour tout ce que le joueur lit (menus, HUD, textes qui volent, panneaux 3D).
PackStyle.FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
PackStyle.TEXT_STROKE = Color3.fromRGB(30, 22, 40)
-- Couleurs de bouton : { bas du degrade, haut du degrade, contour }. Vert = action principale /
-- achat / ON ; rouge = annuler / OFF ; violet = Robux en plus (x2) ; rose = cadeau.
PackStyle.GREEN = { Color3.fromRGB(64, 252, 9), Color3.fromRGB(237, 255, 76), Color3.fromRGB(23, 74, 0) }
PackStyle.RED = { Color3.fromRGB(255, 40, 40), Color3.fromRGB(255, 130, 110), Color3.fromRGB(90, 0, 0) }
PackStyle.PURPLE = { Color3.fromRGB(140, 0, 255), Color3.fromRGB(215, 120, 255), Color3.fromRGB(50, 0, 90) }
PackStyle.PINK = { Color3.fromRGB(230, 20, 190), Color3.fromRGB(255, 150, 240), Color3.fromRGB(80, 0, 64) }
PackStyle.MONEY_GREEN = Color3.fromRGB(76, 255, 63)
-- Contour du montant d'argent du HUD (HUD.rbxm) : les "+$X" qui volent vers lui le reprennent.
PackStyle.MONEY_STROKE = Color3.fromRGB(9, 48, 0)
-- Boutons sur les cotes de l'ecran (Shop/Index a gauche, offres a droite) : meme largeur
-- (part de la largeur de l'ecran) et meme marge au bord, pour qu'ils soient symetriques.
PackStyle.SIDE_BUTTON_WIDTH = 0.075
PackStyle.SIDE_BUTTON_WIDTH_PHONE = 0.085 -- ecran de moins de 450 px de haut
PackStyle.SIDE_MARGIN = 0.005
-- En-tete de tous les menus (bandeau cyan de l'Index du pack) : degrade bas -> haut + bord du bas.
PackStyle.HEADER = { Color3.fromRGB(51, 168, 255), Color3.fromRGB(6, 255, 255), Color3.fromRGB(0, 123, 255) }

local ROBUX_OUTLINE_OFFSETS = {
	Vector2.new(-1.5, 0),
	Vector2.new(1.5, 0),
	Vector2.new(0, -1.5),
	Vector2.new(0, 1.5),
	Vector2.new(-1, -1),
	Vector2.new(1, -1),
	Vector2.new(-1, 1),
	Vector2.new(1, 1),
}

-- Epaisseur des contours selon la hauteur de l'ecran (plus fin sur telephone).
function PackStyle.strokeScale(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	return math.clamp(height / 700, 0.55, 1)
end

function PackStyle.stroke(parent: Instance, thickness: number, color: Color3?, mode: Enum.ApplyStrokeMode?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = math.max(1, thickness * PackStyle.strokeScale())
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Texte blanc d'une ligne, contour fonce, taille automatique (avec un maximum).
function PackStyle.label(parent: Instance, text: string, position: UDim2, size: UDim2, maxSize: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = position
	label.Size = size
	label.FontFace = PackStyle.FONT
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.ZIndex = 4
	PackStyle.stroke(label, 2.5, PackStyle.TEXT_STROKE)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize or 60
	limit.Parent = label
	label.Parent = parent
	return label
end

-- Bouton en degrade (bas -> haut) + liseret blanc + contour fonce, bords carres.
function PackStyle.button(parent: Instance, name: string, colors: { Color3 }, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = position
	button.Size = size
	button.ZIndex = 3
	PackStyle.dress(button, colors)
	button.Parent = parent
	return button
end

-- Donne le look du bouton commun a un bouton deja existant (ex. bouton du pack dans un .rbxm) :
-- ses anciens decors sont caches, il garde ses clics et sa place. `sequence` remplace le degrade
-- 2 couleurs (ex. arc-en-ciel de la rarete Divine).
function PackStyle.dress(button: GuiButton, colors: { Color3 }, sequence: ColorSequence?)
	for _, child in button:GetChildren() do
		if child:IsA("GuiObject") then
			child.Visible = false
		elseif child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then
			child:Destroy()
		end
	end
	if button:IsA("ImageButton") then
		button.Image = ""
	end
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.BackgroundTransparency = 0
	PackStyle.stroke(button, 3, colors[3], Enum.ApplyStrokeMode.Border)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = sequence or ColorSequence.new(colors[1], colors[2])
	gradient.Parent = button
	local inner = Instance.new("Frame")
	inner.Name = "InnerLine"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = button.ZIndex
	PackStyle.stroke(inner, 1.5, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border).Transparency = 0.35
	inner.Parent = button
end

-- Meme taille de texte pour une serie de textes (ex. "Rare" et "Legendary") : la plus grande taille
-- qui rentre pour TOUS, recalculee quand l'ecran change. Les textes doivent avoir la meme boite.
function PackStyle.sameTextSize(labels: { TextLabel }, maxSize: number)
	if #labels == 0 then
		return
	end
	local TextService = game:GetService("TextService")
	local function fit()
		local best = maxSize
		for _, label in labels do
			local box = label.AbsoluteSize
			if box.X < 2 or box.Y < 2 then
				return -- pas encore affiche
			end
			local ok, size = pcall(function()
				local params = Instance.new("GetTextBoundsParams")
				params.Text = label.Text
				params.Font = label.FontFace
				params.Size = 100
				params.Width = 100000
				return TextService:GetTextBoundsAsync(params)
			end)
			if ok and size.X > 0 and size.Y > 0 then
				best = math.min(best, math.floor(100 * math.min(box.X / size.X, box.Y / size.Y)))
			end
		end
		for _, label in labels do
			label.TextScaled = false
			label.TextSize = math.max(1, best)
		end
	end
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			fit()
		end)
	end
	labels[1]:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
	schedule()
end

-- Logo Robux blanc entoure d'un contour fonce (copies foncees decalees).
function PackStyle.robux(parent: Instance, image: string, size: UDim2, zIndex: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Robux"
	holder.BackgroundTransparency = 1
	holder.Size = size
	holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
	holder.ZIndex = zIndex
	local scale = PackStyle.strokeScale()
	local function layer(offset: Vector2, color: Color3)
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Position = UDim2.fromOffset(offset.X * scale, offset.Y * scale)
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = image
		img.ImageColor3 = color
		img.ZIndex = zIndex
		img.Parent = holder
	end
	for _, offset in ROBUX_OUTLINE_OFFSETS do
		layer(offset, PackStyle.TEXT_STROKE)
	end
	layer(Vector2.zero, Color3.new(1, 1, 1))
	holder.Parent = parent
	return holder
end

-- Rangee centree [Robux] prix.
function PackStyle.priceRow(parent: Instance, robuxImage: string, price: number, position: UDim2, size: UDim2): Frame
	local row = Instance.new("Frame")
	row.Name = "Price"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = position
	row.Size = size
	row.ZIndex = 4
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = row
	local icon = PackStyle.robux(row, robuxImage, UDim2.fromScale(0.85, 0.85), 4)
	icon.LayoutOrder = 1
	local text = tostring(price)
	local priceLabel = PackStyle.label(row, text, UDim2.new(), UDim2.fromScale(0.5 * #text, 0.95))
	priceLabel.AnchorPoint = Vector2.zero
	priceLabel.SizeConstraint = Enum.SizeConstraint.RelativeYY
	priceLabel.LayoutOrder = 2
	row.Parent = parent
	return row
end

-- Espace regulier dans une liste qui defile : entre les elements, et en haut / en bas (pour ne pas
-- coller a l'en-tete). `ratio` = part de la hauteur visible de la liste ; recalcule si elle change.
-- Marche avec UIListLayout et UIGridLayout (seul l'ecart vertical change).
function PackStyle.spaceList(scroll: ScrollingFrame, ratio: number)
	local padding = scroll:FindFirstChildOfClass("UIPadding")
	if padding == nil then
		local created = Instance.new("UIPadding")
		created.Parent = scroll
		padding = created
	end
	local pad = padding :: UIPadding
	local function apply()
		local gap = math.max(6, math.floor(scroll.AbsoluteWindowSize.Y * ratio))
		pad.PaddingTop = UDim.new(0, gap)
		pad.PaddingBottom = UDim.new(0, gap)
		local list = scroll:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, gap)
		end
		local grid = scroll:FindFirstChildOfClass("UIGridLayout")
		if grid then
			grid.CellPadding = UDim2.new(grid.CellPadding.X.Scale, grid.CellPadding.X.Offset, 0, gap)
		end
	end
	apply()
	scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(apply)
end

return PackStyle
