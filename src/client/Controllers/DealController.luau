--!strict
-- Fenetres d'offre "au bon moment" (2026-11-23). Le serveur decide quand ; ce controleur affiche.
--   * Feedback "NeedCash" { floor, missing } (FloorService, achat d'etage refuse faute d'argent) :
--     "Almost there!" + le plus petit pack d'argent (Shop.CashPacks) qui couvre ce qui manque
--     (montants : attributs "Cash_<cle>" du serveur) ; bouton -> ShopBuy("CashPack", cle).
--   * Feedback "TrialEnd" { pass, earned } (RobuxShopService, fin de l'essai gratuit 3X CASH) :
--     "3X CASH earned you +$X! Keep it forever?" ; bouton -> ShopBuy("Pass", cle).
-- Une seule fenetre (menu "Deal", copie du menu OfflineEarnings), refaite a chaque ouverture.
-- Si un autre menu est ouvert, la fenetre attend qu'il se ferme (au plus WAIT_MENU_SECONDS).
-- Doc : docs/systems/achats-robux.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("Remotes"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("NumberFormat"))

local DealController = {}

local MENU = "Deal"
local GLOW_IMAGE = "rbxassetid://100034870209210" -- rayons lumineux du pack UI (comme OffersController)
local GLOW_SPEED = 40
local WAIT_MENU_SECONDS = 300 -- l'ecran Welcome Back peut rester ouvert longtemps

local player = Players.LocalPlayer
local Shop: any
local icons: { [string]: string }
local frame: GuiObject? = nil
local body: Frame? = nil
local title: TextLabel? = nil
local content: Frame? = nil
local glow: ImageLabel? = nil
local token = 0

local function menuController(): any
	return require(script.Parent:WaitForChild("MenuController")) :: any
end

local function build()
	local menu = menuController().CloneMenuTemplate("OfflineEarnings", MENU)
	if not menu then
		warn("[Deal] Modele de menu introuvable")
		return
	end
	local subHeader = menu:FindFirstChild("Header") and (menu :: any).Header:FindFirstChild("SubHeader")
	local found = subHeader and subHeader:FindFirstChild("TextLabel", true)
	title = if found and found:IsA("TextLabel") then found else nil
	body = menu:WaitForChild("Shop") :: Frame

	local rays = Instance.new("ImageLabel")
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.24, 0.48)
	rays.Size = UDim2.fromScale(0.95, 0.95)
	rays.SizeConstraint = Enum.SizeConstraint.RelativeYY
	rays.Image = GLOW_IMAGE
	rays.ImageTransparency = 0.2
	rays.ZIndex = 2
	rays.Parent = body
	glow = rays

	local holder = Instance.new("Frame")
	holder.Name = "Content"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 3
	holder.Parent = body
	content = holder

	frame = menu
	menuController().RegisterMenu(menu)
end

local function clear()
	if content then
		for _, child in content:GetChildren() do
			child:Destroy()
		end
	end
end

local function bigIcon(iconKey: string)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.24, 0.48)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = icons[iconKey] or ""
	icon.ZIndex = 3
	icon.Parent = content
	TweenService:Create(
		icon,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromScale(0.24, 0.44), Rotation = 5 }
	):Play()
end

-- Gros bouton vert avec le prix en Robux ; clic -> ShopBuy(kind, key).
local function buyButton(price: number, kind: string, key: string)
	local parent = content :: Frame
	local buy = PackStyle.button(parent, "Buy", PackStyle.GREEN, UDim2.fromScale(0.68, 0.66), UDim2.fromScale(0.42, 0.24))
	local stroke = PackStyle.stroke(buy, 4, Color3.fromRGB(255, 220, 60), Enum.ApplyStrokeMode.Border)
	TweenService:Create(
		stroke,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.8 }
	):Play()
	PackStyle.priceRow(buy, icons.Robux, price, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(1, 0.76))
	buy.Activated:Connect(function()
		local shopBuy = Remotes.WaitClientEvent("ShopBuy")
		if shopBuy then
			shopBuy:FireServer(kind, key, false)
		end
	end)
end

