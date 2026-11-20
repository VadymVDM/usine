--!strict
-- Arbre de chaque ETAGE (lot 4b, 2026-11-20) : l'etage n fait tomber les 10 fruits de la ligne n
-- (un par rarete, Fruits.OfFloor). 1 fruit toutes les Upgrades.TreeDropSeconds(niveau) secondes ;
-- tirage selon la rarete (Fruits.RollWeights) ; le niveau Tree (Floors[n].Upgrades.Tree, 1..10) =
-- vitesse (effet principal) + un peu de Luck (Fruits.LuckMultiplier : Rare+ plus frequents). Le Common reste le plus frequent.
-- S'arrete a Gameplay.MaxGroundFruits ("Tree full!"), pose des pommes a la premiere visite.
-- Lot 5 : ne fait tomber des fruits QUE sur l'etage ou se trouve le joueur (FloorService.IsLive).
-- DECOUVERTE AU RAMASSAGE (plus a la chute) : TreeService.Discover, appele quand le JOUEUR ramasse
-- un fruit jamais vu (le Fruit Picker ne touche pas aux fruits pas encore decouverts) -> Feedback "Discover". Niveau = Upgrades "Tree" (pad "Upgrade Tree" a cote de l'arbre ; avant le
-- 2026-11-19 soir : deux machines Tree Speed / Tree Luck).
-- L'arbre CHANGE NETTEMENT A CHAQUE NIVEAU (2026-11-20 soir) : construit par code (Lib/TreeBuilder,
-- donnees Config/Tree) et pose dans <Etage>.Tree.Body. Palier = (etage - 1) x 9 + niveau : l'etage n
-- au niveau 1 a l'arbre de l'etage n-1 au niveau 10. Avant : 5 modeles ServerStorage.TreeStages
-- agrandis (plus utilises). Attributs Tree.TreeStage (= palier) / Tree.TreeLevel (animation de
-- pousse : TreeFxController, client).
-- 2026-11-20 : PLUS AUCUN FRUIT DE DECO dans l'arbre (avant : pommes du modele remplacees par les
-- fruits decouverts ; les joueurs essayaient de les ramasser). Arbre SANS COLLISION : on le traverse
-- a pied et la camera passe au travers (CameraFadeController le rend transparent devant le joueur).
-- Chute : le serveur pose le fruit a sa place finale tout de suite et met les attributs
-- DropStart / DropHeight / DropTime (+ NewFruit : fruit pas encore decouvert) ; FruitFxController (client) anime la chute et les
-- effets. Le fruit n'est ramassable qu'apres DropTime.
-- Seul module qui ecrit Data.DiscoveredFruits. Seul module qui cree / retire les fruits au sol.
-- Ramassage EN MARCHANT DESSUS (2026-11-19, avant : prompt E "Pick up" sur chaque fruit) :
-- ProductionService teste la position du joueur et appelle TakeNear.
-- Le Fruit Picker (WorkerService) utilise FindNearest / TakeFruit.
-- Doc : docs/systems/chaine-production.md, docs/systems/fruits.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Fruits = require(Config:WaitForChild("Fruits"))
local Gameplay = require(Config:WaitForChild("Gameplay"))
local TreeConfig = require(Config:WaitForChild("Tree"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))
local WorldLabel = require(Shared:WaitForChild("Util"):WaitForChild("WorldLabel"))

local FloorService = require(script.Parent.FloorService)
local Perks = require(script.Parent.Parent.Lib.Perks)
local DataService = require(script.Parent.DataService)
local UpgradeService = require(script.Parent.UpgradeService)
local IndexService = require(script.Parent.IndexService)
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local TreeBuilder = require(script.Parent.Parent.Lib.TreeBuilder)

local TreeService = {}

type TreeState = {
	player: Player,
	floor: Model, -- etage (Floors.FloorN)
	index: number, -- numero de l'etage (ses fruits : Fruits.OfFloor(index))
	area: BasePart, -- Tree.FruitArea (carre ou tombent les fruits)
	folder: Folder, -- Dynamic.GroundFruits
	fruits: { [Model]: string }, -- fruit au sol -> id
	falling: { [Model]: boolean }, -- fruits encore en train de tomber (pas ramassables)
	count: number,
	label: BillboardGui?, -- "Tree full!"
	levelLabel: BillboardGui?, -- "Golden Tree Lv 7" (toujours visible, sous "Tree full!")
	thread: thread?,
	active: boolean,
	shownLevel: number, -- niveau de l'arbre affiche (modele pose) ; 0 = pas encore pose
	metrics: TreeBuilder.Metrics?, -- mesures de l'arbre affiche (rayon et hauteur de chute)
}


