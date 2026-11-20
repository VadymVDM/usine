--!strict
-- Seul proprietaire de MarketplaceService.ProcessReceipt (achats de Developer Products en Robux).
-- Chaque service enregistre ses produits dans son Init : ReceiptService.Register(productId, handler).
-- Le handler doit appliquer l'achat UNE seule fois de facon durable (PurchaseId deja vu = succes)
-- et renvoyer true seulement quand c'est ecrit. Sinon (ou produit inconnu, erreur) : NotProcessedYet,
-- Roblox redonnera le recu plus tard (prochaine connexion du joueur ou prochain achat).
-- Doc : docs/systems/dons.md (section Recus)

local MarketplaceService = game:GetService("MarketplaceService")

export type Receipt = {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
	CurrencySpent: number,
	PlaceIdWherePurchased: number,
}

export type Handler = (receipt: Receipt) -> boolean

local ReceiptService = {}

local handlers: { [number]: Handler } = {}
-- Appeles apres CHAQUE achat accorde (ex. Robux payes du classement). Meme regle que les handlers :
-- un meme PurchaseId ne compte qu'une fois, true seulement quand c'est ecrit. false ou erreur ->
-- NotProcessedYet : Roblox redonne le recu, le handler voit le PurchaseId deja traite et renvoie true.
local grantedHooks: { Handler } = {}

-- A appeler dans Init (avant tout achat). Un seul handler par produit.
function ReceiptService.Register(productId: number, handler: Handler)
	assert(type(productId) == "number" and productId > 0 and productId % 1 == 0, "ReceiptService : productId invalide")
	assert(handlers[productId] == nil, `ReceiptService : produit {productId} deja enregistre`)
	handlers[productId] = handler
end

-- A appeler dans Init. Voir grantedHooks.
function ReceiptService.OnGranted(hook: Handler)
	table.insert(grantedHooks, hook)
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local productId = receiptInfo.ProductId
	local handler = handlers[productId]
	if handler == nil then
		warn(`[ReceiptService] Produit inconnu {tostring(productId)} : recu laisse en attente`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipt: Receipt = {
		PlayerId = receiptInfo.PlayerId,
		ProductId = productId,
		PurchaseId = tostring(receiptInfo.PurchaseId),
		CurrencySpent = receiptInfo.CurrencySpent,
		PlaceIdWherePurchased = receiptInfo.PlaceIdWherePurchased,
	}
	local ok, granted = pcall(handler, receipt)
	if not ok then
		warn(`[ReceiptService] Erreur du handler du produit {productId} : {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	for _, hook in grantedHooks do
		local hookOk, done = pcall(hook, receipt)
		if not hookOk or done ~= true then
			warn(`[ReceiptService] Suite de l'achat {receipt.PurchaseId} pas ecrite, recu laisse en attente : {done}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ReceiptService:Init()
	MarketplaceService.ProcessReceipt = processReceipt
end

return ReceiptService
