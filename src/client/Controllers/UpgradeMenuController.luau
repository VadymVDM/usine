--!strict
-- Menu Upgrade (ShopGUI.MenuFrames.Upgrade du pack) + bouton vert "UPGRADE" du HUD
-- (HUD.Canvas.Buttons.UpgradeButton, cache dans le .rbxm : rendu visible ici).
-- Une ligne par amelioration du joueur (Config/PlayerUpgrades) : icone, nom + niveau, effet
-- "20 → 23 speed", "Lv 1/5" (achats faits / possibles) sur l'icone. Bouton vert avec le prix en
-- argent pour les 3 premiers achats, puis violet avec le prix en Robux (icone R$ + 9), MAX au bout. Lignes =
-- copies de la ligne "Speed" du pack (meme look que le menu d'origine).
-- Le serveur decide de tout (remote BuyPlayerUpgrade -> fenetre d'achat Robux ouverte par
-- PlayerUpgradeService) ; le client lit les niveaux dans les attributs joueur "PUp_<id>".
-- Le bouton UPGRADE du HUD ouvre le menu tout seul (MenuController : bouton de Canvas.Buttons qui
-- porte le nom d'un menu).
-- Doc : docs/systems/ameliorations-joueur.md, docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PlayerUpgrades = require(Config:WaitForChild("PlayerUpgrades"))
local Fruits = require(Config:WaitForChild("Fruits"))
local Icons = require(Config:WaitForChild("Icons")) :: { [string]: string }
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local TextPop = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("TextPop"))

local MENU_NAME = "Upgrade"
local TITLE = "Upgrades"
local BUY_SOUND = "NewFruit" -- "Cute level up"
local MAX_TEXT = "MAX"
-- Bouton UPGRADE du HUD : bas de l'ecran, au centre. Hauteur = part de l'ecran, largeur = hauteur x ratio.
local HUD_BUTTON_HEIGHT = 0.11
local HUD_BUTTON_ASPECT = 2.4 -- proportions du bouton du pack
local HUD_BUTTON_HOME = UDim2.fromScale(0.5, 0.985)
local HUD_BUTTON_HIDDEN = UDim2.fromScale(0.5, 1.3)
-- Lignes du menu : les 3 tiennent sans defiler (rapport largeur / hauteur), texte entre l'icone et le prix
local ROW_WIDTH = 0.95
local ROW_ASPECT = 5.2 -- pack : 3.79 (la 3e ligne etait coupee ; 4.9 : collait au bord du bas)
local TEXT_LEFT = 0.235
local TEXT_WIDTH = 0.36
local ROW_GAP = 8 -- pixels entre les lignes
-- Marges de la liste (retour utilisateur : "ca rentre dans la case derriere", "un petit espace en
-- haut"). La liste descend sous le bord epais du bas de la fenetre : la marge du haut suffit, le
-- reste de la hauteur fait l'espace du bas (meme espace visible, mesure en playtest PC).
local EDGE_GAP = 20
local LEVEL_COLOR = Color3.fromRGB(255, 225, 40) -- "Lv 2/5" jaune sur l'icone (achats faits / possibles)
-- Effet "c'est paye" (demande du 2026-11-20 : "le niveau augmente et il n'y a rien de visuel")
local LEVEL_UP_COLOR = Color3.fromRGB(255, 225, 40) -- "LEVEL UP!" / "MAXED!"
local PAID_COLOR = Color3.fromRGB(255, 70, 70) -- "-$40" qui monte du bouton (achat en argent)
local FLASH_COLOR = Color3.fromRGB(210, 255, 180) -- eclair clair sur la ligne
local BURST_COUNT = 12 -- etincelles autour de l'icone
local BURST_COLORS = { Color3.fromRGB(255, 230, 60), Color3.new(1, 1, 1), Color3.fromRGB(110, 255, 80) }
local FX_DISPLAY_OFFSET = 1 -- calque des effets juste au-dessus de ShopGUI

local UpgradeMenuController = {}

local player = Players.LocalPlayer
local started = false
local buyEvent: RemoteEvent? = nil

type Row = {
	id: string,
	frame: GuiObject,
	title: TextLabel?,
	desc: TextLabel?,
	level: TextLabel?,
	button: GuiButton?,
	price: Frame?, -- icone Robux + prix (achats 4 et 5)
	cashLabel: TextLabel?, -- "$40" (3 premiers achats, argent du jeu)
	maxLabel: TextLabel?, -- "MAX" a la place du prix
	scale: UIScale,
	levelScale: UIScale?,
	lastLevel: number,
}

local rows: { Row } = {}
local scrollFrame: ScrollingFrame? = nil

local function menuController(): any?
	local module = script.Parent:FindFirstChild("MenuController")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function levelOf(id: string): number
	local value = player:GetAttribute(PlayerUpgrades.AttributePrefix .. id)
	return if type(value) == "number" then value else 1
end

local function valueText(_id: string, value: number): string
	return tostring(math.floor(value + 0.5))
end

---------------------------------------------------------------------------------------------
-- Affichage

-- Couleurs du bouton de prix (habille une fois par PackStyle.dress) : vert = argent, violet = Robux.
local function setButtonColors(button: GuiButton, colors: { Color3 })
	local gradient = button:FindFirstChildOfClass("UIGradient")
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if gradient then
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	if stroke then
		stroke.Color = colors[3]
	end
end

local function showRow(row: Row)
	local upgrade = PlayerUpgrades.ById[row.id]
	local level = levelOf(row.id)
	local isMax = level >= upgrade.maxLevel
	local now = PlayerUpgrades.GetValue(row.id, level)
	if row.title then
		row.title.Text = upgrade.title
	end
	if row.level then
		row.level.Text = `Lv {PlayerUpgrades.Bought(level)}/{PlayerUpgrades.MaxBought(row.id)}`
	end
	if row.desc then
		if isMax then
			row.desc.Text = `{valueText(row.id, now)} {upgrade.unit}`
		else
			local nextValue = PlayerUpgrades.GetValue(row.id, level + 1)
			row.desc.Text = `{valueText(row.id, now)} → {valueText(row.id, nextValue)} {upgrade.unit}`
		end
	end
	local cashPrice = if isMax then nil else PlayerUpgrades.GetCashPrice(row.id, level)
	local isCash = cashPrice ~= nil
	if row.button then
		setButtonColors(row.button, if isCash then PackStyle.GREEN else PackStyle.PURPLE)
	end
	-- Premier achat de la vitesse gratuit (tutoriel ; le serveur decide : attribut joueur FreeSpeed)
	local free = isCash and row.id == PlayerUpgrades.FreeFirstId and player:GetAttribute("FreeSpeed") == true
	if row.cashLabel then
		row.cashLabel.Visible = isCash
		row.cashLabel.Text = if free then PlayerUpgrades.FreeText elseif cashPrice then NumberFormat.Price(cashPrice) else ""
	end
	if row.price then
		row.price.Visible = not isMax and not isCash
	end
	if row.maxLabel then
		row.maxLabel.Visible = isMax
	end
end

-- Bouton d'achat d'une ligne (fleche du tutoriel, TutorialController)
function UpgradeMenuController.GetBuyButton(id: string): GuiObject?
	for _, row in rows do
		if row.id == id then
			return row.button
		end
	end
	return nil
end

function UpgradeMenuController.Refresh()
	for _, row in rows do
		showRow(row)
	end
end

-- Petit rebond de la ligne achetee
local function pop(row: Row)
	row.scale.Scale = 1
	local grow = TweenService:Create(row.scale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.08 })
	grow.Completed:Once(function()
		TweenService:Create(row.scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	grow:Play()
end

---------------------------------------------------------------------------------------------
-- Effet d'achat confirme : eclair sur la ligne, "-$prix" rouge qui monte du bouton, "LEVEL UP!"
-- jaune, etincelles autour de l'icone, niveau et effet qui grossissent. Textes et etincelles dans
-- un calque a part (la zone de defilement couperait ce qui sort de la ligne).

local fxGui: ScreenGui? = nil

local function fxLayer(): ScreenGui
	local current = fxGui
	if current and current.Parent then
		return current
	end
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpgradeBuyFx"
	gui.ResetOnSpawn = false
	-- Memes reglages d'ecran que ShopGUI : les positions absolues des lignes tombent juste
	local shop = playerGui:FindFirstChild("ShopGUI")
	if shop and shop:IsA("ScreenGui") then
		gui.DisplayOrder = shop.DisplayOrder + FX_DISPLAY_OFFSET
		gui.IgnoreGuiInset = shop.IgnoreGuiInset
		gui.ScreenInsets = shop.ScreenInsets
	end
	gui.Parent = playerGui
	fxGui = gui
	return gui
end

local function centerOf(item: GuiObject): Vector2
	return item.AbsolutePosition + item.AbsoluteSize / 2
end

local function fadeOut(label: TextLabel, delay: number, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delay)
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
end

-- Texte qui apparait en fondu, monte et s'efface (sans grossir : sur telephone un texte qui
-- grossit clignote, UI/TextPop)
local function floatText(text: string, color: Color3, at: Vector2, height: number, rise: number)
	local label = PackStyle.label(fxLayer(), text, UDim2.fromOffset(at.X, at.Y), UDim2.fromOffset(height * 5, height), 90)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.TextColor3 = color
	label.ZIndex = 20
	TextPop.FadeIn(label)
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(at.X, at.Y - rise),
	}):Play()
	fadeOut(label, 0.6, 0.4)
	task.delay(1.1, function()
		label:Destroy()
	end)
