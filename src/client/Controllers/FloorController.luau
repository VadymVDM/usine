--!strict
-- Tour d'etages, cote client (rien n'est decide ici) :
--   * selecteur d'etage en haut de l'ecran : "<  Floor 3  >". Visible seulement quand SA base a au
--     moins Floors.SelectorMinFloors etages achetes (3). Fleche droite = etage suivant, gauche =
--     etage precedent (grisee au premier / dernier etage). Clic = remote FloorTeleport (numero
--     d'etage) : le serveur reverifie tout (entier, etage achete, proprietaire, delai) et teleporte.
--     (Remplace la fenetre FLOORS et ses panneaux, retires le 2026-11-20.)
--   * "NEW FLOOR!" (+ confettis et feux d'artifice, Fx/Celebration) : un nouvel etage ouvert de SA base apparait en jeu (attribut BuildStamp) :
--     grand texte au centre + son, et l'etage se construit par couches de hauteur (fondu des
--     pieces, cote client seulement, Transparency remise a l'origine ensuite).
-- Doc : docs/systems/tour-etages.md, docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits"))
local Floors = require(Shared:WaitForChild("Config"):WaitForChild("Floors"))
local Icons = require(Shared:WaitForChild("Config"):WaitForChild("Icons"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local Celebration = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Celebration"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local NEW_FLOOR_SOUND = "NewFruit" -- "Cute level up" (Config/Sounds)
local NEW_FLOOR_SECONDS = 2
local STARTUP_GRACE = 6 -- s : etages vus au demarrage = deja la (pas d'effet)
local OWNER_GRACE = 6 -- s : etages reconstruits a l'arrivee du proprietaire (pas d'effet)
local BUILD_SECONDS = 1.5 -- construction de l'etage, du sol au plafond
local BUILD_LAYERS = 12
local BUILD_FADE = 0.3 -- fondu d'une couche
local FIREWORKS_OFFSET = Vector3.new(55, 1, 75) -- centre du sol de l'etage (repere de l'etage) : on les voit de dedans
local BUILD_DISTANCE = 300 -- au-dela, pas d'animation de construction
local GREY = { Color3.fromRGB(120, 120, 130), Color3.fromRGB(175, 175, 185), Color3.fromRGB(45, 45, 55) }
local REFRESH_SECONDS = 0.2 -- relecture de l'etage ou est le joueur
local PENDING_SECONDS = 2.5 -- apres un clic, on affiche l'etage vise le temps que le teleport arrive

local FloorController = {}

local player = Players.LocalPlayer
local started = false
local startedAt = 0
local teleportEvent: RemoteEvent? = nil

-- Proprietaire : depuis quand chaque base est a moi (os.clock)
local mineSince: { [Model]: number } = {}

---------------------------------------------------------------------------------------------
-- Aides

-- Couleur d'un etage (lot 4b : chaque etage a les 10 raretes ; plus de nom de rarete). On garde
-- une couleur par etage (couleurs des raretes, dans l'ordre) : sous-titre de "NEW FLOOR!".
local function floorColor(k: number): Color3
	local rarity = Fruits.Rarities[k]
	return if rarity then rarity.color else Color3.fromRGB(200, 200, 200)
end

local function floorsOwned(base: Model): number
	local value = base:GetAttribute("FloorsOwned")
	if type(value) == "number" and value == value then
		return math.clamp(math.floor(value), 1, Floors.MaxFloors)
	end
	return math.max(1, #FloorWatch.FloorsOf(base))
end

-- Etage ou se trouve le joueur dans cette base (numero), nil si inconnu.
local function currentFloorIndex(base: Model): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return FloorWatch.FloorOfPosition(base, root.Position.Y)
end

---------------------------------------------------------------------------------------------
-- Selecteur d'etage (haut de l'ecran)

local selectorGui: ScreenGui? = nil
local leftButton: ImageButton? = nil
local rightButton: ImageButton? = nil
local floorLabel: TextLabel? = nil
local labelScale: UIScale? = nil
local shownFloor = 0 -- etage affiche (0 = rien encore)
local pendingFloor: number? = nil -- etage demande, en attente du teleport
local pendingUntil = 0
local popConnection: RBXScriptConnection? = nil

local function setArrow(button: ImageButton?, enabled: boolean)
	if button == nil then
		return
	end
	-- Fleche = triangle plein sans fond (2026-11-20) : seule la teinte de l'image change
	button.ImageColor3 = if enabled then Color3.new(1, 1, 1) else GREY[1] -- blanc (2026-11-20), gris au bout
	button.ImageTransparency = if enabled then 0 else 0.35
	button.Active = enabled
	button.AutoButtonColor = false
	button.Selectable = enabled
	button:SetAttribute("Enabled", enabled)
end

-- Petit rebond du texte quand l'etage change
local function pop()
	local scale = labelScale
	if scale == nil then
		return
	end
	local spring = Jelly.Spring(320, 12)
	spring.x = 0.3
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
end

-- Relit la base, l'etage du joueur, et met a jour l'affichage.
local function refreshSelector()
	local screen = selectorGui
	if screen == nil then
		return
	end
	local base = FloorWatch.MyBase()
	local owned = if base then floorsOwned(base) else 0
	if base == nil or owned < Floors.SelectorMinFloors then
		screen.Enabled = false
		shownFloor = 0
		return
	end
	local here = math.clamp(currentFloorIndex(base) or 1, 1, owned)
	local pending = pendingFloor
	if pending then
		if here == pending or os.clock() > pendingUntil or pending > owned then
			pendingFloor = nil
		else
			here = pending
		end
	end
	screen.Enabled = true
	if here ~= shownFloor then
		local label = floorLabel
		if label then
			label.Text = `Floor {here}`
		end
		if shownFloor ~= 0 then
			pop()
		end
		shownFloor = here
	end
	setArrow(leftButton, here > 1)
	setArrow(rightButton, here < owned)
end

local function step(direction: number)
	local base = FloorWatch.MyBase()
	if base == nil or shownFloor == 0 then
		return
	end
	local target = shownFloor + direction
	if target < 1 or target > floorsOwned(base) then
		return
	end
	local event = teleportEvent
	if event == nil then
		return
	end
	event:FireServer(target)
	pendingFloor = target
	pendingUntil = os.clock() + PENDING_SECONDS
	-- Pas de son propre au changement d'etage (retire le 2026-11-20, "j'aime pas le bruit quand on
	-- change d'etage") : seul reste le "Click" commun des boutons (UI/ButtonFx)
	refreshSelector()
end

local function arrowButton(parent: Instance, name: string, x: number, direction: number): ImageButton
	-- Pas de fond (demande du 2026-11-20) : juste un triangle plein colore avec un contour fonce
	-- (image Icons.FloorArrow, pointe a droite ; retournee pour la fleche gauche)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.fromScale(x, 0)
	button.Size = UDim2.fromScale(0.22, 1)
	button.ZIndex = 3
	button.Image = Icons.FloorArrow
	button.ImageColor3 = Color3.new(1, 1, 1)
	button.ScaleType = Enum.ScaleType.Fit
	if direction < 0 then
		button.ImageRectOffset = Vector2.new(256, 0)
		button.ImageRectSize = Vector2.new(-256, 256) -- miroir horizontal
	end
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = button
	button.Parent = parent
	button.Activated:Connect(function()
		if button:GetAttribute("Enabled") == true then
			step(direction)
		end
	end)
	return button
end

local function buildSelector()
	local screen = Instance.new("ScreenGui")
	screen.Name = "FloorSelectorGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20 -- au-dessus du HUD, sous les menus et les messages
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Plus de marge : la barre est dans la bande du haut, au niveau du bouton parametres (2026-11-20)
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.Enabled = false

	-- Barre "<  Floor 3  >" en haut au centre (les messages du serveur sont juste en dessous)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 0) -- centre vertical ~ celui du bouton parametres (y 34 px)
	bar.Size = UDim2.fromScale(0.6, 0.11)
	bar.BackgroundTransparency = 1
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 5.6 -- fleches plus ecartees du texte (2026-11-20)
	ratio.Parent = bar
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(318, 57)
	limit.MaxSize = Vector2.new(549, 98)
	limit.Parent = bar

	-- Nom de l'etage entre les fleches, sans fond (2026-11-20 : "retire le fond")
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.fromScale(0.5, 0)
	plate.Size = UDim2.fromScale(0.46, 1)
	plate.BackgroundTransparency = 1
	plate.ZIndex = 2
	plate.Parent = bar

	local label = PackStyle.label(plate, "Floor 1", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.96, 0.84), 60)
	local labelStroke = label:FindFirstChildOfClass("UIStroke")
	if labelStroke then
		labelStroke.Thickness = math.max(1, 3.5 * PackStyle.strokeScale()) -- plus epais : plus de fond
	end
	label.Name = "FloorName"
	label.ZIndex = 4
	local scale = Instance.new("UIScale")
	scale.Parent = label

	leftButton = arrowButton(bar, "Previous", 0.07, -1)
	rightButton = arrowButton(bar, "Next", 0.93, 1)

	bar.Parent = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	selectorGui, floorLabel, labelScale = screen, label, scale
end

---------------------------------------------------------------------------------------------
-- NEW FLOOR!

local function showNewFloor(k: number, floor: Model)
	local screen = Instance.new("ScreenGui")
	screen.Name = "NewFloorFx"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 45
	screen.IgnoreGuiInset = true
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.4)
	holder.Size = UDim2.fromScale(0.8, 0.26)
	holder.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = holder
	local title = PackStyle.label(holder, "NEW FLOOR!", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.66), 110)
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Rotation = 90
	titleGradient.Color = ColorSequence.new(Color3.fromRGB(255, 245, 120), Color3.fromRGB(255, 170, 30))
	titleGradient.Parent = title
	local color = floorColor(k)
	local sub = PackStyle.label(holder, `Floor {k}`, UDim2.fromScale(0.5, 0.68), UDim2.fromScale(0.8, 0.3), 50)
	sub.TextColor3 = color
	holder.Parent = screen
	screen.Parent = player:WaitForChild("PlayerGui")
	SoundFx.Play(NEW_FLOOR_SOUND)
	-- Confettis a l'ecran + feux d'artifice au-dessus du nouvel'etage (couleur de l etage + or)
	local party = { color, Color3.fromRGB(255, 205, 50), Color3.fromRGB(255, 255, 255), color:Lerp(Color3.new(1, 1, 1), 0.4) }
	Celebration.Confetti(screen.Parent :: Instance, party)
	local center = floor:GetPivot():PointToWorldSpace(FIREWORKS_OFFSET)
	Celebration.Fireworks(center, party, 34, 8, 27) -- eclatent sous le plafond (dalle a 35)

	-- Pop gelee, leger balancement, puis fondu
	local spring = Jelly.Spring(260, 9)
	spring.x = -0.8
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		Jelly.Step(spring, dt)
		scale.Scale = math.max(0.05, 1 + spring.x)
		holder.Rotation = math.sin(elapsed * 5) * 3 * math.max(0, 1 - elapsed / NEW_FLOOR_SECONDS)
		if elapsed >= NEW_FLOOR_SECONDS + 0.4 then
			connection:Disconnect()
			screen:Destroy()
		end
	end)
	task.delay(NEW_FLOOR_SECONDS, function()
		if screen.Parent == nil then
			return
		end
		local info = TweenInfo.new(0.35)
		for _, label in { title, sub } do
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, info, { Transparency = 1 }):Play()
			end
		end
	end)
