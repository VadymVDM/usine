--!strict
-- Contenu de la boutique (prix en Robux). Source : docs/game-design.md (Monetisation).
-- `productId` / `passId` = 0 tant que les produits ne sont pas crees sur Roblox.
-- Doc : docs/systems/interface.md (affichage), docs/systems/achats-robux.md (effets serveur)

export type Boost = {
	key: string,
	title: string,
	icon: string,
	color: Color3, -- bas du degrade
	color2: Color3, -- haut du degrade
	stat: string, -- "Money" | "Luck" | "Speed" (meme nom que les offres, RobuxShopService)
	mult: number, -- multiplicateur du boost (x2)
	options: { { minutes: number, price: number, productId: number } },
}

export type Pass = {
	key: string,
	title: string,
	lines: { string },
	icon: string,
	color: Color3,
	color2: Color3,
	price: number,
	passId: number,
	tag: string?,
	oldPrice: number?, -- prix barre : UNIQUEMENT pendant une vraie promotion
}

export type CashPack = {
	key: string,
	title: string,
	minutes: number, -- le pack donne X minutes des gains actuels du joueur
	minFloorShare: number, -- minimum = cette part du prix du prochain etage (gains encore faibles) [A VALIDER]
	price: number,
	productId: number,
	bestValue: boolean?,
	oldPrice: number?, -- prix barre : UNIQUEMENT pendant une vraie promotion
}

local Shop = {}

Shop.Boosts = {
	{
		key = "CustomerSpeed",
		title = "2x SPEED",
		stat = "Speed",
		mult = 2,
		icon = "PotionPurple",
		color = Color3.fromRGB(122, 28, 255),
		color2 = Color3.fromRGB(224, 112, 255),
		options = {
			{ minutes = 15, price = 9, productId = 0 },
			{ minutes = 30, price = 16, productId = 0 },
		},
	},
	{
		key = "Money",
		title = "2x MONEY",
		stat = "Money",
		mult = 2,
		icon = "PotionGreen",
		color = Color3.fromRGB(31, 168, 0),
		color2 = Color3.fromRGB(157, 255, 58),
		options = {
			{ minutes = 15, price = 9, productId = 0 },
			{ minutes = 30, price = 16, productId = 0 },
		},
	},
	{
		key = "Luck",
		title = "2x LUCK",
		stat = "Luck",
		mult = 2,
		icon = "PotionBlue",
		color = Color3.fromRGB(0, 74, 228),
		color2 = Color3.fromRGB(0, 255, 234),
		options = {
			{ minutes = 15, price = 9, productId = 0 },
			{ minutes = 30, price = 16, productId = 0 },
		},
	},
} :: { Boost }

-- Prix des passes : propositions de docs/game-design.md, a valider.
-- `oldPrice` (prix barre) : a mettre seulement si le prix a vraiment baisse (promo, evenement).
-- Un faux "ancien prix" jamais pratique est trompeur (regles Roblox sur les offres honnetes).
Shop.Passes = {
	{ key = "VIP", title = "VIP", lines = { "VIP name tag", "VIP chat tag" }, icon = "Vip", color = Color3.fromRGB(255, 140, 0), color2 = Color3.fromRGB(255, 238, 58), price = 149, passId = 0 },
	{ key = "Cash3x", title = "3X CASH", lines = { "Permanent", "3x money" }, icon = "Cash3x", color = Color3.fromRGB(31, 168, 0), color2 = Color3.fromRGB(157, 255, 58), price = 399, passId = 0, tag = "BEST" },
	{ key = "DrinkMaster", title = "DRINK MASTER", lines = { "2x chance of", "rare fruits" }, icon = "Clover", color = Color3.fromRGB(212, 90, 0), color2 = Color3.fromRGB(255, 176, 58), price = 249, passId = 0 },
	{ key = "GreedyCustomers", title = "GREEDY CUSTOMERS", lines = { "Customers buy", "2 drinks at a time" }, icon = "Customers", color = Color3.fromRGB(0, 128, 255), color2 = Color3.fromRGB(106, 224, 255), price = 199, passId = 0 },
	{ key = "SpeedMaster", title = "SPEED MASTER", lines = { "2x walk speed", "2x customer speed" }, icon = "Shoe", color = Color3.fromRGB(42, 60, 255), color2 = Color3.fromRGB(92, 184, 255), price = 99, passId = 0 },
	{ key = "AutoCollect", title = "AUTO COLLECT", lines = { "Cash goes straight", "to your wallet" }, icon = "Magnet", color = Color3.fromRGB(224, 0, 48), color2 = Color3.fromRGB(255, 122, 92), price = 149, passId = 0 },
	-- Instant Sell (2026-11-21, ancien "Auto Sell") : pad violet a droite du pad Drop Juices
	-- (PassPadService) ; les jus poses sur le comptoir sont vendus tout de suite (CustomerService).
	{ key = "InstantSell", title = "INSTANT SELL", lines = { "Juices sell as soon", "as you drop them" }, icon = "Customers", color = Color3.fromRGB(0, 168, 120), color2 = Color3.fromRGB(80, 240, 180), price = 199, passId = 0 },
	-- Pads violets dans l'usine (PassPadService, 2026-11-20, prix A VALIDER) : Speed x10 a cote de
	-- Take Juices (apres le Waiter), Billboard dans la cour (99 R$ comme la capture de reference).
	{ key = "SpeedBoost", title = "WAITER SPEED x10", lines = { "10x waiter speed", "Permanent" }, icon = "Shoe", color = Color3.fromRGB(0, 120, 255), color2 = Color3.fromRGB(0, 230, 255), price = 149, passId = 0 },
	{ key = "Billboard", title = "BILLBOARD", lines = { "2x sell price", "Permanent" }, icon = "Cash", color = Color3.fromRGB(255, 120, 0), color2 = Color3.fromRGB(255, 220, 40), price = 99, passId = 0 },
	{ key = "Thief", title = "THIEF", lines = { "Steal ready drinks", "from other stands" }, icon = "Thief", color = Color3.fromRGB(90, 0, 200), color2 = Color3.fromRGB(195, 77, 255), price = 149, passId = 0, tag = "OP" },
	{ key = "RebirthMaster", title = "REBIRTH MASTER", lines = { "Keep your tree", "level on rebirth" }, icon = "Rebirth", color = Color3.fromRGB(255, 0, 122), color2 = Color3.fromRGB(255, 138, 216), price = 299, passId = 0 },
} :: { Pass }