end

-- Etincelles (petits losanges) qui partent en cercle et retrecissent
local function burst(at: Vector2, unit: number)
	local layer = fxLayer()
	for index = 1, BURST_COUNT do
		local angle = (index / BURST_COUNT) * math.pi * 2 + (math.random() - 0.5) * 0.4
		local distance = unit * (0.75 + math.random() * 0.5)
		local size = unit * (0.12 + math.random() * 0.08)
		local spark = Instance.new("Frame")
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromOffset(at.X, at.Y)
		spark.Size = UDim2.fromOffset(size, size)
		spark.Rotation = 45
		spark.BorderSizePixel = 0
		spark.BackgroundColor3 = BURST_COLORS[(index - 1) % #BURST_COLORS + 1]
		spark.ZIndex = 19
		PackStyle.stroke(spark, 1.5, PackStyle.TEXT_STROKE)
		spark.Parent = layer
		local target = at + Vector2.new(math.cos(angle), math.sin(angle)) * distance
		TweenService:Create(spark, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(0, 0),
			Rotation = 45 + 180,
		}):Play()
		task.delay(0.6, function()
			spark:Destroy()
		end)
	end
end

-- Eclair clair sur toute la ligne
local function flashRow(row: Row)
	local flash = Instance.new("Frame")
	flash.Name = "BuyFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = FLASH_COLOR
	flash.BackgroundTransparency = 0.2
	flash.ZIndex = 50
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = flash
	flash.Parent = row.frame
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		flash:Destroy()
	end)
