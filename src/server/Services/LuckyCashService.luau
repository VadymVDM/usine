--!strict
-- Lucky Cash : tas d'argent cache a chaque etage, a acheter en Robux (Developer Product).
-- Le tas et la fenetre sont cote client (LuckyCashController). Ici :
--   * attribut joueur LuckyCashAmount (montant actuel, Config/LuckyCash.Amount), mis a jour toutes
--     les Gameplay.IncomeAttributeSeconds ;
--   * remote LuckyCashBuy (client -> serveur, sans argument) : sauvegarde chargee, delai ; note le
--     montant montre (garde PendingSeconds) puis ouvre la fenetre d'achat Roblox (productId 0 :
--     "coming soon") ;
--   * recu (ReceiptService) : ajoute le montant UNE seule fois par achat (DataService.GrantPurchaseOnce),
--     puis Feedback "Cash" (gerbe de billets vers le HUD, lucky = true : le client cache le tas).
-- Doc : docs/systems/lucky-cash.md

local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LuckyCash = require(Config:WaitForChild("LuckyCash"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local CustomerService = require(script.Parent.CustomerService)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local ReceiptService = require(script.Parent.ReceiptService)

local LuckyCashService = {}

type Pending = { amount: number, at: number }
local pending: { [Player]: Pending } = {}
local feedbackEvent: RemoteEvent? = nil

-- Montant offert maintenant (nil si la sauvegarde n'est pas chargee).
function LuckyCashService.GetAmount(player: Player): number?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local ok, income = pcall(CustomerService.GetIncomePerSecond, player)
	local perSecond = if ok and type(income) == "number" then income else 0
	return LuckyCash.Amount(perSecond, DataService.FloorsOwned(data))
end

local function refresh(player: Player): number?
	local amount = LuckyCashService.GetAmount(player)
	if amount and player.Parent == Players then
		player:SetAttribute(LuckyCash.AmountAttribute, amount)
	end
	return amount
end

local function onBuy(player: Player)
	if not PlayerCheck.Cooldown(player, "LuckyCashBuy", LuckyCash.BuyCooldownSeconds) then
		return
	end
	local amount = refresh(player)
	if amount == nil then
		return
	end
	pending[player] = { amount = amount, at = os.clock() }
	if LuckyCash.ProductId <= 0 then
		NotifyService.Notify(player, LuckyCash.Messages.ComingSoon)
		return
	end
	PurchasePrompt.Product(player, LuckyCash.ProductId)
end

-- Donne l'argent d'un achat (recu ou test). true = ecrit (ou deja donne pour ce PurchaseId).
local function grant(player: Player, purchaseId: string): boolean
	local deadline = os.clock() + LuckyCash.ReceiptWaitSeconds
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	local entry = pending[player]
	local amount = if entry and os.clock() - entry.at <= LuckyCash.PendingSeconds
		then entry.amount
		else LuckyCashService.GetAmount(player)
	if amount == nil then
		return false
	end
	local applied = false
	local granted = DataService.GrantPurchaseOnce(player, purchaseId, function(data): boolean
		data.Money = math.min(data.Money + amount, GameConfig.MaxMoney)
		applied = true
		return true
	end)
	if applied then
		pending[player] = nil
		MoneyService.SyncLeaderstats(player)
		local root = PlayerCheck.GetRoot(player)
		if feedbackEvent and player.Parent == Players then
			feedbackEvent:FireClient(player, "Cash", {
				amount = amount,
				from = if root then root.Position + Vector3.new(0, 2, 0) else nil,
				bills = 24,
				lucky = true,
			})
		end
	end
	return granted
end

local function receiptHandler(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return false -- joueur parti : Roblox redonnera le recu
	end
	return grant(player, receipt.PurchaseId)
end

-- Test Studio (DebugService) : simule un achat paye.
function LuckyCashService.DebugGrant(player: Player): boolean
	return grant(player, "debug-" .. tostring(os.clock()))
end

function LuckyCashService:Init()
	Remotes.GetServerEvent("LuckyCashBuy")
	if LuckyCash.ProductId > 0 then
		ReceiptService.Register(LuckyCash.ProductId, receiptHandler)
	end
end

function LuckyCashService:Start()
	feedbackEvent = Remotes.GetServerEvent("Feedback")
	Remotes.GetServerEvent("LuckyCashBuy").OnServerEvent:Connect(onBuy)
	DataService.OnPlayerLoaded(function(player: Player)
		refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(refresh, player)
				if not ok then
					warn(`[LuckyCashService] {err}`)
				end
			end
			task.wait(Gameplay.IncomeAttributeSeconds)
		end
	end)
end

return LuckyCashService
