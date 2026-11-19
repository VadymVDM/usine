--!strict
-- Construit le contenu du menu Shop (ShopGUI.MenuFrames.Shop) a partir de Config/Shop.
-- Sections : Potions (boosts), Passes (avec bouton cadeau), Packs d'argent.
-- Style du pack UI : bords carres, fond a motif + degrade 2 couleurs, liseret blanc, contour noir.
-- Tout est en echelle (scale) + rapports fixes, pour rester centre sur PC, tablette et telephone.
-- Les tailles de texte sont egalisees par groupe (titres, prix...) pour un rendu uniforme.
-- Les achats ne sont pas encore branches (ids a 0) : le clic affiche un avertissement.
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopController = {}

local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PATTERN = "rbxassetid://89847456327542"
local BUY_COLORS = { Color3.fromRGB(64, 252, 9), Color3.fromRGB(237, 255, 76), Color3.fromRGB(23, 74, 0) }
local GIFT_COLORS = { Color3.fromRGB(230, 20, 190), Color3.fromRGB(255, 150, 240), Color3.fromRGB(80, 0, 64) }
-- Contour des textes : gris tres fonce un peu transparent, coins arrondis (moins dur que le noir pur).
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)
local CASH_COLORS = { Color3.fromRGB(31, 168, 0), Color3.fromRGB(157, 255, 58) }
local OPEN_ANIMATION_TIME = 0.4
-- Groupes ou un texte trop long ne doit pas faire retrecir tous les autres.
local CAP_GROUPS = { PassTitle = true, Tag = true }
local SMALL_SCREEN_HEIGHT = 450 -- en dessous : telephone -> contours plus fins -- attendre la fin de l'animation d'ouverture avant de mesurer

type Config = typeof(require(ReplicatedStorage.Shared.Config.Shop))

local Shop: Config
local Icons: { [string]: string }
local scroll: ScrollingFrame
local shopMenu: GuiObject
local order = 0
local textGroups: { [string]: { TextLabel } } = {}
local lastFitSize: Vector2? = nil
local strokeScale = 1 -- epaisseur des contours selon la hauteur de l'ecran
local smallScreen = false
local sectionTitles: { Frame } = {}
local SECTION_TITLE_RATIO = 0.07 -- hauteur des titres de section / largeur de la boutique

-- Constructeurs de base ---------------------------------------------------------------------------

local function nextOrder(): number
	order += 1
	return order
end

local function addStroke(parent: Instance, thickness: number, color: Color3?, mode: Enum.ApplyStrokeMode?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = math.max(1, thickness * strokeScale)
	stroke.Color = color or BLACK
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = parent
	return stroke
end

local function innerLine(parent: GuiObject, inset: number, thickness: number, transparency: number, zIndex: number)
	local inner = Instance.new("Frame")
	inner.Name = "InnerLine"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	inner.BackgroundTransparency = 1
	inner.ZIndex = zIndex
	addStroke(inner, thickness, WHITE, Enum.ApplyStrokeMode.Border).Transparency = transparency
	inner.Parent = parent
end

-- Texte d'une ligne. `group` = les textes d'un meme groupe auront la meme taille.
local function label(parent: Instance, text: string, group: string, position: UDim2, size: UDim2): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = group
	textLabel.BackgroundTransparency = 1
	textLabel.AnchorPoint = Vector2.new(0.5, 0)
	textLabel.Position = position
	textLabel.Size = size
	textLabel.FontFace = FONT
	textLabel.Text = text
	textLabel.TextColor3 = WHITE
	textLabel.TextScaled = true
	textLabel.TextWrapped = false
	textLabel.ZIndex = 4
	local stroke = addStroke(textLabel, 2, TEXT_STROKE)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Transparency = 0.1
	textLabel.Parent = parent
	local list = textGroups[group]
	if not list then
		list = {}
		textGroups[group] = list
	end
	table.insert(list, textLabel)
	return textLabel
end

local function image(parent: Instance, iconKey: string, position: UDim2, size: UDim2): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0)
	img.Position = position
	img.Size = size
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = Icons[iconKey] or ""
	img.ZIndex = 3
	img.Parent = parent
	return img
end

