--!strict
-- Tutoriel etape par etape (profil neuf, 2026-11-22). Le client (TutorialController) montre ou aller
-- (ligne + fleche + objectif en haut de l'ecran) ; le serveur (TutorialService) sauvegarde l'etape,
-- d'apres l'etat que le serveur publie deja (etape de l'usine Lv_Setup, fruits portes InvFruits / InvMax,
-- jus portes HandJuices, jus sur le comptoir CounterJuices, argent).
-- Doc : docs/systems/tutoriel.md

local Tutorial = {}

-- Objectif affiche en haut de l'ecran (anglais, 5 mots max). Ordre du tutoriel.
Tutorial.Steps = table.freeze({
	PlantTree = "Plant the tree",
	PickFruits = "Pick up the fruits",
	BuildShelf = "Build the shelf",
	DropFruits = "Drop the fruits",
	BuildBlender = "Build the blender",
	Blend = "Blend the fruits", -- touche E sur le panneau du mixeur 1
	TakeJuices = "Take the juices",
	OpenShop = "Open the shop",
	SellJuices = "Sell the juices",
	CollectCash = "Collect your cash",
	-- Suite (apres le premier argent, 2026-11-22)
	HirePicker = "Hire the Fruit Picker",
	EarnPicker = "Fruit Picker: {cash} / {price}", -- petite ligne sous le geste a faire ({cash} = argent, {price} = prix)
	UpgradeTree = "Upgrade the tree", -- pendant l'etape Loop, une fois (Lv_Tree > 1)
	EarnTree = "Tree upgrade: {cash} / {price}",
	OpenIndex = "Open the Index",
	ClaimIndex = "Claim a fruit reward",
	OpenUpgrades = "Open Upgrades",
	CloseMenu = "Close this menu", -- un autre menu cache le bouton du HUD a viser
	FreeSpeed = "Upgrade your speed: FREE!",
	HireOperator = "Hire a Blender Operator",
	BuyUpgrade = "Upgrade {name}", -- {name} = titre de l'amelioration (Config/Upgrades)
	UpgradeElevator = "Upgrade the Elevator", -- conseil unique apres l'etage 2 (2026-11-23)
})

-- Etapes sauvegardees (Data.TutorialStep = nombre d'etapes faites ; TutorialService). Ordre voulu par
-- l'utilisateur : usine + premier argent, Fruit Picker, Index, un tour complet (fruits -> etagere ->
-- mixeur -> jus -> comptoir -> argent), Upgrades (vitesse FREE), 15 s de jeu libre, Operator du mixeur
-- quand il a l'argent, puis une amelioration de panneau au hasard chaque minute (sans fin).
Tutorial.Phases = table.freeze({
	"Factory", -- 0 : usine a construire (pads FREE) puis vendre et encaisser le premier argent
	"Picker", -- 1 : embaucher le Fruit Picker (pad vert ; d'abord gagner son prix si besoin)
	"OpenIndex", -- 2 : fleche sur le bouton Index du HUD
	"ClaimIndex", -- 3 : fleche sur un bouton CLAIM de l'Index
	"Loop", -- 4 : un tour complet de production jusqu'a l'argent encaisse
	"Upgrade", -- 5 : bouton UPGRADE du HUD puis la vitesse (gratuite une fois, serveur)
	"Free", -- 6 : jeu libre (FreePlaySeconds), sans guidage
	"Operator", -- 7 : Operator du mixeur 1 quand le joueur peut le payer (saute s'il l'a deja)
	"Suggest", -- 8 : amelioration de panneau au hasard (une qu'il peut payer) chaque minute ; sans fin
})
Tutorial.Done = #Tutorial.Phases + 1 -- profils existants : pas de tutoriel
Tutorial.FreePlaySeconds = 15
Tutorial.SuggestEverySeconds = 60
Tutorial.SuggestTimeoutSeconds = 30 -- une proposition pas suivie disparait apres ce temps
Tutorial.OperatorId = "Operator1"
Tutorial.PickerId = "Collector"
Tutorial.TreeId = "Tree" -- pad "Upgrade Tree" (Config/Upgrades), propose pendant l'etape Loop
-- Ameliorations de panneau qui peuvent etre proposees au hasard (tuiles Boards.<Board>.<id>)
Tutorial.SuggestIds = table.freeze({
	"ConveyorSpeed", "JuiceLimit", "CustomerSpeed", "CustomerCount", "PickerSpeed", "PickerCarry",
	"Blender1", "Blender2", "Blender3", "Blender4",
})
-- Fleche a l'ecran (boutons du HUD et des menus) : image Icons.FloorArrow (pointe a droite), tournee
Tutorial.PointerSize = 64 -- pixels
Tutorial.BannerTop = 10 -- pixels depuis le haut de l'ecran (meme hauteur que la barre "< Floors >")
Tutorial.PointerBounce = 10 -- pixels

-- Etape "Pick up the fruits" : on vise les fruits au sol jusqu'a en porter ce nombre (ou le plateau
-- plein), puis on passe a l'etagere.
Tutorial.PickFruits = 5
-- Fruits deposes, en route vers le bol : on garde "Blend the fruits" pendant ce delai apres le depot
-- (et apres chaque fruit envoye sur le tapis + son trajet), au lieu de "Pick up the fruits".
Tutorial.TransitGraceSeconds = 2

-- Cibles (chemins depuis l'etage 1, comme Config/Setup)
Tutorial.Targets = table.freeze({
	FruitDrop = "Production.FruitDropPad",
	TakeJuices = "Production.TakeJuicePad",
	JuiceDrop = "Counter.JuiceDropPad",
	Cash = "Counter.CashPad",
	Blender = "Production.Blenders.Blender1", -- attributs BowlCount / Blending ; cible = son Panel
})

-- Ligne "ou aller" (2026-11-22) : triangle arrondi a contour noir, interieur blanc et bande bleue
-- (image donnee par l'utilisateur : "met ca et retourne", pas dans ICONSPACK) repete le long de la
-- ligne, pointe vers la cible, opaque, sans fond. Avant : icone Skip (guide_skip.png), chevrons.
Tutorial.GuideTexture = "rbxassetid://77298151299812" -- assets/textures/guide_triangle.png (256 x 320) : pointe vers le haut de l'image = vers Attachment0 (la cible)
Tutorial.GuideWidth = 2
Tutorial.GuideTextureLength = 2.5 -- studs par triangle (image 256 x 320 : garde les proportions avec GuideWidth = 2)
Tutorial.GuideSpeed = 2 -- defilement vers la cible
Tutorial.GuideStartHeight = 0.3 -- depart a hauteur des mains (centre du joueur + 0.3)
Tutorial.GuideColor = Color3.fromRGB(255, 255, 255) -- couleurs de l'icone gardees
Tutorial.GuideLightEmission = 0 -- 0 : le contour sombre de l'icone reste visible
Tutorial.ArrowHeight = 7 -- studs au-dessus d'un pad
Tutorial.ArrowHeightFruit = 3.5 -- studs au-dessus d'un fruit
Tutorial.ArrowHeightPanel = 4 -- studs au-dessus du panneau du mixeur
Tutorial.ArrowBounce = 1.2 -- studs (hauteur du rebond)
Tutorial.ArrowBounceSpeed = 1.1 -- rebonds par seconde
Tutorial.ArrowPop = 0.12 -- la fleche grossit de 12 % quand elle touche le bas du rebond
Tutorial.ArrowSize = 1 -- taille de la fleche 3D (1 = 3 studs de large)
-- Etage 2 debloque (2026-11-23) : tutoriel fini pour de bon (serveur : TutorialStep = Done), puis
-- UN conseil : ElevatorHintDelaySeconds apres l'arrivee a l'etage 2, des qu'il a le prix, fleche sur
-- l'amelioration Elevator Speed de la terrasse, jusqu'a l'achat d'une amelioration de l'ascenseur.
Tutorial.StopAtFloor = 2
Tutorial.ElevatorHintDelaySeconds = 60
Tutorial.ElevatorHintId = "ElevatorSpeed" -- tuile du panneau Elevator (Config/Floors.ElevatorUpgrades)
Tutorial.CashArrowUntilFloor = 2 -- fleche "argent a encaisser" cachee des que le joueur possede cet etage
Tutorial.RefreshSeconds = 0.2 -- l'etape et la cible sont recalculees a ce rythme

return table.freeze(Tutorial)
