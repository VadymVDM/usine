--!strict
-- Pass Robux "Thief" (Shop.Passes "Thief", 149 R$). Refait le 2026-11-27 (demande utilisateur) :
-- touche E "Steal" (ProximityPrompt) sur les jus d'une AUTRE base : table a jus (Production.JuicePile)
-- et comptoir (Counter.CounterTopArea). Le prompt n'apparait que chez les AUTRES joueurs
-- (attribut "ForOthers", PromptController), et seulement quand il y a des jus a voler sur l'etage
-- vivant de la victime (attribut "Active").
--   * Avec le pass : E = ses mains pleines de jus (gobelets du haut), une fois par victime par
--     Gameplay.StealCooldown ; la victime ne perd rien ("assurance", message) et seul le voleur voit
--     les gobelets disparaitre (Feedback "StolenCups").
--   * Sans le pass : E = fenetre d'achat Roblox du pass. Les jus vises sont "photographies" A
--     L'APPUI SUR E (ids, positions, modeles) : si l'achat aboutit (possession reverifiee par
--     Lib/GamePass) dans les Gameplay.StealPendingSeconds, le voleur recoit CES jus, meme si la table
--     a ete videe pendant qu'il payait.
--   * passId = 0 (pass pas cree) : message "Robux purchases: coming soon!".
-- Possession : attribut joueur "Thief" (pose ici seulement, par le serveur). Rien de sauvegarde.
-- Aucun remote : ProximityPrompt.Triggered, verifie ici (proprietaire, etage vivant, distance, delai).
-- Doc : docs/systems/vol.md

