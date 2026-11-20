--!strict
-- Plateau sur la tete (2026-11-19, demande utilisateur) : quand un joueur ramasse des fruits, un
-- plateau apparait au-dessus de sa tete et les fruits s'y empilent "un peu n'importe comment".
-- Le serveur (ProductionService) pose l'attribut TrayFruits ("Apple;Orange;Apple", ordre du
-- ramassage) sur le personnage ; chaque client dessine le plateau de TOUS les joueurs (pieces
-- locales soudees a la tete : rien n'est cree ni repliquee par le serveur).
--   * nouveau fruit : il tombe sur sa place avec un petit rebond, le plateau plonge un peu ;
--     pour le joueur local, il apparait quand le fruit qui vole du sol arrive (InventoryController) ;
--   * place de chaque fruit : tiree au hasard UNE fois (graine = numero de la place) : le tas est le
--     meme pour tout le monde et ne bouge pas quand on en ajoute ;
--   * plateau vide (depot sur le pad "Drop Fruits") : le plateau disparait ;
--   * joueur local : "12/20" au-dessus du tas, "FULL!" en rouge quand c'est plein.
--   * employes (2026-11-20) : le Fruit Picker porte aussi l'attribut TrayFruits ; on suit les
--     modeles tagues "CarryPoseRig" (employes, clients) en plus des personnages des joueurs.
-- Doc : docs/systems/chaine-production.md (section Plateau)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Fruits = require(Config:WaitForChild("Fruits"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))

local TrayController = {}

local ATTRIBUTE = "TrayFruits"
local RIG_TAG = "CarryPoseRig" -- pose par NpcRig (employes) et CustomerController (clients)
local MAX_FRUITS = 60 -- borne de securite (l'attribut vient du serveur)
local TRAY_SIZE = 3.4 -- plateau carre (studs)
local TRAY_THICK = 0.2
local RIM_HEIGHT = 0.35
local FLY_TIME = 0.35 -- = FLY_TIME_PICKUP d'InventoryController
local FLY_STAGGER = 0.05 -- = ecart entre deux fruits qui volent (InventoryController)
local TRAY_COLOR = Color3.fromRGB(226, 190, 140)
local RIM_COLOR = Color3.fromRGB(168, 120, 76)
local FULL_COLOR = Color3.fromRGB(255, 70, 70)

local localPlayer = Players.LocalPlayer
local started = false

type Tray = {
	character: Model,
	ids: { string }, -- fruits voulus (attribut)
	shown: number, -- fruits deja poses (les suivants attendent la fin de leur vol)
	model: Model?,
	base: BasePart?,
	headWeld: Weld?,
	fruits: { Model },
	label: TextLabel?,
	generation: number, -- change a chaque reconstruction : annule les poses en attente
	connections: { RBXScriptConnection },
}

local trays: { [Model]: Tray } = {}
local folder: Folder? = nil

-- ===== Places des fruits : tas en vrac, de plus en plus haut =====

-- Couches (hauteur, positions x / z dans le repere du plateau). Fruits ~0.95 de haut sur le plateau.
local LAYERS: { { y: number, spots: { Vector2 } } } = {
	{ y = 0, spots = {
		Vector2.new(-0.95, -0.95), Vector2.new(0, -0.95), Vector2.new(0.95, -0.95),
		Vector2.new(-0.95, 0), Vector2.new(0, 0), Vector2.new(0.95, 0),
		Vector2.new(-0.95, 0.95), Vector2.new(0, 0.95), Vector2.new(0.95, 0.95),
	} },
	{ y = 0.72, spots = { Vector2.new(-0.48, -0.48), Vector2.new(0.48, -0.48), Vector2.new(-0.48, 0.48), Vector2.new(0.48, 0.48) } },
	{ y = 1.38, spots = { Vector2.new(-0.62, 0), Vector2.new(0.62, 0), Vector2.new(0, -0.62), Vector2.new(0, 0.62) } },
	{ y = 2.0, spots = { Vector2.new(-0.36, 0.1), Vector2.new(0.36, -0.1) } },
	{ y = 2.58, spots = { Vector2.new(0, 0) } },
}

local slots: { CFrame } = {}
do
	local order = Random.new(42)
	for _, layer in LAYERS do
		-- ordre de remplissage melange dans chaque couche (pas de rangee bien droite)
		local spots = table.clone(layer.spots)
		for i = #spots, 2, -1 do
			local j = order:NextInteger(1, i)
			spots[i], spots[j] = spots[j], spots[i]
		end
		for _, spot in spots do
			local index = #slots + 1
			local rng = Random.new(1000 + index * 17)
			local pos = Vector3.new(
				spot.X + rng:NextNumber(-0.14, 0.14),
				layer.y + rng:NextNumber(-0.04, 0.08),
				spot.Y + rng:NextNumber(-0.14, 0.14)
			)
			local tilt = CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-22, 22)))
			slots[index] = CFrame.new(pos) * tilt
		end
	end
	-- Au-dela (plateau plus grand plus tard) : on continue a empiler au sommet
	for index = #slots + 1, MAX_FRUITS do
		local rng = Random.new(1000 + index * 17)
		local level = 3.1 + (index - 21) * 0.32
		local pos = Vector3.new(rng:NextNumber(-0.45, 0.45), level, rng:NextNumber(-0.45, 0.45))
		slots[index] = CFrame.new(pos) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
	end
