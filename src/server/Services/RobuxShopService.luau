--!strict
-- Effets des achats Robux de la boutique et des offres limitees (2026-11-20). Contenu : Config/Shop.
--   * Developer Products (recus, ReceiptService) : boosts x2 de la boutique (Money, Speed des
--     clients, Luck ; 15 / 30 min), packs d'argent ("X minutes de profit"), offres limitees
--     (Starter Pack, Money Rush, Lucky Hour, Customer Rush, Mega Cash, Triple Boost, Rare Rain).
--     Chaque recu est donne UNE seule fois (DataService.GrantPurchaseOnce).
--   * GamePasses : VIP, 3X CASH, DRINK MASTER, GREEDY CUSTOMERS, SPEED MASTER (Shop.ServicePasses) ;
--     attribut joueur du meme nom pose ICI seulement. Effets lus par Lib/Perks (CustomerService,
--     TreeService, PlayerUpgradeService) et Lib/NameTag (VIP). Rien de sauvegarde : Roblox garde le pass.
--   * Boosts : Data.Boosts = secondes restantes par stat et multiplicateur (sauvegarde ; le temps ne
--     descend que pendant le jeu). Le plus fort multiplicateur d'une stat tourne, les autres attendent.
--     Attributs joueur "Boost<Stat>" (multiplicateur actif) et "Boost<Stat>End" (fin, en
--     workspace:GetServerTimeNow) pour l'affichage (BoostHudController).
--   * Montants d'argent (packs, offres) : calcules ICI (gains recents reels, voir cashAmount) et
--     montres au client par les attributs joueur "Cash_<cle>" ; le client n'affiche que.
--   * Remote ShopBuy (client -> serveur) : (kind, key, isGift) ; verifie type, cle connue, delai ;
--     note le montant montre puis ouvre la fenetre d'achat Roblox (id 0 : "coming soon").
-- Les autres passes ont leur service (AutoCollect : CustomerService, PassPadService,
-- ThiefService, RebirthService) : ShopBuy ne fait qu'ouvrir leur fenetre d'achat.
-- Doc : docs/systems/achats-robux.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Shop = require(Config:WaitForChild("Shop"))
local FloorsConfig = require(Config:WaitForChild("Floors"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))

local GamePass = require(script.Parent.Parent.Lib.GamePass)
local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local NameTag = require(script.Parent.Parent.Lib.NameTag)
local Perks = require(script.Parent.Parent.Lib.Perks)
local CustomerService = require(script.Parent.CustomerService)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local ReceiptService = require(script.Parent.ReceiptService)

local RobuxShopService = {}

type Reward = {
	kind: string, -- "Boost" | "Cash"
	stat: string?,
	mult: number?,
	minutes: number,
	floorShare: number?, -- Cash : plafond = part du prix du prochain etage
	minFloorShare: number?, -- Cash : minimum = part du prix du prochain etage
	minAmount: number?, -- Cash : minimum en $
}

type Entry = {
	kind: string, -- "Boost" | "CashPack" | "Offer"
	key: string, -- Boost : "<cle>_<minutes>" (ex. "Money_15")
	productId: number,
	rewards: { Reward },
	oneTime: boolean?, -- Offer : achetable une seule fois (data.BoughtOffers)
}

type Pending = { amounts: { [number]: number }, at: number }

local MESSAGES = Shop.Messages
local KNOWN_STATS: { [string]: boolean } = {}
for _, stat in Shop.BoostStats do
	KNOWN_STATS[stat] = true
end

-- Catalogue des produits : par "kind:key" (remote ShopBuy) et par productId (recus).
local entries: { [string]: Entry } = {}
local byProduct: { [number]: Entry } = {}

local function addEntry(entry: Entry)
	entries[entry.kind .. ":" .. entry.key] = entry
	if entry.productId > 0 then
		byProduct[entry.productId] = entry
	end
end

