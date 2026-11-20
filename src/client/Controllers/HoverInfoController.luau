--!strict
-- Infobulle au survol de la souris (2026-11-20) : souris sur un fruit -> nom + rarete ; souris sur
-- un jus (gobelet) -> "Apple Juice" + rarete + prix de vente. Contour lumineux sur l'objet survole.
-- Client seulement, rien n'est envoye au serveur (affichage pur).
--
-- Les pieces des fruits et des gobelets ont CanQuery = false (FruitModels : la camera et les autres
-- rayons les ignorent), donc un rayon de souris ne les touche pas. On garde la liste des modeles qui
-- ont l'attribut FruitId (fruits et gobelets, FruitModels.assemble) et on cherche celui dont le
-- centre, projete a l'ecran, est sous la souris ; le plus proche de la camera gagne, s'il n'est pas
-- cache par un mur (rayon camera -> objet).
-- Prix affiche = celui du comptoir (CustomerService.sellOne) : valeur du fruit x multiplicateur du
-- rebirth (leaderstats.Rebirths). Telephone : pas de souris, rien ne s'affiche.
-- Doc : docs/systems/interface.md (section "Infobulle au survol")

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Fruits = require(Config:WaitForChild("Fruits"))
local Rebirth = require(Config:WaitForChild("Rebirth"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local player = Players.LocalPlayer

local HoverInfoController = {}

-- Distance max (studs) entre la camera et un objet pour l'infobulle.
local MAX_DISTANCE = 90
-- Recherche de l'objet survole : 30 fois par seconde (la bulle, elle, suit la souris a chaque image).
local SCAN_INTERVAL = 1 / 30
-- Marge (pixels) autour de l'objet a l'ecran : un petit fruit lointain reste facile a viser.
local HIT_MARGIN = 6
-- Decalage de la bulle par rapport a la pointe de la souris, et marge au bord de l'ecran.
local CURSOR_OFFSET = Vector2.new(18, 16)
local SCREEN_MARGIN = 8
-- Pieces plus transparentes que ca : ne cachent pas l'objet (zones de pad invisibles, vitres).
local SEE_THROUGH = 0.6

type Entry = { primary: BasePart?, radius: number }

local tracked: { [Model]: Entry } = {}

local gui: ScreenGui
local panel: Frame
local panelScale: UIScale
local panelStroke: UIStroke
local nameLabel: TextLabel
local rarityLabel: TextLabel
local priceLabel: TextLabel

local current: Model? = nil
local highlight: Highlight? = nil
local lastScan = 0

-- Suivi des modeles fruit / gobelet presents dans workspace ------------------------------------

local function track(instance: Instance)
	if instance:IsA("Model") and type(instance:GetAttribute("FruitId")) == "string" then
		tracked[instance] = { primary = nil, radius = 0 }
	end
end

local function untrack(instance: Instance)
	if tracked[instance :: any] then
		tracked[instance :: any] = nil
	end
end

-- Piece principale + rayon (moitie du plus grand cote), calcules une fois quand le modele est complet.
local function resolve(model: Model, entry: Entry): BasePart?
	local primary = entry.primary
	if primary == nil or primary.Parent ~= model then
		primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		entry.primary = primary
		entry.radius = 0
	end
	if primary and entry.radius <= 0 then
		local size = model:GetExtentsSize()
		entry.radius = math.max(size.X, size.Y, size.Z) / 2
	end
	return primary
end

-- Objet cache par quelque chose de solide entre la camera et lui ?
local function isHidden(origin: Vector3, target: Vector3, radius: number): boolean
	local offset = target - origin
	local distance = offset.Magnitude
	local reach = distance - radius
	if reach <= 0 then
		return false
	end
	local direction = offset.Unit * reach
	local exclude: { Instance } = {}
	local character = player.Character
	if character then
		table.insert(exclude, character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 5 do
		params.FilterDescendantsInstances = exclude
		local result = workspace:Raycast(origin, direction, params)
		if result == nil then
			return false
		end
		local part = result.Instance
		if part.Transparency < SEE_THROUGH then
			return true
		end
		table.insert(exclude, part)
	end
	return false
end

-- La souris est-elle sur un bouton ou un menu de l'interface ? (alors pas de bulle)
local function mouseOverInterface(mouse: Vector2): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	local inset = GuiService:GetGuiInset()
	local objects = playerGui:GetGuiObjectsAtPosition(mouse.X - inset.X, mouse.Y - inset.Y)
	for _, object in objects do
		if object:IsDescendantOf(gui) or not object.Visible then
			continue
		end
		if object:IsA("GuiButton") or object:IsA("ScrollingFrame") or object:IsA("TextBox") then
			return true
		end
		-- Fond de menu (panneau opaque assez grand)
		if object.BackgroundTransparency < 0.3 and object.AbsoluteSize.X > 80 and object.AbsoluteSize.Y > 80 then
			return true
		end
	end
	return false
end

-- Modele fruit / gobelet sous la souris (le plus proche de la camera et visible), ou nil.
local function findTarget(mouse: Vector2): Model?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local origin = camera.CFrame.Position
	local pixelsPerStud = camera.ViewportSize.Y / (2 * math.tan(math.rad(camera.FieldOfView) / 2))

	local hits: { { model: Model, depth: number, position: Vector3, radius: number } } = {}
	for model, entry in tracked do
		local primary = resolve(model, entry)
		if primary == nil or primary.Transparency >= 0.99 or primary.LocalTransparencyModifier >= 0.99 then
			continue
		end
		local position = primary.Position
		if (position - origin).Magnitude > MAX_DISTANCE then
			continue
		end
		local screen, onScreen = camera:WorldToViewportPoint(position)
		if not onScreen or screen.Z <= 0 then
			continue
		end
		local radiusPx = entry.radius * pixelsPerStud / screen.Z + HIT_MARGIN
		local dx, dy = screen.X - mouse.X, screen.Y - mouse.Y
		if dx * dx + dy * dy <= radiusPx * radiusPx then
			table.insert(hits, { model = model, depth = screen.Z, position = position, radius = entry.radius })
		end
	end
	if #hits == 0 then
		return nil
	end
	table.sort(hits, function(a, b)
		return a.depth < b.depth
	end)
	-- Les 3 plus proches au plus : le premier qui n'est pas derriere un mur.
	for i = 1, math.min(3, #hits) do
		local hit = hits[i]
		if not isHidden(origin, hit.position, hit.radius) then
			return hit.model
		end
	end
	return nil
end

-- Interface -----------------------------------------------------------------------------------

local function textScale(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	return math.clamp(height / 720, 0.85, 1.25)
end

local function makeLabel(name: string, order: number, size: number, color: Color3, strokeColor: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.FontFace = PackStyle.FONT
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label:SetAttribute("BaseTextSize", size)
	PackStyle.stroke(label, 2, strokeColor)
	label.Parent = panel
	return label
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "HoverInfo"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- coordonnees = GetMouseLocation
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.Size = UDim2.fromOffset(0, 0)
	panel.BackgroundColor3 = Color3.fromRGB(30, 22, 40)
	panel.BackgroundTransparency = 0.12
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	panelStroke = PackStyle.stroke(panel, 3, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 7)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = panel

	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	nameLabel = makeLabel("FruitName", 1, 30, Color3.new(1, 1, 1), PackStyle.TEXT_STROKE)
	rarityLabel = makeLabel("Rarity", 2, 25, Color3.new(1, 1, 1), PackStyle.TEXT_STROKE)
	priceLabel = makeLabel("Price", 3, 27, PackStyle.MONEY_GREEN, PackStyle.MONEY_STROKE)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function applyTextScale()
	local scale = textScale()
	for _, label in { nameLabel, rarityLabel, priceLabel } do
		local base = label:GetAttribute("BaseTextSize")
		label.TextSize = math.floor((if type(base) == "number" then base else 20) * scale + 0.5)
	end
end

local function rebirthMultiplier(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")
	local count = if rebirths and rebirths:IsA("IntValue") then rebirths.Value else 0
	-- Pass Billboard (2X Sell Price) : attribut joueur pose par le serveur (PassPadService)
	local billboard = if player:GetAttribute("Billboard") == true then Gameplay.BillboardSellMultiplier else 1
	return Rebirth.Multiplier(count) * billboard
end

local function clearHighlight()
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

-- Remplit la bulle pour ce modele ; false si le fruit est inconnu.
local function fill(model: Model): boolean
	local fruitId = model:GetAttribute("FruitId")
	local fruit = if type(fruitId) == "string" then Fruits.ById[fruitId] else nil
	if fruit == nil then
		return false
	end
	local rarity = Fruits.Rarities[fruit.rarity]
	local isJuice = model:FindFirstChild("Cup") ~= nil
	nameLabel.Text = if isJuice then `{fruit.name} Juice` else fruit.name
	rarityLabel.Text = rarity.name
	rarityLabel.TextColor3 = rarity.color
	panelStroke.Color = rarity.color
	priceLabel.Visible = isJuice
	if isJuice then
		local price = math.floor(fruit.value * rebirthMultiplier() + 0.5)
		priceLabel.Text = `Sells for {NumberFormat.Money(price)}`
	end
	return true
end

local function setTarget(model: Model?)
	if model == current then
		return
	end
	current = model
	clearHighlight()
	if model == nil or not fill(model) then
		current = nil
		gui.Enabled = false
		return
	end
	applyTextScale()
	gui.Enabled = true
	-- Petit "pop" a chaque nouvel objet
	panelScale.Scale = 0.8
	TweenService:Create(panelScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	-- Contour lumineux sur l'objet survole (une seule Highlight a la fois)
	local fruitId = model:GetAttribute("FruitId")
	local fruit = if type(fruitId) == "string" then Fruits.ById[fruitId] else nil
	local h = Instance.new("Highlight")
	h.Name = "HoverHighlight"
	h.Adornee = model
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.8
	h.OutlineColor = if fruit then Fruits.Rarities[fruit.rarity].color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1)
	h.OutlineTransparency = 0
	h.Parent = gui -- pas dans le modele : les autres scripts parcourent ses enfants
	highlight = h
end

-- Place la bulle a cote de la souris, sans sortir de l'ecran.
local function placePanel(mouse: Vector2)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local size = panel.AbsoluteSize
	local x = mouse.X + CURSOR_OFFSET.X
	local y = mouse.Y + CURSOR_OFFSET.Y
	if x + size.X > viewport.X - SCREEN_MARGIN then
		x = mouse.X - CURSOR_OFFSET.X - size.X
	end
	if y + size.Y > viewport.Y - SCREEN_MARGIN then
		y = mouse.Y - CURSOR_OFFSET.Y - size.Y
	end
	panel.Position = UDim2.fromOffset(math.max(SCREEN_MARGIN, x), math.max(SCREEN_MARGIN, y))
end

local function step()
	if not UserInputService.MouseEnabled or GuiService.MenuIsOpen then
		setTarget(nil)
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	-- Objet detruit ou sorti du jeu (jus vendu, fruit ramasse)
	if current and not current:IsDescendantOf(workspace) then
		setTarget(nil)
	end
	local now = os.clock()
	if now - lastScan >= SCAN_INTERVAL then
		lastScan = now
		local target = findTarget(mouse)
		if target and mouseOverInterface(mouse) then
			target = nil
		end
		setTarget(target)
	end
	if current then
		placePanel(mouse)
	end
end

function HoverInfoController:Init()
	buildGui()
end

function HoverInfoController:Start()
	workspace.DescendantAdded:Connect(track)
	workspace.DescendantRemoving:Connect(untrack)
	for _, instance in workspace:GetDescendants() do
		track(instance)
	end
	RunService.RenderStepped:Connect(step)
end

return HoverInfoController
