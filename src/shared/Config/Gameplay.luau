--!strict
-- Valeurs fixes de la boucle de la zone 1 (pas des ameliorations : voir Upgrades.luau).
-- Doc : docs/systems/chaine-production.md, docs/systems/clients.md

local Gameplay = {
	-- Arbre
	MaxGroundFruits = 30, -- au-dela, l'arbre s'arrete : "Tree full!"
	FirstVisitApples = 3, -- pommes deja au sol pour un profil neuf
	TreeTrunkClearRadius = 3.5, -- pas de fruit a moins de cette distance du centre du tronc
	FruitFallHeight = 9, -- studs : hauteur d'ou le fruit tombe (dans le feuillage)
	FruitFallSeconds = 0.55, -- duree de la chute
	TreeFullText = "Tree full!",
	TreeLevelText = "%s Lv %d", -- nom de l'arbre (Tree.Names) + niveau = Upgrades "Tree" (pad "Upgrade Tree")
	TreeLevelLabelDrop = 2.4, -- studs : le texte du niveau est sous "Tree full!"

	-- Touche E (ProximityPrompt). Textes affiches : anglais.
	PromptDistance = 11, -- portee des autres prompts (table a jus, mixeurs, machines, portes)
	WalkPickupRadius = 3.2, -- ramassage en marchant : fruits a moins de X studs (a plat) du joueur (2026-11-19)
	PromptTexts = table.freeze({
		Buy = "Buy",
		Upgrade = "Upgrade",
		Max = "Max level",
		Unlock = "Unlock",
		Hire = "Hire",
		BlenderObject = "Blender",
		BlenderAction = "Blend",
		-- Pass Thief (2026-11-27) : prompt E sur les jus d'une AUTRE base ({name} = proprietaire)
		StealAction = "Steal",
		StealTableObject = "{name}'s Juice Table",
		StealCounterObject = "{name}'s Counter",
	}),
	Messages = table.freeze({
		InventoryFull = "Your inventory is full!",
		HandsFull = "Your hands are full!",
		NoFruits = "Pick up fruits first!",
		NoJuice = "No juice to take yet!",
		AutoCollectOn = "Auto Collect is active!",
		InstantSellOn = "Instant Sell is active!",
		SpeedBoostOn = "Waiter Speed x10 is active!",
		BillboardOn = "Billboard is active! 2X sell price!",
		JuiceTableFull = "Juice table is full!",
		-- Pass Thief (2026-11-23) : {n}, {name} remplaces par ThiefService
		StealDone = "You stole {n} juices from {name}!",
		StealVictim = "{name} stole {n} juices from you! Your insurance refunded everything.",
		StealNothing = "No juice to steal here!",
		-- Vol a l'unite (2026-11-27) : {price} remplace par ThiefService (Shop.Steal.price)
		StealFree = "Free steal used! Next steals cost {price} Robux.",
		StealCredit = "Your paid steal is saved: press E on a stand to use it!",
	}),

	-- Pass Thief (ThiefService, refait le 2026-11-27) : touche E "Steal" sur les jus de la table a
	-- jus ou du comptoir d'une AUTRE base. Sans le pass : fenetre d'achat Roblox, et les jus vises
	-- sont "photographies" a l'appui sur E (donnes apres l'achat, meme si la table a change).
	ThiefPromptCooldown = 2, -- secondes minimum entre deux fenetres d'achat pour un meme joueur
	StealPromptDistance = 14, -- portee du prompt Steal (studs ; le comptoir est long)
	StealPendingSeconds = 180, -- la "photo" reste valable ce temps apres l'appui sur E (achat lent)
	StealRefreshSeconds = 0.5, -- frequence de mise a jour des prompts Steal (jus presents ou non)
	-- Avec le pass : E = prendre ses mains pleines de jus, sans limite de temps (pass "UNLIMITED",
	-- 2026-11-27 : l'ancien StealCooldown de 60 s par victime est supprime). La victime ne perd rien
	-- (seul le voleur voit les gobelets disparaitre).
	StealHideSeconds = 60, -- duree pendant laquelle les gobelets voles restent caches chez le voleur

	-- Pads d'action (2026-11-19 : on marche dessus, pas de touche E). Titres affiches au-dessus.
	-- Production.FruitDropPad (fruits du plateau -> caisses), Production.TakeJuicePad (table a jus ->
	-- mains), Counter.JuiceDropPad (jus des mains ->
	-- comptoir), Counter.CashPad (tas d'argent -> joueur). Le serveur teste la position du joueur.
	PadTitles = table.freeze({
		FruitDrop = "Drop Fruits",
		TakeJuice = "Take Juices",
		JuiceDrop = "Drop Juices",
		Cash = "Collect Cash",
	}),
	PadActionSeconds = 0.4, -- delai minimum entre deux actions d'un meme pad (le joueur reste dessus)
	-- Le client previent le serveur des qu'il monte sur un pad (remote PadEnter) : plus besoin
	-- d'attendre que la position du personnage arrive au serveur. Le serveur accepte si le joueur est
	-- a moins de PadEnterMargin studs (a plat) de la zone (sa position serveur a un peu de retard).
	PadEnterMargin = 4,

	-- Joueur
	CarryCapacity = 20, -- fruits sur le plateau au-dessus de la tete, fixe en phase 1
	JuiceCarryCapacity = 18, -- jus portes (plateau sur la tete : 2 couches de 3 x 3) ; 12 avant le 2026-11-20
	PadHeightAbove = 4, -- studs au-dessus d'une zone (pads, tas d'argent) ou le contact compte encore
	-- Sortie d'un pad (2026-11-20, "ca clique plusieurs fois si on reste dessus") : une fois dessus,
	-- on n'en sort qu'a PadExitMargin studs du bord, ou PadExitHeight studs au-dessus (un saut ne
	-- compte pas comme une sortie). Evite les entrees / sorties en boucle au bord (achat, son).
	PadExitMargin = 1.5,
	PadExitHeight = 12,
	ContactCheckSeconds = 0.1, -- frequence de detection des contacts par le serveur

	-- Mixeurs (refonte du 2026-11-19 : on mixe au bouton E). Taille du bol : niveau de chaque mixeur
	-- (Upgrades "Blender1".."Blender4", 5 niveaux, panneau suspendu au-dessus du mixeur).
	MaxBlenders = 4, -- Production.Blenders.Blender1..4 (le 1 est offert, 2-4 : Upgrades "BlenderN")
	BlendSeconds = 2.5, -- duree d'un mixage, quel que soit le nombre de fruits ; puis tous les jus sortent
	-- Tapis : vitesse = Upgrades "ConveyorSpeed" (fruits par seconde, panneau "Conveyor" du mur du fond).
	-- Le trajet raccourcit avec la vitesse : ConveyorTravelSeconds * (vitesse niv. 1 / vitesse)^0.6.
	ConveyorTravelSeconds = 1.6, -- trajet d'un fruit sur le tapis jusque dans le bol au niveau 1 (serveur ET animation)
	ConveyorTravelMin = 0.75,
	OperatorReactSeconds = 1.0, -- l'operateur appuie ~1 s apres que son bol est plein (moins vite qu'un joueur)
	OperatorIdleBlendSeconds = 8, -- il appuie aussi si le bol n'est pas plein mais ne bouge plus depuis X s

	-- Plateau sur la tete (TrayController, client) : les fruits ramasses s'empilent dessus en vrac
	TrayFruitScale = 0.5, -- taille des fruits sur le plateau (x la taille au sol)
	TrayAboveHead = 0.15, -- studs entre le haut de la tete et le dessous du plateau

	-- Affichage (positions des modeles, textes au-dessus des piles)
	-- Jus portes : plateau sur la tete comme les fruits (HandStackController ; avant le 2026-11-19 :
	-- pile devant le torse). Couches de 3 x 3 gobelets, ecart JuiceCupSpacing.
	JuiceTrayFruitLift = 2.4, -- studs de plus quand le plateau des fruits est aussi sur la tete
	JuiceCupSpacing = 1.1, -- ecart entre deux gobelets sur la table / le comptoir (grille)
	-- Table a jus : bloc compact centre sur la palette (avant : une ligne de 22 au ras du sol,
	-- "des jus par terre"). 6 x 4 = 24 par couche ; 50 jus (limite max) = un peu plus de 2 couches.
	-- Table a jus surelevee (2026-11-19 soir, avant : palette au sol). Elle s'agrandit avec Juice
	-- Table (JuiceLimit) : colonnes de la grille par palier de niveau (1-3, 4-6, 7-9).
	JuicePileCols = 6,
	JuicePileRows = 4,
	JuicePileColsByTier = table.freeze({ 6, 9, 12 }),
	JuiceTableTierLevels = table.freeze({ 1, 4, 7 }), -- niveau de JuiceLimit ou commence chaque palier
	LabelMaxDistance = 70, -- distance max des textes "n/max", "xN" et "Tree full!"
	BinLabelMaxDistance = 40, -- distance max du nombre au-dessus de chaque caisse ("x12")
	JuiceValueLabelLift = 2.1, -- hauteur du prix "$1.2K" au-dessus du "n/max" de la table a jus
	JuiceValueColor = Color3.fromRGB(120, 255, 110), -- vert, comme le tas d'argent du comptoir

	-- Comptoir, clients et tas d'argent (lot D)
	MoneyStacks = 12, -- nombre de liasses sur le plateau (grille)
	MoneyBillsMax = 60, -- billets affiches au maximum
	MoneyBillsPerDoubling = 4, -- +4 billets a chaque fois que le montant double
	CounterCupLayersMax = 3, -- couches de gobelets dessinees sur le comptoir (au-dela : compteur seul, pas de limite)
	SaleMaxSpots = 5, -- places devant le comptoir (Markers.CustomerSpot1..5)
	IncomeWindowSeconds = 120, -- panneau "MONEY / HOUR" : ventes des 2 dernieres minutes ramenees a 1 h
	IncomeMinSeconds = 30, -- au debut, on divise au moins par 30 s (pas de chiffre enorme apres 2 ventes)
	IncomeAttributeSeconds = 10, -- attribut joueur IncomePerSecond (montant des offres d argent) mis a jour toutes les X s

	-- Achats (pads verts des employes, boutons des panneaux)
	BuyCooldownSeconds = 0.25, -- delai minimum entre deux achats d'un meme joueur (clics rapides sur les tuiles)
	BuyHoldSeconds = 0.6, -- appui long pour acheter (prompt E des machines, pads) ; tuiles = simple clic
	PadRepeatSeconds = 0.8, -- pad "Upgrade Tree" : on reste dessus = 1 niveau de plus toutes les X s
	BuildPushMargin = 2, -- studs : un joueur dans une machine qui se construit est sorti a cette distance du bord
	TileClickDistance = 36, -- portee du clic sur les tuiles des panneaux d'ameliorations (studs)
	BuyClickExtraDistance = 8, -- marge (studs) en plus de la portee d'un clic / prompt pour l'accepter
	PadDenyFlashSeconds = 0.6, -- pad / bouton rouge quand l'argent manque (client)
	PromptCooldownSeconds = 0.25, -- delai minimum entre deux actions E d'un joueur

	-- Employes R15 (WorkerService)
	-- Fruits portes par le Fruit Picker avant d'aller a l'etagere : Upgrades "PickerCarry"
	-- (2 au depart -> 6, panneau Fruit Picker). Avant le 2026-11-20 : toujours 6.
	-- Vitesse de base du Fruit Picker (2026-11-20, demande : "30 % plus lent") : x0.7 sur sa marche
	-- et ses pauses, multiplie ensuite par PickerSpeed.
	PickerBaseSpeed = 0.7,
	EmployeeWalkSpeed = 15,
	EmployeePauseSeconds = 0.35, -- petite pause quand un employe prend / pose quelque chose
	-- Fruit Picker (2026-11-27) : il s'arrete a PickerReach studs du fruit (pas dessus), puis geste de
	-- ramassage de PickerPickSeconds (divise par sa vitesse) : accroupi, main au sol, fruit au plateau.
	PickerReach = 2.1,
	PickerPickSeconds = 0.65,
	PickerDumpSeconds = 0.8, -- geste de depot a l'etagere (plateau bascule vers les caisses), / vitesse
	NpcMoveTimeout = 7, -- secondes max pour atteindre un point (sinon il y est replace)

	-- Waiter (WorkerService, 2026-11-20 : employe paye en argent du jeu, volontairement LENT ; le
	-- pass Waiter Speed x10 est la version rapide). Il prend jusqu'a WaiterCarry jus sur la table, des qu'il y
	-- en a WaiterCarry ou que des jus attendent depuis WaiterWaitSeconds, et les porte au comptoir.
	-- Demande du 2026-11-20 : "il en prend 9 a la fois de base et marche plus lentement" (avant : 5, x0.65)
	WaiterCarry = 9,
	WaiterBaseSpeed = 0.5, -- x EmployeeWalkSpeed (7.5 studs/s ; joueur : 16) et pauses plus longues
	WaiterWaitSeconds = 3,

	-- Pass Robux Instant Sell (2026-11-21, ancien "Auto Sell" ; pad violet a droite du pad Drop
	-- Juices, PassPadService ; effet dans CustomerService) : les jus que le joueur pose sur le
	-- comptoir sont vendus des que l'animation de depot est finie. Attente = FlySeconds + (n - 1) x
	-- StaggerSeconds (memes valeurs que HandStackController FLY_SECONDS / FLY_STAGGER), au plus
	-- MaxWaitSeconds, + ExtraSeconds pour voir les gobelets poses.
	InstantSellFlySeconds = 0.32,
	InstantSellStaggerSeconds = 0.06,
	InstantSellMaxWaitSeconds = 1.5,
	InstantSellExtraSeconds = 0.15,

	-- Boost route (PlayerUpgradeService, 2026-11-20) : sur la route et les trottoirs (pieces de
	-- Workspace.Map.Road nommees ci-dessous), vitesse de marche x RoadSpeedMultiplier (x5 -> x3.5
	-- le meme jour). Verifie toutes les RoadCheckSeconds par le serveur.
	RoadSpeedMultiplier = 3.5,
	RoadPartNames = { "Asphalt", "Sidewalk", "Curb" },
	RoadCheckSeconds = 0.1,
	RoadMaxHeight = 8, -- studs au-dessus de la piece encore comptes "sur la route" (saut)

	-- Passes Robux des pads violets (PassPadService, 2026-11-20 ; docs/systems/pads-robux.md).
	-- Pass "Waiter Speed x10" (2026-11-20, avant "Speed x10" qui accelerait le joueur) : vitesse du
	-- Waiter (marche et pauses, WorkerService) et son debit en nombres (Lib/FloorIncome) x10.
	WaiterSpeedPassMultiplier = 10,
	-- Vitesse du joueur (PlayerUpgradeService.applyWalkSpeed) : amelioration Speed x RoadSpeedMultiplier
	-- (sur la route), plafonnee a MaxWalkSpeed (filet de securite).
	MaxWalkSpeed = 400,
	BillboardSellMultiplier = 2, -- pass Billboard : prix de vente des jus x2 (CustomerService, en plus du rebirth)
}

return table.freeze(Gameplay)
