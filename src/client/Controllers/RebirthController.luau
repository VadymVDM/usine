--!strict
-- Menu Rebirth (ShopGUI.MenuFrames.Rebirth du pack) + fete du rebirth. Doc : docs/systems/rebirth.md
--   * Ouverture : E sur la machine doree de SA salle du Rebirth (prompt "RebirthPrompt" pose par
--     FloorService, actif seulement a l'etage 10). Pas de bouton dans le HUD (decision : le rebirth
--     se fait dans la salle).
--   * Contenu du pack rempli ici : "Now: x1 Cash / Rebirth 0" -> "After: x2 Cash / Rebirth 1",
--     barre de progression (argent / prix, ou "Floor 7 / 10"), avertissement, bouton vert
--     "Rebirth" (2e clic dans les ConfirmSeconds = confirmation), bouton violet "KEEP CASH" (Robux,
--     prix du palier du joueur).
--   * Le serveur decide de tout (remote RebirthRequest, RebirthService) ; le client lit l'attribut
--     joueur "Rebirths", leaderstats.Cash et l'attribut FloorsOwned de sa base (affichage seulement).
--   * Fete : quand l'attribut "Rebirths" monte (pas au chargement) : menu ferme, flash blanc,
--     "REBIRTH!" + "x3 CASH", confettis, feux d'artifice, son.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rebirth = require(Config:WaitForChild("Rebirth"))
local Icons = require(Config:WaitForChild("Icons")) :: { [string]: string }
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local Util = Shared:WaitForChild("Util")
local SoundFx = require(Util:WaitForChild("SoundFx")) :: any
local NumberFormat = require(Util:WaitForChild("NumberFormat"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Celebration = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Celebration"))
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local TextPop = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("TextPop"))

local MENU_NAME = "Rebirth"
local PROMPT_NAME = "RebirthPrompt"
local REBIRTHS_ATTRIBUTE = "Rebirths"
local CELEBRATE_SOUND = "NewFruit" -- "Cute level up" (Config/Sounds), comme "NEW FLOOR!"
local BANNER_SECONDS = 2.6
local GOLD = Color3.fromRGB(255, 205, 50)
local RANK_STROKE = Color3.fromRGB(70, 40, 0)
local PARTY = {
	GOLD,
	Color3.fromRGB(255, 245, 140),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(120, 255, 110),
	Color3.fromRGB(255, 120, 200),
}

local RebirthController = {}

local player = Players.LocalPlayer
local started = false
local requestEvent: RemoteEvent? = nil
local menus: any = nil
local lastRebirths: number? = nil
local confirmToken = 0

type Ui = {
	menu: GuiObject,
	cashBefore: TextLabel?,
	cashAfter: TextLabel?,
	rankBefore: TextLabel?,
	rankAfter: TextLabel?,
	fill: GuiObject?,
	progress: TextLabel?,
	rebirthLabel: TextLabel?,
	keepHolder: GuiObject?, -- fond du bouton violet : y poser la rangee [Robux] prix
	keepRow: Frame?,
	keepShown: number?, -- prix affiche (la rangee n'est refaite que s'il change)
}

local ui: Ui? = nil

local function menuController(): any?
	local module = script.Parent:FindFirstChild("MenuController")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

---------------------------------------------------------------------------------------------
-- Etat du joueur (affichage seulement)

local function rebirthCount(): number
	local value = player:GetAttribute(REBIRTHS_ATTRIBUTE)
	return if type(value) == "number" then value else 0
end

local function cash(): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function myBase(): Model?
	local bases = workspace:FindFirstChild("Bases")
	for _, base in (if bases then bases:GetChildren() else {}) do
		if base:IsA("Model") and base:GetAttribute("OwnerUserId") == player.UserId then
			return base
		end
	end
	return nil
end

local function floorsOwned(): number
	local base = myBase()
	local value = base and base:GetAttribute("FloorsOwned")
	return if type(value) == "number" then value else 0
end

-- Le prompt est-il dans MA base ?
local function isMine(prompt: Instance): boolean
	local bases = workspace:FindFirstChild("Bases")
	local current: Instance? = prompt
	while current and current.Parent ~= bases do
		current = current.Parent
	end
	return current ~= nil and current:GetAttribute("OwnerUserId") == player.UserId
end

---------------------------------------------------------------------------------------------
-- Menu

local function find(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function textAt(root: Instance, path: { string }): TextLabel?
	local found = find(root, path)
	return if found and found:IsA("TextLabel") then found else nil
end

local function setText(label: TextLabel?, text: string)
	if label then
		label.Text = text
	end
end

function RebirthController.Refresh()
	local current = ui
	if current == nil then
		return
	end
	local r = rebirthCount()
	setText(current.cashBefore, string.format(Rebirth.Texts.Cash, Rebirth.FormatMultiplier(Rebirth.Multiplier(r))))
	setText(current.cashAfter, string.format(Rebirth.Texts.Cash, Rebirth.FormatMultiplier(Rebirth.Multiplier(r + 1))))
	setText(current.rankBefore, string.format(Rebirth.Texts.Rank, r))
	setText(current.rankAfter, string.format(Rebirth.Texts.Rank, r + 1))
	local floors = floorsOwned()
	local ratio: number
	if floors < Rebirth.RequiredFloors then
		ratio = floors / Rebirth.RequiredFloors
		setText(current.progress, string.format(Rebirth.Texts.NeedFloor, floors, Rebirth.RequiredFloors))
	else
		local price = Rebirth.Price(r)
		local money = cash()
		ratio = if price > 0 then money / price else 1
		setText(current.progress, `{if money >= price then NumberFormat.Price(price) else NumberFormat.Money(money)} / {NumberFormat.Price(price)}`)
	end
	if current.fill then
		current.fill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, current.fill.Size.Y.Scale, current.fill.Size.Y.Offset)
	end
	local keepPrice = Rebirth.KeepCashProduct(r).price
	if current.keepHolder and current.keepShown ~= keepPrice then
		if current.keepRow then
			current.keepRow:Destroy()
		end
		local row = PackStyle.priceRow(current.keepHolder, Icons.Robux, keepPrice, UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.9, 0.34))
		row.ZIndex = current.keepHolder.ZIndex + 2
		for _, item in row:GetDescendants() do
			if item:IsA("GuiObject") then
				item.ZIndex = current.keepHolder.ZIndex + 2
			end
		end
		current.keepRow = row
		current.keepShown = keepPrice
	end
	setText(current.rebirthLabel, if confirmToken > 0 then Rebirth.Texts.Confirm else Rebirth.Texts.Button)
