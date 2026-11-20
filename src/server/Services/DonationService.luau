--!strict
-- Dons (pourboires en Robux), cote serveur :
--   * urne de l'etage 1 (BaseTemplate.Donations, tools/build-map/02i) : prompt E "DonatePrompt" ;
--     le client ouvre la fenetre et demande l'achat lui-meme (PromptProductPurchase). Aucun remote :
--     seul le recu de Roblox (ReceiptService) compte un don.
--   * recu d'un don : UpdateAsync sur la cle "u<UserId>" (Total + derniers PurchaseId) = une seule
--     ecriture, un meme achat n'est jamais compte deux fois ; puis le classement (OrderedDataStore,
--     jamais plus bas que le total sauvegarde). Le joueur n'a pas besoin d'etre dans le serveur.
--   * tableau "TOP DONORS" de chaque base : relu toutes les RefreshSeconds (et peu apres un don),
--     textes ecrits par le serveur dans les lignes construites par 02i.
--   * attribut "DonatedRobux" du joueur (ses dons depuis toujours), affiche dans la fenetre.
-- Doc : docs/systems/dons.md

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Donations = require(Config:WaitForChild("Donations"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Prompt = require(Shared:WaitForChild("Util"):WaitForChild("Prompt"))
local ReceiptService = require(script.Parent.ReceiptService)
local NotifyService = require(script.Parent.NotifyService)

local PROMPT_NAME = "DonatePrompt"
local HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60"

type Entry = { userId: number, total: number }
type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

local DonationService = {}

local robuxByProduct: { [number]: number } = {}
local store: DataStore? = nil
local ranking: OrderedDataStore? = nil
local entries: { Entry } = {}
local names: { [number]: string } = {}
local pendingRanking: { [number]: number } = {} -- classement pas encore ecrit (erreur) : reessaye
local refreshSoon = false

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

---------------------------------------------------------------------------------------------
-- Classement

-- Ecrit le total dans le classement sans jamais le faire baisser (deux serveurs en meme temps).
local function writeRanking(userId: number, total: number): boolean
	local orderedStore = ranking
	if orderedStore == nil then
		return false
	end
	local ok, err = pcall(function()
		orderedStore:UpdateAsync(tostring(userId), function(old: any)
			local current = if isFiniteNumber(old) then old else 0
			if current >= total then
				return nil -- deja a jour
			end
			return math.floor(total)
		end)
	end)
	if not ok then
		warn(`[DonationService] Classement non ecrit pour {userId} : {err}`)
	end
	return ok
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

local function renderBoard(base: Instance)
	local folder = base:FindFirstChild("Donations")
	local rows = folder and folder:FindFirstChild("Rows", true)
	if rows == nil then
		return
	end
	for i = 1, Donations.BoardRows do
		local row = rows:FindFirstChild("Row" .. i)
		if row == nil then
			continue
		end
		local entry = entries[i]
		local nameLabel = row:FindFirstChild("PlayerName")
		local amount = row:FindFirstChild("Amount")
		local avatar = row:FindFirstChild("Avatar")
		local robuxIcon = row:FindFirstChild("RobuxIcon")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = if entry then nameOf(entry.userId) elseif i == 1 then Donations.EmptyRow else "---"
		end
		if amount and amount:IsA("TextLabel") then
			amount.Text = if entry then Donations.Format(entry.total) else ""
		end
		if avatar and avatar:IsA("ImageLabel") then
			avatar.Image = if entry then string.format(HEADSHOT, entry.userId) else ""
			avatar.Visible = entry ~= nil
		end
		if robuxIcon and robuxIcon:IsA("GuiObject") then
			robuxIcon.Visible = entry ~= nil
		end
	end
end

local function renderAll()
	local bases = workspace:FindFirstChild("Bases")
	if bases == nil then
		return
	end
	for _, base in bases:GetChildren() do
		renderBoard(base)
	end
end

local function refresh()
	-- Reessaie les totaux qui n'ont pas pu etre ecrits dans le classement
	for userId, total in pendingRanking do
		if writeRanking(userId, total) then
			pendingRanking[userId] = nil
		end
	end
	local orderedStore = ranking
	if orderedStore == nil then
		return
	end
	local ok, result = pcall(function()
		local pages = orderedStore:GetSortedAsync(false, Donations.BoardRows, 1)
		return pages:GetCurrentPage()
	end)
	if not ok then
		warn(`[DonationService] Lecture du classement impossible : {result}`)
		return
	end
	local fresh: { Entry } = {}
	for _, item in result :: { any } do
		local userId = tonumber(item.key)
		local total = item.value
		if userId and userId > 0 and isFiniteNumber(total) and total > 0 then
			table.insert(fresh, { userId = userId, total = total })
			nameOf(userId) -- prepare le nom (appel web) hors du rendu
		end
	end
	entries = fresh
	renderAll()
end

---------------------------------------------------------------------------------------------
-- Recus

local function onDonationReceipt(receipt: Receipt): boolean
	local robux = robuxByProduct[receipt.ProductId]
	local dataStore = store
	if robux == nil or dataStore == nil then
		return false
	end
	local userId = receipt.PlayerId
	local newTotal: number? = nil
	local alreadyCounted = false
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
				alreadyCounted = true
				newTotal = current
				return nil -- deja compte : rien a ecrire
			end
			alreadyCounted = false
			table.insert(receipts, receipt.PurchaseId)
			while #receipts > Donations.ReceiptsKept do
				table.remove(receipts, 1)
			end
			newTotal = current + robux
			return { Total = current + robux, Receipts = receipts }
		end)
	end)
	if not ok or newTotal == nil then
		warn(`[DonationService] Don de {userId} non enregistre (sera redonne par Roblox) : {err}`)
		return false
	end
	local total = newTotal :: number

	-- Le don est sauvegarde : la suite (classement, messages) ne doit plus faire echouer le recu.
	if not writeRanking(userId, total) then
		pendingRanking[userId] = total
	end
	local donor = Players:GetPlayerByUserId(userId)
	if donor then
		donor:SetAttribute("DonatedRobux", total)
	end
	if not alreadyCounted then
		local amountText = Donations.Format(robux)
		if donor then
			NotifyService.Notify(donor, string.format(Donations.ThanksFormat, amountText))
		end
		local who = if donor then donor.DisplayName else nameOf(userId)
		for _, other in Players:GetPlayers() do
			if other ~= donor then
				NotifyService.Notify(other, string.format(Donations.BroadcastFormat, who, amountText))
			end
		end
		refreshSoon = true
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Joueurs et urnes

