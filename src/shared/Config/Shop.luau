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
	giftProductId: number, -- Developer Product "Gift - <pass>" (meme prix), GiftService ; 0 = pas de cadeau
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
			{ minutes = 15, price = 9, productId = 3734031035 },
			{ minutes = 30, price = 16, productId = 3734031053 },
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
			{ minutes = 15, price = 9, productId = 3734031057 },
			{ minutes = 30, price = 16, productId = 3734031061 },
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
			{ minutes = 15, price = 9, productId = 3734031066 },
			{ minutes = 30, price = 16, productId = 3734031073 },
		},
	},
} :: { Boost }

-- Prix des passes : propositions de docs/game-design.md, a valider.
-- 2026-11-23 (revue) : Drink Master 249 -> 199 (son vrai effet = ~+15 % d'argent + l'Index plus vite),
-- Rebirth Master 299 -> 199 (l'arbre n'est qu'une petite part des achats d'un etage).
-- `oldPrice` (prix barre) : a mettre seulement si le prix a vraiment baisse (promo, evenement).
-- Un faux "ancien prix" jamais pratique est trompeur (regles Roblox sur les offres honnetes).
Shop.Passes = {
	{ key = "VIP", title = "VIP", lines = { "VIP name tag", "VIP chat tag" }, icon = "Vip", color = Color3.fromRGB(255, 140, 0), color2 = Color3.fromRGB(255, 238, 58), price = 149, passId = 2092883003, giftProductId = 3734927628 },
	{ key = "Cash3x", title = "3X CASH", lines = { "Permanent", "3x money" }, icon = "Cash3x", color = Color3.fromRGB(31, 168, 0), color2 = Color3.fromRGB(157, 255, 58), price = 399, passId = 2097328717, giftProductId = 3734927641, tag = "BEST" },
	{ key = "DrinkMaster", title = "DRINK MASTER", lines = { "2x chance of", "rare fruits" }, icon = "Clover", color = Color3.fromRGB(212, 90, 0), color2 = Color3.fromRGB(255, 176, 58), price = 199, passId = 2092763123, giftProductId = 3734927655 },
	{ key = "GreedyCustomers", title = "GREEDY CUSTOMERS", lines = { "Customers buy", "2 drinks at a time" }, icon = "Customers", color = Color3.fromRGB(0, 128, 255), color2 = Color3.fromRGB(106, 224, 255), price = 199, passId = 2093182972, giftProductId = 3734927668 },
	{ key = "SpeedMaster", title = "SPEED MASTER", lines = { "2x walk speed", "2x customer speed" }, icon = "Shoe", color = Color3.fromRGB(42, 60, 255), color2 = Color3.fromRGB(92, 184, 255), price = 99, passId = 2093482922, giftProductId = 3734927675 },
	{ key = "AutoCollect", title = "AUTO COLLECT (All Floors)", lines = { "Cash goes straight", "to your wallet" }, icon = "Magnet", color = Color3.fromRGB(224, 0, 48), color2 = Color3.fromRGB(255, 122, 92), price = 149, passId = 2092570991, giftProductId = 3734927684 },
	-- Instant Sell (2026-11-21, ancien "Auto Sell") : pad violet a droite du pad Drop Juices
	-- (PassPadService) ; les jus poses sur le comptoir sont vendus tout de suite (CustomerService).
	{ key = "InstantSell", title = "INSTANT SELL (All Floors)", lines = { "Juices sell as soon", "as you drop them" }, icon = "Lightning", color = Color3.fromRGB(0, 168, 120), color2 = Color3.fromRGB(80, 240, 180), price = 199, passId = 2093680945, giftProductId = 3734927692 },
	-- Pads violets dans l'usine (PassPadService, 2026-11-20, prix A VALIDER) : Speed x10 a cote de
	-- Take Juices (apres le Waiter), Billboard dans la cour (99 R$ comme la capture de reference).
	{ key = "SpeedBoost", title = "WAITER SPEED x10 (All Floors)", lines = { "10x waiter speed", "Permanent" }, icon = "Shoe", color = Color3.fromRGB(0, 120, 255), color2 = Color3.fromRGB(0, 230, 255), price = 149, passId = 2092415019, giftProductId = 3734927704 },
	{ key = "Billboard", title = "BILLBOARD", lines = { "2x sell price", "Permanent" }, icon = "Cash", color = Color3.fromRGB(255, 120, 0), color2 = Color3.fromRGB(255, 220, 40), price = 99, passId = 2093464945, giftProductId = 3734927718 },
	{ key = "Thief", title = "THIEF (UNLIMITED)", lines = { "Steal ready drinks", "from other stands" }, icon = "Thief", color = Color3.fromRGB(90, 0, 200), color2 = Color3.fromRGB(195, 77, 255), price = 149, passId = 2097082802, giftProductId = 3734927725, tag = "OP" },
	{ key = "RebirthMaster", title = "REBIRTH MASTER", lines = { "Keep your tree", "level on rebirth" }, icon = "Rebirth", color = Color3.fromRGB(255, 0, 122), color2 = Color3.fromRGB(255, 138, 216), price = 199, passId = 2096880861, giftProductId = 3734927736 },
} :: { Pass }