end

-- "Lv 3" grossit et passe en vert ; l'effet ("18 → 20 speed") clignote en jaune
local function punchLevel(row: Row)
	local levelScale = row.levelScale
	if levelScale then
		levelScale.Scale = 1
		local grow = TweenService:Create(levelScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.8 })
		grow.Completed:Once(function()
			TweenService:Create(levelScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		grow:Play()
	end
	local level = row.level
	if level then
		level.TextColor3 = PackStyle.MONEY_GREEN
		TweenService:Create(level, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25), { TextColor3 = LEVEL_COLOR }):Play()
	end
	local desc = row.desc
	if desc then
		desc.TextColor3 = LEVEL_UP_COLOR
		TweenService:Create(desc, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25), { TextColor3 = PackStyle.MONEY_GREEN }):Play()
	end
end

local function celebrate(row: Row, paidCash: number?, isMax: boolean)
	SoundFx.Play(BUY_SOUND)
	pop(row)
	flashRow(row)
	punchLevel(row)
	local unit = row.frame.AbsoluteSize.Y
	if paidCash and row.button then
		floatText(`-{NumberFormat.Price(paidCash)}`, PAID_COLOR, centerOf(row.button), unit * 0.42, unit * 0.9)
	end
	floatText(if isMax then "MAXED!" else "LEVEL UP!", LEVEL_UP_COLOR, centerOf(row.frame), unit * 0.5, unit * 1.1)
	local icon = row.frame:FindFirstChild("ItemIcon", true)
	if icon and icon:IsA("GuiObject") then
		burst(centerOf(icon), unit)
	end
end

