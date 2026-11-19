--!strict
-- Offres limitees a droite de l'ecran (Config/Shop.LimitedOffers).
-- Rotation commune a tous les joueurs, calee sur l'heure du serveur : visibles 10 min, cachees
-- 2 min, puis de nouvelles offres. Chaque offre : nom, icone sur des rayons qui tournent, prix,
-- minuteur rouge ; etiquette "-X%" si l'offre est en reduction.
-- Clic : fenetre "Limited Offer!" (reduction, temps restant, gros bouton d'achat) ; le bouton
-- d'achat ouvre la confirmation de paiement Roblox (quand le produit existe).
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local OffersController = {}

local GLOW_IMAGE = "rbxassetid://100034870209210" -- rayons lumineux du pack UI
local GLOW_SPEED = 40 -- degres par seconde
local TIMER_RED = Color3.fromRGB(255, 70, 70)
local TAG_RED = Color3.fromRGB(230, 25, 40)
local HOME = UDim2.fromScale(0.995, 0.5)
local PHONE_HOME = UDim2.fromScale(0.995, 0.37)
local HIDDEN_X = 1.2
local POPUP_MENU = "LimitedOffer"

type Offer = {
	key: string,
	title: string,
	details: string,
	icon: string,
	price: number,
	oldPrice: number?,
	kind: string,
	productId: number,
}

local player = Players.LocalPlayer
local config: any
local icons: { [string]: string }
local hud: ScreenGui
local column: Frame
local home = HOME
local glows: { ImageLabel } = {}
local timerLabels: { TextLabel } = {}
local currentCycle = -1
local offersVisible = false
local popup: any = {}
local popupOffer: Offer? = nil

local function menuController(): any
	return require(script.Parent:WaitForChild("MenuController")) :: any
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local function discountPercent(offer: Offer): number?
	if offer.oldPrice and offer.oldPrice > offer.price then
		return math.floor((1 - offer.price / offer.oldPrice) * 100 + 0.5)
	end
	return nil
end

-- Etat de la rotation : numero du cycle, offres visibles ?, secondes restantes.
local function cycleState(): (number, boolean, number)
	local offers = config.LimitedOffers
	local period = offers.OnSeconds + offers.OffSeconds
	local now = workspace:GetServerTimeNow()
	local cycle = math.floor(now / period)
	local phase = now - cycle * period
	if phase < offers.OnSeconds then
		return cycle, true, offers.OnSeconds - phase
	end
	return cycle, false, period - phase
end

local function offersForCycle(cycle: number): { Offer }
	local pool = config.LimitedOffers.Pool
	local list = {}
	for slot = 0, math.min(config.LimitedOffers.Slots, #pool) - 1 do
		table.insert(list, pool[((cycle * config.LimitedOffers.Slots + slot) % #pool) + 1])
	end
	return list
end

local function smallTag(parent: GuiObject, text: string)
	local tag = Instance.new("Frame")
	tag.Name = "Discount"
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	-- En haut a droite de l'icone, un peu sous le nom pour ne pas le cacher.
	tag.Position = UDim2.fromScale(0.66, 0.32)
	tag.Size = UDim2.fromScale(0.6, 0.14)
	tag.Rotation = 10
	tag.BackgroundColor3 = TAG_RED
	tag.ZIndex = 6
	PackStyle.stroke(tag, 2, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local label = PackStyle.label(tag, text, UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.9, 0.88), 40)
	label.ZIndex = 7
	tag.Parent = parent
end

-- Fenetre "Limited Offer!" ---------------------------------------------------------------------

local function buildPopup()
	local frame = menuController().CloneMenuTemplate("OfflineEarnings", POPUP_MENU)
	if not frame then
		warn("[Offers] Modele de menu introuvable")
		return
	end
	local subHeader = frame:FindFirstChild("Header") and frame.Header:FindFirstChild("SubHeader")
	local title = subHeader and subHeader:FindFirstChild("TextLabel", true)
	if title and title:IsA("TextLabel") then
		title.Text = "Limited Offer!"
	end
	local body = frame:WaitForChild("Shop") :: Frame

	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.24, 0.48)
	glow.Size = UDim2.fromScale(0.95, 0.95)
	glow.SizeConstraint = Enum.SizeConstraint.RelativeYY
	glow.Image = GLOW_IMAGE
	glow.ImageTransparency = 0.2
	glow.ZIndex = 2
	glow.Parent = body
	table.insert(glows, glow)

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.24, 0.48)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 3
	icon.Parent = body
	TweenService:Create(
		icon,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromScale(0.24, 0.44), Rotation = 5 }
	):Play()

	local name = PackStyle.label(body, "", UDim2.fromScale(0.68, 0.05), UDim2.fromScale(0.58, 0.17), 70)
	local details = PackStyle.label(body, "", UDim2.fromScale(0.68, 0.24), UDim2.fromScale(0.58, 0.09), 36)

	-- Ancien prix barre + "-X%" (seulement si reduction).
	local oldPrice = PackStyle.label(body, "", UDim2.fromScale(0.6, 0.36), UDim2.fromScale(0.26, 0.11), 44)
	oldPrice.RichText = true
	oldPrice.TextColor3 = TIMER_RED
	local discount = Instance.new("Frame")
	discount.AnchorPoint = Vector2.new(0.5, 0)
	discount.Position = UDim2.fromScale(0.82, 0.355)
	discount.Size = UDim2.fromScale(0.2, 0.12)
	discount.Rotation = 6
	discount.BackgroundColor3 = TAG_RED
	discount.ZIndex = 5
	PackStyle.stroke(discount, 2, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local discountText = PackStyle.label(discount, "", UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.9, 0.88), 40)
	discountText.ZIndex = 6
	discount.Parent = body

	local timer = PackStyle.label(body, "", UDim2.fromScale(0.68, 0.5), UDim2.fromScale(0.58, 0.1), 40)
	timer.TextColor3 = TIMER_RED

	local buy = PackStyle.button(body, "Buy", PackStyle.GREEN, UDim2.fromScale(0.68, 0.65), UDim2.fromScale(0.42, 0.24))
	-- Contour dore qui pulse : attire l'oeil sur le bouton d'achat.
	local glowStroke = PackStyle.stroke(buy, 4, Color3.fromRGB(255, 220, 60), Enum.ApplyStrokeMode.Border)
	TweenService:Create(
		glowStroke,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.8 }
	):Play()

	buy.Activated:Connect(function()
		local offer = popupOffer
		if not offer then
			return
		end
		if offer.productId == 0 then
			warn(`[Offers] Produit "{offer.key}" pas encore cree sur Roblox (id = 0).`)
			return
		end
		-- Fenetre de confirmation de Roblox (le serveur donnera l'article a la reception du paiement).
		MarketplaceService:PromptProductPurchase(player, offer.productId)
	end)

	popup = {
		frame = frame,
		icon = icon,
		name = name,
		details = details,
		oldPrice = oldPrice,
		discount = discount,
		discountText = discountText,
		timer = timer,
		buy = buy,
		priceRow = nil :: Frame?,
	}
	menuController().RegisterMenu(frame)
end

local function openPopup(offer: Offer)
	if not popup.frame then
		return
	end
	popupOffer = offer
	popup.icon.Image = icons[offer.icon] or ""
	popup.name.Text = offer.title
	popup.details.Text = offer.details
	local percent = discountPercent(offer)
	popup.oldPrice.Visible = percent ~= nil
	popup.discount.Visible = percent ~= nil
	if percent and offer.oldPrice then
		popup.oldPrice.Text = `<s>{offer.oldPrice}</s>`
		popup.discountText.Text = `-{percent}%`
	end
	if popup.priceRow then
		popup.priceRow:Destroy()
	end
	popup.priceRow = PackStyle.priceRow(popup.buy, icons.Robux, offer.price, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(1, 0.76))
	menuController().Open(POPUP_MENU)
end

-- Colonne des offres ---------------------------------------------------------------------------

local function buildOffer(offer: Offer, order: number)
	local button = Instance.new("ImageButton")
	button.Name = "Offer_" .. offer.key
	button.BackgroundTransparency = 1
	button.Image = ""
	button.LayoutOrder = order
	button.Size = UDim2.fromScale(1, 1)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.8
	ratio.Parent = button

	PackStyle.label(button, offer.title, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.17), 30)

	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.44)
	glow.Size = UDim2.fromScale(1.15, 1.15)
	glow.SizeConstraint = Enum.SizeConstraint.RelativeXX
	glow.Image = GLOW_IMAGE
	glow.ImageTransparency = 0.25
	glow.ZIndex = 1
	glow.Parent = button
	table.insert(glows, glow)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.44)
	icon.Size = UDim2.fromScale(0.74, 0.74)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = icons[offer.icon] or ""
	icon.ZIndex = 2
	icon.Parent = button
	task.delay(order * 0.25, function()
		TweenService:Create(
			icon,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromScale(0.5, 0.4), Rotation = 6 }
		):Play()
	end)

	local percent = discountPercent(offer)
	if percent then
		smallTag(button, `-{percent}%`)
	end

	-- Pas de prix ici : il s'affiche dans la fenetre d'offre. Seulement le temps restant.
	local timer = PackStyle.label(button, "", UDim2.fromScale(0.5, 0.76), UDim2.fromScale(1, 0.15), 28)
	timer.Name = "Timer"
	timer.TextColor3 = TIMER_RED
	table.insert(timerLabels, timer)

	button.Activated:Connect(function()
		openPopup(offer)
	end)
	button.Parent = column
