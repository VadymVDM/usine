--!strict
-- Ameliorations et employes de la zone 1 : effets, prix en argent, prix Robux (bouton violet des tuiles).
-- Ou s'achete chaque id dans l'usine (refonte du 2026-11-19 soir : "on comprend pas a quoi ca sert") :
--   * Tree : un pad vert a cote de l'arbre ("Upgrade Tree"), on se tient dessus (repeatPad) ;
--   * Blender1..4 : la vraie machine teintee bleu pour l'acheter (E), puis un panneau suspendu
--     au-dessus de chaque mixeur pour ses 5 niveaux (Boards.BlenderSignN) ;
--   * ConveyorSpeed, JuiceLimit, CustomerSpeed, CustomerCount : tuiles de panneaux muraux
--     (Boards.ConveyorBoard / JuiceTableBoard / SalesBoard), avec une phrase qui dit a quoi ca sert ;
--   * employes : pad vert a leur poste (Machines.<id>.Pad, BlenderN.Operator) ;
--   * PickerSpeed : panneau Fruit Picker (Boards.PickerBoard, mur du fond derriere la zone du
--     Fruit Picker) : il marche plus vite ; demande le Fruit Picker embauche (requires).
--     PickerCarry : meme panneau, tuile du dessous : nombre de fruits portes (2 -> 6).
-- Chaque niveau se VOIT dans l'usine : pieces "LookId / LookLevel" (client LevelLookController),
-- arbre qui change de modele a chaque niveau (TreeService).
-- Valeurs de depart a equilibrer en test : tableau dans docs/systems/ameliorations-employes.md.
-- Le serveur est le seul a utiliser ces prix pour un achat ; le client les affiche seulement.

local Fruits = require(script.Parent.Fruits)

export type UpgradeId =
	"Tree"
	| "ConveyorSpeed"
	| "JuiceLimit"
	| "CustomerSpeed"
	| "CustomerCount"
	| "Collector"
	| "PickerSpeed"
	| "PickerCarry"
	| "Waiter"
	| "Blender1"
	| "Blender2"
	| "Blender3"
	| "Blender4"
	| "Operator1"
	| "Operator2"
	| "Operator3"
	| "Operator4"

export type Upgrade = {
	id: UpgradeId,
	title: string, -- texte affiche sur la tuile (anglais)
	desc: string?, -- petite phrase sous le titre : a quoi ca sert (anglais)
	kind: "Upgrade" | "Employee",
	machine: string, -- nom de la machine / du poste dans l'usine (affiche au-dessus du pad, anglais)
	-- Vrai si l'effet n'existe pas encore : achat refuse ("Coming soon!"). Aucun en ce moment.
	comingSoon: boolean?,
	icon: string, -- cle de Config/Icons.luau
	color: Color3, -- couleur de la tuile
	startLevel: number, -- niveau d'un profil neuf (employe ou machine a acheter : 0)
	maxLevel: number?, -- nil = Fruits.PerRarity
	-- Niveau a partir duquel la machine est construite (defaut : startLevel + 1). Blender1 : 1 (offert).
	builtAt: number?,
	-- Pad qui reste la apres l'achat : se tenir dessus achete 1 niveau, puis 1 de plus toutes les
	-- Gameplay.PadRepeatSeconds tant qu'on reste dessus (Tree).
	repeatPad: boolean?,
	-- Effet au niveau n : effectValues[n] si la liste existe, sinon base * factor^(n-1) si
	-- `factor`, sinon base + step*(n-1).
	effectBase: number,
	effectFactor: number?,
	effectStep: number?,
	effectValues: { number }?,
	-- Affichage de l'effet sur les tuiles (string.format), ex. "%.1f/s" ; defaut : entier, ou "%.1fs" si factor < 1.
	format: string?,
	-- Achat possible seulement si cet autre id a ete achete (niveau > son startLevel).
	-- Ex. Blender3 demande Blender2 ; Operator2 demande Blender2. Sinon : machine "verrouillee".
	requires: string?,
	-- Prix pour passer du niveau n au niveau n+1 : prices[n + 1] si la liste existe, sinon
	-- priceBase * priceGrowth^(n-1), arrondi. Pour un employe (niveau 0 -> 1) : priceBase.
	prices: { number }?,
	priceBase: number,
	priceGrowth: number,
	-- Prix Robux : robuxBase + robuxStep*(n-1), plafonne a Upgrades.RobuxMax.
	robuxBase: number,
	robuxStep: number,
}

