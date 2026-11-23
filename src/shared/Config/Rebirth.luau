--!strict
-- Rebirth (phase 4, 2026-11-20). Salle du Rebirth de l'annexe (ancien bar a cocktails), ouverte a
-- l'etage 10 : E sur la machine doree -> menu Rebirth (RebirthController) -> le serveur
-- (RebirthService) verifie et fait le rebirth.
--   * Condition : RequiredFloors etages achetes + Price(rebirths) en argent (tout l'argent part).
--   * On perd : argent, etages, ameliorations et employes des etages, ascenseur, fruits / jus portes.
--   * On garde : l'Index (fruits decouverts, CLAIM pris), le menu Upgrade (vitesse, plateaux), les
--     reglages, les statistiques, les passes Robux.
--   * Gain : multiplicateur d'argent permanent sur les ventes de jus : x2, x3, x4...
--   * "Rebirth & keep your cash" (produit Robux, bouton violet du menu) : rebirth tout de suite,
--     sans payer le prix et en gardant tout son argent. Prix selon le nombre de rebirths.
--   * Pass Rebirth Master : chaque etage rachete reprend le niveau d'arbre qu'il avait.
-- Le serveur est le seul a utiliser ces valeurs pour decider ; le client les affiche.
-- Prix et multiplicateur valides (2026-11-20) ; prix Robux A VALIDER. Doc : docs/systems/rebirth.md

local Floors = require(script.Parent.Floors)
local GameConfig = require(script.Parent.GameConfig)

local Rebirth = {}

-- Etages a posseder pour pouvoir renaitre (la salle du Rebirth s'ouvre au meme moment).
Rebirth.RequiredFloors = Floors.MaxFloors

-- Prix du rebirth (argent du jeu) = BasePrice x (1 + PriceStep x rebirths deja faits) :
-- 10B, 20B, 30B... (valide par l'utilisateur le 2026-11-20). Calcul de depart : l'etage 10 coute 1.95B (~12 min de gains) ; une
-- fois l'etage 10 ameliore, la tour gagne ~x5 : 10B = encore ~12-15 min. Le multiplicateur monte
-- comme le prix (x2 pour 20B, x3 pour 30B) : la derniere marche dure toujours a peu pres pareil,
-- alors que les etages, eux, vont de plus en plus vite.
-- 2026-11-20 (revue de l'economie) : courbe progressive des etages (l'etage 10 coute 2.2B) + ascenseur
-- (ventes x3 max aux etages 2+) ; 10B garde. Simulation : 10B ~15 min apres l'achat de l'etage 10
-- (vers 1 h 55 pour un joueur qui achete bien).
Rebirth.BasePrice = 10_000_000_000
Rebirth.PriceStep = 1

-- Multiplicateur des ventes = 1 + MultiplierPerRebirth x rebirths (x2 apres le 1er, x3...).
-- Valide par l'utilisateur le 2026-11-20.
Rebirth.MultiplierPerRebirth = 1

-- "Rebirth & keep your cash" : un produit Robux par palier (Roblox : prix fixe par produit).
-- Le serveur choisit le palier d'apres le nombre de rebirths du joueur. productId = 0 tant que le
-- produit n'est pas cree sur Roblox (bouton -> "coming soon"). Prix A VALIDER.
Rebirth.KeepCashProducts = table.freeze({
	table.freeze({ minRebirths = 0, price = 49, productId = 3734031157 }),
	table.freeze({ minRebirths = 3, price = 99, productId = 3734031163 }),
	table.freeze({ minRebirths = 10, price = 199, productId = 3734031169 }),
	table.freeze({ minRebirths = 25, price = 299, productId = 3734031171 }),
})

Rebirth.RequestCooldown = 1 -- secondes entre deux demandes (remote RebirthRequest)
Rebirth.ReachDistance = 30 -- distance max entre le joueur et la machine doree pour renaitre (studs)
Rebirth.ConfirmSeconds = 3 -- menu : temps pour cliquer une 2e fois sur "Rebirth" (confirmation)
Rebirth.ReceiptWaitSeconds = 10 -- recu Robux : attente max de la sauvegarde du joueur (il vient d'arriver)

-- Nametag au-dessus de la tete (Lib/NameTag, vu seulement par les autres) : pseudo + "Rebirth N"
-- (couleur TitleColor) des le premier rebirth. Tailles en studs.
Rebirth.TitleColor = Color3.fromRGB(255, 210, 60)
Rebirth.NameTagWidth = 7
Rebirth.NameTagHeight = 1.8
Rebirth.NameTagLift = 2.4 -- centre du nametag au-dessus du centre de la tete
Rebirth.NameTagMaxDistance = 100 -- comme le nom affiche par Roblox

-- Textes (anglais : vus par le joueur)
Rebirth.Messages = table.freeze({
	NotEnoughMoney = "Not enough money!",
	NeedFloors = "Reach Floor %d first!",
	TooFar = "Go to the Rebirth machine!",
	Done = "Rebirth %d! Cash x%s forever!",
	Others = "%s reached Rebirth %d!",
	KeepCashSoon = "Robux purchases: coming soon!",
	-- Achat Keep Cash recu alors que le rebirth n'est pas possible : garde pour le prochain (jeton)
	KeepCashSaved = "Keep Cash saved! Reach Floor %d, then press Keep Cash for free.",
})
Rebirth.Texts = table.freeze({
	Before = "Now:",
	After = "After:",
	Cash = "x%s Cash",
	Rank = "Rebirth %d",
	Warning = "Resets your cash, floors and upgrades!",
	Button = "Rebirth",
	Confirm = "Sure?",
	KeepCash = "KEEP CASH", -- bouton violet (Robux) ; le prix [Robux] 49 est dessous
	NeedFloor = "Floor %d / %d",
	Banner = "REBIRTH!",
	BannerSub = "x%s CASH",
	Title = "Rebirth %d",
})

local function count(rebirths: number): number
	if type(rebirths) ~= "number" or rebirths ~= rebirths then
		return 0
	end
	return math.clamp(math.floor(rebirths), 0, GameConfig.MaxRebirths)
end

-- Multiplicateur des ventes apres `rebirths` rebirths (1 = aucun).
function Rebirth.Multiplier(rebirths: number): number
	return 1 + Rebirth.MultiplierPerRebirth * count(rebirths)
end

-- Prix du prochain rebirth quand on en a deja fait `rebirths` (entier, plafonne a MaxMoney).
function Rebirth.Price(rebirths: number): number
	local price = Rebirth.BasePrice * (1 + Rebirth.PriceStep * count(rebirths))
	return math.min(math.floor(price + 0.5), GameConfig.MaxMoney)
end

-- Palier "Rebirth & keep your cash" pour un joueur qui a deja `rebirths` rebirths.
function Rebirth.KeepCashProduct(rebirths: number): { minRebirths: number, price: number, productId: number }
	local r = count(rebirths)
	local found = Rebirth.KeepCashProducts[1]
	for _, tier in Rebirth.KeepCashProducts do
		if r >= tier.minRebirths then
			found = tier
		end
	end
	return found
end

-- "2" pour x2, "2.5" pour x2.5 (textes du menu, de la banniere et des messages).
function Rebirth.FormatMultiplier(multiplier: number): string
	if multiplier % 1 == 0 then
		return tostring(math.floor(multiplier))
	end
	return string.format("%.1f", multiplier)
end

return table.freeze(Rebirth)