end

-- Construction : les pieces visibles apparaissent par couches de hauteur (bas -> haut).
type BuildPart = { part: BasePart, original: number, written: number }

local function playBuild(floor: Model)
	local camera = workspace.CurrentCamera
	local pivot = floor:GetPivot()
	if camera and (camera.CFrame.Position - pivot.Position).Magnitude > BUILD_DISTANCE then
		return
	end
	local entries: { BuildPart } = {}
	local minY, maxY = math.huge, -math.huge
	for _, item in floor:GetDescendants() do
		-- Pieces invisibles d'origine (zones, murs invisibles) : jamais touchees
		if item:IsA("BasePart") and item.Transparency < 1 then
			table.insert(entries, { part = item, original = item.Transparency, written = 1 })
			local y = item.Position.Y
			minY = math.min(minY, y)
			maxY = math.max(maxY, y)
		end
	end
	if #entries == 0 then
		return
	end
	local span = math.max(maxY - minY, 1)
	local layers: { { BuildPart } } = {}
	for i = 1, BUILD_LAYERS do
		layers[i] = {}
	end
	for _, entry in entries do
		local i = math.clamp(math.floor((entry.part.Position.Y - minY) / span * BUILD_LAYERS) + 1, 1, BUILD_LAYERS)
		table.insert(layers[i], entry)
		entry.part.Transparency = 1
	end
	local stagger = (BUILD_SECONDS - BUILD_FADE) / BUILD_LAYERS
	local elapsed = 0
	local nextLayer = 1 -- premiere couche pas encore finie
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local gone = floor.Parent == nil
		for i = nextLayer, BUILD_LAYERS do
			local startAt = (i - 1) * stagger
			if elapsed < startAt and not gone then
				break
			end
			local alpha = if gone then 1 else math.clamp((elapsed - startAt) / BUILD_FADE, 0, 1)
			for _, entry in layers[i] do
				local part = entry.part
				-- Le serveur a change la transparence entre-temps : on le laisse faire
				if part.Parent == nil or part.Transparency ~= entry.written then
					continue
				end
				local value = 1 + (entry.original - 1) * alpha
				part.Transparency = value
				entry.written = part.Transparency -- valeur relue (arrondi du moteur)
			end
			if alpha >= 1 and i == nextLayer then
				nextLayer += 1
			end
		end
		if nextLayer > BUILD_LAYERS then
			connection:Disconnect()
		end
	end)