local function onBuyClicked(row: Row)
	local upgrade = PlayerUpgrades.ById[row.id]
	local level = levelOf(row.id)
	if level >= upgrade.maxLevel then
		return
	end
	-- Le serveur verifie tout et ouvre lui-meme la fenetre d'achat Robux
	if buyEvent then
		buyEvent:FireServer(row.id)
	end
end

---------------------------------------------------------------------------------------------
-- Construction

-- Objet 3D (pomme, gobelet) dans l'icone de la ligne, a la place de l'image.
local function fillViewport(holder: GuiObject, model: Model)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model3D"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(0.95, 0.95)
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.5, -1)
	viewport.ZIndex = holder.ZIndex + 1
	for _, item in model:GetDescendants() do
		if item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("Beam") or item:IsA("Trail") then
			item:Destroy()
		end
	end
	model:PivotTo(CFrame.Angles(0, math.rad(-25), 0))
	local boxCFrame, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.5
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.3
	local center = boxCFrame.Position
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, radius * 0.4, distance), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
	viewport.Parent = holder
end

local function setIcon(rowFrame: Instance, upgrade: PlayerUpgrades.PlayerUpgrade)
	local iconFrame = rowFrame:FindFirstChild("ItemIcon", true)
	if iconFrame == nil or not iconFrame:IsA("GuiObject") then
		return
	end
	local image = iconFrame:FindFirstChildOfClass("ImageLabel")
	if upgrade.icon and image then
		image.Image = Icons[upgrade.icon] or image.Image
		image.ScaleType = Enum.ScaleType.Fit
		return
	end
	-- Pas d'icone : pomme 3D (fruits) ou gobelet 3D (jus)
	local firstFruit = Fruits.List[1].id
	local ok, model = pcall(function()
		if upgrade.id == "JuiceCarry" then
			return FruitModels.CreateCup(firstFruit, true)
		end
		return FruitModels.CreateFruit(firstFruit, true)
	end)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		if image then
			image.Visible = false
		end
		fillViewport(iconFrame, model)
	end
end

