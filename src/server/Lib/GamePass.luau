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
local Players = game:GetService("Players")

local GamePass = {}

type GrantedCallback = (player: Player, passId: number) -> ()

local giftedCheck: ((player: Player, passId: number) -> boolean)? = nil
local grantedCallbacks: { GrantedCallback } = {}
local purchasedCallbacks: { GrantedCallback } = {}
-- Passes deja confirmes par Roblox (par joueur) : evite de redemander, et un "oui" ne se perd pas.
local confirmed: { [Player]: { [number]: boolean } } = {}

-- Essais de UserOwnsGamePassAsync quand Roblox ne repond pas (attente 1 s, 2 s, 4 s).
local OWNS_RETRY_WAITS = { 1, 2, 4 }

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
	local cache = confirmed[player]
	if cache and cache[passId] then
		return true
	end
	for attempt = 1, #OWNS_RETRY_WAITS + 1 do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok then
			if owns == true and player.Parent == Players then
				local list = confirmed[player] or {}
				list[passId] = true
				confirmed[player] = list
			end
			return owns == true
		end
		local wait = OWNS_RETRY_WAITS[attempt]
		if wait == nil or player.Parent ~= Players then
			break
		end
		task.wait(wait)
	end
	warn(`[GamePass] UserOwnsGamePassAsync en echec pour {player.UserId} / {passId}`)
	return false
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

-- Achat dans la fenetre Roblox (PromptGamePassPurchaseFinished). Le signal "purchased" vient de
-- la fenetre du CLIENT (falsifiable) : on redemande toujours a Roblox (Owns) avant d'appeler les
-- services. Seul endroit du serveur branche sur PromptGamePassPurchaseFinished (relecture du
-- 2026-11-23). Le createur n'est jamais confirme (Owns), comme avant.
function GamePass.OnPurchased(callback: GrantedCallback)
	table.insert(purchasedCallbacks, callback)
end

local function firePurchased(player: Player, passId: number)
	for _, callback in purchasedCallbacks do
		task.spawn(callback, player, passId)
	end
end

-- Lib/PurchasePrompt, AVANT d'ouvrir la fenetre d'achat : si Roblox dit que le joueur possede deja
-- le pass (achete hors de ce serveur, verification ratee a l'arrivee...), on l'active tout de suite
-- (memes effets qu'un achat) et on renvoie vrai : pas de fenetre "Vous possedez deja cet objet"
-- (signale le 2026-11-27). Peut attendre (appel Roblox).
function GamePass.ActivateIfOwned(player: Player, passId: number): boolean
	if not GamePass.Owns(player, passId) or player.Parent ~= Players then
		return false
	end
	firePurchased(player, passId)
	return true
end

-- `purchased` est ignore : quand le joueur possede DEJA le pass, Roblox affiche "Vous possedez deja
-- cet objet" et renvoie purchased = false (verifie dans Studio le 2026-11-27). Si le serveur avait
-- rate la possession (pass achete sur le site ou dans un autre serveur, Roblox injoignable a
-- l'arrivee), le joueur restait bloque : chaque appui rouvrait la fenetre. On redemande donc a
-- Roblox dans tous les cas ; une annulation sans possession ne donne rien (Owns = faux).
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, _purchased: boolean)
	if typeof(passId) ~= "number" or passId <= 0 then
		return
	end
	task.spawn(function()
		if not GamePass.Owns(player, passId) or player.Parent ~= Players then
			return
		end
		firePurchased(player, passId)
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	confirmed[player] = nil
end)

return GamePass
