--!strict
-- Panneau admin (tests rapides) : argent, fruits, jus, tas d'argent, ameliorations, etages, rebirth,
-- passes, Index, teleport et remise a zero, sur soi OU sur un autre joueur du serveur (la cible).
-- Le serveur decide qui est admin (createur du jeu, GameConfig.AdminUserIds, ou n'importe qui en
-- Studio) et pose l'attribut joueur "IsAdmin" pour que le client affiche le panneau. L'attribut sert
-- seulement a l'affichage : chaque action est reverifiee ici.
-- Doc : docs/systems/admin.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FloorsConfig = require(Config:WaitForChild("Floors"))
local Fruits = require(Config:WaitForChild("Fruits"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local CustomerService = require(script.Parent.CustomerService)
local DataService = require(script.Parent.DataService)
local FloorService = require(script.Parent.FloorService)
local IndexService = require(script.Parent.IndexService)
local LuckyCashService = require(script.Parent.LuckyCashService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerUpgradeService = require(script.Parent.PlayerUpgradeService)
local ProductionService = require(script.Parent.ProductionService)
local RebirthService = require(script.Parent.RebirthService)
local TreeService = require(script.Parent.TreeService)

local AdminService = {}

local RESET_KICK_MESSAGE = "Your progress was reset. Rejoin to start fresh!"
-- Passes basculables (attribut joueur = possede le pass ; lu par les services du jeu)
local PASS_ATTRIBUTES = { "InstantSell", "SpeedBoost", "Billboard", "Thief", "AutoCollect" }
local MAX_JUICES = 50 -- jus poses d'un coup sur le comptoir

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(GameConfig.AdminUserIds, player.UserId) ~= nil
end

-- Entier fini dans [low, high], sinon `default`.
local function intIn(value: any, low: number, high: number, default: number): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return default
	end
	return math.clamp(math.floor(value), low, high)
end

-- Etage ou se trouve la cible (index), 1 par defaut.
local function hereIndex(target: Player): number
	local _, index = FloorService.GetPlayerFloor(target)
	return index or 1
end

-- Reconstruit la tour (memes etages) pour que les modeles suivent les niveaux changes a la main,
-- puis ramene la cible a l'etage ou elle etait.
local function rebuildTower(target: Player, backTo: number): boolean
	if not FloorService.SetFloorCount(target, FloorService.GetOwnedCount(target)) then
		return false
	end
	FloorService.DebugGoTo(target, backTo)
	return true
end

local function setMoney(target: Player, amount: number): boolean
	local missing = amount - MoneyService.Get(target)
	if missing > 0 then
		return MoneyService.Add(target, missing, "admin")
	elseif missing < 0 then
		return MoneyService.TrySpend(target, -missing, "admin")
	end
	return true
end

local function addMoney(target: Player, amount: number): string?
	if MoneyService.Add(target, amount, "admin") then
		return `+{NumberFormat.Money(amount)}`
	end
	return nil
end

local function setFloorLevels(target: Player, toMax: boolean): string?
	local data = DataService.GetData(target)
	local index = hereIndex(target)
	local levels = data and DataService.FloorUpgrades(data, index)
	if data == nil or levels == nil then
		return nil
	end
	for _, upgrade in Upgrades.List do
		levels[upgrade.id] = if toMax then Upgrades.GetMaxLevel(upgrade.id, data.Rebirths) else upgrade.startLevel
	end
	if not rebuildTower(target, index) then
		return nil
	end
	return if toMax then `floor {index} upgrades maxed` else `floor {index} upgrades reset`
end

local function setFloorCount(target: Player, count: number): string?
	if FloorService.SetFloorCount(target, count) then
		return `{FloorService.GetOwnedCount(target)} floors`
	end
	return nil
end

-- Action -> effet sur la cible. Renvoie le message pour l'admin (nil = rien fait).
-- `value` = nombre du champ "Value" du panneau (deja verifie : nombre fini ou nil).
type Action = (admin: Player, target: Player, value: number?) -> string?

local ACTIONS: { [string]: Action } = {
	-- Argent
	Money1K = function(_, target)
		return addMoney(target, 1_000)
	end,
	Money1M = function(_, target)
		return addMoney(target, 1_000_000)
	end,
	Money1B = function(_, target)
		return addMoney(target, 1_000_000_000)
	end,
	MoneyN = function(_, target, value)
		return addMoney(target, intIn(value, 0, GameConfig.MaxMoney, 0))
	end,
	MaxMoney = function(_, target)
		return if setMoney(target, GameConfig.MaxMoney) then "max money" else nil
	end,
	ZeroMoney = function(_, target)
		return if setMoney(target, 0) then "money = 0" else nil
	end,

	-- Fruits, jus, tas d'argent (etage ou se trouve la cible)
	Drop10 = function(_, target)
		return `{TreeService.DebugDrop(target, 10)} fruits dropped`
	end,
	DropN = function(_, target, value)
		return `{TreeService.DebugDrop(target, intIn(value, 1, 1000, 10))} fruits dropped`
	end,
	FillBins = function(_, target)
		return if ProductionService.DebugAction(target, "FillBins") then "20 fruits in bins" else nil
	end,
	Juices = function(_, target, value)
		local floor, index = FloorService.GetPlayerFloor(target)
		if floor == nil or index == nil then
			floor, index = FloorService.GetFloor(target, 1), 1
		end
		if floor == nil or index == nil then
			return nil
		end
		local id = Fruits.OfFloor(index)[1].id
		local added = CustomerService.AddToCounter(floor, table.create(intIn(value, 1, MAX_JUICES, 10), id))
		return `{added} juices on the counter`
	end,
	PileCash = function(_, target, value)
		local cash = CustomerService.DebugAction(target, "AddCash", intIn(value, 1, GameConfig.MaxMoney, 10_000))
		return if type(cash) == "number" then `cash pile: {NumberFormat.Money(cash)}` else nil
	end,
	CollectPile = function(_, target)
		return if CustomerService.DebugAction(target, "Collect") then "cash pile collected" else nil
	end,

	-- Ameliorations
	MaxFloorUp = function(_, target)
		return setFloorLevels(target, true)
	end,
	ResetFloorUp = function(_, target)
		return setFloorLevels(target, false)
	end,
	MaxPlayerUp = function(_, target)
		return if PlayerUpgradeService.AdminSetAll(target, true) then "player upgrades maxed" else nil
	end,
	ResetPlayerUp = function(_, target)
		return if PlayerUpgradeService.AdminSetAll(target, false) then "player upgrades reset" else nil
	end,
	MaxTower = function(_, target)
		local data = DataService.GetData(target)
		if data == nil then
			return nil
		end
		for id in FloorsConfig.TowerUpgradeDefaults do
			data.TowerUpgrades[id] = FloorsConfig.TowerUpgradeMaxLevel
		end
		return if rebuildTower(target, hereIndex(target)) then "elevator maxed" else nil
	end,

	-- Etages (ecrivent la sauvegarde ; les etages retires sont perdus)
	AddFloor = function(_, target)
		return setFloorCount(target, FloorService.GetOwnedCount(target) + 1)
	end,
	RemoveFloor = function(_, target)
		return setFloorCount(target, FloorService.GetOwnedCount(target) - 1)
	end,
	AllFloors = function(_, target)
		return setFloorCount(target, FloorsConfig.MaxFloors)
	end,
	ResetFloors = function(_, target)
		return setFloorCount(target, 1)
	end,
	SetFloorsN = function(_, target, value)
		return setFloorCount(target, intIn(value, 1, FloorsConfig.MaxFloors, 1))
	end,
	GoToFloorN = function(_, target, value)
		local n = intIn(value, 1, FloorsConfig.MaxFloors, 1)
		return if FloorService.DebugGoTo(target, n) then `teleported to floor {n}` else nil
	end,

	-- Rebirth
	Rebirth = function(_, target)
		return if RebirthService.ForceRebirth(target) then "rebirth done" else nil
	end,
	RebirthKeep = function(_, target)
		return if RebirthService.ForceRebirth(target, true) then "rebirth done (cash kept)" else nil
	end,
	SetRebirthsN = function(_, target, value)
		local n = intIn(value, 0, GameConfig.MaxRebirths, 0)
		return if RebirthService.DebugSet(target, n) then `rebirths = {n}` else nil
	end,
	LuckyCash = function(_, target)
		return if LuckyCashService.DebugGrant(target) then "lucky cash granted" else nil
	end,

	-- Passes (bascule ON / OFF, sans achat)
	TogglePass = function(_, target, value)
		local key = PASS_ATTRIBUTES[intIn(value, 1, #PASS_ATTRIBUTES, 1)]
		local owned = target:GetAttribute(key) == true
		target:SetAttribute(key, if owned then nil else true)
		return `{key} {if owned then "OFF" else "ON"}`
	end,
	ToggleMaster = function(_, target)
		local owned = RebirthService.OwnsMaster(target)
		RebirthService.DebugSetMaster(target, not owned)
		return `Rebirth Master {if owned then "OFF" else "ON"}`
	end,

	-- Index
	DiscoverAll = function(_, target)
		local data = DataService.GetData(target)
		if data == nil then
			return nil
		end
		for _, fruit in Fruits.List do
			data.DiscoveredFruits[fruit.id] = true
		end
		IndexService.Sync(target)
		return "all fruits discovered"
	end,
	ResetIndex = function(_, target)
		local data = DataService.GetData(target)
		if data == nil then
			return nil
		end
		table.clear(data.DiscoveredFruits)
		table.clear(data.ClaimedFruits)
		data.DiscoveredFruits[Fruits.List[1].id] = true
		IndexService.Sync(target)
		return "index reset"
	end,

	-- Joueur
	TpTo = function(admin, target)
		local from, to = PlayerCheck.GetRoot(admin), PlayerCheck.GetRoot(target)
		if from == nil or to == nil or admin == target then
			return nil
		end
		from.CFrame = to.CFrame * CFrame.new(0, 0, 4)
		return "teleported"
	end,
	Bring = function(admin, target)
		local from, to = PlayerCheck.GetRoot(target), PlayerCheck.GetRoot(admin)
		if from == nil or to == nil or admin == target then
			return nil
		end
		from.CFrame = to.CFrame * CFrame.new(0, 0, -4)
		return "brought"
	end,
	Respawn = function(_, target)
		target:LoadCharacter()
		return "respawned"
	end,
	ResetAll = function(_, target)
		if DataService.ResetOnLeave(target) then
			target:Kick(RESET_KICK_MESSAGE)
			return "save reset (kicked)"
		end
		return nil
	end,
}

local function onAction(admin: Player, action: any, targetId: any, value: any)
	if not isAdmin(admin) then
		warn(`[AdminService] Action admin refusee pour {admin.UserId}`)
		return
	end
	if type(action) ~= "string" or ACTIONS[action] == nil then
		return
	end
	if not PlayerCheck.Cooldown(admin, "Admin", GameConfig.AdminCooldownSeconds) then
		return
	end
	-- Cible : un joueur present sur le serveur (soi-meme par defaut)
	local target = admin
	if type(targetId) == "number" then
		local found = Players:GetPlayerByUserId(targetId)
		if found == nil then
			NotifyService.Notify(admin, "Admin: player left", true)
			return
		end
		target = found
	end
	local number = if type(value) == "number" and value == value and math.abs(value) ~= math.huge then value else nil
	local ok, result = pcall(ACTIONS[action], admin, target, number)
	if not ok then
		warn(`[AdminService] {action} a echoue : {result}`)
		NotifyService.Notify(admin, `Admin: {action} failed`, true)
	elseif result == nil then
		NotifyService.Notify(admin, `Admin: {action} did nothing`, true)
	elseif target ~= admin and admin.Parent == Players then
		NotifyService.Notify(admin, `Admin ({target.Name}): {result}`)
	else
		NotifyService.Notify(admin, `Admin: {result}`)
	end
	print(`[AdminService] {admin.Name} -> {target.Name} : {action} ({tostring(number)})`)
end

local function onPlayerAdded(player: Player)
	if isAdmin(player) then
		player:SetAttribute("IsAdmin", true)
	end
end

function AdminService:Init()
	Remotes.GetServerEvent("AdminAction").OnServerEvent:Connect(onAction)
end

function AdminService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return AdminService
