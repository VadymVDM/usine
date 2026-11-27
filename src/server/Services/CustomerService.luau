--!strict
-- Comptoir, ventes et tas d'argent de chaque ETAGE (2026-11-20 : chaque etage a SA table a argent et
-- SON pad Collect Cash ; les ventes d'un etage vont sur le tas de cet etage, il faut y aller pour
-- encaisser. Le pad Robux Auto Collect est sur chaque etage depuis le 2026-11-21 et vaut pour toute la tour) :
--   * comptoir : se tenir sur le pad "Drop Juices" (Counter.JuiceDropPad, derriere le comptoir)
--     = poser tous les jus portes. Pas de limite (2026-11-19) : on n'ameliore que la vitesse des
--     clients. Au-dela de CounterCupLayersMax couches, les gobelets ne sont plus dessines (compteur seul) ;
--   * ventes : toutes les CustomerSpeed secondes, jusqu'a CustomerCount clients achetent chacun
--     1 jus ; le prix (valeur du fruit) va sur le tas d'argent. Les clients sont dessines par
--     chaque client (CustomerController) : le serveur envoie WorldFx "Sale" (place, fruit, montant)
--     et pose les attributs de base CustomerSlots / CounterJuices ;
--   * tas d'argent : vraies liasses de billets sur la table, montant au-dessus ; se tenir sur le
--     pad "Collect Cash" (Counter.CashPad) = encaisser (MoneyService.Add) + Feedback "Cash" ;
--   * pad Robux "Auto Collect" (pass Shop.Passes AutoCollect) : l'argent des ventes va directement
--     au joueur. passId = 0 tant que le pass n'est pas cree : message "coming soon". Possession =
--     attribut joueur "AutoCollect" (pose par le serveur seulement, comme les autres passes ; avant
--     le 2026-11-21 c'etait une table interne que la boutique et le panneau admin ne voyaient pas) ;
--   * pass Robux "Instant Sell" (attribut joueur "InstantSell", pad PassPadService, 2026-11-21) :
--     les jus que le JOUEUR pose sur le comptoir sont vendus tout de suite, des que l'animation de
--     depot est finie (sans attendre les clients). Prix comme une vente normale.
--   * panneau "MONEY / HOUR" au-dessus du comptoir (Counter.IncomeSign, 2026-11-19 soir) : ventes
--     des IncomeWindowSeconds dernieres secondes ramenees a une heure, remis a jour a chaque tour
--     de vente.
-- Lot 5 : les etages ou le joueur n'est pas versent leur argent "en nombres" (Lib/FloorIncome, toutes
-- les Floors.IncomeTickSeconds) ; clients dessines (WorldFx Sale) seulement sur l'etage du joueur.
-- Rien n'est sauvegarde (comptoir et tas repartent a zero). Seul module qui modifie le comptoir et le tas.
-- Doc : docs/systems/clients.md