local states: { [Model]: TreeState } = {}
local applesGiven: { [Player]: boolean } = {} -- pommes de premiere visite deja posees (cette session)
local rng = Random.new()
local feedbackEvent: RemoteEvent? = nil

-- Niveau actuel de l'arbre de l'etage (1..10 : Luck + vitesse de chute).
local function getLevel(player: Player, index: number): number?
	local data = DataService.GetData(player)
	local levels = data and DataService.FloorUpgrades(data, index)
	if levels == nil then
		return nil
	end
	return math.clamp(math.floor(levels.Tree or 1), 1, Fruits.PerFloor)
end

-- Pieces de deco en forme de fruit dans les anciens modeles (on les prenait pour de vrais fruits).
local DECO_FRUITS = { Apple = true, GoldenApple = true, AppleStem = true, HangFruit = true }

-- Prepare le modele de l'arbre : retire les fruits de deco (securite : TreeBuilder n'en fait pas)
-- et coupe la collision de toutes les pieces : le joueur traverse l'arbre et la camera de Roblox
-- (Poppercam) ne bute plus dessus.
local function prepareBody(body: Model)
	for _, item in body:GetDescendants() do
		if item:IsA("BasePart") then
			if DECO_FRUITS[item.Name] then
				item:Destroy()
			else
				item.CanCollide = false
				item.CanTouch = false
			end
		end
	end
end