-- Prix des packs : propositions de docs/game-design.md, a valider.
-- 2026-11-22 (demande utilisateur) : un peu plus d'argent, prix un peu plus bas, et "BEST VALUE" sur
-- un pack du milieu (ancrage : le gros pack fait paraitre le 4 h pas cher). L'etiquette reste VRAIE :
-- le 4 h donne le plus de minutes par Robux (240 / 189 = 1.27 contre 600 / 479 = 1.25).
-- 2026-11-23 (revue de la monetisation, "qu'ils achetent, que ce soit renta") : chaque pack plus
-- rentable que le precedent (minutes / R$ : 0.79, 1.22, 1.86, 2.41) et les gros packs au-dessus du
-- boost 2x Money (1.67). BEST VALUE sur le 12 h (vrai meilleur rapport). Avant : 6 min / 22, 35 min / 75,
-- 4 h / 189, 10 h / 479 (le 6 min etait 6x moins rentable que le boost a 9 R$).
-- Les cles (Cash5m...) restent les anciennes (attributs Cash_<cle>, ids des produits).
Shop.CashPacks = {
	{ key = "Cash5m", title = "CASH - 15 minutes", minutes = 15, minFloorShare = 0.5, price = 19, productId = 3734031076 },
	{ key = "Cash30m", title = "CASH - 1 hour", minutes = 60, minFloorShare = 1, price = 49, productId = 3734031080 },
	{ key = "Cash3h", title = "CASH - 4 hours", minutes = 240, minFloorShare = 2, price = 129, productId = 3734031084 },
	{ key = "Cash10h", title = "CASH - 12 hours", minutes = 720, minFloorShare = 4, price = 299, productId = 3734031092, bestValue = true },
} :: { CashPack }

