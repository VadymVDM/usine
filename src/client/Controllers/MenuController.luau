--!strict
-- Controleur des menus de l'interface (HUD + ShopGUI).
-- Adapte du script "MenuController" du pack UI (ultrauipack) : animations des boutons,
-- ouverture/fermeture des menus avec flou et zoom, sons d'interface, bouton Settings en haut.
-- Doc : docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")

local MenuController = {}

-- Engrenage blanc (ICONSPACK "Settings White"), comme les icones blanches des boutons Roblox.
local SETTINGS_ICON_IMAGE = "rbxassetid://105567916477578"
local SETTINGS_ICON_SCALE = 0.62

-- Placement du HUD et taille des menus. Ces valeurs remplacent celles des fichiers .rbxm
-- (decision 2026-11-19 : reglages de mise en page dans le code, plus simples a ajuster).
local HUD_LAYOUT = {
	-- Colonne Shop/Index : largeur et marge au bord = celles des offres de droite (PackStyle.SIDE_*),
	-- calculees dans applyLayout (2026-11-20 : "meme taille que les offres, pas trop a droite").
	MoneyHeightPC = 0.13,
	BuyMoneySize = 0.46, -- bouton "+" (part de la hauteur de la ligne d'argent ; .rbxm : 0.6)
	BuyMoneySizePC = 0.6, -- bouton "+" sur PC, un peu plus gros
	MoneyPosition = UDim2.fromScale(0.018, 0.955),
	MoneyHeight = 0.14,
	MoneyTouchY = 0.975, -- ecran tactile : un peu plus bas, aligne sous le bouton Index
	IndexIcon = "rbxassetid://101346279017126", -- livre bleu, assorti au menu Index
}
-- Largeur des menus : rapport largeur/hauteur du cadre (le contenu suit).
local MENU_ASPECT = { Shop = 1.65, Index = 1.4 }
local MENU_WIDTH = { Shop = 0.64, Index = 0.56 }
-- Telephone (ecran < 450 px de haut) : fenetre plus large et plus haute plutot qu'un zoom.
local PHONE_MENU_ASPECT = { Shop = 1.95, Index = 1.6 }
local PHONE_MENU_WIDTH = { Shop = 0.8, Index = 0.68 }
local PHONE_MENU_HEIGHT = 0.88
local MENU_BODY_HEIGHT = 0.8387 -- part de la hauteur du menu occupee par le corps "Shop"
local HEADER_HEIGHT = 0.18 -- hauteur de l'en-tete (part du menu)
local HEADER_GAP = 0.0075 -- espace entre le bandeau titre et le X
local SMALL_SCREEN_MENU_SCALE = 1
local SOUND_NAMES = { "Hover", "Click", "MenuOpen", "ShopOpen", "CloseMenu" }
-- En-tetes : meme bandeau pour tous les menus (couleur PackStyle.HEADER), titre colle a l'icone,
-- meme hauteur de titre. Icone ajoutee aux menus du pack qui n'en ont pas.
local HEADER_TITLE_SIZE = UDim2.fromScale(0.8, 0.68)
local HEADER_ICONS = { Settings = SETTINGS_ICON_IMAGE }
-- Fleche verte/orange du pack (en-tete de OfflineEarnings, donc aussi Welcome Back et les pop-ups
-- copies de ce menu) : remplacee par l'icone cadeau (demande 2026-11-20).
local PACK_ARROW_ICON = "rbxassetid://94770154818570"

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local ButtonFx = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ButtonFx"))
local SoundFx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("SoundFx")) :: any


type MenuState = {
	frame: GuiObject,
	scale: UIScale,
	base: number,
	home: UDim2,
	token: number,
	scaleTween: Tween?,
	positionTween: Tween?,
}

type HudGroup = {
	frame: GuiObject,
	direction: string,
	home: UDim2,
	tween: Tween?,
}

type SoundPool = { next: number, voices: { Sound } }

local player = Players.LocalPlayer

local hud: ScreenGui
local shopGUI: ScreenGui
local menuFrames: Frame
local blur: BlurEffect
local soundFolder: Folder
local soundTemplates: Folder?

