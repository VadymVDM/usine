--!strict
-- Lucky Cash (cote client) : une liasse de billets 3D qui tourne sur elle-meme, posee de temps en
-- temps sur UN etage ouvert de SA tour (Config/LuckyCash.Spot ; rythme : FirstSpawnSeconds,
-- VisibleSeconds, SpawnMin/MaxSeconds). Marcher dessus (TouchRadius) ou E ouvre la fenetre
-- "Lucky Find!" : montant (attribut joueur LuckyCashAmount, calcule par le serveur), bouton Robux
-- -> remote LuckyCashBuy. Le serveur ouvre la fenetre d'achat Roblox et donne l'argent a la
-- reception du paiement ; il renvoie alors Feedback "Cash" avec lucky = true : la liasse disparait
-- jusqu'a la prochaine apparition.
-- La liasse est locale (le joueur seul la voit) et ne touche a rien : pas de collision, pas de
-- requete. Pas de lueur au sol, pas de lumiere, pas de Neon (2026-11-21).
-- Doc : docs/systems/lucky-cash.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LuckyCash = require(Config:WaitForChild("LuckyCash"))
local Icons = require(Config:WaitForChild("Icons")) :: any
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local Prompt = require(Shared:WaitForChild("Util"):WaitForChild("Prompt"))
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local LuckyCashController = {}

local MENU_NAME = "LuckyCash"
local GLOW_IMAGE = "rbxassetid://100034870209210" -- rayons lumineux du pack UI (comme les offres)
local CHECK_SECONDS = 0.15
local PILE_REFRESH_SECONDS = 1
local PILE_SCALE = 2
local HOVER = 1.8 -- hauteur du centre de la liasse au-dessus du sol
local SPIN_SPEED = math.rad(90) -- un tour complet en 4 s
local BOB = 0.25 -- monte / descend de X studs
local TILT = CFrame.Angles(0, 0, math.rad(15)) -- liasse un peu penchee

local BILL = Color3.fromRGB(46, 196, 64)
local BILL_BAND = Color3.fromRGB(170, 255, 120)
local BILL_DARK = Color3.fromRGB(30, 150, 50)
local AMOUNT_GREEN = Color3.fromRGB(110, 255, 80)
local DEAL_YELLOW = Color3.fromRGB(255, 230, 40)

local player = Players.LocalPlayer
local started = false

type Pile = { model: Model, cash: Model, rest: CFrame, floor: Model, center: Vector3, amountLabel: TextLabel }
local pile: Pile? = nil -- la liasse visible (une seule a la fois)
local folder: Folder? = nil
local visibleUntil = 0
local nextSpawnAt = 0
local spinConnection: RBXScriptConnection? = nil
local rng = Random.new()
local armed = true
local lastAutoOpen = -math.huge
local buyEvent: RemoteEvent? = nil

local popupAmount: TextLabel? = nil
local popupDeal: TextLabel? = nil
local popupFloor: TextLabel? = nil
local popupBuy: GuiObject? = nil
local popupPriceRow: Instance? = nil
local popupPrice = 0 -- prix affiche sur le bouton (refait a l'ouverture s'il a change)

local function menuController(): any
	return require(script.Parent:WaitForChild("MenuController")) :: any
end

local function currentAmount(): number?
	local value = player:GetAttribute(LuckyCash.AmountAttribute)
	if type(value) == "number" and value == value and value > 0 then
		return value
	end
	return nil
end

local function amountText(): string
	local amount = currentAmount()
	return if amount then "+" .. NumberFormat.Money(amount) else "" -- jamais "+$0" ni "+$???"
end

