--!strict
-- Les 100 fruits (10 raretes x 10 fruits), valeurs, couleurs de jus et chances.
-- Regle du 2026-11-20 (lot 4b, remplace "1 etage = 1 rarete") : CHAQUE ETAGE A LES 10 RARETES.
-- Etage n = la ligne n du tableau (le n-ieme fruit de chaque rarete, voir docs/systems/fruits.md).
-- Valeur = valeur de l'etage x bonus de rarete ; chance = selon la rarete seule (+ Luck de l'arbre).
-- Doc : docs/systems/fruits.md

export type Rarity = {
	id: string,
	name: string,
	color: Color3,
	outline: Color3?, -- nil = pas de contour (Common) ou arc-en-ciel anime plus tard (Infinity)
}

export type Fruit = {
	id: string, -- id stable pour la sauvegarde (DiscoveredFruits)
	index: number, -- 1..100, ordre de deblocage (Luck)
	name: string, -- nom affiche (anglais)
	rarity: number, -- 1..10
	floor: number, -- 1..10 : etage ou ce fruit pousse (sa place dans sa rarete)
	value: number, -- prix du jus, entier (FloorValues[floor] x RarityBonus[rarity])
	juiceColor: Color3,
	weight: number, -- poids de tirage a Luck 1 (= 1 / chance de la rarete ; voir RollWeights)
}

-- Entree ecrite a la main ; index, rarity, floor, value et weight sont remplis par la boucle plus bas.
type FruitEntry = {
	id: string,
	name: string,
	juiceColor: Color3,
}

local Fruits = {}

Fruits.Rarities = {
	{ id = "Common", name = "Common", color = Color3.fromRGB(160, 160, 165), outline = nil },
	{ id = "Uncommon", name = "Uncommon", color = Color3.fromRGB(60, 200, 70), outline = Color3.fromRGB(60, 220, 60) },
	{ id = "Rare", name = "Rare", color = Color3.fromRGB(50, 130, 255), outline = Color3.fromRGB(40, 120, 255) },
	{ id = "Epic", name = "Epic", color = Color3.fromRGB(165, 80, 240), outline = Color3.fromRGB(170, 70, 245) },
	{ id = "Legendary", name = "Legendary", color = Color3.fromRGB(255, 195, 40), outline = Color3.fromRGB(255, 200, 40) },
	{ id = "Mythic", name = "Mythic", color = Color3.fromRGB(240, 60, 50), outline = Color3.fromRGB(245, 50, 40) },
	{ id = "Godly", name = "Godly", color = Color3.fromRGB(250, 250, 250), outline = Color3.fromRGB(255, 255, 255) },
	{ id = "Celestial", name = "Celestial", color = Color3.fromRGB(130, 225, 255), outline = Color3.fromRGB(150, 235, 255) },
	{ id = "Glitched", name = "Glitched", color = Color3.fromRGB(255, 50, 220), outline = Color3.fromRGB(255, 40, 220) },
	{ id = "Infinity", name = "Infinity", color = Color3.fromRGB(255, 120, 190), outline = nil },
} :: { Rarity }

