--!strict
-- Gains hors ligne (ecran "Welcome Back!").
-- A l'arrivee, l'absence = heure de chargement - Data.LastLogout de la session d'avant
-- (DataService.GetPreviousLogout). Montant = CustomerService.GetIncomePerSecond (production en
-- nombres des etages AUTOMATISES : un etage pas automatise ne rapporte rien hors ligne, voulu)
-- x min(absence, Offline.MaxSeconds) x Offline.Rate. Rien sous Offline.MinAwaySeconds / MinAmount.
-- L'offre est sauvegardee (Data.OfflineReward) : un CLAIM ou un achat x2 n'est donne qu'une fois,
-- meme si le recu Robux arrive plus tard. Calculee une fois par session, au plus tard :
--   * quand le client a fini de charger (remote OfflineEarnings "Ready") ;
--   * a la reception d'un recu x2 ; au depart du joueur.
-- Pas reclamee au depart (ecran ferme, joueur parti) : l'argent est donne quand meme (rien de perdu).
-- Remote OfflineEarnings (client -> serveur : "Ready" | "Claim" | "Double" ; serveur -> client :
-- "Show" (secondes, montant) | "Claimed"). Le client n'envoie jamais de montant.
-- Doc : docs/systems/gains-hors-ligne.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Offline = require(Config:WaitForChild("Offline"))
local Shop = require(Config:WaitForChild("Shop")) :: any
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local CustomerService = require(script.Parent.CustomerService)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local ReceiptService = require(script.Parent.ReceiptService)

local OfflineService = {}

type Session = {
	loadedAt: number, -- os.time() au chargement de la sauvegarde
	previousLogout: number, -- Data.LastLogout lu avant la session (0 = premiere visite)
	computed: boolean, -- offre deja calculee pour cette session
}

local sessions: { [Player]: Session } = {}
local offlineEvent: RemoteEvent? = nil
local feedbackEvent: RemoteEvent? = nil

local function productId(): number
	local id = Shop.OfflineDouble and Shop.OfflineDouble.productId
	return if type(id) == "number" then id else 0
end

local function incomePerSecond(player: Player): number
	local ok, value = pcall(CustomerService.GetIncomePerSecond, player)
	if ok and type(value) == "number" and value == value and value > 0 and value ~= math.huge then
		return value
	end
	return 0
end

-- Montant gagne pour `awaySeconds` d'absence avec cet argent/s (entier >= 0, regles de la Config).
function OfflineService.Compute(perSecond: number, awaySeconds: number): number
	if awaySeconds < Offline.MinAwaySeconds or perSecond <= 0 then
		return 0
	end
	local seconds = math.min(awaySeconds, Offline.MaxSeconds)
	local amount = math.floor(perSecond * seconds * Offline.Rate)
	return if amount >= Offline.MinAmount then math.min(amount, GameConfig.MaxMoney) else 0
end

-- Calcule l'offre de la session (une seule fois). Une offre d'avant pas reclamee (serveur coupe
-- avant la sauvegarde de depart) est ajoutee a la nouvelle : rien n'est perdu.
local function ensureOffer(player: Player)
	local session = sessions[player]
	local data = DataService.GetData(player)
	if session == nil or data == nil or session.computed then
		return
	end
	session.computed = true
	local reward = data.OfflineReward
	local carried = if reward.Claimed then 0 else reward.Amount
	local away = if session.previousLogout > 0 then math.max(0, session.loadedAt - session.previousLogout) else 0
	local earned = OfflineService.Compute(incomePerSecond(player), away)
	if earned <= 0 and carried <= 0 then
		return -- rien a donner : l'ancienne offre (deja reclamee) reste pour un recu x2 en retard
	end
	data.OfflineReward = {
		Amount = math.min(carried + earned, GameConfig.MaxMoney),
		Seconds = math.min(away, Offline.MaxSeconds),
		Claimed = false,
		Doubled = false,
	}
end

local function cashFeedback(player: Player, amount: number)
	if feedbackEvent and player.Parent == Players and amount > 0 then
		-- Pas de position 3D : le compteur du HUD monte d'un coup (CashController)
		feedbackEvent:FireClient(player, "Cash", { amount = amount })
	end
end

local function sendClaimed(player: Player)
	if offlineEvent and player.Parent == Players then
		offlineEvent:FireClient(player, "Claimed")
	end
end

-- CLAIM : l'argent de l'offre, une seule fois.
local function claim(player: Player): number
	local data = DataService.GetData(player)
	if data == nil then
		return 0
	end
	local reward = data.OfflineReward
	if reward.Claimed then
		return 0
	end
	local amount = reward.Amount
	-- Marque avant d'ajouter (pas de yield entre les deux)
	reward.Claimed = true
	if amount > 0 and not MoneyService.Add(player, amount, "Offline") then
		reward.Claimed = false
		return 0
	end
	return amount
end