-- Prix actuel en R$ (attribut LuckyCashPrice du serveur : 9 a l'etage 1, puis 24).
local function currentPrice(): number
	local value = player:GetAttribute(LuckyCash.PriceAttribute)
	if type(value) == "number" and value > 0 then
		return value
	end
	return LuckyCash.Products[#LuckyCash.Products].price
end

-- "= 2 HOURS of profit!" : vrai calcul avec les gains theoriques (attribut IncomePerSecond).
local function dealText(): string
	local amount = currentAmount()
	local perSecond = player:GetAttribute("IncomePerSecond")
	if amount and type(perSecond) == "number" and perSecond > 0 then
		local minutes = math.floor(amount / perSecond / 60 + 0.5)
		if minutes >= 120 then
			return `= {math.floor(minutes / 60)} HOURS of profit!`
		elseif minutes >= 10 then
			return `= {math.floor(minutes)} MIN of profit!`
		end
	end
	return "SUPER DEAL!"
end

-- Tas en 3D -------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Billet : brique verte + bordure plus foncee.
local function bill(parent: Instance, cf: CFrame)
	part(parent, "Bill", Vector3.new(2.6, 0.22, 1.25), cf, BILL)
	part(parent, "Edge", Vector3.new(2.66, 0.2, 1.31), cf, BILL_DARK)
end

-- "$" sur une face de la bande.
local function dollar(band: Part, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "$"
	label.TextScaled = true
	label.TextColor3 = BILL_DARK
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	label.Parent = gui
	gui.Parent = band
end

-- Liasse 3D (billets empiles + bande avec "$"), centree sur CFrame.identity.
local function buildCash(): Model
	local cash = Instance.new("Model")
	cash.Name = "Cash"
	for i = 0, 4 do
		local twist = if i % 2 == 0 then 0 else math.rad(4)
		bill(cash, CFrame.new(0, (i - 2) * 0.23, 0) * CFrame.Angles(0, twist, 0))
	end
	local band = part(cash, "Band", Vector3.new(0.7, 1.22, 1.36), CFrame.identity, BILL_BAND)
	dollar(band, Enum.NormalId.Top)
	dollar(band, Enum.NormalId.Front)
	dollar(band, Enum.NormalId.Back)
	cash.WorldPivot = CFrame.identity
	cash:ScaleTo(PILE_SCALE)
	return cash
end

local function buildPile(floor: Model): Pile
	local origin = floor:GetPivot() * CFrame.new(LuckyCash.Spot)
	local model = Instance.new("Model")
	model.Name = "LuckyCash_" .. floor.Name

	-- Liasse qui tourne (Heartbeat, voir spin)
	local rest = origin * CFrame.new(0, HOVER, 0)
	local cash = buildCash()
	cash:PivotTo(rest * TILT)
	cash.Parent = model

	-- Point d'accroche (fixe) : etiquette, touche E
	local anchor = part(model, "Anchor", Vector3.new(1, 1, 1), origin * CFrame.new(0, 2, 0), BILL)
	anchor.Transparency = 1

	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromScale(7, 3.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local title = PackStyle.label(gui, "LUCKY CASH!", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.45), 60)
	title.TextColor3 = DEAL_YELLOW
	local amount = PackStyle.label(gui, amountText(), UDim2.fromScale(0.5, 0.45), UDim2.fromScale(1, 0.55), 80)
	amount.TextColor3 = AMOUNT_GREEN
	gui.Parent = anchor
	TweenService:Create(gui, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0) }):Play()

	local prompt = Prompt.Create(anchor, "Lucky Cash", "Open", { distance = LuckyCash.PromptDistance })
	prompt.Triggered:Connect(function()
		LuckyCashController.OpenPopup(floor)
	end)

	model.Parent = folder
	return { model = model, cash = cash, rest = rest, floor = floor, center = origin.Position, amountLabel = amount }
end

-- Rotation + petit mouvement de haut en bas, a chaque image (une seule liasse : peu couteux).
local function spin()
	local current = pile
	if current == nil then
		return
	end
	local t = os.clock()
	current.cash:PivotTo(current.rest * CFrame.new(0, math.sin(t * 2) * BOB, 0) * CFrame.Angles(0, t * SPIN_SPEED, 0) * TILT)
end

local function scheduleNext()
	nextSpawnAt = os.clock() + rng:NextNumber(LuckyCash.SpawnMinSeconds, LuckyCash.SpawnMaxSeconds)
end

local function removePile()
	local current = pile
	if current then
		pile = nil
		current.model:Destroy()
	end
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

-- Une seule liasse a la fois, sur un etage ouvert de SA tour tire au hasard ; elle reste
-- VisibleSeconds puis revient apres SpawnMin/MaxSeconds.
local function refreshPiles()
	local now = os.clock()
	local base = FloorWatch.MyBase()
	local current = pile
	if current then
		local gone = current.floor.Parent == nil or base == nil or not FloorWatch.IsMine(current.floor)
		if gone or now >= visibleUntil then
			removePile()
			scheduleNext()
		end
		return
	end
	if base == nil or now < nextSpawnAt then
		return
	end
	local floors = FloorWatch.FloorsOf(base)
	if #floors == 0 then
		return
	end
	pile = buildPile(floors[rng:NextInteger(1, #floors)])
	visibleUntil = now + LuckyCash.VisibleSeconds
	spinConnection = RunService.Heartbeat:Connect(spin)
end

-- Fenetre "Lucky Find!" -------------------------------------------------------------------------

local function buildPopup()
	local frame = menuController().CloneMenuTemplate("OfflineEarnings", MENU_NAME)
	if not frame then
		warn("[LuckyCash] Modele de menu introuvable")
		return
	end
	local header = frame:FindFirstChild("Header")
	local title = header and header:FindFirstChild("TextLabel", true)
	if title and title:IsA("TextLabel") then
		title.Text = "Lucky Find!"
	end
	local body = frame:WaitForChild("Shop") :: Frame

	PackStyle.label(body, "WOW! You found a secret cash stash!", UDim2.fromScale(0.5, 0.03), UDim2.fromScale(0.94, 0.13), 44)

	-- Encadre du montant : rayons qui tournent + billets + montant vert
	local box = Instance.new("Frame")
	box.Name = "AmountBox"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.fromScale(0.5, 0.19)
	box.Size = UDim2.fromScale(0.7, 0.3)
	box.BackgroundColor3 = Color3.fromRGB(40, 45, 70)
	box.BackgroundTransparency = 0.15
	box.ZIndex = 2
	PackStyle.stroke(box, 3, Color3.fromRGB(10, 10, 20), Enum.ApplyStrokeMode.Border)
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.16, 0.5)
	glow.Size = UDim2.fromScale(1.5, 1.5)
	glow.SizeConstraint = Enum.SizeConstraint.RelativeYY
	glow.Image = GLOW_IMAGE
	glow.ImageTransparency = 0.2
	glow.ZIndex = 2
	glow.Parent = box
	TweenService:Create(glow, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
	local cash = Instance.new("ImageLabel")
	cash.BackgroundTransparency = 1
	cash.AnchorPoint = Vector2.new(0.5, 0.5)
	cash.Position = UDim2.fromScale(0.16, 0.5)
	cash.Size = UDim2.fromScale(0.9, 0.9)
	cash.SizeConstraint = Enum.SizeConstraint.RelativeYY
	cash.ScaleType = Enum.ScaleType.Fit
	cash.Image = Icons.Cash
	cash.ZIndex = 3
	cash.Parent = box
	TweenService:Create(cash, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 8, Size = UDim2.fromScale(1, 1) }):Play()
	local amount = PackStyle.label(box, "",UDim2.fromScale(0.62, 0.1), UDim2.fromScale(0.68, 0.8), 80)
	amount.TextColor3 = PackStyle.MONEY_GREEN
	box.Parent = body
	popupAmount = amount

	local floorLabel = PackStyle.label(body, "", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.08), 30)
	popupFloor = floorLabel
	local deal = PackStyle.label(body, "", UDim2.fromScale(0.5, 0.58), UDim2.fromScale(0.8, 0.1), 40)
	deal.TextColor3 = DEAL_YELLOW
	popupDeal = deal

	local buy = PackStyle.button(body, "Buy", PackStyle.GREEN, UDim2.fromScale(0.5, 0.71), UDim2.fromScale(0.42, 0.22))
	-- Contour dore qui pulse sur le bouton d'achat (comme les offres)
	local glowStroke = PackStyle.stroke(buy, 4, Color3.fromRGB(255, 220, 60), Enum.ApplyStrokeMode.Border)
	TweenService:Create(glowStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.8 }):Play()
	popupBuy = buy
	popupPriceRow = PackStyle.priceRow(buy, Icons.Robux, currentPrice(), UDim2.fromScale(0.5, 0.12), UDim2.fromScale(1, 0.76))
	buy.Activated:Connect(function()
		if buyEvent then
			buyEvent:FireServer()
		end
	end)

	menuController().RegisterMenu(frame)
end

function LuckyCashController.OpenPopup(floor: Model?)
	if popupAmount == nil or currentAmount() == nil then
		return
	end
	local menus = menuController()
	if menus.GetActiveMenu() == MENU_NAME then
		return
	end
	popupAmount.Text = amountText()
	local price = currentPrice()
	if popupBuy and price ~= popupPrice then
		popupPrice = price
		if popupPriceRow then
			popupPriceRow:Destroy()
		end
		popupPriceRow = PackStyle.priceRow(popupBuy, Icons.Robux, price, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(1, 0.76))
	end
	if popupDeal then
		popupDeal.Text = dealText()
	end
	if popupFloor then
		popupFloor.Text = if floor then `Hidden on Floor {FloorWatch.IndexOf(floor)}` else ""
	end
	menus.Open(MENU_NAME)
	SoundFx.Play("WelcomeBack")
end

-- Marcher sur le tas ouvre la fenetre (une fois ; il faut s'eloigner pour la rouvrir seule, et
-- au plus une fois toutes les AutoOpenCooldownSeconds).
local function checkTouch()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local nearest = pile
	local nearestDistance = math.huge
	if nearest then
		local offset = root.Position - nearest.center
		if math.abs(offset.Y) < 6 then
			nearestDistance = Vector2.new(offset.X, offset.Z).Magnitude
		end
	end
	if nearestDistance > LuckyCash.RearmRadius then
		armed = true
	elseif nearest and armed and nearestDistance <= LuckyCash.TouchRadius then
		armed = false
		-- Pas par-dessus un autre menu deja ouvert, et pas a chaque passage (E marche toujours)
		local now = os.clock()
		if menuController().GetActiveMenu() == nil and now - lastAutoOpen >= LuckyCash.AutoOpenCooldownSeconds then
			lastAutoOpen = now
			LuckyCashController.OpenPopup(nearest.floor)
		end
	end
end

local function onAmountChanged()
	if pile then
		pile.amountLabel.Text = amountText()
	end
end

-- Achat confirme par le serveur : fermer la fenetre, la liasse part jusqu'a la prochaine fois.
local function onFeedback(kind: any, payload: any)
	if kind ~= "Cash" or type(payload) ~= "table" or payload.lucky ~= true then
		return
	end
	removePile()
	scheduleNext()
	if menuController().GetActiveMenu() == MENU_NAME then
		menuController().Close()
	end
end

function LuckyCashController.Init() end

function LuckyCashController.Start()
	if started then
		return
	end
	started = true
	local created = Instance.new("Folder")
	created.Name = "LuckyCashPiles"
	created.Parent = workspace
	folder = created
	nextSpawnAt = os.clock() + LuckyCash.FirstSpawnSeconds

	FloorWatch.Watch(function() end) -- demarre le suivi des etages
	player:GetAttributeChangedSignal(LuckyCash.AmountAttribute):Connect(onAmountChanged)

	task.spawn(function()
		buyEvent = Remotes.WaitClientEvent("LuckyCashBuy")
		local feedback = Remotes.WaitClientEvent("Feedback")
		if feedback then
			feedback.OnClientEvent:Connect(onFeedback)
		end
	end)
	task.spawn(function()
		if menuController().WaitUntilReady(15) then
			buildPopup()
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(refreshPiles)
			if not ok then
				warn(`[LuckyCash] {err}`)
			end
			task.wait(PILE_REFRESH_SECONDS)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local ok, err = pcall(checkTouch)
			if not ok then
				warn(`[LuckyCash] {err}`)
			end
		end
	end)
end

return LuckyCashController
