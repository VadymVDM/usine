--!strict
-- Sauvegarde des joueurs avec ProfileStore (verrou de session, sauvegarde auto, BindToClose).
-- Seul module qui ouvre/ferme les sessions. Chaque champ a un seul proprietaire qui le modifie
-- (Money -> MoneyService, Boosts -> RobuxShopService, Floors[n].Upgrades -> UpgradeService, PlayerUpgrades -> PlayerUpgradeService, longueur de Floors (achat d'un etage)
-- -> FloorService, DiscoveredFruits -> TreeService).
-- Tour d'etages (SchemaVersion 4, 2026-11-20) : Floors = une case par etage achete (1..MaxFloors),
-- chacune avec ses ameliorations ; TowerUpgrades = ameliorations de toute la tour (ascenseur).
-- Doc : docs/systems/sauvegarde.md

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore) :: any
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Fruits = require(Config:WaitForChild("Fruits"))
local FloorsConfig = require(Config:WaitForChild("Floors"))
local PlayerUpgrades = require(Config:WaitForChild("PlayerUpgrades"))
local Shop = require(Config:WaitForChild("Shop"))
local SetupConfig = require(Config:WaitForChild("Setup"))
local TutorialConfig = require(Config:WaitForChild("Tutorial"))

-- Premier fruit (toujours decouvert) : pris dans la Config, jamais ecrit en dur
local FIRST_FRUIT_ID: string = Fruits.List[1].id