local function makeRow(template: GuiObject, upgrade: PlayerUpgrades.PlayerUpgrade, parent: Instance): Row
	local frame = template:Clone()
	frame.Name = upgrade.id
	frame.LayoutOrder = upgrade.order
	local scale = Instance.new("UIScale")
	scale.Name = "BuyPopScale"
	scale.Parent = frame
	-- Police du jeu partout
	for _, item in frame:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			item.FontFace = PackStyle.FONT
		end
	end
	local row: Row = { id = upgrade.id, frame = frame, scale = scale, lastLevel = levelOf(upgrade.id) }
	-- Hauteur tiree de la largeur (le Y en echelle du pack suivait la zone de defilement)
	frame.Size = UDim2.new(ROW_WIDTH, 0, 0, 1000)
	local rowRatio = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if rowRatio then
		rowRatio.AspectRatio = ROW_ASPECT
		rowRatio.DominantAxis = Enum.DominantAxis.Width
	end
	local description = frame:FindFirstChild("UpgradeDescription", true)
	if description and description:IsA("GuiObject") then
		-- Zone de texte entre l'icone et le bouton (le pack : carre etroit, textes minuscules)
		local square = description:FindFirstChildOfClass("UIAspectRatioConstraint")
		if square then
			square:Destroy()
		end
		description.AnchorPoint = Vector2.new(0, 0.5)
		description.Position = UDim2.fromScale(TEXT_LEFT, 0.5)
		description.Size = UDim2.fromScale(TEXT_WIDTH, 0.9)
		local padding = description:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, 0)
			padding.PaddingRight = UDim.new(0, 0)
		end
		local layout = description:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.Padding = UDim.new(0.04, 0)
		end
		local spare = description:FindFirstChild("TextLabel")
		if spare and spare:IsA("GuiObject") then
			spare.Visible = false
		end
		-- Textes du pack caches et remplaces par des PackStyle.label (ceux du pack repassaient en
		-- petite taille fixe 14 apres l'ouverture, cause non trouvee)
		for _, name in { "Upgrade", "Description" } do
			local old = description:FindFirstChild(name)
			if old and old:IsA("GuiObject") then
				old.Visible = false
			end
		end
		local title = PackStyle.label(description, "", UDim2.new(), UDim2.fromScale(1, 0.36), 34)
		title.Name = "Title"
		local desc = PackStyle.label(description, "", UDim2.new(), UDim2.fromScale(1, 0.28), 26)
		desc.Name = "Effect"
		desc.TextColor3 = PackStyle.MONEY_GREEN
		for index, label in { title, desc } do
			label.AnchorPoint = Vector2.zero
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.LayoutOrder = index
		end
		row.title = title
		row.desc = desc
	end
	local buy = frame:FindFirstChild("BuyButton", true)
	if buy then
		local purple = buy:FindFirstChild("Purple")
		if purple and purple:IsA("GuiObject") then
			purple.Visible = false -- bouton Robux du pack pas utilise : le bouton du dessous est habille en violet
		end
		local layout = buy:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		end
		local green = buy:FindFirstChild("GreenButton")
		if green and green:IsA("GuiButton") then
			green.Size = UDim2.fromScale(green.Size.X.Scale, 0.5)
			-- Marge du pack en bas du bouton : elle decalait le liseré blanc (retour utilisateur 2026-11-20)
			local padding = green:FindFirstChildOfClass("UIPadding")
			if padding then
				padding:Destroy()
			end
			PackStyle.dress(green, PackStyle.PURPLE)
			local price = PackStyle.priceRow(green, Icons.Robux, PlayerUpgrades.RobuxPrice, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76))
			price.ZIndex = green.ZIndex + 2
			local maxLabel = PackStyle.label(green, MAX_TEXT, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 40)
			maxLabel.Name = "Max"
			maxLabel.ZIndex = green.ZIndex + 2
			maxLabel.Visible = false
			local cashLabel = PackStyle.label(green, "", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 40)
			cashLabel.Name = "CashPrice"
			cashLabel.ZIndex = green.ZIndex + 2
			cashLabel.Visible = false
			row.cashLabel = cashLabel
			row.button = green
			row.price = price
			row.maxLabel = maxLabel
			green.Activated:Connect(function()
				onBuyClicked(row)
			end)
		end
	end
	setIcon(frame, upgrade)
	-- Niveau en petit sur l'icone (dans le titre, "Fruit Tray  Lv 1" etait coupe)
	local iconFrame = frame:FindFirstChild("ItemIcon", true)
	if iconFrame then
		local level = PackStyle.label(iconFrame, "", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.9, 0.3), 30)
		level.Name = "Level"
		level.TextColor3 = LEVEL_COLOR
		level.ZIndex = 10
		local levelScale = Instance.new("UIScale")
		levelScale.Parent = level
		row.level = level
		row.levelScale = levelScale
	end
	frame.Parent = parent
	return row
end

