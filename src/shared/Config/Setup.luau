--!strict
-- Usine a construire (profil neuf, etage 1) : 4 pads verts "FREE" a faire dans l'ordre, et ce que
-- chaque etape construit (fantome bleu -> vrai objet) ou fait apparaitre (cache -> visible).
-- Le serveur (SetupService) decide de tout : etape sauvegardee (Data.Setup = nombre d'etapes faites,
-- 0..Done), attribut d'etage "Lv_Setup" pour le client (SetupController, LevelLookController).
-- Profils existants, etages 2-10, rebirth, bases libres : etape = Done (usine deja construite).
-- Chemins = depuis l'etage (Model FloorN). Doc : docs/systems/usine-a-construire.md

export type Step = {
	id: string, -- nom du modele dans FloorTemplate.Setup
	label: string, -- texte du pad (anglais : vu par le joueur)
	x: number, -- centre du pad (repere du FloorTemplate, tools/build-map/02l)
	z: number,
	floorY: number, -- hauteur du sol sous le pad (0.5 = sol, 0.9 = allee 02k)
	prompt: boolean?, -- vrai : touche E (ProximityPrompt) au lieu de marcher dessus
	spot: string?, -- chemin d'une piece de l'etage : la touche E est la, et le pad reste cache
}

local Setup = {}

Setup.Done = 4

Setup.Steps = table.freeze({
	-- 1. Graine -> l'arbre pousse, 5 pommes tombent (on plante l'arbre niveau 1 tenu en main depuis la
	--    cinematique). Depuis le 2026-11-22 (demande : "au lieu de mettre un pad, on appuie sur E au
	--    milieu de l'herbe la ou y aura l'arbre") : pas de pad visible, touche E sur Tree.TreeRoot.
	--    Le modele de pad (x 78.5, z 92.5) reste dans FloorTemplate.Setup mais toujours cache.
	{ id = "PlantTree", label = "Plant tree", x = 78.5, z = 92.5, floorY = 0.5, prompt = true, spot = "Tree.TreeRoot" },
	-- 2. Etagere + caisses + plancher + tapis. Au bout de l'allee qui monte (ToBack), devant l'etagere.
	{ id = "BuildShelf", label = "Build shelf", x = 57, z = 112, floorY = 0.5 },
	-- 3. Mixeur 1 + table a jus. Dans l'allee devant les mixeurs, cote route du mixeur 1.
	{ id = "BuildBlender", label = "Build blender", x = 8.5, z = 86.5, floorY = 0.5 },
	-- 4. Comptoir + tas d'argent + panneau MONEY / HOUR ; les clients arrivent. Sur l'allee de la
	--    vente, juste a gauche du pad Drop Juices (vu de la route).
	{ id = "OpenShop", label = "Open shop", x = 52, z = 30, floorY = 0.9 },
} :: { Step })

-- Construit a l'etape k (fantome bleu avant, sauf chez les autres joueurs : cache).
-- L'arbre (Tree.Body, refait par TreeService) et le mixeur 1 (UpgradeService) sont geres a part.
Setup.Build = table.freeze({
	[2] = { "Production.FruitRack", "Production.Bins", "Production.BinRims", "Production.BinsDeck", "Production.Conveyor" },
	[3] = { "Production.JuicePallet" },
	[4] = { "Counter.SalesCounter", "Counter.IncomeSign", "Counter.MoneyTray" },
} :: { [number]: { string } })

-- Cache avant l'etape k, apparait avec une animation ensuite (pads sans UpgradeId).
Setup.Reveal = table.freeze({
	[2] = { "Production.FruitDropPad" },
	[3] = { "Production.TakeJuicePad" },
	[4] = {
		"Counter.JuiceDropPad",
		"Counter.CashPad",
		"Counter.InstantSellPad",
		"Counter.AutoCollectPad",
		"Machines.Billboard", -- (dossier OnlyGround deplie a l'etage 1 par FloorAssembly)
	},
} :: { [number]: { string } })

-- Ameliorations (UpgradeService) : etape a partir de laquelle leur pad / panneau / machine existe.
-- Avant : pad cache, panneau cache (HideWhenLocked), machine cachee, achat refuse.
local UPGRADE_STEP: { [string]: number } = {
	Tree = 1, -- pad Upgrade Tree
	ConveyorSpeed = 2, -- panneau Conveyor
	Collector = 2, -- pad Fruit Picker (son panneau apparait a l'embauche : requires)
	PickerSpeed = 2,
	PickerCarry = 2,
	JuiceLimit = 4, -- panneau Juice Table
	CustomerSpeed = 4, -- panneau Customers
	CustomerCount = 4,
	Waiter = 4,
}
for n = 1, 4 do
	UPGRADE_STEP["Blender" .. n] = 3 -- mixeurs 2-4 en bleu seulement apres le mixeur 1
	UPGRADE_STEP["Operator" .. n] = 3
end
Setup.UpgradeStep = table.freeze(UPGRADE_STEP)

-- Machine d'amelioration construite par un pad FREE (fantome bleu avant, pas cachee).
Setup.UpgradeBuild = table.freeze({ Blender1 = 3 } :: { [string]: number })

-- Rythme (le tout doit tenir en ~15-20 s de construction, premier billet avant ~45 s)
Setup.NextPadDelay = 1.3 -- secondes entre la fin d'une etape et l'apparition du pad suivant
Setup.TreeGrowSeconds = 1.4 -- l'arbre pousse (client) avant la chute des pommes
Setup.FirstApples = 5 -- pommes qui tombent de l'arbre plante
Setup.AppleStagger = 0.25 -- secondes entre deux pommes

-- Tutoriel etape par etape (2026-11-22) : le pad k n'apparait que quand c'est son tour (en plus de
-- l'etape d'avant faite). minFruits : fruits portes (plafonne a la taille du plateau) ; emptyTray : les
-- fruits ont ete poses ; minJuices : jus en main. Une fois apparu, le pad reste. Lu par SetupService.
export type PadGate = { minFruits: number?, emptyTray: boolean?, minJuices: number? }
Setup.PadGates = table.freeze({
	[2] = { minFruits = 5 }, -- Build shelf : apres avoir ramasse les pommes
	[3] = { emptyTray = true }, -- Build blender : apres avoir pose les fruits sur l'etagere
	[4] = { minJuices = 1 }, -- Open shop : apres avoir pris les jus
} :: { [number]: PadGate })

Setup.PadText = "FREE"
Setup.PromptDistance = 10 -- studs : portee de la touche E des pads `prompt`
Setup.PlantText = "Tree" -- texte du dessus de la touche E de l'etape `spot` (au lieu de "FREE")

return table.freeze(Setup)