end

local function rebuildColumn(cycle: number)
	for _, child in column:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	timerLabels = {}
	-- Garder les rayons de la fenetre d'offre, retirer ceux des anciennes offres.
	local kept = {}
	for _, glow in glows do
		if glow.Parent then
			table.insert(kept, glow)
		end
	end
	glows = kept
	for index, offer in offersForCycle(cycle) do
		buildOffer(offer, index)
	end
end

local function slideColumn()
	local menuOpen = (hud:GetAttribute("ActiveMenu") or "") ~= ""
	local show = offersVisible and not menuOpen
	TweenService:Create(
		column,
		TweenInfo.new(if show then 0.27 else 0.21, if show then Enum.EasingStyle.Back else Enum.EasingStyle.Cubic),
		{ Position = if show then home else UDim2.fromScale(HIDDEN_X, home.Y.Scale) }
	):Play()
end

-- Chaque seconde : minuteurs, changement de cycle, apparition / disparition.
local function tick()
	local cycle, visible, remaining = cycleState()
	if cycle ~= currentCycle then
		currentCycle = cycle
		rebuildColumn(cycle)
	end
	if visible ~= offersVisible then
		offersVisible = visible
		slideColumn()
		if not visible and popupOffer and menuController().GetActiveMenu() == POPUP_MENU then
			menuController().Close() -- l'offre est terminee
		end
	end
	local text = formatTime(remaining)
	for _, label in timerLabels do
		label.Text = text
	end
	if popup.timer then
		popup.timer.Text = if visible then `Ends in {text}` else "Offer ended"
	end
