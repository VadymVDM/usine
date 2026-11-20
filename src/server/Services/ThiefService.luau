--!strict
-- Pass Robux "Thief" (Shop.Passes "Thief", 149 R$) : proposition d'achat directe (2026-11-20).
-- Un joueur qui marche sur les pads a jus d'un etage d'une AUTRE base (Production.TakeJuicePad =
-- table a jus, Counter.JuiceDropPad = comptoir) voit tout de suite la fenetre d'achat Roblox du pass
-- (MarketplaceService:PromptGamePassPurchase, pas de menu du jeu). Seulement a l'arrivee sur le pad,
-- et au plus une fois toutes les Gameplay.ThiefPromptCooldown secondes.
--   * passId = 0 (pass pas encore cree sur Roblox) : message "Robux purchases: coming soon!".
--   * Deja proprietaire : message Gameplay.Messages.ThiefOwned. Le VOL lui-meme n'est pas code.
-- Possession : attribut joueur "Thief" (pose ici seulement, par le serveur). Rien de sauvegarde.
-- Aucun remote : le serveur lit la position des personnages (PlayerCheck.IsOver).
-- Doc : docs/systems/vol.md

local MarketplaceService = game:GetService("MarketplaceService")
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Shop = require(Config:WaitForChild("Shop"))
local Upgrades = require(Config:WaitForChild("Upgrades"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local FloorService = require(script.Parent.FloorService)
local NotifyService = require(script.Parent.NotifyService)

local ThiefService = {}

local ATTRIBUTE = "Thief"
-- Pads ou sont les jus des autres : { dossier de l'etage, pad }
local PADS = {
	{ "Production", "TakeJuicePad" },
	{ "Counter", "JuiceDropPad" },
}

local passId = 0
for _, pass in Shop.Passes do
	if pass.key == "Thief" then
		passId = pass.passId
	end
end

-- Etages qui tournent (proprietaire charge) -> proprietaire
local floors: { [Model]: Player } = {}
-- Pad sur lequel se tient chaque joueur (pour ne reagir qu'a l'arrivee)
local standingOn: { [Player]: BasePart } = {}

function ThiefService.Owns(player: Player): boolean
	return player:GetAttribute(ATTRIBUTE) == true
end

local function grant(player: Player)
	if player.Parent == Players then
		player:SetAttribute(ATTRIBUTE, true)
	end
end

local function checkPass(player: Player)
	if passId <= 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	if ok and owns then
		grant(player)
	end
end

local function zoneOf(floor: Model, folderName: string, padName: string): BasePart?
	local folder = floor:FindFirstChild(folderName)
	local pad = folder and folder:FindFirstChild(padName)
	local zone = pad and pad:FindFirstChild("PadZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end

-- Pad a jus d'une autre base sous les pieds du joueur (nil sinon).
local function foreignPadUnder(player: Player, position: Vector3): BasePart?
	for floor, owner in floors do
		if owner == player or not FloorService.IsLive(floor) then
			continue
		end
		for _, entry in PADS do
			local zone = zoneOf(floor, entry[1], entry[2])
			if zone and PlayerCheck.IsOver(zone, position) then
				return zone
			end
		end
	end
	return nil
end

local function onEnter(player: Player)
	if not PlayerCheck.Cooldown(player, "ThiefPrompt", Gameplay.ThiefPromptCooldown) then
		return
	end
	if ThiefService.Owns(player) then
		NotifyService.Notify(player, Gameplay.Messages.ThiefOwned)
	elseif passId > 0 then
		PurchasePrompt.GamePass(player, passId)
	else
		NotifyService.Notify(player, Upgrades.Messages.RobuxSoon)
	end
end

local function checkContact(player: Player)
	local root = PlayerCheck.GetRoot(player)
	local zone = root and foreignPadUnder(player, root.Position)
	if zone and standingOn[player] ~= zone then
		onEnter(player)
	end
	standingOn[player] = zone
end

function ThiefService:Init() end

function ThiefService:Start()
	FloorService.OnFloorStarted(function(player: Player, floor: Model, _index: number)
		floors[floor] = player
	end)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		floors[floor] = nil
	end)
	Players.PlayerAdded:Connect(checkPass)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPass, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		standingOn[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, purchased: boolean)
		if purchased and passId > 0 and id == passId then
			grant(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Gameplay.ContactCheckSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkContact, player)
				if not ok then
					warn(`[ThiefService] {err}`)
				end
			end
		end
	end)
end

return ThiefService