end


local function onFloor(floor: Model, base: Model)
	if mineSince[base] == nil and FloorWatch.IsMine(floor) then
		mineSince[base] = os.clock()
	end
	local played = false
	local function tryPlay()
		if played or floor.Parent == nil or type(floor:GetAttribute("BuildStamp")) ~= "number" then
			return
		end
		local now = os.clock()
		local since = mineSince[base]
		if not FloorWatch.IsMine(floor) or since == nil then
			return
		end
		if now - startedAt < STARTUP_GRACE or now - since < OWNER_GRACE then
			return -- etage deja la au chargement / reconstruit a l'arrivee du proprietaire
		end
		played = true
		showNewFloor(FloorWatch.IndexOf(floor), floor)
		playBuild(floor)
	end
	tryPlay()
	-- BuildStamp peut arriver juste apres l'etage
	local stampConnection = floor:GetAttributeChangedSignal("BuildStamp"):Connect(tryPlay)
	FloorWatch.OnRemoved(floor, function()
		stampConnection:Disconnect()
	end)
end

local function watchOwner(base: Model)
	local function update()
		if base:GetAttribute("OwnerUserId") == player.UserId then
			if mineSince[base] == nil then
				mineSince[base] = os.clock()
			end
		else
			mineSince[base] = nil
		end
		refreshSelector()
	end
	update()
	base:GetAttributeChangedSignal("OwnerUserId"):Connect(update)
	-- Le selecteur apparait des le 3e etage achete
	base:GetAttributeChangedSignal("FloorsOwned"):Connect(refreshSelector)
end

---------------------------------------------------------------------------------------------

function FloorController:Init() end

function FloorController:Start()
	if started then
		return
	end
	started = true
	startedAt = os.clock()
	buildSelector()

	task.spawn(function()
		-- Remote ajoute par FloorService (type RemoteName : cast tant qu'il n'y est pas)
		teleportEvent = Remotes.WaitClientEvent("FloorTeleport")
	end)

	task.spawn(function()
		local bases = workspace:WaitForChild("Bases", 60)
		if bases == nil then
			return
		end
		bases.ChildAdded:Connect(function(base)
			if base:IsA("Model") then
				watchOwner(base)
			end
		end)
		for _, base in bases:GetChildren() do
			if base:IsA("Model") then
				watchOwner(base)
			end
		end
	end)

	-- L'etage affiche suit le joueur (escalier, ascenseur, teleport)
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			refreshSelector()
		end
	end)

	FloorWatch.Watch(onFloor)
end

return FloorController