for _, boost in Shop.Boosts do
	assert(KNOWN_STATS[boost.stat], `Shop : stat de boost inconnue {boost.stat}`)
	for _, option in boost.options do
		addEntry({
			kind = "Boost",
			key = `{boost.key}_{option.minutes}`,
			productId = option.productId,
			rewards = { { kind = "Boost", stat = boost.stat, mult = boost.mult, minutes = option.minutes } },
		})
	end
end
for _, pack in Shop.CashPacks do
	addEntry({
		kind = "CashPack",
		key = pack.key,
		productId = pack.productId,
		rewards = { { kind = "Cash", minutes = pack.minutes, minFloorShare = pack.minFloorShare } },
	})
end
local offerList: { any } = { Shop.LimitedOffers.FirstOffer }
for _, offer in Shop.LimitedOffers.Pool do
	table.insert(offerList, offer)
end
for _, offer in offerList do
	local rewards: { Reward } = {}
	for _, reward in offer.rewards do
		assert(reward.kind ~= "Boost" or KNOWN_STATS[reward.stat], `Shop : stat de boost inconnue dans {offer.key}`)
		-- Un paquet d'argent sans minimum vaudrait $0 pour un joueur sans gains recents ("+$0").
		assert(
			reward.kind ~= "Cash" or (reward.minAmount or 0) > 0 or (reward.minFloorShare or 0) > 0,
			`Shop : recompense Cash sans minAmount ni minFloorShare dans {offer.key}`
		)
		table.insert(rewards, {
			kind = reward.kind,
			stat = reward.stat,
			mult = reward.mult,
			minutes = reward.minutes,
			floorShare = reward.floorShare,
			minFloorShare = reward.minFloorShare,
			minAmount = reward.minAmount,
		})
	end
	addEntry({ kind = "Offer", key = offer.key, productId = offer.productId, rewards = rewards, oneTime = offer.oneTime == true })
end

-- Passes donnes ici : cle -> passId (0 = pas encore cree)
local servicePasses: { [string]: number } = {}
for _, key in Shop.ServicePasses do
	servicePasses[key] = 0
end
local allPasses: { [string]: number } = {}
local passTitles: { [string]: string } = {}
for _, pass in Shop.Passes do
	allPasses[pass.key] = pass.passId
	passTitles[pass.key] = pass.title
	if servicePasses[pass.key] ~= nil then
		servicePasses[pass.key] = pass.passId
	end
end