local function card(parent: Instance, name: string, bottom: Color3, top: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = WHITE
	frame.LayoutOrder = nextOrder()
	frame.ZIndex = 1
	addStroke(frame, 4, BLACK, Enum.ApplyStrokeMode.Border)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = ColorSequence.new(bottom, top)
	gradient.Parent = frame
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "Pattern"
	pattern.Size = UDim2.fromScale(1, 1)
	pattern.BackgroundTransparency = 1
	pattern.Image = PATTERN
	pattern.ImageTransparency = 0.8
	pattern.ScaleType = Enum.ScaleType.Tile
	pattern.TileSize = UDim2.fromOffset(60, 60)
	pattern.ZIndex = 1
	pattern.Parent = frame
	innerLine(frame, 4, 2, 0.45, 2)
	frame.Parent = parent
	return frame
end

-- Bouton au style du pack : degrade + liseret blanc + contour fonce, bords carres.
local function packButton(parent: Instance, name: string, colors: { Color3 }, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = WHITE
	button.ZIndex = 3
	addStroke(button, 3, colors[3], Enum.ApplyStrokeMode.Border)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = ColorSequence.new(colors[1], colors[2])
	gradient.Parent = button
	innerLine(button, 3, 1.5, 0.3, 3)
	button.Parent = parent
	return button
end

-- Decalages (en pixels) des copies foncees qui forment le contour du logo Robux.
local ROBUX_OUTLINE_OFFSETS = {
	Vector2.new(-1.5, 0), Vector2.new(1.5, 0), Vector2.new(0, -1.5), Vector2.new(0, 1.5),
	Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1),
}

-- Logo Robux blanc avec un contour fonce, comme le texte (copies foncees decalees tout autour).
local function robuxIcon(parent: Instance, size: UDim2, zIndex: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Robux"
	holder.BackgroundTransparency = 1
	holder.Size = size
	holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
	holder.ZIndex = zIndex
	local function layer(offset: Vector2, color: Color3)
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Position = UDim2.fromOffset(offset.X * strokeScale, offset.Y * strokeScale)
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = Icons.Robux
		img.ImageColor3 = color
		img.ZIndex = zIndex
		img.Parent = holder
	end
	for _, offset in ROBUX_OUTLINE_OFFSETS do
		layer(offset, TEXT_STROKE)
	end
	layer(Vector2.zero, Color3.new(1, 1, 1))
	holder.Parent = parent
	return holder
end

-- Bouton d'achat : [Robux] prix, centre. La largeur du texte suit le nombre de chiffres.
local function priceButton(parent: Instance, price: number, position: UDim2, size: UDim2, group: string?): TextButton
	local button = packButton(parent, "Buy", BUY_COLORS, position, size)
	button:SetAttribute("Price", price)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 4
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = content
	local robux = robuxIcon(content, UDim2.fromScale(0.66, 0.66), 4)
	robux.LayoutOrder = 1
	local text = tostring(price)
	local priceLabel = label(content, text, group or "Price", UDim2.new(), UDim2.fromScale(0.42 * #text, 0.66))
	priceLabel.SizeConstraint = Enum.SizeConstraint.RelativeYY
	priceLabel.AnchorPoint = Vector2.zero
	priceLabel.LayoutOrder = 2
	content.Parent = button
	return button
end

local function giftButton(parent: Instance, position: UDim2, size: UDim2): TextButton
	local button = packButton(parent, "Gift", GIFT_COLORS, position, size)
	local img = image(button, "Gift", UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.8, 0.8))
	img.ZIndex = 4
	return button
end

local function onBuy(kind: string, key: string, id: number, isGift: boolean)
	if id == 0 then
		warn(`[Shop] {kind} "{key}" pas encore cree sur Roblox (id = 0). Cadeau : {isGift}`)
		return
	end
	-- A brancher : MarketplaceService:PromptProductPurchase / PromptGamePassPurchase,
	-- et pour un cadeau, choix du joueur puis produit "Gift" (voir docs/game-design.md).
end

local function grid(name: string, cellWidth: number, aspect: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(0.96, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = nextOrder()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(cellWidth, 0, 1, 0)
	layout.CellPadding = UDim2.new(0.02, 0, 0, 14)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspect
	ratio.Parent = layout
	layout.Parent = frame
	frame.Parent = scroll
	return frame
end

local function sectionTitle(text: string)
	local holder = Instance.new("Frame")
	holder.Name = "Title_" .. text
	holder.BackgroundTransparency = 1
	-- Hauteur = part de la largeur de la boutique (mise a jour dans updateTitleHeights),
	-- pour garder les memes proportions sur PC et telephone.
	holder.Size = UDim2.new(0.96, 0, 0, 44)
	table.insert(sectionTitles, holder)
	holder.LayoutOrder = nextOrder()
	label(holder, `-{text}-`, "Section", UDim2.fromScale(0.5, 0), UDim2.fromScale(0.6, 1))
	holder.Parent = scroll
end

-- Etiquette inclinee ("BEST", "OP") : la carte passe au-dessus de ses voisines.
local TAG_RED = Color3.fromRGB(230, 25, 40)

-- Etiquette simple : rectangle rouge incline avec un petit contour noir, texte blanc. "BEST", "OP", "BEST VALUE", "-30%". La carte passe au-dessus de ses voisines.
local function cornerTag(frame: Frame, text: string, _colorName: string?, left: boolean?)
	frame.ZIndex = 3
	local band = Instance.new("Frame")
	band.Name = "Tag"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = if left then UDim2.fromScale(0.17, 0.01) else UDim2.fromScale(0.8, 0.01)
	band.Size = if left then UDim2.fromScale(0.34, 0.13) else UDim2.fromScale(0.5, 0.13)
	band.Rotation = if left then -8 else 8
	band.BackgroundColor3 = TAG_RED
	band.BorderSizePixel = 0
	band.ZIndex = 6
	addStroke(band, 2, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local tagText = label(band, text, "Tag", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.9, 0.84))
	tagText.ZIndex = 7
	band.Parent = frame
end

-- Ancien prix barre au-dessus du bouton (seulement pour une vraie promotion, voir Config/Shop).
local function oldPriceLabel(frame: Frame, oldPrice: number, buy: GuiObject)
	-- Pose sur le coin haut-droit du bouton, comme dans le pack UI.
	local text = label(buy, `<s>{oldPrice}</s>`, "OldPrice", UDim2.fromScale(0.85, -0.5), UDim2.fromScale(0.5, 0.6))
	text.Rotation = -8
	text.ZIndex = 8
	text.RichText = true
	text.TextColor3 = Color3.fromRGB(255, 70, 70)
	-- Etiquette "-30%" calculee depuis l'ancien prix.
	local price = buy:GetAttribute("Price")
	if typeof(price) == "number" and oldPrice > price then
		local percent = math.floor((1 - price / oldPrice) * 100 + 0.5)
		cornerTag(frame, `-{percent}%`, "Red", true)
	end
end

-- Sections ----------------------------------------------------------------------------------------

local function buildBoosts()
	sectionTitle("POTIONS")
	local row = grid("Potions", 0.315, 0.95)
	for _, boost in Shop.Boosts do
		local frame = card(row, boost.key, boost.color, boost.color2)
		label(frame, boost.title, "PotionTitle", UDim2.fromScale(0.5, 0.04), UDim2.fromScale(0.9, 0.14))
		for index, option in boost.options do
			local x = if index == 1 then 0.27 else 0.73
			image(frame, boost.icon, UDim2.fromScale(x, 0.19), UDim2.fromScale(0.4, 0.36))
			label(frame, `{option.minutes} min`, "Minutes", UDim2.fromScale(x, 0.56), UDim2.fromScale(0.44, 0.12))
			local buy = priceButton(frame, option.price, UDim2.fromScale(x, 0.72), UDim2.fromScale(0.41, 0.19))
			buy.Activated:Connect(function()
				onBuy("Boost", `{boost.key}_{option.minutes}`, option.productId, false)
			end)
		end
	end
end

local function buildPasses()
	sectionTitle("PASSES")
	local row = grid("Passes", 0.315, 0.92)
	for _, pass in Shop.Passes do
		local frame = card(row, pass.key, pass.color, pass.color2)
		label(frame, pass.title, "PassTitle", UDim2.fromScale(0.5, 0.035), UDim2.fromScale(0.94, 0.15))
		-- Grosse icone, en partie derriere les deux lignes de texte (moins d'espace perdu).
		local icon = image(frame, pass.icon, UDim2.fromScale(0.5, 0.15), UDim2.fromScale(0.7, 0.5))
		icon.ZIndex = 2
		for index, line in pass.lines do
			label(frame, line, "PassLine", UDim2.fromScale(0.5, 0.49 + (index - 1) * 0.1), UDim2.fromScale(0.94, 0.1))
		end
		if pass.tag then
			cornerTag(frame, pass.tag, if pass.tag == "OP" then "Purple" else "Red")
		end
		local gift = giftButton(frame, UDim2.fromScale(0.19, 0.73), UDim2.fromScale(0.24, 0.21))
		gift.Activated:Connect(function()
			onBuy("Pass", pass.key, pass.passId, true)
		end)
		local buy = priceButton(frame, pass.price, UDim2.fromScale(0.63, 0.73), UDim2.fromScale(0.56, 0.21), "PassPrice")
		buy.Activated:Connect(function()
			onBuy("Pass", pass.key, pass.passId, false)
		end)
		if pass.oldPrice then
			oldPriceLabel(frame, pass.oldPrice, buy)
		end
	end
end

local function formatDuration(minutes: number): string
	if minutes >= 60 then
		local hours = minutes // 60
		return `{hours} hour{if hours > 1 then "s" else ""}`
	end
	return `{minutes} minutes`
end

local function buildCashPacks()
	sectionTitle("CASH PACKS")
	local row = grid("CashPacks", 0.475, 1.3)
	for _, pack in Shop.CashPacks do
		local frame = card(row, pack.key, CASH_COLORS[1], CASH_COLORS[2])
		label(frame, pack.title, "PackTitle", UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.9, 0.12))
		label(frame, `{formatDuration(pack.minutes)} of profit`, "PackLine", UDim2.fromScale(0.36, 0.22), UDim2.fromScale(0.62, 0.1))
		label(frame, "instantly", "PackLine", UDim2.fromScale(0.36, 0.32), UDim2.fromScale(0.62, 0.1))
		local amount = label(frame, "", "PackAmount", UDim2.fromScale(0.36, 0.44), UDim2.fromScale(0.62, 0.12))
		amount.Name = "Amount"
		image(frame, "Cash", UDim2.fromScale(0.8, 0.2), UDim2.fromScale(0.34, 0.38))
		local buy = priceButton(frame, pack.price, UDim2.fromScale(0.5, 0.64), UDim2.fromScale(0.6, 0.27), "PackPrice")
		buy.Activated:Connect(function()
			onBuy("CashPack", pack.key, pack.productId, false)
		end)
		if pack.oldPrice then
			oldPriceLabel(frame, pack.oldPrice, buy)
		end
		if pack.bestValue then
			cornerTag(frame, "BEST VALUE", "Red")
		end
	end
end

-- Egalise la taille du texte dans chaque groupe (la plus petite taille qui tient partout).
local function fitTextGroups()
	for _, labels in textGroups do
		for _, textLabel in labels do
			textLabel.TextScaled = true
			local limit = textLabel:FindFirstChildOfClass("UITextSizeConstraint")
			if limit then
				limit:Destroy() -- mesurer sans l'ancien plafond
			end
		end
	end
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	-- TextBounds inclut le zoom du menu (UIScale) ; TextSize est avant zoom : on divise.
	local uiScale = shopMenu:FindFirstChildOfClass("UIScale")
	local zoom = if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
	for group, labels in textGroups do
		if CAP_GROUPS[group] then
			-- Groupe "plafonne" : taille commune = la mediane ; seuls les textes trop longs retrecissent.
			local sizes = {}
			for _, textLabel in labels do
				if textLabel.TextBounds.Y > 0 then
					table.insert(sizes, textLabel.TextBounds.Y)
				end
			end
			table.sort(sizes)
			local median = sizes[math.max(1, math.ceil(#sizes / 2))]
			if median then
				for _, textLabel in labels do
					local limit = textLabel:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
					limit.MaxTextSize = math.floor(median / zoom)
					limit.Parent = textLabel
				end
			end
			continue
		end
		local smallest = math.huge
		for _, textLabel in labels do
			local height = textLabel.TextBounds.Y
			if height > 0 then
				smallest = math.min(smallest, height)
			end
		end
		if smallest < math.huge then
			for _, textLabel in labels do
				textLabel.TextScaled = false
				textLabel.TextSize = math.floor(smallest / zoom)
			end
		end
	end
end

local function refitIfNeeded()
	local camera = workspace.CurrentCamera
	if not camera or not shopMenu.Visible then
		return
	end
	local viewport = camera.ViewportSize
	if lastFitSize == viewport then
		return
	end
	lastFitSize = viewport
	task.delay(OPEN_ANIMATION_TIME, fitTextGroups)
end

-- Cycle de vie ----------------------------------------------------------------------------------

function ShopController:Start()
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	Shop = require(config:WaitForChild("Shop")) :: any
	Icons = require(config:WaitForChild("Icons")) :: any
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local shopGUI = playerGui:WaitForChild("ShopGUI")
	shopMenu = shopGUI:WaitForChild("MenuFrames"):WaitForChild("Shop") :: GuiObject
	scroll = shopMenu:WaitForChild("Shop"):WaitForChild("ScrollingFrame") :: ScrollingFrame

	local camera = workspace.CurrentCamera
	local viewportHeight = if camera then camera.ViewportSize.Y else 720
	smallScreen = viewportHeight < SMALL_SCREEN_HEIGHT
	strokeScale = math.clamp(viewportHeight / 700, 0.55, 1)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.Parent = scroll

	buildBoosts()
	buildPasses()
	buildCashPacks()

	local function updateTitleHeights()
		local height = math.floor(scroll.AbsoluteSize.X * SECTION_TITLE_RATIO)
		if height > 0 then
			for _, holder in sectionTitles do
				holder.Size = UDim2.new(0.96, 0, 0, height)
			end
		end
	end
	updateTitleHeights()
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTitleHeights)

	shopMenu:GetPropertyChangedSignal("Visible"):Connect(refitIfNeeded)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			lastFitSize = nil
			refitIfNeeded()
		end)
	end
end

return ShopController
