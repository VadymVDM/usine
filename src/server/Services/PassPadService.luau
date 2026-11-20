--!strict
-- Pads violets des passes Robux "simples" (2026-11-20) : marcher dessus = fenetre d'achat Roblox du
-- pass ; pass possede = attribut joueur (pose ICI seulement, par le serveur) + etiquette "ACTIVE".
--   * "SpeedBoost" (Waiter Speed x10) : Machines.SpeedBoost.Pad de chaque etage, a cote du pad Take Juices
--     (ancien pad Auto Sell). Cache tant que le Waiter de l'etage n'est pas embauche (attribut
--     d'etage Lv_Waiter, LevelLookController). Effet : WorkerService (Waiter x10 plus rapide) + Lib/FloorIncome.
--   * "Billboard" (2X Sell Price) : Machines.Billboard.Pad de l'etage 1, dans la cour. Effet :
--     CustomerService (prix de vente x Gameplay.BillboardSellMultiplier).
--   * "InstantSell" (2026-11-21, ancien pass Auto Sell) : Counter.InstantSellPad de chaque etage,
--     juste a droite du pad Drop Juices. Effet : CustomerService (jus poses = vendus tout de suite).
-- passId = 0 tant que le pass n'est pas cree sur Roblox : message "coming soon".
-- Rien de sauvegarde : Roblox garde le pass (UserOwnsGamePassAsync a chaque arrivee).
-- Doc : docs/systems/pads-robux.md

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Shop = require(Config:WaitForChild("Shop"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local RobuxPad = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("RobuxPad"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local FloorService = require(script.Parent.FloorService)
local NotifyService = require(script.Parent.NotifyService)

local PassPadService = {}

type PadDef = {
	key: string, -- Shop.Passes key = nom du modele dans Machines = attribut joueur
	gate: string?, -- attribut d'etage qui doit etre >= 1 pour que le pad marche (pad cache sinon)
	counterPad: string?, -- pad dans floor.Counter (ce nom) au lieu de floor.Machines.<key>.Pad
	message: string, -- "deja actif"
	passId: number,
	price: number,
}

local PADS: { PadDef } = {
	{ key = "SpeedBoost", gate = "Lv_Waiter", message = Gameplay.Messages.SpeedBoostOn, passId = 0, price = 0 },
	{ key = "Billboard", gate = nil, message = Gameplay.Messages.BillboardOn, passId = 0, price = 0 },
	{ key = "InstantSell", gate = nil, counterPad = "InstantSellPad", message = Gameplay.Messages.InstantSellOn, passId = 0, price = 0 },
}
for _, def in PADS do
	for _, pass in Shop.Passes do
		if pass.key == def.key then
			def.passId = pass.passId
			def.price = pass.price
		end
	end
end

-- onPad[player][key] = vrai tant que le joueur est sur ce pad (achat seulement a l'arrivee)
local onPad: { [Player]: { [string]: boolean } } = {}
local gateWatch: { [Model]: RBXScriptConnection } = {}

function PassPadService.Owns(player: Player, key: string): boolean
	return player:GetAttribute(key) == true
end

local function padOf(floor: Model, def: PadDef): Model?
	if def.counterPad then
		local counter = floor:FindFirstChild("Counter")
		local pad = counter and counter:FindFirstChild(def.counterPad)
		return if pad and pad:IsA("Model") then pad else nil
	end
	local machines = floor:FindFirstChild("Machines")
	local machine = machines and machines:FindFirstChild(def.key)
	local inner = machine and machine:FindFirstChild("Pad")
	return if inner and inner:IsA("Model") then inner else nil
end

local function refreshFloor(floor: Model, player: Player?)
	for _, def in PADS do
		local pad = padOf(floor, def)
		if pad then
			RobuxPad.SetPrice(pad, def.price, player ~= nil and PassPadService.Owns(player, def.key))
		end
	end
end

local function refreshPlayer(player: Player)
	local index = 1
	while true do
		local floor = FloorService.GetFloor(player, index)
		if floor == nil then
			break
		end
		refreshFloor(floor, player)
		index += 1
	end
end

local function grant(player: Player, key: string)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(key, true)
	refreshPlayer(player)
end

local function checkPasses(player: Player)
	for _, def in PADS do
		if def.passId > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, def.passId)
			if ok and owns then
				grant(player, def.key)
			end
		end
	end
end

local function onPadEnter(player: Player, def: PadDef)
	if PassPadService.Owns(player, def.key) then
		NotifyService.Notify(player, def.message)
	elseif def.passId > 0 then
		PurchasePrompt.GamePass(player, def.passId)
	else
		NotifyService.Notify(player, Upgrades.Messages.RobuxSoon)
	end
end

-- Le proprietaire marche sur un pad d'un de SES etages (seulement a l'arrivee sur le pad).
local function checkContact(player: Player)
	local root = PlayerCheck.GetRoot(player)
	local flags = onPad[player]
	if flags == nil then
		flags = {}
		onPad[player] = flags
	end
	for _, def in PADS do
		local inside = false
		local gated = false
		if root then
			local index = 1
			while not inside do
				local floor = FloorService.GetFloor(player, index)
				if floor == nil then
					break
				end
				local pad = padOf(floor, def)
				local zone = pad and pad:FindFirstChild("PadZone")
				if zone and zone:IsA("BasePart") and PlayerCheck.IsOver(zone, root.Position) then
					inside = true
					local level = if def.gate then floor:GetAttribute(def.gate) else 1
					gated = type(level) ~= "number" or level < 1
				end
				index += 1
			end
		end
		-- Pad cache (Waiter pas embauche) : on note quand meme si le joueur est dessus. Juste apres
		-- l'embauche, il doit descendre et remonter pour ouvrir l'achat Robux.
		if inside and not gated and not flags[def.key] then
			onPadEnter(player, def)
		end
		flags[def.key] = if inside then true else nil
	end
end

function PassPadService:Init() end

function PassPadService:Start()
	FloorService.OnFloorStarted(function(player: Player, floor: Model, _index: number)
		refreshFloor(floor, player)
		-- Embauche du Waiter (le joueur est encore sur le pad) : on le compte deja "sur le pad
		-- violet", sinon la boucle de contact ouvrait l'achat Robux dans la meme seconde.
		if gateWatch[floor] then
			gateWatch[floor]:Disconnect()
		end
		gateWatch[floor] = floor:GetAttributeChangedSignal("Lv_Waiter"):Connect(function()
			local level = floor:GetAttribute("Lv_Waiter")
			local flags = onPad[player]
			if type(level) == "number" and level >= 1 and flags and player.Parent == Players then
				flags.SpeedBoost = true -- remis a nil des qu'il n'est plus sur le pad
			end
		end)
	end)
	-- Base libre / etage ferme : etiquettes par defaut
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		refreshFloor(floor, nil)
		if gateWatch[floor] then
			gateWatch[floor]:Disconnect()
			gateWatch[floor] = nil
		end
	end)
	Players.PlayerAdded:Connect(checkPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		onPad[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, purchased: boolean)
		if not purchased then
			return
		end
		for _, def in PADS do
			if def.passId > 0 and id == def.passId then
				grant(player, def.key)
			end
		end
	end)
	-- Attribut pose a la main (tests Studio) : etiquettes a jour
	local function watch(player: Player)
		for _, def in PADS do
			player:GetAttributeChangedSignal(def.key):Connect(function()
				refreshPlayer(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	task.spawn(function()
		while true do
			task.wait(Gameplay.ContactCheckSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkContact, player)
				if not ok then
					warn(`[PassPadService] contact : {err}`)
				end
			end
		end
	end)
end

return PassPadService
