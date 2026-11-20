--!strict
-- Ecran "Welcome Back!" (gains hors ligne) a l'arrivee dans le jeu.
-- Remplit le menu "OfflineEarnings" du pack UI : texte, montant, bouton CLAIM et bouton x2 (Robux).
-- Le serveur calcule tout (OfflineService) : quand le chargement est fini (attribut joueur
-- "LoadingDone") et les images de l'ecran prechargees, le client envoie "Ready" sur le remote
-- OfflineEarnings ; s'il y a des gains, le serveur repond "Show" (secondes, montant) -> l'ecran s'ouvre.
-- CLAIM (ou fermer l'ecran) -> "Claim" ; x2 -> "Double" (fenetre d'achat Robux ouverte par le serveur).
-- Le serveur repond "Claimed" -> l'ecran se ferme. Le client n'envoie jamais de montant.
-- Doc : docs/systems/gains-hors-ligne.md, docs/systems/interface.md

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("NumberFormat"))
local SoundFx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("Remotes"))

local WelcomeBackController = {}

local MENU_NAME = "OfflineEarnings"
local READY_TIMEOUT = 30 -- securite si "LoadingDone" n'est jamais pose
local PRELOAD_TIMEOUT = 2 -- images de l'ecran : on n'attend pas plus avant de l'ouvrir

local subtitle: TextLabel
local amountLabel: TextLabel
local event: RemoteEvent? = nil
-- Une offre est affichee et pas encore reclamee (anti double-clic : une seule demande "Claim")
local pending = false
local claimSent = false

local function send(action: string)
	if event then
		event:FireServer(action)
	end
end

-- CLAIM (bouton ou fermeture de l'ecran) : une seule demande par offre
local function requestClaim()
	if pending and not claimSent then
		claimSent = true
		send("Claim")
	end
end

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
	pending = true
	claimSent = false
	subtitle.Text = `You were offline for {formatDuration(seconds)} and earned:`
	amountLabel.Text = formatMoney(amount)
	-- Open() bascule : ne pas refermer l'ecran s'il est deja ouvert
	if menuController().GetActiveMenu() ~= MENU_NAME then
		menuController().Open(MENU_NAME)
		SoundFx.Play("WelcomeBack")
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
		requestClaim()
	end)

	local double = PackStyle.button(body, "Double", PackStyle.PURPLE, UDim2.fromScale(0.68, 0.62), UDim2.fromScale(0.3, 0.2))
	PackStyle.label(double, "x2", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.8, 0.84), 60)
	PackStyle.priceRow(body, icons.Robux, shopConfig.OfflineDouble.price, UDim2.fromScale(0.68, 0.84), UDim2.fromScale(0.3, 0.1))
	double.Activated:Connect(function()
		-- Le serveur verifie l'offre et ouvre la fenetre d'achat (productId 0 : "coming soon")
		if pending and not claimSent then
			send("Double")
		end
	end)
end

-- Attend la fin du chargement ("LoadingDone" : HUD montre), puis precharge les images de l'ecran (au plus PRELOAD_TIMEOUT secondes) pour l'ouvrir deja complet.
function WelcomeBackController.WaitUntilReady(menu: Instance)
	local player = Players.LocalPlayer
	local startedAt = os.clock()
	while player:GetAttribute("LoadingDone") ~= true and os.clock() - startedAt < READY_TIMEOUT do
		task.wait(0.05)
	end
	local finished = false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ menu })
		end)
		finished = true
	end)
	local preloadStart = os.clock()
	while not finished and os.clock() - preloadStart < PRELOAD_TIMEOUT do
		task.wait(0.05)
	end
end

function WelcomeBackController:Start()
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	local shopConfig = require(config:WaitForChild("Shop")) :: any
	local icons = require(config:WaitForChild("Icons")) :: any
	local shopGUI = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("ShopGUI")
	local menu = shopGUI:WaitForChild("MenuFrames"):WaitForChild(MENU_NAME) :: Frame
	build(menu, shopConfig, icons)

	event = Remotes.WaitClientEvent("OfflineEarnings")
	if event == nil then
		return
	end
	event.OnClientEvent:Connect(function(kind: any, seconds: any, amount: any)
		if kind == "Show" and type(seconds) == "number" and type(amount) == "number" then
			WelcomeBackController.Show(math.max(0, seconds), math.max(0, amount))
		elseif kind == "Claimed" then
			pending = false
			if menuController().GetActiveMenu() == MENU_NAME then
				menuController().Close()
			end
		end
	end)
	-- Fermer l'ecran (croix, autre menu) sans CLAIM = CLAIM : l'argent n'attend pas le depart
	local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD")
	hud:GetAttributeChangedSignal("ActiveMenu"):Connect(function()
		if pending and hud:GetAttribute("ActiveMenu") ~= MENU_NAME then
			requestClaim()
		end
	end)
	task.spawn(function()
		WelcomeBackController.WaitUntilReady(menu)
		send("Ready")
	end)
end

return WelcomeBackController