-- Ouvre la fenetre quand aucun autre menu n'est ouvert (une demande plus recente remplace l'ancienne).
local function show(fill: () -> ())
	if not frame then
		return
	end
	token += 1
	local mine = token
	task.spawn(function()
		local deadline = os.clock() + WAIT_MENU_SECONDS
		while menuController().GetActiveMenu() ~= nil and os.clock() < deadline do
			task.wait(0.5)
			if mine ~= token then
				return
			end
		end
		if mine ~= token or menuController().GetActiveMenu() ~= nil then
			return
		end
		clear()
		fill()
		menuController().Open(MENU)
	end)
end

-- Plus petit pack qui couvre `missing` (sinon le plus gros montant).
local function pickPack(missing: number): (any?, number)
	local best, bestAmount = nil, 0
	local biggest, biggestAmount = nil, 0
	for _, pack in Shop.CashPacks do
		local value = player:GetAttribute("Cash_" .. pack.key)
		local amount = if type(value) == "number" then value else 0
		if amount >= missing and (best == nil or amount < bestAmount) then
			best, bestAmount = pack, amount
		end
		if amount > biggestAmount then
			biggest, biggestAmount = pack, amount
		end
	end
	if best then
		return best, bestAmount
	end
	return biggest, biggestAmount
end

local function onNeedCash(info: any)
	if type(info) ~= "table" or type(info.missing) ~= "number" or type(info.floor) ~= "number" then
		return
	end
	local pack, amount = pickPack(info.missing)
	if pack == nil or amount <= 0 then
		return
	end
	local texts = Shop.DealTexts
	show(function()
		if title then
			title.Text = texts.NeedTitle
		end
		bigIcon("Cash")
		local parent = content :: Frame
		PackStyle.label(parent, string.format(texts.NeedLine, info.floor, NumberFormat.Money(info.missing)), UDim2.fromScale(0.68, 0.06), UDim2.fromScale(0.6, 0.14), 60)
		local money = PackStyle.label(parent, "+" .. NumberFormat.Money(amount), UDim2.fromScale(0.68, 0.24), UDim2.fromScale(0.58, 0.26), 110)
		money.TextColor3 = PackStyle.MONEY_GREEN
		PackStyle.label(parent, pack.title, UDim2.fromScale(0.68, 0.51), UDim2.fromScale(0.5, 0.1), 40)
		buyButton(pack.price, "CashPack", pack.key)
	end)
end

local function onTrialEnd(info: any)
	if type(info) ~= "table" or type(info.earned) ~= "number" or info.earned <= 0 or type(info.pass) ~= "string" then
		return
	end
	local pass = nil
	for _, candidate in Shop.Passes do
		if candidate.key == info.pass then
			pass = candidate
		end
	end
	if pass == nil or player:GetAttribute(pass.key) == true then
		return
	end
	local texts = Shop.DealTexts
	show(function()
		if title then
			title.Text = texts.TrialTitle
		end
		bigIcon(pass.icon)
		local parent = content :: Frame
		PackStyle.label(parent, texts.TrialLine, UDim2.fromScale(0.68, 0.05), UDim2.fromScale(0.6, 0.13), 60)
		local money = PackStyle.label(parent, "+" .. NumberFormat.Money(info.earned), UDim2.fromScale(0.68, 0.2), UDim2.fromScale(0.58, 0.26), 110)
		money.TextColor3 = PackStyle.MONEY_GREEN
		PackStyle.label(parent, texts.TrialAsk, UDim2.fromScale(0.68, 0.49), UDim2.fromScale(0.58, 0.13), 60)
		buyButton(pass.price, "Pass", pass.key)
	end)
end

function DealController:Start()
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	Shop = require(config:WaitForChild("Shop")) :: any
	icons = require(config:WaitForChild("Icons")) :: any
	player:WaitForChild("PlayerGui"):WaitForChild("ShopGUI")
	if not menuController().WaitUntilReady(15) then
		warn("[Deal] Menus pas prets")
		return
	end
	build()
	RunService.RenderStepped:Connect(function(dt: number)
		local rays = glow
		if rays and frame and frame.Visible then
			rays.Rotation = (rays.Rotation + GLOW_SPEED * dt) % 360
		end
	end)
	local event = Remotes.WaitClientEvent("Feedback")
	if event then
		event.OnClientEvent:Connect(function(kind: any, info: any)
			if kind == "NeedCash" then
				onNeedCash(info)
			elseif kind == "TrialEnd" then
				onTrialEnd(info)
			end
		end)
	end
end

return DealController
