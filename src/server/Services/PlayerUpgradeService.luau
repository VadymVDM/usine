--!strict
-- Ameliorations du joueur (menu Upgrade du HUD) : vitesse de marche, fruits et jus portes.
-- Seul module qui ecrit Data.PlayerUpgrades. Valeurs et prix : Config/PlayerUpgrades.
-- Remote BuyPlayerUpgrade (client -> serveur, id) : id connu (chaine), sauvegarde chargee, delai
-- PlayerUpgrades.BuyCooldownSeconds, niveau < max. 3 premiers achats : argent du jeu (MoneyService.TrySpend,
-- prix lu ici dans la config). Achats suivants : le serveur ouvre la fenetre d'achat du Developer
-- Product (productId 0 : "coming soon") ; le niveau n'est donne qu'a la
-- reception du recu (ReceiptService -> DataService.GrantPurchaseOnce : une seule fois par achat).
-- Le client lit les niveaux dans les attributs joueur "PUp_<id>" (rien d'autre n'est envoye).
-- Effets : Humanoid.WalkSpeed a chaque apparition du personnage et apres un achat ; capacites lues
-- par ProductionService (PlayerUpgradeService.GetValue), attributs InvMax / HandMax remis a jour ici.
-- Boost route : sur la route et les trottoirs (Workspace.Map.Road), vitesse x Gameplay.RoadSpeedMultiplier (boucle serveur).
-- Vitesse finale plafonnee a Gameplay.MaxWalkSpeed. (Le pass "Waiter Speed x10" n'accelere plus le
-- joueur depuis le 2026-11-20 : il accelere le Waiter, WorkerService.)
-- Doc : docs/systems/ameliorations-joueur.md

local PurchasePrompt = require(script.Parent.Parent.Lib.PurchasePrompt)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PlayerUpgrades = require(Config:WaitForChild("PlayerUpgrades"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))

local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local Perks = require(script.Parent.Parent.Lib.Perks)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NotifyService = require(script.Parent.NotifyService)
local ReceiptService = require(script.Parent.ReceiptService)

local PlayerUpgradeService = {}

local characterConnections: { [Player]: RBXScriptConnection } = {}
local onRoad: { [Player]: true } = {} -- joueurs dont le personnage est sur la route (boost vitesse)

-- Niveau d'une amelioration (1 si la sauvegarde n'est pas chargee).
function PlayerUpgradeService.GetLevel(player: Player, id: string): number
	local data = DataService.GetData(player)
	local level = data and data.PlayerUpgrades and data.PlayerUpgrades[id]
	return if type(level) == "number" then level else 1
end

-- Effet actuel (vitesse, nombre de fruits ou de jus portes au maximum).
function PlayerUpgradeService.GetValue(player: Player, id: string): number
	return PlayerUpgrades.GetValue(id, PlayerUpgradeService.GetLevel(player, id))
end