end

function OffersController:Start()
	local shared = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	config = require(shared:WaitForChild("Shop")) :: any
	icons = require(shared:WaitForChild("Icons")) :: any
	hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD") :: ScreenGui
	player:WaitForChild("PlayerGui"):WaitForChild("ShopGUI")

	column = Instance.new("Frame")
	column.Name = "SideOffers"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(1, 0.5)
	local camera = workspace.CurrentCamera
	local phone = camera ~= nil and camera.ViewportSize.Y < 450
	-- Telephone : colonne remontee pour laisser libre le bouton de saut (bas a droite).
	home = if phone then PHONE_HOME else HOME
	column.Size = if phone then UDim2.fromScale(0.085, 0.62) else UDim2.fromScale(0.075, 0.66)
	column.Position = UDim2.fromScale(HIDDEN_X, home.Y.Scale)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = column
	column.Parent = hud

	-- Attendre que MenuController ait enregistre les menus du pack (au lieu d'un delai fixe)
	if menuController().WaitUntilReady(15) then
		buildPopup()
	else
		warn("[OffersController] Menus pas prets apres 15 s : fenetre des offres indisponible")
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, glow in glows do
			glow.Rotation = (glow.Rotation + GLOW_SPEED * dt) % 360
		end
	end)
	hud:GetAttributeChangedSignal("ActiveMenu"):Connect(slideColumn)

	while true do
		local ok, err = pcall(tick)
		if not ok then
			warn(`[OffersController] tick : {err}`)
		end
		task.wait(1)
	end
end

return OffersController
