--!strict
-- Cadeaux de passes (2026-11-23). Bouton rose d'un pass dans la boutique -> le client montre les
-- joueurs du serveur (GiftController) -> remote ShopGift(passKey, recipientUserId).
--   * ShopGift : cle connue avec un produit cadeau, destinataire dans le serveur, pas soi-meme, pas
--     deja possede (achat ou cadeau), delai. Le serveur note le destinataire pour ce produit
--     (Shop.Gifts.PendingSeconds) puis ouvre le Developer Product "Gift - <pass>" (meme prix).
--   * Recu (ReceiptService) : le cadeau est ecrit dans la boite aux lettres du destinataire
--     (DataStore Shop.Gifts.StoreName, cle "u<UserId>", UpdateAsync : { Pending, Done }) ; un meme
--     PurchaseId n'y entre qu'une fois (deja en attente ou deja livre = deja fait). Recu sans
--     destinataire note (serveur change, plus de 10 min) : le pass est offert a l'acheteur lui-meme.
--   * Livraison : destinataire dans ce serveur (tout de suite) ou a sa prochaine arrivee
--     (DataService.OnPlayerLoaded) : chaque cadeau en attente -> DataService.GrantPurchaseOnce
--     (Data.GiftedPasses[cle] = true, PurchaseId garde : jamais deux fois) -> deplace dans Done.
--   * Effet : Lib/GamePass.Owns compte Data.GiftedPasses ; GamePass.FireGranted previent les
--     services de passes (meme effet qu'un achat), au cadeau et a chaque chargement de sauvegarde.
-- Doc : docs/systems/cadeaux.md

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Shop = require(Config:WaitForChild("Shop"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local GamePass = require(script.Parent.Parent.Lib.GamePass)
local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)
local ReceiptService = require(script.Parent.ReceiptService)

local GiftService = {}

type PassInfo = { key: string, title: string, passId: number, giftProductId: number }
type Gift = { id: string, key: string, from: number, fromName: string }
type Mailbox = { Pending: { Gift }, Done: { string } }
type Intent = { to: number, at: number }

local MESSAGES = Shop.Messages
local GIFTS = Shop.Gifts

local byKey: { [string]: PassInfo } = {}
local byPassId: { [number]: PassInfo } = {}
local byGiftProduct: { [number]: PassInfo } = {}
for _, pass in Shop.Passes do
	local info: PassInfo = { key = pass.key, title = pass.title, passId = pass.passId, giftProductId = pass.giftProductId }
	byKey[pass.key] = info
	if pass.passId > 0 then
		byPassId[pass.passId] = info
	end
	if pass.giftProductId > 0 then
		assert(byGiftProduct[pass.giftProductId] == nil, `Shop : produit cadeau en double ({pass.key})`)
		byGiftProduct[pass.giftProductId] = info
	end
end

local intents: { [Player]: { [number]: Intent } } = {}
local delivering: { [Player]: boolean } = {}
local store: DataStore? = nil

local function getStore(): DataStore
	if store == nil then
		store = DataStoreService:GetDataStore(GIFTS.StoreName)
	end
	return store :: DataStore
end

local function mailboxKey(userId: number): string
	return "u" .. tostring(userId)
end

-- Boite aux lettres lue depuis le DataStore (valeurs nettoyees : jamais confiance aveugle).
local function cleanMailbox(raw: any): Mailbox
	local box: Mailbox = { Pending = {}, Done = {} }
	if type(raw) ~= "table" then
		return box
	end
	if type(raw.Pending) == "table" then
		for _, gift in raw.Pending do
			if type(gift) == "table" and type(gift.id) == "string" and type(gift.key) == "string" and byKey[gift.key] then
				table.insert(box.Pending, {
					id = gift.id,
					key = gift.key,
					from = if type(gift.from) == "number" then gift.from else 0,
					fromName = if type(gift.fromName) == "string" then string.sub(gift.fromName, 1, 40) else "Someone",
				})
			end
		end
	end
	if type(raw.Done) == "table" then
		for _, id in raw.Done do
			if type(id) == "string" then
				table.insert(box.Done, id)
			end
		end
	end
	return box
end

local function hasId(box: Mailbox, id: string): boolean
	if table.find(box.Done, id) then
		return true
	end
	for _, gift in box.Pending do
		if gift.id == id then
			return true
		end
	end
	return false
end

-- UpdateAsync avec quelques essais. `transform` recoit une boite propre et la modifie.
local function updateMailbox(userId: number, transform: (Mailbox) -> ()): (boolean, Mailbox?)
	for attempt = 1, GIFTS.Retries do
		local result: Mailbox? = nil
		local ok, err = pcall(function()
			getStore():UpdateAsync(mailboxKey(userId), function(raw: any)
				local box = cleanMailbox(raw)
				transform(box)
				while #box.Pending > GIFTS.MaxMailbox do
					table.remove(box.Pending, 1)
				end
				while #box.Done > GIFTS.MaxDone do
					table.remove(box.Done, 1)
				end
				result = box
				return box
			end)
		end)
		if ok then
			return true, result
		end
		warn(`[GiftService] Boite aux lettres {userId} (essai {attempt}) : {err}`)
		task.wait(attempt)
	end
	return false, nil
end

-- Le joueur a-t-il deja ce pass (achat Roblox ou cadeau) ? Peut attendre (appel Roblox).
local function ownsPass(player: Player, info: PassInfo): boolean
	local data = DataService.GetData(player)
	if data and data.GiftedPasses[info.key] then
		return true
	end
	return GamePass.Owns(player, info.passId)
end

---------------------------------------------------------------------------------------------
-- Livraison

-- Previent les services de passes pour chaque pass offert (effets actifs).
local function applyGifted(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	for key in data.GiftedPasses do
		local info = byKey[key]
		if info and info.passId > 0 then
			GamePass.FireGranted(player, info.passId)
		end
	end
end

-- Lit la boite aux lettres du joueur et lui donne chaque cadeau en attente (une fois chacun).
local function deliver(player: Player)
	if delivering[player] or DataService.GetData(player) == nil then
		return
	end
	delivering[player] = true
	local ok, box = updateMailbox(player.UserId, function() end) -- lecture fraiche (sans cache)
	local delivered: { string } = {}
	if ok and box then
		for _, gift in box.Pending do
			local info = byKey[gift.key]
			local isNew = false
			local granted = DataService.GrantPurchaseOnce(player, gift.id, function(data): boolean
				isNew = data.GiftedPasses[gift.key] ~= true
				data.GiftedPasses[gift.key] = true
				return true
			end)
			if granted then
				table.insert(delivered, gift.id)
				if info and player.Parent == Players then
					if info.passId > 0 then
						GamePass.FireGranted(player, info.passId)
					end
					local message = if gift.from == player.UserId
						then string.format(MESSAGES.GiftSelfGot, info.title)
						else string.format(MESSAGES.GiftGot, gift.fromName, info.title)
					NotifyService.Notify(player, message)
					if not isNew then
						warn(`[GiftService] {player.UserId} avait deja {gift.key} (cadeau {gift.id})`)
					end
				end
			end
		end
	end
	if #delivered > 0 then
		-- Livres : sortis de Pending, gardes dans Done (un recu redonne n'offre jamais deux fois)
		updateMailbox(player.UserId, function(mailbox: Mailbox)
			local kept: { Gift } = {}
			for _, gift in mailbox.Pending do
				if table.find(delivered, gift.id) then
					if not table.find(mailbox.Done, gift.id) then
						table.insert(mailbox.Done, gift.id)
					end
				else
					table.insert(kept, gift)
				end
			end
			mailbox.Pending = kept
		end)
	end
	delivering[player] = nil
end

---------------------------------------------------------------------------------------------
-- Achat

local function onShopGift(player: Player, key: unknown, recipientId: unknown)
	if type(key) ~= "string" or #key > 40 or type(recipientId) ~= "number" or recipientId % 1 ~= 0 then
		return
	end
	if not PlayerCheck.Cooldown(player, "ShopGift", Shop.BuyCooldownSeconds) then
		return
	end
	local info = byKey[key]
	if info == nil then
		return
	end
	if info.giftProductId <= 0 then
		NotifyService.Notify(player, MESSAGES.GiftSoon)
		return
	end
	if recipientId == player.UserId then
		NotifyService.Notify(player, MESSAGES.GiftSelf, true)
		return
	end
	local recipient = Players:GetPlayerByUserId(recipientId)
	if recipient == nil then
		NotifyService.Notify(player, MESSAGES.GiftNoPlayer, true)
		return
	end
	if ownsPass(recipient, info) then
		NotifyService.Notify(player, string.format(MESSAGES.GiftAlreadyOwned, recipient.DisplayName), true)
		return
	end
	local list = intents[player]
	if list == nil then
		list = {}
		intents[player] = list
	end
	list[info.giftProductId] = { to = recipientId, at = os.clock() }
	PurchasePrompt.Product(player, info.giftProductId)
end

local function receiptHandler(receipt: ReceiptService.Receipt): boolean
	local info = byGiftProduct[receipt.ProductId]
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if info == nil then
		return false
	end
	local list = if buyer then intents[buyer] else nil
	local intent = if list then list[receipt.ProductId] else nil
	local to = if intent and os.clock() - intent.at <= GIFTS.PendingSeconds then intent.to else receipt.PlayerId
	local gift: Gift = {
		id = receipt.PurchaseId,
		key = info.key,
		from = receipt.PlayerId,
		fromName = if buyer then string.sub(buyer.DisplayName, 1, 40) else "Someone",
	}
	local ok = updateMailbox(to, function(box: Mailbox)
		if not hasId(box, gift.id) then
			table.insert(box.Pending, gift)
		end
	end)
	if not ok then
		return false -- Roblox redonnera le recu
	end
	if list then
		list[receipt.ProductId] = nil
	end
	print(`[GiftService] Recu {receipt.PurchaseId} : {info.key} de {receipt.PlayerId} pour {to}`)
	local recipient = Players:GetPlayerByUserId(to)
	if buyer and to ~= receipt.PlayerId then
		local name = if recipient then recipient.DisplayName else tostring(to)
		NotifyService.Notify(buyer, string.format(MESSAGES.GiftSent, name))
	end
	if recipient then
		task.spawn(deliver, recipient)
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Tests Studio (DebugService) : recu simule (sans fenetre). recipientId 0 = sans destinataire note.

function GiftService.DebugGift(buyer: Player, key: string, recipientId: number, purchaseId: string): any
	local info = byKey[key]
	if info == nil or info.giftProductId <= 0 then
		return "unknown pass"
	end
	if recipientId > 0 then
		intents[buyer] = intents[buyer] or {}
		intents[buyer][info.giftProductId] = { to = recipientId, at = os.clock() }
	end
	return receiptHandler({
		PlayerId = buyer.UserId,
		ProductId = info.giftProductId,
		PurchaseId = purchaseId,
		CurrencySpent = 0,
		PlaceIdWherePurchased = game.PlaceId,
	})
end

-- Retire un pass offert (remise du profil de test ; l'effet reste jusqu'a la prochaine arrivee).
function GiftService.DebugRemove(player: Player, key: string): any
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	data.GiftedPasses[key] = nil
	return true
end

function GiftService.DebugGet(player: Player): any
	local data = DataService.GetData(player)
	local ok, box = updateMailbox(player.UserId, function() end)
	return { gifted = if data then table.clone(data.GiftedPasses) else nil, mailbox = if ok then box else "error" }
end

---------------------------------------------------------------------------------------------

function GiftService:Init()
	Remotes.GetServerEvent("ShopGift")
	GamePass.SetGiftedCheck(function(player: Player, passId: number): boolean
		local info = byPassId[passId]
		local data = DataService.GetData(player)
		return info ~= nil and data ~= nil and data.GiftedPasses[info.key] == true
	end)
	for productId in byGiftProduct do
		ReceiptService.Register(productId, receiptHandler)
	end
end

function GiftService:Start()
	Remotes.GetServerEvent("ShopGift").OnServerEvent:Connect(onShopGift)
	DataService.OnPlayerLoaded(function(player: Player)
		applyGifted(player)
		task.spawn(deliver, player)
	end)
	-- Deja charges : apres les Start des autres services (leurs OnGranted sont alors branches)
	task.defer(function()
		for _, player in Players:GetPlayers() do
			if DataService.GetData(player) then
				applyGifted(player)
				task.spawn(deliver, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		intents[player] = nil
		delivering[player] = nil
	end)
end

return GiftService
