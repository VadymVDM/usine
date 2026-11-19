--!strict
-- Ameliorations et employes de la zone 1 : effets, prix en argent, prix Robux (A VALIDER).
-- Valeurs de depart a equilibrer en test : tableau dans docs/systems/ameliorations-employes.md.
-- Le serveur est le seul a utiliser ces prix pour un achat ; le client les affiche seulement.

local Fruits = require(script.Parent.Fruits)

export type UpgradeId =
	"TreeSpeed"
	| "TreeLuck"
	| "JuiceLimit"
	| "CounterLimit"
	| "CustomerSpeed"
	| "CustomerCount"
	| "Collector"
	| "Presser"
	| "Server"

export type Upgrade = {
	id: UpgradeId,
	title: string, -- texte affiche (anglais)
	kind: "Upgrade" | "Employee",
	board: "Tree" | "Press" | "Counter" | "Employees", -- groupe de pads ou il est affiche
	icon: string, -- cle de Config/Icons.luau
	color: Color3, -- couleur de la tuile
	startLevel: number, -- niveau d'un profil neuf (employe : 0 = pas embauche)
	maxLevel: number?, -- nil = calcule (TreeLuck : depend des rebirths)
	-- Effet au niveau n : base * factor^(n-1) si `factor`, sinon base + step*(n-1).
	effectBase: number,
	effectFactor: number?,
	effectStep: number?,
	-- Prix pour passer du niveau n au niveau n+1 : priceBase * priceGrowth^(n-1), arrondi.
	-- Pour un employe (niveau 0 -> 1) : priceBase.
	priceBase: number,
	priceGrowth: number,
	-- Prix Robux A VALIDER (aucun produit cree) : robuxBase + robuxStep*(n-1).
	robuxBase: number,
	robuxStep: number,
}

local Upgrades = {}

-- A VALIDER : prix Robux provisoires, affiches seulement (pas d'achat Robux en phase 1).
local ROBUX_BASE = 5
local ROBUX_STEP = 3

local list: { Upgrade } = {
	{
		id = "TreeSpeed",
		title = "Tree Speed",
		kind = "Upgrade",
		board = "Tree",
		icon = "Clock",
		color = Color3.fromRGB(255, 150, 30),
		startLevel = 1,
		maxLevel = 15,
		effectBase = 2.5, -- secondes entre deux fruits
		effectFactor = 0.92,
		priceBase = 15, -- = 3 pommes : premier achat vers 0:35
		priceGrowth = 1.35,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "TreeLuck",
		title = "Tree Luck",
		kind = "Upgrade",
		board = "Tree",
		icon = "Clover",
		color = Color3.fromRGB(60, 200, 80),
		startLevel = 1,
		maxLevel = nil, -- Fruits.MaxLuck(rebirths)
		effectBase = 1, -- nombre de fruits possibles
		effectStep = 1,
		priceBase = 25,
		priceGrowth = 1.3,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "JuiceLimit",
		title = "Juice Limit",
		kind = "Upgrade",
		board = "Press",
		icon = "PotionGreen",
		color = Color3.fromRGB(255, 80, 120),
		startLevel = 1,
		maxLevel = 9,
		effectBase = 10, -- jus max a cote de la presse
		effectStep = 5,
		priceBase = 30,
		priceGrowth = 1.5,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "CounterLimit",
		title = "Counter Limit",
		kind = "Upgrade",
		board = "Counter",
		icon = "Cash",
		color = Color3.fromRGB(40, 150, 255),
		startLevel = 1,
		maxLevel = 9,
		effectBase = 6, -- jus max sur le comptoir
		effectStep = 3,
		priceBase = 30,
		priceGrowth = 1.5,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "CustomerSpeed",
		title = "Customer Speed",
		kind = "Upgrade",
		board = "Counter",
		icon = "Shoe",
		color = Color3.fromRGB(150, 80, 255),
		startLevel = 1,
		maxLevel = 15,
		effectBase = 2.5, -- secondes entre deux passages de clients
		effectFactor = 0.92,
		priceBase = 80,
		priceGrowth = 1.45,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "CustomerCount",
		title = "Customers",
		kind = "Upgrade",
		board = "Counter",
		icon = "Customers",
		color = Color3.fromRGB(255, 200, 40),
		startLevel = 1,
		maxLevel = 5,
		effectBase = 1, -- clients a chaque passage (1 jus chacun)
		effectStep = 1,
		priceBase = 300,
		priceGrowth = 2.5,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "Collector",
		title = "Collector",
		kind = "Employee",
		board = "Employees",
		icon = "Magnet",
		color = Color3.fromRGB(60, 200, 80),
		startLevel = 0,
		maxLevel = 1,
		effectBase = 1,
		effectStep = 0,
		priceBase = 40,
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "Presser",
		title = "Presser",
		kind = "Employee",
		board = "Employees",
		icon = "Rebirth",
		color = Color3.fromRGB(255, 150, 30),
		startLevel = 0,
		maxLevel = 1,
		effectBase = 1,
		effectStep = 0,
		priceBase = 150,
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "Server",
		title = "Server",
		kind = "Employee",
		board = "Employees",
		icon = "Gift",
		color = Color3.fromRGB(40, 150, 255),
		startLevel = 0,
		maxLevel = 1,
		effectBase = 1,
		effectStep = 0,
		priceBase = 400,
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	assert(byId[upgrade.id] == nil, "Upgrades : id en double " .. upgrade.id)
	assert(upgrade.effectFactor ~= nil or upgrade.effectStep ~= nil, "Upgrades : effet manquant " .. upgrade.id)
	byId[upgrade.id] = table.freeze(upgrade)
end

Upgrades.List = table.freeze(list)
Upgrades.ById = table.freeze(byId)

-- Niveau maximum (TreeLuck depend des rebirths).
function Upgrades.GetMaxLevel(id: string, rebirths: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	return upgrade.maxLevel or Fruits.MaxLuck(rebirths)
end

-- Effet au niveau `level` (ex. secondes entre deux fruits, nombre de jus max).
function Upgrades.GetValue(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	-- Employe pas embauche (niveau 0) : aucun effet
	if upgrade.kind == "Employee" and level <= 0 then
		return 0
	end
	local n = math.max(level, 1) - 1
	if upgrade.effectFactor then
		return upgrade.effectBase * upgrade.effectFactor ^ n
	end
	return upgrade.effectBase + (upgrade.effectStep :: number) * n
end

-- Prix en argent pour passer du niveau `level` au suivant (entier).
function Upgrades.GetPrice(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	local n = math.max(level, 1) - 1
	return math.floor(upgrade.priceBase * upgrade.priceGrowth ^ n + 0.5)
end

-- Prix Robux affiche (A VALIDER, aucun achat en phase 1).
function Upgrades.GetRobuxPrice(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	return upgrade.robuxBase + upgrade.robuxStep * (math.max(level, 1) - 1)
end

-- Niveaux d'un profil neuf (modele de la sauvegarde).
function Upgrades.DefaultLevels(): { [string]: number }
	local levels = {}
	for _, upgrade in list do
		levels[upgrade.id] = upgrade.startLevel
	end
	return levels
end

return table.freeze(Upgrades)