local GamePass = require(script.Parent.Parent.Lib.GamePass)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Fruits = require(Config:WaitForChild("Fruits"))
local FloorsConfig = require(Config:WaitForChild("Floors"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Shop = require(Config:WaitForChild("Shop"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Rebirth = require(Config:WaitForChild("Rebirth"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local Util = Shared:WaitForChild("Util")
local NumberFormat = require(Util:WaitForChild("NumberFormat"))
local HandStack = require(Util:WaitForChild("HandStack"))
local WorldLabel = require(Util:WaitForChild("WorldLabel"))
local RobuxPad = require(Util:WaitForChild("RobuxPad"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local FloorIncome = require(script.Parent.Parent.Lib.FloorIncome)
local Perks = require(script.Parent.Parent.Lib.Perks)
local FloorService = require(script.Parent.FloorService)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local ProductionService = require(script.Parent.ProductionService)
local LeaderboardService = require(script.Parent.LeaderboardService)
-- Usine a construire (profil neuf) : comptoir, pads et clients seulement apres "Open shop" (etape 4)
local SetupService = require(script.Parent.SetupService)

local CustomerService = {}

local MESSAGES = Gameplay.Messages
local CASH_COLOR = Color3.fromRGB(120, 255, 110)
local BILL_COLORS = { Color3.fromRGB(150, 220, 120), Color3.fromRGB(118, 196, 96) } -- vert clair sur tapis rouge
local BILL_SIZE = Vector3.new(1.7, 0.18, 0.85)
local COIN_COLOR = Color3.fromRGB(255, 205, 50)

local autoCollectPass = 0
local autoCollectPrice = 0
for _, pass in Shop.Passes do
	if pass.key == "AutoCollect" then
		autoCollectPass = pass.passId
		autoCollectPrice = pass.price
	end
end

type CounterState = {
	player: Player,
	floor: Model, -- etage (Floors.FloorN)
	index: number, -- numero de l'etage (1 = en plus le pad Robux Auto Collect)
	folder: Folder, -- Dynamic.Counter
	cups: { string },
	cupModels: { Model },
	topArea: BasePart?,
	juiceZone: BasePart?, -- Counter.JuiceDropPad.PadZone : s'y tenir = poser les jus sur le comptoir
	cashZone: BasePart?, -- Counter.CashPad.PadZone : s'y tenir = encaisser le tas d'argent
	label: BillboardGui?,
	cash: number,
	bills: { BasePart },
	billFolder: Folder,
	pile: BasePart?,
	cashLabel: BillboardGui?,
	autoPad: Model?,
	autoZone: BasePart?,
	onAutoPad: boolean, -- le proprietaire est sur le pad Auto Collect de CET etage (achat a l'arrivee)
	sales: { { t: number, amount: number } }, -- ventes recentes (argent / heure)
	startedAt: number,
	numbersPending: number, -- argent "en nombres" pas encore verse (fraction de $)
	juicesPending: number, -- jus vendus "en nombres" pas encore comptes (classement)
	incomeLabel: TextLabel?, -- Counter.IncomeSign : "$12.5K"
	thread: thread?,
	active: boolean,
}

local states: { [Model]: CounterState } = {}
local AUTO_ATTRIBUTE = "AutoCollect"
local INSTANT_ATTRIBUTE = "InstantSell"
local onJuicePad: { [Player]: boolean } = {}
local feedbackEvent: RemoteEvent? = nil
local worldFxEvent: RemoteEvent? = nil
local rng = Random.new()

-- Pass Auto Collect possede (attribut pose par le serveur : le client ne peut pas le changer).
local function ownsAutoCollect(player: Player): boolean
	return player:GetAttribute(AUTO_ATTRIBUTE) == true
end

-- Effet d'une amelioration de l'etage (CustomerSpeed, CustomerCount).
local function getLevelValue(player: Player, index: number, id: string): number
	local data = DataService.GetData(player)
	local levels = if data then DataService.FloorUpgrades(data, index) else nil
	local level = if levels then levels[id] or Upgrades.ById[id].startLevel else Upgrades.ById[id].startLevel
	return Upgrades.GetValue(id, level)
end

-- Multiplicateur des ventes du joueur : rebirths (Config/Rebirth) x pass Billboard (2X Sell Price,
-- attribut joueur "Billboard" pose par PassPadService ; Gameplay.BillboardSellMultiplier) x achats
-- Robux (pass 3X CASH, boost Money : Lib/Perks ; `withBoosts` = false sans les boosts temporaires).
-- 1 si pas charge.
local function sellMultiplier(player: Player, withBoosts: boolean): number
	local data = DataService.GetData(player)
	local multiplier = Rebirth.Multiplier(if data then data.Rebirths else 0)
	if player:GetAttribute("Billboard") == true then
		multiplier *= Gameplay.BillboardSellMultiplier
	end
	return multiplier * Perks.MoneyMultiplier(player, withBoosts)
end

---------------------------------------------------------------------------------------------
-- Comptoir

local function cupCFrame(state: CounterState, index: number): CFrame?
	local area = state.topArea
	if area == nil then
		return nil
	end
	local spacing = Gameplay.JuiceCupSpacing
	local cols = math.max(1, math.floor(area.Size.X / spacing))
	local rows = math.max(1, math.floor(area.Size.Z / spacing))
	local perLayer = cols * rows
	local i = index - 1
	local layer = i // perLayer
	if layer >= Gameplay.CounterCupLayersMax then
		return nil -- trop de jus : pas de modele (seul le compteur monte)
	end
	local inLayer = i % perLayer
	local col = inLayer % cols
	local row = inLayer // cols
	local corner = area.CFrame * CFrame.new(-area.Size.X / 2, -area.Size.Y / 2, -area.Size.Z / 2)
	return corner * CFrame.new((col + 0.5) * spacing, layer * (FruitModels.CupHeight + 0.05), (row + 0.5) * spacing)
end

local function refreshCounter(state: CounterState)
	if state.label then
		WorldLabel.SetPlainText(state.label, `x{#state.cups}`)
	end
	state.floor:SetAttribute("CounterJuices", #state.cups)
end

-- `from[k]` (optionnel) : d'ou part le jus ids[k] ; le client le fait sauter de la jusqu'au
-- comptoir (attributs PopFrom / PopIndex / PopAt, HandStackController).
local function addToCounter(state: CounterState, ids: { string }, from: { Vector3 }?): number
	local accepted = 0
	local now = workspace:GetServerTimeNow()
	for k, fruitId in ids do
		table.insert(state.cups, fruitId)
		accepted += 1
		local cf = cupCFrame(state, #state.cups)
		if cf then
			local cup = FruitModels.CreateCup(fruitId, true)
			cup:PivotTo(cf)
			local start = from and from[k]
			if start then
				cup:SetAttribute("PopFrom", start)
				cup:SetAttribute("PopIndex", k)
				cup:SetAttribute("PopAt", now)
			end
			cup.Parent = state.folder
			state.cupModels[#state.cups] = cup
		end
	end
	refreshCounter(state)
	return accepted
end

---------------------------------------------------------------------------------------------
-- Tas d'argent : des liasses de billets qui grandissent avec le montant

local function targetBills(cash: number): number
	if cash <= 0 then
		return 0
	end
	local n = math.floor(Gameplay.MoneyBillsPerDoubling * math.log(cash + 1, 2))
	return math.clamp(n, 1, Gameplay.MoneyBillsMax)
end

local function addBill(state: CounterState, index: number)
	local pile = state.pile
	if pile == nil then
		return
	end
	local stacks = Gameplay.MoneyStacks
	local cols = 4
	local rows = math.ceil(stacks / cols)
	local stack = (index - 1) % stacks
	local layer = (index - 1) // stacks
	local col = stack % cols
	local row = stack // cols
	local usable = Vector3.new(pile.Size.X * 0.8, 0, pile.Size.Z * 0.8)
	local x = -usable.X / 2 + (col + 0.5) * usable.X / cols
	local z = -usable.Z / 2 + (row + 0.5) * usable.Z / rows
	local floorY = -pile.Size.Y / 2
	local coin = index % 7 == 0
	local bill = Instance.new("Part")
	bill.Name = if coin then "Coin" else "Bill"
	bill.Anchored = true
	bill.CanCollide = false
	bill.CanQuery = false
	bill.CanTouch = false
	bill.CastShadow = false
	bill.Material = Enum.Material.SmoothPlastic
	bill.TopSurface = Enum.SurfaceType.Smooth
	bill.BottomSurface = Enum.SurfaceType.Smooth
	local jitter = CFrame.new(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
		* CFrame.Angles(0, math.rad(rng:NextNumber(-14, 14)), 0)
	if coin then
		bill.Shape = Enum.PartType.Cylinder
		bill.Size = Vector3.new(0.14, 0.6, 0.6)
		bill.Color = COIN_COLOR
		bill.Material = Enum.Material.Metal
		bill.CFrame = pile.CFrame
			* CFrame.new(x + 0.55, floorY + 0.09 + layer * 0.19, z + 0.3)
			* jitter
			* CFrame.Angles(0, 0, math.rad(90))
	else
		bill.Size = BILL_SIZE
		bill.Color = BILL_COLORS[(layer % 2) + 1]
		bill.CFrame = pile.CFrame * CFrame.new(x, floorY + 0.09 + layer * 0.19, z) * jitter
	end
	bill.Parent = state.billFolder
	state.bills[index] = bill
end

local function refreshCash(state: CounterState)
	local wanted = targetBills(state.cash)
	while #state.bills < wanted do
		addBill(state, #state.bills + 1)
	end
	while #state.bills > wanted do
		local bill = table.remove(state.bills)
		if bill then
			bill:Destroy()
		end
	end
	-- Montant du tas, lu par le client (TutorialController : fleche vers Collect Cash tant qu'il reste)
	state.floor:SetAttribute("PileCash", state.cash)
	local label = state.cashLabel
	if label then
		WorldLabel.SetVisible(label, state.cash > 0)
		WorldLabel.SetPlainText(label, "$" .. NumberFormat.Abbreviate(state.cash), CASH_COLOR)
	end
end

local function collect(player: Player, state: CounterState)
	if state.cash <= 0 or not PlayerCheck.Cooldown(player, "Cash", Gameplay.PadActionSeconds) then
		return
	end
	local amount = state.cash
	local bills = #state.bills
	if not MoneyService.Add(player, amount, "Sales") then
		return
	end
	state.cash = 0
	refreshCash(state)
	local pile = state.pile
	if feedbackEvent then
		feedbackEvent:FireClient(player, "Cash", {
			amount = amount,
			from = if pile then pile.Position else Vector3.zero,
			bills = bills,
		})
	end
end

---------------------------------------------------------------------------------------------
-- Ventes

-- Texte du panneau "MONEY / HOUR" (Counter.IncomeSign.Display.Value) d'un etage.
local function findIncomeLabel(floor: Model): TextLabel?
	local counter = floor:FindFirstChild("Counter")
	local sign = counter and counter:FindFirstChild("IncomeSign")
	local board = sign and sign:FindFirstChild("Board")
	local gui = board and board:FindFirstChild("Display")
	local label = gui and gui:FindFirstChild("Value")
	return if label and label:IsA("TextLabel") then label else nil
end

-- Argent gagne par heure : ventes des IncomeWindowSeconds dernieres secondes, ramenees a 1 h. Au
-- debut, on divise au moins par IncomeMinSeconds (pas de chiffre enorme apres 2 ventes).
local function updateIncome(state: CounterState)
	local now = os.clock()
	local window = Gameplay.IncomeWindowSeconds
	local total = 0
	local kept: { { t: number, amount: number } } = {}
	for _, sale in state.sales do
		if now - sale.t <= window then
			table.insert(kept, sale)
			total += sale.amount
		end
	end
	state.sales = kept
	local elapsed = math.clamp(now - state.startedAt, Gameplay.IncomeMinSeconds, window)
	local perHour = math.floor(total / elapsed * 3600 + 0.5)
	local label = state.incomeLabel
	if label then
		label.Text = "$" .. NumberFormat.Abbreviate(perHour)
	end
	state.floor:SetAttribute("IncomePerHour", perHour)
end

-- Verse `price` sur le tas de CET etage (ou au joueur avec Auto Collect).
-- Ecouteurs de chaque vente (RobuxShopService : surplus gagne pendant l'essai 3X CASH). Sans yield.
local saleListeners: { (player: Player, amount: number) -> () } = {}

function CustomerService.OnSale(callback: (player: Player, amount: number) -> ())
	table.insert(saleListeners, callback)
end

local function pay(state: CounterState, price: number)
	local player = state.player
	table.insert(state.sales, { t = os.clock(), amount = price })
	for _, listener in saleListeners do
		local ok, err = pcall(listener, player, price)
		if not ok then
			warn(`[CustomerService] OnSale : {err}`)
		end
	end
	-- Un tas d'argent par etage (2026-11-20). Etage sans table (vieille place) : directement au joueur.
	local auto = ownsAutoCollect(player)
	if auto or state.pile == nil then
		MoneyService.Add(player, price, "Sales:Auto")
		if feedbackEvent and auto then
			local from = state.pile or state.topArea
			feedbackEvent:FireClient(player, "AutoCash", {
				amount = price,
				from = if from then from.Position else Vector3.zero,
			})
		end
	else
		state.cash = math.min(state.cash + price, 1e15)
		refreshCash(state)
	end
end

-- Retire jusqu'a `count` jus du haut du comptoir et renvoie leur prix total, le nombre vendu et le
-- fruit du premier (rien n'est encore paye).
local function takeSold(state: CounterState, count: number): (number, number, string?)
	-- Multiplicateur du rebirth (x2, x3... : Config/Rebirth), du pass Billboard (x2) et des achats
	-- Robux (3X CASH, boost Money)
	local multiplier = sellMultiplier(state.player, true)
	if state.index >= 2 then
		-- Ascenseur (panneau Elevator de la terrasse) : plus d'argent par vente aux etages 2+ (2026-11-20)
		local data = DataService.GetData(state.player)
		multiplier *= FloorIncome.ElevatorBonus(if data then data.TowerUpgrades else nil)
	end
	local total = 0
	local sold = 0
	local firstFruit: string? = nil
	for _ = 1, count do
		local index = #state.cups
		local fruitId = table.remove(state.cups)
		if fruitId == nil then
			break
		end
		-- Pile : le dernier pose part en premier. Son modele n'existe que s'il etait dessine.
		local model = state.cupModels[index]
		state.cupModels[index] = nil
		if model then
			model:Destroy()
		end
		local fruit = Fruits.ById[fruitId]
		total += if fruit then math.floor(fruit.value * multiplier + 0.5) else 0
		sold += 1
		firstFruit = firstFruit or fruitId
	end
	return total, sold, firstFruit
end

-- Un client achete `count` jus (pass Greedy Customers : 2). Un seul effet de vente (le fruit du
-- premier jus, le montant total).
local function sellOne(state: CounterState, spot: number, count: number)
	local total, sold, firstFruit = takeSold(state, count)
	if sold == 0 then
		return
	end
	pay(state, total)
	LeaderboardService.AddJuicesSold(state.player, sold)
	-- Clients dessines seulement sur l'etage ou est le joueur (lot 5)
	if worldFxEvent and FloorService.IsLive(state.floor) then
		worldFxEvent:FireAllClients(state.floor, "Sale", { spot = spot, fruit = firstFruit, amount = total })
	end
end

-- Debit en nombres d'un etage (Lib/FloorIncome) avec les niveaux du joueur. `withBoosts` = avec les
-- boosts Robux temporaires (false pour les gains hors ligne ; les passes comptent toujours).
local function incomeOf(player: Player, index: number, withBoosts: boolean): FloorIncome.Result?
	local data = DataService.GetData(player)
	local levels = if data then DataService.FloorUpgrades(data, index) else nil
	if data == nil or levels == nil then
		return nil
	end
	-- Pass "Waiter Speed x10" (PassPadService) : attribut joueur (pas de require en cercle). Instant
	-- Sell ne compte pas ici : il ne vend que les jus poses par le joueur (2026-11-21).
	local result = FloorIncome.Compute(
		levels,
		index,
		data.TowerUpgrades,
		player:GetAttribute("SpeedBoost") == true,
		{
			luck = Perks.LuckMultiplier(player, withBoosts),
			customers = Perks.CustomerSpeedMultiplier(player, withBoosts) * Perks.JuicesPerCustomer(player),
		}
	)
	-- Multiplicateur du rebirth, du pass Billboard et des achats Robux, comme pour les ventes dessinees
	local multiplier = sellMultiplier(player, withBoosts)
	result.averageValue *= multiplier
	result.moneyPerSecond *= multiplier
	return result
end

-- Lot 5 : les etages ou le joueur n'est pas (et automatises) versent leur argent en nombres.
local function payNumbers(state: CounterState, dt: number)
	if FloorService.IsLive(state.floor) then
		state.numbersPending = 0
		state.juicesPending = 0
		return
	end
	local result = incomeOf(state.player, state.index, true)
	if result == nil or result.moneyPerSecond <= 0 then
		return
	end
	state.numbersPending += result.moneyPerSecond * dt
	state.juicesPending += result.juicesPerSecond * dt
	local juices = math.floor(state.juicesPending)
	if juices >= 1 then
		state.juicesPending -= juices
		LeaderboardService.AddJuicesSold(state.player, juices)
	end
	local whole = math.floor(state.numbersPending)
	if whole >= 1 then
		state.numbersPending -= whole
		pay(state, whole)
	end
	updateIncome(state)
end

local function runSales(state: CounterState)
	while state.active do
		-- (l'ascenseur ne change plus la vitesse des clients depuis le 2026-11-20 : il augmente le prix, sellOne)
		local seconds = getLevelValue(state.player, state.index, "CustomerSpeed")
		local slots = math.clamp(math.floor(getLevelValue(state.player, state.index, "CustomerCount")), 1, Gameplay.SaleMaxSpots)
		-- Boutique pas encore ouverte : aucun client (CustomerController n'en dessine pas)
		local open = SetupService.Allows(state.floor, 4)
		state.floor:SetAttribute("CustomerSlots", if open then slots else 0)
		if state.label then
			WorldLabel.SetVisible(state.label, open) -- pas de "x0" au-dessus du comptoir fantome
		end
		if not open then
			task.wait(0.25)
			continue
		end
		-- Achats Robux (Lib/Perks) : Speed Master et boost Speed = clients plus rapides ; Greedy
		-- Customers = 2 jus par client
		task.wait(math.max(seconds / Perks.CustomerSpeedMultiplier(state.player, true), 0.2))
		if not state.active then
			break
		end
		local ok, err = pcall(function()
			local perCustomer = Perks.JuicesPerCustomer(state.player)
			for spot = 1, slots do
				if #state.cups == 0 then
					break
				end
				sellOne(state, spot, perCustomer)
			end
			refreshCounter(state)
			updateIncome(state)
		end)
		if not ok then
			warn(`[CustomerService] Erreur de vente ({state.floor.Name}) : {err}`)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Actions du joueur

-- Comptoir de l'etage `index` de ce joueur (nil si pas charge).
local function counterStateOf(player: Player, index: number): CounterState?
	for _, other in states do
		if other.player == player and other.index == index then
			return other
		end
	end
	return nil
end

-- Pass Instant Sell : vend tout de suite jusqu'a `count` jus du haut du comptoir (ceux que le joueur
-- vient de poser, sauf si des clients en ont deja pris pendant l'animation).
local function instantSell(state: CounterState, count: number)
	if not state.active or #state.cups == 0 then
		return
	end
	local total, sold = takeSold(state, count)
	if sold == 0 then
		return
	end
	pay(state, total)
	LeaderboardService.AddJuicesSold(state.player, sold)
	refreshCounter(state)
	updateIncome(state)
	if feedbackEvent then
		feedbackEvent:FireClient(state.player, "InstantSell", { amount = total, count = sold })
	end
end

-- Duree de l'animation de depot de `count` gobelets (HandStackController : un saut de
-- InstantSellFlySeconds, un gobelet toutes les InstantSellStaggerSeconds), plafonnee.
local function dropAnimationSeconds(count: number): number
	local seconds = Gameplay.InstantSellFlySeconds + math.max(count - 1, 0) * Gameplay.InstantSellStaggerSeconds
	return math.min(seconds, Gameplay.InstantSellMaxWaitSeconds) + Gameplay.InstantSellExtraSeconds
end

-- Pad "Drop Juices" : les jus des mains vont sur le comptoir (la position est verifiee par la
-- boucle des pads). Le comptoir n'a pas de limite : tout ce qui est porte est pose.
local function placeJuices(state: CounterState)
	local player = state.player
	local count = ProductionService.GetHandCount(player)
	if count <= 0 then
		return
	end
	if not PlayerCheck.Cooldown(player, "Counter", Gameplay.PadActionSeconds) then
		return
	end
	local ids = ProductionService.TakeFromHands(player, count)
	if #ids == 0 then
		return
	end
	-- Les jus partent du haut du plateau de jus (sur la tete) : ids[k] etait a la place count - k + 1.
	local character = player.Character
	local from: { Vector3 }? = nil
	if character then
		local list: { Vector3 } = {}
		for k = 1, #ids do
			local slot = HandStack.WorldSlot(character, count - k + 1)
			if slot == nil then
				break
			end
			table.insert(list, slot.Position)
		end
		from = list
	end
	-- Chaque jus va sur le comptoir de l'etage de SON fruit (retour du 2026-11-20 soir) : on peut
	-- deposer a n'importe quel comptoir, les gobelets volent jusqu'au bon (PopFrom). Comptoir pas
	-- charge -> il reste ici.
	local groups: { [CounterState]: { ids: { string }, from: { Vector3 } } } = {}
	for k, id in ids do
		local fruit = Fruits.ById[id]
		local target = (fruit and counterStateOf(player, fruit.floor)) or state
		local group = groups[target]
		if group == nil then
			group = { ids = {}, from = {} }
			groups[target] = group
		end
		table.insert(group.ids, id)
		local start = from and from[k]
		if start then
			table.insert(group.from, start)
		end
	end
	local accepted = 0
	local instant = player:GetAttribute(INSTANT_ATTRIBUTE) == true
	for target, group in groups do
		local placed = addToCounter(target, group.ids, if #group.from == #group.ids then group.from else nil)
		accepted += placed
		if instant and placed > 0 then
			task.delay(dropAnimationSeconds(placed), function()
				local ok, err = pcall(instantSell, target, placed)
				if not ok then
					warn(`[CustomerService] Instant Sell : {err}`)
				end
			end)
		end
	end
	if feedbackEvent then
		feedbackEvent:FireClient(player, "PlaceJuice", { count = accepted })
	end
end

local function onAutoPadEnter(player: Player, state: CounterState)
	if ownsAutoCollect(player) then
		NotifyService.Notify(player, MESSAGES.AutoCollectOn)
	elseif autoCollectPass > 0 then
		PurchasePrompt.GamePass(player, autoCollectPass)
	else
		NotifyService.Notify(player, Upgrades.Messages.RobuxSoon)
	end
	local pad = state.autoPad
	if pad then
		local value = pad:GetAttribute("Touched")
		pad:SetAttribute("Touched", (if type(value) == "number" then value else 0) + 1)
	end
end

-- Etiquette du pad (style Util/RobuxPad) : icone Robux + prix, ou "ACTIVE".
local function refreshAutoPad(state: CounterState)
	local pad = state.autoPad
	if pad then
		RobuxPad.SetPrice(pad, autoCollectPrice, ownsAutoCollect(state.player))
	end
end

-- Pads (Drop Juices, Collect Cash, Robux Auto Collect) : le proprietaire se tient dessus.
-- 10 fois par seconde. Seul le proprietaire de l'etage declenche ses pads.
local function checkContacts(state: CounterState)
	local player = state.player
	local root = PlayerCheck.GetRoot(player)
	if root == nil then
		state.onAutoPad = false
		onJuicePad[player] = nil
		return
	end
	if DataService.GetData(player) == nil or not SetupService.Allows(state.floor, 4) then
		return
	end
	local juiceZone = state.juiceZone
	-- Pad Auto Collect sur chaque etage (2026-11-21) : drapeau "sur le pad" PAR ETAGE (state), sinon
	-- l'etage 2 effacerait celui de l'etage 1 a chaque tour et la fenetre d'achat se rouvrirait.
	local onJuice = juiceZone ~= nil and PlayerCheck.IsOver(juiceZone, root.Position)
	if onJuice then
		placeJuices(state)
		onJuicePad[player] = true
	end
	local cashZone = state.cashZone
	if cashZone and state.cash > 0 and PlayerCheck.IsOver(cashZone, root.Position) then
		collect(player, state)
	end
	local zone = state.autoZone
	if zone then
		local inside = PlayerCheck.IsOver(zone, root.Position)
		if inside and not state.onAutoPad then
			onAutoPadEnter(player, state)
		end
		state.onAutoPad = inside
	end
end

---------------------------------------------------------------------------------------------
-- Etages

local function startFloor(player: Player, floor: Model, index: number)
	if DataService.GetData(player) == nil or states[floor] ~= nil then
		return
	end
	local counter = floor:FindFirstChild("Counter")
	local dynamic = floor:FindFirstChild("Dynamic")
	if counter == nil or dynamic == nil then
		warn(`[CustomerService] {floor.Name} : Counter ou Dynamic manquant`)
		return
	end
	local function findPart(name: string): BasePart?
		local p = counter:FindFirstChild(name)
		return if p and p:IsA("BasePart") then p else nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Counter"
	folder.Parent = dynamic
	local billFolder = Instance.new("Folder")
	billFolder.Name = "Money"
	billFolder.Parent = folder
	local autoPad = counter:FindFirstChild("AutoCollectPad")
	local autoZone = autoPad and autoPad:FindFirstChild("PadZone")
	-- Zone (PadZone) d'un pad d'action du comptoir
	local function padZone(padName: string): BasePart?
		local pad = counter:FindFirstChild(padName)
		local zone = pad and pad:FindFirstChild("PadZone")
		if zone == nil or not zone:IsA("BasePart") then
			warn(`[CustomerService] {floor:GetFullName()} : Counter.{padName}.PadZone manquant`)
			return nil
		end
		return zone
	end

	local state: CounterState = {
		player = player,
		floor = floor,
		index = index,
		folder = folder,
		cups = {},
		cupModels = {},
		topArea = findPart("CounterTopArea"),
		juiceZone = padZone("JuiceDropPad"),
		cashZone = padZone("CashPad"),
		label = nil,
		cash = 0,
		bills = {},
		billFolder = billFolder,
		pile = findPart("MoneyPile"),
		cashLabel = nil,
		autoPad = if autoPad and autoPad:IsA("Model") then autoPad else nil,
		autoZone = if autoZone and autoZone:IsA("BasePart") then autoZone else nil,
		onAutoPad = false,
		sales = {},
		startedAt = os.clock(),
		numbersPending = 0,
		juicesPending = 0,
		incomeLabel = findIncomeLabel(floor),
		thread = nil,
		active = true,
	}
	local labelAnchor = findPart("CounterLabelAnchor")
	if labelAnchor then
		state.label = WorldLabel.Create(folder, labelAnchor, "CounterLabel", {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(6, 2),
		})
	end
	local moneyAnchor = findPart("MoneyLabelAnchor")
	if moneyAnchor then
		state.cashLabel = WorldLabel.Create(folder, moneyAnchor, "MoneyLabel", {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(7, 2.2),
		})
	end
	states[floor] = state
	refreshCounter(state)
	refreshCash(state)
	refreshAutoPad(state)
	updateIncome(state)
	state.thread = task.spawn(runSales, state)
end

local function stopFloor(floor: Model)
	local state = states[floor]
	if state == nil then
		return
	end
	states[floor] = nil
	state.active = false
	if state.thread and coroutine.status(state.thread) == "suspended" then
		task.cancel(state.thread)
	end
	floor:SetAttribute("CounterJuices", 0)
	floor:SetAttribute("CustomerSlots", 0)
	floor:SetAttribute("IncomePerHour", 0)
	floor:SetAttribute("PileCash", 0)
	local incomeLabel = findIncomeLabel(floor)
	if incomeLabel then
		incomeLabel.Text = "$0"
	end
end

local function checkPass(player: Player)
	if autoCollectPass <= 0 then
		return
	end
	local owns = GamePass.Owns(player, autoCollectPass) -- jamais vrai pour le createur (Lib/GamePass)
	if owns and player.Parent == Players then
		player:SetAttribute(AUTO_ATTRIBUTE, true) -- onAutoCollectChanged fait le reste
	end
end

-- Pass Auto Collect pris (achat, panneau admin, test) ou retire : etiquette du pad et tas d'argent.
-- Avec le pass, plus rien n'arrive sur les tas : on les encaisse tout de suite (avec l'effet de
-- billets pour l'etage ou est le joueur).
local function onAutoCollectChanged(player: Player)
	-- Etiquette "ACTIVE" / prix sur le pad de chaque etage du joueur (un pad par etage depuis le 2026-11-21)
	for _, state in states do
		if state.player == player then
			refreshAutoPad(state)
		end
	end
	if not ownsAutoCollect(player) then
		return
	end
	local floor = FloorService.GetPlayerFloor(player)
	local here = floor and states[floor]
	if here and here.player == player then
		PlayerCheck.ResetCooldown(player, "Cash")
		collect(player, here)
	end
	CustomerService.CollectPile(player)
end

-- Remote PadEnter : le client vient de monter sur un pad du comptoir (reaction immediate, sans
-- attendre la boucle des pads ni la position du personnage). Verifie : nom connu, son etage, position
-- (marge PadEnterMargin), delai. La boucle des pads continue tant qu'il reste dessus.
local function onPadEnter(player: Player, padName: any)
	if padName ~= "JuiceDrop" and padName ~= "Cash" then
		return
	end
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and states[floor]
	local root = PlayerCheck.GetRoot(player)
	if state == nil or state.player ~= player or root == nil or DataService.GetData(player) == nil then
		return
	end
	if not SetupService.Allows(floor :: Model, 4) then
		return
	end
	if not PlayerCheck.Cooldown(player, "PadEnter" .. padName, 0.15) then
		return
	end
	local zone = if padName == "JuiceDrop" then state.juiceZone else state.cashZone
	if zone == nil or not PlayerCheck.IsOver(zone, root.Position, Gameplay.PadEnterMargin) then
		return
	end
	if padName == "JuiceDrop" then
		placeJuices(state)
		onJuicePad[player] = true
	else
		collect(player, state)
	end
end

function CustomerService:Init()
	feedbackEvent = Remotes.GetServerEvent("Feedback")
	worldFxEvent = Remotes.GetServerEvent("WorldFx")
	Remotes.GetServerEvent("PadEnter")
end

function CustomerService:Start()
	FloorService.OnFloorStarted(startFloor)
	FloorService.OnFloorStopped(function(player: Player, floor: Model)
		onJuicePad[player] = nil
		stopFloor(floor)
	end)
	Remotes.GetServerEvent("PadEnter").OnServerEvent:Connect(function(player: Player, padName: any)
		local ok, err = pcall(onPadEnter, player, padName)
		if not ok then
			warn(`[CustomerService] Erreur de PadEnter : {err}`)
		end
	end)
	local function watchPlayer(player: Player)
		player:GetAttributeChangedSignal(AUTO_ATTRIBUTE):Connect(function()
			local ok, err = pcall(onAutoCollectChanged, player)
			if not ok then
				warn(`[CustomerService] Auto Collect : {err}`)
			end
		end)
		checkPass(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(watchPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		onJuicePad[player] = nil
	end)
	GamePass.OnPurchased(function(player: Player, passId: number) -- possession reverifiee
		if passId == autoCollectPass and autoCollectPass > 0 and player.Parent == Players then
			player:SetAttribute(AUTO_ATTRIBUTE, true) -- onAutoCollectChanged encaisse les tas
		end
	end)
	-- Pass offert (GiftService) : meme effet qu'un achat
	GamePass.OnGranted(function(player: Player, passId: number)
		if passId == autoCollectPass and autoCollectPass > 0 and player.Parent == Players then
			player:SetAttribute(AUTO_ATTRIBUTE, true)
		end
	end)

	-- Production en nombres des etages ou le joueur n'est pas (lot 5)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(FloorsConfig.IncomeTickSeconds)
			local now = os.clock()
			local dt = math.min(now - last, FloorsConfig.IncomeTickSeconds * 3)
			last = now
			for _, state in states do
				local ok, err = pcall(payNumbers, state, dt)
				if not ok then
					warn(`[CustomerService] Erreur de production en nombres : {err}`)
				end
			end
		end
	end)
	-- Attribut joueur IncomePerSecond (gains theoriques de toute la tour) : l'offre "argent tout de
	-- suite" de OffersController affiche le vrai montant ("+$1.2K") au lieu de "5 min of cash".
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local ok, value = pcall(CustomerService.GetIncomePerSecond, player)
				if ok then
					player:SetAttribute("IncomePerSecond", value)
				end
			end
			task.wait(Gameplay.IncomeAttributeSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Gameplay.ContactCheckSeconds)
			for _, state in states do
				local ok, err = pcall(checkContacts, state)
				if not ok then
					warn(`[CustomerService] Erreur de contact : {err}`)
				end
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- API (Waiter, rebirth, tests)

-- Encaisse les tas d'argent de TOUS les etages du joueur, sans delai ni effet (rebirth : l'argent
-- gagne n'est pas perdu avant le calcul ; achat d'Auto Collect). Renvoie le montant encaisse.
function CustomerService.CollectPile(player: Player): number
	local total = 0
	for _, state in states do
		if state.player == player and state.cash > 0 then
			local amount = math.floor(state.cash)
			if amount > 0 and MoneyService.Add(player, amount, "Sales") then
				state.cash = 0
				refreshCash(state)
				total += amount
			end
		end
	end
	return total
end

-- Pose des jus sur le comptoir (pas de limite). Renvoie le nombre pose (0 si l'etage n'est pas pret).
-- Vrai si le comptoir de l'etage est pret (AddToCounter ne perdra pas les jus).
function CustomerService.HasCounter(floor: Model): boolean
	return states[floor] ~= nil
end

-- `from` (optionnel) : d'ou chaque gobelet saute jusqu'a sa place (HandStackController).
function CustomerService.AddToCounter(floor: Model, ids: { string }, from: { Vector3 }?): number
	local state = states[floor]
	if state == nil then
		return 0
	end
	return addToCounter(state, ids, from)
end

-- Nombre de jus poses sur le comptoir de l'etage (0 si pas pret). Pass Thief (ThiefService).
function CustomerService.GetCounterCount(floor: Model): number
	local state = states[floor]
	return if state then #state.cups else 0
end

-- Pass Thief (ThiefService, 2026-11-27) : les `max` gobelets du haut du comptoir, SANS les retirer
-- (la victime ne perd rien). Renvoie ids, positions (effet de vol) et modeles (caches chez le voleur).
function CustomerService.PeekCounter(floor: Model, max: number): ({ string }, { Vector3 }, { Model })
	local state = states[floor]
	local ids: { string } = {}
	local from: { Vector3 } = {}
	local models: { Model } = {}
	if state == nil or max <= 0 then
		return ids, from, models
	end
	local last = #state.cups
	for index = last, math.max(1, last - max + 1), -1 do
		table.insert(ids, state.cups[index])
		local model = state.cupModels[index]
		if model and model.Parent then
			table.insert(from, model:GetPivot().Position)
			table.insert(models, model)
		else
			local cf = cupCFrame(state, index)
			local area = state.topArea
			table.insert(from, if cf then cf.Position elseif area then area.Position else Vector3.zero)
		end
	end
	return ids, from, models
end

-- Argent par seconde VRAIMENT gagne ces dernieres minutes (somme des panneaux MONEY / HOUR de ses
-- etages : ventes des IncomeWindowSeconds dernieres secondes). Packs d'argent Robux (RobuxShopService).
function CustomerService.GetRecentIncomePerSecond(player: Player): number
	local total = 0
	for _, state in states do
		if state.player == player and state.active then
			local perHour = state.floor:GetAttribute("IncomePerHour")
			if type(perHour) == "number" and perHour > 0 then
				total += perHour / 3600
			end
		end
	end
	return total
end

-- Argent par seconde de toute la tour du joueur si tous ses etages tournaient en nombres
-- (Lib/FloorIncome). Servira aux gains hors ligne : sans les boosts Robux temporaires (les passes
-- comptent). 0 si pas charge.
function CustomerService.GetIncomePerSecond(player: Player): number
	local data = DataService.GetData(player)
	if data == nil then
		return 0
	end
	local total = 0
	for n = 1, DataService.FloorsOwned(data) do
		local result = incomeOf(player, n, false)
		if result then
			total += result.moneyPerSecond
		end
	end
	return total
end

-- Detail par etage (tests).
function CustomerService.DebugIncome(player: Player): { any }
	local data = DataService.GetData(player)
	local list = {}
	for n = 1, if data then DataService.FloorsOwned(data) else 0 do
		local result = incomeOf(player, n, true)
		local floor = FloorService.GetFloor(player, n)
		table.insert(list, {
			floor = n,
			live = floor ~= nil and FloorService.IsLive(floor),
			automated = result and result.automated,
			perSecond = result and result.moneyPerSecond,
			bottleneck = result and result.bottleneck,
			average = result and result.averageValue,
		})
	end
	return list
end

-- Tests Studio
function CustomerService.DebugGet(player: Player): { [string]: any }?
	local floor = FloorService.GetPlayerFloor(player)
	local state = floor and states[floor]
	if state == nil then
		return nil
	end
	return {
		Floor = state.index,
		Counter = table.clone(state.cups),
		Cash = state.cash, -- tas de l'etage ou est le joueur
		Bills = #state.bills,
		AutoCollect = ownsAutoCollect(player),
	}
end

-- Tests (DebugService en Studio, panneau admin) : serveur seulement, les appelants verifient.
function CustomerService.DebugAction(player: Player, action: string, value: any): any
	-- Auto Collect : attribut joueur, marche partout (meme hors de l'usine)
	if action == "SetAutoCollect" then
		player:SetAttribute(AUTO_ATTRIBUTE, if value then true else nil)
		return ownsAutoCollect(player)
	end
	local floor = FloorService.GetPlayerFloor(player)
	local here = floor and states[floor]
	if here == nil then
		return false
	end
	-- Comptoir et tas d'argent de l'etage ou est le joueur (un tas par etage depuis le 2026-11-20).
	local state: CounterState = here
	if action == "Place" or action == "CashPad" then
		-- Teleporte sur le pad "Drop Juices" / "Collect Cash" : la boucle des pads agit ~0.1 s apres
		local zone = if action == "Place" then state.juiceZone else state.cashZone
		local root = PlayerCheck.GetRoot(player)
		if zone == nil or root == nil then
			return false
		end
		PlayerCheck.ResetCooldown(player, "Counter")
		PlayerCheck.ResetCooldown(player, "Cash")
		root.CFrame = CFrame.new(zone.Position.X, zone.Position.Y - zone.Size.Y / 2 + 3, zone.Position.Z)
		return true
	elseif action == "AddCash" and type(value) == "number" then
		state.cash += math.max(0, math.floor(value))
		refreshCash(state)
		return state.cash
	elseif action == "Collect" then
		collect(player, state)
		return true
	end
	return false
end

return CustomerService
