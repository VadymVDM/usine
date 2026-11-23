--!strict
-- Pass Robux "Thief" (Shop.Passes "Thief", 149 R$) : proposition d'achat directe (2026-11-20).
-- Un joueur qui marche sur les pads a jus d'un etage d'une AUTRE base (Production.TakeJuicePad =
-- table a jus, Counter.JuiceDropPad = comptoir) voit tout de suite la fenetre d'achat Roblox du pass
-- (MarketplaceService:PromptGamePassPurchase, pas de menu du jeu). Seulement a l'arrivee sur le pad,
-- et au plus une fois toutes les Gameplay.ThiefPromptCooldown secondes.
--   * passId = 0 (pass pas encore cree sur Roblox) : message "Robux purchases: coming soon!".
--   * Deja proprietaire : sur la table a jus = VOL (2026-11-23) : ses mains pleines de jus, une fois
--     par victime par Gameplay.StealCooldown ; la victime ne perd rien ("assurance", message) et seul
--     le voleur voit les gobelets disparaitre (Feedback "StolenCups"). Sur le comptoir : message.
-- Possession : attribut joueur "Thief" (pose ici seulement, par le serveur). Rien de sauvegarde.
-- Aucun remote : le serveur lit la position des personnages (PlayerCheck.IsOver).
-- Doc : docs/systems/vol.md

local GamePass = require(script.Parent.Parent.Lib.GamePass)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Shop = require(Config:WaitForChild("Shop"))
local Upgrades = require(Config:WaitForChild("Upgrades"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local FloorService = require(script.Parent.FloorService)
local ProductionService = require(script.Parent.ProductionService)
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
	local owns = GamePass.Owns(player, passId) -- jamais vrai pour le createur (Lib/GamePass)
	if owns then
		grant(player)
	end
end

local function zoneOf(floor: Model, folderName: string, padName: string): BasePart?
	local folder = floor:FindFirstChild(folderName)
	local pad = folder and folder:FindFirstChild(padName)
	local zone = pad and pad:FindFirstChild("PadZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end

-- Pad a jus d'une autre base sous les pieds du joueur : (zone, etage, proprietaire, nom du pad).
local function foreignPadUnder(player: Player, position: Vector3): (BasePart?, Model?, Player?, string?)
	for floor, owner in floors do
		if owner == player or not FloorService.IsLive(floor) then
			continue
		end
		for _, entry in PADS do
			local zone = zoneOf(floor, entry[1], entry[2])
			if zone and PlayerCheck.IsOver(zone, position) then
				return zone, floor, owner, entry[2]
			end
		end
	end
	return nil, nil, nil, nil
end

local function fill(template: string, values: { [string]: string }): string
	return (string.gsub(template, "{(%w+)}", function(key: string)
		return values[key] or ""
	end))
end

-- Dernier vol de chaque voleur, par victime (UserId) : une fois par victime par StealCooldown.
local lastSteal: { [Player]: { [number]: number } } = {}

-- Vol (2026-11-23, regles de l'utilisateur) : le voleur prend ses mains pleines de jus de la table
-- de la victime. La victime ne perd RIEN (son "assurance" rembourse) : elle recoit seulement un
-- message. Seul le voleur voit les gobelets disparaitre (son client les cache).
local function steal(player: Player, floor: Model, victim: Player)
	local messages = Gameplay.Messages
	local now = os.clock()
	local history = lastSteal[player]
	if history == nil then
		history = {}
		lastSteal[player] = history
	end
	local last = history[victim.UserId]
	if last and now - last < Gameplay.StealCooldown then
		local wait = math.ceil(Gameplay.StealCooldown - (now - last))
		NotifyService.Notify(player, fill(messages.StealWait, { name = victim.DisplayName, seconds = tostring(wait) }), true)
		return
	end
	local room = ProductionService.GetHandRoom(player)
	if room <= 0 then
		NotifyService.Notify(player, messages.HandsFull, true)
		return
	end
	local ids, from, models = ProductionService.PeekJuices(floor, room)
	if #ids == 0 then
		NotifyService.Notify(player, messages.StealNothing, true)
		return
	end
	local given = ProductionService.GiveJuices(player, ids, from, models)
	if given <= 0 then
		return
	end
	history[victim.UserId] = now
	local count = tostring(given)
	NotifyService.Notify(player, fill(messages.StealDone, { n = count, name = victim.DisplayName }))
	if victim.Parent == Players then
		NotifyService.Notify(victim, fill(messages.StealVictim, { n = count, name = player.DisplayName }))
	end
end

local function onEnter(player: Player, floor: Model, owner: Player, padName: string)
	if ThiefService.Owns(player) then
		if padName == "TakeJuicePad" then
			steal(player, floor, owner)
		elseif PlayerCheck.Cooldown(player, "ThiefPrompt", Gameplay.ThiefPromptCooldown) then
			NotifyService.Notify(player, Gameplay.Messages.StealAtTable)
		end
		return
	end
	if not PlayerCheck.Cooldown(player, "ThiefPrompt", Gameplay.ThiefPromptCooldown) then
		return
	end
	if passId > 0 then
		PurchasePrompt.GamePass(player, passId)
	else
		NotifyService.Notify(player, Upgrades.Messages.RobuxSoon)
	end
end

local function checkContact(player: Player)
	local root = PlayerCheck.GetRoot(player)
	local zone, floor, owner, padName
	if root then
		zone, floor, owner, padName = foreignPadUnder(player, root.Position)
	end
	if zone and floor and owner and padName and standingOn[player] ~= zone then
		onEnter(player, floor, owner, padName)
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
		lastSteal[player] = nil
	end)
	GamePass.OnPurchased(function(player: Player, id: number) -- possession reverifiee
		if passId > 0 and id == passId then
			grant(player)
		end
	end)
	-- Pass offert (GiftService) : meme effet qu'un achat
	GamePass.OnGranted(function(player: Player, id: number)
		if passId > 0 and id == passId then
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