end

local function isOpen(): boolean
	return menus ~= nil and menus.GetActiveMenu() == MENU_NAME
end

local function onRebirthClicked()
	local event = requestEvent
	if event == nil then
		return
	end
	-- 2e clic dans les ConfirmSeconds : on demande le rebirth (le serveur verifie tout)
	if confirmToken > 0 then
		confirmToken = 0
		RebirthController.Refresh()
		event:FireServer("Rebirth")
		return
	end
	local r = rebirthCount()
	if floorsOwned() < Rebirth.RequiredFloors or cash() < Rebirth.Price(r) then
		-- Pas pret : le serveur repond "Not enough money!" / "Reach Floor 10 first!"
		event:FireServer("Rebirth")
		return
	end
	confirmToken += 1
	local token = confirmToken
	RebirthController.Refresh()
	task.delay(Rebirth.ConfirmSeconds, function()
		if confirmToken == token then
			confirmToken = 0
			RebirthController.Refresh()
		end
	end)
end

local function onKeepCashClicked()
	if requestEvent then
		requestEvent:FireServer("KeepCash")
	end
end

-- Case "x1 Cash" / "Rebirth 0" du pack : c'etait un bouton vert / orange (retour utilisateur du
-- 2026-11-20 : "on dirait des boutons"). Devient du texte colore avec une icone a gauche : fond,
-- contour et clic retires.
local function plainStat(box: Instance?, icon: string, color: Color3, strokeColor: Color3): TextLabel?
	if box == nil or not box:IsA("GuiObject") then
		return nil
	end
	box.BackgroundTransparency = 1
	box.Selectable = false
	box:SetAttribute("NoButtonFx", true)
	if box:IsA("GuiButton") then
		box.AutoButtonColor = false
		box.Active = false
	end
	for _, child in box:GetChildren() do
		if child:IsA("ImageLabel") then
			child.Visible = false
		elseif child:IsA("UIStroke") then
			child.Enabled = false
		end
	end
	local image = Instance.new("ImageLabel")
	image.Name = "StatIcon"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.13, 0.5)
	image.Size = UDim2.fromScale(0.95, 0.95)
	image.SizeConstraint = Enum.SizeConstraint.RelativeYY
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = icon
	image.ZIndex = box.ZIndex + 1
	image.Parent = box
	local label = box:FindFirstChild("CashMultiplier")
	if label == nil or not label:IsA("TextLabel") then
		return nil
	end
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.64, 0.5)
	label.Size = UDim2.fromScale(0.7, 0.8)
	label.TextColor3 = color
	label.ZIndex = box.ZIndex + 1
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = strokeColor
	end
	return label