-- Ecran "Welcome Back!" (gains hors ligne) : bouton x2 en Robux (docs/game-design.md : 9 R$).
Shop.OfflineDouble = { price = 9, productId = 3734031096 }

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
--     `minAmount` = montant minimum en $ (Starter Pack : jamais moins de $1K au debut).
--     `minFloorShare` = montant minimum en part du prix du prochain etage.
--     OBLIGATOIRE (2026-11-22) : chaque recompense Cash a `minAmount` ou `minFloorShare`, sinon un
--     joueur sans gains recents verrait "+$0" (RobuxShopService refuse de demarrer sinon).
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
		productId = 3734031104,
	},
	-- 2026-11-23 (revue de la monetisation) : chaque offre limitee vaut mieux que la meme chose en
	-- boutique (sinon le minuteur ment) : Money / Customer Rush 10 -> 15 min, Lucky Hour 29 -> 19 R$,
	-- Triple Boost 20 -> 30 min, Rare Rain 5 -> 10 min, Mega Cash voir sa ligne.
	Pool = {
		{ key = "OfferMoneyRush", title = "Money Rush", icon = "Cash", badge = "x3", price = 15, rewards = { { kind = "Boost", stat = "Money", mult = 3, minutes = 15 } }, productId = 3734031113 },
		{ key = "OfferLuckyHour", title = "Lucky Hour", icon = "Clover", badge = "x2", price = 19, rewards = { { kind = "Boost", stat = "Luck", mult = 2, minutes = 60 } }, productId = 3734031128 },
		{ key = "OfferRush", title = "Customer Rush", icon = "Shoe", badge = "x3", price = 15, rewards = { { kind = "Boost", stat = "Speed", mult = 3, minutes = 15 } }, productId = 3734031132 },
		{ key = "OfferMegaCash", title = "Mega Cash", icon = "Cash", price = 49, minCycle = 3, rewards = { { kind = "Cash", minutes = 90, floorShare = 1.5, minFloorShare = 0.8 } }, productId = 3734031138 }, -- 2026-11-23 : 99 -> 49 R$, plafond 0.5 -> 1.5 x prochain etage, minimum 0.25 -> 0.8 (avant : meme plafond que Lucky Cash a 24 R$) ; minCycle 3 : pas avant ~10 min de jeu (99 R$) ; 2026-11-22 : minimum 0.25 x prochain etage (avant : $0 sans gains recents)
		{
			key = "OfferTriple",
			title = "Triple Boost",
			icon = "PotionPurple",
			badge = "x2",
			price = 35,
			rewards = {
				{ kind = "Boost", stat = "Money", mult = 2, minutes = 30 },
				{ kind = "Boost", stat = "Luck", mult = 2, minutes = 30 },
				{ kind = "Boost", stat = "Speed", mult = 2, minutes = 30 },
			},
			productId = 3734031141,
		},
		{ key = "OfferRareRain", title = "Rare Rain", icon = "Clover", badge = "x5", price = 19, rewards = { { kind = "Boost", stat = "Luck", mult = 5, minutes = 10 } }, productId = 3734031150 },
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

-- Boost GRATUIT (2026-11-22, demande utilisateur) : le joueur goute au boost 2x SPEED (clients 2x
-- plus rapides) sans payer, pour sentir la difference quand il s'arrete. Aucune proposition d'achat
-- liee. Compte en temps de jeu de la session : FirstDelaySeconds apres le debut du tuto (fin de la
-- cinematique pour un profil neuf, arrivee sinon), puis Minutes de boost, puis GapSeconds de pause,
-- et ainsi de suite. S'ajoute au temps du boost Speed x2 (meme potion dans le HUD). RobuxShopService.
Shop.FreeBoost = table.freeze({
	stat = "Speed",
	mult = 2,
	minutes = 5,
	firstDelaySeconds = 3 * 60,
	gapSeconds = 10 * 60, -- pause entre la fin d'un boost gratuit et le suivant
})
-- Offre au bon moment (2026-11-23, "techniques qui rapportent") : achat d'etage refuse faute
-- d'argent -> fenetre "Almost there!" avec le plus petit pack d'argent qui couvre ce qui manque
-- (DealController ; FloorService envoie Feedback "NeedCash"). Au plus une fois par CooldownSeconds.
Shop.NeedCash = table.freeze({
	cooldownSeconds = 180,
})

-- Essai GRATUIT de 3X CASH (2026-11-23) : une fois par session, apres FirstDelaySeconds de jeu (en
-- pause pendant la cinematique, comme le boost gratuit), ventes x3 pendant Seconds. A la fin, si le
-- joueur a vendu : fenetre "3X CASH earned you +$X!" avec le VRAI surplus gagne et le bouton du pass.
-- Pas pour ceux qui ont deja le pass. Effet : Lib/Perks (attribut "Cash3xTrialEnd"), RobuxShopService.
Shop.Cash3xTrial = table.freeze({
	passKey = "Cash3x",
	mult = 3,
	seconds = 3 * 60,
	firstDelaySeconds = 9 * 60, -- apres le 1er boost gratuit 2x Speed (3 min + 5 min)
})

-- Lots de passes (2026-11-23) : un Developer Product qui donne plusieurs passes (Data.GiftedPasses,
-- comme un cadeau). Vraie reduction (prix des passes separes : 399 + 199 + 149 + 199 = 946).
-- Vendu seulement a un joueur qui n'a AUCUN de ces passes (sinon il paierait deux fois) :
-- attribut joueur "BundleBlocked_<cle>" = true (serveur), la boutique affiche "OWNED".
Shop.Bundles = {
	{
		key = "Ultimate",
		title = "ULTIMATE BUNDLE",
		passes = { "Cash3x", "GreedyCustomers", "AutoCollect", "InstantSell" },
		labels = { "3X CASH", "GREEDY", "AUTO COLLECT", "INSTANT SELL" }, -- nom court sous chaque logo
		price = 499,
		productId = 3734946982, -- "Ultimate Bundle", cree par Open Cloud le 2026-11-23
	},
}

-- Textes des fenetres de DealController (anglais : vus par le joueur).
Shop.DealTexts = table.freeze({
	NeedTitle = "Almost there!",
	NeedLine = "Floor %d: you need +%s", -- (etage, argent manquant)
	NeedGet = "Get %s now!", -- montant du pack propose
	TrialTitle = "Free Trial Over!",
	TrialLine = "3X CASH earned you", -- au-dessus du montant "+$2.1K"
	TrialAsk = "Keep it forever?",
	Owned = "OWNED",
	Save = "SAVE %d%%", -- etiquette du lot (vraie reduction)
})

Shop.BoostMaxSeconds = 7 * 24 * 3600 -- plafond du temps stocke par stat et multiplicateur (filet de securite)
Shop.PendingSeconds = 120 -- montant d'argent montre au clic garde X s (le recu donne ce montant)
Shop.ReceiptWaitSeconds = 20 -- attente max du chargement de la sauvegarde a la reception d'un recu
Shop.BuyCooldownSeconds = 0.5 -- delai entre deux clics d'achat (remote ShopBuy)

-- Cadeaux de passes (GiftService, 2026-11-23) : bouton rose d'un pass -> choix d'un joueur du serveur
-- -> produit "Gift - <pass>" (giftProductId, meme prix que le pass). Le cadeau passe par une boite aux
-- lettres DataStore (cle "u<UserId>" du destinataire) : il arrive meme si le destinataire est parti.
Shop.Gifts = table.freeze({
	StoreName = "PassGifts_v1",
	PendingSeconds = 600, -- destinataire choisi garde X s (sinon le recu offre le pass a l'acheteur)
	MaxMailbox = 50, -- cadeaux en attente gardes au plus par joueur
	MaxDone = 100, -- ids de cadeaux deja livres gardes (un recu redonne n'offre jamais deux fois)
	Retries = 3,
})

Shop.Messages = table.freeze({
	ComingSoon = "Robux purchases: coming soon!",
	GiftSoon = "Gifts: coming soon!",
	GiftPickPlayer = "Choose a player to gift!",
	GiftNoPlayer = "That player left the server!",
	GiftSelf = "You can't gift yourself!",
	GiftAlreadyOwned = "%s already has this pass!", -- %s = pseudo du destinataire
	GiftSent = "Gift sent to %s!", -- acheteur
	GiftGot = "%s gifted you %s!", -- destinataire : (pseudo de l'acheteur, nom du pass)
	GiftSelfGot = "%s unlocked!", -- recu sans destinataire note : pass offert a l'acheteur
	AlreadyOwned = "You already own this pass!",
	AlreadyBought = "You already got this offer!",
	BoostOn = "%s x%d for %d min!", -- "MONEY x2 for 15 min!"
	FreeBoostOn = "FREE %s x%d for %d min!", -- boost gratuit (Shop.FreeBoost)
	CashGot = "+%s cash!",
	PassOn = "%s unlocked!",
	TrialOn = "FREE 3X CASH for %d min!",
	BundleOwned = "You already own a pass from this bundle!",
})
Shop.StatNames = table.freeze({ Money = "MONEY", Luck = "LUCK", Speed = "SPEED" })

return Shop