local pending: { [Player]: { [string]: Pending } } = {}
local lastEnd: { [Player]: { [string]: number } } = {}
-- Boost gratuit (Shop.FreeBoost) : secondes de jeu avant le prochain, par joueur (session seulement).
local freeBoostIn: { [Player]: number } = {}
-- Essai gratuit de 3X CASH (Shop.Cash3xTrial) : secondes avant l'essai (nil = deja fait cette session),
-- puis essai en cours (temps restant, surplus gagne grace a l'essai).
local trialIn: { [Player]: number } = {}
local trialActive: { [Player]: { left: number, earned: number } } = {}
-- Lots de passes (Shop.Bundles)
local bundlesByKey: { [string]: any } = {}
local bundleByProduct: { [number]: any } = {}
for _, bundle in Shop.Bundles do
	bundlesByKey[bundle.key] = bundle
	if bundle.productId > 0 then
		bundleByProduct[bundle.productId] = bundle
	end
end
local feedbackEvent: RemoteEvent? = nil

---------------------------------------------------------------------------------------------
-- Montants d'argent

-- Prix du prochain etage (tour complete : dernier prix x UpgradePriceFactor), comme
-- OffersController jusqu'au 2026-11-20.
local function nextFloorPrice(data: DataService.PlayerData): number
	local prices = FloorsConfig.Prices
	local n = DataService.FloorsOwned(data) + 1
	if n <= #prices then
		return prices[n]
	end
	return prices[#prices] * FloorsConfig.UpgradePriceFactor
end

-- Argent par seconde servant de base : le plus grand des gains VRAIMENT faits ces dernieres minutes
-- (panneaux MONEY / HOUR) et des gains theoriques des etages automatises (sans boost temporaire).
-- 2026-11-23 : les ventes reelles comptent les boosts en cours ; on les retire (boost Money et Speed)
-- pour qu'un boost x3 + un pack ne donne pas un pack x3 (les passes, eux, restent comptes).
local function incomeBasis(player: Player): number
	local okRecent, recent = pcall(CustomerService.GetRecentIncomePerSecond, player)
	local okTheory, theory = pcall(CustomerService.GetIncomePerSecond, player)
	local boostFactor = (Perks.MoneyMultiplier(player, true) / Perks.MoneyMultiplier(player, false))
		* (Perks.CustomerSpeedMultiplier(player, true) / Perks.CustomerSpeedMultiplier(player, false))
	local real = if okRecent and recent == recent then recent / math.max(boostFactor, 1) else 0
	local basis = math.max(real, if okTheory and theory == theory then theory else 0)
	return if basis == basis and basis < math.huge then basis else 0
end

-- Montant d'une recompense d'argent maintenant (nil si la sauvegarde n'est pas chargee).
local function cashAmount(player: Player, reward: Reward): number?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local price = nextFloorPrice(data)
	local amount = incomeBasis(player) * reward.minutes * 60
	if reward.floorShare and reward.floorShare > 0 then
		amount = math.min(amount, reward.floorShare * price)
	end
	if reward.minFloorShare and reward.minFloorShare > 0 then
		amount = math.max(amount, reward.minFloorShare * price)
	end
	amount = math.max(amount, reward.minAmount or 0)
	-- Jamais $0 (filet de securite, la config impose deja un minimum) : 1 % du prochain etage.
	amount = math.max(amount, price * 0.01, 1)
	return math.clamp(math.floor(amount), 1, GameConfig.MaxMoney)
end

-- Montants des recompenses d'argent d'un produit (index de la recompense -> $). nil si pas charge.
local function entryAmounts(player: Player, entry: Entry): { [number]: number }?
	local amounts: { [number]: number } = {}
	for i, reward in entry.rewards do
		if reward.kind == "Cash" then
			local amount = cashAmount(player, reward)
			if amount == nil then
				return nil
			end
			amounts[i] = amount
		end
	end
	return amounts
end

-- Attributs "Cash_<cle>" (montant total d'argent de chaque pack / offre) pour l'affichage.
local function refreshCashAttributes(player: Player)
	if player.Parent ~= Players or DataService.GetData(player) == nil then
		return
	end
	for _, entry in entries do
		if entry.kind ~= "Boost" then
			local amounts = entryAmounts(player, entry)
			if amounts and next(amounts) ~= nil then
				local total = 0
				for _, amount in amounts do
					total += amount
				end
				player:SetAttribute("Cash_" .. entry.key, total)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Boosts

local function tierKey(mult: number): string
	return "x" .. tostring(mult)
end

-- Multiplicateur actif d'une stat (le plus fort) et ses secondes restantes.
local function activeTier(data: DataService.PlayerData, stat: string): (number?, number)
	local tiers = data.Boosts[stat]
	if tiers == nil then
		return nil, 0
	end
	local best: number? = nil
	local seconds = 0
	for key, left in tiers do
		local mult = tonumber(string.match(key, "^x(%d+)$"))
		if mult and left > 0 and (best == nil or mult > best) then
			best, seconds = mult, left
		end
	end
	return best, seconds
end

-- Attributs Boost<Stat> / Boost<Stat>End. La fin n'est reecrite que si elle bouge de plus d'1 s.
local function publishBoosts(player: Player, data: DataService.PlayerData)
	if player.Parent ~= Players then
		return
	end
	local ends = lastEnd[player]
	if ends == nil then
		ends = {}
		lastEnd[player] = ends
	end
	local now = workspace:GetServerTimeNow()
	for _, stat in Shop.BoostStats do
		local mult, seconds = activeTier(data, stat)
		player:SetAttribute("Boost" .. stat, mult)
		if mult == nil then
			ends[stat] = nil
			player:SetAttribute("Boost" .. stat .. "End", nil)
		else
			local finish = now + seconds
			local previous = ends[stat]
			if previous == nil or math.abs(previous - finish) > 1 then
				ends[stat] = finish
				player:SetAttribute("Boost" .. stat .. "End", finish)
			end
		end
	end
end

-- Ajoute du temps a un boost (cumul). Pas de yield.
local function addBoost(data: DataService.PlayerData, stat: string, mult: number, seconds: number)
	local tiers = data.Boosts[stat]
	if tiers == nil then
		tiers = {}
		data.Boosts[stat] = tiers
	end
	local key = tierKey(mult)
	tiers[key] = math.min((tiers[key] or 0) + seconds, Shop.BoostMaxSeconds)
end

-- Fait descendre le temps du boost actif de chaque stat.
local function tickBoosts(player: Player, data: DataService.PlayerData, dt: number)
	for _, stat in Shop.BoostStats do
		local mult = activeTier(data, stat)
		local tiers = data.Boosts[stat]
		if mult and tiers then
			local key = tierKey(mult)
			local left = (tiers[key] or 0) - dt
			tiers[key] = if left > 0 then left else nil
			if next(tiers) == nil then
				data.Boosts[stat] = nil
			end
		end
	end
	publishBoosts(player, data)
end

-- Boost gratuit : le compte a rebours ne tourne pas pendant la cinematique d'ouverture (attribut
-- "IntroPending", IntroService) : pour un profil neuf il demarre avec le tuto. Pas de yield.
local function tickFreeBoost(player: Player, data: DataService.PlayerData, dt: number)
	local left = freeBoostIn[player]
	if left == nil or player:GetAttribute("IntroPending") == true then
		return
	end
	left -= dt
	if left > 0 then
		freeBoostIn[player] = left
		return
	end
	local free = Shop.FreeBoost
	addBoost(data, free.stat, free.mult, free.minutes * 60)
	publishBoosts(player, data)
	freeBoostIn[player] = free.minutes * 60 + free.gapSeconds
	local name = Shop.StatNames[free.stat] or free.stat
	NotifyService.Notify(player, string.format(MESSAGES.FreeBoostOn, name, free.mult, free.minutes))
end

---------------------------------------------------------------------------------------------
-- Essai gratuit de 3X CASH (Shop.Cash3xTrial)

local function ownsCash3x(player: Player, data: DataService.PlayerData): boolean
	return player:GetAttribute(Shop.Cash3xTrial.passKey) == true or data.GiftedPasses[Shop.Cash3xTrial.passKey] == true
end

local function stopTrial(player: Player)
	trialActive[player] = nil
	if player.Parent == Players then
		player:SetAttribute("Cash3xTrialEnd", nil)
	end
end

-- Meme pause que le boost gratuit pendant la cinematique. Pas de yield.
local function tickTrial(player: Player, data: DataService.PlayerData, dt: number)
	local trial = Shop.Cash3xTrial
	local active = trialActive[player]
	if active then
		active.left -= dt
		if active.left > 0 then
			return
		end
		local earned = math.floor(active.earned)
		stopTrial(player)
		-- Fenetre de fin (DealController) seulement s'il a vraiment gagne quelque chose
		if earned > 0 and feedbackEvent and not ownsCash3x(player, data) then
			feedbackEvent:FireClient(player, "TrialEnd", { pass = trial.passKey, earned = earned })
		end
		return
	end
	local left = trialIn[player]
	if left == nil or player:GetAttribute("IntroPending") == true then
		return
	end
	left -= dt
	if left > 0 then
		trialIn[player] = left
		return
	end
	trialIn[player] = nil -- une fois par session
	if ownsCash3x(player, data) then
		return
	end
	trialActive[player] = { left = trial.seconds, earned = 0 }
	player:SetAttribute("Cash3xTrialEnd", workspace:GetServerTimeNow() + trial.seconds)
	NotifyService.Notify(player, string.format(MESSAGES.TrialOn, math.floor(trial.seconds / 60)))
end

-- Chaque vente pendant l'essai : surplus du a l'essai = vente x (1 - 1 / mult) (multiplications).
local function onSale(player: Player, amount: number)
	local active = trialActive[player]
	if active and amount > 0 and amount == amount and Perks.InCash3xTrial(player) then
		active.earned += amount * (1 - 1 / Shop.Cash3xTrial.mult)
	end
end

---------------------------------------------------------------------------------------------
-- Lots de passes (Shop.Bundles) : donnes comme des cadeaux (Data.GiftedPasses)

local function ownsAnyOf(player: Player, bundle: any): boolean
	for _, key in bundle.passes do
		local passId = allPasses[key]
		if passId and passId > 0 and GamePass.Owns(player, passId) then
			return true
		end
	end
	return false
end

-- Attribut "BundleBlocked_<cle>" : la boutique affiche OWNED (peut attendre Roblox : a lancer a part).
local function refreshBundles(player: Player)
	for _, bundle in Shop.Bundles do
		local blocked = ownsAnyOf(player, bundle)
		if player.Parent == Players then
			player:SetAttribute("BundleBlocked_" .. bundle.key, if blocked then true else nil)
		end
	end
end

local function bundleReceipt(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local bundle = bundleByProduct[receipt.ProductId]
	if player == nil or bundle == nil then
		return false
	end
	local deadline = os.clock() + Shop.ReceiptWaitSeconds
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	if DataService.GetData(player) == nil then
		return false
	end
	local applied = false
	local granted = DataService.GrantPurchaseOnce(player, receipt.PurchaseId, function(data): boolean
		for _, key in bundle.passes do
			data.GiftedPasses[key] = true
		end
		applied = true
		return true
	end)
	if applied then
		print(`[RobuxShopService] Lot {bundle.key} donne a {player.UserId} ({receipt.PurchaseId})`)
		for _, key in bundle.passes do
			local passId = allPasses[key]
			if passId and passId > 0 then
				GamePass.FireGranted(player, passId)
			end
		end
		NotifyService.Notify(player, string.format(MESSAGES.PassOn, bundle.title))
		task.spawn(refreshBundles, player)
	end
	return granted
end

---------------------------------------------------------------------------------------------
-- Offres uniques achetees : attribut joueur "Bought_<cle>" = true (OffersController ne les propose plus).
local function publishBoughtOffers(player: Player, data: DataService.PlayerData)
	if player.Parent ~= Players then
		return
	end
	for key in data.BoughtOffers do
		player:SetAttribute("Bought_" .. key, true)
	end
end

-- Remise d'un achat

-- Donne un produit (recu ou test). true = ecrit (ou deja donne pour ce PurchaseId).
local function grant(player: Player, entry: Entry, purchaseId: string): boolean
	local deadline = os.clock() + Shop.ReceiptWaitSeconds
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	if DataService.GetData(player) == nil then
		return false
	end
	-- Montant montre au clic s'il est recent (le joueur recoit ce qu'il a vu), sinon recalcule
	local list = pending[player]
	local shown = if list then list[entry.key] else nil
	local amounts = if shown and os.clock() - shown.at <= Shop.PendingSeconds then shown.amounts else entryAmounts(player, entry)
	if amounts == nil then
		return false
	end
	local applied = false
	local granted = DataService.GrantPurchaseOnce(player, purchaseId, function(data): boolean
		for i, reward in entry.rewards do
			if reward.kind == "Cash" then
				data.Money = math.min(data.Money + (amounts[i] or 0), GameConfig.MaxMoney)
			elseif reward.kind == "Boost" and reward.stat and reward.mult then
				addBoost(data, reward.stat, reward.mult, reward.minutes * 60)
			end
		end
		if entry.oneTime then
			data.BoughtOffers[entry.key] = true
		end
		applied = true
		return true
	end)
	if applied then
		if list then
			list[entry.key] = nil
		end
		local data = DataService.GetData(player)
		if data then
			publishBoosts(player, data)
			publishBoughtOffers(player, data)
		end
		MoneyService.SyncLeaderstats(player)
		if entry.kind == "Offer" and player.Parent == Players then
			-- Pour OffersController : retirer l'offre achetee de l'ecran. "<cle>#<n>" : change a chaque achat.
			player:SetAttribute("OfferBought", `{entry.key}#{math.floor(os.clock() * 1000)}`)
		end
		local cash = 0
		for i, reward in entry.rewards do
			if reward.kind == "Cash" then
				cash += amounts[i] or 0
			elseif reward.kind == "Boost" and reward.stat and reward.mult then
				local name = Shop.StatNames[reward.stat] or reward.stat
				NotifyService.Notify(player, string.format(MESSAGES.BoostOn, name, reward.mult, reward.minutes))
			end
		end
		if cash > 0 and player.Parent == Players then
			NotifyService.Notify(player, string.format(MESSAGES.CashGot, NumberFormat.Money(cash)))
			local root = PlayerCheck.GetRoot(player)
			if feedbackEvent then
				feedbackEvent:FireClient(player, "Cash", {
					amount = cash,
					from = if root then root.Position + Vector3.new(0, 2, 0) else nil,
					bills = 24,
				})
			end
		end
	end
	return granted
end

local function receiptHandler(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local entry = byProduct[receipt.ProductId]
	if player == nil or entry == nil then
		return false -- joueur parti : Roblox redonnera le recu
	end
	return grant(player, entry, receipt.PurchaseId)
end

---------------------------------------------------------------------------------------------
-- Passes

local function setPass(player: Player, key: string, owned: boolean)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(key, if owned then true else nil)
	if key == "VIP" then
		local data = DataService.GetData(player)
		NameTag.Apply(player, if data then data.Rebirths else 0)
	end
end

local function checkPasses(player: Player)
	for key, passId in servicePasses do
		if passId > 0 then
			local owns = GamePass.Owns(player, passId) -- jamais vrai pour le createur (Lib/GamePass)
			if owns then
				setPass(player, key, true)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Remote ShopBuy

local function onShopBuy(player: Player, kind: any, key: any, isGift: any)
	if type(kind) ~= "string" or type(key) ~= "string" or #kind > 20 or #key > 40 then
		return
	end
	if not PlayerCheck.Cooldown(player, "ShopBuy", Shop.BuyCooldownSeconds) then
		return
	end
	if isGift == true then
		-- Ancien client : les cadeaux passent par le remote ShopGift (GiftService) et un choix de joueur
		NotifyService.Notify(player, MESSAGES.GiftPickPlayer)
		return
	end
	if kind == "Bundle" then
		local bundle = bundlesByKey[key]
		if bundle == nil or DataService.GetData(player) == nil then
			return
		end
		if ownsAnyOf(player, bundle) then
			NotifyService.Notify(player, MESSAGES.BundleOwned)
			task.spawn(refreshBundles, player)
		elseif bundle.productId <= 0 then
			NotifyService.Notify(player, MESSAGES.ComingSoon)
		else
			PurchasePrompt.Product(player, bundle.productId)
		end
		return
	end
	if kind == "Pass" then
		local passId = allPasses[key]
		if passId == nil then
			return
		end
		local data = DataService.GetData(player)
		local gifted = data ~= nil and data.GiftedPasses[key] == true
		if player:GetAttribute(key) == true or gifted then
			NotifyService.Notify(player, MESSAGES.AlreadyOwned)
		elseif passId <= 0 then
			NotifyService.Notify(player, MESSAGES.ComingSoon)
		else
			PurchasePrompt.GamePass(player, passId)
		end
		return
	end
	local entry = entries[kind .. ":" .. key]
	if entry == nil then
		return
	end
	local data = DataService.GetData(player)
	if entry.oneTime and data and data.BoughtOffers[entry.key] then
		NotifyService.Notify(player, MESSAGES.AlreadyBought) -- deja achetee : pas de 2e fenetre de paiement
		return
	end
	-- Note le montant montre : le recu donnera celui-ci s'il arrive dans les PendingSeconds
	local amounts = entryAmounts(player, entry)
	if amounts and next(amounts) ~= nil then
		local list = pending[player]
		if list == nil then
			list = {}
			pending[player] = list
		end
		list[entry.key] = { amounts = amounts, at = os.clock() }
	end
	if entry.productId <= 0 then
		NotifyService.Notify(player, MESSAGES.ComingSoon)
		return
	end
	PurchasePrompt.Product(player, entry.productId)
end

---------------------------------------------------------------------------------------------
-- Tests (DebugService, Studio)

-- Simule un achat paye. kind = "Boost" | "CashPack" | "Offer", key = cle (Boost : "Money_15").
-- `purchaseId` optionnel : le meme deux fois = donne une seule fois.
function RobuxShopService.DebugGrant(player: Player, kind: string, key: string, purchaseId: string?): any
	local entry = entries[kind .. ":" .. key]
	if entry == nil then
		return "unknown product"
	end
	return grant(player, entry, purchaseId or ("debug-" .. tostring(os.clock())))
end

function RobuxShopService.DebugSetPass(player: Player, key: string, owned: boolean): any
	if servicePasses[key] == nil then
		return "unknown pass"
	end
	setPass(player, key, owned)
	return true
end

-- Etat : boosts sauvegardes, attributs, montants d'argent.
function RobuxShopService.DebugGet(player: Player): any
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local attributes: { [string]: any } = {}
	for name, value in player:GetAttributes() do
		if string.sub(name, 1, 5) == "Boost" or string.sub(name, 1, 5) == "Cash_" or string.sub(name, 1, 7) == "Bought_" or servicePasses[name] ~= nil then
			attributes[name] = value
		end
	end
	return {
		boosts = table.clone(data.Boosts),
		boughtOffers = table.clone(data.BoughtOffers),
		attributes = attributes,
		basis = incomeBasis(player),
		money = data.Money,
	}
end

-- Oublie les offres uniques achetees (pour retester le Starter Pack ; attributs retires).
function RobuxShopService.DebugClearOffers(player: Player): any
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	for key in data.BoughtOffers do
		player:SetAttribute("Bought_" .. key, nil)
	end
	table.clear(data.BoughtOffers)
	return true
end

-- Retire tous les boosts (remise du profil de test).
function RobuxShopService.DebugClearBoosts(player: Player): any
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	table.clear(data.Boosts)
	publishBoosts(player, data)
	return true
end

-- Avance le prochain boost gratuit a dans `seconds` s (0 = a la prochaine seconde). Renvoie l'ancien delai.
-- Essai 3X CASH dans `seconds` s (renvoie l'ancien delai) ; `trialSeconds` = duree de l'essai (test court).
function RobuxShopService.DebugTrial(player: Player, seconds: number?, trialSeconds: number?): any
	local old = trialIn[player]
	stopTrial(player)
	trialIn[player] = seconds or 0
	if trialSeconds then
		task.delay((seconds or 0) + 1.5, function()
			local active = trialActive[player]
			if active then
				active.left = trialSeconds
				player:SetAttribute("Cash3xTrialEnd", workspace:GetServerTimeNow() + trialSeconds)
			end
		end)
	end
	return old
end

-- Recu simule du lot `key` (ecrit la sauvegarde !).
function RobuxShopService.DebugBundle(player: Player, key: string, purchaseId: string): any
	local bundle = bundlesByKey[key]
	if bundle == nil then
		return "lot inconnu"
	end
	return bundleReceipt({
		PlayerId = player.UserId,
		ProductId = bundle.productId,
		PurchaseId = purchaseId,
		CurrencySpent = 0,
		PlaceIdWherePurchased = game.PlaceId,
	} :: any)
end

function RobuxShopService.DebugFreeBoost(player: Player, seconds: number?): any
	local old = freeBoostIn[player]
	if old == nil then
		return false
	end
	freeBoostIn[player] = seconds or 0
	return old
end

---------------------------------------------------------------------------------------------

function RobuxShopService:Init()
	Remotes.GetServerEvent("ShopBuy")
	for productId in byProduct do
		ReceiptService.Register(productId, receiptHandler)
	end
	for productId in bundleByProduct do
		ReceiptService.Register(productId, bundleReceipt)
	end
end

function RobuxShopService:Start()
	feedbackEvent = Remotes.GetServerEvent("Feedback")
	Remotes.GetServerEvent("ShopBuy").OnServerEvent:Connect(onShopBuy)
	DataService.OnPlayerLoaded(function(player: Player, data: DataService.PlayerData)
		publishBoosts(player, data)
		publishBoughtOffers(player, data)
		refreshCashAttributes(player)
		freeBoostIn[player] = Shop.FreeBoost.firstDelaySeconds
		trialIn[player] = Shop.Cash3xTrial.firstDelaySeconds
		task.spawn(refreshBundles, player)
	end)
	CustomerService.OnSale(onSale)
	Players.PlayerAdded:Connect(checkPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastEnd[player] = nil
		freeBoostIn[player] = nil
		trialIn[player] = nil
		trialActive[player] = nil
	end)
	local function onPassGranted(player: Player, id: number, notify: boolean)
		if id == allPasses[Shop.Cash3xTrial.passKey] then
			stopTrial(player) -- pass achete pendant l'essai : plus de fenetre de fin
		end
		task.spawn(refreshBundles, player)
		for key, passId in servicePasses do
			if passId > 0 and id == passId then
				setPass(player, key, true)
				if notify then
					NotifyService.Notify(player, string.format(MESSAGES.PassOn, passTitles[key] or key))
				end
			end
		end
	end
	-- Achat confirme par Roblox (GamePass.OnPurchased reverifie la possession)
	GamePass.OnPurchased(function(player: Player, id: number)
		onPassGranted(player, id, true)
	end)
	-- Pass offert (GiftService : cadeau recu ou sauvegarde chargee) : meme effet, message par GiftService
	GamePass.OnGranted(function(player: Player, id: number)
		onPassGranted(player, id, false)
	end)

	-- Temps des boosts (seulement pendant le jeu, sauvegarde chargee)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				local data = DataService.GetData(player)
				if data then
					local ok, err = pcall(tickBoosts, player, data, dt)
					if not ok then
						warn(`[RobuxShopService] boosts : {err}`)
					end
					local okFree, errFree = pcall(tickFreeBoost, player, data, dt)
					if not okFree then
						warn(`[RobuxShopService] boost gratuit : {errFree}`)
					end
					local okTrial, errTrial = pcall(tickTrial, player, data, dt)
					if not okTrial then
						warn(`[RobuxShopService] essai 3X CASH : {errTrial}`)
					end
				end
			end
		end
	end)
	-- Montants des packs et offres montres au client
	task.spawn(function()
		while true do
			task.wait(Gameplay.IncomeAttributeSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(refreshCashAttributes, player)
				if not ok then
					warn(`[RobuxShopService] montants : {err}`)
				end
			end
		end
	end)
end

return RobuxShopService