-- Prix des packs : propositions de docs/game-design.md, a valider.
Shop.CashPacks = {
	{ key = "Cash5m", title = "CASH - 5 minutes", minutes = 5, minFloorShare = 0.25, price = 25, productId = 0 },
	{ key = "Cash30m", title = "CASH - 30 minutes", minutes = 30, minFloorShare = 0.5, price = 79, productId = 0 },
	{ key = "Cash3h", title = "CASH - 3 hours", minutes = 180, minFloorShare = 1, price = 199, productId = 0 },
	{ key = "Cash10h", title = "CASH - 10 hours", minutes = 600, minFloorShare = 2.5, price = 499, productId = 0, bestValue = true },
} :: { CashPack }

-- Ecran "Welcome Back!" (gains hors ligne) : bouton x2 en Robux (docs/game-design.md : 9 R$).
Shop.OfflineDouble = { price = 9, productId = 0 }

-- Offres limitees a droite de l'ecran (OffersController). Choix utilisateur 2026-11-20 :
-- UNE seule offre a la fois, visible `OnSeconds` (3 min, minuteur rouge), puis elle disparait ;
-- `OffSeconds` (30 s) plus tard, une autre offre arrive. Pas d'etiquette de reduction : juste le temps.
-- Calendrier propre a chaque joueur (compte depuis son arrivee) :
--   * rien pendant `FirstDelaySeconds` (le joueur decouvre d'abord le jeu) ;
--   * 1re offre = `FirstOffer` (petit prix, pour un premier achat facile) ;
--   * ensuite `Pool` a tour de role, en partant d'un endroit au hasard.
-- Contenu d'une offre = `rewards`, montre en IMAGES dans la fenetre (pas de phrase, lisible par un
-- enfant) : icone + "x2" en gros + "15 MIN" ; un paquet d'argent montre le vrai montant ("+$1.2K",
-- calcule avec les gains actuels du joueur). `badge` = gros texte pose sur l'icone de l'offre a droite
-- ("x2") ; sans badge, une offre d'argent seule y montre son vrai montant (jamais "$$$").
--   { kind = "Boost", stat = "Money" | "Luck" | "Speed", mult = 2, minutes = 15 }
--   { kind = "Cash", minutes = 5, floorShare = 0.06 } -- argent tout de suite, adapte a l'etage :
--     minutes x gains theoriques IncomePerSecond, PLAFONNE a floorShare x prix du prochain etage
--     du joueur (Floors.Prices). Ex. Mega Cash 0.5 : au plus $750 a l'etage 1, 5.5K a l'etage 2...
--     (courbe des etages du 2026-11-20 ; le minimum $1K du Starter Pack, demande utilisateur, est garde)
--     (2026-11-20 : avant, le plus grand des deux -> ~$44K a l'etage 1, "beaucoup trop").
--     `minAmount` (optionnel) = montant minimum (Starter Pack : jamais moins de $1K au debut).
-- Nouvelle offre : elle apparait d'abord en grand au milieu de l'ecran, puis file a sa place a droite.
-- Chaque offre a son propre produit Robux (`productId`, 0 = pas encore cree : "coming soon").
-- Remise des `rewards` par RobuxShopService a la reception du paiement (2026-11-20).
Shop.LimitedOffers = {
	FirstDelaySeconds = 15, -- 2026-11-21 : Starter Pack 15 s apres l'ecran de chargement (le joueur a vu le jeu)
	OnSeconds = 3 * 60,
	OffSeconds = 30,
	FirstOffer = {
		key = "OfferStarter",
		title = "Starter Pack",
		oneTime = true, -- 2026-11-21 : achetable une seule fois (sauvegarde BoughtOffers), plus propose ensuite
		icon = "Gift",
		price = 19,
		rewards = { { kind = "Boost", stat = "Money", mult = 2, minutes = 15 }, { kind = "Cash", minutes = 5, floorShare = 0.06, minAmount = 1000 } },
		productId = 0,
	},
	Pool = {
		{ key = "OfferMoneyRush", title = "Money Rush", icon = "Cash", badge = "x3", price = 15, rewards = { { kind = "Boost", stat = "Money", mult = 3, minutes = 10 } }, productId = 0 },
		{ key = "OfferLuckyHour", title = "Lucky Hour", icon = "Clover", badge = "x2", price = 29, rewards = { { kind = "Boost", stat = "Luck", mult = 2, minutes = 60 } }, productId = 0 },
		{ key = "OfferRush", title = "Customer Rush", icon = "Shoe", badge = "x3", price = 15, rewards = { { kind = "Boost", stat = "Speed", mult = 3, minutes = 10 } }, productId = 0 },
		{ key = "OfferMegaCash", title = "Mega Cash", icon = "Cash", price = 99, minCycle = 3, rewards = { { kind = "Cash", minutes = 60, floorShare = 0.5 } }, productId = 0 }, -- minCycle 3 : pas avant ~10 min de jeu (99 R$)
		{
			key = "OfferTriple",
			title = "Triple Boost",
			icon = "PotionPurple",
			badge = "x2",
			price = 35,
			rewards = {
				{ kind = "Boost", stat = "Money", mult = 2, minutes = 20 },
				{ kind = "Boost", stat = "Luck", mult = 2, minutes = 20 },
				{ kind = "Boost", stat = "Speed", mult = 2, minutes = 20 },
			},
			productId = 0,
		},
		{ key = "OfferRareRain", title = "Rare Rain", icon = "Clover", badge = "x5", price = 19, rewards = { { kind = "Boost", stat = "Luck", mult = 5, minutes = 5 } }, productId = 0 },
	},
}

-- Effets des passes (RobuxShopService pose l'attribut joueur du meme nom ; Lib/Perks lit les effets).
-- Les autres passes ont leur propre service : AutoCollect (CustomerService),
-- InstantSell / SpeedBoost / Billboard (PassPadService), Thief (ThiefService),
-- RebirthMaster (RebirthService).
Shop.PassEffects = table.freeze({
	Cash3xMoney = 3, -- 3X CASH : argent des ventes x3
	DrinkMasterLuck = 2, -- DRINK MASTER : chance des fruits rares x2
	GreedyJuices = 2, -- GREEDY CUSTOMERS : jus achetes par client
	SpeedMasterWalk = 2, -- SPEED MASTER : vitesse de marche x2
	SpeedMasterCustomers = 2, -- SPEED MASTER : clients x2 plus rapides
})
-- Passes donnes par RobuxShopService (attribut joueur = cle du pass).
Shop.ServicePasses = table.freeze({ "VIP", "Cash3x", "DrinkMaster", "GreedyCustomers", "SpeedMaster" })

-- Boosts (RobuxShopService) : temps restant sauvegarde, il ne descend que pendant le jeu.
-- Meme stat, meme multiplicateur : les temps s'additionnent. Multiplicateurs differents (x2 boutique
-- + x3 Money Rush) : le plus fort tourne d'abord, les autres attendent (rien n'est perdu).
Shop.BoostStats = table.freeze({ "Money", "Luck", "Speed" })
Shop.BoostMaxSeconds = 7 * 24 * 3600 -- plafond du temps stocke par stat et multiplicateur (filet de securite)
Shop.PendingSeconds = 120 -- montant d'argent montre au clic garde X s (le recu donne ce montant)
Shop.ReceiptWaitSeconds = 20 -- attente max du chargement de la sauvegarde a la reception d'un recu
Shop.BuyCooldownSeconds = 0.5 -- delai entre deux clics d'achat (remote ShopBuy)

Shop.Messages = table.freeze({
	ComingSoon = "Robux purchases: coming soon!",
	GiftSoon = "Gifts: coming soon!",
	AlreadyOwned = "You already own this pass!",
	AlreadyBought = "You already got this offer!",
	BoostOn = "%s x%d for %d min!", -- "MONEY x2 for 15 min!"
	CashGot = "+%s cash!",
	PassOn = "%s unlocked!",
})
Shop.StatNames = table.freeze({ Money = "MONEY", Luck = "LUCK", Speed = "SPEED" })

return Shop
