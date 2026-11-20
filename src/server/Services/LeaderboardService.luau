--!strict
-- Classements mondiaux (2 murs-ecrans aux bouts de la route, Workspace.Map.Leaderboards) :
--   * Money      : argent actuel (Data.Money, MoneyService en reste le seul proprietaire) ;
--   * JuicesSold : jus vendus depuis toujours (Data.JuicesSold, proprietaire : ce service) ;
--   * TimePlayed : secondes de jeu depuis toujours (Data.TimePlayed, proprietaire : ce service) ;
--   * RobuxSpent : Robux payes pour tous les achats (DataStore a part, rempli a chaque recu
--     accorde via ReceiptService.OnGranted, un meme achat jamais compte deux fois).
-- Ecriture : chaque joueur toutes les WriteSeconds (et a son depart) dans un OrderedDataStore par
-- classement. Lecture : les 4 classements toutes les RefreshSeconds, textes ecrits par le serveur
-- dans les lignes construites par tools/build-map/08-leaderboards. Aucun remote.
-- Doc : docs/systems/classements.md

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Leaderboards = require(Config:WaitForChild("Leaderboards"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Donations = require(Config:WaitForChild("Donations"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local DataService = require(script.Parent.DataService)
local ReceiptService = require(script.Parent.ReceiptService)

local HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60"

type Entry = { userId: number, value: number }
type Receipt = ReceiptService.Receipt

local LeaderboardService = {}

local ordered: { [string]: OrderedDataStore } = {}
local robuxStore: DataStore? = nil
local entries: { [string]: { Entry } } = {}
local names: { [number]: string } = {}
local lastWritten: { [Player]: { [string]: number } } = {}
local timeMark: { [Player]: number } = {} -- os.clock du dernier ajout au temps de jeu
local pendingRobux: { [number]: number } = {} -- total Robux pas encore ecrit au classement

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function formatValue(kind: Leaderboards.Kind, value: number): string
	if kind == "Money" then
		return "$" .. NumberFormat.Abbreviate(value)
	elseif kind == "Time" then
		return Leaderboards.FormatTime(value)
	elseif kind == "Robux" then
		return "R$" .. Donations.Format(value)
	end
	return NumberFormat.Abbreviate(value)
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		names[userId] = inServer.Name
		return inServer.Name
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and type(name) == "string" then
		names[userId] = name
		return name
	end
	return "Player"
end

---------------------------------------------------------------------------------------------
-- Statistiques du joueur

-- Ajoute le temps ecoule depuis le dernier passage au temps de jeu sauvegarde.
local function accountTime(player: Player)
	local data = DataService.GetData(player)
	local mark = timeMark[player]
	local now = os.clock()
	timeMark[player] = now
	if data == nil or mark == nil then
		return
	end
	data.TimePlayed = math.min(data.TimePlayed + (now - mark), GameConfig.MaxMoney)
end

-- Valeurs a ecrire maintenant (lues tout de suite : la sauvegarde peut partir juste apres).
local function snapshot(player: Player): { [string]: number }?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	return {
		Money = math.floor(data.Money),
		JuicesSold = math.floor(data.JuicesSold),
		TimePlayed = math.floor(data.TimePlayed),
	}
end

local function writeValues(player: Player, userId: number, values: { [string]: number })
	if userId <= 0 then
		return -- joueurs de test de Studio (Local Server) : pas de classement
	end
	local written = lastWritten[player] or {}
	for id, value in values do
		local store = ordered[id]
		if store == nil or written[id] == value or value <= 0 then
			continue
		end
		local ok, err = pcall(store.SetAsync, store, tostring(userId), value)
		if ok then
			written[id] = value
		else
			warn(`[LeaderboardService] {id} non ecrit pour {userId} : {err}`)
		end
	end
	if player.Parent ~= nil then
		lastWritten[player] = written
	end
end

local function writePlayer(player: Player)
	accountTime(player)
	local values = snapshot(player)
	if values then
		writeValues(player, player.UserId, values)
	end
end

-- Jus vendus (appele par CustomerService a chaque vente, aussi les ventes "en nombres").
function LeaderboardService.AddJuicesSold(player: Player, count: number)
	if not isFiniteNumber(count) or count <= 0 then
		return
	end
	local data = DataService.GetData(player)
	if data then
		data.JuicesSold = math.min(data.JuicesSold + count, GameConfig.MaxMoney)
	end
end

---------------------------------------------------------------------------------------------
-- Robux payes

-- Classement Robux : jamais plus bas que le total sauvegarde (deux serveurs en meme temps).
local function writeRobuxRanking(userId: number, total: number): boolean
	local store = ordered.RobuxSpent
	if store == nil then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(userId), function(old: any)
			local current = if isFiniteNumber(old) then old else 0
			if current >= total then
				return nil
			end
			return math.floor(total)
		end)
	end)
	if not ok then
		warn(`[LeaderboardService] Classement Robux non ecrit pour {userId} : {err}`)
	end
	return ok
end

local function onPurchaseGranted(receipt: Receipt): boolean
	local spent = receipt.CurrencySpent
	if not isFiniteNumber(spent) or spent <= 0 then
		return true -- rien a compter (ex. achat de test gratuit dans Studio)
	end
	local dataStore = robuxStore
	if dataStore == nil then
		warn("[LeaderboardService] DataStore indisponible : Robux payes non comptes")
		return true -- ne jamais bloquer un achat pour une statistique
	end
	local userId = receipt.PlayerId
	local newTotal: number? = nil
	local ok, err = pcall(function()
		dataStore:UpdateAsync("u" .. userId, function(old: any)
			local data = if type(old) == "table" then old else {}
			local receipts: { string } = {}
			if type(data.Receipts) == "table" then
				for _, id in data.Receipts do
					if type(id) == "string" then
						table.insert(receipts, id)
					end
				end
			end
			local current = if isFiniteNumber(data.Total) and data.Total > 0 then math.floor(data.Total) else 0
			if table.find(receipts, receipt.PurchaseId) then
				newTotal = current
				return nil -- deja compte
			end
			table.insert(receipts, receipt.PurchaseId)
			while #receipts > Leaderboards.ReceiptsKept do
				table.remove(receipts, 1)
			end
			newTotal = current + math.floor(spent)
			return { Total = newTotal, Receipts = receipts }
		end)
	end)
	if not ok or newTotal == nil then
		warn(`[LeaderboardService] Robux payes de {userId} non enregistres (recu redonne par Roblox) : {err}`)
		return false
	end
	-- Le total est sauvegarde : le classement peut etre reessaye plus tard.
	if not writeRobuxRanking(userId, newTotal :: number) then
		pendingRobux[userId] = newTotal :: number
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Panneaux

local function renderBoard(board: Leaderboards.Board)
	local folder = workspace:FindFirstChild("Map")
	local walls = folder and folder:FindFirstChild("Leaderboards")
	local wall = walls and walls:FindFirstChild(board.wall)
	local column = wall and wall:FindFirstChild(board.id, true)
	local rows = column and column:FindFirstChild("Rows")
	if rows == nil then
		return
	end
	local list = entries[board.id] or {}
	for i = 1, Leaderboards.Rows do
		local row = rows:FindFirstChild("Row" .. i)
		if row == nil then
			continue
		end
		local entry = list[i]
		local nameLabel = row:FindFirstChild("PlayerName")
		local valueLabel = row:FindFirstChild("Value")
		local avatar = row:FindFirstChild("Avatar")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = if entry then nameOf(entry.userId) elseif i == 1 then Leaderboards.EmptyRow else "---"
		end
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = if entry then formatValue(board.kind, entry.value) else ""
		end
		if avatar and avatar:IsA("ImageLabel") then
			avatar.Image = if entry then string.format(HEADSHOT, entry.userId) else ""
			avatar.Visible = entry ~= nil
		end
	end
end

local function refresh()
	for userId, total in pendingRobux do
		if writeRobuxRanking(userId, total) then
			pendingRobux[userId] = nil
		end
	end
	for _, board in Leaderboards.Boards do
		local store = ordered[board.id]
		if store == nil then
			renderBoard(board)
			continue
		end
		local ok, result = pcall(function()
			return store:GetSortedAsync(false, Leaderboards.Rows):GetCurrentPage()
		end)
		if not ok then
			warn(`[LeaderboardService] Lecture du classement {board.id} impossible : {result}`)
			continue
		end
		local fresh: { Entry } = {}
		for _, item in result :: { any } do
			local userId = tonumber(item.key)
			local value = item.value
			if userId and userId > 0 and isFiniteNumber(value) and value > 0 then
				table.insert(fresh, { userId = userId, value = value })
				nameOf(userId) -- prepare le nom (appel web) hors du rendu
			end
		end
		entries[board.id] = fresh
		renderBoard(board)
	end
end

---------------------------------------------------------------------------------------------

function LeaderboardService:Init()
	ReceiptService.OnGranted(onPurchaseGranted)
	local ok, err = pcall(function()
		for _, board in Leaderboards.Boards do
			ordered[board.id] = DataStoreService:GetOrderedDataStore(board.storeName)
		end
		robuxStore = DataStoreService:GetDataStore(Leaderboards.RobuxStoreName)
	end)
	if not ok then
		warn(`[LeaderboardService] DataStore indisponible : {err}`)
	end
end

function LeaderboardService:Start()
	DataService.OnPlayerLoaded(function(player: Player)
		timeMark[player] = os.clock()
	end)
	DataService.OnPlayerRemoving(function(player: Player)
		accountTime(player) -- avant la derniere sauvegarde
		local values = snapshot(player)
		local userId = player.UserId
		timeMark[player] = nil
		if values then
			task.spawn(writeValues, player, userId, values)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			lastWritten[player] = nil
			timeMark[player] = nil
		end)
	end)

	-- Ecriture des joueurs, etalee : un joueur toutes les WriteSeconds / nombre de joueurs
	task.spawn(function()
		while true do
			local players = Players:GetPlayers()
			local pause = Leaderboards.WriteSeconds / math.max(#players, 1)
			if #players == 0 then
				task.wait(pause)
			end
			for _, player in players do
				if player.Parent ~= nil then
					writePlayer(player)
				end
				task.wait(pause)
			end
		end
	end)

	-- Lecture des classements
	task.spawn(function()
		local folder = workspace:WaitForChild("Map", 30)
		if folder == nil or folder:WaitForChild("Leaderboards", 10) == nil then
			warn("[LeaderboardService] Workspace.Map.Leaderboards manquant (lancer tools/build-map/08-leaderboards)")
		end
		task.wait(5) -- laisse les premiers joueurs arriver
		while true do
			refresh()
			task.wait(Leaderboards.RefreshSeconds)
		end
	end)
end

return LeaderboardService
