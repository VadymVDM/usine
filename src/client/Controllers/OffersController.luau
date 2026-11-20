--!strict
-- Offre limitee a droite de l'ecran (Config/Shop.LimitedOffers).
-- UNE offre a la fois, calendrier propre au joueur (depuis la fin du chargement) : rien pendant
-- FirstDelaySeconds (15 s), puis l'offre "pop" au milieu de l'ecran, file vite a droite et
-- reste OnSeconds (3 min), disparait (ou tout de suite si elle est achetee),
-- et OffSeconds (30 s) plus tard la suivante arrive. 1re offre = FirstOffer, puis Pool melange
-- (voir pickFromPool : pas de repetition, pas d'offre trop tot ni de boost deja actif).
-- A droite : nom, icone sur des rayons qui tournent (+ gros "x2" si `badge` ; offre d'argent : le
-- vrai montant "+$2.5K" en vert, jamais des "$$$"), minuteur rouge.
-- Pas de reduction ni de prix.
-- Clic : fenetre "Limited Offer!" : le contenu en IMAGES (une tuile par recompense : icone, "x2",
-- "15 MIN" ou "+$1.2K"), temps restant, gros bouton d'achat avec le prix ; le bouton
-- d'achat envoie ShopBuy au serveur (RobuxShopService : fenetre de paiement Roblox, ou "coming soon"
-- si le produit n'existe pas encore). Montants d'argent : attributs "Cash_<cle>" du serveur.
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("Remotes"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("NumberFormat"))

local OffersController = {}

local GLOW_IMAGE = "rbxassetid://100034870209210" -- rayons lumineux du pack UI
local GLOW_SPEED = 40 -- degres par seconde
local TIMER_RED = Color3.fromRGB(255, 70, 70)
local MULT_YELLOW = Color3.fromRGB(255, 225, 40)
-- Icone de chaque recompense (cles de Config/Icons). Argent = billets, chance = trefle,
-- vitesse des clients = chaussure : comprehensible sans lire.
local STAT_ICONS = { Money = "Cash", Luck = "Clover", Speed = "Shoe" }
local KIND_ICONS = { Cash = "Cash" }
local HOME = UDim2.fromScale(1 - PackStyle.SIDE_MARGIN, 0.5)
local PHONE_HOME = UDim2.fromScale(1 - PackStyle.SIDE_MARGIN, 0.37)
local HIDDEN_X = 1.2
local POPUP_MENU = "LimitedOffer"

type Reward = {
	kind: string, -- "Boost" | "Cash"
	stat: string?, -- Boost : "Money" | "Luck" | "Speed"
	mult: number?,
	minutes: number,
	floorShare: number?, -- Cash : part du prix du prochain etage du joueur (montant adapte a l'etage)
	minAmount: number?, -- Cash : montant minimum
}

type Offer = {
	key: string,
	title: string,
	icon: string,
	badge: string?,
	price: number,
	rewards: { Reward },
	productId: number,
	oneTime: boolean?, -- une seule fois (le serveur pose "Bought_<cle>" une fois achetee)
}

local player = Players.LocalPlayer
local config: any
local icons: { [string]: string }
local hud: ScreenGui
local column: Frame
local home = HOME
local normalSize = UDim2.fromScale(PackStyle.SIDE_BUTTON_WIDTH, 0.66)
-- Entree d'une nouvelle offre : en grand au milieu, puis a sa place a droite.
local INTRO_SCALE = 2.4 -- taille au milieu (x la taille normale)
local INTRO_HOLD = 0.7 -- secondes au milieu (2026-11-21 : 1.8 -> 0.7, restait trop longtemps)
local INTRO_POP = 0.25 -- duree du "pop" au milieu
local INTRO_MOVE = 0.35 -- duree du trajet vers la droite
local introPlaying = false
local pendingIntro = false -- nouvelle offre arrivee pendant qu'un menu etait ouvert
local glows: { ImageLabel } = {}
local timerLabels: { TextLabel } = {}
-- Montant affiche sur l'offre d'argent a droite (mis a jour chaque seconde : gains et etage changent).
local cashBadge: { label: TextLabel, reward: Reward }? = nil
local currentCycle = -2
local startClock = 0
local boughtCycle = -2 -- cycle dont l'offre vient d'etre achetee : elle se retire tout de suite
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

-- Etat du calendrier : numero de l'offre (-1 = pas encore), visible ?, secondes restantes.
local function cycleState(): (number, boolean, number)
	local offers = config.LimitedOffers
	local elapsed = os.clock() - startClock - offers.FirstDelaySeconds
	if elapsed < 0 then
		return -1, false, -elapsed
	end
	local period = offers.OnSeconds + offers.OffSeconds
	local cycle = math.floor(elapsed / period)
	local phase = elapsed - cycle * period
	if phase < offers.OnSeconds then
		return cycle, true, offers.OnSeconds - phase
	end
	return cycle, false, period - phase
end

-- Choix des offres (2026-11-21) : le Pool est melange a chaque session et parcouru sans repetition
-- (re-melange quand tout a ete vu, jamais deux fois la meme offre de suite). On saute une offre :
-- - trop tot pour elle (`minCycle` : Mega Cash a 99 R$ pas dans les premieres minutes) ;
-- - inutile maintenant : tous ses boosts tournent deja avec un multiplicateur au moins aussi fort.
local bag: { Offer } = {}
local lastPicked: Offer? = nil
local chosen: { [number]: Offer | false } = {} -- cycle -> offre choisie (false = aucune)

local function refillBag()
	bag = table.clone(config.LimitedOffers.Pool)
	for i = #bag, 2, -1 do
		local j = math.random(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end
	if #bag > 1 and bag[#bag] == lastPicked then
		bag[1], bag[#bag] = bag[#bag], bag[1] -- on pioche par la fin : pas deux fois la meme de suite
	end
end

local function isUseless(offer: Offer): boolean
	local boosts = 0
	for _, reward in offer.rewards do
		if reward.kind ~= "Boost" then
			return false -- de l'argent est toujours utile
		end
		boosts += 1
		local active = player:GetAttribute("Boost" .. (reward.stat or ""))
		if type(active) ~= "number" or active < (reward.mult or 0) then
			return false
		end
	end
	return boosts > 0
end

local function pickFromPool(cycle: number): Offer?
	local pool = config.LimitedOffers.Pool
	-- Deux tours du sac au plus : si tout est ecarte (trop tot / inutile), on prend la premiere
	-- offre permise par minCycle, sinon rien.
	local fallback: Offer? = nil
	for _ = 1, #pool * 2 do
		if #bag == 0 then
			refillBag()
		end
		local offer = table.remove(bag) :: Offer
		local early = cycle < ((offer :: any).minCycle or 0)
		if offer.oneTime and player:GetAttribute("Bought_" .. offer.key) == true then
			continue -- offre unique deja achetee : plus jamais proposee
		end
		if not early and not isUseless(offer) then
			return offer
		end
		if not early and fallback == nil then
			fallback = offer
		end
	end
	return fallback
end

local function offerForCycle(cycle: number): Offer?
	local offers = config.LimitedOffers
	if cycle < 0 then
		return nil
	end
	local cached = chosen[cycle]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local offer: Offer?
	local first = offers.FirstOffer
	if cycle == 0 and first and not (first.oneTime and player:GetAttribute("Bought_" .. first.key) == true) then
		offer = first -- Starter Pack deja achete (attribut "Bought_<cle>" du serveur) : on passe au Pool
	elseif #offers.Pool > 0 then
		offer = pickFromPool(cycle)
	end
	chosen[cycle] = offer or false
	if offer then
		lastPicked = offer
	end
	return offer
end

-- Montant d'une recompense d'argent : calcule par le SERVEUR (RobuxShopService : gains recents x
-- minutes, plafonne a floorShare x prix du prochain etage, minimum minAmount), attribut joueur
-- "Cash_<cle de l'offre>". Le client n'affiche que ; le recu donne le montant du serveur.
local rewardOffer: { [any]: string } = {} -- table de recompense (Config/Shop) -> cle de son offre
local function cashAmount(reward: Reward): number
	local key = rewardOffer[reward]
	local value = if key then player:GetAttribute("Cash_" .. key) else nil
	return if type(value) == "number" then value else 0
end

local function durationText(minutes: number): string
	if minutes >= 60 and minutes % 60 == 0 then
		return `{minutes // 60} HOUR`
	end
	return `{minutes} MIN`
end

-- Gros texte jaune penche pose sur une icone ("x2", "$$$").
local function badgeLabel(parent: GuiObject, text: string, position: UDim2, size: UDim2, maxSize: number): TextLabel
	local label = PackStyle.label(parent, text, position, size, maxSize)
	label.Name = "Badge"
	label.Rotation = -10
	label.TextColor3 = MULT_YELLOW
	label.ZIndex = 8
	return label
end

-- Une tuile de recompense : icone, "x2" en gros, et dessous la duree ou le montant.
local function rewardTile(parent: Instance, reward: Reward, order: number)
	local tile = Instance.new("Frame")
	tile.Name = "Reward" .. order
	tile.LayoutOrder = order
	tile.Size = UDim2.fromScale(1, 1)
	tile.BackgroundColor3 = Color3.new(0, 0, 0)
	tile.BackgroundTransparency = 0.55
	tile.ZIndex = 5
	PackStyle.stroke(tile, 2, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.85
	ratio.Parent = tile

	local iconKey = if reward.kind == "Boost" then STAT_ICONS[reward.stat or ""] else KIND_ICONS[reward.kind]
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.03)
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = icons[iconKey or ""] or ""
	icon.ZIndex = 6
	icon.Parent = tile

	local bottom: string
	local bottomColor = Color3.new(1, 1, 1)
	if reward.kind == "Boost" and reward.mult then
		badgeLabel(tile, `x{reward.mult}`, UDim2.fromScale(0.7, 0.3), UDim2.fromScale(0.75, 0.36), 70)
		bottom = durationText(reward.minutes)
	elseif reward.kind == "Cash" then
		-- Le vrai montant, jamais "5 min" (incomprehensible), adapte a l'etage du joueur.
		local amount = cashAmount(reward)
		if amount > 0 then
			bottom = "+" .. NumberFormat.Money(amount)
			bottomColor = PackStyle.MONEY_GREEN
		else
			bottom = "+" .. durationText(reward.minutes)
		end
	else
		bottom = durationText(reward.minutes)
	end
	local text = PackStyle.label(tile, bottom, UDim2.fromScale(0.5, 0.69), UDim2.fromScale(0.96, 0.29), 48)
	text.TextColor3 = bottomColor
	text.ZIndex = 7
	tile.Parent = parent
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

	local name = PackStyle.label(body, "", UDim2.fromScale(0.68, 0.03), UDim2.fromScale(0.58, 0.15), 70)
	-- Contenu de l'offre en tuiles (rempli a chaque ouverture : le montant d'argent change).
	local rewards = Instance.new("Frame")
	rewards.Name = "Rewards"
	rewards.BackgroundTransparency = 1
	rewards.AnchorPoint = Vector2.new(0.5, 0)
	rewards.Position = UDim2.fromScale(0.68, 0.19)
	rewards.Size = UDim2.fromScale(0.6, 0.34)
	rewards.Parent = body
	local rewardsLayout = Instance.new("UIListLayout")
	rewardsLayout.FillDirection = Enum.FillDirection.Horizontal
	rewardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rewardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rewardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rewardsLayout.Padding = UDim.new(0.04, 0)
	rewardsLayout.Parent = rewards

	local timer = PackStyle.label(body, "", UDim2.fromScale(0.68, 0.545), UDim2.fromScale(0.58, 0.09), 40)
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
		-- Le serveur (RobuxShopService) note le montant montre et ouvre la fenetre d'achat Roblox
		-- (effet d'ecran : Feedback "PurchasePrompt") ; produit pas cree : message "coming soon".
		local shopBuy = Remotes.WaitClientEvent("ShopBuy")
		if shopBuy then
			shopBuy:FireServer("Offer", offer.key)
		end
	end)

	popup = {
		frame = frame,
		icon = icon,
		name = name,
		rewards = rewards,
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
	for _, child in popup.rewards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, reward in offer.rewards do
		rewardTile(popup.rewards, reward, index)
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

	if offer.badge then
		badgeLabel(button, offer.badge, UDim2.fromScale(0.72, 0.42), UDim2.fromScale(0.62, 0.22), 48)
	else
		-- Offre d'argent seule (Mega Cash) : le vrai montant sur l'icone.
		local cash: Reward? = nil
		for _, reward in offer.rewards do
			if reward.kind == "Cash" then
				cash = reward
				break
			end
		end
		if cash and #offer.rewards == 1 then
			local label = badgeLabel(button, "", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1.05, 0.2), 44)
			label.Rotation = -6
			label.TextColor3 = PackStyle.MONEY_GREEN
			label.Text = "+" .. NumberFormat.Money(cashAmount(cash))
			cashBadge = { label = label, reward = cash }
		end
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
	cashBadge = nil
	-- Garder les rayons de la fenetre d'offre, retirer ceux des anciennes offres.
	local kept = {}
	for _, glow in glows do
		if glow.Parent then
			table.insert(kept, glow)
		end
	end
	glows = kept
	local offer = offerForCycle(cycle)
	if offer then
		buildOffer(offer, 1)
	end
end

local playIntro: () -> () -- defini plus bas (s'appellent l'un l'autre)

local function slideColumn()
	if introPlaying then
		return -- playIntro remet la colonne a sa place a la fin
	end
	local menuOpen = (hud:GetAttribute("ActiveMenu") or "") ~= ""
	local show = offersVisible and not menuOpen
	if show and pendingIntro then
		pendingIntro = false
		playIntro()
		return
	end
	TweenService:Create(
		column,
		TweenInfo.new(if show then 0.27 else 0.21, if show then Enum.EasingStyle.Back else Enum.EasingStyle.Cubic),
		{ Position = if show then home else UDim2.fromScale(HIDDEN_X, home.Y.Scale) }
	):Play()
end

-- Nouvelle offre : elle "pop" en grand au milieu de l'ecran, reste INTRO_HOLD secondes,
-- puis file a sa place a droite (taille normale).
function playIntro()
	introPlaying = true
	local bigSize = UDim2.fromScale(normalSize.X.Scale * INTRO_SCALE, normalSize.Y.Scale)
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.fromScale(0.5, 0.5)
	column.Size = UDim2.fromScale(normalSize.X.Scale * 0.3, normalSize.Y.Scale)
	TweenService:Create(column, TweenInfo.new(INTRO_POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = bigSize }):Play()
	task.delay(INTRO_HOLD, function()
		local move = TweenService:Create(
			column,
			TweenInfo.new(INTRO_MOVE, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ AnchorPoint = Vector2.new(1, 0.5), Position = home, Size = normalSize }
		)
		move.Completed:Once(function()
			introPlaying = false
			slideColumn() -- un menu a pu s'ouvrir, ou l'offre finir, pendant l'animation
		end)
		move:Play()
	end)
end

-- Chaque seconde : minuteurs, changement de cycle, apparition / disparition.
local function tick()
	local cycle, visible, remaining = cycleState()
	if cycle == boughtCycle then
		visible = false -- deja achetee : on ne la montre plus jusqu'a la suivante
	end
	if cycle ~= currentCycle then
		currentCycle = cycle
		rebuildColumn(cycle)
	end
	if visible ~= offersVisible then
		offersVisible = visible
		pendingIntro = visible -- une offre qui arrive passe d'abord par le milieu de l'ecran
		slideColumn()
		if not visible and popupOffer and menuController().GetActiveMenu() == POPUP_MENU then
			menuController().Close() -- l'offre est terminee
		end
	end
	local text = formatTime(remaining)
	if cashBadge then
		cashBadge.label.Text = "+" .. NumberFormat.Money(cashAmount(cashBadge.reward))
	end
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
	for _, offer in { config.LimitedOffers.FirstOffer, table.unpack(config.LimitedOffers.Pool) } do
		for _, reward in offer.rewards do
			rewardOffer[reward] = offer.key
		end
	end
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
	normalSize = if phone
		then UDim2.fromScale(PackStyle.SIDE_BUTTON_WIDTH_PHONE, 0.62)
		else UDim2.fromScale(PackStyle.SIDE_BUTTON_WIDTH, 0.66)
	column.Size = normalSize
	column.ZIndex = 5 -- au-dessus du HUD pendant le passage au milieu
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

	-- Calendrier de ce joueur : compte depuis la fin de l'ecran de chargement (attribut LoadingDone
	-- du Preloader), pour que le Starter Pack passe au milieu de l'ecran quand le joueur le voit.
	local waited = 0
	while player:GetAttribute("LoadingDone") ~= true and waited < 30 do
		waited += task.wait(0.2)
	end
	startClock = os.clock()

	RunService.Heartbeat:Connect(function(dt)
		for _, glow in glows do
			glow.Rotation = (glow.Rotation + GLOW_SPEED * dt) % 360
		end
	end)
	hud:GetAttributeChangedSignal("ActiveMenu"):Connect(slideColumn)
	-- Achat confirme (attribut "OfferBought" pose par RobuxShopService a la remise) : l'offre
	-- affichee se retire et le menu se ferme, au lieu de rester proposee jusqu'a la fin du minuteur.
	player:GetAttributeChangedSignal("OfferBought"):Connect(function()
		local key = player:GetAttribute("OfferBought")
		local current = offerForCycle(currentCycle)
		if current and type(key) == "string" and string.match(key, "^(.-)#") == current.key then
			boughtCycle = currentCycle
			pcall(tick)
		end
	end)

	while true do
		local ok, err = pcall(tick)
		if not ok then
			warn(`[OffersController] tick : {err}`)
		end
		task.wait(1)
	end
end

return OffersController