local menus: { [string]: MenuState } = {}
local actionBound: { [GuiButton]: boolean } = {}
local hudGroups: { HudGroup } = {}
local soundPools: { [string]: SoundPool } = {}
local connections: { RBXScriptConnection } = {}

local activeMenu: string? = nil
local baselineFOV: number? = nil
local fovCamera: Camera? = nil
local fovTween: Tween? = nil
local blurTween: Tween? = nil

local function connect(signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

-- Sons ------------------------------------------------------------------------------------------

local function prepareSound(name: string): SoundPool?
	local template = soundTemplates and soundTemplates:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		return nil
	end
	local pool: SoundPool = { next = 0, voices = {} }
	for index = 1, 4 do
		local voice = template:Clone()
		voice.Name = `{name}_{index}`
		voice.Looped = false
		voice.PlayOnRemove = false
		voice.SoundGroup = SoundFx.Group() -- curseur Sons (menu Settings)
		voice.Parent = soundFolder
		table.insert(pool.voices, voice)
	end
	soundPools[name] = pool
	return pool
end

local function playSound(name: string)
	-- Sons a 0 dans Settings (attribut pose par SettingsService)
	if not SoundFx.IsEnabled() then
		return
	end
	local pool = soundPools[name] or prepareSound(name)
	if not pool then
		return
	end
	pool.next = pool.next % #pool.voices + 1
	local voice = pool.voices[pool.next]
	voice:Stop()
	voice.TimePosition = 0
	voice:Play()
end

-- Animation des boutons ---------------------------------------------------------------------------

local function getScale(object: Instance, name: string): UIScale
	local scale = object:FindFirstChildOfClass("UIScale")
	if not scale then
		local newScale = Instance.new("UIScale")
		newScale.Name = name
		newScale.Parent = object
		return newScale
	end
	return scale
end

local function resetButtons(root: Instance)
	ButtonFx.ResetUnder(root)
end

-- Animation commune de tous les boutons (UI/ButtonFx) ; force = garder l'UIScale du pack UI.
local function bindFeedback(button: GuiButton)
	button.Active = true
	button.Interactable = true
	ButtonFx.Bind(button, true)
end

-- HUD qui sort de l'ecran quand un menu est ouvert ----------------------------------------------

local function addHUDGroup(frame: Instance?, direction: string)
	if frame and frame:IsA("GuiObject") then
		table.insert(hudGroups, { frame = frame, direction = direction, home = frame.Position })
	end
end

local function setHUDHidden(hidden: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	for _, state in hudGroups do
		if state.tween then
			state.tween:Cancel()
		end
		local frame = state.frame
		local target = state.home
		if hidden then
			-- Position de repos (pas la position du moment : le groupe peut etre en pleine animation
			-- de retour si on rouvre un menu tres vite). Seul l'offset change pendant les animations.
			local current = frame.Position
			local position = frame.AbsolutePosition
				- Vector2.new(current.X.Offset - state.home.X.Offset, current.Y.Offset - state.home.Y.Offset)
			local size = frame.AbsoluteSize
			local dx, dy = 0, 0
			-- Marge en plus pour que contours, ombres et enfants agrandis sortent completement.
			if state.direction == "Up" then
				dy = -position.Y - size.Y - 120
			elseif state.direction == "Left" then
				dx = -position.X - size.X - 24
			elseif state.direction == "Down" then
				dy = viewport.Y - position.Y + 24
			elseif state.direction == "Right" then
				dx = viewport.X - position.X + 24
			end
			target = state.home + UDim2.fromOffset(dx, dy)
		end
		local tween = TweenService:Create(
			frame,
			TweenInfo.new(
				if hidden then 0.21 else 0.27,
				if hidden then Enum.EasingStyle.Cubic else Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{ Position = target }
		)
		state.tween = tween
		tween:Play()
		if hidden then
			resetButtons(frame)
		end
	end
end

-- Fond flou + zoom camera -----------------------------------------------------------------------

local function setBackdrop(open: boolean)
	if blurTween then
		blurTween:Cancel()
	end
	local newBlurTween = TweenService:Create(
		blur,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = if open then 24 else 0 }
	)
	blurTween = newBlurTween
	if open then
		blur.Enabled = true
	else
		newBlurTween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				blur.Enabled = false
			end
		end)
	end
	newBlurTween:Play()

	local camera = workspace.CurrentCamera
	if open and not baselineFOV and camera then
		fovCamera = camera
		baselineFOV = camera.FieldOfView
	end
	if fovTween then
		fovTween:Cancel()
	end
	local savedCamera, savedFOV = fovCamera, baselineFOV
	if savedCamera and savedFOV then
		local tween = TweenService:Create(
			savedCamera,
			TweenInfo.new(0.20, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ FieldOfView = if open then math.min(savedFOV + 8, 110) else savedFOV }
		)
		fovTween = tween
		tween:Play()
		if not open then
			tween.Completed:Once(function(status)
				if status == Enum.PlaybackState.Completed and not activeMenu and fovTween == tween then
					baselineFOV, fovCamera = nil, nil
				end
			end)
		end
	end
end

-- Ouverture / fermeture des menus ---------------------------------------------------------------

local function cancelMenuTweens(state: MenuState)
	state.token += 1
	if state.scaleTween then
		state.scaleTween:Cancel()
	end
	if state.positionTween then
		state.positionTween:Cancel()
	end
end

local function hideImmediately(state: MenuState)
	cancelMenuTweens(state)
	state.frame.Visible = false
	state.frame.Position = state.home
	state.scale.Scale = state.base
	resetButtons(state.frame)
end

function MenuController.Close()
	local name = activeMenu
	if not name then
		return
	end
	local state = menus[name]
	activeMenu = nil
	hud:SetAttribute("ActiveMenu", "")
	playSound("CloseMenu")
	setBackdrop(false)
	setHUDHidden(false)
	cancelMenuTweens(state)
	local token = state.token
	local scaleTween = TweenService:Create(
		state.scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = state.base * 0.82 }
	)
	local positionTween = TweenService:Create(
		state.frame,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = state.home + UDim2.fromOffset(0, 24) }
	)
	state.scaleTween, state.positionTween = scaleTween, positionTween
	scaleTween.Completed:Once(function(status)
		if status == Enum.PlaybackState.Completed and token == state.token then
			hideImmediately(state)
			if not activeMenu then
				menuFrames.Active = false
			end
		end
	end)
	positionTween:Play()
	scaleTween:Play()
