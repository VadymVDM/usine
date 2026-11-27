--!strict
-- Personnages non joueurs (PNJ) : employes et clients, tous en R6 avec les animations de base de
-- Roblox. Les rigs sont crees par le serveur (NpcRig) a partir de ces tenues, puis ranges dans
-- ReplicatedStorage.NpcTemplates (les clients copient les modeles "Customer<n>").
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
	-- Animations R6 de base de Roblox (celles du script Animate par defaut)
	Animations = table.freeze({
		Idle = "rbxassetid://180435571",
		Walk = "rbxassetid://180426354",
	}),
	-- Animations R15 par defaut de Roblox (script Animate des joueurs, lues en Play le 2026-11-27) :
	-- employes R15 (Employees.<role>.r15). Marche et course melangees selon la vitesse, comme Animate.
	AnimationsR15 = table.freeze({
		Idle = "rbxassetid://507766388",
		Walk = "rbxassetid://913402848",
		Run = "rbxassetid://913376220",
	}),
	WalkAnimSpeed = 14, -- vitesse (studs/s) pour laquelle l'animation de marche R6 est a vitesse 1
	-- Ramassage d'un fruit par le Fruit Picker R15 (NpcRig.Pick, pose dessinee par CarryPoseController).
	-- Fractions de la duree du geste : la main touche le fruit, puis le fruit arrive sur le plateau.
	PickGrabAt = 0.42,
	PickTrayAt = 0.78,
	-- Depot a l'etagere (NpcRig.Dump) : fraction du geste ou les fruits quittent le plateau
	DumpReleaseAt = 0.45,
	WaypointLookAhead = 2.5, -- distance (studs) a laquelle l'employe vise deja le point de passage suivant
	StuckSeconds = 1.2, -- employe qui n'avance plus depuis X s : il est pose a l'arrivee (NpcRig)

	-- Clients (dessines par chaque client, voir CustomerController)
	CustomerWalkSpeed = 10,
	CustomerQueueGap = 3.2, -- studs entre un client au comptoir et celui qui attend derriere
	CustomerRenderDistance = 220, -- au-dela, pas de clients dessines pour cette base

	-- Employes : nom affiche au-dessus (anglais), couleur du tablier / de la casquette
	Employees = table.freeze({
		-- r15 = vrai perso Roblox actuel (comme les joueurs) ; les autres restent R6 (gestes NpcRig.Press /
		-- Deposit ecrits pour les epaules R6). Fruit Picker passe en R15 le 2026-11-27.
		Collector = table.freeze({ title = "Fruit Picker", color = Color3.fromRGB(80, 190, 80), r15 = true }),
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
