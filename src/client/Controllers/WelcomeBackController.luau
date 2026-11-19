--!strict
-- Ecran "Welcome Back!" (gains hors ligne) a l'arrivee dans le jeu.
-- Remplit le menu "OfflineEarnings" du pack UI : texte, montant, bouton CLAIM et bouton x2 (Robux).
-- Le vrai calcul des gains hors ligne est cote serveur (pas encore code) ; en attendant, Studio
-- affiche un exemple au lancement (`SHOW_DEMO_IN_STUDIO`) pour verifier l'interface.
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("NumberFormat"))

local WelcomeBackController = {}

local MENU_NAME = "OfflineEarnings"
local SHOW_DEMO_IN_STUDIO = true
local DEMO_SECONDS = 5 * 60
local DEMO_AMOUNT = 5

local subtitle: TextLabel
local amountLabel: TextLabel

local function formatDuration(seconds: number): string
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	return `{hours}h {minutes}m`
end

-- Meme format que le HUD (NumberFormat) : "$5K", "$1.2M"...
local function formatMoney(amount: number): string
	return NumberFormat.Money(amount)
end

local function menuController(): any
	return require(script.Parent:WaitForChild("MenuController")) :: any
end

-- Affiche l'ecran avec la duree d'absence (secondes) et l'argent gagne.
function WelcomeBackController.Show(seconds: number, amount: number)
	if not subtitle then
		return
	end
	subtitle.Text = `You were offline for {formatDuration(seconds)} and earned:`
	amountLabel.Text = formatMoney(amount)
	-- Open() bascule : ne pas refermer l'ecran s'il est deja ouvert
	if menuController().GetActiveMenu() ~= MENU_NAME then
		menuController().Open(MENU_NAME)
	end
end

local function build(menu: Frame, shopConfig: any, icons: any)
	local header = menu:FindFirstChild("Header")
	local title = header and header:FindFirstChild("TextLabel", true)
	if title and title:IsA("TextLabel") then
		title.Text = "Welcome Back!"
	end

	local body = menu:WaitForChild("Shop") :: Frame
	for _, child in body:GetChildren() do
		if not child:IsA("UIAspectRatioConstraint") then
			child:Destroy()
		end
	end

	subtitle = PackStyle.label(body, "", UDim2.fromScale(0.5, 0.07), UDim2.fromScale(0.92, 0.13), 40)

	-- Encadre du montant : fond sombre + billets + montant vert.
	local box = Instance.new("Frame")
	box.Name = "AmountBox"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.fromScale(0.5, 0.26)
	box.Size = UDim2.fromScale(0.62, 0.27)
	box.BackgroundColor3 = Color3.fromRGB(40, 45, 70)
	box.BackgroundTransparency = 0.15
	box.ZIndex = 2
	PackStyle.stroke(box, 3, Color3.fromRGB(10, 10, 20), Enum.ApplyStrokeMode.Border)
	local cash = Instance.new("ImageLabel")
	cash.BackgroundTransparency = 1
	cash.AnchorPoint = Vector2.new(0, 0.5)
	cash.Position = UDim2.fromScale(0.06, 0.5)
	cash.Size = UDim2.fromScale(0.8, 0.8)
	cash.SizeConstraint = Enum.SizeConstraint.RelativeYY
	cash.ScaleType = Enum.ScaleType.Fit
	cash.Image = icons.Cash
	cash.ZIndex = 3
	cash.Parent = box
	amountLabel = PackStyle.label(box, "$0", UDim2.fromScale(0.58, 0.12), UDim2.fromScale(0.6, 0.76), 70)
	amountLabel.TextColor3 = PackStyle.MONEY_GREEN
	box.Parent = body

	local claim = PackStyle.button(body, "Claim", PackStyle.GREEN, UDim2.fromScale(0.32, 0.62), UDim2.fromScale(0.3, 0.2))
	PackStyle.label(claim, "CLAIM", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 50)
	claim.Activated:Connect(function()
		-- A brancher : demander au serveur de crediter les gains hors ligne.
		menuController().Close()
	end)

	local double = PackStyle.button(body, "Double", PackStyle.PURPLE, UDim2.fromScale(0.68, 0.62), UDim2.fromScale(0.3, 0.2))
	PackStyle.label(double, "x2", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.8, 0.84), 60)
	PackStyle.priceRow(body, icons.Robux, shopConfig.OfflineDouble.price, UDim2.fromScale(0.68, 0.84), UDim2.fromScale(0.3, 0.1))
	double.Activated:Connect(function()
		if shopConfig.OfflineDouble.productId == 0 then
			warn('[WelcomeBack] Produit "x2 gains hors ligne" pas encore cree sur Roblox (id = 0).')
		end
	end)
end

function WelcomeBackController:Start()
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	local shopConfig = require(config:WaitForChild("Shop")) :: any
	local icons = require(config:WaitForChild("Icons")) :: any
	local shopGUI = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("ShopGUI")
	local menu = shopGUI:WaitForChild("MenuFrames"):WaitForChild(MENU_NAME) :: Frame
	build(menu, shopConfig, icons)

	if SHOW_DEMO_IN_STUDIO and RunService:IsStudio() then
		task.delay(2, function()
			WelcomeBackController.Show(DEMO_SECONDS, DEMO_AMOUNT)
			-- Demo de la pastille "!" sur le bouton Shop (Studio seulement).
			menuController().SetBadge("Shop", true)
		end)
	end
end

return WelcomeBackController