local function applyWalkSpeed(player: Player, character: Model?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Pass Speed Master (Lib/Perks) : marche x2
		local speed = PlayerUpgradeService.GetValue(player, "WalkSpeed") * Perks.WalkSpeedMultiplier(player)
		if onRoad[player] then
			speed *= Gameplay.RoadSpeedMultiplier
		end
		humanoid.WalkSpeed = math.min(speed, Gameplay.MaxWalkSpeed)
	end
end

-- Le personnage est-il sur une des pieces de la route (asphalte, trottoirs, bordures) ?
-- (position du HumanoidRootPart dans le repere de chaque piece)
local function isOnRoad(parts: { BasePart }, character: Model?): boolean
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	for _, part in parts do
		local localPos = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		if
			math.abs(localPos.X) <= half.X
			and math.abs(localPos.Z) <= half.Z
			and localPos.Y >= -half.Y
			and localPos.Y <= half.Y + Gameplay.RoadMaxHeight
		then
			return true
		end
	end
	return false
end

-- Pieces de Workspace.Map.Road qui donnent le boost (noms dans Gameplay.RoadPartNames).
local function getRoadParts(): { BasePart }
	local parts = {}
	local map = workspace:FindFirstChild("Map")
	local road = map and map:FindFirstChild("Road")
	if road then
		for _, child in road:GetChildren() do
			if child:IsA("BasePart") and table.find(Gameplay.RoadPartNames, child.Name) then
				table.insert(parts, child)
			end
		end
	end
	return parts
end

-- Boucle serveur : met a jour onRoad et la vitesse quand le joueur entre / sort de la route.
local function roadLoop()
	while true do
		task.wait(Gameplay.RoadCheckSeconds)
		local parts = getRoadParts()
		if #parts > 0 then
			for _, player in Players:GetPlayers() do
				local now = isOnRoad(parts, player.Character)
				if now ~= (onRoad[player] == true) then
					onRoad[player] = if now then true else nil
					applyWalkSpeed(player, player.Character)
				end
			end
		end
	end
end

-- Attributs lus par le client (menu) et par TrayController / HandStackController (InvMax, HandMax).
local function sync(player: Player)
	if player.Parent ~= Players then
		return
	end
	for _, upgrade in PlayerUpgrades.List do
		player:SetAttribute(PlayerUpgrades.AttributePrefix .. upgrade.id, PlayerUpgradeService.GetLevel(player, upgrade.id))
	end
	player:SetAttribute("InvMax", PlayerUpgradeService.GetValue(player, "FruitCarry"))
	player:SetAttribute("HandMax", PlayerUpgradeService.GetValue(player, "JuiceCarry"))
	applyWalkSpeed(player, player.Character)
end

-- Panneau admin : toutes les ameliorations du joueur au max (toMax) ou au niveau 1. Ecrit la sauvegarde.
function PlayerUpgradeService.AdminSetAll(player: Player, toMax: boolean): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	for _, upgrade in PlayerUpgrades.List do
		data.PlayerUpgrades[upgrade.id] = if toMax then upgrade.maxLevel else 1
	end
	sync(player)
	return true
end

local function onBuy(player: Player, id: any)
	if typeof(id) ~= "string" or PlayerUpgrades.ById[id] == nil then
		return
	end
	if not PlayerCheck.Cooldown(player, "BuyPlayerUpgrade", PlayerUpgrades.BuyCooldownSeconds) then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	local upgrade = PlayerUpgrades.ById[id]
	local level = PlayerUpgradeService.GetLevel(player, id)
	if level >= upgrade.maxLevel then
		NotifyService.Notify(player, PlayerUpgrades.Messages.MaxLevel, true)
		sync(player)
		return
	end
	local cashPrice = PlayerUpgrades.GetCashPrice(id, level)
	if cashPrice then
		if not MoneyService.TrySpend(player, cashPrice, "PlayerUpgrade:" .. id) then
			NotifyService.Notify(player, PlayerUpgrades.Messages.NotEnoughMoney, true)
			return
		end
		data.PlayerUpgrades[id] = level + 1
		sync(player)
		return
	end
	if upgrade.productId <= 0 then
		NotifyService.Notify(player, PlayerUpgrades.Messages.ComingSoon)
		return
	end
	PurchasePrompt.Product(player, upgrade.productId)
end

-- Recu Robux d'une amelioration : +1 niveau, une seule fois par achat (PurchaseId garde dans la
-- sauvegarde). Deja au max (deux achats tres rapproches) : le recu est accepte quand meme, rien
-- n'est donne (avertissement dans la sortie). Joueur parti : false, Roblox redonnera le recu.
local function makeReceiptHandler(id: string): ReceiptService.Handler
	return function(receipt: ReceiptService.Receipt): boolean
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if player == nil then
			return false
		end
		local deadline = os.clock() + PlayerUpgrades.ReceiptWaitSeconds
		while DataService.GetData(player) == nil and player.Parent == Players and os.clock() < deadline do
			task.wait(0.25)
		end
		local granted = DataService.GrantPurchaseOnce(player, receipt.PurchaseId, function(data): boolean
			local upgrade = PlayerUpgrades.ById[id]
			local level = data.PlayerUpgrades[id] or 1
			if level >= upgrade.maxLevel then
				warn(`[PlayerUpgradeService] Achat {receipt.PurchaseId} recu alors que {id} est deja au max`)
				return true
			end
			data.PlayerUpgrades[id] = level + 1
			return true
		end)
		sync(player)
		return granted
	end
end

function PlayerUpgradeService:Init()
	Remotes.GetServerEvent("BuyPlayerUpgrade")
	-- Un handler par produit deja cree sur Roblox (productId > 0)
	for _, upgrade in PlayerUpgrades.List do
		if upgrade.productId > 0 then
			ReceiptService.Register(upgrade.productId, makeReceiptHandler(upgrade.id))
		end
	end
end

function PlayerUpgradeService:Start()
	Remotes.GetServerEvent("BuyPlayerUpgrade").OnServerEvent:Connect(onBuy)
	local function watch(player: Player)
		if characterConnections[player] then
			return
		end
		-- Pass Speed Master donne ou retire (RobuxShopService) : vitesse remise a jour
		player:GetAttributeChangedSignal("SpeedMaster"):Connect(function()
			applyWalkSpeed(player, player.Character)
		end)
		characterConnections[player] = player.CharacterAdded:Connect(function(character)
			-- Le Humanoid peut arriver juste apres le modele
			if character:WaitForChild("Humanoid", 10) then
				applyWalkSpeed(player, character)
			end
		end)
	end
	DataService.OnPlayerLoaded(function(player: Player)
		watch(player)
		sync(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.GetData(player) then
			watch(player)
			sync(player)
		end
	end
	task.spawn(roadLoop)
	Players.PlayerRemoving:Connect(function(player)
		onRoad[player] = nil
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
			characterConnections[player] = nil
		end
	end)
end

return PlayerUpgradeService