local Upgrades = {}

-- Prix Robux des tuiles (5, 8, puis 9 R$ ; un produit par prix : Upgrades.RobuxProducts).
local ROBUX_BASE = 5
local ROBUX_STEP = 3
Upgrades.RobuxMax = 9 -- plafond du prix Robux sur les panneaux d'achat (demande utilisateur 2026-11-23)
-- Bouton violet des tuiles (2026-11-23) : un Developer Product par prix Robux possible (Roblox : prix
-- fixe par produit). Le serveur note quelle tuile a ete cliquee et donne +1 niveau au recu.
-- Crees par Open Cloud le 2026-11-23 ("Machine Upgrade I / II / III"). Prix Roblox = cle.
Upgrades.RobuxProducts = table.freeze({
	[5] = 3734912690,
	[8] = 3734912738,
	[9] = 3734912752,
} :: { [number]: number })
Upgrades.RobuxPendingSeconds = 600 -- tuile cliquee gardee en memoire ce temps (puis recu = meilleure tuile au meme prix)
Upgrades.ReceiptWaitSeconds = 20 -- recu : attente max de la sauvegarde du joueur (il vient d'arriver)

-- Arbre : chaque niveau fait surtout tomber les fruits PLUS VITE (effet visible), et un peu de Luck.
-- (Avant le 2026-11-19 soir : deux machines, Sprinkler = vitesse et Lucky Fertilizer = luck.)
-- 2026-11-20 (nuit) : "la vitesse plutot que la chance" : x0.955 -> x0.885 par niveau, soit x3 au
-- niveau 10 (2.5 s -> ~0.83 s ; avant ~1.65 s) ; Fruits.LuckMax 4 -> 1.5. A VALIDER en jeu.
local TREE_DROP_SECONDS = 2.5 -- niveau 1 : 1 fruit toutes les 2.5 s
local TREE_DROP_FACTOR = 0.885 -- x0.885 par niveau (niveau 10, le max : ~0.83 s = 3x plus vite)
local TREE_DROP_MIN = 0.6

local list: { Upgrade } = {
	{
		id = "Tree",
		title = "Upgrade Tree",
		desc = "Faster drops + luck",
		kind = "Upgrade",
		machine = "Upgrade Tree",
		icon = "Clover",
		color = Color3.fromRGB(60, 200, 80),
		startLevel = 1,
		maxLevel = 10, -- tour d'etages (2026-11-20) : l'arbre d'un etage a les 10 fruits de sa rarete
		builtAt = 1, -- l'arbre est toujours la : le pad sert seulement a l'ameliorer
		repeatPad = true,
		effectBase = 1, -- nombre de fruits possibles (= niveau)
		effectStep = 1,
		priceBase = 15, -- = 3 pommes : premier achat vers 0:35
		priceGrowth = 1.32,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "ConveyorSpeed",
		title = "Conveyor Speed",
		desc = "Fruits reach blenders faster",
		kind = "Upgrade",
		machine = "Conveyor",
		icon = "Lightning",
		color = Color3.fromRGB(35, 190, 245), -- cyan (palette des captures)
		startLevel = 1,
		maxLevel = 10,
		effectBase = 2.2, -- fruits envoyes par seconde par le tapis
		effectFactor = 1.15,
		format = "%.1f/s",
		priceBase = 60,
		-- 1.55 -> 1.3 (2026-11-20, revue) : 2.2 fruits/s des le niveau 1 depasse deja l'arbre au max
		-- (1.2/s) ; les niveaux suivants servent peu (remplissage du bol) : total ~5.5K -> ~1.9K.
		priceGrowth = 1.3,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "JuiceLimit",
		title = "Juice Table",
		desc = "Holds more juices",
		kind = "Upgrade",
		machine = "Juice Table",
		icon = "PotionGreen",
		color = Color3.fromRGB(180, 50, 235), -- violet
		startLevel = 1,
		maxLevel = 9,
		effectBase = 10, -- jus max sur la table a jus
		effectStep = 5,
		priceBase = 30,
		priceGrowth = 1.5,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "CustomerSpeed",
		title = "Faster Customers",
		desc = "Time between customers",
		kind = "Upgrade",
		machine = "Faster Customers",
		icon = "Clock",
		color = Color3.fromRGB(180, 50, 235), -- violet
		startLevel = 1,
		maxLevel = 15,
		-- 2026-11-20 (revue de l'economie) : 2.5 s -> 1.8 s au depart. Avant, 1 client / 2.5 s = 0.4 jus/s =
		-- exactement l'arbre niveau 1 : les premiers "Upgrade Tree" ne rapportaient pas un dollar de plus.
		-- x0.92 -> x0.942 : le niveau 15 reste a ~0.78 s comme avant (meme nombre de clients dessines).
		effectBase = 1.8, -- secondes entre deux passages de clients
		effectFactor = 0.942,
		priceBase = 80,
		priceGrowth = 1.25, -- 1.45 -> 1.25 : la fin (inutile une fois l'arbre au max) coutait ~32K a l'etage 1
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "CustomerCount",
		title = "More Customers",
		desc = "Customers buying at once",
		kind = "Upgrade",
		machine = "More Customers",
		icon = "Customers",
		color = Color3.fromRGB(250, 225, 35), -- jaune
		startLevel = 1,
		maxLevel = 5,
		effectBase = 1, -- clients a chaque passage (1 jus chacun)
		effectStep = 1,
		-- 2026-11-20 (revue) : 300 x2.5 -> 150 x2 (150 / 300 / 600 / 1 200) : le niveau 2 double les
		-- ventes, c'est l'achat le plus utile du debut ; atteignable vers 2-3 min au lieu de ~3-20 min.
		priceBase = 150,
		priceGrowth = 2,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		id = "Collector",
		title = "Collector",
		kind = "Employee",
		machine = "Fruit Picker",
		icon = "Magnet",
		color = Color3.fromRGB(60, 200, 80),
		startLevel = 0,
		maxLevel = 1,
		effectBase = 1,
		effectStep = 0,
		priceBase = 25, -- 40 -> 25 (2026-11-19, demande utilisateur)
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		-- Vitesse du Fruit Picker (2026-11-20, demande : "un panneau sur le mur a cote du fruit
		-- picker qui permet de l'accelerer") : multiplie sa vitesse de marche et raccourcit ses
		-- pauses (WorkerService) et son debit en nombres (FloorIncome).
		id = "PickerSpeed",
		title = "Picker Speed",
		desc = "Fruit Picker walks faster",
		kind = "Upgrade",
		machine = "Fruit Picker",
		icon = "Shoe",
		color = Color3.fromRGB(60, 200, 80), -- vert (couleur du Fruit Picker)
		startLevel = 1,
		maxLevel = 11, -- 8 -> 11 (2026-11-21, demande : "3 niveaux pour la rapidite")
		builtAt = 1, -- le panneau est toujours la
		effectBase = 1, -- multiplicateur de vitesse (x1 -> x3.0)
		effectStep = 0.2,
		format = "x%.1f",
		requires = "Collector", -- il faut d'abord embaucher le Fruit Picker
		priceBase = 40,
		priceGrowth = 1.6,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	{
		-- Fruits portes par le Fruit Picker (2026-11-20, demande : "il prend seulement 2 fruits, et
		-- sur le panneau on peut ameliorer le nombre qu'il prend, max 6") : 2 -> 6. Tuile sous
		-- Picker Speed sur le panneau Fruit Picker. Lu par WorkerService et FloorIncome.
		id = "PickerCarry",
		title = "Picker Hands",
		desc = "Carries more fruits",
		kind = "Upgrade",
		machine = "Fruit Picker",
		icon = "Plus",
		color = Color3.fromRGB(60, 200, 80), -- vert (couleur du Fruit Picker)
		startLevel = 1,
		maxLevel = 8, -- 5 -> 8 (2026-11-21, demande : "3 niveaux pour le nombre de fruits")
		builtAt = 1, -- le panneau est toujours la
		effectBase = 2, -- fruits portes (2 -> 9)
		effectStep = 1,
		requires = "Collector",
		priceBase = 50, -- 50, 95, 180, 343, 652, 1.2K, 2.4K (A VALIDER)
		priceGrowth = 1.9,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
	-- (id "Server" = l'ancien Waiter, retire le 2026-11-20 : remplace par le pass Robux Auto Sell,
	-- devenu Instant Sell le 2026-11-21 : Config/Shop.Passes + PassPadService.)
	{
		-- Serveur (2026-11-20, demande : "on paye l'employe qui ramene les boissons vers le comptoir,
		-- il est lent, on l'achete avec l'argent du jeu ; des qu'on l'achete le pad se transforme en
		-- pad violet Auto Sell"). Pad vert a cote du pad Take Juices ; WorkerService (runWaiter).
		-- Nouvel id "Waiter" (l'ancien "Server" est efface des sauvegardes par DataService).
		id = "Waiter",
		title = "Waiter",
		kind = "Employee",
		machine = "Waiter",
		icon = "Rebirth",
		color = Color3.fromRGB(70, 160, 255),
		startLevel = 0,
		maxLevel = 1,
		effectBase = 1,
		effectStep = 0,
		priceBase = 400, -- comme l'ancien Waiter (A VALIDER)
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
	},
}

-- Mixeurs (2026-11-19 soir) : chacun a 5 niveaux ; le niveau donne la taille de SON bol (plus de
-- fruits = plus de jus d'un coup) et change son look. Le 1 est offert (niveau 1), les 2 a 4
-- s'achetent dans l'ordre (niveau 0 -> 1 = la machine bleue se construit), puis s'ameliorent sur
-- leur panneau. Avant : une seule amelioration "Bigger Bowl" pour tous les bols.
local BOWL_SIZES = { 5, 8, 12, 16, 20 } -- fruits max dans le bol, par niveau
-- 2026-11-20 (revue de l'economie) : l'arbre au max (1.2 fruit/s) est deja suivi par le mixeur 1
-- (bol 12 + operateur = 1.34 jus/s). Les mixeurs 2-4 et leurs niveaux ne font presque pas monter
-- l'argent : avant ils coutaient ~105K a l'etage 1 (21 x le prix de l'etage 2) et un joueur qui
-- achete tout ce qui brille restait coince a l'etage 1. Prix baisses (~11K), rien n'est retire.
-- Avant : achat 0 / 250 / 1200 / 5000 ; niveaux 120 / 500 / 2000 / 8000 ; facteurs 1 / 1.5 / 2.5 / 4 ;
-- operateurs 150 / 400 / 1500 / 5000.
local BLENDER_PRICES = { 0, 250, 500, 1000 } -- achat du mixeur N (le 1 est offert)
local BLENDER_UPGRADES = { 100, 200, 400, 800 } -- niveau 1 -> 2, 2 -> 3, 3 -> 4, 4 -> 5 (mixeur 1)
local BLENDER_FACTORS = { 1, 1.2, 1.4, 1.6 } -- les mixeurs suivants coutent plus cher a ameliorer
local OPERATOR_PRICES = { 150, 300, 500, 800 } -- l'operateur 1 coute comme l'ancien Blender Operator
for n = 1, 4 do
	local prices = { BLENDER_PRICES[n] }
	for _, price in BLENDER_UPGRADES do
		table.insert(prices, math.floor(price * BLENDER_FACTORS[n] + 0.5))
	end
	table.insert(list, {
		id = "Blender" .. n,
		title = "Blender " .. n,
		desc = "Bigger bowl: more juices",
		kind = "Upgrade",
		machine = "Blender " .. n,
		icon = "PotionBlue",
		color = Color3.fromRGB(235, 35, 45), -- rouge
		startLevel = if n == 1 then 1 else 0,
		maxLevel = #BOWL_SIZES,
		builtAt = 1,
		effectBase = BOWL_SIZES[1],
		effectValues = BOWL_SIZES,
		prices = prices,
		priceBase = prices[1],
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
		requires = if n > 2 then "Blender" .. (n - 1) else nil,
	} :: any)
end
for n = 1, 4 do
	table.insert(list, {
		id = "Operator" .. n,
		title = "Operator " .. n,
		kind = "Employee",
		machine = "Blender Operator",
		icon = "Rebirth",
		color = Color3.fromRGB(255, 150, 30),
		startLevel = 0,
		maxLevel = 1,
		effectBase = 1,
		effectStep = 0,
		priceBase = OPERATOR_PRICES[n],
		priceGrowth = 1,
		robuxBase = ROBUX_BASE,
		robuxStep = ROBUX_STEP,
		requires = if n > 1 then "Blender" .. n else nil,
	} :: any)
end

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	assert(byId[upgrade.id] == nil, "Upgrades : id en double " .. upgrade.id)
	assert(upgrade.effectFactor ~= nil or upgrade.effectStep ~= nil or upgrade.effectValues ~= nil, "Upgrades : effet manquant " .. upgrade.id)
	byId[upgrade.id] = table.freeze(upgrade)
end
for _, upgrade in list do
	assert(upgrade.requires == nil or byId[upgrade.requires] ~= nil, "Upgrades : requires inconnu " .. upgrade.id)
end

-- Messages d'achat (anglais, envoyes par UpgradeService avec le remote Notify)
Upgrades.Messages = table.freeze({
	NotEnoughMoney = "Not enough money!",
	MaxLevel = "Max level!",
	ComingSoon = "Coming soon!",
	RobuxSoon = "Robux purchases: coming soon!",
	NeedsFirst = "Buy %s first!", -- %s = machine demandee (ex. "Blender 2")
})

Upgrades.List = table.freeze(list)
Upgrades.ById = table.freeze(byId)

-- Niveau maximum. `rebirths` est garde pour plus tard (aucun maximum n'en depend depuis la tour
-- d'etages : Tree = les 10 fruits de la rarete de l'etage).
function Upgrades.GetMaxLevel(id: string, _rebirths: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	return upgrade.maxLevel or Fruits.PerRarity
end

-- Effet au niveau `level` (ex. nombre de jus max, fruits par seconde du tapis).
function Upgrades.GetValue(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	-- Employe pas embauche (niveau 0) : aucun effet
	if upgrade.kind == "Employee" and level <= 0 then
		return 0
	end
	local values = upgrade.effectValues
	if values then
		return values[math.clamp(math.floor(level), 1, #values)]
	end
	local n = math.max(level, 1) - 1
	if upgrade.effectFactor then
		return upgrade.effectBase * upgrade.effectFactor ^ n
	end
	return upgrade.effectBase + (upgrade.effectStep :: number) * n
end

-- Texte de l'effet sur les tuiles (ex. "2.2/s", "15", "2.3s").
function Upgrades.FormatValue(id: string, value: number): string
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	if upgrade.format then
		return string.format(upgrade.format, value)
	end
	if upgrade.effectFactor and upgrade.effectFactor < 1 then
		return string.format("%.1fs", value)
	end
	return tostring(math.floor(value + 0.5))
end

-- Secondes entre deux chutes de fruits pour un niveau d'arbre.
function Upgrades.TreeDropSeconds(level: number): number
	return math.max(TREE_DROP_MIN, TREE_DROP_SECONDS * TREE_DROP_FACTOR ^ (math.max(level, 1) - 1))
end

-- Prix en argent pour passer du niveau `level` au suivant (entier).
function Upgrades.GetPrice(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	local prices = upgrade.prices
	if prices then
		return prices[math.clamp(math.floor(level) + 1, 1, #prices)]
	end
	local n = math.max(level, 1) - 1
	return math.floor(upgrade.priceBase * upgrade.priceGrowth ^ n + 0.5)
end

-- Prix Robux du bouton violet d'une tuile pour passer du niveau `level` au suivant.
function Upgrades.GetRobuxPrice(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	return math.min(upgrade.robuxBase + upgrade.robuxStep * (math.max(level, 1) - 1), Upgrades.RobuxMax)
end

-- Developer Product a ouvrir pour ce prix Robux (nil = aucun produit a ce prix).
function Upgrades.RobuxProductFor(id: string, level: number): number?
	return Upgrades.RobuxProducts[Upgrades.GetRobuxPrice(id, level)]
end

-- Au demarrage : chaque prix Robux affiche doit avoir son produit (sinon le bouton ne marcherait pas)
for _, upgrade in list do
	for level = 0, Upgrades.GetMaxLevel(upgrade.id, 0) - 1 do
		local price = Upgrades.GetRobuxPrice(upgrade.id, level)
		assert(Upgrades.RobuxProducts[price], `Upgrades : pas de produit Robux a {price} R$ ({upgrade.id} niveau {level})`)
	end
end

-- Niveau a partir duquel la machine de cet id est construite (voir `builtAt`).
function Upgrades.BuiltAt(id: string): number
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	return upgrade.builtAt or (upgrade.startLevel + 1)
end

-- Vrai si l'id demande un autre achat pas encore fait (`levels` = Data.Upgrades, ou nil = profil neuf).
function Upgrades.IsLocked(id: string, levels: { [string]: number }?): boolean
	local upgrade = byId[id]
	assert(upgrade, "Upgrades : id inconnu")
	local required = upgrade.requires and byId[upgrade.requires]
	if required == nil then
		return false
	end
	local level = if levels then levels[required.id] or required.startLevel else required.startLevel
	return level <= required.startLevel
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
