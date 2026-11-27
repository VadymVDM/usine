--!strict
-- Personnages non joueurs (PNJ) : employes et clients, tous en R15 (comme les joueurs) avec les
-- animations R15 par defaut de Roblox (R6 jusqu'au 2026-11-27). Les rigs sont crees par le serveur
-- (NpcRig) a partir de ces tenues, puis ranges dans ReplicatedStorage.NpcTemplates (les clients
-- copient les modeles "Customer<n>").
-- Ids = objets du catalogue Roblox (vetements classiques, cheveux, visages) ; 0 = rien.
-- Doc : docs/systems/ameliorations-employes.md, docs/systems/clients.md

export type Outfit = {
	shirt: number,
	pants: number,
	hair: number,
	hat: number,
	face: number,
	skin: Color3,
}

local SKINS = {
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 110, 80),
	Color3.fromRGB(124, 92, 70),
}

local Npcs = {
	TemplateFolder = "NpcTemplates", -- dossier dans ReplicatedStorage
	-- Tag (CollectionService) de chaque PNJ du monde, employe ou client : le client les rend
	-- invisibles quand ils sont loin de la camera (WorldDetailController, docs/perf-mobile.md).
	FarHideTag = "FarHideNpc",
	-- Animations R15 par defaut de Roblox (script Animate des joueurs, lues en Play le 2026-11-27) :
	-- tous les PNJ. Marche et course melangees selon la vitesse, comme Animate (Util/R15Walk).
	AnimationsR15 = table.freeze({
		Idle = "rbxassetid://507766388",
		Walk = "rbxassetid://913402848",
		Run = "rbxassetid://913376220",
	}),
	-- Ramassage d'un fruit par le Fruit Picker R15 (NpcRig.Pick, pose dessinee par CarryPoseController).
	-- Fractions de la duree du geste : la main touche le fruit, puis le fruit arrive sur le plateau.
	PickGrabAt = 0.42,
	PickTrayAt = 0.78,
	-- Depot a l'etagere (NpcRig.Dump) : fraction du geste ou les fruits quittent le plateau
	DumpReleaseAt = 0.45,
	-- Blender Operator R15 (NpcRig.Press / Deposit, pose dessinee par CarryPoseController), en secondes.
	-- Memes durees que l'ancien geste R6 (tweens serveur) : BlenderFxController et WorkerService.onPour en dependent.
	PressSeconds = 0.65, -- geste complet : bras leve (0.2), appui (0.1), tenu (0.05), redescend (0.3)
	PressReachSeconds = 0.3, -- le doigt touche le bouton
	DepositTurnSeconds = 0.3, -- se tourne vers la table en tendant les bras avant de lancer les gobelets
	WaypointLookAhead = 2.5, -- distance (studs) a laquelle l'employe vise deja le point de passage suivant
	StuckSeconds = 1.2, -- employe qui n'avance plus depuis X s : il est pose a l'arrivee (NpcRig)

	-- Clients (dessines par chaque client, voir CustomerController)
	CustomerWalkSpeed = 10,
	CustomerQueueGap = 3.2, -- etages 2+ (balcon) : studs entre un client au comptoir et celui qui attend derriere
	CustomerRenderDistance = 220, -- au-dela, pas de clients dessines pour cette base
	-- Vraies files d'attente (2026-11-27, demande : "vraies queues plus naturelles, apparaitre et
	-- disparaitre plus loin"). Rez-de-chaussee : une file par place du comptoir ; etages 2+ : la file
	-- en serpentin de la terrasse.
	CustomerLineLength = table.freeze({ 5, 4, 4, 3, 3 }), -- clients par file (selon le nombre de places), +-1 au hasard
	CustomerLineGap = table.freeze({ 2.8, 3.5 }), -- ecart avec le client de devant (au hasard, studs)
	CustomerLineJitter = 0.35, -- decalage de cote max dans une file (studs)
	CustomerSpawnGap = table.freeze({ 0.3, 0.9 }), -- secondes entre deux arrivees (au hasard)
	-- Apparition / depart le long de la rue : distance (studs) avec peu de clients -> beaucoup de clients
	CustomerSpawnFar = table.freeze({ 70, 30 }),
	CustomerLeaveFar = table.freeze({ 55, 20 }),
	CustomerFadeInSeconds = 1, -- apparition en fondu (au loin, en marchant)
	CustomerFadeOutStuds = 10, -- disparition en fondu sur les X derniers studs du depart
	CustomerMaxPerFloor = 48, -- rez-de-chaussee : clients dessines au plus pour une base
	-- Bulles rondes avec un emoji au-dessus des clients qui attendent (Fx/EmojiBubble)
	CustomerEmojiEvery = table.freeze({ 4, 12 }), -- secondes entre deux essais de bulle par client
	CustomerEmojiSeconds = 2.2, -- duree d'une bulle
	CustomerEmojiMax = 4, -- bulles en meme temps par etage (+ 1 par place du comptoir)
	CustomerImpatientSeconds = 25, -- au-dela (ou comptoir vide), emojis d'impatience
	CustomerHappySeconds = 1.8, -- bulle contente apres l'achat
	CustomerEmojis = table.freeze({
		Want = "🥤", -- au comptoir, comptoir vide (avec une pastille "?") : il faut poser des jus
		Waiting = table.freeze({ "🥤", "😋", "🤤", "🍹", "🧃", "🤔", "🎵", "👀", "😊", "🍊", "🍓", "🍉" }),
		Impatient = table.freeze({ "⏳", "😤", "😒", "🥱", "😴", "⌛" }),
		Happy = table.freeze({ "😍", "😋", "🤩", "❤️", "👍", "✨", "😄" }),
	}),

	-- Employes : nom affiche au-dessus (anglais), couleur du tablier / de la casquette
	Employees = table.freeze({
		Collector = table.freeze({ title = "Fruit Picker", color = Color3.fromRGB(80, 190, 80) }),
		Operator = table.freeze({ title = "Blender Operator", color = Color3.fromRGB(255, 150, 40) }), -- Operator1..4
		Waiter = table.freeze({ title = "Waiter", color = Color3.fromRGB(70, 160, 255) }), -- 2026-11-20 (WorkerService)
	}),
	-- Employes : t-shirt Roblox + jean noir (vetements gratuits du catalogue, createur "Roblox") ;
	-- NpcRig ajoute un tablier et une casquette de la couleur du poste.
	EmployeeOutfit = table.freeze({
		shirt = 3670737444, -- T-shirt Roblox
		pants = 382537569, -- jean noir
		hair = 0,
		hat = 0,
		face = 0,
		skin = SKINS[1],
	}) :: Outfit,

	-- Tenues des clients (une au hasard pour chaque client). Objets gratuits du catalogue Roblox,
	-- trouves le 2026-11-19 (AvatarEditorService:SearchCatalog, createur "Roblox").
	CustomerOutfits = table.freeze({
		table.freeze({ shirt = 382537702, pants = 382537569, hair = 376548738, hat = 0, face = 0, skin = SKINS[1] }),
		table.freeze({ shirt = 398635081, pants = 398633812, hair = 376526888, hat = 0, face = 0, skin = SKINS[2] }),
		table.freeze({ shirt = 382537085, pants = 382537806, hair = 1103003368, hat = 0, face = 0, skin = SKINS[3] }),
		table.freeze({ shirt = 144076358, pants = 144076760, hair = 451221329, hat = 0, face = 0, skin = SKINS[4] }),
		table.freeze({ shirt = 4047884939, pants = 382538503, hair = 2956239660, hat = 0, face = 0, skin = SKINS[5] }),
		table.freeze({ shirt = 382538059, pants = 398635338, hair = 63690008, hat = 0, face = 0, skin = SKINS[2] }),
		table.freeze({ shirt = 4047884046, pants = 382537950, hair = 7193454569, hat = 0, face = 0, skin = SKINS[3] }),
		table.freeze({ shirt = 398633584, pants = 398634487, hair = 376524487, hat = 0, face = 0, skin = SKINS[1] }),
	}) :: { Outfit },
	-- Couleurs de secours (torse / jambes) si un vetement ne se charge pas
	FallbackShirtColors = table.freeze({
		Color3.fromRGB(230, 80, 80),
		Color3.fromRGB(80, 150, 230),
		Color3.fromRGB(250, 200, 60),
		Color3.fromRGB(120, 200, 110),
		Color3.fromRGB(190, 110, 220),
		Color3.fromRGB(250, 150, 60),
	}),
}

return table.freeze(Npcs)
