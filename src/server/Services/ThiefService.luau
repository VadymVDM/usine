--!strict
-- Pass Robux "Thief" (Shop.Passes "Thief", 149 R$). Refait le 2026-11-27 (demande utilisateur) :
-- touche E "Steal" (ProximityPrompt) sur les jus d'une AUTRE base : table a jus (Production.JuicePile)
-- et comptoir (Counter.CounterTopArea). Le prompt n'apparait que chez les AUTRES joueurs
-- (attribut "ForOthers", PromptController), et seulement quand il y a des jus a voler sur l'etage
-- vivant de la victime (attribut "Active").
--   * Avec le pass : E = ses mains pleines de jus (gobelets du haut), SANS limite de temps (pass
--     "UNLIMITED", demande utilisateur du 2026-11-27 : plus de delai de 60 s par victime) ; seules
--     les mains pleines et l'anti-spam d'appui limitent. La victime ne perd rien ("assurance",
--     message) et seul le voleur voit les gobelets disparaitre (Feedback "StolenCups").
--   * (Jusqu'au 2026-11-27) Sans le pass : E = fenetre d'achat du pass. Les jus vises sont "photographies" A
--     L'APPUI SUR E (ids, positions, modeles) : si l'achat aboutit (possession reverifiee par
--     Lib/GamePass) dans les Gameplay.StealPendingSeconds, le voleur recoit CES jus, meme si la table
--     a ete videe pendant qu'il payait.
--   * passId = 0 (pass pas cree) : message "Robux purchases: coming soon!".
-- 2026-11-27 (demande utilisateur) : VOL A L'UNITE. Le pass n'est plus vendu en jeu (Shop "hidden").
--   * Avec le pass (deja achete / offert) : inchange, vol gratuit sans limite.
--   * Sans le pass : 1er vol GRATUIT a chaque serveur (memoire, rien de sauvegarde), puis chaque vol
--     = produit Robux Shop.Steal (19 R$). Meme "photo" des jus a l'appui sur E ; le recu
--     (ReceiptService) donne ces jus. Recu sans photo valable ou mains pleines : le vol paye devient
--     un credit (prochain E gratuit), jamais de Robux perdus. PurchaseId note une seule fois
--     (DataService.GrantPurchaseOnce).
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
local DataService = require(script.Parent.DataService)
local ReceiptService = require(script.Parent.ReceiptService)

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

local STEAL = Shop.Steal
local RECEIPT_WAIT_SECONDS = 15 -- recu arrive pendant le chargement du joueur : attendre ses donnees

local floors: { [Model]: FloorSteal } = {}
local pending: { [Player]: Pending } = {}
-- Vols gratuits restants sur ce serveur, par compte (UserId : quitter / revenir ne redonne pas le
-- vol gratuit ; un vol paye pas encore utilise reste au retour sur ce serveur). Jamais vide : petit.
local freeSteals: { [number]: number } = {}

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

-- Donne les jus au voleur et previent les deux joueurs. Renvoie le nombre donne.
local function give(player: Player, victimId: number, victimName: string, ids: { string }, from: { Vector3 }, models: { Model }): number
	local given = ProductionService.GiveJuices(player, ids, from, models)
	if given <= 0 then
		return 0
	end
	local count = tostring(given)
	NotifyService.Notify(player, fill(MESSAGES.StealDone, { n = count, name = victimName }))
	local victim = Players:GetPlayerByUserId(victimId)
	if victim then
		NotifyService.Notify(victim, fill(MESSAGES.StealVictim, { n = count, name = player.DisplayName }))
	end
	return given
end

-- Vol immediat (ses mains pleines) : avec le pass, ou vol gratuit / deja paye. Renvoie le nombre vole.
local function stealNow(player: Player, floor: Model, victim: Player, source: Source): number
	local room = ProductionService.GetHandRoom(player)
	if room <= 0 then
		NotifyService.Notify(player, MESSAGES.HandsFull, true)
		return 0
	end
	local ids, from, models = peek(floor, source, room)
	if #ids == 0 then
		NotifyService.Notify(player, MESSAGES.StealNothing, true)
		return 0
	end
	return give(player, victim.UserId, victim.DisplayName, ids, from, models)
end

-- Sans le pass, sans vol gratuit : photo des jus vises PUIS fenetre d'achat du vol (19 R$). La photo
-- est prise avant la fenetre : le temps de payer ne fait rien perdre.
local function offerSteal(player: Player, floor: Model, victim: Player, source: Source)
	if not PlayerCheck.Cooldown(player, "ThiefPrompt", Gameplay.ThiefPromptCooldown) then
		return
	end
	if STEAL.productId <= 0 then
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
	PurchasePrompt.Product(player, STEAL.productId)
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
		return
	end
	local left = freeSteals[player.UserId] or 0
	if left > 0 then
		if stealNow(player, floor, victim, source) > 0 then
			freeSteals[player.UserId] = left - 1
			if left - 1 <= 0 then
				NotifyService.Notify(player, fill(MESSAGES.StealFree, { price = tostring(STEAL.price) }))
			end
		end
		return
	end
	offerSteal(player, floor, victim, source)
end

---------------------------------------------------------------------------------------------
-- Recu du vol a l'unite (Shop.Steal) : donne les jus de la photo, sinon un vol gratuit en reserve.

local function grantSteal(player: Player, purchaseId: string): boolean
	local deadline = os.clock() + RECEIPT_WAIT_SECONDS
	while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
	end
	local stolen = 0
	local applied = false
	local granted = DataService.GrantPurchaseOnce(player, purchaseId, function(_data): boolean
		applied = true
		local snap = pending[player]
		pending[player] = nil
		if snap and os.clock() - snap.at <= Gameplay.StealPendingSeconds then
			stolen = give(player, snap.victimId, snap.victimName, snap.ids, snap.from, snap.models)
		end
		if stolen <= 0 then
			freeSteals[player.UserId] = (freeSteals[player.UserId] or 0) + 1 -- vol paye garde pour le prochain E
		end
		return true
	end)
	if applied and stolen <= 0 then
		NotifyService.Notify(player, MESSAGES.StealCredit)
	end
	return granted
end

local function receiptHandler(receipt: ReceiptService.Receipt): boolean
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return false -- joueur parti : Roblox redonnera le recu
	end
	return grantSteal(player, receipt.PurchaseId)
end

-- Test Studio : simule un achat paye du vol a l'unite.
function ThiefService.DebugGrantSteal(player: Player): boolean
	return grantSteal(player, "debug-steal-" .. tostring(os.clock()))
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

function ThiefService:Init()
	if STEAL.productId > 0 then
		ReceiptService.Register(STEAL.productId, receiptHandler)
	end
end

local function onPlayerAdded(player: Player)
	if freeSteals[player.UserId] == nil then
		freeSteals[player.UserId] = 1 -- 1er vol gratuit sur ce serveur
	end
	checkPass(player)
end

function ThiefService:Start()
	FloorService.OnFloorStarted(function(player: Player, floor: Model, _index: number)
		startFloor(player, floor)
	end)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		stopFloor(floor)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
	GamePass.OnPurchased(function(player: Player, id: number) -- possession reverifiee
		if passId > 0 and id == passId then
			grant(player)
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