-- Chances de depart (Luck 1) : "1 sur X" par rarete (Common : le reste, presque toujours).
-- 2026-11-20 (soir) : raretes Rare+ rendues plus rares ("on peut pas l'avoir facilement", tout l'Index
-- = 10 h de jeu minimum). Simulation (arbre monte au niveau 10 en ~20 min, puis au max), temps median
-- pour voir chaque rarete sur UN etage : Rare ~40 s, Epic ~2 min, Legendary ~6 min, Mythic ~13 min,
-- Godly ~25 min, Celestial ~55 min, Glitched ~2 h, Infinity ~4.5 h (tout l'etage : ~6 h ; on ne
-- decouvre que sur l'etage ou on est, donc les 100 fruits = bien plus de 10 h). A VALIDER.
Fruits.OneInByRarity = table.freeze({ 0, 4, 20, 75, 300, 1_000, 3_000, 8_000, 20_000, 50_000 })
-- Le Common prend le reste des chances a Luck 1 (calcule : 1 - somme des 1/X, ~0.68)
local commonRest = 1
for r = 2, #Fruits.OneInByRarity do
	commonRest -= 1 / Fruits.OneInByRarity[r]
end
Fruits.CommonWeight = commonRest
-- Garde-fou : le Common reste le plus frequent (poids >= CommonLead x le plus gros autre poids)
Fruits.CommonLead = 1.05
-- Luck (niveau Tree de l'etage) : multiplie les chances des raretes >= LuckFromRarity (Rare+ ; pas
-- l'Uncommon, sinon il depasse vite le Common). x1 au niveau 1 -> x LuckMax au niveau 10.
-- 5 -> 4 le 2026-11-20 (soir) : les raretes tombaient trop vite une fois l'arbre ameliore.
-- 4 -> 1.5 le 2026-11-20 (nuit) : l'arbre mise sur la vitesse (x3 au niveau 10, Upgrades
-- TREE_DROP_FACTOR). Plus de fruits = plus de tirages : au niveau 10, ~7.1 Rare+ par minute
-- (avant ~8.2), donc les temps de la simulation ci-dessus bougent peu (~15 % plus lents). A VALIDER.
Fruits.LuckFromRarity = 3
Fruits.LuckMax = 1.5
-- Bonus de chance des premiers etages (Rare+, comme la Luck) : le joueur voit plus vite des fruits
-- differents au debut. Index = numero d'etage ; absent = x1. Ajoute le 2026-11-23 ("un tout petit
-- peu plus souvent"). A VALIDER.
Fruits.FloorLuck = table.freeze({ 2, 1.5 })
-- Valeur d'un jus = FloorValues[etage] x RarityBonus[rarete]. ~x5 par etage. A VALIDER.
Fruits.FloorValues = table.freeze({ 5, 25, 125, 625, 3_125, 15_625, 78_125, 390_625, 1_953_125, 9_765_625 })
Fruits.RarityBonus = table.freeze({ 1, 2, 3, 5, 8, 15, 30, 60, 120, 250 })
-- Index : recompense "CLAIM" (une seule fois par fruit decouvert) = FloorValues[etage] x ClaimBonus[rarete].
-- On ne decouvre un fruit que sur l'etage ou on est : le montant suit donc l'etage du joueur.
-- Regle (2026-11-20 soir, "un rare ne doit pas donner enorme des le 1er arbre") : les 10 CLAIM d'un
-- etage ensemble = ~40 % du prix de l'etage suivant (avant : ~3.8x le prix, un Glitched de l'etage 1
-- payait l'etage 2). Etage 1 : Apple 10 $, Dragon Fruit 30 $, Golden Apple 75 $, Rainbow Apple 750 $
-- (~2 min des gains de l'etage 1 au max). Etage 10 : Apricot ~20 M$, Juice God Fruit ~1.5 B$. A VALIDER.
-- 2026-11-20 (revue) : prix des etages / 2 -> les 10 CLAIM = ~80 % de l'etage suivant, mais le plus
-- gros (Infinity, 1 chance sur ~35 000) = 30 % ; avant l'etage 2 on ne trouve en pratique que
-- Common -> Legendary (~185 $ = 7 %). Montants gardes : ils donnent un coup de pouce au debut.
Fruits.ClaimBonus = table.freeze({ 2, 4, 6, 10, 15, 25, 40, 60, 90, 150 })

-- Common
local common: { FruitEntry } = {
	{ id = "Apple", name = "Apple", juiceColor = Color3.fromRGB(230, 40, 40) },
	{ id = "Orange", name = "Orange", juiceColor = Color3.fromRGB(255, 140, 20) },
	{ id = "Banana", name = "Banana", juiceColor = Color3.fromRGB(250, 235, 140) },
	{ id = "Pear", name = "Pear", juiceColor = Color3.fromRGB(215, 225, 120) },
	{ id = "Lemon", name = "Lemon", juiceColor = Color3.fromRGB(255, 240, 60) },
	{ id = "Lime", name = "Lime", juiceColor = Color3.fromRGB(120, 220, 40) },
	{ id = "Grape", name = "Grape", juiceColor = Color3.fromRGB(120, 40, 160) },
	{ id = "Plum", name = "Plum", juiceColor = Color3.fromRGB(130, 40, 110) },
	{ id = "Peach", name = "Peach", juiceColor = Color3.fromRGB(255, 175, 130) },
	{ id = "Apricot", name = "Apricot", juiceColor = Color3.fromRGB(255, 170, 60) },
}

-- Uncommon
local uncommon: { FruitEntry } = {
	{ id = "Strawberry", name = "Strawberry", juiceColor = Color3.fromRGB(240, 50, 80) },
	{ id = "Cherry", name = "Cherry", juiceColor = Color3.fromRGB(170, 15, 40) },
	{ id = "Blueberry", name = "Blueberry", juiceColor = Color3.fromRGB(60, 70, 190) },
	{ id = "Raspberry", name = "Raspberry", juiceColor = Color3.fromRGB(215, 30, 90) },
	{ id = "Kiwi", name = "Kiwi", juiceColor = Color3.fromRGB(140, 200, 40) },
	{ id = "Pineapple", name = "Pineapple", juiceColor = Color3.fromRGB(255, 220, 60) },
	{ id = "Mango", name = "Mango", juiceColor = Color3.fromRGB(255, 180, 30) },
	{ id = "Coconut", name = "Coconut", juiceColor = Color3.fromRGB(245, 240, 230) },
	{ id = "Melon", name = "Melon", juiceColor = Color3.fromRGB(255, 190, 110) },
	{ id = "Watermelon", name = "Watermelon", juiceColor = Color3.fromRGB(250, 80, 100) },
}

-- Rare
local rare: { FruitEntry } = {
	{ id = "DragonFruit", name = "Dragon Fruit", juiceColor = Color3.fromRGB(235, 40, 140) },
	{ id = "StarFruit", name = "Star Fruit", juiceColor = Color3.fromRGB(240, 225, 80) },
	{ id = "Lychee", name = "Lychee", juiceColor = Color3.fromRGB(250, 225, 225) },
	{ id = "PassionFruit", name = "Passion Fruit", juiceColor = Color3.fromRGB(255, 190, 30) },
	{ id = "Papaya", name = "Papaya", juiceColor = Color3.fromRGB(255, 140, 60) },
	{ id = "Pomegranate", name = "Pomegranate", juiceColor = Color3.fromRGB(190, 20, 50) },
	{ id = "Guava", name = "Guava", juiceColor = Color3.fromRGB(255, 130, 140) },
	{ id = "Fig", name = "Fig", juiceColor = Color3.fromRGB(120, 50, 90) },
	{ id = "Rambutan", name = "Rambutan", juiceColor = Color3.fromRGB(245, 235, 215) },
	{ id = "Durian", name = "Durian", juiceColor = Color3.fromRGB(230, 205, 90) },
}

-- Epic
local epic: { FruitEntry } = {
	{ id = "Mangosteen", name = "Mangosteen", juiceColor = Color3.fromRGB(150, 40, 110) },
	{ id = "Jabuticaba", name = "Jabuticaba", juiceColor = Color3.fromRGB(70, 20, 90) },
	{ id = "Cherimoya", name = "Cherimoya", juiceColor = Color3.fromRGB(190, 225, 160) },
	{ id = "SnakeFruit", name = "Snake Fruit", juiceColor = Color3.fromRGB(190, 130, 70) },
	{ id = "HornedMelon", name = "Horned Melon", juiceColor = Color3.fromRGB(150, 220, 60) },
	{ id = "BuddhasHand", name = "Buddha's Hand", juiceColor = Color3.fromRGB(255, 225, 70) },
	{ id = "MiracleBerry", name = "Miracle Berry", juiceColor = Color3.fromRGB(230, 60, 90) },
	{ id = "Cloudberry", name = "Cloudberry", juiceColor = Color3.fromRGB(255, 170, 70) },
	{ id = "FingerLime", name = "Finger Lime", juiceColor = Color3.fromRGB(190, 230, 90) },
	{ id = "Ackee", name = "Ackee", juiceColor = Color3.fromRGB(255, 120, 60) },
}

-- Legendary
local legendary: { FruitEntry } = {
	{ id = "GoldenApple", name = "Golden Apple", juiceColor = Color3.fromRGB(255, 200, 40) },
	{ id = "DiamondPear", name = "Diamond Pear", juiceColor = Color3.fromRGB(170, 240, 255) },
	{ id = "RubyCherry", name = "Ruby Cherry", juiceColor = Color3.fromRGB(215, 20, 60) },
	{ id = "EmeraldKiwi", name = "Emerald Kiwi", juiceColor = Color3.fromRGB(30, 200, 100) },
	{ id = "SapphireBerry", name = "Sapphire Berry", juiceColor = Color3.fromRGB(40, 90, 230) },
	{ id = "CrystalGrape", name = "Crystal Grape", juiceColor = Color3.fromRGB(190, 160, 255) },
	{ id = "PearlCoconut", name = "Pearl Coconut", juiceColor = Color3.fromRGB(245, 240, 250) },
	{ id = "AmberPeach", name = "Amber Peach", juiceColor = Color3.fromRGB(255, 160, 30) },
	{ id = "SilverPlum", name = "Silver Plum", juiceColor = Color3.fromRGB(200, 205, 215) },
	{ id = "PlatinumBanana", name = "Platinum Banana", juiceColor = Color3.fromRGB(225, 230, 240) },
}

-- Mythic
local mythic: { FruitEntry } = {
	{ id = "FireMango", name = "Fire Mango", juiceColor = Color3.fromRGB(255, 100, 20) },
	{ id = "IceBerry", name = "Ice Berry", juiceColor = Color3.fromRGB(140, 220, 255) },
	{ id = "ThunderLemon", name = "Thunder Lemon", juiceColor = Color3.fromRGB(255, 245, 90) },
	{ id = "LavaMelon", name = "Lava Melon", juiceColor = Color3.fromRGB(255, 70, 20) },
	{ id = "StormGrape", name = "Storm Grape", juiceColor = Color3.fromRGB(90, 90, 160) },
	{ id = "ShadowPlum", name = "Shadow Plum", juiceColor = Color3.fromRGB(50, 20, 70) },
	{ id = "FrostPeach", name = "Frost Peach", juiceColor = Color3.fromRGB(200, 235, 245) },
	{ id = "ToxicApple", name = "Toxic Apple", juiceColor = Color3.fromRGB(120, 240, 30) },
	{ id = "MagmaOrange", name = "Magma Orange", juiceColor = Color3.fromRGB(240, 80, 10) },
	{ id = "VolcanoPineapple", name = "Volcano Pineapple", juiceColor = Color3.fromRGB(230, 50, 20) },
}

-- Godly
local godly: { FruitEntry } = {
	{ id = "AngelApple", name = "Angel Apple", juiceColor = Color3.fromRGB(255, 250, 220) },
	{ id = "HolyGrape", name = "Holy Grape", juiceColor = Color3.fromRGB(235, 220, 255) },
	{ id = "PhoenixFruit", name = "Phoenix Fruit", juiceColor = Color3.fromRGB(255, 130, 40) },
	{ id = "DragonHeart", name = "Dragon Heart", juiceColor = Color3.fromRGB(200, 20, 40) },
	{ id = "UnicornBerry", name = "Unicorn Berry", juiceColor = Color3.fromRGB(255, 170, 235) },
	{ id = "KrakenMelon", name = "Kraken Melon", juiceColor = Color3.fromRGB(30, 120, 140) },
	{ id = "TitanBanana", name = "Titan Banana", juiceColor = Color3.fromRGB(255, 225, 100) },
	{ id = "GriffinPear", name = "Griffin Pear", juiceColor = Color3.fromRGB(210, 170, 90) },
	{ id = "PegasusPeach", name = "Pegasus Peach", juiceColor = Color3.fromRGB(255, 205, 220) },
	{ id = "HydraCherry", name = "Hydra Cherry", juiceColor = Color3.fromRGB(100, 160, 50) },
}

-- Celestial
local celestial: { FruitEntry } = {
	{ id = "MoonMelon", name = "Moon Melon", juiceColor = Color3.fromRGB(225, 230, 245) },
	{ id = "SunOrange", name = "Sun Orange", juiceColor = Color3.fromRGB(255, 190, 20) },
	{ id = "StarBerry", name = "Star Berry", juiceColor = Color3.fromRGB(255, 240, 140) },
	{ id = "CometCherry", name = "Comet Cherry", juiceColor = Color3.fromRGB(110, 190, 255) },
	{ id = "MeteorMango", name = "Meteor Mango", juiceColor = Color3.fromRGB(235, 120, 40) },
	{ id = "NebulaGrape", name = "Nebula Grape", juiceColor = Color3.fromRGB(170, 80, 230) },
	{ id = "GalaxyPlum", name = "Galaxy Plum", juiceColor = Color3.fromRGB(60, 40, 150) },
	{ id = "AuroraKiwi", name = "Aurora Kiwi", juiceColor = Color3.fromRGB(80, 240, 170) },
	{ id = "SaturnPeach", name = "Saturn Peach", juiceColor = Color3.fromRGB(240, 200, 140) },
	{ id = "EclipseApple", name = "Eclipse Apple", juiceColor = Color3.fromRGB(70, 40, 90) },
}

-- Glitched
local glitched: { FruitEntry } = {
	{ id = "ErrorApple", name = "Error Apple", juiceColor = Color3.fromRGB(255, 30, 60) },
	{ id = "PixelBerry", name = "Pixel Berry", juiceColor = Color3.fromRGB(60, 255, 120) },
	{ id = "LagLemon", name = "Lag Lemon", juiceColor = Color3.fromRGB(230, 255, 40) },
	{ id = "BugBanana", name = "Bug Banana", juiceColor = Color3.fromRGB(150, 255, 60) },
	{ id = "Fruit404", name = "404 Fruit", juiceColor = Color3.fromRGB(120, 120, 130) },
	{ id = "CorruptedGrape", name = "Corrupted Grape", juiceColor = Color3.fromRGB(180, 30, 220) },
	{ id = "NullMelon", name = "Null Melon", juiceColor = Color3.fromRGB(20, 20, 25) },
	{ id = "StaticCherry", name = "Static Cherry", juiceColor = Color3.fromRGB(200, 200, 210) },
	{ id = "BinaryMango", name = "Binary Mango", juiceColor = Color3.fromRGB(30, 230, 90) },
	{ id = "GlitchKiwi", name = "Glitch Kiwi", juiceColor = Color3.fromRGB(255, 40, 200) },
}

-- Infinity
local infinity: { FruitEntry } = {
	{ id = "RainbowApple", name = "Rainbow Apple", juiceColor = Color3.fromRGB(255, 110, 170) },
	{ id = "TimeBerry", name = "Time Berry", juiceColor = Color3.fromRGB(120, 200, 230) },
	{ id = "VoidFruit", name = "Void Fruit", juiceColor = Color3.fromRGB(40, 10, 70) },
	{ id = "QuantumMango", name = "Quantum Mango", juiceColor = Color3.fromRGB(90, 240, 220) },
	{ id = "MultiverseMelon", name = "Multiverse Melon", juiceColor = Color3.fromRGB(150, 110, 255) },
	{ id = "EternalPeach", name = "Eternal Peach", juiceColor = Color3.fromRGB(255, 200, 180) },
	{ id = "BigBangBerry", name = "Big Bang Berry", juiceColor = Color3.fromRGB(255, 160, 60) },
	{ id = "OmegaFruit", name = "Omega Fruit", juiceColor = Color3.fromRGB(220, 60, 140) },
	{ id = "InfinityFruit", name = "Infinity Fruit", juiceColor = Color3.fromRGB(180, 255, 255) },
	{ id = "JuiceGodFruit", name = "Juice God Fruit", juiceColor = Color3.fromRGB(255, 230, 120) },
}

local entriesByRarity: { { FruitEntry } } =
	{ common, uncommon, rare, epic, legendary, mythic, godly, celestial, glitched, infinity }

-- Construction de la liste ordonnee (index = ordre du tableau : rarete par rarete, comme avant ;
-- les ids ne changent pas, les sauvegardes restent valables).
local list: { Fruit } = {}
local byId: { [string]: Fruit } = {}

local function baseWeight(r: number): number
	local oneIn = Fruits.OneInByRarity[r]
	return if r == 1 or oneIn == nil or oneIn <= 0 then Fruits.CommonWeight else 1 / oneIn
end

for r, entries in entriesByRarity do
	for p, entry in entries do
		local fruit: Fruit = table.freeze({
			id = entry.id,
			index = #list + 1,
			name = entry.name,
			rarity = r,
			floor = p,
			value = math.floor(Fruits.FloorValues[p] * Fruits.RarityBonus[r] + 0.5),
			juiceColor = entry.juiceColor,
			weight = baseWeight(r),
		})
		if byId[fruit.id] ~= nil then
			error("Fruits : id en double : " .. fruit.id)
		end
		table.insert(list, fruit)
		byId[fruit.id] = fruit
	end
end

Fruits.Count = 100

-- Verifications au chargement : on echoue tout de suite avec un message clair.
if #list ~= Fruits.Count then
	error(("Fruits : il faut exactement %d fruits, il y en a %d"):format(Fruits.Count, #list))
end
for _, fruit in list do
	if fruit.value <= 0 or fruit.value % 1 ~= 0 then
		error(("Fruits : la valeur de %s doit etre un entier > 0 (%s)"):format(fruit.id, tostring(fruit.value)))
	end
end

Fruits.List = table.freeze(list)
Fruits.ById = table.freeze(byId)
table.freeze(Fruits.Rarities)
for _, rarity in Fruits.Rarities do
	table.freeze(rarity)
end

-- Tour d'etages (lot 4b, 2026-11-20) : l'etage n = la ligne n du tableau (un fruit par rarete).
Fruits.PerRarity = 10
Fruits.PerFloor = 10

local byRarity: { { Fruit } } = {}
local byFloor: { { Fruit } } = {}
for _, fruit in list do
	byRarity[fruit.rarity] = byRarity[fruit.rarity] or {}
	table.insert(byRarity[fruit.rarity], fruit)
	byFloor[fruit.floor] = byFloor[fruit.floor] or {}
	table.insert(byFloor[fruit.floor], fruit)
end
for _, group in byRarity do
	table.freeze(group)
end
for _, group in byFloor do
	table.sort(group, function(a, b)
		return a.rarity < b.rarity
	end)
	table.freeze(group)
end

-- Les 10 fruits de l'etage n (de Common a Infinity ; vide si n n'existe pas). Caisse = Bin<rarete>.
function Fruits.OfFloor(n: number): { Fruit }
	return byFloor[n] or {}
end

-- Les 10 fruits de la rarete r (un par etage).
function Fruits.OfRarity(r: number): { Fruit }
	return byRarity[r] or {}
end

-- Multiplicateur de chance (Rare+) pour un niveau Tree 1..10.
function Fruits.LuckMultiplier(treeLevel: number): number
	local level = math.clamp(math.floor(treeLevel), 1, Fruits.PerFloor)
	return 1 + (Fruits.LuckMax - 1) * (level - 1) / (Fruits.PerFloor - 1)
end

-- Bonus de chance fixe d'un etage (Fruits.FloorLuck), 1 si aucun.
function Fruits.FloorLuckFor(floor: number?): number
	return if floor ~= nil then Fruits.FloorLuck[floor] or 1 else 1
end

-- Poids de tirage par rarete (index = rarete) pour un multiplicateur de chance. Le Common garde
-- toujours le plus gros poids (CommonLead).
function Fruits.RollWeights(luck: number): { number }
	local weights: { number } = {}
	local biggest = 0
	for r = 2, #Fruits.Rarities do
		local w = baseWeight(r) * (if r >= Fruits.LuckFromRarity then luck else 1)
		weights[r] = w
		biggest = math.max(biggest, w)
	end
	weights[1] = math.max(Fruits.CommonWeight, biggest * Fruits.CommonLead)
	return weights
end

-- Chance "1 sur X" d'une rarete (arrondie, pour l'affichage) ; 1 pour le Common.
function Fruits.OneIn(rarity: number, luck: number?): number
	local weights = Fruits.RollWeights(luck or 1)
	local total = 0
	for _, w in weights do
		total += w
	end
	local w = weights[rarity]
	if w == nil or w <= 0 then
		return 0
	end
	return math.max(1, math.floor(total / w + 0.5))
end

-- Recompense "CLAIM" de l'Index pour ce fruit (entier ; 0 si le fruit est inconnu).
function Fruits.ClaimReward(fruitId: string): number
	local fruit = byId[fruitId]
	if fruit == nil then
		return 0
	end
	return math.floor(Fruits.FloorValues[fruit.floor] * Fruits.ClaimBonus[fruit.rarity] + 0.5)
end

return table.freeze(Fruits)