-- Bouton vert UPGRADE : sorti de la colonne Shop / Index (trop etroite : il debordait de l'ecran)
-- et pose en bas au centre (demande : "en bas"). Il descend hors de l'ecran quand un menu est ouvert.
local function setupHudButton(hud: Instance)
	local holder = hud:FindFirstChild("UpgradeButton", true)
	local canvas = hud:FindFirstChild("Canvas")
	if holder == nil or not holder:IsA("GuiObject") or canvas == nil then
		warn("[UpgradeMenuController] Bouton UpgradeButton du HUD introuvable")
		return
	end
	local button = holder:FindFirstChild(MENU_NAME)
	if button then
		button:SetAttribute("MenuName", MENU_NAME) -- MenuController : ouvre le menu Upgrade
	end
	for _, item in holder:GetDescendants() do
		if item:IsA("TextLabel") then
			item.FontFace = PackStyle.FONT
		end
	end
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Size = UDim2.fromScale(1, HUD_BUTTON_HEIGHT)
	local ratio = holder:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ratio == nil then
		local created = Instance.new("UIAspectRatioConstraint")
		created.Parent = holder
		ratio = created
	end
	local constraint = ratio :: UIAspectRatioConstraint
	constraint.AspectRatio = HUD_BUTTON_ASPECT
	constraint.DominantAxis = Enum.DominantAxis.Height
	holder.Position = HUD_BUTTON_HOME
	holder.Parent = canvas
	holder.Visible = true

	local tween: Tween? = nil
	local function onMenu()
		local open = hud:GetAttribute("ActiveMenu")
		local hidden = type(open) == "string" and open ~= ""
		if tween then
			tween:Cancel()
		end
		local newTween = TweenService:Create(
			holder,
			TweenInfo.new(if hidden then 0.21 else 0.27, if hidden then Enum.EasingStyle.Cubic else Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = if hidden then HUD_BUTTON_HIDDEN else HUD_BUTTON_HOME }
		)
		tween = newTween
		newTween:Play()
	end
	hud:GetAttributeChangedSignal("ActiveMenu"):Connect(onMenu)
	onMenu()
end

local function setupMenu(): boolean
	local playerGui = player:WaitForChild("PlayerGui")
	local shopGUI = playerGui:WaitForChild("ShopGUI", 30)
	local frames = shopGUI and shopGUI:WaitForChild("MenuFrames", 30)
	local menu = frames and frames:WaitForChild(MENU_NAME, 30)
	if menu == nil or not menu:IsA("GuiObject") then
		warn("[UpgradeMenuController] Menu Upgrade introuvable")
		return false
	end
	local body = menu:FindFirstChild("Shop")
	local scroll = body and body:FindFirstChildOfClass("ScrollingFrame")
	local template = scroll and scroll:FindFirstChild("Speed")
	if scroll == nil or template == nil or not template:IsA("GuiObject") then
		warn("[UpgradeMenuController] Ligne modele du menu Upgrade introuvable")
		return false
	end
	local model = template:Clone()
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = scroll:FindFirstChildOfClass("UIListLayout")
	if list then
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Padding = UDim.new(0, ROW_GAP)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
	end
	local scrollPadding = scroll:FindFirstChildOfClass("UIPadding")
	if scrollPadding then
		scrollPadding.PaddingTop = UDim.new(0, EDGE_GAP)
		scrollPadding.PaddingBottom = UDim.new(0, EDGE_GAP)
	end
	-- Le pack avait une zone de defilement 5.5 fois trop haute (lignes perdues tout en bas)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasPosition = Vector2.zero
	scrollFrame = scroll
	for _, upgrade in PlayerUpgrades.List do
		table.insert(rows, makeRow(model, upgrade, scroll))
	end
	model:Destroy()
	-- Titre de l'en-tete
	local header = menu:FindFirstChild("Header")
	local sub = header and header:FindFirstChild("SubHeader")
	local band = sub and sub:FindFirstChildOfClass("ImageLabel")
	local title = band and band:FindFirstChildOfClass("TextLabel")
	if title then
		title.Text = TITLE
	end
	return true
end

function UpgradeMenuController:Init() end

function UpgradeMenuController:Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		buyEvent = Remotes.WaitClientEvent("BuyPlayerUpgrade")
	end)
	task.spawn(function()
		local menus = menuController()
		if menus then
			menus.WaitUntilReady(30)
		end
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD", 30)
		if hud then
			setupHudButton(hud)
		end
		if not setupMenu() then
			return
		end
		UpgradeMenuController.Refresh()
		player:GetAttributeChangedSignal("FreeSpeed"):Connect(UpgradeMenuController.Refresh)
		-- A chaque ouverture : liste en haut, valeurs a jour
		if hud then
			hud:GetAttributeChangedSignal("ActiveMenu"):Connect(function()
				if hud:GetAttribute("ActiveMenu") == MENU_NAME then
					if scrollFrame then
						scrollFrame.CanvasPosition = Vector2.zero
					end
					UpgradeMenuController.Refresh()
				end
			end)
		end
		-- Niveau monte (achat confirme par le serveur) : effet "c'est paye". Un niveau qui baisse
		-- (Rebirth, admin) met juste l'affichage a jour.
		for _, row in rows do
			player:GetAttributeChangedSignal(PlayerUpgrades.AttributePrefix .. row.id):Connect(function()
				showRow(row)
				local old = row.lastLevel
				local new = levelOf(row.id)
				row.lastLevel = new
				if new > old and menus and menus.GetActiveMenu() == MENU_NAME then
					local upgrade = PlayerUpgrades.ById[row.id]
					local paidCash = PlayerUpgrades.GetCashPrice(row.id, old)
					celebrate(row, paidCash, new >= upgrade.maxLevel)
				end
			end)
		end
	end)
end

return UpgradeMenuController
