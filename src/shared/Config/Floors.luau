--!strict
-- Tour d'etages (phase 1b) : chaque base est une tour de MaxFloors etages, tous copies du meme
-- modele ServerStorage.FloorTemplate (scripts tools/build-map/02*). Etage n = rarete n (ses 10
-- fruits). Ajouter un etage = une rarete de plus dans Fruits + MaxFloors, zero code.
-- Repere de la base : origine au bord avant, +Z vers le fond, vu de la route +X est a gauche.
-- Doc : docs/systems/tour-etages.md

local Floors = {}

Floors.MaxFloors = 10
Floors.FloorHeight = 36 -- etage n : sol a y = FloorHeight * (n - 1) dans le repere de la base

-- Zone STAIRS (sur chaque etage) et les 2 voies d'escalier. L'escalier qui monte de l'etage n est
-- sur la voie A si n est impair, B si n est pair ; il part de StairStartX (sol) et arrive a
-- StairEndX (+FloorHeight), puis palier StairEndX -> LandingEndX contre le mur (x 109).
Floors.StairsZone = table.freeze({ x0 = 60, x1 = 108, z0 = 50, z1 = 84 })
Floors.StairStartX = 64
Floors.StairEndX = 100
Floors.LandingEndX = 108
Floors.Lanes = table.freeze({
	A = table.freeze({ z0 = 57, z1 = 65 }),
	B = table.freeze({ z0 = 70, z1 = 78 }),
})

-- Voie de l'escalier qui MONTE depuis l'etage n.
function Floors.StairLane(n: number): string
	return if n % 2 == 1 then "A" else "B"
end

