--!strict
-- Production "en nombres" d'un etage (tour d'etages, lot 5) : ce que rapporte un etage AUTOMATISE
-- quand le joueur n'y est pas (pas de fruits, d'employes ni de clients dessines). La meme formule
-- servira aux gains hors ligne (WelcomeBack, plus tard).
--
-- Etage automatise = Fruit Picker (Collector) + vendeur (Waiter de l'etage) + l'operateur du
-- mixeur 1 embauches (2026-11-21 : l'ancien pass Auto Sell, devenu Instant Sell, ne compte plus : il
-- ne vend que les jus poses par le joueur).
-- Sinon il ne produit rien hors de la presence du joueur (ca pousse a embaucher avant de monter).
-- Debit (jus par seconde) = le plus lent de :
--   * l'arbre : 1 fruit toutes les Upgrades.TreeDropSeconds(Tree) s ;
--   * le Fruit Picker : FloorIncome.PickerRate (fruits portes PickerCarry, vitesse PickerBaseSpeed
--     x PickerSpeed, temps d'un tour Floors.PickerTripSeconds / PickerFruitSeconds : A VALIDER) ;
--   * le tapis : Upgrades ConveyorSpeed (fruits / s) ;
--   * les mixeurs avec operateur : somme de bol / (BlendSeconds + OperatorReactSeconds + bol / tapis
--     + trajet sur le tapis + Floors.BlendCycleExtraSeconds) ;
--   * la vente : le Waiter = Gameplay.WaiterCarry / Floors.WaiterTripSeconds (A VALIDER), x Gameplay.WaiterSpeedPassMultiplier
--     avec le pass "Waiter Speed x10" ;
--   * les clients : CustomerCount / CustomerSpeed.
-- Valeur d'un jus = moyenne des 10 fruits de l'etage ponderee par leurs chances (Luck = niveau Tree),
-- x bonus de l'ascenseur aux etages 2+ (TowerUpgrades ; depuis le 2026-11-20 l'ascenseur augmente
-- l'argent des ventes, avant il accelerait les clients, qui ne bloquaient presque jamais).
-- Doc : docs/systems/tour-etages.md (section "Production en nombres")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Floors = require(Config:WaitForChild("Floors"))
local Fruits = require(Config:WaitForChild("Fruits"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Upgrades = require(Config:WaitForChild("Upgrades"))

local FloorIncome = {}

export type Result = {
	automated: boolean,
	juicesPerSecond: number,
	averageValue: number,
	moneyPerSecond: number,
	bottleneck: string, -- "Tree", "Picker", "Conveyor", "Blenders", "Waiter", "Customers", "NotAutomated"
}

local function level(levels: { [string]: number }, id: string): number
	return levels[id] or Upgrades.ById[id].startLevel
end

-- Valeur moyenne d'un jus de l'etage n (chances de chaque rarete avec la Luck du niveau Tree).
-- `luckFactor` = multiplicateur de chance en plus (achats Robux : Lib/Perks.LuckMultiplier), 1 par defaut.
function FloorIncome.AverageValue(n: number, treeLevel: number, luckFactor: number?): number
	local weights = Fruits.RollWeights(Fruits.LuckMultiplier(treeLevel) * (luckFactor or 1))
	local total, sum = 0, 0
	for _, fruit in Fruits.OfFloor(n) do
		local w = weights[fruit.rarity] or 0
		total += w
		sum += w * fruit.value
	end
	return if total > 0 then sum / total else 0
end

-- Multiplicateur de l'argent des ventes des etages 2+ (panneau Elevator de la terrasse) : ventes
-- dessinees (CustomerService.sellOne) et en nombres (Compute). Revue de l'economie du 2026-11-20 :
-- un achat toujours utile a partir de l'etage 2 (avant : vitesse des clients, souvent sans effet).
function FloorIncome.ElevatorBonus(tower: { [string]: number }?): number
	if tower == nil then
		return 1
	end
	local speed = tower.ElevatorSpeed or 0
	local cabin = tower.ElevatorCabin or 0
	return 1 + speed * Floors.ElevatorSpeedBonus + cabin * Floors.ElevatorCabinBonus
end

-- Fruits par seconde du Fruit Picker de l'etage (va-et-vient arbre -> etagere).
function FloorIncome.PickerRate(levels: { [string]: number }): number
	local carry = Upgrades.GetValue("PickerCarry", level(levels, "PickerCarry"))
	local speed = Gameplay.PickerBaseSpeed * Upgrades.GetValue("PickerSpeed", level(levels, "PickerSpeed"))
	return carry * speed / (Floors.PickerTripSeconds + carry * Floors.PickerFruitSeconds)
end

-- Debit de l'etage n avec ces niveaux. `tower` = Data.TowerUpgrades (bonus des etages 2+).
-- `waiterBoost` = le joueur a le pass "Waiter Speed x10" (attribut SpeedBoost, PassPadService).
-- `perks` (achats Robux, Lib/Perks, 2026-11-20) : luck = chance en plus ; customers = debit des
-- clients en plus (vitesse x jus par client). Absent = 1.
export type Perks = { luck: number?, customers: number? }
function FloorIncome.Compute(
	levels: { [string]: number },
	n: number,
	tower: { [string]: number }?,
	waiterBoost: boolean?,
	perks: Perks?
): Result
	local waiter = level(levels, "Waiter") >= 1
	local automated = level(levels, "Collector") >= 1 and waiter and level(levels, "Operator1") >= 1
	local treeLevel = level(levels, "Tree")
	local average = FloorIncome.AverageValue(n, treeLevel, if perks then perks.luck else nil)
	if n >= 2 then
		average *= FloorIncome.ElevatorBonus(tower)
	end
	if not automated then
		return { automated = false, juicesPerSecond = 0, averageValue = average, moneyPerSecond = 0, bottleneck = "NotAutomated" }
	end
	local conveyor = Upgrades.GetValue("ConveyorSpeed", level(levels, "ConveyorSpeed"))
	-- Trajet du dernier fruit sur le tapis (meme formule que ProductionService.conveyorTravel) + petit
	-- temps perdu mesure en playtest (2026-11-20 : bol de 12, tapis 2.53/s, operateur : un cycle
	-- = ~11 s, soit ~1.1 jus/s ; sans le trajet la formule donnait 1.46 jus/s).
	local baseConveyor = Upgrades.GetValue("ConveyorSpeed", 1)
	local travel = math.max(Gameplay.ConveyorTravelMin, Gameplay.ConveyorTravelSeconds * (baseConveyor / math.max(conveyor, 0.1)) ^ 0.6)
	local blenders = 0
	for i = 1, Gameplay.MaxBlenders do
		local owned = i == 1 or level(levels, "Blender" .. i) >= 1
		if owned and level(levels, "Operator" .. i) >= 1 then
			local bowl = Upgrades.GetValue("Blender" .. i, math.max(level(levels, "Blender" .. i), 1))
			local cycle = Gameplay.BlendSeconds
				+ Gameplay.OperatorReactSeconds
				+ bowl / math.max(conveyor, 0.1)
				+ travel
				+ Floors.BlendCycleExtraSeconds
			blenders += bowl / cycle
		end
	end
	local customers = Upgrades.GetValue("CustomerCount", level(levels, "CustomerCount"))
		/ math.max(Upgrades.GetValue("CustomerSpeed", level(levels, "CustomerSpeed")), 0.2)
		* (if perks and perks.customers then perks.customers else 1)
	local rates = {
		{ "Tree", 1 / Upgrades.TreeDropSeconds(treeLevel) },
		{ "Picker", FloorIncome.PickerRate(levels) },
		{ "Conveyor", conveyor },
		{ "Blenders", blenders },
		{
			"Waiter",
			Gameplay.WaiterCarry / Floors.WaiterTripSeconds * (if waiterBoost then Gameplay.WaiterSpeedPassMultiplier else 1),
		},
		{ "Customers", customers },
	}
	local slowest, name = math.huge, "Tree"
	for _, entry in rates do
		local rate = entry[2] :: number
		if rate < slowest then
			slowest, name = rate, entry[1] :: string
		end
	end
	return {
		automated = true,
		juicesPerSecond = slowest,
		averageValue = average,
		moneyPerSecond = slowest * average,
		bottleneck = name,
	}
end

return FloorIncome