end

-- ===== Pieces =====

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Trays"
	created.Parent = workspace
	folder = created
	return created
end

local function prepare(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
end

local function makePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	prepare(p)
	p.Parent = parent
	return p
end

local function parseIds(value: any): { string }
	local ids: { string } = {}
	if type(value) ~= "string" or value == "" or #value > 2000 then
		return ids
	end
	for id in string.gmatch(value, "[^;]+") do
		if Fruits.ById[id] ~= nil then
			table.insert(ids, id)
			if #ids >= MAX_FRUITS then
				break
			end
		end
	end
	return ids
end

local function clearModel(tray: Tray)
	tray.generation += 1
	if tray.model then
		tray.model:Destroy()
	end
	tray.model = nil
	tray.base = nil
	tray.headWeld = nil
	tray.label = nil
	table.clear(tray.fruits)
	tray.shown = 0
end

local function restOffset(head: BasePart): CFrame
	return CFrame.new(0, head.Size.Y / 2 + Gameplay.TrayAboveHead + TRAY_THICK / 2, 0)
end

-- Cree le plateau vide sur la tete (il tombe un peu et rebondit).
local function buildTray(tray: Tray): boolean
	local head = tray.character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Tray"
	local cf = head.CFrame * restOffset(head)
	local base = makePart(model, "TrayBase", Vector3.new(TRAY_SIZE, TRAY_THICK, TRAY_SIZE), cf, TRAY_COLOR)
	-- Bords : 0.05 plus larges que le plateau de chaque cote, du dessous du plateau jusqu'au-dessus
	-- (aucune face au meme endroit qu'une face du plateau ou d'un autre bord : pas de z-fighting).
	-- Avant (2026-11-19) : faces de cote communes avec le plateau = clignotement.
	local half = TRAY_SIZE / 2
	local out = half + 0.05 -- bord exterieur
	local w = 0.25 -- epaisseur d'un bord
	local rimH = TRAY_THICK + 0.1 + RIM_HEIGHT -- de 0.05 sous le plateau a RIM_HEIGHT au-dessus
	local rimY = TRAY_THICK / 2 + RIM_HEIGHT - rimH / 2
	local rims = {
		-- avant / arriere : toute la largeur ; gauche / droite : entre les deux (bouts colles)
		{ Vector3.new(out * 2, rimH, w), CFrame.new(0, rimY, -out + w / 2) },
		{ Vector3.new(out * 2, rimH, w), CFrame.new(0, rimY, out - w / 2) },
		{ Vector3.new(w, rimH - 0.04, (out - w) * 2), CFrame.new(-out + w / 2, rimY - 0.02, 0) },
		{ Vector3.new(w, rimH - 0.04, (out - w) * 2), CFrame.new(out - w / 2, rimY - 0.02, 0) },
	}
	for _, rim in rims do
		-- Weld a decalage fixe (pas WeldConstraint : il prendrait le decalage au moment ou le plateau
		-- est encore en l'air pendant son animation d'arrivee)
		local p = makePart(model, "Rim", rim[1], cf * rim[2], RIM_COLOR)
		local weld = Instance.new("Weld")
		weld.Part0 = base
		weld.Part1 = p
		weld.C0 = rim[2]
		weld.Parent = p
	end
	local weld = Instance.new("Weld")
	weld.Name = "HeadWeld"
	weld.Part0 = head
	weld.Part1 = base
	local rest = restOffset(head)
	weld.C0 = rest * CFrame.new(0, 1.2, 0)
	weld.Parent = base
	model.PrimaryPart = base

	if tray.character == localPlayer.Character then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Count"
		gui.Size = UDim2.fromOffset(110, 34)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = base
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = PackStyle.FONT
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = ""
		PackStyle.stroke(label, 2.5, PackStyle.TEXT_STROKE)
		label.Parent = gui
		gui.Parent = model
		tray.label = label
	end

	model.Parent = getFolder()
	tray.model = model
	tray.base = base
	tray.headWeld = weld
	TweenService:Create(weld, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = rest }):Play()
	return true
end

local function updateLabel(tray: Tray)
	local label = tray.label
	if label == nil then
		return
	end
	local max = localPlayer:GetAttribute("InvMax")
	local capacity = if type(max) == "number" then max else Gameplay.CarryCapacity
	if tray.shown >= capacity then
		label.Text = "FULL!"
		label.TextColor3 = FULL_COLOR
	else
		label.Text = `{tray.shown}/{capacity}`
		label.TextColor3 = Color3.new(1, 1, 1)
	end
end

