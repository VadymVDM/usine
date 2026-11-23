--!strict
-- Outil de test, actif SEULEMENT dans Studio : permet aux tests (MCP, barre de commande) d'appeler
-- les vrais services du jeu. Un require depuis la barre de commande cree une copie separee des
-- modules : on passe donc par un BindableFunction serveur (invisible pour les clients).
-- Usage (serveur, en playtest) :
--   game.ServerStorage.Debug.Call:Invoke("Money", "Add", "<NomJoueur>", 100)
--   game.ServerStorage.Debug.Call:Invoke("Base", "SimulateFull", "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("Tree", "Drop", "<NomJoueur>", 5)
--   game.ServerStorage.Debug.Call:Invoke("Tree", "SetLevel", "<NomJoueur>", niveau)
--   game.ServerStorage.Debug.Call:Invoke("Production", "Get", "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("Production", "Do", "<NomJoueur>", "PickAll" | "Shelf" | "TakeJuice" | "Blend1".."Blend4" | "FillBins")
--   game.ServerStorage.Debug.Call:Invoke("Customer", "Get", "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("Customer", "Do", "<NomJoueur>", "Place" | "CashPad" | "Collect" | "AddCash" | "SetAutoCollect", valeur)
--   game.ServerStorage.Debug.Call:Invoke("Upgrade", "Buy", "<NomJoueur>", "Tree")
--   game.ServerStorage.Debug.Call:Invoke("Upgrade", "SetLevel", "<NomJoueur>", "Blender2", 0)
--   game.ServerStorage.Debug.Call:Invoke("Upgrade", "Reset", "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("Floor", "Get" | "Set" n | "GoTo" n, "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("Rebirth", "Get" | "Do" [keepCash] | "Set" n | "Master" bool, "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("LuckyCash", "Get" | "Grant", "<NomJoueur>") (Grant = simule un achat Robux paye)
--   game.ServerStorage.Debug.Call:Invoke("Shop", "Get" | "ClearBoosts" | "ClearOffers", "<NomJoueur>")
--   game.ServerStorage.Debug.Call:Invoke("Shop", "FreeBoost", "<NomJoueur>", 0) -- boost gratuit tout de suite
--   game.ServerStorage.Debug.Call:Invoke("Shop", "Grant", "<NomJoueur>", "Boost" | "CashPack" | "Offer", "Money_15" | "Cash5m" | "OfferStarter", purchaseId?) (recu simule)
--   game.ServerStorage.Debug.Call:Invoke("Shop", "Pass", "<NomJoueur>", "Cash3x", true)
--   game.ServerStorage.Debug.Call:Invoke("Gift", "Send", "<NomJoueur>", "VIP", <UserId ou 0>, "id") | "Get" | "Remove", "VIP"
--   game.ServerStorage.Debug.Call:Invoke("Offline", "Get" | "Simulate" secondes | "Double", "<NomJoueur>") (gains hors ligne ; Simulate / Double ecrivent la sauvegarde)
--   game.ServerStorage.Debug.Call:Invoke("Data", "SetTower", "<NomJoueur>", "ElevatorSpeed", 0)
--   game.ServerStorage.Debug.Call:Invoke("Data", "SetDiscovered", "<NomJoueur>", { "Apple", ... })
--   game.ServerStorage.Debug.Call:Invoke("Data", "Snapshot" | "Restore", "<NomJoueur>") (avant / apres un test de rebirth)
--   game.ServerStorage.Debug.Call:Invoke("Data", "Backup", "<NomJoueur>") (copie du profil dans le DataStore
--     "DebugBackups", garde entre les playtests ; renvoie aussi le JSON)
--   game.ServerStorage.Debug.Call:Invoke("Data", "ResetOnLeave" | "RestoreBackup", "<NomJoueur>") (profil
--     neuf / copie "Backup" remis au DEPART du joueur : arreter le playtest juste apres)
--   game.ServerStorage.Debug.Call:Invoke("Tutorial", "Get" | "Set", "<NomJoueur>", n) (etape du tutoriel, ECRIT la sauvegarde)
--   game.ServerStorage.Debug.Call:Invoke("Setup", "Get" | "Set" n, "<NomJoueur>") (usine a construire,
--     etape 0..4 ; Set ecrit la sauvegarde)
-- Les actions par etage (Tree, Production, Customer, Upgrade) visent l'etage ou se trouve le joueur.
-- Doc : docs/systems/argent.md (section Tests)

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Upgrades"))

local BaseService = require(script.Parent.BaseService)
local IndexService = require(script.Parent.IndexService)
local DataService = require(script.Parent.DataService)
local FloorService = require(script.Parent.FloorService)
local MoneyService = require(script.Parent.MoneyService)
local CustomerService = require(script.Parent.CustomerService)
local ProductionService = require(script.Parent.ProductionService)
local LuckyCashService = require(script.Parent.LuckyCashService)
local RobuxShopService = require(script.Parent.RobuxShopService)
local GiftService = require(script.Parent.GiftService)
local OfflineService = require(script.Parent.OfflineService)
local RebirthService = require(script.Parent.RebirthService)
local TreeService = require(script.Parent.TreeService)
local UpgradeService = require(script.Parent.UpgradeService)
local SetupService = require(script.Parent.SetupService)
local TutorialService = require(script.Parent.TutorialService)

local BACKUP_STORE = "DebugBackups" -- Studio seulement (DebugService n'existe pas en jeu publie)

local DebugService = {}

-- Photos de progression (Data.Snapshot / Data.Restore), par UserId
local snapshots: { [number]: any } = {}

-- Ameliorations de l'etage ou se trouve le joueur (etage 1 par defaut).
local function hereLevels(player: Player): { [string]: number }?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local _, index = FloorService.GetPlayerFloor(player)
	return DataService.FloorUpgrades(data, index or 1)
end

type Handler = (player: Player, ...any) -> any

local handlers: { [string]: { [string]: Handler } } = {
	Money = {
		Add = function(player, amount)
			return MoneyService.Add(player, amount, "debug")
		end,
		TrySpend = function(player, amount)
			return MoneyService.TrySpend(player, amount, "debug")
		end,
		Get = function(player)
			return MoneyService.Get(player)
		end,
	},
	Base = {
		Get = function(player)
			local base = BaseService.GetBase(player)
			return if base then base.Name else nil
		end,
		-- Simule un serveur plein (7e joueur) puis revient a la normale
		SimulateFull = function(player)
			return BaseService.DebugSimulateFull(player)
		end,
		EndSimulation = function(player)
			return BaseService.DebugEndSimulation(player)
		end,
	},
	Tree = {
		-- Fait tomber n fruits tout de suite (garantie et plafond respectes)
		Drop = function(player, count)
			return TreeService.DebugDrop(player, if type(count) == "number" then count else 1)
		end,
		-- Change le niveau de l'arbre (ecrit la sauvegarde !). L'arbre change au tour suivant.
		SetLevel = function(player, level)
			local data = DataService.GetData(player)
			local levels = hereLevels(player)
			if data == nil or levels == nil or type(level) ~= "number" then
				return false
			end
			levels.Tree = math.clamp(math.floor(level), 1, Upgrades.GetMaxLevel("Tree", data.Rebirths))
			return true
		end,
	},
	Production = {
		Get = function(player)
			return ProductionService.DebugGet(player)
		end,
		-- Actions E sans la distance : "PickAll", "Shelf", "TakeJuice"
		Do = function(player, action)
			return if type(action) == "string" then ProductionService.DebugAction(player, action) else false
		end,
	},
	Customer = {
		Get = function(player)
			return CustomerService.DebugGet(player)
		end,
		-- "Place" (poser les jus portes), "AddCash" n, "Collect", "SetAutoCollect" true/false
		Do = function(player, action, value)
			return if type(action) == "string" then CustomerService.DebugAction(player, action, value) else false
		end,
	},
	Upgrade = {
		-- Achat comme un vrai clic (argent, niveau max, construction de la machine), sans la distance
		Buy = function(player, id)
			return if type(id) == "string" then UpgradeService.DebugBuy(player, id) else false
		end,
		-- Bouton violet + recu simule (ecrit la sauvegarde !) : (id ou "" = sans tuile notee, PurchaseId)
		-- -> { granted, productId, level } ; meme PurchaseId 2 fois = un seul niveau.
		RobuxBuy = function(player, id, purchaseId)
			return UpgradeService.DebugRobuxBuy(player, if type(id) == "string" then id else "", tostring(purchaseId))
		end,
		-- Met un id a un niveau precis (ecrit la sauvegarde !). Ex. ("Blender2", 0) pour annuler un test.
		-- Le modele (fantome / construit) se met a jour a la prochaine arrivee dans la base.
		SetLevel = function(player, id, level)
			local data = DataService.GetData(player)
			local levels = hereLevels(player)
			local upgrade = if type(id) == "string" then Upgrades.ById[id] else nil
			if data == nil or levels == nil or upgrade == nil or type(level) ~= "number" then
				return false
			end
			local maxLevel = Upgrades.GetMaxLevel(id, data.Rebirths)
			levels[id] = math.max(upgrade.startLevel, math.min(math.floor(level), maxLevel))
			return true
		end,
		-- Remet les ameliorations de l'etage ou est le joueur au niveau de depart (ecrit la sauvegarde !)
		Reset = function(player)
			local levels = hereLevels(player)
			if levels == nil then
				return false
			end
			for id, level in Upgrades.DefaultLevels() do
				levels[id] = level
			end
			return true
		end,
	},
	Floor = {
		-- Etat de la tour (etages, etage ferme, etage ou est le joueur)
		Get = function(player)
			return FloorService.DebugGet(player)
		end,
		-- Met la tour a n etages (ecrit la sauvegarde ! les etages retires sont perdus)
		Set = function(player, count)
			return if type(count) == "number" then FloorService.SetFloorCount(player, count) else false
		end,
		-- Teleporte a l'etage n (sans delai)
		GoTo = function(player, n)
			return if type(n) == "number" then FloorService.DebugGoTo(player, n) else false
		end,
	},
	Gift = {
		-- Recu simule d'un cadeau : ("<Pass>", destinataire UserId ou 0 = sans destinataire note, PurchaseId)
		Send = function(player, key, recipientId, purchaseId)
			if type(key) ~= "string" then
				return false
			end
			return GiftService.DebugGift(player, key, if type(recipientId) == "number" then recipientId else 0, tostring(purchaseId))
		end,
		Get = function(player)
			return GiftService.DebugGet(player)
		end,
		-- Retire un pass offert de la sauvegarde (ecrit la sauvegarde !)
		Remove = function(player, key)
			return if type(key) == "string" then GiftService.DebugRemove(player, key) else false
		end,
	},
	Shop = {
		Get = function(player)
			return RobuxShopService.DebugGet(player)
		end,
		Grant = function(player, kind, key, purchaseId)
			return RobuxShopService.DebugGrant(player, kind, key, purchaseId)
		end,
		Pass = function(player, key, owned)
			return RobuxShopService.DebugSetPass(player, key, owned == true)
		end,
		ClearBoosts = function(player)
			return RobuxShopService.DebugClearBoosts(player)
		end,
		ClearOffers = function(player)
			return RobuxShopService.DebugClearOffers(player)
		end,
		-- Boost gratuit dans X s (Shop.FreeBoost) ; renvoie l'ancien delai
		FreeBoost = function(player, seconds)
			return RobuxShopService.DebugFreeBoost(player, if type(seconds) == "number" then seconds else 0)
		end,
	},
	LuckyCash = {
		-- Montant offert maintenant
		Get = function(player)
			return LuckyCashService.GetAmount(player)
		end,
		-- Simule un achat paye (ecrit la sauvegarde !)
		Grant = function(player)
			return LuckyCashService.DebugGrant(player)
		end,
	},
	Offline = {
		-- Offre sauvegardee, argent/s, absence de la session
		Get = function(player)
			return OfflineService.DebugGet(player)
		end,
		-- Simule une absence de n secondes et montre l'ecran (ecrit la sauvegarde !)
		Simulate = function(player, seconds)
			return if type(seconds) == "number" then OfflineService.DebugSimulate(player, seconds) else nil
		end,
		-- Simule un achat x2 paye (ecrit la sauvegarde !)
		Double = function(player)
			return OfflineService.DebugDouble(player)
		end,
	},
	Rebirth = {
		-- Rebirths, multiplicateur, prix, arbres gardes, pass Rebirth Master
		Get = function(player)
			return RebirthService.DebugGet(player)
		end,
		-- Rebirth gratuit sans conditions (ecrit la sauvegarde !) ; keepCash = true : garde l'argent
		Do = function(player, keepCash)
			return RebirthService.ForceRebirth(player, keepCash == true)
		end,
		-- Met le nombre de rebirths a n (la tour ne change pas)
		Set = function(player, n)
			return if type(n) == "number" then RebirthService.DebugSet(player, n) else false
		end,
		-- Donne / retire le pass Rebirth Master (attribut, pas de vrai pass)
		Master = function(player, owned)
			return RebirthService.DebugSetMaster(player, owned == true)
		end,
	},
	Data = {
		-- Remet une sauvegarde de test (ecrit la sauvegarde !) : niveaux de la tour, fruits decouverts
		SetTower = function(player, id, level)
			local data = DataService.GetData(player)
			if data == nil or type(id) ~= "string" or data.TowerUpgrades[id] == nil or type(level) ~= "number" then
				return false
			end
			data.TowerUpgrades[id] = math.max(0, math.floor(level))
			return true
		end,
		SetDiscovered = function(player, ids)
			local data = DataService.GetData(player)
			if data == nil or type(ids) ~= "table" then
				return false
			end
			table.clear(data.DiscoveredFruits)
			for _, id in ids do
				if type(id) == "string" then
					data.DiscoveredFruits[id] = true
				end
			end
			-- Recompenses prises : on oublie celles des fruits retires
			for id in data.ClaimedFruits do
				if not data.DiscoveredFruits[id] then
					data.ClaimedFruits[id] = nil
				end
			end
			IndexService.Sync(player)
			return true
		end,
		-- Photo de la progression (argent, rebirths, etages, ascenseur, arbres gardes) pour la remettre
		-- apres un test qui la detruit (rebirth) : Snapshot avant, Restore apres. En memoire seulement.
		Snapshot = function(player)
			local data = DataService.GetData(player)
			if data == nil then
				return false
			end
			local floors = {}
			for _, floor in data.Floors do
				table.insert(floors, { Upgrades = table.clone(floor.Upgrades) })
			end
			snapshots[player.UserId] = {
				Money = data.Money,
				Rebirths = data.Rebirths,
				Floors = floors,
				TowerUpgrades = table.clone(data.TowerUpgrades),
				KeptTrees = table.clone(data.KeptTrees),
			}
			return true
		end,
		Restore = function(player)
			local data = DataService.GetData(player)
			local snap = snapshots[player.UserId]
			if data == nil or snap == nil then
				return false
			end
			-- Copies : la photo reste intacte (on peut la remettre plusieurs fois)
			local floors = {}
			for _, floor in snap.Floors do
				table.insert(floors, { Upgrades = table.clone(floor.Upgrades) })
			end
			data.Floors = floors
			data.TowerUpgrades = table.clone(snap.TowerUpgrades)
			data.KeptTrees = table.clone(snap.KeptTrees)
			data.Rebirths = snap.Rebirths
			local missing = snap.Money - data.Money
			if missing > 0 then
				MoneyService.Add(player, missing, "debug")
			elseif missing < 0 then
				MoneyService.TrySpend(player, -missing, "debug")
			end
			RebirthService.DebugSet(player, snap.Rebirths)
			-- Reconstruit la tour avec les etages remis (meme nombre : rien n'est ajoute ni retire)
			return FloorService.SetFloorCount(player, #snap.Floors)
		end,
		-- Copie du profil gardee entre deux playtests (avant un test "profil neuf")
		Backup = function(player)
			local data = DataService.GetData(player)
			if data == nil then
				return false
			end
			local json = HttpService:JSONEncode(data)
			DataStoreService:GetDataStore(BACKUP_STORE):SetAsync(`player_{player.UserId}`, json)
			return json
		end,
		RestoreBackup = function(player)
			local json = DataStoreService:GetDataStore(BACKUP_STORE):GetAsync(`player_{player.UserId}`)
			if type(json) ~= "string" then
				return "no backup"
			end
			return DataService.ReplaceOnLeave(player, HttpService:JSONDecode(json))
		end,
		ResetOnLeave = function(player)
			return DataService.ResetOnLeave(player)
		end,
		Get = function(player)
			local data = DataService.GetData(player)
			if data == nil then
				return nil
			end
			return {
				Money = data.Money,
				Rebirths = data.Rebirths,
				Upgrades = table.clone(hereLevels(player) or {}),
				FloorsOwned = DataService.FloorsOwned(data),
				TowerUpgrades = table.clone(data.TowerUpgrades),
				DiscoveredFruits = table.clone(data.DiscoveredFruits),
				FirstVisit = DataService.IsFirstVisit(player),
				SavingEnabled = DataService.IsSavingEnabled(),
				Setup = (data :: any).Setup,
			}
		end,
	},
	Setup = {
		Get = function(player)
			return SetupService.PlayerStep(player)
		end,
		Set = function(player, n)
			return type(n) == "number" and SetupService.DebugSet(player, n)
		end,
	},
	-- Tutoriel (TutorialService) : etape sauvegardee
	Tutorial = {
		Get = function(player)
			return player:GetAttribute("TutorialStep")
		end,
		Set = function(player, n)
			return type(n) == "number" and TutorialService.DebugSet(player, n)
		end,
	},
}

function DebugService:Init()
	if not RunService:IsStudio() then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Debug"
	local call = Instance.new("BindableFunction")
	call.Name = "Call"
	call.OnInvoke = function(system: string, action: string, playerName: string, ...: any): any
		local group = handlers[system]
		local handler = group and group[action]
		local player = Players:FindFirstChild(playerName)
		if handler == nil or player == nil or not player:IsA("Player") then
			return "unknown system/action/player"
		end
		return handler(player, ...)
	end
	call.Parent = folder
	folder.Parent = ServerStorage
end

return DebugService
