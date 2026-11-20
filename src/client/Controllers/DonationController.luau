--!strict
-- Fenetre des dons (rien n'est decide ici) : ouverte par le prompt E "DonatePrompt" de l'urne de
-- SA base (etage 1). 8 boutons verts "[R$] 5" ... "[R$] 10000" : clic = fenetre d'achat de Roblox
-- (PromptProductPurchase). Le don n'est compte que par le serveur, a la reception du recu
-- (DonationService). Produit pas encore cree (productId 0) : "Donations: coming soon!".
-- "Your tips: X" = attribut DonatedRobux du joueur (pose par le serveur).
-- X / Echap / clic a cote = fermer.
-- Doc : docs/systems/dons.md, docs/systems/interface.md

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Donations = require(Config:WaitForChild("Donations"))
local Icons = require(Config:WaitForChild("Icons")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local PurchaseFx = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("PurchaseFx"))

type Amount = { robux: number, productId: number }

local PROMPT_NAME = "DonatePrompt"
local FOOTER_COLOR = Color3.fromRGB(200, 255, 190)
local WARN_COLOR = Color3.fromRGB(255, 120, 110)
local WARN_SECONDS = 2.5

local DonationController = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local panel: Frame? = nil
local panelScale: UIScale? = nil
local firstButton: GuiButton? = nil
local footer: TextLabel? = nil
local yourTips: TextLabel? = nil
local popConnection: RBXScriptConnection? = nil
local warnToken = 0

local function close()
	local frame = panel
	if gui then
		gui.Enabled = false
	end
	if popConnection then
		popConnection:Disconnect()
		popConnection = nil
	end
	local selected = GuiService.SelectedObject
	if selected and frame and selected:IsDescendantOf(frame) then
		GuiService.SelectedObject = nil
	end
end

local function updateYourTips()
	local label = yourTips
	if label == nil then
		return
	end
	local value = player:GetAttribute("DonatedRobux")
	if type(value) == "number" and value > 0 then
		label.Text = string.format(Donations.YourTipsFormat, Donations.Format(value) .. " R$")
		label.Visible = true
	else
		label.Visible = false
	end
end

local function showFooter(text: string, color: Color3)
	local label = footer
	if label then
		label.Text = text
		label.TextColor3 = color
	end
end

local function comingSoon()
	warnToken += 1
	local token = warnToken
	showFooter(Donations.ComingSoon, WARN_COLOR)
	task.delay(WARN_SECONDS, function()
		if token == warnToken then
			showFooter(Donations.WindowFooter, FOOTER_COLOR)
		end
	end)
end

local function donate(amount: Amount)
	if amount.productId <= 0 then
		comingSoon()
		return
	end
	-- Fenetre de confirmation de Roblox ; le serveur compte le don a la reception du paiement.
	MarketplaceService:PromptProductPurchase(player, amount.productId)
	PurchaseFx.Show()
end

local function open()
	local screen, scale = gui, panelScale
	if screen == nil or scale == nil then
		return
	end
	warnToken += 1
	showFooter(Donations.WindowFooter, FOOTER_COLOR)
	updateYourTips()
	screen.Enabled = true
	if UserInputService.GamepadEnabled and firstButton then
		GuiService.SelectedObject = firstButton
	end
	-- Ouverture "gelee" : la fenetre gonfle et rebondit
	local spring = Jelly.Spring(320, 14)
	spring.x = -0.45
	scale.Scale = 1 + spring.x
	if popConnection then
		popConnection:Disconnect()
	end
	popConnection = RunService.RenderStepped:Connect(function(dt: number)
		Jelly.Step(spring, dt)
		scale.Scale = math.max(0.05, 1 + spring.x)
		if Jelly.Resting(spring) then
			scale.Scale = 1
			if popConnection then
				popConnection:Disconnect()
				popConnection = nil
			end
		end
	end)
	SoundFx.Play("PadStep")
end

local function buildWindow()
	local screen = Instance.new("ScreenGui")
	screen.Name = "DonationsGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30 -- au-dessus du HUD, sous les messages (50)
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false

	-- Clic a cote de la fenetre = fermer
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Selectable = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Activated:Connect(close)
	backdrop.Parent = screen

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.5, 0.78)
	frame.BackgroundColor3 = Color3.fromRGB(30, 22, 40)
	frame.BackgroundTransparency = 0.1
	frame.ZIndex = 2
	frame.Active = true -- un clic dans la fenetre ne passe pas au fond
	PackStyle.stroke(frame, 3, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.03, 0)
	corner.Parent = frame
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(260, 260)
	limit.MaxSize = Vector2.new(500, 500)
	limit.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- En-tete (bandeau cyan des menus)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.14)
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	header.ZIndex = 3
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0.2, 0)
	headerCorner.Parent = header
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = ColorSequence.new(PackStyle.HEADER[1], PackStyle.HEADER[2])
	gradient.Parent = header
	PackStyle.stroke(header, 3, PackStyle.HEADER[3], Enum.ApplyStrokeMode.Border)
	PackStyle.label(header, Donations.WindowTitle, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.6, 0.76), 40).ZIndex = 5
	header.Parent = frame

	local closeButton = PackStyle.button(header, "Close", PackStyle.RED, UDim2.fromScale(0.92, 0.5), UDim2.fromScale(0.14, 0.76))
	closeButton.AnchorPoint = Vector2.new(0.5, 0.5) -- retrecit au centre a l'appui (avant : vers le haut)
	closeButton.ZIndex = 5
	local closeRatio = Instance.new("UIAspectRatioConstraint")
	closeRatio.AspectRatio = 1
	closeRatio.Parent = closeButton
	PackStyle.label(closeButton, "X", UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.8, 0.8), 32).ZIndex = 7
	closeButton.Activated:Connect(close)

	PackStyle.label(frame, Donations.WindowSubtitle, UDim2.fromScale(0.5, 0.165), UDim2.fromScale(0.86, 0.06), 24).ZIndex = 4

	-- 2 colonnes x 4 lignes de boutons verts
	local grid = Instance.new("Frame")
	grid.Name = "Amounts"
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.fromScale(0.5, 0.25)
	grid.Size = UDim2.fromScale(0.86, 0.56)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 3
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.FillDirectionMaxCells = 2
	gridLayout.CellSize = UDim2.fromScale(0.47, 0.22)
	gridLayout.CellPadding = UDim2.fromScale(0.06, 0.04)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = grid
	for i, amount in Donations.Amounts do
		local button = PackStyle.button(grid, "Tip" .. amount.robux, PackStyle.GREEN, UDim2.new(), UDim2.new())
		button.LayoutOrder = i
		PackStyle.priceRow(button, Icons.Robux, amount.robux, UDim2.fromScale(0.5, 0.14), UDim2.fromScale(0.9, 0.72))
		button.Activated:Connect(function()
			donate(amount)
		end)
		if i == 1 then
			firstButton = button
		end
	end
	grid.Parent = frame

	local tips = PackStyle.label(frame, "", UDim2.fromScale(0.5, 0.835), UDim2.fromScale(0.7, 0.06), 26)
	tips.Name = "YourTips"
	tips.TextColor3 = Color3.fromRGB(235, 200, 255)
	tips.Visible = false
	local foot = PackStyle.label(frame, Donations.WindowFooter, UDim2.fromScale(0.5, 0.91), UDim2.fromScale(0.9, 0.055), 22)
	foot.Name = "Footer"
	foot.TextColor3 = FOOTER_COLOR

	frame.Parent = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	gui, panel, panelScale, footer, yourTips = screen, frame, scale, foot, tips
end

local function onPromptTriggered(prompt: ProximityPrompt, who: Player)
	if who ~= player or prompt.Name ~= PROMPT_NAME then
		return
	end
	open()
end

function DonationController:Init() end

function DonationController:Start()
	buildWindow()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	player:GetAttributeChangedSignal("DonatedRobux"):Connect(updateYourTips)
	-- Achat termine : on ferme (le merci vient du serveur, une fois le don enregistre)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		if userId ~= player.UserId or not purchased then
			return
		end
		for _, amount in Donations.Amounts do
			if amount.productId == productId then
				close()
				return
			end
		end
	end)
	GuiService.MenuOpened:Connect(close)
	player.CharacterRemoving:Connect(close)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if gui and gui.Enabled then
				close()
			end
		end
	end)
end

return DonationController