end

-- Ouvre un menu de ShopGUI.MenuFrames par son nom ("Shop", "Index"...). Le rouvrir le ferme.
function MenuController.Open(name: string)
	local state = menus[name]
	if not state then
		warn(`[MenuController] Menu inconnu : {name}`)
		return
	end
	if activeMenu == name then
		MenuController.Close()
		return
	end
	local firstOpen = activeMenu == nil
	for _, other in menus do
		hideImmediately(other)
	end
	activeMenu = name
	hud:SetAttribute("ActiveMenu", name)
	MenuController.SetBadge(name, false)
	shopGUI.Enabled = true
	menuFrames.Active = true
	if firstOpen then
		setBackdrop(true)
		setHUDHidden(true)
	end
	playSound(if name == "Shop" then "ShopOpen" else "MenuOpen")
	state.frame.Position = state.home + UDim2.fromOffset(0, 32)
	state.scale.Scale = state.base * 0.74
	state.frame.Visible = true
	local token = state.token
	local positionTween = TweenService:Create(
		state.frame,
		TweenInfo.new(0.20, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
		{ Position = state.home }
	)
	local scaleTween = TweenService:Create(
		state.scale,
		TweenInfo.new(0.17, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
		{ Scale = state.base * 1.025 }
	)
	state.scaleTween, state.positionTween = scaleTween, positionTween
	positionTween:Play()
	scaleTween:Play()
	scaleTween.Completed:Once(function(status)
		if status ~= Enum.PlaybackState.Completed or token ~= state.token then
			return
		end
		local settle = TweenService:Create(
			state.scale,
			TweenInfo.new(0.13, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Scale = state.base }
		)
		state.scaleTween = settle
		settle:Play()
	end)
end

-- Pastille (petit rond rouge, contour noir, immobile) sur un bouton du HUD ("Shop", "Index"...) pour signaler une nouveaute.
-- Elle disparait quand le joueur ouvre le menu correspondant.
local badges: { [string]: Frame } = {}

function MenuController.SetBadge(buttonName: string, visible: boolean)
	local canvas = hud and hud:FindFirstChild("Canvas")
	local column = canvas and canvas:FindFirstChild("Buttons")
	local four = column and column:FindFirstChild("FourButtons")
	local button = four and four:FindFirstChild(buttonName)
	if not button or not button:IsA("GuiObject") then
		return
	end
	local badge = badges[buttonName]
	if visible and not badge then
		local newBadge = Instance.new("Frame")
		newBadge.Name = "Badge"
		newBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		newBadge.Position = UDim2.fromScale(0.88, 0.12)
		newBadge.Size = UDim2.fromScale(0.26, 0.26)
		newBadge.SizeConstraint = Enum.SizeConstraint.RelativeXX
		newBadge.BackgroundColor3 = Color3.fromRGB(230, 25, 40)
		newBadge.ZIndex = 20
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = newBadge
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = newBadge
		newBadge.Parent = button
		badges[buttonName] = newBadge
	elseif not visible and badge then
		badge:Destroy()
		badges[buttonName] = nil
	end
end

function MenuController.GetActiveMenu(): string?
	return activeMenu
end

-- Liaison des boutons ---------------------------------------------------------------------------

local function hudMenuName(button: GuiButton): string?
	local navigation = hud:FindFirstChild("Canvas") and (hud :: any).Canvas:FindFirstChild("Buttons")
	if navigation and button:IsDescendantOf(navigation) and menus[button.Name] then
		return button.Name
	end
	if button.Name == "ShopButton" then
		return if menus.StockShop then "StockShop" elseif menus.Shop then "Shop" else nil
	end
	local requested = button:GetAttribute("MenuName")
	if type(requested) == "string" and menus[requested] then
		return requested
	end
	return nil
end

local function bindHUDButton(object: Instance)
	if not object:IsA("GuiButton") then
		return
	end
	bindFeedback(object)
	if actionBound[object] then
		return
	end
	actionBound[object] = true
	-- "+" a cote de l'argent : ouvre le Shop directement sur les packs d'argent
	if object.Name == "BuyMoney" and menus.Shop then
		connect(object.Activated, function()
			MenuController.OpenShopSection("CashPacks")
		end)
		return
	end
	local menuName = hudMenuName(object)
	if menuName then
		connect(object.Activated, function()
			MenuController.Open(menuName)
		end)
	end
end

-- Ouvre le Shop (s'il n'est pas deja ouvert) et fait defiler jusqu'a une section ("CashPacks"...).
function MenuController.OpenShopSection(section: string)
	if activeMenu ~= "Shop" then
		MenuController.Open("Shop")
	end
	local module = script.Parent:FindFirstChild("ShopController")
	if module and module:IsA("ModuleScript") then
		local ok, shop = pcall(require, module)
		if ok and type(shop) == "table" and (shop :: any).ScrollToSection then
			(shop :: any).ScrollToSection(section)
		end
	end
end

local function bindMenuButton(object: Instance)
	if not object:IsA("GuiButton") then
		return
	end
	local frame: Instance? = object.Parent
	while frame and frame.Parent ~= menuFrames do
		frame = frame.Parent
	end
	if not frame or not menus[frame.Name] then
		return
	end
	local isRebirth = frame.Name == "Rebirth"
	-- Menu Rebirth : ses boutons decoratifs restent sans animation, mais pas la croix (2026-11-20)
	if not isRebirth or object.Name == "RebirthButton" or object.Name == "SkipButton" or object.Name == "ExitButton" then
		bindFeedback(object)
	end
	if object.Name == "ExitButton" and not actionBound[object] then
		actionBound[object] = true
		connect(object.Activated, MenuController.Close)
	end
end

-- Bouton X des menus : le pack dessinait un fond rouge fonce sous l'image (bande en bas, comme un
-- 2e bouton derriere). On garde une seule plaque rouge PackStyle, pleine taille, sans ce fond.
local function styleExitButton(header: Instance)
	local exit = header:FindFirstChild("ExitButton")
	if exit == nil or not exit:IsA("TextButton") then
		return
	end
	exit.BackgroundTransparency = 1
	exit.TextTransparency = 1
	local padding = exit:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 0)
	end
	local plate = exit:FindFirstChildOfClass("ImageLabel")
	if plate == nil then
		return
	end
	-- Appui / survol : c'est la plaque (centree) qui change de taille. Le bouton est range dans le
	-- UIListLayout de l'en-tete : reduit, il etait recolle en haut a gauche (retour utilisateur 2026-11-20).
	-- Deja branche (ButtonFxController passe parfois avant) : debranche, il sera rebranche sur la plaque.
	ButtonFx.Unbind(exit)
	local oldScale = exit:FindFirstChildOfClass("UIScale")
	if oldScale then
		oldScale:Destroy()
	end
	exit:SetAttribute("FxTarget", plate.Name)
	local gradient = plate:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Rotation = -90
		gradient.Color = ColorSequence.new(PackStyle.RED[1], PackStyle.RED[2])
	end
	local cross = plate:FindFirstChildOfClass("TextLabel")
	if cross then
		cross.FontFace = PackStyle.FONT
	end
