--!strict
-- Ouvre la fenetre d'achat Roblox (pass ou produit Robux) et previent le client par le Feedback
-- "PurchasePrompt" : il montre l'effet d'ecran (contour arc-en-ciel + zoom, Fx/PurchaseFx).
-- Seul endroit du serveur qui appelle MarketplaceService:Prompt...Purchase. Aucune donnee de jeu
-- ici : la remise de l'achat reste dans chaque service (recu / PromptGamePassPurchaseFinished).
-- Doc : docs/systems/interface.md (section "Envie d'acheter")

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("Remotes"))
local GamePass = require(script.Parent.GamePass)

local PurchasePrompt = {}

local function notifyClient(player: Player)
	Remotes.GetServerEvent("Feedback"):FireClient(player, "PurchasePrompt")
end

-- Pass deja possede chez Roblox mais pas encore actif ici : active sans ouvrir la fenetre (sinon
-- Roblox affiche "Vous possedez deja cet objet"). Peut attendre (Lib/GamePass.Owns).
function PurchasePrompt.GamePass(player: Player, passId: number)
	if GamePass.ActivateIfOwned(player, passId) then
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, passId)
	notifyClient(player)
end

function PurchasePrompt.Product(player: Player, productId: number)
	MarketplaceService:PromptProductPurchase(player, productId)
	notifyClient(player)
end

return PurchasePrompt