local function loadPlayerTotal(player: Player)
	local dataStore = store
	if dataStore == nil then
		return
	end
	local ok, data = pcall(dataStore.GetAsync, dataStore, "u" .. player.UserId)
	if not ok or player.Parent == nil then
		return
	end
	local total = if type(data) == "table" and isFiniteNumber(data.Total) then math.max(0, math.floor(data.Total)) else 0
	-- Un don pendant la lecture a deja pose une valeur plus recente : ne pas la remplacer
	local current = player:GetAttribute("DonatedRobux")
	if type(current) ~= "number" or current < total then
		player:SetAttribute("DonatedRobux", total)
	end
end

local function setupBase(base: Instance)
	local folder = base:FindFirstChild("Donations")
	local anchor = folder and folder:FindFirstChild("PromptAnchor", true)
	if anchor == nil or not anchor:IsA("BasePart") then
		warn(`[DonationService] {base.Name} : Donations.PromptAnchor manquant (relancer tools/build-map/02i)`)
		return
	end
	if anchor:FindFirstChild(PROMPT_NAME) == nil then
		-- Le client ouvre la fenetre des dons (DonationController) ; rien a verifier ici
		Prompt.Create(anchor, Donations.PromptObject, Donations.PromptAction, {
			name = PROMPT_NAME,
			distance = Gameplay.PromptDistance,
		})
	end
	renderBoard(base)
end

function DonationService:Init()
	for _, amount in Donations.Amounts do
		if amount.productId > 0 then
			robuxByProduct[amount.productId] = amount.robux
			ReceiptService.Register(amount.productId, onDonationReceipt)
		end
	end
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Donations.StoreName)
		ranking = DataStoreService:GetOrderedDataStore(Donations.RankingName)
	end)
	if not ok then
		warn(`[DonationService] DataStore indisponible : {err}`)
	end
end

function DonationService:Start()
	Players.PlayerAdded:Connect(loadPlayerTotal)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayerTotal, player)
	end

	local bases = workspace:WaitForChild("Bases", 30)
	if bases then
		for _, base in bases:GetChildren() do
			setupBase(base)
		end
		bases.ChildAdded:Connect(setupBase)
	end

	task.spawn(function()
		while true do
			refresh()
			local waited = 0
			while waited < Donations.RefreshSeconds do
				task.wait(Donations.RefreshAfterGiftSeconds)
				waited += Donations.RefreshAfterGiftSeconds
				if refreshSoon then
					refreshSoon = false
					break
				end
			end
		end
	end)
end

return DonationService