end

-- Meme en-tete pour tous les menus (le pack donnait une couleur par menu : rose, gris, vert...).
local function styleHeader(menu: Instance)
	local header = menu:FindFirstChild("Header")
	if header then
		styleExitButton(header)
	end
	local subHeader = header and header:FindFirstChild("SubHeader")
	if subHeader == nil or not subHeader:IsA("GuiObject") then
		return
	end
	subHeader.BackgroundColor3 = PackStyle.HEADER[3] -- bord du bas (relief)
	local band = subHeader:FindFirstChildOfClass("ImageLabel")
	if band == nil then
		return
	end
	local icon: ImageLabel? = nil
	local title: TextLabel? = nil
	for _, child in band:GetChildren() do
		if child:IsA("UIGradient") then
			child.Color = ColorSequence.new(PackStyle.HEADER[1], PackStyle.HEADER[2])
		elseif child:IsA("ImageLabel") and icon == nil then
			icon = child
		elseif child:IsA("TextLabel") and title == nil then
			title = child
		end
	end
	if title == nil then
		return
	end
	title.Size = HEADER_TITLE_SIZE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.FontFace = PackStyle.FONT
	-- Icone manquante (Settings) : copie de celle de l'Index avec la bonne image
	local image = HEADER_ICONS[menu.Name]
	if icon == nil and image then
		local index = menuFrames:FindFirstChild("Index")
		local model = index and index:FindFirstChild("Header")
		model = model and model:FindFirstChild("SubHeader")
		model = model and model:FindFirstChildOfClass("ImageLabel")
		local modelIcon = model and model:FindFirstChildOfClass("ImageLabel")
		if modelIcon then
			local copy = modelIcon:Clone()
			copy.Image = image
			copy.LayoutOrder = title.LayoutOrder - 1
			copy.Parent = band
		end
	end