local GamePass = require(script.Parent.Parent.Lib.GamePass)
local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Shop = require(Config:WaitForChild("Shop"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Prompt = require(Shared:WaitForChild("Util"):WaitForChild("Prompt"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local FloorService = require(script.Parent.FloorService)
local ProductionService = require(script.Parent.ProductionService)
local CustomerService = require(script.Parent.CustomerService)
local NotifyService = require(script.Parent.NotifyService)

local ThiefService = {}

local ATTRIBUTE = "Thief"
local TEXTS = Gameplay.PromptTexts
local MESSAGES = Gameplay.Messages

type Source = "Table" | "Counter"

-- Prompts Steal d'un etage qui tourne
type FloorSteal = {
	owner: Player,
	anchors: { BasePart },
	prompts: { [Source]: ProximityPrompt },
}

-- "Photo" des jus vises au moment de l'appui sur E (sans le pass), en attente de l'achat
type Pending = {
	victimId: number,
	victimName: string,
	ids: { string },
	from: { Vector3 },
	models: { Model },
	at: number,
}

local passId = 0
for _, pass in Shop.Passes do
	if pass.key == "Thief" then
		passId = pass.passId
	end
end

local floors: { [Model]: FloorSteal } = {}
local pending: { [Player]: Pending } = {}
-- Dernier vol de chaque voleur, par victime (UserId) : une fois par victime par StealCooldown.
local lastSteal: { [Player]: { [number]: number } } = {}

function ThiefService.Owns(player: Player): boolean
	return player:GetAttribute(ATTRIBUTE) == true
end

local function fill(template: string, values: { [string]: string }): string
	return (string.gsub(template, "{(%w+)}", function(key: string)
		return values[key] or ""
	end))
end

---------------------------------------------------------------------------------------------
-- Vol

-- Jus du haut de la table ou du comptoir (sans les retirer : la victime ne perd rien).
local function peek(floor: Model, source: Source, max: number): ({ string }, { Vector3 }, { Model })
	if source == "Table" then
		return ProductionService.PeekJuices(floor, max)
	end
	return CustomerService.PeekCounter(floor, max)
end

-- Secondes a attendre avant de revoler cette victime (0 = possible).
local function waitLeft(player: Player, victimId: number): number
	local history = lastSteal[player]
	local last = history and history[victimId]
	if last == nil then
		return 0
	end
	return math.max(0, Gameplay.StealCooldown - (os.clock() - last))
end

-- Donne les jus au voleur et previent les deux joueurs. Renvoie le nombre donne.
local function give(player: Player, victimId: number, victimName: string, ids: { string }, from: { Vector3 }, models: { Model }): number
	local given = ProductionService.GiveJuices(player, ids, from, models)
	if given <= 0 then
		return 0
	end
	local history = lastSteal[player]
	if history == nil then
		history = {}
		lastSteal[player] = history
	end
	history[victimId] = os.clock()
	local count = tostring(given)
	NotifyService.Notify(player, fill(MESSAGES.StealDone, { n = count, name = victimName }))
	local victim = Players:GetPlayerByUserId(victimId)
	if victim then
		NotifyService.Notify(victim, fill(MESSAGES.StealVictim, { n = count, name = player.DisplayName }))
	end
	return given
end

-- Avec le pass : vol immediat (ses mains pleines).
local function stealNow(player: Player, floor: Model, victim: Player, source: Source)
	local wait = waitLeft(player, victim.UserId)
	if wait > 0 then
		NotifyService.Notify(player, fill(MESSAGES.StealWait, { name = victim.DisplayName, seconds = tostring(math.ceil(wait)) }), true)
		return
	end
	local room = ProductionService.GetHandRoom(player)
	if room <= 0 then
		NotifyService.Notify(player, MESSAGES.HandsFull, true)
		return
	end
	local ids, from, models = peek(floor, source, room)
	if #ids == 0 then
		NotifyService.Notify(player, MESSAGES.StealNothing, true)
		return
	end
	give(player, victim.UserId, victim.DisplayName, ids, from, models)
end

-- Sans le pass : photo des jus vises PUIS fenetre d'achat. La photo est prise avant la fenetre :
-- le temps de payer ne fait rien perdre.
local function offerPass(player: Player, floor: Model, victim: Player, source: Source)
	if not PlayerCheck.Cooldown(player, "ThiefPrompt", Gameplay.ThiefPromptCooldown) then
		return
	end
	if passId <= 0 then
		NotifyService.Notify(player, Upgrades.Messages.RobuxSoon)
		return
	end
	local ids, from, models = peek(floor, source, ProductionService.GetHandCapacity(player))
	if #ids == 0 then
		NotifyService.Notify(player, MESSAGES.StealNothing, true)
		return
	end
	pending[player] = {
		victimId = victim.UserId,
		victimName = victim.DisplayName,
		ids = ids,
		from = from,
		models = models,
		at = os.clock(),
	}
	PurchasePrompt.GamePass(player, passId)
end

-- Achat confirme : vol avec la photo prise a l'appui sur E (si encore valable).
local function claimPending(player: Player)
	local snap = pending[player]
	pending[player] = nil
	if snap == nil or os.clock() - snap.at > Gameplay.StealPendingSeconds then
		return
	end
	if ProductionService.GetHandRoom(player) <= 0 then
		NotifyService.Notify(player, MESSAGES.HandsFull, true)
		return
	end
	give(player, snap.victimId, snap.victimName, snap.ids, snap.from, snap.models)
end

local function onTriggered(player: Player, floor: Model, source: Source)
	local entry = floors[floor]
	if entry == nil or player.Parent ~= Players then
		return
	end
	local victim = entry.owner
	if victim == player or victim.Parent ~= Players or not FloorService.IsLive(floor) then
		return
	end
	local prompt = entry.prompts[source]
	local anchor = prompt and prompt.Parent
	if anchor == nil or not anchor:IsA("BasePart") then
		return
	end
	if not PlayerCheck.CanReach(player, anchor.Position, Gameplay.StealPromptDistance) then
		return
	end
	if not PlayerCheck.Cooldown(player, "StealPress", Gameplay.PadActionSeconds) then
		return
	end
	if ThiefService.Owns(player) then
		stealNow(player, floor, victim, source)
	else
		offerPass(player, floor, victim, source)
	end
end

---------------------------------------------------------------------------------------------
-- Prompts Steal (un par source, sur une petite piece invisible dans Dynamic de l'etage : hors des
-- groupes Ghost de l'usine a construire)

local function makeAnchor(floor: Model, zone: BasePart, name: string): BasePart?
	local dynamic = floor:FindFirstChild("Dynamic")
	if dynamic == nil then
		return nil
	end
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = zone.CFrame
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = dynamic
	return anchor
end

local function zoneOf(floor: Model, folderName: string, partName: string): BasePart?
	local folder = floor:FindFirstChild(folderName)
	local part = folder and folder:FindFirstChild(partName, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function addPrompt(entry: FloorSteal, floor: Model, source: Source, zone: BasePart?, objectText: string)
	if zone == nil then
		warn(`[ThiefService] {floor:GetFullName()} : zone des jus manquante ({source})`)
		return
	end
	local anchor = makeAnchor(floor, zone, "Steal" .. source .. "Anchor")
	if anchor == nil then
		return
	end
	table.insert(entry.anchors, anchor)
	local prompt = Prompt.Create(anchor, fill(objectText, { name = entry.owner.DisplayName }), TEXTS.StealAction, {
		name = "StealPrompt",
		distance = Gameplay.StealPromptDistance,
	})
	prompt:SetAttribute("ForOthers", true) -- PromptController : montre aux AUTRES joueurs seulement
	prompt:SetAttribute("Active", false)
	prompt.Triggered:Connect(function(who: Player)
		onTriggered(who, floor, source)
	end)
	entry.prompts[source] = prompt
end

local function startFloor(player: Player, floor: Model)
	if floors[floor] then
		return
	end
	local entry: FloorSteal = { owner = player, anchors = {}, prompts = {} }
	floors[floor] = entry
	addPrompt(entry, floor, "Table", zoneOf(floor, "Production", "JuicePile"), TEXTS.StealTableObject)
	addPrompt(entry, floor, "Counter", zoneOf(floor, "Counter", "CounterTopArea"), TEXTS.StealCounterObject)
end

local function stopFloor(floor: Model)
	local entry = floors[floor]
	if entry == nil then
		return
	end
	floors[floor] = nil
	for _, anchor in entry.anchors do
		anchor:Destroy()
	end
end

-- Active = il y a des jus a voler sur l'etage vivant de la victime.
local function refreshPrompts()
	for floor, entry in floors do
		local live = FloorService.IsLive(floor)
		Prompt.SetActive(entry.prompts.Table, live and ProductionService.GetJuiceCount(floor) > 0)
		Prompt.SetActive(entry.prompts.Counter, live and CustomerService.GetCounterCount(floor) > 0)
	end
end

---------------------------------------------------------------------------------------------
-- Possession du pass

local function grant(player: Player)
	if player.Parent == Players then
		player:SetAttribute(ATTRIBUTE, true)
	end
end

local function checkPass(player: Player)
	if passId <= 0 then
		return
	end
	if GamePass.Owns(player, passId) then -- jamais vrai pour le createur (Lib/GamePass)
		grant(player)
	end
end

function ThiefService:Init() end

function ThiefService:Start()
	FloorService.OnFloorStarted(function(player: Player, floor: Model, _index: number)
		startFloor(player, floor)
	end)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		stopFloor(floor)
	end)
	Players.PlayerAdded:Connect(checkPass)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPass, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
		lastSteal[player] = nil
	end)
	GamePass.OnPurchased(function(player: Player, id: number) -- possession reverifiee
		if passId > 0 and id == passId then
			grant(player)
			claimPending(player)
		end
	end)
	-- Pass offert (GiftService) : meme effet qu'un achat (sans vol en attente : pas d'appui sur E)
	GamePass.OnGranted(function(player: Player, id: number)
		if passId > 0 and id == passId then
			grant(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Gameplay.StealRefreshSeconds)
			local ok, err = pcall(refreshPrompts)
			if not ok then
				warn(`[ThiefService] {err}`)
			end
		end
	end)
end

return ThiefService
