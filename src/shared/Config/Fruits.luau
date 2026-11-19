--!strict
-- Les 100 fruits (10 raretes x 10 fruits), valeurs, couleurs de jus et poids de tirage.
-- Ordre dans chaque rarete = ordre de deblocage (amelioration Luck de l'arbre).
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
	value: number, -- prix du jus, entier
	juiceColor: Color3,
	weight: number, -- poids de tirage (calcule, ou weightOverride)
}

-- Entree ecrite a la main ; index, rarity et weight sont remplis par la boucle plus bas.
type FruitEntry = {
	id: string,
	name: string,
	value: number,
	juiceColor: Color3,
	weightOverride: number?, -- remplace le poids calcule (aucun utilise pour l'instant)
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

-- Nombre de raretes ouvertes avec 0 rebirth.
Fruits.StartRarities = 3

-- Poids de tirage : BaseWeight * WeightDecayInRarity^(p-1) * WeightDecayPerRarity^(r-1)
Fruits.BaseWeight = 1000
Fruits.WeightDecayInRarity = 0.8
Fruits.WeightDecayPerRarity = 0.1

-- Common
local common: { FruitEntry } = {
	{ id = "Apple", name = "Apple", value = 5, juiceColor = Color3.fromRGB(230, 40, 40) },
	{ id = "Orange", name = "Orange", value = 6, juiceColor = Color3.fromRGB(255, 140, 20) },
	{ id = "Banana", name = "Banana", value = 7, juiceColor = Color3.fromRGB(250, 235, 140) },
	{ id = "Pear", name = "Pear", value = 9, juiceColor = Color3.fromRGB(215, 225, 120) },
	{ id = "Lemon", name = "Lemon", value = 10, juiceColor = Color3.fromRGB(255, 240, 60) },
	{ id = "Lime", name = "Lime", value = 12, juiceColor = Color3.fromRGB(120, 220, 40) },
	{ id = "Grape", name = "Grape", value = 15, juiceColor = Color3.fromRGB(120, 40, 160) },
	{ id = "Plum", name = "Plum", value = 18, juiceColor = Color3.fromRGB(130, 40, 110) },
	{ id = "Peach", name = "Peach", value = 21, juiceColor = Color3.fromRGB(255, 175, 130) },
	{ id = "Apricot", name = "Apricot", value = 26, juiceColor = Color3.fromRGB(255, 170, 60) },
}

-- Uncommon
local uncommon: { FruitEntry } = {
	{ id = "Strawberry", name = "Strawberry", value = 125, juiceColor = Color3.fromRGB(240, 50, 80) },
	{ id = "Cherry", name = "Cherry", value = 150, juiceColor = Color3.fromRGB(170, 15, 40) },
	{ id = "Blueberry", name = "Blueberry", value = 180, juiceColor = Color3.fromRGB(60, 70, 190) },
	{ id = "Raspberry", name = "Raspberry", value = 216, juiceColor = Color3.fromRGB(215, 30, 90) },
	{ id = "Kiwi", name = "Kiwi", value = 259, juiceColor = Color3.fromRGB(140, 200, 40) },
	{ id = "Pineapple", name = "Pineapple", value = 311, juiceColor = Color3.fromRGB(255, 220, 60) },
	{ id = "Mango", name = "Mango", value = 373, juiceColor = Color3.fromRGB(255, 180, 30) },
	{ id = "Coconut", name = "Coconut", value = 448, juiceColor = Color3.fromRGB(245, 240, 230) },
	{ id = "Melon", name = "Melon", value = 537, juiceColor = Color3.fromRGB(255, 190, 110) },
	{ id = "Watermelon", name = "Watermelon", value = 645, juiceColor = Color3.fromRGB(250, 80, 100) },
}

-- Rare
local rare: { FruitEntry } = {
	{ id = "DragonFruit", name = "Dragon Fruit", value = 3_120, juiceColor = Color3.fromRGB(235, 40, 140) },
	{ id = "StarFruit", name = "Star Fruit", value = 3_750, juiceColor = Color3.fromRGB(240, 225, 80) },
	{ id = "Lychee", name = "Lychee", value = 4_500, juiceColor = Color3.fromRGB(250, 225, 225) },
	{ id = "PassionFruit", name = "Passion Fruit", value = 5_400, juiceColor = Color3.fromRGB(255, 190, 30) },
	{ id = "Papaya", name = "Papaya", value = 6_480, juiceColor = Color3.fromRGB(255, 140, 60) },
	{ id = "Pomegranate", name = "Pomegranate", value = 7_780, juiceColor = Color3.fromRGB(190, 20, 50) },
	{ id = "Guava", name = "Guava", value = 9_330, juiceColor = Color3.fromRGB(255, 130, 140) },
	{ id = "Fig", name = "Fig", value = 11_200, juiceColor = Color3.fromRGB(120, 50, 90) },
	{ id = "Rambutan", name = "Rambutan", value = 13_400, juiceColor = Color3.fromRGB(245, 235, 215) },
	{ id = "Durian", name = "Durian", value = 16_100, juiceColor = Color3.fromRGB(230, 205, 90) },
}

-- Epic
local epic: { FruitEntry } = {
	{ id = "Mangosteen", name = "Mangosteen", value = 78_100, juiceColor = Color3.fromRGB(150, 40, 110) },
	{ id = "Jabuticaba", name = "Jabuticaba", value = 93_800, juiceColor = Color3.fromRGB(70, 20, 90) },
	{ id = "Cherimoya", name = "Cherimoya", value = 112_000, juiceColor = Color3.fromRGB(190, 225, 160) },
	{ id = "SnakeFruit", name = "Snake Fruit", value = 135_000, juiceColor = Color3.fromRGB(190, 130, 70) },
	{ id = "HornedMelon", name = "Horned Melon", value = 162_000, juiceColor = Color3.fromRGB(150, 220, 60) },
	{ id = "BuddhasHand", name = "Buddha's Hand", value = 194_000, juiceColor = Color3.fromRGB(255, 225, 70) },
	{ id = "MiracleBerry", name = "Miracle Berry", value = 233_000, juiceColor = Color3.fromRGB(230, 60, 90) },
	{ id = "Cloudberry", name = "Cloudberry", value = 280_000, juiceColor = Color3.fromRGB(255, 170, 70) },
	{ id = "FingerLime", name = "Finger Lime", value = 336_000, juiceColor = Color3.fromRGB(190, 230, 90) },
	{ id = "Ackee", name = "Ackee", value = 403_000, juiceColor = Color3.fromRGB(255, 120, 60) },
}

-- Legendary
local legendary: { FruitEntry } = {
	{ id = "GoldenApple", name = "Golden Apple", value = 1_950_000, juiceColor = Color3.fromRGB(255, 200, 40) },
	{ id = "DiamondPear", name = "Diamond Pear", value = 2_340_000, juiceColor = Color3.fromRGB(170, 240, 255) },
	{ id = "RubyCherry", name = "Ruby Cherry", value = 2_810_000, juiceColor = Color3.fromRGB(215, 20, 60) },
	{ id = "EmeraldKiwi", name = "Emerald Kiwi", value = 3_370_000, juiceColor = Color3.fromRGB(30, 200, 100) },
	{ id = "SapphireBerry", name = "Sapphire Berry", value = 4_050_000, juiceColor = Color3.fromRGB(40, 90, 230) },
	{ id = "CrystalGrape", name = "Crystal Grape", value = 4_860_000, juiceColor = Color3.fromRGB(190, 160, 255) },
	{ id = "PearlCoconut", name = "Pearl Coconut", value = 5_830_000, juiceColor = Color3.fromRGB(245, 240, 250) },
	{ id = "AmberPeach", name = "Amber Peach", value = 7_000_000, juiceColor = Color3.fromRGB(255, 160, 30) },
	{ id = "SilverPlum", name = "Silver Plum", value = 8_400_000, juiceColor = Color3.fromRGB(200, 205, 215) },
	{ id = "PlatinumBanana", name = "Platinum Banana", value = 10_100_000, juiceColor = Color3.fromRGB(225, 230, 240) },
}

-- Mythic
local mythic: { FruitEntry } = {
	{ id = "FireMango", name = "Fire Mango", value = 48_800_000, juiceColor = Color3.fromRGB(255, 100, 20) },
	{ id = "IceBerry", name = "Ice Berry", value = 58_600_000, juiceColor = Color3.fromRGB(140, 220, 255) },
	{ id = "ThunderLemon", name = "Thunder Lemon", value = 70_300_000, juiceColor = Color3.fromRGB(255, 245, 90) },
	{ id = "LavaMelon", name = "Lava Melon", value = 84_400_000, juiceColor = Color3.fromRGB(255, 70, 20) },
	{ id = "StormGrape", name = "Storm Grape", value = 101_000_000, juiceColor = Color3.fromRGB(90, 90, 160) },
	{ id = "ShadowPlum", name = "Shadow Plum", value = 121_000_000, juiceColor = Color3.fromRGB(50, 20, 70) },
	{ id = "FrostPeach", name = "Frost Peach", value = 146_000_000, juiceColor = Color3.fromRGB(200, 235, 245) },
	{ id = "ToxicApple", name = "Toxic Apple", value = 175_000_000, juiceColor = Color3.fromRGB(120, 240, 30) },
	{ id = "MagmaOrange", name = "Magma Orange", value = 210_000_000, juiceColor = Color3.fromRGB(240, 80, 10) },
	{ id = "VolcanoPineapple", name = "Volcano Pineapple", value = 252_000_000, juiceColor = Color3.fromRGB(230, 50, 20) },
}

-- Godly
local godly: { FruitEntry } = {
	{ id = "AngelApple", name = "Angel Apple", value = 1_220_000_000, juiceColor = Color3.fromRGB(255, 250, 220) },
	{ id = "HolyGrape", name = "Holy Grape", value = 1_460_000_000, juiceColor = Color3.fromRGB(235, 220, 255) },
	{ id = "PhoenixFruit", name = "Phoenix Fruit", value = 1_760_000_000, juiceColor = Color3.fromRGB(255, 130, 40) },
	{ id = "DragonHeart", name = "Dragon Heart", value = 2_110_000_000, juiceColor = Color3.fromRGB(200, 20, 40) },
	{ id = "UnicornBerry", name = "Unicorn Berry", value = 2_530_000_000, juiceColor = Color3.fromRGB(255, 170, 235) },
	{ id = "KrakenMelon", name = "Kraken Melon", value = 3_040_000_000, juiceColor = Color3.fromRGB(30, 120, 140) },
	{ id = "TitanBanana", name = "Titan Banana", value = 3_640_000_000, juiceColor = Color3.fromRGB(255, 225, 100) },
	{ id = "GriffinPear", name = "Griffin Pear", value = 4_370_000_000, juiceColor = Color3.fromRGB(210, 170, 90) },
	{ id = "PegasusPeach", name = "Pegasus Peach", value = 5_250_000_000, juiceColor = Color3.fromRGB(255, 205, 220) },
	{ id = "HydraCherry", name = "Hydra Cherry", value = 6_300_000_000, juiceColor = Color3.fromRGB(100, 160, 50) },
}

-- Celestial
local celestial: { FruitEntry } = {
	{ id = "MoonMelon", name = "Moon Melon", value = 30_500_000_000, juiceColor = Color3.fromRGB(225, 230, 245) },
	{ id = "SunOrange", name = "Sun Orange", value = 36_600_000_000, juiceColor = Color3.fromRGB(255, 190, 20) },
	{ id = "StarBerry", name = "Star Berry", value = 43_900_000_000, juiceColor = Color3.fromRGB(255, 240, 140) },
	{ id = "CometCherry", name = "Comet Cherry", value = 52_700_000_000, juiceColor = Color3.fromRGB(110, 190, 255) },
	{ id = "MeteorMango", name = "Meteor Mango", value = 63_300_000_000, juiceColor = Color3.fromRGB(235, 120, 40) },
	{ id = "NebulaGrape", name = "Nebula Grape", value = 75_900_000_000, juiceColor = Color3.fromRGB(170, 80, 230) },
	{ id = "GalaxyPlum", name = "Galaxy Plum", value = 91_100_000_000, juiceColor = Color3.fromRGB(60, 40, 150) },
	{ id = "AuroraKiwi", name = "Aurora Kiwi", value = 109_000_000_000, juiceColor = Color3.fromRGB(80, 240, 170) },
	{ id = "SaturnPeach", name = "Saturn Peach", value = 131_000_000_000, juiceColor = Color3.fromRGB(240, 200, 140) },
	{ id = "EclipseApple", name = "Eclipse Apple", value = 157_000_000_000, juiceColor = Color3.fromRGB(70, 40, 90) },
}

-- Glitched
local glitched: { FruitEntry } = {
	{ id = "ErrorApple", name = "Error Apple", value = 763_000_000_000, juiceColor = Color3.fromRGB(255, 30, 60) },
	{ id = "PixelBerry", name = "Pixel Berry", value = 916_000_000_000, juiceColor = Color3.fromRGB(60, 255, 120) },
	{ id = "LagLemon", name = "Lag Lemon", value = 1_100_000_000_000, juiceColor = Color3.fromRGB(230, 255, 40) },
	{ id = "BugBanana", name = "Bug Banana", value = 1_320_000_000_000, juiceColor = Color3.fromRGB(150, 255, 60) },
	{ id = "Fruit404", name = "404 Fruit", value = 1_580_000_000_000, juiceColor = Color3.fromRGB(120, 120, 130) },
	{ id = "CorruptedGrape", name = "Corrupted Grape", value = 1_900_000_000_000, juiceColor = Color3.fromRGB(180, 30, 220) },
	{ id = "NullMelon", name = "Null Melon", value = 2_280_000_000_000, juiceColor = Color3.fromRGB(20, 20, 25) },
	{ id = "StaticCherry", name = "Static Cherry", value = 2_730_000_000_000, juiceColor = Color3.fromRGB(200, 200, 210) },
	{ id = "BinaryMango", name = "Binary Mango", value = 3_280_000_000_000, juiceColor = Color3.fromRGB(30, 230, 90) },
	{ id = "GlitchKiwi", name = "Glitch Kiwi", value = 3_940_000_000_000, juiceColor = Color3.fromRGB(255, 40, 200) },
}

-- Infinity
local infinity: { FruitEntry } = {
	{ id = "RainbowApple", name = "Rainbow Apple", value = 19_100_000_000_000, juiceColor = Color3.fromRGB(255, 110, 170) },
	{ id = "TimeBerry", name = "Time Berry", value = 22_900_000_000_000, juiceColor = Color3.fromRGB(120, 200, 230) },
	{ id = "VoidFruit", name = "Void Fruit", value = 27_500_000_000_000, juiceColor = Color3.fromRGB(40, 10, 70) },
	{ id = "QuantumMango", name = "Quantum Mango", value = 33_000_000_000_000, juiceColor = Color3.fromRGB(90, 240, 220) },
	{ id = "MultiverseMelon", name = "Multiverse Melon", value = 39_600_000_000_000, juiceColor = Color3.fromRGB(150, 110, 255) },
	{ id = "EternalPeach", name = "Eternal Peach", value = 47_500_000_000_000, juiceColor = Color3.fromRGB(255, 200, 180) },
	{ id = "BigBangBerry", name = "Big Bang Berry", value = 57_000_000_000_000, juiceColor = Color3.fromRGB(255, 160, 60) },
	{ id = "OmegaFruit", name = "Omega Fruit", value = 68_300_000_000_000, juiceColor = Color3.fromRGB(220, 60, 140) },
	{ id = "InfinityFruit", name = "Infinity Fruit", value = 82_000_000_000_000, juiceColor = Color3.fromRGB(180, 255, 255) },
	{ id = "JuiceGodFruit", name = "Juice God Fruit", value = 98_400_000_000_000, juiceColor = Color3.fromRGB(255, 230, 120) },
}

local entriesByRarity: { { FruitEntry } } =
	{ common, uncommon, rare, epic, legendary, mythic, godly, celestial, glitched, infinity }

-- Construction de la liste ordonnee (index, rarete et poids calcules depuis la position).
local list: { Fruit } = {}
local byId: { [string]: Fruit } = {}

for r, entries in entriesByRarity do
	for p, entry in entries do
		local weight = entry.weightOverride
			or Fruits.BaseWeight * Fruits.WeightDecayInRarity ^ (p - 1) * Fruits.WeightDecayPerRarity ^ (r - 1)
		local fruit: Fruit = table.freeze({
			id = entry.id,
			index = #list + 1,
			name = entry.name,
			rarity = r,
			value = entry.value,
			juiceColor = entry.juiceColor,
			weight = weight,
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
for i, fruit in list do
	if fruit.value % 1 ~= 0 then
		error(("Fruits : la valeur de %s doit etre un entier (%s)"):format(fruit.id, tostring(fruit.value)))
	end
	if i > 1 and fruit.value <= list[i - 1].value then
		error(("Fruits : les valeurs doivent augmenter strictement (%s <= %s)"):format(fruit.id, list[i - 1].id))
	end
end

Fruits.List = table.freeze(list)
Fruits.ById = table.freeze(byId)
table.freeze(Fruits.Rarities)
for _, rarity in Fruits.Rarities do
	table.freeze(rarity)
end

-- Nombre de fruits que l'arbre peut atteindre selon les rebirths (ne jamais ecrire 30 en dur ailleurs).
function Fruits.MaxLuck(rebirths: number): number
	return math.min(10 * (Fruits.StartRarities + rebirths), Fruits.Count)
end

return table.freeze(Fruits)
