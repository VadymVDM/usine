--!strict
-- Arbre de chaque etage : il change NETTEMENT a CHAQUE niveau (pad "Upgrade Tree", niveau 1..10 par etage).
-- Depuis le 2026-11-20 (soir) l'arbre est construit par code (server/Lib/TreeBuilder) a partir de
-- ce fichier ; les 5 modeles ServerStorage.TreeStages ne servent plus.
--   * PALIER = (etage - 1) x 9 + niveau (1..91). L'arbre de l'etage n au niveau 1 est EXACTEMENT
--     celui de l'etage n-1 au niveau 10 (demande : "chaque etage, l'arbre commence au niveau max
--     de l'etage precedent, et apres il s'ameliore"), puis il continue de s'ameliorer.
--   * Etage 1 : l'arbre POUSSE (Growth[1..10]) : pousse avec tuteur -> grand arbre avec nichoir,
--     ruche et balancoire.
--   * Etages 2..10 : chaque niveau passe UNE partie de l'arbre au theme de l'etage (Slots) : tronc,
--     feuillage du bas, du haut, pointes lumineuses, ornements, veines, aura, anneau, couronne. Au
--     niveau 10, tout l'arbre a le theme de l'etage ; l'etage suivant repart de la. L'arbre grandit
--     aussi un peu a chaque palier (LateGrowth).
-- Aucun champ en plus dans la sauvegarde (on lit Floors[n].Upgrades.Tree).
-- REGLE : aucune piece en forme de fruit (2026-11-20 : les joueurs essayaient de ramasser les pommes
-- accrochees). Ornements = trefles, lingots, cristaux, runes, gemmes, flammes, etoiles, anneaux, ailes.
-- Doc : docs/systems/fruits.md (section Arbre qui grandit)

local Tree = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Tree.LevelsPerFloor = 10 -- niveaux de l'arbre dans un etage (= Fruits.PerFloor)
Tree.MaxHeight = 31.5 -- studs au-dessus de l'herbe : sous les poutres du puits de lumiere (34.6)

-- Taille de l'arbre sur l'etage 1 (palier = niveau). Studs, pied du tronc = 0.
--   trunk : hauteur du tronc jusqu'au bas du feuillage ; width : largeur du tronc au pied ;
--   radius : rayon du feuillage ; canopy : hauteur du feuillage ; layers : etages de feuillage (1..3) ;
--   ring : grappes autour du feuillage ; branches / roots : nombre de branches / racines ;
--   stake : tuteur ; bark : anneaux d'ecorce ; birdhouse / hive / swing : nichoir, ruche, balancoire.
export type Growth = {
	trunk: number,
	width: number,
	radius: number,
	canopy: number,
	layers: number,
	ring: number,
	branches: number,
	roots: number,
	stake: boolean?,
	bark: boolean?,
	birdhouse: boolean?,
	hive: boolean?,
	swing: boolean?,
}

Tree.Growth = {
	{ trunk = 3.4, width = 1.0, radius = 2.8, canopy = 4.4, layers = 1, ring = 3, branches = 0, roots = 0, stake = true },
	{ trunk = 4.4, width = 1.4, radius = 3.8, canopy = 5.4, layers = 1, ring = 4, branches = 0, roots = 2, stake = true },
	{ trunk = 5.4, width = 1.8, radius = 4.8, canopy = 6.6, layers = 2, ring = 5, branches = 2, roots = 3 },
	{ trunk = 6.3, width = 2.2, radius = 5.8, canopy = 7.8, layers = 2, ring = 6, branches = 2, roots = 3 },
	{ trunk = 7.1, width = 2.7, radius = 6.8, canopy = 9.0, layers = 2, ring = 7, branches = 3, roots = 4, birdhouse = true },
	{ trunk = 7.9, width = 3.1, radius = 7.6, canopy = 10.0, layers = 3, ring = 8, branches = 3, roots = 4, birdhouse = true, bark = true },
	{ trunk = 8.6, width = 3.5, radius = 8.4, canopy = 11.0, layers = 3, ring = 8, branches = 4, roots = 5, birdhouse = true, bark = true },
	{ trunk = 9.2, width = 3.9, radius = 9.0, canopy = 11.8, layers = 3, ring = 9, branches = 4, roots = 6, birdhouse = true, bark = true, hive = true },
	{ trunk = 9.8, width = 4.3, radius = 9.6, canopy = 12.6, layers = 3, ring = 10, branches = 4, roots = 6, birdhouse = true, bark = true, hive = true, swing = true },
	{ trunk = 10.4, width = 4.7, radius = 10.2, canopy = 13.4, layers = 3, ring = 10, branches = 5, roots = 8, birdhouse = true, bark = true, hive = true, swing = true },
} :: { Growth }

