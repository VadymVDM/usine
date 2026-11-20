--!strict
-- Index des fruits : envoie au joueur la liste de ses fruits decouverts / recompenses prises, et
-- donne la recompense "CLAIM" (une seule fois par fruit decouvert).
-- Seul module qui ecrit Data.ClaimedFruits. Les decouvertes restent ecrites par TreeService, qui
-- appelle IndexService.Sync apres une decouverte.
-- Remote IndexClaim (client -> serveur) : id = chaine, fruit connu, decouvert, pas deja pris,
-- sauvegarde chargee, delai GameConfig.IndexClaimCooldown. Montant calcule ici (Fruits.ClaimReward),
-- jamais envoye par le client.
-- Remote IndexState (serveur -> client) : { discovered = { ids }, claimed = { ids } }.
-- Doc : docs/systems/fruits.md (section "Index")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Fruits = require(Config:WaitForChild("Fruits"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)

local IndexService = {}

local stateEvent: RemoteEvent? = nil
local feedbackEvent: RemoteEvent? = nil

local function listOf(set: { [string]: boolean }): { string }
	local list: { string } = {}
	for id in set do
		table.insert(list, id)
	end
	return list
end

-- Renvoie l'etat complet de l'Index au joueur (apres chargement, decouverte, claim, outils de test).
function IndexService.Sync(player: Player)
	local data = DataService.GetData(player)
	if data == nil or stateEvent == nil or player.Parent ~= Players then
		return
	end
	stateEvent:FireClient(player, {
		discovered = listOf(data.DiscoveredFruits),
		claimed = listOf(data.ClaimedFruits),
	})
end

local function onClaim(player: Player, fruitId: any)
	if typeof(fruitId) ~= "string" or Fruits.ById[fruitId] == nil then
		return
	end
	if not PlayerCheck.Cooldown(player, "IndexClaim", GameConfig.IndexClaimCooldown) then
		return
	end
	local data = DataService.GetData(player)
	if data == nil or not data.DiscoveredFruits[fruitId] or data.ClaimedFruits[fruitId] then
		IndexService.Sync(player)
		return
	end
	local amount = Fruits.ClaimReward(fruitId)
	data.ClaimedFruits[fruitId] = true
	if amount > 0 then
		MoneyService.Add(player, amount, "IndexClaim")
	end
	if feedbackEvent then
		feedbackEvent:FireClient(player, "IndexClaim", { fruit = fruitId, amount = amount })
	end
	IndexService.Sync(player)
end

function IndexService:Init()
	stateEvent = Remotes.GetServerEvent("IndexState")
	Remotes.GetServerEvent("IndexClaim")
	feedbackEvent = Remotes.GetServerEvent("Feedback")
end

function IndexService:Start()
	Remotes.GetServerEvent("IndexClaim").OnServerEvent:Connect(onClaim)
	DataService.OnPlayerLoaded(function(player: Player)
		IndexService.Sync(player)
	end)
end

return IndexService
