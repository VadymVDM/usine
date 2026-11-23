--!strict
-- Effets des achats Robux sur la partie, lus par les services du jeu (2026-11-20).
-- Les attributs joueur sont poses par le serveur SEULEMENT (RobuxShopService) :
--   * passes : "Cash3x", "DrinkMaster", "GreedyCustomers", "SpeedMaster" (booleens) ;
--   * boosts en cours : "BoostMoney" / "BoostLuck" / "BoostSpeed" = multiplicateur actif (nil = aucun).
-- Passer par des attributs evite les require en cercle (RobuxShopService a besoin de CustomerService).
-- `withBoosts` = false : sans les boosts temporaires (gains hors ligne : le temps d'un boost ne
-- descend pas hors ligne, il ne doit donc rien rapporter hors ligne).
-- Doc : docs/systems/achats-robux.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Shop"))

local Perks = {}

local EFFECTS = Shop.PassEffects

local function boost(player: Player, stat: string): number
	local value = player:GetAttribute("Boost" .. stat)
	return if type(value) == "number" and value >= 1 then value else 1
end

local function owns(player: Player, key: string): boolean
	return player:GetAttribute(key) == true
end

-- Essai gratuit de 3X CASH en cours (Shop.Cash3xTrial, attribut "Cash3xTrialEnd" pose par
-- RobuxShopService). Compte comme un boost temporaire (pas hors ligne, retire de la base des packs).
function Perks.InCash3xTrial(player: Player): boolean
	local ends = player:GetAttribute("Cash3xTrialEnd")
	return type(ends) == "number" and workspace:GetServerTimeNow() < ends and not owns(player, "Cash3x")
end

-- Argent des ventes : pass 3X CASH (ou son essai gratuit) x boost Money.
function Perks.MoneyMultiplier(player: Player, withBoosts: boolean): number
	local multiplier = if owns(player, "Cash3x") then EFFECTS.Cash3xMoney else 1
	if withBoosts then
		multiplier *= boost(player, "Money")
		if Perks.InCash3xTrial(player) then
			multiplier *= Shop.Cash3xTrial.mult
		end
	end
	return multiplier
end

-- Chance des fruits rares (multiplie la Luck du niveau d'arbre) : DRINK MASTER x boost Luck.
function Perks.LuckMultiplier(player: Player, withBoosts: boolean): number
	local multiplier = if owns(player, "DrinkMaster") then EFFECTS.DrinkMasterLuck else 1
	if withBoosts then
		multiplier *= boost(player, "Luck")
	end
	return multiplier
end

-- Vitesse des clients (le temps entre deux ventes est divise par ce nombre) : SPEED MASTER x boost Speed.
function Perks.CustomerSpeedMultiplier(player: Player, withBoosts: boolean): number
	local multiplier = if owns(player, "SpeedMaster") then EFFECTS.SpeedMasterCustomers else 1
	if withBoosts then
		multiplier *= boost(player, "Speed")
	end
	return multiplier
end

-- Jus achetes par client : GREEDY CUSTOMERS.
function Perks.JuicesPerCustomer(player: Player): number
	return if owns(player, "GreedyCustomers") then EFFECTS.GreedyJuices else 1
end

-- Vitesse de marche du joueur : SPEED MASTER.
function Perks.WalkSpeedMultiplier(player: Player): number
	return if owns(player, "SpeedMaster") then EFFECTS.SpeedMasterWalk else 1
end

return Perks