-- Croissance en plus entre le palier 10 (etage 1 au max) et le dernier palier (etage 10 au max),
-- repartie sur tous les paliers. Le plus grand arbre (+ couronne) reste sous Tree.MaxHeight.
-- Hauteur gardee faible : la place au-dessus sert a la couronne.
Tree.LateGrowth = table.freeze({ trunk = 0.6, width = 1.2, radius = 2.0, canopy = 0.8 })

-- Niveau (dans l'etage) ou chaque partie de l'arbre prend le theme de l'etage. Avant ce niveau, la
-- partie garde le theme de l'etage d'en dessous. Une partie par niveau : un vrai changement a chaque achat.
Tree.Slots = table.freeze({
	trunk = 2, -- tronc, branches, racines (couleur, matiere, anneaux)
	leavesLow = 3, -- grande grappe du bas + couronne de grappes
	leavesHigh = 4, -- grappes du haut
	tips = 5, -- dessus des grappes a la couleur d'accent du theme (lisse, un peu brillant ; jamais de Neon)
	ornaments = 6, -- 8 ornements dans le feuillage
	veins = 7, -- veines (couleur d'accent) sur le tronc + anneau au pied
	aura = 8, -- particules + lumiere dans le feuillage
	halo = 9, -- grand anneau (couleur d'accent) autour du feuillage
	crown = 10, -- objet au sommet de l'arbre
})

-- Theme de chaque etage (index = numero de l'etage). glow / ornament / aura / crown = nil : pas de
-- piece pour cette partie (etage 1 : arbre naturel).
export type Theme = {
	trunk: Color3,
	trunkDark: Color3,
	band: Color3, -- anneaux d'ecorce
	trunkMaterial: Enum.Material,
	leaves: { Color3 }, -- 3 tons
	leafTop: Color3, -- dessus clair des grappes (sans pointes lumineuses)
	leafMaterial: Enum.Material,
	glow: Color3?, -- couleur d'accent (contraste avec les feuilles) : pointes, veines, anneau, lumiere
	ornament: string?, -- "clover" | "bar" | "crystal" | "rune" | "gem" | "flame" | "star" | "orbit" | "wing"
	ornamentColors: { Color3 }?,
	aura: { Color3 }?, -- couleurs des particules (debut, fin)
	crown: string?, -- "clover" | "star" | "crystal" | "orb" | "crown" | "eye" | "planet" | "galaxy" | "halo"
	crownColors: { Color3 }?,
}

local PLASTIC = Enum.Material.Plastic

Tree.Themes = {
	-- 1 Fruit Tree : arbre naturel (il pousse)
	{
		trunk = rgb(112, 78, 52),
		trunkDark = rgb(96, 66, 44),
		band = rgb(132, 94, 62),
		trunkMaterial = PLASTIC,
		leaves = { rgb(62, 124, 50), rgb(76, 140, 56), rgb(92, 156, 64) },
		leafTop = rgb(116, 178, 74),
		leafMaterial = PLASTIC,
	},
	-- 2 Lucky Tree : vert emeraude vif, trefles a 4 feuilles, or
	{
		trunk = rgb(0, 120, 60),
		trunkDark = rgb(0, 95, 50),
		band = rgb(255, 200, 0),
		trunkMaterial = PLASTIC,
		leaves = { rgb(0, 200, 80), rgb(40, 225, 70), rgb(120, 240, 60) },
		leafTop = rgb(200, 255, 90),
		leafMaterial = PLASTIC,
		glow = rgb(255, 200, 0), -- accent : or
		ornament = "clover",
		ornamentColors = { rgb(255, 200, 0), rgb(0, 200, 80) }, -- trefles dores (verts, on ne les voyait pas sur les feuilles)
		aura = { rgb(130, 255, 60), rgb(255, 230, 60) },
		crown = "clover",
		crownColors = { rgb(30, 230, 90), rgb(255, 210, 0), rgb(0, 120, 60) },
	},
	-- 3 Golden Tree : tout en or, lingots, etoile doree
	{
		trunk = rgb(240, 170, 20),
		trunkDark = rgb(215, 140, 10),
		band = rgb(255, 240, 140),
		trunkMaterial = PLASTIC,
		leaves = { rgb(240, 175, 0), rgb(255, 205, 30), rgb(215, 150, 0) },
		leafTop = rgb(255, 230, 110),
		leafMaterial = PLASTIC,
		glow = rgb(255, 120, 0), -- accent : ambre
		ornament = "bar",
		ornamentColors = { rgb(255, 195, 0), rgb(255, 240, 120) },
		aura = { rgb(255, 230, 80), rgb(255, 255, 210) },
		crown = "star",
		crownColors = { rgb(255, 215, 0), rgb(255, 255, 255) },
	},
	-- 4 Crystal Tree : bleu glace, pics de cristal
	{
		trunk = rgb(110, 200, 255),
		trunkDark = rgb(80, 170, 240),
		band = rgb(230, 250, 255),
		trunkMaterial = Enum.Material.Ice,
		leaves = { rgb(0, 210, 255), rgb(80, 230, 255), rgb(150, 245, 255) },
		leafTop = rgb(230, 255, 255),
		leafMaterial = Enum.Material.Ice,
		glow = rgb(0, 110, 255), -- accent : bleu profond
		ornament = "crystal",
		ornamentColors = { rgb(0, 240, 255), rgb(235, 255, 255) },
		aura = { rgb(170, 255, 255), rgb(255, 255, 255) },
		crown = "crystal",
		crownColors = { rgb(0, 240, 255), rgb(220, 255, 255) },
	},
	-- 5 Magic Tree : violet, runes roses flottantes, orbe magique
	{
		trunk = rgb(90, 30, 150),
		trunkDark = rgb(70, 20, 120),
		band = rgb(255, 60, 230),
		trunkMaterial = PLASTIC,
		leaves = { rgb(170, 0, 255), rgb(200, 50, 255), rgb(140, 0, 220) },
		leafTop = rgb(255, 130, 255),
		leafMaterial = PLASTIC,
		glow = rgb(0, 225, 255), -- accent : cyan
		ornament = "rune",
		ornamentColors = { rgb(255, 60, 230), rgb(130, 255, 255) },
		aura = { rgb(255, 80, 255), rgb(160, 80, 255) },
		crown = "orb",
		crownColors = { rgb(255, 60, 230), rgb(130, 255, 255), rgb(90, 30, 150) },
	},
	-- 6 Royal Tree : rouge et or, gemmes, couronne
	{
		trunk = rgb(140, 0, 30),
		trunkDark = rgb(110, 0, 25),
		band = rgb(255, 200, 0),
		trunkMaterial = PLASTIC,
		leaves = { rgb(230, 0, 40), rgb(255, 30, 60), rgb(200, 0, 35) },
		leafTop = rgb(255, 100, 110),
		leafMaterial = PLASTIC,
		glow = rgb(255, 200, 0), -- accent : or
		ornament = "gem",
		ornamentColors = { rgb(0, 90, 255), rgb(0, 210, 90), rgb(255, 200, 0) },
		aura = { rgb(255, 215, 0), rgb(255, 60, 80) },
		crown = "crown",
		crownColors = { rgb(255, 200, 0), rgb(230, 0, 40), rgb(0, 90, 255) },
	},
	-- 7 Mystic Tree : turquoise, flammes spectrales, oeil
	{
		trunk = rgb(30, 55, 75),
		trunkDark = rgb(20, 40, 60),
		band = rgb(0, 255, 200),
		trunkMaterial = PLASTIC,
		leaves = { rgb(0, 190, 160), rgb(0, 220, 180), rgb(0, 160, 140) },
		leafTop = rgb(120, 255, 220),
		leafMaterial = PLASTIC,
		glow = rgb(170, 80, 255), -- accent : violet
		ornament = "flame",
		ornamentColors = { rgb(170, 80, 255), rgb(235, 220, 255) }, -- violet : contraste avec les feuilles turquoise
		aura = { rgb(0, 255, 200), rgb(120, 255, 255) },
		crown = "eye",
		crownColors = { rgb(0, 255, 200), rgb(255, 255, 255), rgb(20, 20, 30) },
	},
	-- 8 Cosmic Tree : bleu nuit, etoiles, planete
	{
		trunk = rgb(30, 30, 70),
		trunkDark = rgb(20, 20, 50),
		band = rgb(90, 150, 255),
		trunkMaterial = PLASTIC,
		leaves = { rgb(40, 50, 200), rgb(60, 90, 255), rgb(30, 30, 160) },
		leafTop = rgb(150, 180, 255),
		leafMaterial = PLASTIC,
		glow = rgb(255, 215, 50), -- accent : jaune etoile
		ornament = "star",
		ornamentColors = { rgb(255, 255, 255), rgb(255, 230, 90) },
		aura = { rgb(255, 255, 255), rgb(140, 180, 255) },
		crown = "planet",
		crownColors = { rgb(255, 120, 60), rgb(255, 220, 120), rgb(120, 200, 255) },
	},
	-- 9 Galaxy Tree : rose / violet / bleu, anneaux, galaxie
	{
		trunk = rgb(70, 20, 100),
		trunkDark = rgb(50, 10, 80),
		band = rgb(255, 90, 210),
		trunkMaterial = PLASTIC,
		leaves = { rgb(255, 40, 180), rgb(150, 50, 255), rgb(60, 120, 255) },
		leafTop = rgb(255, 170, 250),
		leafMaterial = PLASTIC,
		glow = rgb(60, 240, 255), -- accent : cyan
		ornament = "orbit",
		ornamentColors = { rgb(255, 100, 230), rgb(90, 170, 255) },
		aura = { rgb(255, 120, 240), rgb(120, 170, 255) },
		crown = "galaxy",
		crownColors = { rgb(255, 80, 220), rgb(100, 160, 255), rgb(255, 255, 255) },
	},
	-- 10 Divine Tree : blanc et or, ailes, aureole
	{
		trunk = rgb(245, 245, 245),
		trunkDark = rgb(225, 225, 230),
		band = rgb(255, 205, 40),
		trunkMaterial = Enum.Material.SmoothPlastic, -- (Marble paraissait gris-bleu)
		leaves = { rgb(255, 255, 255), rgb(255, 250, 220), rgb(255, 240, 180) },
		leafTop = rgb(255, 252, 235),
		leafMaterial = PLASTIC,
		glow = rgb(255, 195, 30), -- accent : or
		ornament = "wing",
		ornamentColors = { rgb(255, 255, 255), rgb(255, 205, 40) },
		aura = { rgb(255, 240, 150), rgb(255, 255, 255) },
		crown = "halo",
		crownColors = { rgb(255, 215, 40), rgb(255, 255, 255) },
	},
} :: { Theme }

-- Nom de l'arbre de chaque etage (affiche : "Golden Tree Lv 7"). Pas un nom de fruit (chaque arbre
-- donne les 10 raretes) ni un nom de rarete (Common..Infinity, deja sur les fruits) : un rang qui
-- monte d'etage en etage, en accord avec le theme (Themes). Texte seul, rien n'est sauvegarde.
Tree.Names = table.freeze({
	"Fruit Tree",
	"Lucky Tree",
	"Golden Tree",
	"Crystal Tree",
	"Magic Tree",
	"Royal Tree",
	"Mystic Tree",
	"Cosmic Tree",
	"Galaxy Tree",
	"Divine Tree",
})

-- Nom affiche de l'arbre de l'etage `floor` ("Tree" si l'etage n'a pas de nom).
function Tree.NameFor(floor: number): string
	return Tree.Names[floor] or "Tree"
end

local function clampFloor(floor: number): number
	return math.clamp(math.floor(floor), 1, #Tree.Themes)
end

local function clampLevel(level: number): number
	return math.clamp(math.floor(level), 1, Tree.LevelsPerFloor)
end

-- Palier de l'arbre (1..MaxTier) : etage n niveau 1 = etage n-1 niveau 10.
function Tree.Tier(floor: number, level: number): number
	return (clampFloor(floor) - 1) * (Tree.LevelsPerFloor - 1) + clampLevel(level)
end

function Tree.MaxTier(): number
	return Tree.Tier(#Tree.Themes, Tree.LevelsPerFloor)
end

-- Taille de l'arbre pour un palier (etage 1 : Growth ; ensuite Growth[10] + LateGrowth reparti).
function Tree.GrowthFor(tier: number): Growth
	local list = Tree.Growth
	local t = math.max(math.floor(tier), 1)
	if t <= #list then
		return list[t]
	end
	local last = list[#list]
	local late = Tree.LateGrowth
	local e = math.clamp((t - #list) / math.max(1, Tree.MaxTier() - #list), 0, 1)
	local g = table.clone(last)
	g.trunk = last.trunk + late.trunk * e
	g.width = last.width + late.width * e
	g.radius = last.radius + late.radius * e
	g.canopy = last.canopy + late.canopy * e
	return g
end

-- Theme d'une partie de l'arbre (Slots) a l'etage `floor`, niveau `level` : celui de l'etage si la
-- partie est deja passee, sinon celui de l'etage d'en dessous (etage 1 : toujours le sien).
function Tree.SlotTheme(floor: number, level: number, slot: string): Theme
	local f = clampFloor(floor)
	local need = Tree.Slots[slot] or 1
	local index = if clampLevel(level) >= need then f else math.max(f - 1, 1)
	return Tree.Themes[index]
end

for _, g in Tree.Growth do
	table.freeze(g)
end
table.freeze(Tree.Growth)
for _, theme in Tree.Themes do
	table.freeze(theme.leaves)
	if theme.ornamentColors then
		table.freeze(theme.ornamentColors)
	end
	if theme.aura then
		table.freeze(theme.aura)
	end
	if theme.crownColors then
		table.freeze(theme.crownColors)
	end
	table.freeze(theme)
end
table.freeze(Tree.Themes)

return table.freeze(Tree)