end

-- Ajoute un menu cree par code (copie d'un menu du pack) : meme ouverture/fermeture que les autres.
-- `frame` doit avoir un "Header" avec un ExitButton, comme les menus du pack.
function MenuController.RegisterMenu(frame: GuiObject)
	local scale = getScale(frame, "MenuPopScale")
	menus[frame.Name] = { frame = frame, scale = scale, base = scale.Scale, home = frame.Position, token = 0 }
	frame.Visible = false
	styleHeader(frame)
	frame.Parent = menuFrames
	for _, object in frame:GetDescendants() do
		bindMenuButton(object)
	end
end

-- Copie vide d'un menu du pack (en-tete + corps vide) pour construire un nouveau menu.
function MenuController.CloneMenuTemplate(templateName: string, newName: string): GuiObject?
	local template = menuFrames:FindFirstChild(templateName)
	if not template or not template:IsA("GuiObject") then
		return nil
	end
	local copy = template:Clone()
	copy.Name = newName
	local body = copy:FindFirstChild("Shop")
	if body then
		for _, child in body:GetChildren() do
			if not child:IsA("UIAspectRatioConstraint") then
				child:Destroy()
			end
		end
	end
	local scale = copy:FindFirstChildOfClass("UIScale")
	if scale then
		scale:Destroy()
	end
	return copy
end

-- Bouton Settings dans la barre du haut (TopbarPlus) --------------------------------------------

local function setupSettingsIcon()
	if not menus.Settings then
		return
	end
	local vendor = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vendor")
	local Icon = require(vendor:WaitForChild("TopbarPlus"):WaitForChild("Icon") :: ModuleScript) :: any
	local settingsIcon = Icon.new()
	settingsIcon:setImage(SETTINGS_ICON_IMAGE)
	pcall(function()
		settingsIcon:setImageScale(SETTINGS_ICON_SCALE)
	end)
	settingsIcon.selected:Connect(function()
		if activeMenu ~= "Settings" then
			MenuController.Open("Settings")
		end
	end)
	settingsIcon.deselected:Connect(function()
		if activeMenu == "Settings" then
			MenuController.Close()
		end
	end)
	connect(hud:GetAttributeChangedSignal("ActiveMenu"), function()
		local isSettings = hud:GetAttribute("ActiveMenu") == "Settings"
		-- Dans TopbarPlus, isSelected est un champ (pas une fonction).
		if isSettings and not settingsIcon.isSelected then
			settingsIcon:select()
		elseif not isSettings and settingsIcon.isSelected then
			settingsIcon:deselect()
		end
	end)
end

-- Cycle de vie ----------------------------------------------------------------------------------

-- Applique HUD_LAYOUT et les tailles de menus.
local function applyLayout()
	local canvas = hud:FindFirstChild("Canvas")
	if not canvas then
		return
	end
	local c = canvas :: any
	local buttons = c:FindFirstChild("Buttons")
	local touch = UserInputService.TouchEnabled
	if buttons then
		-- Taille visuelle des offres de droite : la grille a 2 colonnes (cellule = 0.5 de la largeur),
		-- donc la colonne fait 2 fois la largeur d'une offre, x LEFT_BUTTON_SCALE (icone pleine largeur). Hauteur 1 : c'est la largeur qui decide
		-- (UIAspectRatioConstraint du .rbxm), comme pour les offres.
		local camera = workspace.CurrentCamera
		local phone = camera ~= nil and camera.ViewportSize.Y < 450
		local width = 2
			* PackStyle.LEFT_BUTTON_SCALE
			* (if phone then PackStyle.SIDE_BUTTON_WIDTH_PHONE else PackStyle.SIDE_BUTTON_WIDTH)
		buttons.Size = UDim2.fromScale(width, 1)
		-- Bord gauche de Shop/Index a la meme marge que le bord droit des offres.
		local shop = buttons:FindFirstChild("Shop", true)
		if shop and shop:IsA("GuiObject") then
			buttons.Position = UDim2.fromScale(0.5, buttons.Position.Y.Scale)
			task.wait() -- laisser la grille placer les boutons
			local frameSize = buttons.AbsoluteSize.X
			if frameSize > 0 then
				local inside = (shop.AbsolutePosition.X - buttons.AbsolutePosition.X) / frameSize
				local x = PackStyle.SIDE_MARGIN + width * (buttons.AnchorPoint.X - inside)
				buttons.Position = UDim2.fromScale(x, buttons.Position.Y.Scale)
			end
		end
		local indexIcon = buttons:FindFirstChild("Index", true)
		local icon = indexIcon and indexIcon:FindFirstChild("Icon", true)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = HUD_LAYOUT.IndexIcon
		end
	end
	-- Anciennes offres du pack (X2 Money / X2 Luck) : remplacees par OffersController.
	local oldOffers = hud:FindFirstChild("Gamepasses")
	if oldOffers and oldOffers:IsA("GuiObject") then
		oldOffers.Visible = false
	end
	local money = c:FindFirstChild("Money")
	if money then
		money.Position = HUD_LAYOUT.MoneyPosition
		money.Size = UDim2.fromScale(money.Size.X.Scale, if touch then HUD_LAYOUT.MoneyHeight else HUD_LAYOUT.MoneyHeightPC)
		local buyMoney = money:FindFirstChild("BuyMoney", true)
		if buyMoney and buyMoney:IsA("GuiObject") then
			local buySize = if touch then HUD_LAYOUT.BuyMoneySize else HUD_LAYOUT.BuyMoneySizePC
			buyMoney.Size = UDim2.fromScale(buySize, buySize)
		end
		-- Ecran tactile : l'argent s'aligne sous le bouton Index (meme bord gauche), un peu plus bas.
		if UserInputService.TouchEnabled and buttons then
			task.wait() -- laisser la mise en page calculer la position du bouton
			local index = buttons:FindFirstChild("Index", true)
			if index and index:IsA("GuiObject") then
				local left = index.AbsolutePosition.X - hud.AbsolutePosition.X
				money.Position = UDim2.new(0, left, HUD_LAYOUT.MoneyTouchY, 0)
			end
		end
	end
	-- Contours de texte : coins arrondis (les coins pointus faisaient des pics sur les lettres).
	for _, gui in { hud, shopGUI } do
		for _, d in gui:GetDescendants() do
			if d:IsA("UIStroke") and d.Parent and (d.Parent:IsA("TextLabel") or d.Parent:IsA("TextButton")) then
				d.LineJoinMode = Enum.LineJoinMode.Round
			end
		end
	end
	-- Telephone : memes proportions que sur PC (demande utilisateur). Mettre `phone` a vrai pour
	-- reutiliser PHONE_MENU_* si besoin plus tard.
	local phone = false
	for name, baseAspect in MENU_ASPECT do
		local menu = menuFrames:FindFirstChild(name)
		local aspect = if phone then PHONE_MENU_ASPECT[name] else baseAspect
		if menu and menu:IsA("GuiObject") then
			local width = if phone then PHONE_MENU_WIDTH[name] else MENU_WIDTH[name]
			local height = if phone then PHONE_MENU_HEIGHT else menu.Size.Y.Scale
			menu.Size = UDim2.new(width, 0, height, 0)
			local ratio = menu:FindFirstChildOfClass("UIAspectRatioConstraint")
			if ratio then
				ratio.AspectRatio = aspect
			end
			-- En-tete (titre + X carre) : meme largeur que le menu. Rapport = largeur / hauteur
			-- naturelles (hauteur = 18 % du menu), et le bandeau titre prend la place restante.
			local header = menu:FindFirstChild("Header")
			local headerRatio = header and header:FindFirstChildOfClass("UIAspectRatioConstraint")
			if header and headerRatio then
				local ratio = aspect / HEADER_HEIGHT
				headerRatio.AspectRatio = ratio
				local subHeader = header:FindFirstChild("SubHeader")
				if subHeader and subHeader:IsA("GuiObject") then
					subHeader.Size = UDim2.fromScale(1 - 1 / ratio - HEADER_GAP, subHeader.Size.Y.Scale)
				end
			end
			local body = menu:FindFirstChild("Shop")
			local bodyRatio = body and body:FindFirstChildOfClass("UIAspectRatioConstraint")
			if bodyRatio then
				bodyRatio.AspectRatio = aspect / MENU_BODY_HEIGHT
			end
		end
	end
end

-- Attend l'interface (appele au debut de Start : Init ne doit pas attendre).
local function setup()
	local playerGui = player:WaitForChild("PlayerGui")
	hud = playerGui:WaitForChild("HUD") :: ScreenGui
	shopGUI = playerGui:WaitForChild("ShopGUI") :: ScreenGui
	menuFrames = shopGUI:WaitForChild("MenuFrames") :: Frame

	local assets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets")
	soundTemplates = assets:WaitForChild("UISounds") :: Folder

	shopGUI.DisplayOrder = math.max(shopGUI.DisplayOrder, hud.DisplayOrder + 10)
	-- Les menus restent sous la barre Roblox du haut (sinon le bouton Settings chevauche l'en-tete).
	shopGUI.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Avant toute copie de menu (CloneMenuTemplate) : les copies gardent l'icone cadeau.
	local icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Icons")) :: any
	for _, object in menuFrames:GetDescendants() do
		if object:IsA("ImageLabel") and object.Image == PACK_ARROW_ICON then
			object.Image = icons.Gift
		end
	end

	applyLayout()
	shopGUI.Enabled = true
	menuFrames.Visible = true
	menuFrames.Active = false

	blur = Instance.new("BlurEffect")
	blur.Name = "MenuBackgroundBlur"
	blur.Size = 0
	blur.Enabled = false -- active seulement quand un menu est ouvert
	blur.Parent = Lighting

	soundFolder = Instance.new("Folder")
	soundFolder.Name = "MenuUISounds"
	soundFolder.Parent = player:WaitForChild("PlayerGui")
end

local ready = false

-- Attend que les menus du pack soient prets (setup fait dans Start). Faux apres le delai.
function MenuController.WaitUntilReady(timeoutSeconds: number): boolean
	local startedAt = os.clock()
	while not ready and os.clock() - startedAt < timeoutSeconds do
		task.wait(0.1)
	end
	return ready
end

function MenuController:Start()
	ButtonFx.SetSoundPlayer(playSound)
	setup()
	ready = true

	for _, name in SOUND_NAMES do
		prepareSound(name)
	end
	task.spawn(function()
		local preload: { Instance } = {}
		for _, pool in soundPools do
			for _, voice in pool.voices do
				table.insert(preload, voice)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
	end)

	-- Un panneau est un menu s'il a un "Header".
	for _, child in menuFrames:GetChildren() do
		if child:IsA("GuiObject") and child:FindFirstChild("Header") then
			local scale = getScale(child, "MenuPopScale")
			-- Petits ecrans (telephone) : menus 25 % plus grands pour rester lisibles.
			local camera = workspace.CurrentCamera
			if camera and camera.ViewportSize.Y < 450 then
				scale.Scale = SMALL_SCREEN_MENU_SCALE
			end
			menus[child.Name] = { frame = child, scale = scale, base = scale.Scale, home = child.Position, token = 0 }
			child.Visible = false
			styleHeader(child)
		end
	end
	-- Index : contenu refait par IndexController (grille des 100 fruits, plus de filtres de rarete)
	hud:SetAttribute("ActiveMenu", "")

	local canvas = hud:WaitForChild("Canvas")
	addHUDGroup(canvas:FindFirstChild("TopButtons"), "Up")
	addHUDGroup(canvas:FindFirstChild("Buttons"), "Left")
	addHUDGroup(canvas:FindFirstChild("Money"), "Down")
	addHUDGroup(canvas:FindFirstChild("ProgressBar"), "Down")
	addHUDGroup(hud:FindFirstChild("Gamepasses"), "Right")
	addHUDGroup(hud:FindFirstChild("Multipliers"), "Right")

	for _, object in hud:GetDescendants() do
		bindHUDButton(object)
	end
	connect(hud.DescendantAdded, bindHUDButton)
	for _, object in menuFrames:GetDescendants() do
		bindMenuButton(object)
	end
	connect(menuFrames.DescendantAdded, bindMenuButton)

	connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.ButtonB and activeMenu then
			MenuController.Close()
		end
	end)
	connect(UserInputService.WindowFocusReleased, function()
		ButtonFx.ResetUnder(player:WaitForChild("PlayerGui"))
	end)
	connect(player.CharacterRemoving, function()
		if activeMenu then
			MenuController.Close()
		end
	end)

	local ok, err = pcall(setupSettingsIcon)
	if not ok then
		warn(`[MenuController] Bouton Settings indisponible : {err}`)
	end
end

return MenuController