local function onAction(player: Player, action: any)
	-- Action connue seulement (avant le delai : pas de cle de delai pour une chaine inventee)
	if action ~= "Ready" and action ~= "Claim" and action ~= "Double" then
		return
	end
	if not PlayerCheck.Cooldown(player, "Offline" .. action, Offline.ActionCooldownSeconds) then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	if action == "Ready" then
		ensureOffer(player)
		local reward = data.OfflineReward
		if not reward.Claimed and offlineEvent then
			offlineEvent:FireClient(player, "Show", reward.Seconds, reward.Amount)
		end
	elseif action == "Claim" then
		local amount = claim(player)
		cashFeedback(player, amount)
		sendClaimed(player) -- ferme l'ecran (aussi si deja reclame)
	elseif action == "Double" then
		local reward = data.OfflineReward
		if reward.Claimed or reward.Doubled then
			sendClaimed(player)
			return
		end
		local id = productId()
		if id <= 0 then
			NotifyService.Notify(player, Offline.Messages.ComingSoon)
			return
		end
		PurchasePrompt.Product(player, id)
	end
end

-- Achat x2 (recu ou test) : x2 de l'offre, ou la moitie manquante si le CLAIM est deja fait.
-- true = ecrit (ou deja donne pour ce PurchaseId).
local function grantDouble(player: Player, purchaseId: string): boolean
	local deadline = os.clock() + Offline.ReceiptWaitSeconds
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	if DataService.GetData(player) == nil then
		return false
	end
	ensureOffer(player)
	local fallback = math.floor(incomePerSecond(player) * Offline.FallbackMinutes * 60)
	local given = 0
	local granted = DataService.GrantPurchaseOnce(player, purchaseId, function(data): boolean
		local reward = data.OfflineReward
		local amount
		if reward.Doubled then
			amount = math.max(reward.Amount, fallback, Offline.MinAmount)
		elseif reward.Claimed then
			amount = reward.Amount
		else
			amount = reward.Amount * 2
		end
		reward.Claimed = true
		reward.Doubled = true
		data.Money = math.min(data.Money + amount, GameConfig.MaxMoney)
		given = amount
		return true
	end)
	if given > 0 then
		MoneyService.SyncLeaderstats(player)
		cashFeedback(player, given)
		sendClaimed(player)
	end
	return granted
end

local function receiptHandler(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return false -- joueur parti : Roblox redonnera le recu
	end
	return grantDouble(player, receipt.PurchaseId)
end

function OfflineService:Init()
	offlineEvent = Remotes.GetServerEvent("OfflineEarnings")
	if productId() > 0 then
		ReceiptService.Register(productId(), receiptHandler)
	end
end

function OfflineService:Start()
	feedbackEvent = Remotes.GetServerEvent("Feedback")
	Remotes.GetServerEvent("OfflineEarnings").OnServerEvent:Connect(onAction)
	DataService.OnPlayerLoaded(function(player: Player)
		if sessions[player] == nil then
			sessions[player] = {
				loadedAt = os.time(),
				previousLogout = DataService.GetPreviousLogout(player),
				computed = false,
			}
		end
	end)
	-- Avant la derniere sauvegarde : offre pas reclamee = donnee quand meme
	DataService.OnPlayerRemoving(function(player: Player)
		ensureOffer(player)
		claim(player)
		sessions[player] = nil
	end)
end

---------------------------------------------------------------------------------------------
-- Tests Studio (DebugService) : serveur seulement.

-- Etat : offre sauvegardee, argent/s, absence de la session.
function OfflineService.DebugGet(player: Player): { [string]: any }?
	local data = DataService.GetData(player)
	local session = sessions[player]
	if data == nil then
		return nil
	end
	return {
		Reward = table.clone(data.OfflineReward),
		IncomePerSecond = incomePerSecond(player),
		PreviousLogout = session and session.previousLogout,
		LoadedAt = session and session.loadedAt,
		Computed = session and session.computed,
	}
end

-- Simule une absence de `seconds` (comme si LastLogout etait plus tot) et recalcule l'offre
-- (ecrit la sauvegarde ! a remettre apres le test). Le client la recoit au prochain "Ready" :
-- on la lui envoie tout de suite.
function OfflineService.DebugSimulate(player: Player, seconds: number): { [string]: any }?
	local session = sessions[player]
	local data = DataService.GetData(player)
	if session == nil or data == nil or type(seconds) ~= "number" or seconds ~= seconds then
		return nil
	end
	session.previousLogout = session.loadedAt - math.max(0, math.floor(seconds))
	session.computed = false
	ensureOffer(player)
	local reward = data.OfflineReward
	if not reward.Claimed and offlineEvent then
		offlineEvent:FireClient(player, "Show", reward.Seconds, reward.Amount)
	end
	return OfflineService.DebugGet(player)
end

-- Simule un achat x2 paye (ecrit la sauvegarde !).
function OfflineService.DebugDouble(player: Player): boolean
	return grantDouble(player, "debug-offline-" .. tostring(os.clock()))
end

return OfflineService