end

-- Police du jeu sur tous les textes du menu
local function applyFont(root: Instance)
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			item.FontFace = PackStyle.FONT
		end
	end
end

local function setupMenu(): boolean
	local playerGui = player:WaitForChild("PlayerGui")
	local shopGUI = playerGui:WaitForChild("ShopGUI", 30)
	local frames = shopGUI and shopGUI:WaitForChild("MenuFrames", 30)
	local menu = frames and frames:WaitForChild(MENU_NAME, 30)
	if menu == nil or not menu:IsA("GuiObject") then
		warn("[RebirthController] Menu Rebirth introuvable")
		return false
	end
	local body = menu:FindFirstChild("Shop")
	if body == nil then
		warn("[RebirthController] Corps du menu Rebirth introuvable")
		return false
	end
	applyFont(menu)
	local columns = body:FindFirstChild("Before_After")
	local fill = find(body, { "ProgressBar", "Fill" })
	local function stat(column: string, box: string, icon: string, color: Color3, strokeColor: Color3): TextLabel?
		return plainStat(columns and find(columns, { column, box }), icon, color, strokeColor)
	end
	-- Bouton violet : gros "KEEP CASH" en haut, rangee [Robux] prix dessous (a la place du
	-- sous-titre du pack, qui debordait, et du "19" du pack pose dans le coin sans logo Robux)
	local keepImage = find(body, { "Buttons", "SkipButton", "ImageLabel" })
	local packPrice = find(body, { "Buttons", "SkipButton", "Price" })
	if packPrice and packPrice:IsA("GuiObject") then
		packPrice.Visible = false
	end
	local subtitle = keepImage and keepImage:FindFirstChild("SaveProgress")
	if subtitle and subtitle:IsA("GuiObject") then
		subtitle.Visible = false
	end
	local keepTitle = keepImage and keepImage:FindFirstChild("SKIP")
	if keepTitle and keepTitle:IsA("GuiObject") then
		keepTitle.AnchorPoint = Vector2.new(0.5, 0.5)
		keepTitle.Position = UDim2.fromScale(0.5, 0.34)
		keepTitle.Size = UDim2.fromScale(0.92, 0.56)
	end
	local current: Ui = {
		menu = menu,
		cashBefore = stat("BeforeColumn", "CashBefore", Icons.Cash, PackStyle.MONEY_GREEN, PackStyle.MONEY_STROKE),
		cashAfter = stat("AfterColumn", "CashAfter", Icons.Cash, PackStyle.MONEY_GREEN, PackStyle.MONEY_STROKE),
		rankBefore = stat("BeforeColumn", "PowerBefore", Icons.Rebirth, Rebirth.TitleColor, RANK_STROKE),
		rankAfter = stat("AfterColumn", "PowerAfter", Icons.Rebirth, Rebirth.TitleColor, RANK_STROKE),
		fill = if fill and fill:IsA("GuiObject") then fill else nil,
		progress = textAt(body, { "ProgressBar", "LevelFrame", "LevelLabel" }),
		rebirthLabel = textAt(body, { "Buttons", "RebirthButton", "ImageLabel", "RebirthLabel" }),
		keepHolder = if keepImage and keepImage:IsA("GuiObject") then keepImage else nil,
	}
	if columns then
		setText(textAt(columns, { "BeforeColumn", "Before" }), Rebirth.Texts.Before)
		setText(textAt(columns, { "AfterColumn", "After" }), Rebirth.Texts.After)
	end
	setText(textAt(body, { "Notification" }), Rebirth.Texts.Warning)
	setText(textAt(body, { "Buttons", "SkipButton", "ImageLabel", "SKIP" }), Rebirth.Texts.KeepCash)
	local rebirthButton = find(body, { "Buttons", "RebirthButton" })
	if rebirthButton and rebirthButton:IsA("GuiButton") then
		rebirthButton.Activated:Connect(onRebirthClicked)
	else
		warn("[RebirthController] Bouton RebirthButton introuvable")
	end
	local keepButton = find(body, { "Buttons", "SkipButton" })
	if keepButton and keepButton:IsA("GuiButton") then
		keepButton.Activated:Connect(onKeepCashClicked)
	else
		warn("[RebirthController] Bouton SkipButton introuvable")
	end
	ui = current
	return true
