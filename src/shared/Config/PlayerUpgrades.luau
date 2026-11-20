--!strict
-- Ameliorations du JOUEUR (bouton vert "UPGRADE" du HUD, menu Upgrade) : elles le suivent partout,
-- sur tous les etages (pas comme Config/Upgrades, qui sont celles de chaque etage).
--   * WalkSpeed : vitesse de marche (Humanoid.WalkSpeed) ;
--   * FruitCarry : fruits sur le plateau au-dessus de la tete (remplace Gameplay.CarryCapacity) ;
--   * JuiceCarry : jus portes (remplace Gameplay.JuiceCarryCapacity).
-- 5 achats max (niveau 1 -> 6, affiche "Lv 0/5" ... "Lv 5/5"). Les 3 premiers achats se paient avec
-- l'argent du jeu (cashPrices), les 2 suivants en ROBUX : 9 R$ chacun (demande utilisateur du 2026-11-20).
-- Un Developer Product par amelioration (achetable plusieurs fois), productId = 0 tant qu'il n'est
-- pas cree sur le site Roblox ("Coming soon!"). Le serveur (PlayerUpgradeService) ouvre la fenetre
-- d'achat et donne le niveau a la reception du recu ; le client affiche seulement.
-- Effets A VALIDER en jouant. Doc : docs/systems/ameliorations-joueur.md

local Gameplay = require(script.Parent.Gameplay)

export type PlayerUpgradeId = "WalkSpeed" | "FruitCarry" | "JuiceCarry"

export type PlayerUpgrade = {
	id: PlayerUpgradeId,
	order: number, -- ordre dans le menu
	title: string, -- anglais (affiche)
	unit: string, -- mot apres le nombre : "16 → 18 speed" (anglais)
	icon: string?, -- cle de Config/Icons.luau (nil = fruit 3D)
	maxLevel: number, -- niveau 1 = profil neuf ; maxLevel - 1 = nombre d'achats possibles
	effectBase: number, -- effet au niveau 1
	effectStep: number, -- + par niveau
	cashPrices: { number }, -- prix en argent du jeu des premiers achats ([1] = niveau 1 -> 2, ...)
	productId: number, -- Developer Product Roblox des achats suivants (prix = RobuxPrice) ; 0 = pas encore cree
}

local MAX_LEVEL = 6 -- 5 achats maximum

local list: { PlayerUpgrade } = {
	{
		id = "WalkSpeed",
		order = 1,
		title = "Speed",
		unit = "speed",
		icon = "Shoe",
		maxLevel = MAX_LEVEL,
		effectBase = 16 * 1.15 * 1.1, -- vitesse Roblox par defaut (16) x1.15 puis x1.1 = 20.24 (demandes du 2026-11-20)
		effectStep = 3, -- niveau 6 : 35.24
		cashPrices = { 40, 140, 490 },
		productId = 0,
	},
	{
		id = "FruitCarry",
		order = 2,
		title = "Fruit Tray",
		unit = "fruits",
		icon = nil, -- pomme 3D
		maxLevel = MAX_LEVEL,
		effectBase = Gameplay.CarryCapacity, -- 20
		effectStep = 8, -- niveau 6 : 60 (TrayController.MAX_FRUITS = 60 : ne pas depasser)
		cashPrices = { 30, 105, 370 },
		productId = 0,
	},
	{
		id = "JuiceCarry",
		order = 3,
		title = "Juice Tray",
		unit = "juices",
		icon = "PotionBlue",
		maxLevel = MAX_LEVEL,
		effectBase = Gameplay.JuiceCarryCapacity, -- 18 (2 couches de 3 x 3)
		effectStep = 5, -- niveau 6 : 43 (avant : 42 au niveau 9)
		cashPrices = { 30, 105, 370 },
		productId = 0,
	},
}

local byId: { [string]: PlayerUpgrade } = {}
for _, upgrade in list do
	assert(byId[upgrade.id] == nil, "PlayerUpgrades : id en double " .. upgrade.id)
	byId[upgrade.id] = table.freeze(upgrade)
end

local PlayerUpgrades = {}

PlayerUpgrades.List = table.freeze(list)
PlayerUpgrades.ById = table.freeze(byId)
PlayerUpgrades.RobuxPrice = 9 -- prix d'UN niveau ; a recopier dans chaque Developer Product sur Roblox
PlayerUpgrades.BuyCooldownSeconds = 0.5 -- delai minimum entre deux demandes d'achat (clics rapides)
PlayerUpgrades.ReceiptWaitSeconds = 15 -- recu arrive avant la sauvegarde : attente max
PlayerUpgrades.AttributePrefix = "PUp_" -- attribut joueur "PUp_WalkSpeed" = niveau (lu par le client)
PlayerUpgrades.Messages = table.freeze({
	MaxLevel = "Max level!",
	NotEnoughMoney = "Not enough money!",
	ComingSoon = "Robux upgrades: coming soon!",
})

-- Effet au niveau `level` (vitesse, nombre de fruits, nombre de jus).
function PlayerUpgrades.GetValue(id: string, level: number): number
	local upgrade = byId[id]
	assert(upgrade, "PlayerUpgrades : id inconnu")
	local n = math.clamp(math.floor(level), 1, upgrade.maxLevel) - 1
	return upgrade.effectBase + upgrade.effectStep * n
end

-- Prix en argent du jeu pour passer du niveau `level` au suivant, ou nil si ce niveau se paie en Robux.
function PlayerUpgrades.GetCashPrice(id: string, level: number): number?
	local upgrade = byId[id]
	assert(upgrade, "PlayerUpgrades : id inconnu")
	return upgrade.cashPrices[math.max(math.floor(level), 1)]
end

-- Nombre d'achats faits / possibles ("Lv 2/5" dans le menu).
function PlayerUpgrades.Bought(level: number): number
	return math.max(math.floor(level), 1) - 1
end

function PlayerUpgrades.MaxBought(id: string): number
	local upgrade = byId[id]
	assert(upgrade, "PlayerUpgrades : id inconnu")
	return upgrade.maxLevel - 1
end

-- Niveaux d'un profil neuf (modele de la sauvegarde).
function PlayerUpgrades.DefaultLevels(): { [string]: number }
	local levels = {}
	for _, upgrade in list do
		levels[upgrade.id] = 1
	end
	return levels
end

return table.freeze(PlayerUpgrades)