-- Pose l'arbre de l'etage `index` au niveau `level` dans <Etage>.Tree.Body (remplace l'ancien) :
-- construit par TreeBuilder, sans fruit de deco ni collision, texte "Tree full!" a la bonne hauteur.
-- Renvoie ses mesures (meme si l'etage n'a pas de Tree.TreeRoot : rien n'est pose alors).
local function setTreeModel(floor: Model, index: number, level: number): TreeBuilder.Metrics
	local body, metrics = TreeBuilder.Build(index, level)
	local tree = floor:FindFirstChild("Tree")
	local root = tree and tree:FindFirstChild("TreeRoot")
	if tree == nil or root == nil or not root:IsA("BasePart") then
		body:Destroy()
		return metrics
	end
	body:PivotTo(root.CFrame)
	prepareBody(body)
	local old = tree:FindFirstChild("Body")
	if old then
		old:Destroy()
	end
	body.Parent = tree
	local anchor = tree:FindFirstChild("TreeLabelAnchor")
	if anchor and anchor:IsA("BasePart") then
		anchor.CFrame = root.CFrame * CFrame.new(0, metrics.labelHeight, 0)
	end
	-- TreeStage = palier : change a chaque niveau (TreeFxController joue la grande pousse)
	tree:SetAttribute("TreeStage", metrics.tier)
	tree:SetAttribute("TreeLevel", level)
	return metrics
end

-- Change l'arbre (modele, taille) si son niveau a change.
local function updateStage(state: TreeState)
	local level = getLevel(state.player, state.index) or 1
	local levelLabel = state.levelLabel
	if levelLabel then
		WorldLabel.SetPlainText(levelLabel, string.format(Gameplay.TreeLevelText, TreeConfig.NameFor(state.index), level))
	end
	if level ~= state.shownLevel then
		state.shownLevel = level
		state.metrics = setTreeModel(state.floor, state.index, level)
	end
end

local function updateLabel(state: TreeState)
	local label = state.label
	if label then
		WorldLabel.SetVisible(label, state.count >= Gameplay.MaxGroundFruits)
	end
end

-- Point au sol au hasard sous le feuillage du stade actuel (anneau autour du tronc), dans la zone.
local function randomGroundPoint(state: TreeState): Vector3
	local area = state.area
	local half = area.Size / 2
	local metrics = state.metrics or TreeBuilder.Measure(state.index, 1)
	local outer = math.min(metrics.dropRadius, half.X, half.Z)
	local inner = math.min(metrics.trunkClear, outer - 0.5)
	-- tirage uniforme dans l'anneau inner..outer
	local r = math.sqrt(rng:NextNumber(inner * inner, outer * outer))
	local a = rng:NextNumber(0, math.pi * 2)
	local x, z = math.cos(a) * r, math.sin(a) * r
	local top = area.CFrame:PointToWorldSpace(Vector3.new(x, half.Y + 2, z))
	local bottom = area.CFrame:PointToWorldSpace(Vector3.new(x, -half.Y, z))
	-- Le sol reel (herbe, fleurs) : on ignore les objets du jeu et les personnages.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { state.folder.Parent :: Instance }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(top, bottom - top, params)
	return if result then result.Position else bottom
end

-- Pose un fruit a sa place finale. Si `animate` : attributs de chute pour FruitFxController (le
-- client fait la chute qui tourne et rebondit, et les effets) ; ramassable apres la chute.
local function spawnFruit(state: TreeState, fruitId: string, animate: boolean, isNew: boolean?)
	local ground = randomGroundPoint(state)
	local model = FruitModels.CreateFruit(fruitId, true)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	-- Un fruit au sol est un peu penche (il ne tient pas droit comme un bloc)
	local tilt = CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	local finalCFrame = CFrame.new(ground) * yaw * tilt
	state.fruits[model] = fruitId
	state.count += 1
	model:PivotTo(finalCFrame)
	if not animate then
		model.Parent = state.folder
		return
	end
	local metrics = state.metrics or TreeBuilder.Measure(state.index, 1)
	-- Plus l'arbre est haut, plus la chute dure (comme une vraie chute : racine de la hauteur)
	local height = metrics.fallHeight
	local seconds = Gameplay.FruitFallSeconds * math.sqrt(height / Gameplay.FruitFallHeight)
	model:SetAttribute("DropStart", workspace:GetServerTimeNow())
	model:SetAttribute("DropHeight", height)
	model:SetAttribute("DropTime", seconds)
	if isNew then
		model:SetAttribute("NewFruit", true)
	end
	model.Parent = state.folder
	state.falling[model] = true
	task.delay(seconds, function()
		state.falling[model] = nil -- ramassable a partir de maintenant
	end)
end

-- Tire le fruit suivant parmi les 10 de l'etage (poids de sa rarete, Luck = niveau Tree).
-- Renvoie (id, pas encore decouvert ?). La decouverte se fait au RAMASSAGE (TreeService.Discover).
local function rollFruit(state: TreeState, level: number): (string?, boolean)
	local data = DataService.GetData(state.player)
	local pool = Fruits.OfFloor(state.index)
	if data == nil or #pool == 0 then
		return nil, false
	end
	-- Achats Robux (Lib/Perks) : pass Drink Master, boost Luck (Rare Rain x5) = rares plus frequents
	local weights = Fruits.RollWeights(Fruits.LuckMultiplier(level) * Perks.LuckMultiplier(state.player, true))
	local total = 0
	for _, fruit in pool do
		total += weights[fruit.rarity] or 0
	end
	local roll = rng:NextNumber(0, total)
	local picked = pool[1]
	for _, fruit in pool do
		roll -= weights[fruit.rarity] or 0
		if roll <= 0 then
			picked = fruit
			break
		end
	end
	return picked.id, not data.DiscoveredFruits[picked.id]
end

local function dropOne(state: TreeState): boolean
	if state.count >= Gameplay.MaxGroundFruits then
		return false
	end
	local level = getLevel(state.player, state.index)
	if level == nil then
		return false
	end
	local fruitId, isNew = rollFruit(state, level)
	if fruitId == nil then
		return false
	end
	spawnFruit(state, fruitId, true, isNew)
	updateLabel(state)
	return true
end

local function runTree(state: TreeState)
	while state.active do
		local level = getLevel(state.player, state.index)
		local interval = Upgrades.TreeDropSeconds(level or 1)
		task.wait(math.max(interval, Gameplay.ContactCheckSeconds))
		if not state.active then
			break
		end
		if level ~= nil then
			-- Stade de l'arbre (achats, outils de test, rebirth) puis chute.
			-- Une erreur ne doit pas arreter l'arbre pour toute la session
			pcall(updateStage, state)
			-- Lot 5 : l'arbre ne fait tomber des fruits que sur l'etage ou est le joueur (les autres
			-- etages produisent en nombres : Lib/FloorIncome)
			if FloorService.IsLive(state.floor) then
				local ok, err = pcall(dropOne, state)
				if not ok then
					warn(`[TreeService] Erreur de chute ({state.floor:GetFullName()}) : {err}`)
				end
			end
		end
	end
end

local function stopTree(floor: Model)
	local state = states[floor]
	if state == nil then
		return
	end
	states[floor] = nil
	state.active = false
	if state.thread and coroutine.status(state.thread) == "suspended" then
		task.cancel(state.thread)
	end
	-- Les modeles sont dans le Dynamic de l'etage, vide (ou l'etage detruit) juste apres.
	table.clear(state.fruits)
	table.clear(state.falling)
	-- Base libre (l'etage 1 reste) : on remet la jeune pousse
	if state.shownLevel ~= 1 and floor.Parent ~= nil then
		setTreeModel(floor, state.index, 1)
	end
end

-- Demarre l'arbre d'un etage (FloorService : etage d'un joueur charge).
local function startTree(player: Player, floor: Model, index: number)
	if states[floor] ~= nil or DataService.GetData(player) == nil then
		return
	end
	local tree = floor:FindFirstChild("Tree")
	local dynamic = floor:FindFirstChild("Dynamic")
	local area = tree and tree:FindFirstChild("FruitArea")
	local anchor = tree and tree:FindFirstChild("TreeLabelAnchor")
	if dynamic == nil or area == nil or not area:IsA("BasePart") then
		warn(`[TreeService] {floor:GetFullName()} : Tree.FruitArea ou Dynamic manquant`)
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "GroundFruits"
	folder.Parent = dynamic

	local state: TreeState = {
		player = player,
		floor = floor,
		index = index,
		area = area,
		folder = folder,
		fruits = {},
		falling = {},
		count = 0,
		label = nil,
		levelLabel = nil,
		thread = nil,
		active = true,
		shownLevel = 0,
		metrics = nil,
	}
	if anchor and anchor:IsA("BasePart") then
		-- Toujours au premier plan : le feuillage et les poutres ne le cachent plus
		local label = WorldLabel.Create(dynamic, anchor, "TreeFullLabel", {
			maxDistance = Gameplay.LabelMaxDistance + 30,
			size = UDim2.fromScale(10, 2.5),
			alwaysOnTop = true,
		})
		WorldLabel.SetPlainText(label, Gameplay.TreeFullText, Color3.fromRGB(255, 110, 110))
		WorldLabel.SetVisible(label, false)
		state.label = label
		-- Nom + niveau de l'arbre ("Golden Tree Lv 15"), meme style, juste sous "Tree full!"
		local levelLabel = WorldLabel.Create(dynamic, anchor, "TreeLevelLabel", {
			maxDistance = Gameplay.LabelMaxDistance + 30,
			size = UDim2.fromScale(13, 2), -- 8 -> 13 : place pour le nom ("Crystal Tree Lv 30")
			offset = Vector3.new(0, -Gameplay.TreeLevelLabelDrop, 0),
			alwaysOnTop = true,
		})
		state.levelLabel = levelLabel
	end
	states[floor] = state
	updateStage(state)

	-- Premiere visite : quelques pommes (premier fruit de la Config) deja au sol de l'etage 1
	-- (une seule fois par session, meme si la base est rendue puis redonnee)
	if index == 1 and DataService.IsFirstVisit(player) and not applesGiven[player] then
		applesGiven[player] = true
		local firstId = Fruits.List[1].id
		for _ = 1, math.min(Gameplay.FirstVisitApples, Gameplay.MaxGroundFruits) do
			spawnFruit(state, firstId, false)
		end
		updateLabel(state)
	end
	state.thread = task.spawn(runTree, state)
end

function TreeService:Init()
	feedbackEvent = Remotes.GetServerEvent("Feedback")
end

function TreeService:Start()
	FloorService.OnFloorStarted(startTree)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		stopTree(floor)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		applesGiven[player] = nil
	end)
	-- L'arbre change tout de suite apres un achat sur le pad "Upgrade Tree" de cet etage
	UpgradeService.OnBought(function(_player: Player, id: string, _level: number, floor: Model)
		if id ~= "Tree" then
			return
		end
		local state = states[floor]
		if state then
			updateStage(state)
		end
	end)
end

export type TakenFruit = { id: string, pos: Vector3 }

-- Decouverte (lot 4b) : le joueur (ou le Fruit Picker de l'etage ou il se trouve) vient de ramasser
-- ce fruit. Premiere fois : ecrit Data.DiscoveredFruits, previent le client (Feedback "Discover" :
-- animation NEW FRUIT!, DiscoveryController). `_floor` : etage du ramassage (plus utilise depuis
-- qu'il n'y a plus de fruits accroches dans l'arbre, garde pour les appels existants).
-- Renvoie vrai si c'etait une decouverte. Les etages calcules en nombres (lot 5) ne decouvrent rien.
function TreeService.Discover(player: Player, fruitId: string, _floor: Model?): boolean
	local data = DataService.GetData(player)
	if data == nil or Fruits.ById[fruitId] == nil or data.DiscoveredFruits[fruitId] then
		return false
	end
	data.DiscoveredFruits[fruitId] = true
	if feedbackEvent and player.Parent == Players then
		feedbackEvent:FireClient(player, "Discover", { fruit = fruitId })
	end
	IndexService.Sync(player)
	return true
end

local function removeFruit(state: TreeState, model: Model): TakenFruit?
	local fruitId = state.fruits[model]
	if fruitId == nil or state.falling[model] then
		return nil
	end
	local pos = model:GetPivot().Position + Vector3.new(0, 0.6, 0)
	state.fruits[model] = nil
	state.count -= 1
	model:Destroy()
	return { id = fruitId, pos = pos }
end

-- Ramassage en marchant : retire les fruits au sol (pas en chute) a moins de `radius` (a plat) de
-- `position` et a moins de 5 studs en hauteur, au plus `maxCount`. Les plus proches d'abord.
function TreeService.TakeNear(floor: Model, position: Vector3, radius: number, maxCount: number): { TakenFruit }
	local taken: { TakenFruit } = {}
	local state = states[floor]
	if state == nil or maxCount <= 0 then
		return taken
	end
	local radiusSq = radius * radius
	local near: { { model: Model, sq: number } } = {}
	for model in state.fruits do
		if state.falling[model] then
			continue
		end
		local p = model:GetPivot().Position
		local dx, dz = p.X - position.X, p.Z - position.Z
		local sq = dx * dx + dz * dz
		if sq <= radiusSq and math.abs(p.Y - position.Y) < 5 then
			table.insert(near, { model = model, sq = sq })
		end
	end
	if #near == 0 then
		return taken
	end
	table.sort(near, function(a, b)
		return a.sq < b.sq
	end)
	for _, entry in near do
		if #taken >= maxCount then
			break
		end
		local item = removeFruit(state, entry.model)
		if item then
			table.insert(taken, item)
		end
	end
	updateLabel(state)
	return taken
end

-- Fruit au sol le plus proche de `position` (pas en chute, pas dans `exclude`).
-- `knownOnly` : seulement les fruits deja decouverts par le joueur (le Fruit Picker laisse au
-- joueur le plaisir de ramasser lui-meme un nouveau fruit).
function TreeService.FindNearest(
	floor: Model,
	position: Vector3,
	exclude: { [Model]: boolean }?,
	knownOnly: boolean?
): Model?
	local state = states[floor]
	if state == nil then
		return nil
	end
	local data = if knownOnly then DataService.GetData(state.player) else nil
	if knownOnly and data == nil then
		return nil
	end
	local best: Model? = nil
	local bestSq = math.huge
	for model, fruitId in state.fruits do
		if state.falling[model] or (exclude and exclude[model]) then
			continue
		end
		if data and not data.DiscoveredFruits[fruitId] then
			continue
		end
		local p = model:GetPivot().Position
		local dx, dz = p.X - position.X, p.Z - position.Z
		local sq = dx * dx + dz * dz
		if sq < bestSq then
			best, bestSq = model, sq
		end
	end
	return best
end

-- Retire ce fruit precis du sol (s'il y est encore). Renvoie son id et sa position.
function TreeService.TakeFruit(floor: Model, model: Model): TakenFruit?
	local state = states[floor]
	if state == nil then
		return nil
	end
	local item = removeFruit(state, model)
	if item then
		updateLabel(state)
	end
	return item
end

-- Nombre de fruits au sol (tests).
function TreeService.GetGroundCount(floor: Model): number
	local state = states[floor]
	return if state then state.count else 0
end

-- Tests (DebugService en Studio, panneau admin) : fait tomber `count` fruits tout de suite.
-- Serveur seulement : les appelants verifient Studio / admin.
function TreeService.DebugDrop(player: Player, count: number): number
	local floor = FloorService.GetPlayerFloor(player) or FloorService.GetFloor(player, 1)
	local state = floor and states[floor]
	if state == nil then
		return 0
	end
	local dropped = 0
	for _ = 1, math.clamp(math.floor(count), 0, Gameplay.MaxGroundFruits) do
		if not dropOne(state) then
			break
		end
		dropped += 1
	end
	return dropped
end

return TreeService
