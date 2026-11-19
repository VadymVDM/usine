--!strict
-- Sauvegarde des joueurs avec ProfileStore (verrou de session, sauvegarde auto, BindToClose).
-- Seul module qui ouvre/ferme les sessions. Chaque champ a un seul proprietaire qui le modifie
-- (Money -> MoneyService, Upgrades -> UpgradeService, DiscoveredFruits -> TreeService).
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

-- Premier fruit (toujours decouvert) : pris dans la Config, jamais ecrit en dur
local FIRST_FRUIT_ID: string = Fruits.List[1].id

export type PlayerData = {
	SchemaVersion: number,
	Money: number,
	Rebirths: number,
	Upgrades: { [string]: number },
	DiscoveredFruits: { [string]: boolean },
	LastLogout: number,
	IntroSeen: boolean,
}

type Profile = {
	Data: PlayerData,
	SessionLoadCount: number,
	OnSessionEnd: any,
	OnLastSave: any,
	AddUserId: (Profile, number) -> (),
	Reconcile: (Profile) -> (),
	EndSession: (Profile) -> (),
	IsActive: (Profile) -> boolean,
}

local TEMPLATE: PlayerData = {
	SchemaVersion = GameConfig.SchemaVersion,
	Money = GameConfig.StartingMoney,
	Rebirths = 0,
	Upgrades = Upgrades.DefaultLevels(),
	DiscoveredFruits = { [FIRST_FRUIT_ID] = true },
	LastLogout = 0,
	IntroSeen = false,
}

local DataService = {}

local store: any = nil
local savingEnabled = false
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local firstVisit: { [Player]: boolean } = {}
local loadedCallbacks: { (Player, PlayerData) -> () } = {}
local removingCallbacks: { (Player) -> () } = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Migrations : une etape par version. Le modele (Reconcile) ajoute deja les champs absents.
local MIGRATIONS: { [number]: (PlayerData) -> () } = {
	-- [1] = function(data) ... end, -- exemple : passage de la version 1 a la version 2
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
	if type(data.Upgrades) ~= "table" then
		warn(`[DataService] Upgrades invalide pour {player.UserId}, remis par defaut`)
		data.Upgrades = Upgrades.DefaultLevels()
	end
	for _, upgrade in Upgrades.List do
		local level: any = data.Upgrades[upgrade.id]
		local maxLevel = Upgrades.GetMaxLevel(upgrade.id, data.Rebirths)
		if not isFiniteNumber(level) then
			level = upgrade.startLevel
		end
		-- Pas de math.clamp : il plante si la Config donne un max < niveau de depart.
		data.Upgrades[upgrade.id] = math.max(upgrade.startLevel, math.min(math.floor(level), maxLevel))
	end
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

-- Appele au depart du joueur, AVANT la derniere sauvegarde (dernieres ecritures, nettoyage).
function DataService.OnPlayerRemoving(callback: (Player) -> ())
	table.insert(removingCallbacks, callback)
end

return DataService