export type PlayerData = {
	SchemaVersion: number,
	Money: number,
	Rebirths: number,
	Floors: { FloorData }, -- un element par etage achete, dans l'ordre (nombre d'etages = #Floors)
	TowerUpgrades: { [string]: number }, -- ElevatorSpeed, ElevatorCabin (toute la tour)
	PlayerUpgrades: { [string]: number }, -- vitesse, fruits et jus portes (menu Upgrade, PlayerUpgradeService)
	DiscoveredFruits: { [string]: boolean },
	ClaimedFruits: { [string]: boolean }, -- recompenses de l'Index deja prises (IndexService)
	LastLogout: number,
	IntroSeen: boolean,
	Settings: { [string]: boolean | number }, -- reglages (Music, Effects = volumes 0..1 ; LowQuality), SettingsService
	JuicesSold: number, -- jus vendus depuis toujours (LeaderboardService)
	TimePlayed: number, -- secondes de jeu depuis toujours (LeaderboardService)
	KeptTrees: { number }, -- niveau d'arbre le plus haut de chaque etage avant un rebirth (pass Rebirth Master, RebirthService)
	PurchaseIds: { string }, -- derniers achats Robux appliques (GrantPurchaseOnce : un achat n'est jamais donne deux fois)
	-- Boosts Robux (RobuxShopService, 2026-11-20) : secondes restantes par stat ("Money", "Luck",
	-- "Speed") et multiplicateur ("x2", "x3", "x5"). Ex. { Money = { x2 = 900 } }.
	Boosts: { [string]: { [string]: number } },
	-- Offres a acheter une seule fois deja achetees (cle d'offre -> true, `oneTime` dans Config/Shop ;
	-- RobuxShopService, 2026-11-21). Ex. { OfferStarter = true }. Champ ajoute sans migration :
	-- absent des anciennes sauvegardes, sanitize le cree vide.
	BoughtOffers: { [string]: boolean },
	-- Passes recus en cadeau (cle de Shop.Passes -> true ; GiftService, 2026-11-23). Comptent comme
	-- achetes (Lib/GamePass). Champ ajoute sans migration : sanitize le cree vide.
	GiftedPasses: { [string]: boolean },
	OfflineReward: OfflineReward, -- derniere offre de gains hors ligne (OfflineService)
	-- Achats Robux "Keep Cash" payes alors que le rebirth n'etait pas possible (moins de 10 etages) :
	-- utilises au prochain rebirth (RebirthService, 2026-11-21). Champ sans migration (Reconcile : 0).
	KeepCashTokens: number,
	-- Usine a construire (SetupService, SchemaVersion 6, 2026-11-21) : pads FREE de l'etage 1 deja
	-- faits (0 = profil neuf, usine vide ; Config/Setup.Done = tout construit).
	Setup: number,
	-- Tutoriel (TutorialService, SchemaVersion 7, 2026-11-22) : etape faite (0 = debut, voir
	-- Config/Tutorial.Phases ; Tutorial.Done = fini). Profils existants : Done (migration 6).
	TutorialStep: number,
	-- Premiere amelioration de vitesse gratuite deja prise (PlayerUpgradeService, SchemaVersion 7).
	FreeSpeedUsed: boolean,
}

-- Gains hors ligne (OfflineService, SchemaVersion 5) : Claimed = argent deja donne (CLAIM, x2 ou
-- depart) ; Doubled = achat x2 deja donne. Par defaut : rien a prendre.
export type OfflineReward = {
	Amount: number,
	Seconds: number,
	Claimed: boolean,
	Doubled: boolean,
}

export type FloorData = {
	Upgrades: { [string]: number }, -- niveaux des ameliorations / employes de cet etage
}

type Profile = {
	Data: PlayerData,
	SessionLoadCount: number,
	OnSessionEnd: any,
	OnLastSave: any,
	OnSave: any,
	AddUserId: (Profile, number) -> (),
	Reconcile: (Profile) -> (),
	EndSession: (Profile) -> (),
	IsActive: (Profile) -> boolean,
	Save: (Profile) -> (),
	LastSavedData: any, -- derniere version ecrite dans le DataStore (GrantPurchaseOnce)
	OnAfterSave: any,
}

local TEMPLATE: PlayerData = {
	SchemaVersion = GameConfig.SchemaVersion,
	Money = GameConfig.StartingMoney,
	Rebirths = 0,
	Floors = { { Upgrades = Upgrades.DefaultLevels() } },
	TowerUpgrades = table.clone(FloorsConfig.TowerUpgradeDefaults),
	PlayerUpgrades = PlayerUpgrades.DefaultLevels(),
	DiscoveredFruits = { [FIRST_FRUIT_ID] = true },
	ClaimedFruits = {},
	LastLogout = 0,
	IntroSeen = false,
	Settings = table.clone(GameConfig.DefaultSettings),
	JuicesSold = 0,
	TimePlayed = 0,
	KeptTrees = {},
	PurchaseIds = {},
	Boosts = {},
	BoughtOffers = {},
	GiftedPasses = {},
	OfflineReward = { Amount = 0, Seconds = 0, Claimed = true, Doubled = true },
	KeepCashTokens = 0,
	Setup = 0, -- profil neuf : usine vide (les anciens profils passent a Done par la migration 5)
	TutorialStep = 0, -- profil neuf : tutoriel au debut (anciens profils : fini, migration 6)
	FreeSpeedUsed = false, -- profil neuf : 1re vitesse gratuite (anciens profils : deja prise, migration 6)
}

-- Nombre d'achats Robux retenus dans PurchaseIds (les plus recents)
local PURCHASE_ID_CACHE = 50

local DataService = {}

local store: any = nil
local savingEnabled = false
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local firstVisit: { [Player]: boolean } = {}
-- Data.LastLogout lu au chargement, avant que la session ne le mette a jour (OfflineService)
local previousLogout: { [Player]: number } = {}
local loadedCallbacks: { (Player, PlayerData) -> () } = {}
local removingCallbacks: { (Player) -> () } = {}
-- Joueurs dont la sauvegarde repart a zero a leur depart (panneau admin, AdminService)
local resetOnLeave: { [Player]: boolean } = {}
-- Joueurs dont la sauvegarde est remplacee par une copie a leur depart (tests Studio, DebugService)
local replaceOnLeave: { [Player]: { [string]: any } } = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Copie profonde (le modele contient des tables dans des tables : ne jamais les partager)
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Migrations : une etape par version. Le modele (Reconcile) ajoute deja les champs absents.
local MIGRATIONS: { [number]: (PlayerData) -> () } = {
	-- 1 -> 2 (2026-11-19, refonte du mixeur) : l'ancien employe "Presser" (Blender Operator qui
	-- portait les fruits au tapis) devient l'operateur du mixeur 1 (meme prix, 150 $) : rien n'est perdu.
	[1] = function(data: PlayerData)
		local upgrades: any = (data :: any).Upgrades
		if type(upgrades) ~= "table" then
			return
		end
		local presser = upgrades.Presser
		if type(presser) == "number" and presser >= 1 then
			upgrades.Operator1 = 1
		end
		upgrades.Presser = nil
	end,
	-- 2 -> 3 (2026-11-19 soir, "un pad qui ameliore l'arbre" + mixeurs a 5 niveaux) :
	--   * TreeSpeed + TreeLuck -> Tree (un seul niveau : le fruit suivant ET plus vite). On garde le
	--     niveau Luck (memes fruits possibles), ou Speed s'il etait plus haut ;
	--   * BowlSize (meme taille pour tous les bols : 5 / 8 / 12 / 20) -> niveau de chaque mixeur
	--     possede (bols 5 / 8 / 12 / 16 / 20) : rien n'est perdu.
	[2] = function(data: PlayerData)
		local upgrades: any = (data :: any).Upgrades
		if type(upgrades) ~= "table" then
			return
		end
		local function num(value: any): number
			return if isFiniteNumber(value) then math.floor(value) else 0
		end
		local tree = math.max(1, num(upgrades.TreeLuck), num(upgrades.TreeSpeed))
		upgrades.Tree = math.max(num(upgrades.Tree), tree)
		upgrades.TreeSpeed = nil
		upgrades.TreeLuck = nil
		local bowl = num(upgrades.BowlSize)
		local blenderLevel = if bowl >= 4 then 5 else math.max(1, bowl)
		for n = 1, 4 do
			local id = "Blender" .. n
			local owned = n == 1 or num(upgrades[id]) >= 1
			if owned then
				upgrades[id] = math.max(num(upgrades[id]), blenderLevel)
			end
		end
		upgrades.BowlSize = nil
	end,
	-- 3 -> 4 (2026-11-20, tour d'etages) : les ameliorations deviennent celles de l'etage 1 ;
	-- l'arbre d'un etage n'a que 10 fruits (niveau Tree borne a 10 par sanitize) ; ascenseur a 0.
	-- Reconcile a deja pose Floors / TowerUpgrades par defaut : on remplace Floors par l'ancien etage.
	[3] = function(data: PlayerData)
		local raw = data :: any
		local upgrades: any = raw.Upgrades
		if type(upgrades) == "table" then
			data.Floors = { { Upgrades = upgrades } }
		end
		raw.Upgrades = nil
	end,
	-- 4 -> 5 (2026-11-20, gains hors ligne) : champ OfflineReward ajoute. Reconcile l'a deja pose
	-- (rien a prendre) ; LastLogout existait deja. Rien a convertir.
	[4] = function(_data: PlayerData) end,
	-- 5 -> 6 (2026-11-21, usine a construire) : Reconcile a pose Setup = 0 (profil neuf) ; un profil
	-- existant a deja son usine : toutes les etapes sont faites (rien ne change pour lui).
	[5] = function(data: PlayerData)
		data.Setup = SetupConfig.Done
	end,
	-- 6 -> 7 (2026-11-22, tutoriel etape par etape) : Reconcile a pose TutorialStep = 0 et
	-- FreeSpeedUsed = false. Un profil dont l'usine est deja construite n'a pas de tutoriel ni de
	-- vitesse gratuite (rien ne change pour lui) ; une usine pas finie (profil du jour) : tuto au debut.
	[6] = function(data: PlayerData)
		if data.Setup >= SetupConfig.Done then
			data.TutorialStep = TutorialConfig.Done
			data.FreeSpeedUsed = true
		end
	end,
}

local function migrate(player: Player, data: PlayerData)
	local version = if isFiniteNumber(data.SchemaVersion) then data.SchemaVersion else 1
	while version < GameConfig.SchemaVersion do
		local step = MIGRATIONS[version]
		if step then
			step(data)
		end
		version += 1
	end
	data.SchemaVersion = math.max(version, GameConfig.SchemaVersion)
end

-- Corrige les valeurs impossibles (sauvegarde abimee, Config changee) sans jamais effacer le profil.
-- Peut lever une erreur sur une sauvegarde tres abimee : l'appelant est protege par pcall.
local function sanitize(player: Player, data: PlayerData)
	local money: any = data.Money
	if not isFiniteNumber(money) or money < 0 or money % 1 ~= 0 or money > GameConfig.MaxMoney then
		local fixed = if isFiniteNumber(money)
			then math.clamp(math.floor(money), 0, GameConfig.MaxMoney)
			elseif money == math.huge then GameConfig.MaxMoney
			else 0
		warn(`[DataService] Argent invalide pour {player.UserId} ({tostring(money)}), corrige en {fixed}`)
		data.Money = fixed
	end
	if not isFiniteNumber(data.Rebirths) or data.Rebirths < 0 then
		data.Rebirths = 0
	end
	-- Plafond : une valeur enorme (sauvegarde abimee) ferait planter l'IntValue du classement.
	data.Rebirths = math.min(math.floor(data.Rebirths), GameConfig.MaxRebirths)
	-- Etages : liste sans trou de 1 a MaxFloors etages (au moins l'etage 1). Une case abimee arrete la
	-- liste (on ne garde pas d'etage "apres un trou") ; ses ameliorations sont remises par defaut.
	local floors: any = data.Floors
	local cleanFloors: { FloorData } = {}
	if type(floors) ~= "table" then
		warn(`[DataService] Floors invalide pour {player.UserId}, remis a 1 etage`)
		floors = {}
	end
	for n = 1, FloorsConfig.MaxFloors do
		local floor = floors[n]
		if type(floor) ~= "table" then
			break
		end
		local levels: any = floor.Upgrades
		if type(levels) ~= "table" then
			warn(`[DataService] Upgrades de l'etage {n} invalide pour {player.UserId}, remis par defaut`)
			levels = {}
		end
		local clean: { [string]: number } = {}
		for _, upgrade in Upgrades.List do
			local level: any = levels[upgrade.id]
			local maxLevel = Upgrades.GetMaxLevel(upgrade.id, data.Rebirths)
			if not isFiniteNumber(level) then
				level = upgrade.startLevel
			end
			-- Pas de math.clamp : il plante si la Config donne un max < niveau de depart.
			clean[upgrade.id] = math.max(upgrade.startLevel, math.min(math.floor(level), maxLevel))
		end
		table.insert(cleanFloors, { Upgrades = clean })
	end
	if #cleanFloors == 0 then
		table.insert(cleanFloors, { Upgrades = Upgrades.DefaultLevels() })
	end
	data.Floors = cleanFloors
	-- Ameliorations de la tour : seulement les cles connues, entiers entre 0 et leur maximum
	local tower: any = data.TowerUpgrades
	local cleanTower: { [string]: number } = {}
	for id, default in FloorsConfig.TowerUpgradeDefaults do
		local level = if type(tower) == "table" then tower[id] else nil
		cleanTower[id] = if isFiniteNumber(level)
			then math.max(0, math.min(math.floor(level), FloorsConfig.TowerUpgradeMaxLevel))
			else default
	end
	data.TowerUpgrades = cleanTower
	-- Ameliorations du joueur (2026-11-20) : seulement les cles connues, entiers entre 1 et leur maximum.
	-- Champ ajoute sans migration : Reconcile le pose pour les anciens profils (niveaux 1).
	local playerUps: any = data.PlayerUpgrades
	local cleanPlayerUps: { [string]: number } = {}
	for _, upgrade in PlayerUpgrades.List do
		local level = if type(playerUps) == "table" then playerUps[upgrade.id] else nil
		cleanPlayerUps[upgrade.id] = if isFiniteNumber(level)
			then math.max(1, math.min(math.floor(level), upgrade.maxLevel))
			else 1
	end
	data.PlayerUpgrades = cleanPlayerUps
	if type(data.DiscoveredFruits) ~= "table" then
		warn(`[DataService] DiscoveredFruits invalide pour {player.UserId}, remis par defaut`)
		data.DiscoveredFruits = {}
	end
	-- Ne garde que des fruits connus marques `true`
	local cleaned: { [string]: boolean } = {}
	for id, discovered in data.DiscoveredFruits :: { [any]: any } do
		if type(id) == "string" and Fruits.ById[id] ~= nil and discovered == true then
			cleaned[id] = true
		end
	end
	cleaned[FIRST_FRUIT_ID] = true
	data.DiscoveredFruits = cleaned
	-- Recompenses de l'Index : seulement des fruits connus ET decouverts, marques `true`
	local claimed: any = data.ClaimedFruits
	local cleanClaimed: { [string]: boolean } = {}
	if type(claimed) == "table" then
		for id, value in claimed do
			if type(id) == "string" and cleaned[id] and value == true then
				cleanClaimed[id] = true
			end
		end
	end
	data.ClaimedFruits = cleanClaimed
	-- Reglages : seulement les cles connues, du type de la valeur par defaut (sinon la defaut).
	-- Volumes (nombre 0..1) : un ancien interrupteur (booleen, avant le 2026-11-23) devient 0 ou la defaut.
	local settings: any = data.Settings
	local cleanSettings: { [string]: boolean | number } = {}
	for key, default in GameConfig.DefaultSettings do
		local value = if type(settings) == "table" then settings[key] else nil
		if type(default) == "number" then
			if type(value) == "number" and value == value then
				cleanSettings[key] = math.clamp(value, 0, 1)
			elseif value == false then
				cleanSettings[key] = 0
			else
				cleanSettings[key] = default
			end
		else
			cleanSettings[key] = if type(value) == "boolean" then value else default
		end
	end
	data.Settings = cleanSettings
	-- Statistiques des classements (LeaderboardService) : entiers >= 0
	local raw: any = data
	for _, key in { "JuicesSold", "TimePlayed" } do
		local value: any = raw[key]
		raw[key] = if isFiniteNumber(value) and value > 0 then math.min(math.floor(value), GameConfig.MaxMoney) else 0
	end
	-- Arbres gardes pour Rebirth Master (RebirthService) : liste sans trou de 0 a MaxFloors niveaux,
	-- chacun entre le niveau de depart de l'arbre et son maximum
	local kept: any = raw.KeptTrees
	local cleanKept: { number } = {}
	local treeStart = Upgrades.ById.Tree.startLevel
	local treeMax = Upgrades.GetMaxLevel("Tree", data.Rebirths)
	for n = 1, FloorsConfig.MaxFloors do
		local level = if type(kept) == "table" then kept[n] else nil
		if not isFiniteNumber(level) then
			break
		end
		table.insert(cleanKept, math.max(treeStart, math.min(math.floor(level), treeMax)))
	end
	data.KeptTrees = cleanKept
	-- Achats Robux deja appliques : seulement des chaines, les PURCHASE_ID_CACHE plus recents
	local ids: any = raw.PurchaseIds
	local cleanIds: { string } = {}
	if type(ids) == "table" then
		for _, id in ids do
			if type(id) == "string" and #cleanIds < PURCHASE_ID_CACHE then
				table.insert(cleanIds, id)
			end
		end
	end
	data.PurchaseIds = cleanIds
	-- Boosts Robux : stats connues, cles "x<entier 2..100>", secondes > 0 plafonnees (RobuxShopService)
	local boosts: any = raw.Boosts
	local cleanBoosts: { [string]: { [string]: number } } = {}
	for _, stat in Shop.BoostStats do
		local tiers = if type(boosts) == "table" then boosts[stat] else nil
		if type(tiers) == "table" then
			local cleanTiers: { [string]: number } = {}
			for key, seconds in tiers do
				local mult = if type(key) == "string" then tonumber(string.match(key, "^x(%d+)$")) else nil
				if mult and mult >= 2 and mult <= 100 and isFiniteNumber(seconds) and seconds > 0 then
					cleanTiers[key] = math.min(seconds, Shop.BoostMaxSeconds)
				end
			end
			if next(cleanTiers) ~= nil then
				cleanBoosts[stat] = cleanTiers
			end
		end
	end
	data.Boosts = cleanBoosts
	-- Offres uniques achetees : seulement des cles d'offres connues, valeur true
	local bought: any = raw.BoughtOffers
	local cleanBought: { [string]: boolean } = {}
	local offerKeys: { [string]: boolean } = { [Shop.LimitedOffers.FirstOffer.key] = true }
	for _, offer in Shop.LimitedOffers.Pool do
		offerKeys[offer.key] = true
	end
	if type(bought) == "table" then
		for key, value in bought do
			if type(key) == "string" and offerKeys[key] and value == true then
				cleanBought[key] = true
			end
		end
	end
	data.BoughtOffers = cleanBought
	-- Passes offerts : seulement des cles de passes connues, valeur true
	local giftedRaw: any = raw.GiftedPasses
	local cleanGifted: { [string]: boolean } = {}
	local passKeys: { [string]: boolean } = {}
	for _, pass in Shop.Passes do
		passKeys[pass.key] = true
	end
	if type(giftedRaw) == "table" then
		for key, value in giftedRaw do
			if type(key) == "string" and passKeys[key] and value == true then
				cleanGifted[key] = true
			end
		end
	end
	data.GiftedPasses = cleanGifted
	-- Heure de depart : seconde entiere >= 0, jamais dans le futur (horloge d'un serveur en avance)
	local logout: any = raw.LastLogout
	data.LastLogout = if isFiniteNumber(logout) and logout > 0 then math.min(math.floor(logout), os.time()) else 0
	-- Offre de gains hors ligne : montant entier entre 0 et MaxMoney, sinon "rien a prendre"
	local reward: any = raw.OfflineReward
	local amount = if type(reward) == "table" then reward.Amount else nil
	if type(reward) == "table" and isFiniteNumber(amount) and amount >= 0 then
		local seconds = reward.Seconds
		data.OfflineReward = {
			Amount = math.min(math.floor(amount), GameConfig.MaxMoney),
			Seconds = if isFiniteNumber(seconds) and seconds > 0 then math.floor(seconds) else 0,
			Claimed = reward.Claimed ~= false,
			Doubled = reward.Doubled ~= false,
		}
	else
		data.OfflineReward = { Amount = 0, Seconds = 0, Claimed = true, Doubled = true }
	end
	-- Jetons Keep Cash : entier 0..MaxRebirths (valeur abimee -> 0)
	local tokens: any = raw.KeepCashTokens
	data.KeepCashTokens = if isFiniteNumber(tokens) and tokens > 0
		then math.min(math.floor(tokens), GameConfig.MaxRebirths)
		else 0
	-- Tutoriel : entier 0..Done (valeur abimee -> Done) ; vitesse gratuite : booleen (abime -> deja prise)
	local tutorialStep: any = raw.TutorialStep
	data.TutorialStep = if isFiniteNumber(tutorialStep)
		then math.clamp(math.floor(tutorialStep), 0, TutorialConfig.Done)
		else TutorialConfig.Done
	if type(raw.FreeSpeedUsed) ~= "boolean" then
		data.FreeSpeedUsed = true
	end
	-- Cinematique d'ouverture (IntroService) : booleen ; valeur abimee -> deja vue (jamais rejouee par erreur)
	if type(raw.IntroSeen) ~= "boolean" then
		data.IntroSeen = true
	end
	-- Usine a construire : entier 0..Done ; valeur abimee -> Done (jamais d'usine videe par erreur).
	-- Plus d'un etage ou un rebirth : l'usine de l'etage 1 est forcement construite.
	local setup: any = raw.Setup
	if not isFiniteNumber(setup) then
		setup = SetupConfig.Done
	end
	setup = math.max(0, math.min(math.floor(setup), SetupConfig.Done))
	if #data.Floors > 1 or data.Rebirths > 0 then
		setup = SetupConfig.Done
	end
	data.Setup = setup
end

local function runLoadedCallbacks(player: Player, data: PlayerData)
	for _, callback in loadedCallbacks do
		task.spawn(function()
			local ok, err = pcall(callback, player, data)
			if not ok then
				warn(`[DataService] Erreur dans un OnPlayerLoaded : {err}`)
			end
		end)
	end
end

-- Retire le joueur des tables et previent les autres services (une seule fois par session).
-- Renvoie le profil s'il etait encore actif ici.
local function detachPlayer(player: Player): Profile?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	for _, callback in removingCallbacks do
		local ok, err = pcall(callback, player)
		if not ok then
			warn(`[DataService] Erreur dans un OnPlayerRemoving : {err}`)
		end
	end
	profiles[player] = nil
	firstVisit[player] = nil
	previousLogout[player] = nil
	if resetOnLeave[player] then
		resetOnLeave[player] = nil
		-- Vide la table (sans la remplacer) et remet un profil neuf, juste avant la derniere sauvegarde
		local data = profile.Data :: any
		table.clear(data)
		for key, value in TEMPLATE :: any do
			data[key] = deepCopy(value)
		end
	end
	local replacement = replaceOnLeave[player]
	if replacement then
		replaceOnLeave[player] = nil
		local data = profile.Data :: any
		table.clear(data)
		for key, value in replacement do
			data[key] = deepCopy(value)
		end
	end
	return profile
end

local function loadPlayer(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	local startedAt = os.clock()
	-- Note : en mode Mock, ProfileStore ignore `Cancel` (pas d'attente possible dans ce mode).
	local ok, result = pcall(function()
		return store:StartSessionAsync(`player_{player.UserId}`, {
			Cancel = function(): boolean
				return not player:IsDescendantOf(Players)
					or ProfileStore.IsClosing
					or os.clock() - startedAt > GameConfig.LoadTimeoutSeconds
			end,
		})
	end)
	-- Le joueur peut etre parti pendant le chargement (PlayerRemoving a deja efface `loading`)
	local stillWanted = loading[player] == true and player:IsDescendantOf(Players)
	loading[player] = nil

	local profile: Profile? = if ok then result else nil
	if not ok then
		warn(`[DataService] StartSessionAsync a echoue pour {player.UserId} : {result}`)
	end
	if profile == nil then
		-- Jamais de profil vide a la place d'un profil qu'on n'a pas pu lire.
		if player:IsDescendantOf(Players) then
			player:Kick("Your data could not be loaded. Please rejoin.")
		end
		return
	end
	local activeProfile = profile :: Profile

	if not stillWanted or not player:IsDescendantOf(Players) then
		activeProfile:EndSession()
		return
	end

	local prepared, err = pcall(function()
		activeProfile:AddUserId(player.UserId)
		activeProfile:Reconcile()
		migrate(player, activeProfile.Data)
		sanitize(player, activeProfile.Data)
	end)
	if not prepared then
		-- Sauvegarde illisible : on ferme la session sans jouer avec, pour ne rien ecraser de plus.
		warn(`[DataService] Sauvegarde invalide pour {player.UserId} : {err}`)
		activeProfile:EndSession()
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end

	-- Heure de depart : a chaque sauvegarde (auto ~ toutes les 5 min, et la derniere). Si le serveur
	-- plante, l'absence comptee part de la derniere sauvegarde, pas de la session d'avant.
	previousLogout[player] = activeProfile.Data.LastLogout
	activeProfile.OnSave:Connect(function()
		activeProfile.Data.LastLogout = os.time()
	end)
	activeProfile.OnLastSave:Connect(function()
		activeProfile.Data.LastLogout = os.time()
	end)
	activeProfile.OnSessionEnd:Connect(function()
		-- Session terminee ailleurs (fermeture du serveur, autre serveur) : nettoyer ici aussi.
		local wasActive = detachPlayer(player) ~= nil
		if wasActive and player:IsDescendantOf(Players) and not ProfileStore.IsClosing then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)

	profiles[player] = activeProfile
	-- Premiere visite = premier chargement de ce profil (en mode Mock : chaque session).
	firstVisit[player] = activeProfile.SessionLoadCount <= 1
	runLoadedCallbacks(player, activeProfile.Data)
end

local function releasePlayer(player: Player)
	local profile = detachPlayer(player)
	if profile == nil then
		return
	end
	profile.Data.LastLogout = os.time()
	profile:EndSession()
end

-- En Studio, verifie soi-meme l'acces API (en plus du test de ProfileStore, qui ne cherche que
-- certains textes d'erreur) : sans acces, on utilise le mode Mock, qui n'ecrit jamais rien.
local function studioHasApiAccess(): boolean
	local ok = pcall(function()
		DataStoreService:GetDataStore("____ApiProbe"):GetAsync("probe")
	end)
	return ok
end

function DataService:Init() end

function DataService:Start()
	-- Le test d'acces API attend une reponse : il est fait ici, pas dans Init.
	local real = ProfileStore.New(GameConfig.DataStoreName, TEMPLATE)
	if RunService:IsStudio() and not studioHasApiAccess() then
		store = real.Mock
		savingEnabled = false
		warn(
			"[DataService] DataStore indisponible (Studio sans acces API) : sauvegarde desactivee pour"
				.. " cette session. Activer Game Settings > Security > Enable Studio Access to API Services."
		)
	else
		store = real
		savingEnabled = true
	end

	ProfileStore.OnError:Connect(function(message: string, storeName: string, key: string)
		warn(`[DataService] Erreur DataStore ({storeName} / {key}) : {message}`)
	end)

	Players.PlayerAdded:Connect(function(player)
		loadPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		loading[player] = nil
		releasePlayer(player)
		resetOnLeave[player] = nil
		replaceOnLeave[player] = nil
	end)
	-- Joueurs deja presents avant la connexion (Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
end

-- Donnees du joueur si sa session est ouverte, sinon nil. Ne pas garder la table apres un yield
-- sans revalider (le joueur peut partir).
function DataService.GetData(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Ameliorations d'un etage (nil si l'etage n'est pas achete). Le seul acces aux niveaux : ne jamais
-- lire data.Floors[n] directement ailleurs.
function DataService.FloorUpgrades(data: PlayerData, floorIndex: number): { [string]: number }?
	local floor = data.Floors[floorIndex]
	return if floor then floor.Upgrades else nil
end

-- Nombre d'etages achetes (1..MaxFloors).
function DataService.FloorsOwned(data: PlayerData): number
	return #data.Floors
end

-- Data.LastLogout tel qu'il etait au chargement (0 = jamais parti / premiere visite). Gains hors ligne.
function DataService.GetPreviousLogout(player: Player): number
	return previousLogout[player] or 0
end

function DataService.IsFirstVisit(player: Player): boolean
	return firstVisit[player] == true
end

-- Vrai si les donnees sont vraiment ecrites dans le DataStore (faux en Studio sans acces API).
function DataService.IsSavingEnabled(): boolean
	return savingEnabled
end

-- Appele quand la sauvegarde d'un joueur est chargee (aussi pour ceux deja charges).
function DataService.OnPlayerLoaded(callback: (Player, PlayerData) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
end

-- Remise a zero complete (panneau admin) : la sauvegarde redevient celle d'un nouveau joueur au
-- moment ou il quitte (l'appelant le kick juste apres). Rien n'est garde, intro comprise.
function DataService.ResetOnLeave(player: Player): boolean
	if profiles[player] == nil then
		return false
	end
	resetOnLeave[player] = true
	return true
end

-- Tests Studio (DebugService, "Data RestoreBackup") : la sauvegarde est remplacee par `snapshot`
-- au moment ou le joueur quitte (juste avant la derniere sauvegarde), comme ResetOnLeave.
function DataService.ReplaceOnLeave(player: Player, snapshot: { [string]: any }): boolean
	if profiles[player] == nil or type(snapshot) ~= "table" then
		return false
	end
	replaceOnLeave[player] = deepCopy(snapshot)
	return true
end

-- Appele au depart du joueur, AVANT la derniere sauvegarde (dernieres ecritures, nettoyage).
function DataService.OnPlayerRemoving(callback: (Player) -> ())
	table.insert(removingCallbacks, callback)
end

-- Achat Robux (Developer Product, appele par un handler de ReceiptService) : applique `apply` UNE
-- seule fois par PurchaseId (memorise dans Data.PurchaseIds), puis attend que la sauvegarde qui
-- contient cet achat soit ecrite dans le DataStore. Renvoie true seulement dans ce cas (ou en
-- Studio sans acces API, ou rien n'est jamais ecrit) : le handler renvoie alors true a Roblox.
-- `apply(data)` ne doit pas attendre (pas de yield) et renvoie false pour refuser (rien n'est note).
-- Peut attendre (sauvegarde) : a appeler seulement depuis ProcessReceipt.
-- Methode de l'exemple officiel de ProfileStore (PurchaseIdCache + OnAfterSave).
function DataService.GrantPurchaseOnce(player: Player, purchaseId: string, apply: (PlayerData) -> boolean): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() or type(purchaseId) ~= "string" then
		return false
	end
	local ids = profile.Data.PurchaseIds
	if table.find(ids, purchaseId) == nil then
		if apply(profile.Data) ~= true then
			return false
		end
		table.insert(ids, 1, purchaseId)
		while #ids > PURCHASE_ID_CACHE do
			table.remove(ids)
		end
	end
	if not savingEnabled then
		return true
	end
	local function isSaved(): boolean
		local saved: any = profile.LastSavedData
		local list = if type(saved) == "table" then saved.PurchaseIds else nil
		return type(list) == "table" and table.find(list, purchaseId) ~= nil
	end
	if isSaved() then
		return true
	end
	profile:Save()
	while profile:IsActive() do
		profile.OnAfterSave:Wait()
		if isSaved() then
			return true
		end
	end
	return isSaved()
end

return DataService