-- Voie du trou (arrivee de l'escalier du dessous) sur l'etage n ; nil pour l'etage 1.
function Floors.HoleLane(n: number): string?
	if n <= 1 then
		return nil
	end
	return Floors.StairLane(n - 1)
end

-- Variantes gardees au clonage de FloorTemplate (dossiers "Only<Tag>", voir FloorAssembly).
-- closed = etage suivant ferme (coque bleue + vitre rouge d'achat).
function Floors.Tags(n: number, closed: boolean): { [string]: boolean }
	local tags: { [string]: boolean } = {}
	tags[if n == 1 then "Ground" else "Upper"] = true
	local stair = Floors.StairLane(n)
	local hole = Floors.HoleLane(n)
	tags["Stair" .. stair] = true
	for _, lane in { "A", "B" } do
		if lane == hole then
			tags["Hole" .. lane] = true
		else
			tags["Solid" .. lane] = true
		end
	end
	tags[if closed then "Closed" else "Open"] = true
	return tags
end

-- Prix de chaque etage (achat a la vitre rouge en haut de l'escalier), index = numero de l'etage.
-- [1] = 0 : l'etage 1 est offert. A VALIDER (2026-11-20) : calcul de depart = ~12 minutes des gains
-- de la tour quand l'etage d'en dessous est bien ameliore. Etage 1 au max (arbre niveau 10 : un
-- fruit toutes les ~1.65 s, jus moyen ~9 $ avec les raretes) : ~5.6 $/s, soit ~4 000 $ en 12 min.
-- 2026-11-20 (nuit) : arbre niveau 10 = 1 fruit / 0.83 s, jus moyen ~7.8 $ (Luck x1.5) : ~9.3 $/s si
-- le joueur suit le rythme (~9 min pour l'etage 2), ~6.2 $/s avec le Fruit Picker de base (0.8 fruit/s,
-- c'est lui qui bloque). Prix gardes. A VALIDER.
-- Lot 4b : les jus valent ~x5 d'un etage a l'autre (Fruits.FloorValues) : chaque etage coute ~x5.
-- 2026-11-20 (revue de l'economie, validee par l'utilisateur) : tous les prix / 2. L'arbre plafonne
-- un etage (etage 1 : ~9.4 $/s) vers 7-9 min ; avec 5K le joueur n'avait plus rien d'utile a acheter
-- pendant ~8.5 min avant l'etage 2. Simulation (joueur qui achete bien) : etage 2 vers 11 min au lieu
-- de 17, attente max ~4.5 min, etage 10 vers 1 h 25. Avant : 5K / 25K / 125K / ... / 1.95B.
-- 2026-11-20 (suite, "progressif, pas trop rapide ni trop lent") : courbe PROGRESSIVE : x5.5 entre les
-- premiers etages puis jusqu'a x5.8 (les jus restent x5) : le 1er etage arrive vite (accroche de la
-- 1re session), les suivants durent un peu plus. Avec l'ascenseur (achat utile en continu des
-- l'etage 2, ElevatorUpgrades), simulation d'un joueur qui achete bien : etage 2 ~10 min, etages
-- suivants ~11-16 min, attente max ~2-3.5 min, rebirth (10B) ~1 h 55 (un vrai joueur : plus lent).
-- Precedent : 2.5K / 12.5K / 62.5K / 312.5K / 1.55M / 7.8M / 39M / 195M / 975M.
-- Playtest chronometre (robot, profil neuf, 2026-11-20) avec 2K : derniers achats utiles de l'etage 1
-- a 8:05, etage 2 a 12:07 grace a 2 fruits tres rares (+1 650 $) ; sans eux ~14:55, soit ~6.5 min
-- sans achat a la fin de l'etage 1. Etage 2 : 2K -> 1.5K (~2.5 min d'attente). Etage 3 a 29:07.
Floors.Prices = table.freeze({
	0,
	1_500,
	11_000,
	62_000,
	350_000,
	2_000_000,
	11_500_000,
	66_000_000,
	380_000_000,
	2_200_000_000,
})

-- Les ameliorations et employes d'un etage coutent plus cher en haut (memes ids, memes niveaux) :
-- prix de Config/Upgrades x UpgradePriceFactor^(n - 1). ~x5 comme les jus (A VALIDER).
Floors.UpgradePriceFactor = 5

function Floors.UpgradePrice(basePrice: number, n: number): number
	return math.floor(basePrice * Floors.UpgradePriceFactor ^ (math.max(n, 1) - 1) + 0.5)
end

-- Prix de l'etage n (nil si n est hors de la tour).
function Floors.Price(n: number): number?
	return Floors.Prices[n]
end

-- Production en nombres (lot 5, Lib/FloorIncome) : etages ou le joueur n'est pas. A VALIDER en jeu.
-- Fruit Picker (2026-11-20) : un aller-retour = PickerTripSeconds + PickerFruitSeconds par fruit porte
-- (a vitesse x1). Cale sur l'ancien debit mesure a l'oeil : 6 fruits -> 6 / (3 + 6 x 0.75) = 0.8 fruit/s.
-- Debit = fruits portes (PickerCarry) / temps du tour, x vitesse (PickerBaseSpeed x PickerSpeed).
-- Depart (2 fruits, x0.7) : ~0.31 fruit/s ; max (6 fruits, x0.7 x2.4) : ~1.34 fruit/s. A VALIDER.
Floors.PickerTripSeconds = 3
Floors.PickerFruitSeconds = 0.75
-- Waiter (2026-11-20) : un aller-retour table -> comptoir ~ WaiterTripSeconds (mesure en playtest :
-- ~16 s a vitesse x0.65, donc ~21 s a x0.5) pour Gameplay.WaiterCarry jus : 9 / 21 = ~0.43 jus/s.
Floors.WaiterTripSeconds = 21
-- Temps perdu par cycle d'un mixeur avec operateur, en plus du remplissage, du trajet sur le tapis, de
-- la reaction et du mixage (mesure en playtest le 2026-11-20 : ~11 s pour un bol de 12 au tapis 2.53/s).
Floors.BlendCycleExtraSeconds = 0.5
Floors.IncomeTickSeconds = 2 -- les etages en nombres versent leur argent toutes les X s
Floors.ActiveCheckSeconds = 0.4 -- etage ou se trouve le joueur : verifie toutes les X s

-- Ascenseur des clients (terrasse, panneau Elevator, lot 5). Chaque niveau = +X % d'argent par vente
-- aux etages 2+ (Lib/FloorIncome.ElevatorBonus : ventes reelles et en nombres). Revue de l'economie du
-- 2026-11-20 : avant, +X % de vitesse des clients (sans effet des que les clients suivent l'arbre) et
-- 2 000 / 3 000 x1.6 (un niveau rapportait trop peu pour son prix aux etages 2-3). Maintenant un
-- achat toujours utile pendant qu'on economise pour l'etage suivant : 400 / 600 x1.75, 25 niveaux
-- chacun (max : ventes x3 aux etages 2+). La cabine reste animee plus vite / plus remplie (client).
Floors.ElevatorSpeedBonus = 0.04 -- Elevator Speed : +4 % par niveau
Floors.ElevatorCabinBonus = 0.04 -- Bigger Cabin : +4 % par niveau
Floors.ElevatorUpgrades = table.freeze({
	table.freeze({ id = "ElevatorSpeed", title = "Elevator Speed", desc = "More cash from floors 2+", priceBase = 400, priceGrowth = 1.75 }),
	table.freeze({ id = "ElevatorCabin", title = "Bigger Cabin", desc = "More cash from floors 2+", priceBase = 600, priceGrowth = 1.75 }),
})

-- Prix du niveau suivant d'une amelioration de la tour (niveau actuel `level`, 0 = jamais achetee).
function Floors.TowerUpgradePrice(id: string, level: number): number?
	for _, upgrade in Floors.ElevatorUpgrades do
		if upgrade.id == id then
			return math.floor(upgrade.priceBase * upgrade.priceGrowth ^ math.max(level, 0) + 0.5)
		end
	end
	return nil
end

-- Ameliorations de toute la tour (panneau Elevator de la terrasse, lot 5) : niveaux sauvegardes
-- dans Data.TowerUpgrades, remis a 0 au rebirth. Prix / effets : lot 5 (A VALIDER).
Floors.TowerUpgradeDefaults = table.freeze({
	ElevatorSpeed = 0,
	ElevatorCabin = 0,
})
Floors.TowerUpgradeMaxLevel = 25 -- A VALIDER (lot 5)

-- Etage ferme : la vraie coque teintee bleu clair + contour (meme regle que les machines a acheter,
-- valeurs reprises de UpgradeService).
Floors.ClosedColor = Color3.fromRGB(150, 205, 255)
Floors.ClosedTint = 0.72
Floors.ClosedTransparency = 0.18
Floors.ClosedOutline = Color3.fromRGB(110, 185, 255)

-- Textes (anglais : vus par le joueur)
Floors.TitleFormat = "FLOOR %d" -- vitre rouge d'achat (lot 4b : plus de nom de rarete, chaque etage a les 10)
Floors.TerraceTitle = "???" -- vitre rouge de la terrasse : nom cache comme le Rebirth (utilisateur, 2026-11-20)
Floors.TerraceLockedText = "Opens with Floor 2"
Floors.RebirthLockedText = "Reach Floor 10"
Floors.RebirthRoomTitle = "???" -- salle du Rebirth : nom cache (mystere) tant qu'elle est fermee (utilisateur, 2026-11-20)
Floors.RebirthRoomOpenTitle = "REBIRTH" -- panneau de la salle une fois ouverte (etage 10, phase 4)
Floors.PromptBuyObject = "Floor %d" -- prompt E de la vitre d'achat (ObjectText)
Floors.PromptRebirthObject = "Rebirth" -- prompt E de la machine doree (actif seulement salle ouverte)
Floors.PromptRebirthAction = "Open" -- ouvre le menu Rebirth (RebirthController)
Floors.Messages = table.freeze({
	NotEnoughMoney = "Not enough money!",
	NewFloor = "Floor %d unlocked!",
	NeedPreviousFloor = "Buy the floor below first!",
})
Floors.BuyCooldown = 1 -- secondes entre deux achats d'etage (anti double appui)
Floors.TeleportCooldown = 0.5 -- secondes entre deux teleports (remote FloorTeleport, fleches du selecteur)
Floors.SelectorMinFloors = 3 -- selecteur "< Floor N >" en haut de l'ecran a partir de 3 etages achetes
Floors.StreamTimeout = 3 -- secondes max pour charger l'etage d'arrivee avant un teleport (StreamingEnabled)

return table.freeze(Floors)
