--!strict
-- Le joueur possede-t-il ce GamePass ? (seul endroit du serveur qui appelle UserOwnsGamePassAsync)
-- Roblox dit que le CREATEUR du jeu possede tous ses passes : pour lui on repond toujours non, pour
-- qu'il joue comme un joueur normal. Il active les passes a la main dans le panneau admin
-- (AdminService TogglePass / ToggleMaster). Demande utilisateur du 2026-11-21.
-- Passes OFFERTS (cadeaux, GiftService, 2026-11-23) : sauvegardes dans Data.GiftedPasses ; Owns les
-- compte comme achetes (createur compris). GiftService previent les services par OnGranted (a
-- l'arrivee du cadeau et au chargement de la sauvegarde), comme PromptGamePassPurchaseFinished.
-- Utilise par : RobuxShopService, PassPadService, CustomerService (Auto Collect), RebirthService
-- (Rebirth Master), ThiefService, GiftService. Doc : docs/systems/achats-robux.md, docs/systems/cadeaux.md

local MarketplaceService = game:GetService("MarketplaceService")

local GamePass = {}

type GrantedCallback = (player: Player, passId: number) -> ()

local giftedCheck: ((player: Player, passId: number) -> boolean)? = nil
local grantedCallbacks: { GrantedCallback } = {}

-- Createur du jeu (jeu a un utilisateur ; meme regle que AdminService.isAdmin).
function GamePass.IsCreator(player: Player): boolean
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- true si le joueur a achete le pass ou l'a recu en cadeau (achat : faux pour le createur, ou si
-- Roblox ne repond pas). Peut attendre (appel Roblox) : a lancer dans un thread a part si besoin.
function GamePass.Owns(player: Player, passId: number): boolean
	if passId <= 0 then
		return false
	end
	if giftedCheck and giftedCheck(player, passId) then
		return true
	end
	if GamePass.IsCreator(player) then
		return false
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	return ok and owns == true
end

-- GiftService (Init) : fonction qui dit si le pass a ete offert au joueur (sauvegarde).
function GamePass.SetGiftedCheck(check: (player: Player, passId: number) -> boolean)
	giftedCheck = check
end

-- Appele quand un pass est donne autrement que par la fenetre d'achat (cadeau). A brancher dans
-- chaque service de pass, avec le meme effet que PromptGamePassPurchaseFinished.
function GamePass.OnGranted(callback: GrantedCallback)
	table.insert(grantedCallbacks, callback)
end

function GamePass.FireGranted(player: Player, passId: number)
	for _, callback in grantedCallbacks do
		task.spawn(callback, player, passId)
	end
end

return GamePass
