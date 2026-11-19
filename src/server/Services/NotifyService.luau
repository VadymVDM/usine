--!strict
-- Envoie un court message (anglais) a un joueur via le remote Notify (serveur -> client).
-- Le texte vient toujours de la Config, jamais d'un client.
-- Doc : docs/architecture.md (section Remotes)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))
local TextUtil = require(Shared:WaitForChild("Util"):WaitForChild("TextUtil"))

local NotifyService = {}

function NotifyService:Init()
	-- Cree le remote avant l'arrivee des joueurs.
	Remotes.GetServerEvent("Notify")
end

function NotifyService.Notify(player: Player, message: string)
	if player.Parent == nil then
		return
	end
	local text = TextUtil.Truncate(message, MapConfig.MaxNotifyLength)
	if text == nil then
		warn("[NotifyService] Message non UTF-8 ignore")
		return
	end
	-- Un RemoteEvent tire avant que le client ecoute est garde en file et livre a la connexion.
	Remotes.GetServerEvent("Notify"):FireClient(player, text)
end

return NotifyService
