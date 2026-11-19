--!strict
-- Seul module qui modifie l'argent du joueur (Data.Money). Argent toujours entier et >= 0.
-- Aucun remote : le client lit leaderstats.Cash. Doc : docs/systems/argent.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local MoneyService = {}

local function isValidAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount -- pas NaN
		and math.abs(amount) ~= math.huge
		and amount >= 0
		and amount % 1 == 0
end

-- Cree le classement tout de suite (le HUD l'attend), rempli quand la sauvegarde est chargee.
local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
end

local function syncLeaderstats(player: Player)
	local data = DataService.GetData(player)
	local folder = player:FindFirstChild("leaderstats")
	if data == nil or folder == nil then
		return
	end
	local cash = folder:FindFirstChild("Cash") :: IntValue?
	local rebirths = folder:FindFirstChild("Rebirths") :: IntValue?
	if cash then
		cash.Value = data.Money
	end
	if rebirths then
		rebirths.Value = data.Rebirths
	end
end

function MoneyService:Init() end

function MoneyService:Start()
	Players.PlayerAdded:Connect(createLeaderstats)
	for _, player in Players:GetPlayers() do
		createLeaderstats(player)
	end
	DataService.OnPlayerLoaded(function(player: Player)
		createLeaderstats(player)
		syncLeaderstats(player)
	end)
end

-- Argent actuel (0 si la sauvegarde n'est pas chargee).
function MoneyService.Get(player: Player): number
	local data = DataService.GetData(player)
	return if data then data.Money else 0
end

-- Ajoute `amount` (entier >= 0). `reason` sert aux logs et plus tard aux analytics.
-- Renvoie faux si la sauvegarde n'est pas chargee ou si le montant est invalide.
function MoneyService.Add(player: Player, amount: number, reason: string): boolean
	if not isValidAmount(amount) then
		warn(`[MoneyService] Montant refuse pour Add ({tostring(amount)}, {reason})`)
		return false
	end
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	-- Plafond (GameConfig.MaxMoney) : garde des entiers exacts.
	data.Money = math.min(data.Money + amount, GameConfig.MaxMoney)
	syncLeaderstats(player)
	return true
end

-- Retire `price` seulement si le joueur a assez. Renvoie vrai si c'est paye.
function MoneyService.TrySpend(player: Player, price: number, reason: string): boolean
	if not isValidAmount(price) then
		warn(`[MoneyService] Prix refuse pour TrySpend ({tostring(price)}, {reason})`)
		return false
	end
	local data = DataService.GetData(player)
	if data == nil or data.Money < price then
		return false
	end
	data.Money -= price
	syncLeaderstats(player)
	return true
end

return MoneyService
