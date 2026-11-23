--!strict
-- Rebirth (phase 4, 2026-11-20). Seul module qui modifie Data.Rebirths et Data.KeptTrees.
--   * Remote RebirthRequest (menu Rebirth, RebirthController) :
--       - "Rebirth" : sauvegarde chargee, Config/Rebirth.RequiredFloors etages, joueur pres de la
--         machine doree de SA salle du Rebirth (ReachDistance), delai RequestCooldown ; le tas
--         d'argent de l'etage 1 est d'abord encaisse ; argent >= Rebirth.Price(rebirths). Puis TOUT
--         l'argent part et le rebirth est fait.
--       - "KeepCash" : memes verifications sauf l'argent ; le serveur choisit le produit Robux du
--         palier du joueur et ouvre la fenetre d'achat (productId = 0 : "coming soon"). Le rebirth
--         est fait seulement a la reception du paiement (ReceiptService -> DataService.GrantPurchaseOnce,
--         un achat n'est jamais donne deux fois), sans payer le prix et en gardant l'argent.
--         Recu alors que le joueur n'a pas les 10 etages (fenetre ouverte par le client lui-meme) :
--         pas de rebirth, un jeton Data.KeepCashTokens est garde ; "KeepCash" avec un jeton = rebirth
--         gratuit tout de suite (memes verifications). Attribut joueur "KeepCashTokens" (affichage).
--   * Rebirth : niveaux d'arbre notes (KeptTrees, pour Rebirth Master), argent a 0 (sauf KeepCash),
--     Rebirths + 1, fruits / jus portes vides (ProductionService.ClearCarried), tour remise a 1 etage
--     et ascenseur a 0 (FloorService.ResetForRebirth), joueur ramene au depart.
--   * Gain : multiplicateur des ventes Rebirth.Multiplier(rebirths), applique par CustomerService
--     (lit Data.Rebirths : pas de require en cercle).
--   * Pass Rebirth Master (Shop.Passes "RebirthMaster", passId 0 = pas cree) : un etage neuf reprend
--     le plus haut niveau d'arbre qu'il avait avant un rebirth (FloorService.SetNewFloorLevels).
--   * Signes visibles : leaderstats.Rebirths (MoneyService), attribut joueur "Rebirths" (menu,
--     effet de fete cote client), nametag pseudo + "Rebirth N" au-dessus de la tete (Lib/NameTag, vu
--     seulement par les autres), message aux autres joueurs.
-- Doc : docs/systems/rebirth.md

local MarketplaceService = game:GetService("MarketplaceService")
local GamePass = require(script.Parent.Parent.Lib.GamePass)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Rebirth = require(Config:WaitForChild("Rebirth"))
local Shop = require(Config:WaitForChild("Shop"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local NameTag = require(script.Parent.Parent.Lib.NameTag)
local BaseService = require(script.Parent.BaseService)
local CustomerService = require(script.Parent.CustomerService)
local DataService = require(script.Parent.DataService)
local FloorService = require(script.Parent.FloorService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local ProductionService = require(script.Parent.ProductionService)
local ReceiptService = require(script.Parent.ReceiptService)

local RebirthService = {}

local REBIRTHS_ATTRIBUTE = "Rebirths" -- joueur : nombre de rebirths (lu par le client)
local MASTER_ATTRIBUTE = "RebirthMaster" -- joueur : possede le pass Rebirth Master
local TOKENS_ATTRIBUTE = "KeepCashTokens" -- joueur : Keep Cash deja payes (nil = aucun ; affichage seulement)

local masterPassId = 0
for _, pass in Shop.Passes do
	if pass.key == "RebirthMaster" then
		masterPassId = pass.passId
	end
end

local characterConnections: { [Player]: RBXScriptConnection } = {}

---------------------------------------------------------------------------------------------
-- Lecture

-- Nombre de rebirths du joueur (0 si pas charge).
function RebirthService.GetRebirths(player: Player): number
	local data = DataService.GetData(player)
	return if data then data.Rebirths else 0
end

-- Multiplicateur des ventes du joueur (1 si pas charge).
function RebirthService.GetMultiplier(player: Player): number
	return Rebirth.Multiplier(RebirthService.GetRebirths(player))
end

function RebirthService.OwnsMaster(player: Player): boolean
	return player:GetAttribute(MASTER_ATTRIBUTE) == true
end

-- Point de la machine doree dans la salle du Rebirth de la base du joueur.
local function machineAnchor(player: Player): BasePart?
	local base = BaseService.GetBase(player)
	local annex = base and base:FindFirstChild("Annex")
	local room = annex and annex:FindFirstChild("RebirthRoom")
	local anchor = room and room:FindFirstChild("PromptAnchor")
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

---------------------------------------------------------------------------------------------
-- Signes visibles

-- Nametag au-dessus de la tete : pseudo + "Rebirth N" (Lib/NameTag, vu seulement par les autres).
local function refreshTitle(player: Player)
	NameTag.Apply(player, RebirthService.GetRebirths(player))
end

-- Attribut, classement et titre a jour (chargement, rebirth).
local function syncPlayer(player: Player)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(REBIRTHS_ATTRIBUTE, RebirthService.GetRebirths(player))
	local data = DataService.GetData(player)
	player:SetAttribute(TOKENS_ATTRIBUTE, if data and data.KeepCashTokens > 0 then data.KeepCashTokens else nil)
	MoneyService.SyncLeaderstats(player)
	refreshTitle(player)
end

---------------------------------------------------------------------------------------------
-- Rebirth

-- Note le plus haut niveau d'arbre atteint par chaque etage (Rebirth Master le rend plus tard).
local function recordTrees(data: DataService.PlayerData)
	local treeStart = Upgrades.ById.Tree.startLevel
	for n = 1, DataService.FloorsOwned(data) do
		local levels = DataService.FloorUpgrades(data, n)
		local level = if levels then levels.Tree or treeStart else treeStart
		data.KeptTrees[n] = math.max(data.KeptTrees[n] or treeStart, level)
	end
end

-- Fait le rebirth (conditions deja verifiees par l'appelant). Les donnees changent d'abord, d'un
-- coup ; puis le monde (tour, mains) dans un pcall : une erreur d'affichage ne laisse pas la
-- sauvegarde a moitie faite. keepCash = achat Robux : ni prix ni argent perdu.
local function performRebirth(player: Player, data: DataService.PlayerData, keepCash: boolean)
	recordTrees(data)
	if not keepCash then
		MoneyService.TrySpend(player, MoneyService.Get(player), "Rebirth")
	end
	data.Rebirths = math.min(data.Rebirths + 1, GameConfig.MaxRebirths)
	-- La sauvegarde est faite : la suite ne doit jamais lever d'erreur (achat Robux : le recu doit
	-- etre marque comme donne, sinon Roblox le redonnerait alors que le rebirth est deja fait).
	local ok, err = pcall(function()
		ProductionService.ClearCarried(player)
		FloorService.ResetForRebirth(player)
		syncPlayer(player)
		local multiplier = Rebirth.FormatMultiplier(Rebirth.Multiplier(data.Rebirths))
		NotifyService.Notify(player, string.format(Rebirth.Messages.Done, data.Rebirths, multiplier))
		for _, other in Players:GetPlayers() do
			if other ~= player then
				NotifyService.Notify(other, string.format(Rebirth.Messages.Others, player.DisplayName, data.Rebirths))
			end
		end
	end)
	if not ok then
		warn(`[RebirthService] Erreur pendant le rebirth de {player.UserId} : {err}`)
	end
end

-- Verifications communes aux deux boutons du menu. Renvoie la sauvegarde si tout va bien.
local function checkRequest(player: Player): DataService.PlayerData?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	if DataService.FloorsOwned(data) < Rebirth.RequiredFloors or FloorService.GetOwnedCount(player) < Rebirth.RequiredFloors then
		NotifyService.Notify(player, string.format(Rebirth.Messages.NeedFloors, Rebirth.RequiredFloors), true)
		return nil
	end
	local anchor = machineAnchor(player)
	if anchor == nil or not PlayerCheck.CanReach(player, anchor.Position, Rebirth.ReachDistance) then
		NotifyService.Notify(player, Rebirth.Messages.TooFar, true)
		return nil
	end
	return data
end

local function onRebirth(player: Player)
	local data = checkRequest(player)
	if data == nil then
		return
	end
	-- L'argent du tas d'en bas compte (il est a lui) : encaisse avant de comparer au prix.
	CustomerService.CollectPile(player)
	local price = Rebirth.Price(data.Rebirths)
	if MoneyService.Get(player) < price then
		NotifyService.Notify(player, Rebirth.Messages.NotEnoughMoney, true)
		return
	end
	performRebirth(player, data, false)
end

local function onKeepCash(player: Player)
	local data = checkRequest(player)
	if data == nil then
		return
	end
	-- Keep Cash deja paye (jeton) : rebirth tout de suite, sans nouvelle fenetre d'achat
	if data.KeepCashTokens > 0 then
		data.KeepCashTokens -= 1 -- performRebirth remet l'attribut a jour (syncPlayer)
		CustomerService.CollectPile(player)
		performRebirth(player, data, true)
		return
	end
	local tier = Rebirth.KeepCashProduct(data.Rebirths)
	if tier.productId <= 0 then
		NotifyService.Notify(player, Rebirth.Messages.KeepCashSoon)
		return
	end
	PurchasePrompt.Product(player, tier.productId)
end

local function onRequest(player: Player, action: any)
	if action ~= "Rebirth" and action ~= "KeepCash" then
		return
	end
	if not PlayerCheck.Cooldown(player, "RebirthRequest", Rebirth.RequestCooldown) then
		return
	end
	if action == "Rebirth" then
		onRebirth(player)
	else
		onKeepCash(player)
	end
end

-- Recu Robux "Rebirth & keep your cash" (n'importe quel palier). Le paiement est fait : le rebirth
-- est donne meme si le joueur n'a plus ses 10 etages (rare : un autre rebirth entre l'achat et le
-- recu). Rien n'est donne deux fois (PurchaseId memorise dans la sauvegarde).
local function onKeepCashReceipt(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return false -- Roblox redonnera le recu a sa prochaine connexion
	end
	local deadline = os.clock() + Rebirth.ReceiptWaitSeconds
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	local saved = false
	local granted = DataService.GrantPurchaseOnce(player, receipt.PurchaseId, function(data: DataService.PlayerData): boolean
		-- Le client peut ouvrir lui-meme la fenetre d'achat (sans les 10 etages) : pas de rebirth
		-- gratuit des conditions, l'achat devient un jeton garde pour le prochain rebirth.
		if DataService.FloorsOwned(data) < Rebirth.RequiredFloors then
			data.KeepCashTokens = math.min(data.KeepCashTokens + 1, GameConfig.MaxRebirths)
			saved = true
			return true
		end
		-- Le tas d'argent d'en bas est garde lui aussi (achat "keep your cash")
		pcall(CustomerService.CollectPile, player)
		performRebirth(player, data, true)
		return true
	end)
	if saved then
		syncPlayer(player)
		NotifyService.Notify(player, string.format(Rebirth.Messages.KeepCashSaved, Rebirth.RequiredFloors))
	end
	return granted
end

---------------------------------------------------------------------------------------------
-- Pass Rebirth Master

local function grantMaster(player: Player)
	if player.Parent == Players then
		player:SetAttribute(MASTER_ATTRIBUTE, true)
	end
end

local function checkMasterPass(player: Player)
	if masterPassId <= 0 then
		return
	end
	local owns = GamePass.Owns(player, masterPassId) -- jamais vrai pour le createur (Lib/GamePass)
	if owns then
		grantMaster(player)
	end
end

-- Niveaux d'un etage neuf : ceux de depart ; avec Rebirth Master, l'arbre reprend son niveau garde.
local function newFloorLevels(player: Player, n: number): { [string]: number }?
	local levels = Upgrades.DefaultLevels()
	local data = DataService.GetData(player)
	if data == nil or not RebirthService.OwnsMaster(player) then
		return levels
	end
	local kept = data.KeptTrees[n]
	if kept then
		local maxLevel = Upgrades.GetMaxLevel("Tree", data.Rebirths)
		levels.Tree = math.max(levels.Tree or 1, math.min(kept, maxLevel))
	end
	return levels
end

---------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local function onCharacter(character: Model)
		character:WaitForChild("Head", 5)
		if player.Character == character then
			refreshTitle(player)
		end
	end
	characterConnections[player] = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	task.spawn(checkMasterPass, player)
end

function RebirthService:Init()
	Remotes.GetServerEvent("RebirthRequest").OnServerEvent:Connect(function(player: Player, action: any)
		local ok, err = pcall(onRequest, player, action)
		if not ok then
			warn(`[RebirthService] Erreur de RebirthRequest : {err}`)
		end
	end)
	-- Un handler par palier deja cree sur Roblox (productId > 0)
	for _, tier in Rebirth.KeepCashProducts do
		if tier.productId > 0 then
			ReceiptService.Register(tier.productId, onKeepCashReceipt)
		end
	end
end

function RebirthService:Start()
	FloorService.SetNewFloorLevels(newFloorLevels)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, purchased: boolean)
		if purchased and masterPassId > 0 and id == masterPassId then
			grantMaster(player)
		end
	end)
	-- Pass offert (GiftService) : meme effet qu'un achat
	GamePass.OnGranted(function(player: Player, id: number)
		if masterPassId > 0 and id == masterPassId then
			grantMaster(player)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
			characterConnections[player] = nil
		end
	end)
	DataService.OnPlayerLoaded(function(player: Player)
		syncPlayer(player)
	end)
end

---------------------------------------------------------------------------------------------
-- Tests (panneau admin, DebugService en Studio) : ECRIVENT LA SAUVEGARDE.

-- Rebirth gratuit sans conditions (argent remis a 0, comme un vrai rebirth).
function RebirthService.ForceRebirth(player: Player, keepCash: boolean?): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	performRebirth(player, data, keepCash == true)
	return true
end

-- Met le nombre de rebirths a `count` (la tour ne change pas).
function RebirthService.DebugSet(player: Player, count: number): boolean
	local data = DataService.GetData(player)
	if data == nil or type(count) ~= "number" or count ~= count then
		return false
	end
	data.Rebirths = math.clamp(math.floor(count), 0, GameConfig.MaxRebirths)
	syncPlayer(player)
	return true
end

-- Donne ou retire le pass Rebirth Master pour les tests (DebugService en Studio, panneau admin).
function RebirthService.DebugSetMaster(player: Player, owned: boolean): boolean
	player:SetAttribute(MASTER_ATTRIBUTE, if owned then true else nil)
	return true
end

function RebirthService.DebugGet(player: Player): { [string]: any }?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	return {
		Rebirths = data.Rebirths,
		Multiplier = Rebirth.Multiplier(data.Rebirths),
		Price = Rebirth.Price(data.Rebirths),
		KeepCashPrice = Rebirth.KeepCashProduct(data.Rebirths).price,
		KeptTrees = table.clone(data.KeptTrees),
		Master = RebirthService.OwnsMaster(player),
		Floors = DataService.FloorsOwned(data),
		Money = data.Money,
	}
end

return RebirthService
