--!strict
-- Menu Index (ShopGUI.MenuFrames.Index) : les 100 fruits dans une grille, sans filtres de rarete.
-- Ordre (2026-11-20, demande "range par rarete") : les 10 Common (etage 1 -> 10), puis les 10
-- Uncommon... jusqu'a Infinity. 5 cartes par ligne : une rarete (10 fruits) = 2 lignes pile. Si une
-- rarete n'avait pas un multiple de 5 fruits, des cases vides completent sa ligne.
-- Carte : fruit en 3D (ViewportFrame) ou silhouette noire "???" s'il n'est pas decouvert, nom,
-- rarete dans sa couleur, chance de base (Luck 1) : "1 in 3,000" (Common : "68%"), affichee meme
-- pour un fruit pas decouvert. Fruit decouvert pas encore recompense : bouton vert "CLAIM +$X" qui pulse
-- (montant = Fruits.ClaimReward, calcule aussi par le serveur ; le client ne fait qu'afficher).
-- Le serveur decide de tout : remote IndexState (etat), IndexClaim (demande), Feedback "IndexClaim"
-- (effet : "+$X" qui monte, son, confettis pour Legendary+).
-- Pastille rouge sur le bouton Index du HUD tant qu'il reste une recompense a prendre.
-- Les cartes sont construites a la premiere ouverture (par paquets, pour ne pas figer l'ecran).
-- Doc : docs/systems/fruits.md (section "Index"), docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local TextPop = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("TextPop"))
local Celebration = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Celebration"))

local MENU_NAME = "Index"
local COLUMNS = 5 -- cartes par ligne (2026-11-20, demande : "5 par 5") : 1 etage = 2 lignes
local COLUMNS_PHONE = 5 -- telephone : pareil (les cases vides de fin d'etage en dependent)
local GAP = 8 -- pixels entre les cartes (et autour de la grille)
local TOP_GAP = 16 -- marge en haut de la grille (le contour des cartes deborde de 3 px : il manquait de l'air)
local CARD_RATIO = 1.22 -- hauteur / largeur d'une carte
local BUILD_BATCH = 10 -- cartes construites par image
local BIG_RARITY = 5 -- Legendary+ : confettis au claim
local SILHOUETTE = Color3.fromRGB(20, 16, 30)
local CARD_DARK = Color3.fromRGB(34, 30, 52) -- fond des cartes non decouvertes
local CLAIM_SOUND = "CashPop"
local CLAIM_SOUND_2 = "Sale"

local IndexController = {}

local player = Players.LocalPlayer
local started = false

type Card = {
	frame: Frame,
	viewport: ViewportFrame,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	chanceLabel: TextLabel,
	claim: TextButton,
	claimScale: UIScale,
	gradient: UIGradient,
	pulse: Tween?,
	shown: string?, -- "locked" | "found" | "claim" : dernier etat affiche
}

local discovered: { [string]: boolean } = {}
local claimed: { [string]: boolean } = {}
local pending: { [string]: boolean } = {} -- claim envoye, reponse du serveur pas encore recue
local hasState = false

local menu: Frame? = nil
local list: ScrollingFrame? = nil
local grid: UIGridLayout? = nil
local titleLabel: TextLabel? = nil
local titleText = "Index"
local cards: { [string]: Card } = {}
local built = false
local building = false
local claimEvent: RemoteEvent? = nil

---------------------------------------------------------------------------------------------
-- Aides

local function menuController(): any?
	local module = script.Parent:FindFirstChild("MenuController")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function isPhone(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.Y < 450
end

local function canClaim(id: string): boolean
	return discovered[id] == true and not claimed[id] and not pending[id]
end

local function countFound(): number
	local n = 0
	for _ in discovered do
		n += 1
	end
	return n
end

local function anyClaim(): boolean
	for id in discovered do
		if canClaim(id) then
			return true
		end
	end
	return false
end

-- Chance de base (Luck 1 + bonus de l'etage, Fruits.FloorLuck) : "1 in 3,000" ; Common en pourcentage.
local function chanceText(rarity: number, floor: number): string
	local luck = Fruits.FloorLuckFor(floor)
	local oneIn = Fruits.OneIn(rarity, luck)
	if rarity > 1 and oneIn > 1 then
		return `1 in {NumberFormat.Commas(oneIn)}`
	end
	local weights = Fruits.RollWeights(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local w = weights[rarity] or 0
	return if total > 0 then `{math.floor(w / total * 100 + 0.5)}%` else "?"
end

-- Modele 3D du fruit dans la carte, camera cadree sur sa boite.
local function fillViewport(viewport: ViewportFrame, fruitId: string)
	local ok, model = pcall(FruitModels.CreateFruit, fruitId, true)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	-- Pas d'effets dans une carte (les particules ne s'affichent pas dans un ViewportFrame)
	for _, item in model:GetDescendants() do
		if item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("Beam") or item:IsA("Trail") then
			item:Destroy()
		end
	end
	model:PivotTo(CFrame.Angles(0, math.rad(-25), 0))
	local boxCFrame, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.5
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.25
	local center = boxCFrame.Position
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, radius * 0.35, distance), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
end

---------------------------------------------------------------------------------------------
-- Cartes

local function makeCard(fruit: Fruits.Fruit, order: number): Card
	local rarity = Fruits.Rarities[fruit.rarity]
	local frame = Instance.new("Frame")
	frame.Name = fruit.id
	frame.LayoutOrder = order
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	PackStyle.stroke(frame, 3, rarity.color:Lerp(Color3.new(0, 0, 0), 0.6), Enum.ApplyStrokeMode.Border)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Parent = frame
	local inner = Instance.new("Frame")
	inner.Name = "InnerLine"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	PackStyle.stroke(inner, 1.5, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border).Transparency = 0.6
	inner.Parent = frame

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Fruit"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.fromScale(0.5, 0.03)
	viewport.Size = UDim2.fromScale(0.94, 0.52)
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.5, -1)
	viewport.ZIndex = 2
	viewport.Parent = frame
	fillViewport(viewport, fruit.id)

	local nameLabel = PackStyle.label(frame, "???", UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.92, 0.15), 22)
	nameLabel.Name = "FruitName"
	local rarityLabel =
		PackStyle.label(frame, rarity.name, UDim2.fromScale(0.5, 0.70), UDim2.fromScale(0.86, 0.12), 18)
	rarityLabel.Name = "Rarity"
	rarityLabel.TextColor3 = rarity.color
	local chanceLabel =
		PackStyle.label(frame, chanceText(fruit.rarity, fruit.floor), UDim2.fromScale(0.5, 0.83), UDim2.fromScale(0.86, 0.11), 16)
	chanceLabel.Name = "Chance"

	-- Bouton CLAIM (a la place de la rarete et de la chance quand une recompense attend)
	local claim =
		PackStyle.button(frame, "Claim", PackStyle.GREEN, UDim2.fromScale(0.5, 0.74), UDim2.fromScale(0.9, 0.2))
	claim.AnchorPoint = Vector2.new(0.5, 0)
	claim.ZIndex = 5
	local claimText = PackStyle.label(
		claim,
		"+" .. NumberFormat.Money(Fruits.ClaimReward(fruit.id)),
		UDim2.fromScale(0.5, 0.08),
		UDim2.fromScale(0.9, 0.84),
		22
	)
	claimText.ZIndex = 6
	local claimScale = Instance.new("UIScale")
	claimScale.Name = "PulseScale"
	claimScale.Parent = claim
	claim.Visible = false

	local card: Card = {
		frame = frame,
		viewport = viewport,
		nameLabel = nameLabel,
		rarityLabel = rarityLabel,
		chanceLabel = chanceLabel,
		claim = claim,
		claimScale = claimScale,
		gradient = gradient,
		pulse = nil,
		shown = nil,
	}
	claim.Activated:Connect(function()
		if not canClaim(fruit.id) or claimEvent == nil then
			return
		end
		pending[fruit.id] = true
		claimEvent:FireServer(fruit.id)
		-- Securite : sans reponse du serveur, le bouton revient
		task.delay(3, function()
			if pending[fruit.id] then
				pending[fruit.id] = nil
				IndexController.Refresh()
			end
		end)
		IndexController.Refresh()
	end)
	return card
end

local function showCard(fruit: Fruits.Fruit, card: Card)
	local found = discovered[fruit.id] == true
	local state = if not found then "locked" elseif canClaim(fruit.id) then "claim" else "found"
	if card.shown == state then
		return
	end
	card.shown = state
	local rarity = Fruits.Rarities[fruit.rarity]
	if found then
		card.gradient.Color = ColorSequence.new(rarity.color:Lerp(Color3.new(0, 0, 0), 0.45), rarity.color:Lerp(Color3.new(1, 1, 1), 0.15))
		card.viewport.ImageColor3 = Color3.new(1, 1, 1)
		card.viewport.ImageTransparency = 0
		card.nameLabel.Text = fruit.name
	else
		card.gradient.Color = ColorSequence.new(CARD_DARK, CARD_DARK:Lerp(rarity.color, 0.25))
		card.viewport.ImageColor3 = SILHOUETTE
		card.viewport.ImageTransparency = 0.15
		card.nameLabel.Text = "???"
	end
	card.claim.Visible = state == "claim"
	card.rarityLabel.Visible = state ~= "claim"
	card.chanceLabel.Visible = state ~= "claim"
	if state == "claim" then
		if card.pulse == nil then
			card.claimScale.Scale = 1
			local pulse = TweenService:Create(
				card.claimScale,
				TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.08 }
			)
			card.pulse = pulse
			pulse:Play()
		end
	elseif card.pulse then
		card.pulse:Cancel()
		card.pulse = nil
		card.claimScale.Scale = 1
	end
end

-- Taille des cartes : en part de la largeur (5 par ligne), hauteur gardee par le
-- UIAspectRatioConstraint du UIGridLayout. Pas de pixels : l'UIScale d'ouverture du menu les fausserait.
local function layoutGrid()
	local layout = grid
	if layout == nil then
		return
	end
	local columns = if isPhone() then COLUMNS_PHONE else COLUMNS
	local gapShare = math.ceil(GAP * (columns - 1) / columns) + 1
	layout.CellSize = UDim2.new(1 / columns, -gapShare, 1, 0)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
end

-- Construit les 100 cartes (une fois), par paquets.
local function build()
	if built or building or list == nil then
		return
	end
	building = true
	local scroll = list :: ScrollingFrame
	local order = 0
	for rarityIndex = 1, #Fruits.Rarities do
		for _, fruit in Fruits.OfRarity(rarityIndex) do
			order += 1
			local card = makeCard(fruit, order)
			cards[fruit.id] = card
			showCard(fruit, card)
			card.frame.Parent = scroll
			if order % BUILD_BATCH == 0 then
				task.wait()
			end
		end
		-- Cases vides en fin de rarete : la rarete suivante commence en debut de ligne
		local columns = if isPhone() then COLUMNS_PHONE else COLUMNS
		local count = #Fruits.OfRarity(rarityIndex)
		for _ = 1, (columns - count % columns) % columns do
			order += 1
			local spacer = Instance.new("Frame")
			spacer.Name = "Spacer"
			spacer.LayoutOrder = order
			spacer.BackgroundTransparency = 1
			spacer.BorderSizePixel = 0
			spacer.Parent = scroll
		end
	end
	built = true
	building = false
	IndexController.Refresh()
end

---------------------------------------------------------------------------------------------
-- Etat

function IndexController.Refresh()
	if built then
		for id, card in cards do
			local fruit = Fruits.ById[id]
			if fruit then
				showCard(fruit, card)
			end
		end
	end
	if titleLabel then
		titleLabel.Text = `{titleText}  {countFound()}/{#Fruits.List}`
	end
	local menus = menuController()
	if menus and hasState then
		-- Pastille tant qu'une recompense attend (sauf menu deja ouvert)
		local open = menus.GetActiveMenu() == MENU_NAME
		menus.SetBadge(MENU_NAME, anyClaim() and not open)
	end
end

local function onState(payload: any)
	if type(payload) ~= "table" or type(payload.discovered) ~= "table" or type(payload.claimed) ~= "table" then
		return
	end
	table.clear(discovered)
	table.clear(claimed)
	for _, id in payload.discovered do
		if type(id) == "string" and Fruits.ById[id] then
			discovered[id] = true
		end
	end
	for _, id in payload.claimed do
		if type(id) == "string" and Fruits.ById[id] then
			claimed[id] = true
			pending[id] = nil
		end
	end
	hasState = true
	IndexController.Refresh()
end

-- "+$X" qui monte depuis la carte, son ; confettis pour Legendary+.
local function onClaimed(fruitId: string, amount: number)
	pending[fruitId] = nil
	claimed[fruitId] = true
	SoundFx.Play(CLAIM_SOUND)
	SoundFx.Play(CLAIM_SOUND_2, 0.7)
	local fruit = Fruits.ById[fruitId]
	local card = cards[fruitId]
	if card and menu and card.frame.Parent then
		local root = menu :: Frame
		local start = card.frame.AbsolutePosition - root.AbsolutePosition + card.frame.AbsoluteSize / 2
		local pop = PackStyle.label(
			root,
			"+" .. NumberFormat.Money(amount),
			UDim2.fromOffset(start.X, start.Y),
			-- Taille finale d'avant (ancien pop qui finissait a x1.15), sans animation de taille
			UDim2.fromOffset(card.frame.AbsoluteSize.X * 1.6 * 1.15, card.frame.AbsoluteSize.X * 0.45 * 1.15),
			46
		)
		pop.AnchorPoint = Vector2.new(0.5, 0.5)
		pop.TextColor3 = PackStyle.MONEY_GREEN
		pop.ZIndex = 30
		-- Apparait en fondu et monte, sans grossir (un texte qui grossit clignote sur telephone : UI/TextPop)
		TextPop.FadeIn(pop)
		local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(pop, rise, { Position = pop.Position - UDim2.fromOffset(0, card.frame.AbsoluteSize.Y * 0.8) }):Play()
		task.delay(0.55, function()
			local fade = TweenInfo.new(0.35)
			TweenService:Create(pop, fade, { TextTransparency = 1 }):Play()
			local stroke = pop:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			end
			task.delay(0.4, function()
				pop:Destroy()
			end)
		end)
	end
	if fruit and fruit.rarity >= BIG_RARITY then
		local color = Fruits.Rarities[fruit.rarity].color
		Celebration.Confetti(player:WaitForChild("PlayerGui"), { color, Color3.new(1, 1, 1), PackStyle.MONEY_GREEN })
	end
	IndexController.Refresh()
end

local function onFeedback(kind: any, payload: any)
	if kind ~= "IndexClaim" or type(payload) ~= "table" then
		return
	end
	local fruitId, amount = payload.fruit, payload.amount
	if type(fruitId) ~= "string" or Fruits.ById[fruitId] == nil or type(amount) ~= "number" then
		return
	end
	onClaimed(fruitId, amount)
end

---------------------------------------------------------------------------------------------
-- Mise en place du menu du pack : retire les filtres de rarete et les cartes d'exemple.

local function setupMenu(): boolean
	local playerGui = player:WaitForChild("PlayerGui")
	local shopGUI = playerGui:WaitForChild("ShopGUI", 30)
	local frames = shopGUI and shopGUI:WaitForChild("MenuFrames", 30)
	local frame = frames and frames:WaitForChild(MENU_NAME, 30)
	if frame == nil or not frame:IsA("Frame") then
		warn("[IndexController] Menu Index introuvable")
		return false
	end
	menu = frame
	local rarities = frame:FindFirstChild("Rarities")
	if rarities then
		rarities:Destroy()
	end
	local body = frame:FindFirstChild("Shop")
	local scroll = body and body:FindFirstChildOfClass("ScrollingFrame")
	if scroll == nil then
		warn("[IndexController] Liste de l'Index introuvable")
		return false
	end
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") or child:IsA("UIGridLayout") or child:IsA("UIListLayout") or child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, TOP_GAP)
	padding.PaddingBottom = UDim.new(0, GAP)
	padding.PaddingLeft = UDim.new(0, GAP)
	padding.PaddingRight = UDim.new(0, GAP)
	padding.Parent = scroll
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.FillDirectionMaxCells = 0
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1 / CARD_RATIO
	aspect.Parent = layout
	layout.Parent = scroll
	list = scroll
	grid = layout
	layoutGrid()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutGrid)
	end

	-- Titre de l'en-tete : "Index  12/100"
	local header = frame:FindFirstChild("Header")
	local sub = header and header:FindFirstChild("SubHeader")
	local band = sub and sub:FindFirstChildOfClass("ImageLabel")
	local title = band and band:FindFirstChildOfClass("TextLabel")
	if title then
		titleLabel = title
		titleText = title.Text
	end
	return true
end

function IndexController:Init() end

function IndexController:Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local event = Remotes.WaitClientEvent("IndexState")
		if event then
			event.OnClientEvent:Connect(onState)
		end
	end)
	task.spawn(function()
		local event = Remotes.WaitClientEvent("Feedback")
		if event then
			event.OnClientEvent:Connect(onFeedback)
		end
	end)
	task.spawn(function()
		claimEvent = Remotes.WaitClientEvent("IndexClaim")
	end)
	task.spawn(function()
		local menus = menuController()
		if menus then
			menus.WaitUntilReady(30)
		end
		if not setupMenu() then
			return
		end
		IndexController.Refresh()
		-- Cartes construites a la premiere ouverture ; pastille remise a la fermeture
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
		hud:GetAttributeChangedSignal("ActiveMenu"):Connect(function()
			if hud:GetAttribute("ActiveMenu") == MENU_NAME then
				task.spawn(build)
			else
				IndexController.Refresh()
			end
		end)
	end)
end

return IndexController
