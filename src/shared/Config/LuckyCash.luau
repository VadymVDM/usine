--!strict
-- "Lucky Cash" : liasse de billets 3D qui tourne, cachee de temps en temps sur un etage (allee entre
-- l'escalier et le verger, pres du mur). Marcher dessus ou E -> fenetre "WOW! You found a secret cash stash!" : un gros montant
-- d'argent du jeu, adapte a la progression du joueur, contre des Robux (Developer Product).
-- Le serveur calcule le montant (LuckyCashService) ; le client ne fait que l'afficher.
-- Prix et montants A VALIDER (2026-11-20). productId = 0 tant que le produit n'est pas cree sur
-- Roblox : le bouton affiche "Robux purchases: coming soon!".
-- Doc : docs/systems/lucky-cash.md

local Floors = require(script.Parent:WaitForChild("Floors"))

local LuckyCash = {}

LuckyCash.Price = 29 -- Robux (affiche dans la fenetre ; le vrai prix est celui du produit sur Roblox)
LuckyCash.ProductId = 0

-- Montant = Minutes x gains theoriques de toute la tour (CustomerService.GetIncomePerSecond),
-- PLAFONNE a FloorShare x prix du prochain etage du joueur (Floors.Prices), jamais sous MinAmount.
-- 2026-11-20 : avant, le plus grand des deux -> $32.7K a l'etage 1 (12 $/s x 45 min) alors que
-- l'etage 2 coute $5K ("c'est beaucoup trop"). Plafond : le tas aide a monter, ne paie jamais
-- un etage entier. Prix des etages / 2 le 2026-11-20 (revue de l'economie) : etage 2 = $2.5K, donc
-- MinAmount 1 500 -> 600 pour garder 0.4 x le prochain etage. Courbe progressive (etage 2 = $1.5K) :
-- ex. etage 1 : $600 ; etage 3 (prochain = $62K) : jusqu'a $24.8K.
LuckyCash.Minutes = 45
LuckyCash.FloorShare = 0.4
LuckyCash.MinAmount = 600

-- Place du tas dans le repere de l'etage (pivot de l'etage, sol a y = 0) : allee nord de la zone
-- STAIRS (z 78 -> 84, libre sur tous les etages), contre l'escalier (voie B, z 78) et pres du mur
-- (x 109). 2026-11-21 : (78, 81.3) -> (96, 80.5), "plus proche du mur et de l'escalier".
LuckyCash.Spot = Vector3.new(96, 0, 80.5)

-- Apparition (cote client, 2026-11-21 : "plus rarement") : UN seul tas a la fois, sur un etage
-- ouvert tire au hasard. Il apparait FirstSpawnSeconds apres l'arrivee, reste VisibleSeconds, puis
-- revient au bout d'un delai tire entre SpawnMinSeconds et SpawnMaxSeconds.
LuckyCash.FirstSpawnSeconds = 2 * 60
LuckyCash.VisibleSeconds = 2 * 60
LuckyCash.SpawnMinSeconds = 6 * 60
LuckyCash.SpawnMaxSeconds = 10 * 60

LuckyCash.TouchRadius = 4 -- marcher a moins de X studs du centre ouvre la fenetre
LuckyCash.RearmRadius = 9 -- il faut s'eloigner de X studs avant qu'elle puisse se rouvrir seule
LuckyCash.AutoOpenCooldownSeconds = 60 -- ouverture en marchant dessus : au plus 1 fois par minute
LuckyCash.PromptDistance = 10 -- touche E

LuckyCash.AmountAttribute = "LuckyCashAmount" -- attribut joueur pose par le serveur (montant actuel)
LuckyCash.BuyCooldownSeconds = 1
LuckyCash.PendingSeconds = 10 * 60 -- montant montre au clic garde pour le recu pendant X s
LuckyCash.ReceiptWaitSeconds = 15 -- attente max de la sauvegarde a la reception d'un recu

LuckyCash.Messages = table.freeze({
	ComingSoon = "Robux purchases: coming soon!",
})

local function nextFloorPrice(floorsOwned: number): number
	local prices = Floors.Prices
	local n = math.max(floorsOwned, 1) + 1
	if n <= #prices then
		return prices[n]
	end
	return prices[#prices] * Floors.UpgradePriceFactor
end

-- Garde 3 chiffres significatifs (12 345 -> 12 300) : le montant affiche "+$12.3K" = le montant donne.
local function round3(value: number): number
	if value < 1000 then
		return math.floor(value)
	end
	local step = 10 ^ (math.floor(math.log10(value)) - 2)
	return math.floor(value / step) * step
end

-- Montant offert (entier >= MinAmount).
function LuckyCash.Amount(incomePerSecond: number, floorsOwned: number): number
	local income = if incomePerSecond == incomePerSecond and incomePerSecond > 0 then incomePerSecond else 0
	local fromIncome = income * LuckyCash.Minutes * 60
	local fromFloor = LuckyCash.FloorShare * nextFloorPrice(floorsOwned)
	return round3(math.max(math.min(fromIncome, fromFloor), LuckyCash.MinAmount))
end

return LuckyCash
