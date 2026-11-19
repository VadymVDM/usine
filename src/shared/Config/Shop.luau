--!strict
-- Contenu de la boutique (prix en Robux). Source : docs/game-design.md (Monetisation).
-- `productId` / `passId` = 0 tant que les produits ne sont pas crees sur Roblox.
-- Doc : docs/systems/interface.md

export type Boost = {
	key: string,
	title: string,
	icon: string,
	color: Color3, -- bas du degrade
	color2: Color3, -- haut du degrade
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
	{ key = "Thief", title = "THIEF", lines = { "Steal ready drinks", "from other stands" }, icon = "Thief", color = Color3.fromRGB(90, 0, 200), color2 = Color3.fromRGB(195, 77, 255), price = 149, passId = 0, tag = "OP" },
	{ key = "RebirthMaster", title = "REBIRTH MASTER", lines = { "Keep your tree", "level on rebirth" }, icon = "Rebirth", color = Color3.fromRGB(255, 0, 122), color2 = Color3.fromRGB(255, 138, 216), price = 299, passId = 0 },
} :: { Pass }

-- Prix des packs : propositions de docs/game-design.md, a valider.
Shop.CashPacks = {
	{ key = "Cash5m", title = "CASH - 5 minutes", minutes = 5, price = 25, productId = 0 },
	{ key = "Cash30m", title = "CASH - 30 minutes", minutes = 30, price = 79, productId = 0 },
	{ key = "Cash3h", title = "CASH - 3 hours", minutes = 180, price = 199, productId = 0 },
	{ key = "Cash10h", title = "CASH - 10 hours", minutes = 600, price = 499, productId = 0, bestValue = true },
} :: { CashPack }

-- Ecran "Welcome Back!" (gains hors ligne) : bouton x2 en Robux (docs/game-design.md : 9 R$).
Shop.OfflineDouble = { price = 9, productId = 0 }

-- Offres limitees a droite de l'ecran (OffersController).
-- Rotation commune a tous les joueurs (heure du serveur) : visibles `OnSeconds`, puis cachees
-- `OffSeconds`, puis de nouvelles offres. `Slots` offres a la fois, prises a tour de role dans `Pool`.
-- `oldPrice` (facultatif, seulement certaines offres) = le VRAI prix normal du meme article dans la
-- boutique (reduction honnete). Sans `oldPrice` : offre a prix normal, juste limitee dans le temps.
-- Chaque offre aura son propre produit Robux (`productId`) au prix reduit ; pour un pass, le produit
-- donnera l'avantage du pass (comme un cadeau).
Shop.LimitedOffers = {
	OnSeconds = 10 * 60,
	OffSeconds = 2 * 60,
	Slots = 3,
	Pool = {
		{ key = "OfferMoney30", title = "2x Money", details = "2x money for 30 minutes", icon = "PotionGreen", price = 16, kind = "Boost", productId = 0 },
		{ key = "OfferLuck30", title = "2x Luck", details = "2x tree luck for 30 minutes", icon = "PotionBlue", price = 12, oldPrice = 16, kind = "Boost", productId = 0 },
		{ key = "OfferCash3x", title = "3x Cash", details = "Permanent 3x money", icon = "Cash3x", price = 299, oldPrice = 399, kind = "Pass", productId = 0 },
		{ key = "OfferSpeed30", title = "2x Speed", details = "2x customer speed for 30 minutes", icon = "PotionPurple", price = 16, kind = "Boost", productId = 0 },
		{ key = "OfferCash30m", title = "Cash Pack", details = "30 minutes of profit instantly", icon = "Cash", price = 79, kind = "CashPack", productId = 0 },
		{ key = "OfferDrinkMaster", title = "Drink Master", details = "Permanent 2x chance of rare fruits", icon = "Clover", price = 189, oldPrice = 249, kind = "Pass", productId = 0 },
	},
}

return Shop