end

---------------------------------------------------------------------------------------------
-- Fete du rebirth

local function flash(screen: ScreenGui)
	local white = Instance.new("Frame")
	white.Name = "Flash"
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 0.05
	white.BorderSizePixel = 0
	white.ZIndex = 1
	white.Parent = screen
	TweenService:Create(white, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function celebrate(count: number)
	if isOpen() then
		menus.Close()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "RebirthFx"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 46
	screen.IgnoreGuiInset = true
	flash(screen)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.4)
	holder.Size = UDim2.fromScale(0.8, 0.3)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	local title = PackStyle.label(holder, Rebirth.Texts.Banner, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.62), 120)
	title.ZIndex = 3
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 245, 120), Color3.fromRGB(255, 160, 20))
	gradient.Parent = title
	local multiplier = Rebirth.FormatMultiplier(Rebirth.Multiplier(count))
	local sub = PackStyle.label(holder, string.format(Rebirth.Texts.BannerSub, multiplier), UDim2.fromScale(0.5, 0.64), UDim2.fromScale(0.7, 0.34), 64)
	sub.TextColor3 = PackStyle.MONEY_GREEN
	sub.ZIndex = 3
	-- Chute "gelee" en fondu, sans grossir (un texte qui grossit clignote sur telephone : UI/TextPop)
	local spring = Jelly.Spring(260, 9)
	spring.x = -0.8
	local drop = TextPop.NewDrop(holder, spring, 0.3)
	holder.Parent = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	SoundFx.Play(CELEBRATE_SOUND)
	Celebration.Confetti(screen.Parent :: Instance, PARTY)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		Celebration.Fireworks(root.Position, PARTY, 22, 8, 22)
	end
	-- Chute gelee, leger balancement, puis fondu (comme "NEW FLOOR!")
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		TextPop.StepDrop(drop, dt, elapsed < BANNER_SECONDS)
		holder.Rotation = math.sin(elapsed * 5) * 3 * math.max(0, 1 - elapsed / BANNER_SECONDS)
		if elapsed >= BANNER_SECONDS + 0.4 then
			connection:Disconnect()
			screen:Destroy()
		end
	end)
	task.delay(BANNER_SECONDS, function()
		for _, label in { title, sub } do
			TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end
	end)
end

local function onRebirthsChanged()
	local now = rebirthCount()
	local before = lastRebirths
	lastRebirths = now
	if before ~= nil and now > before then
		local ok, err = pcall(celebrate, now)
		if not ok then
			warn(`[RebirthController] Erreur de la fete du rebirth : {err}`)
		end
	end
	RebirthController.Refresh()
end

---------------------------------------------------------------------------------------------

function RebirthController:Init() end

function RebirthController:Start()
	if started then
		return
	end
	started = true
	local initial = player:GetAttribute(REBIRTHS_ATTRIBUTE)
	lastRebirths = if type(initial) == "number" then initial else nil
	player:GetAttributeChangedSignal(REBIRTHS_ATTRIBUTE):Connect(onRebirthsChanged)
	task.spawn(function()
		requestEvent = Remotes.WaitClientEvent("RebirthRequest")
	end)
	task.spawn(function()
		menus = menuController()
		if menus then
			menus.WaitUntilReady(30)
		end
		if not setupMenu() then
			return
		end
		RebirthController.Refresh()
		-- Argent qui change pendant que le menu est ouvert : barre a jour
		task.spawn(function()
			local stats = player:WaitForChild("leaderstats", 30)
			local value = stats and stats:WaitForChild("Cash", 30)
			if value and value:IsA("IntValue") then
				value.Changed:Connect(function()
					if isOpen() then
						RebirthController.Refresh()
					end
				end)
			end
		end)
		ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
			if prompt.Name ~= PROMPT_NAME or not isMine(prompt) or menus == nil then
				return
			end
			confirmToken = 0
			RebirthController.Refresh()
			if not isOpen() then
				menus.Open(MENU_NAME)
			end
		end)
	end)
end

return RebirthController