-- Pose le fruit numero `index` sur le plateau (il tombe sur sa place).
local function placeFruit(tray: Tray, index: number, animate: boolean)
	local base = tray.base
	local model = tray.model
	local id = tray.ids[index]
	if base == nil or model == nil or id == nil then
		return
	end
	local ok, fruit = pcall(FruitModels.CreateFruit, id, false)
	if not ok then
		return
	end
	local fruitModel = fruit :: Model
	local primary = fruitModel.PrimaryPart
	if primary == nil then
		fruitModel:Destroy()
		return
	end
	fruitModel:ScaleTo(Gameplay.TrayFruitScale)
	for _, d in fruitModel:GetDescendants() do
		if d:IsA("BasePart") then
			prepare(d)
		end
	end
	local slot = CFrame.new(0, TRAY_THICK / 2, 0) * (slots[index] or slots[#slots])
	local start = if animate then CFrame.new(0, 1.4, 0) * slot else slot
	-- Le fruit est deja a sa position de depart : ses soudures internes gardent la bonne forme
	fruitModel:PivotTo(base.CFrame * start)
	local weld = Instance.new("Weld")
	weld.Part0 = base
	weld.Part1 = primary
	weld.C1 = primary.PivotOffset
	weld.C0 = start
	weld.Parent = primary
	fruitModel.Parent = model
	tray.fruits[index] = fruitModel
	tray.shown = math.max(tray.shown, index)
	updateLabel(tray)
	if animate then
		TweenService:Create(weld, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = slot }):Play()
		-- le plateau plonge un peu sous le poids puis remonte
		local headWeld = tray.headWeld
		local head = tray.character:FindFirstChild("Head")
		if headWeld and head and head:IsA("BasePart") then
			local rest = restOffset(head)
			headWeld.C0 = rest * CFrame.new(0, -0.12, 0)
			TweenService:Create(headWeld, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = rest }):Play()
		end
	end
end

-- Met le plateau a jour apres un changement de l'attribut.
local function refresh(tray: Tray)
	local ids = parseIds(tray.character:GetAttribute(ATTRIBUTE))
	if #ids == 0 then
		tray.ids = ids
		clearModel(tray)
		return
	end
	-- Ajout au bout de la liste (ou premier fruit) : on garde le tas, seuls les nouveaux tombent
	local extends = (tray.model ~= nil or #tray.ids == 0) and #ids >= #tray.ids
	if extends then
		for i, id in tray.ids do
			if ids[i] ~= id then
				extends = false
				break
			end
		end
	end
	local previous = if extends then #tray.ids else 0
	if not extends then
		clearModel(tray)
	end
	tray.ids = ids
	if tray.model == nil and not buildTray(tray) then
		return
	end
	local isLocal = tray.character == localPlayer.Character
	local generation = tray.generation
	for index = previous + 1, #ids do
		-- Joueur local : le fruit arrive sur le plateau a la fin de son vol depuis le sol
		local delay = if isLocal and extends then FLY_TIME + (index - previous - 1) * FLY_STAGGER else 0
		if not extends then
			placeFruit(tray, index, false)
		elseif delay <= 0 then
			placeFruit(tray, index, true)
		else
			task.delay(delay, function()
				if tray.generation == generation and trays[tray.character] == tray and tray.ids[index] ~= nil and tray.fruits[index] == nil then
					placeFruit(tray, index, true)
				end
			end)
		end
	end
	updateLabel(tray)
end

local function removeCharacter(character: Model)
	local tray = trays[character]
	if tray == nil then
		return
	end
	trays[character] = nil
	clearModel(tray)
	for _, connection in tray.connections do
		connection:Disconnect()
	end
end

local function addCharacter(character: Model)
	if trays[character] then
		return
	end
	local tray: Tray = {
		character = character,
		ids = {},
		shown = 0,
		model = nil,
		base = nil,
		headWeld = nil,
		fruits = {},
		label = nil,
		generation = 0,
		connections = {},
	}
	trays[character] = tray
	table.insert(tray.connections, character:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		refresh(tray)
	end))
	table.insert(tray.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			removeCharacter(character)
		end
	end))
	task.spawn(function()
		character:WaitForChild("Head", 10)
		if trays[character] == tray then
			refresh(tray)
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(addCharacter)
	player.CharacterRemoving:Connect(removeCharacter)
	if player.Character then
		addCharacter(player.Character)
	end
end

function TrayController.Init() end

function TrayController.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- Employes (Fruit Picker) : meme plateau que les joueurs
	local function addRig(instance: Instance)
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
			addCharacter(instance)
		end
	end
	for _, instance in CollectionService:GetTagged(RIG_TAG) do
		addRig(instance)
	end
	CollectionService:GetInstanceAddedSignal(RIG_TAG):Connect(addRig)
	localPlayer:GetAttributeChangedSignal("InvMax"):Connect(function()
		local character = localPlayer.Character
		local tray = character and trays[character]
		if tray then
			updateLabel(tray)
		end
	end)
end

return TrayController
