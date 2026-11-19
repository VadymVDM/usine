--!strict
-- Briques d'interface au style du pack UI (texte, boutons en degrade, logo Robux avec contour).
-- Utilise par WelcomeBackController ; ShopController a encore ses propres copies (a regrouper).
-- Doc : docs/systems/interface.md

local PackStyle = {}

PackStyle.FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
PackStyle.TEXT_STROKE = Color3.fromRGB(30, 22, 40)
PackStyle.GREEN = { Color3.fromRGB(64, 252, 9), Color3.fromRGB(237, 255, 76), Color3.fromRGB(23, 74, 0) }
PackStyle.PURPLE = { Color3.fromRGB(140, 0, 255), Color3.fromRGB(215, 120, 255), Color3.fromRGB(50, 0, 90) }
PackStyle.MONEY_GREEN = Color3.fromRGB(76, 255, 63)

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
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.ZIndex = 3
	PackStyle.stroke(button, 3, colors[3], Enum.ApplyStrokeMode.Border)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = ColorSequence.new(colors[1], colors[2])
	gradient.Parent = button
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 3
	PackStyle.stroke(inner, 1.5, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border).Transparency = 0.35
	inner.Parent = button
	button.Parent = parent
	return button
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

return PackStyle
