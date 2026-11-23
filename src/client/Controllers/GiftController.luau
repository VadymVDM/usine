--!strict
-- Fenetre "Gift <pass> to..." (2026-11-23) : ouverte par le bouton rose d'un pass dans la boutique
-- (ShopController -> GiftController.Open). Liste les autres joueurs du serveur (tete + pseudo + bouton
-- GIFT) ; un clic envoie le remote ShopGift(passKey, userId). Le serveur (GiftService) verifie tout,
-- ouvre la fenetre d'achat Roblox et ne donne le pass qu'au recu. Copie du menu OfflineEarnings
-- du pack (comme la pop-up de BuyController), ouverte par MenuController.
-- Doc : docs/systems/cadeaux.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(Shared:WaitForChild("Config"):WaitForChild("Shop"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local GiftController = {}

local MENU_NAME = "GiftPlayer"
local HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"
local ROW_HEIGHT = 0.2 -- hauteur d'une ligne / largeur de la liste (rapport fixe : meme rendu partout)

local player = Players.LocalPlayer

type Popup = { frame: GuiObject, title: TextLabel, list: ScrollingFrame, empty: TextLabel }

local popup: Popup? = nil
local currentKey: string? = nil

local function menuController(): any
	return require(script.Parent:WaitForChild("MenuController")) :: any
end

local function passTitle(key: string): string
	for _, pass in Shop.Passes do
		if pass.key == key then
			return pass.title
		end
	end
	return key
end

local function send(key: string, userId: number)
	local event = Remotes.WaitClientEvent("ShopGift")
	if event then
		event:FireServer(key, userId)
	end
end

local function buildPopup(): Popup?
	local frame = menuController().CloneMenuTemplate("OfflineEarnings", MENU_NAME)
	if not frame then
		warn("[GiftController] Modele de menu introuvable : cadeaux impossibles")
		return nil
	end
	local header = frame:FindFirstChild("Header")
	local subHeader = header and header:FindFirstChild("SubHeader")
	local headerTitle = subHeader and subHeader:FindFirstChild("TextLabel", true)
	if headerTitle and headerTitle:IsA("TextLabel") then
		headerTitle.Text = "Gift"
	end
	local body = frame:WaitForChild("Shop") :: Frame

	local title = PackStyle.label(body, "", UDim2.fromScale(0.5, 0.03), UDim2.fromScale(0.92, 0.14), 48)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.fromScale(0.5, 0.2)
	list.Size = UDim2.fromScale(0.92, 0.76)
	list.BackgroundColor3 = Color3.fromRGB(40, 45, 70)
	list.BackgroundTransparency = 0.25
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 2
	PackStyle.stroke(list, 3, Color3.fromRGB(10, 10, 20), Enum.ApplyStrokeMode.Border)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.015, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.02, 0)
	padding.PaddingBottom = UDim.new(0.02, 0)
	padding.Parent = list
	list.Parent = body

	local empty = PackStyle.label(body, "No other players here!", UDim2.fromScale(0.5, 0.48), UDim2.fromScale(0.8, 0.14), 40)
	empty.Visible = false

	menuController().RegisterMenu(frame)
	return { frame = frame, title = title, list = list, empty = empty }
end

local function addRow(p: Popup, other: Player, index: number)
	local row = Instance.new("Frame")
	row.Name = "Player_" .. other.UserId
	row.LayoutOrder = index
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(0.96, 0)
	row.ZIndex = 3
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1 / ROW_HEIGHT
	ratio.Parent = row

	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.BackgroundColor3 = Color3.fromRGB(70, 80, 120)
	head.Size = UDim2.fromScale(1, 1)
	head.SizeConstraint = Enum.SizeConstraint.RelativeYY
	head.Image = string.format(HEADSHOT, other.UserId)
	head.ZIndex = 3
	PackStyle.stroke(head, 2.5, Color3.fromRGB(10, 10, 20), Enum.ApplyStrokeMode.Border)
	head.Parent = row

	local name = PackStyle.label(row, other.DisplayName, UDim2.fromScale(0.45, 0.2), UDim2.fromScale(0.46, 0.6), 40)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.AutoLocalize = false -- un pseudo ne se traduit pas

	local button = PackStyle.button(row, "Gift", PackStyle.PINK, UDim2.fromScale(0.85, 0.12), UDim2.fromScale(0.28, 0.76))
	PackStyle.label(button, "GIFT", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 40)
	button.Activated:Connect(function()
		local key = currentKey
		if key then
			send(key, other.UserId)
			menuController().Close()
		end
	end)
	row.Parent = p.list
end

local function refresh()
	local p = popup
	if p == nil then
		return
	end
	for _, child in p.list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local others: { Player } = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	for index, other in others do
		addRow(p, other, index)
	end
	p.empty.Visible = #others == 0
	p.list.Visible = #others > 0
end

-- Ouvre la fenetre pour offrir ce pass (cle de Shop.Passes).
function GiftController.Open(passKey: string)
	if popup == nil then
		popup = buildPopup()
	end
	local p = popup
	if p == nil then
		return
	end
	currentKey = passKey
	p.title.Text = `Gift {passTitle(passKey)} to:`
	refresh()
	if menuController().GetActiveMenu() ~= MENU_NAME then
		menuController().Open(MENU_NAME)
	end
end

function GiftController:Start()
	-- Joueur qui arrive / part pendant que la fenetre est ouverte : liste a jour
	local function onChange()
		if popup and menuController().GetActiveMenu() == MENU_NAME then
			refresh()
		end
	end
	Players.PlayerAdded:Connect(onChange)
	Players.PlayerRemoving:Connect(function()
		task.defer(onChange)
	end)
end

return GiftController
