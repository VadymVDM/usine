--!strict
-- Seul endroit qui liste les remotes du jeu. Le serveur les cree au demarrage dans
-- ReplicatedStorage.Remotes ; le client les attend avec un delai maximum.
-- Les actions du jeu passent par des ProximityPrompt (touche E) et des contacts, tous verifies par
-- le serveur. Remotes client -> serveur : SetSetting (reglages du menu Settings, sans effet sur
-- l'argent ni la partie ; verifie par SettingsService : cle connue, booleen, delai) et BuyUpgrade
-- (achat apres appui long / confirmation ; verifie par UpgradeService : id connu, sa base,
-- distance, delai, niveau max, argent) et PadEnter (le joueur vient de monter sur un pad d'action ;
-- verifie par ProductionService / CustomerService : nom connu, sa base, position, delai) et
-- FloorTeleport (panneau FLOORS ; verifie par FloorService : entier, etage achete, delai) et
-- IndexClaim (bouton CLAIM de l'Index ; verifie par IndexService : fruit connu, decouvert, pas deja pris, delai) et
-- BuyPlayerUpgrade (menu Upgrade du HUD ; verifie par PlayerUpgradeService : id connu, delai, niveau max, puis fenetre d'achat Robux) et
-- RebirthRequest (menu Rebirth ; verifie par RebirthService : action connue, delai, 10 etages, distance, argent) et
-- LuckyCashBuy (tas d'argent Lucky Cash ; verifie par LuckyCashService : sauvegarde chargee, delai, puis fenetre d'achat Robux) et
-- OfflineEarnings (ecran Welcome Back ; verifie par OfflineService : action connue, delai, sauvegarde chargee, offre pas deja prise) et
-- ShopBuy (boutique et offres limitees ; verifie par RobuxShopService : types, cle connue, delai, puis fenetre d'achat Robux) et
-- IntroDone (fin ou Skip de la cinematique d'ouverture ; IntroService : sauvegarde chargee, delai, une seule fois) et
-- TutorialProgress (etape suivante du tutoriel ; TutorialService : entier, exactement +1, sauvegarde chargee, delai).
-- Doc : docs/architecture.md (section Remotes)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type RemoteName = "Notify" | "Feedback" | "WorldFx" | "SetSetting" | "BuyUpgrade" | "PadEnter" | "AdminAction" | "FloorTeleport" | "IndexState" | "IndexClaim" | "BuyPlayerUpgrade" | "RebirthRequest" | "LuckyCashBuy" | "OfflineEarnings" | "ShopBuy" | "ShopGift" | "IntroDone" | "TutorialProgress"

-- Nom -> sens et role. Les verifications de chaque remote sont dans docs/architecture.md.
local EVENTS: { [string]: string } = {
	Notify = "serveur -> client : (message court en anglais, isError) ; isError = true -> texte rouge (refus, pas assez d'argent)",
	Feedback = "serveur -> un client : effet de SON action (ramassage, depot, jus, argent, \"Paid\" = son de paiement apres un achat, \"PurchasePrompt\" = fenetre d'achat Robux ouverte : effet d'ecran)",
	WorldFx = "serveur -> tous : effet visible par tous dans une base (vente, fruits vers les caisses)",
	SetSetting = "client -> serveur : (cle, booleen) reglage du joueur a sauvegarder (Music, Effects, LowQuality)",
	BuyUpgrade = "client -> serveur : (id) acheter un niveau apres appui long ou confirmation",
	PadEnter = "client -> serveur : (nom du pad) le joueur vient de monter sur un pad d'action de SA base",
	AdminAction = "client -> serveur : (action, userIdCible?, valeur?) bouton du panneau admin ; refuse si le joueur n'est pas admin",
	FloorTeleport = "client -> serveur : (numero d'etage) aller a un etage achete de SA tour (FloorService : entier, achete, delai)",
	IndexState = "serveur -> un client : { discovered = {ids}, claimed = {ids} } etat de l'Index du joueur",
	IndexClaim = "client -> serveur : (id du fruit) prendre la recompense de l'Index (IndexService : fruit connu, decouvert, pas deja pris, delai)",
	BuyPlayerUpgrade = "client -> serveur : (id) acheter un niveau de vitesse / fruits / jus portes (PlayerUpgradeService : id connu, delai, niveau max ; ouvre la fenetre d'achat Robux)",
	RebirthRequest = "client -> serveur : (action) \"Rebirth\" (payer et renaitre) ou \"KeepCash\" (demande l'achat Robux) ; RebirthService : action connue, delai, 10 etages, pres de la machine, argent",
	LuckyCashBuy = "client -> serveur : (rien) acheter le tas Lucky Cash (LuckyCashService : sauvegarde chargee, delai ; ouvre la fenetre d'achat Robux, le montant est calcule par le serveur)",
	ShopBuy = "client -> serveur : (kind, key, isGift) acheter un boost / pass / pack d'argent / offre (RobuxShopService : chaines courtes, cle connue, delai ; ouvre la fenetre d'achat Robux, montants calcules par le serveur)",
	ShopGift = "client -> serveur : (passKey, recipientUserId) offrir un pass a un joueur du serveur (GiftService : cle connue, destinataire present, pas soi-meme, pas deja possede, delai ; ouvre le produit Gift, rien n est donne avant le recu)",
	TutorialProgress = "client -> serveur : (numero de l'etape suivante) etape du tutoriel faite (TutorialService : entier, exactement l'etape actuelle + 1, delai ; guidage seulement, aucun effet sur la partie)",
	IntroDone = "client -> serveur : (rien) la cinematique d'ouverture est finie ou passee (IntroService : sauvegarde chargee, delai ; ecrit IntroSeen = true une fois)",
	OfflineEarnings = "client -> serveur : (\"Ready\" | \"Claim\" | \"Double\") ecran Welcome Back (OfflineService : action connue, delai, offre pas deja prise ; le montant est calcule par le serveur). serveur -> un client : (\"Show\", secondes, montant) | (\"Claimed\") ferme l'ecran",
}

local FOLDER_NAME = "Remotes"
local CLIENT_TIMEOUT_SECONDS = 15

local Remotes = {}

-- Serveur : renvoie le RemoteEvent (le cree s'il n'existe pas encore).
function Remotes.GetServerEvent(name: RemoteName): RemoteEvent
	assert(RunService:IsServer(), "Remotes.GetServerEvent : serveur seulement")
	assert(EVENTS[name] ~= nil, "Remote inconnu : " .. tostring(name))
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	assert(folder, "Remotes : dossier introuvable")
	local event = folder:FindFirstChild(name)
	if event == nil then
		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = folder
		event = created
	end
	assert(event and event:IsA("RemoteEvent"), "Remotes : " .. name .. " n'est pas un RemoteEvent")
	return event :: RemoteEvent
end

-- Client : attend le RemoteEvent (nil + avertissement s'il n'arrive pas a temps).
function Remotes.WaitClientEvent(name: RemoteName): RemoteEvent?
	assert(RunService:IsClient(), "Remotes.WaitClientEvent : client seulement")
	assert(EVENTS[name] ~= nil, "Remote inconnu : " .. tostring(name))
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_TIMEOUT_SECONDS)
	local event = if folder then folder:WaitForChild(name, CLIENT_TIMEOUT_SECONDS) else nil
	if event == nil or not event:IsA("RemoteEvent") then
		warn(`[Remotes] {name} introuvable apres {CLIENT_TIMEOUT_SECONDS} s`)
		return nil
	end
	return event :: RemoteEvent
end

return table.freeze(Remotes)
