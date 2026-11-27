--!strict
-- Rigs R15 des PNJ (serveur), comme les joueurs. Prepare() fabrique les modeles a partir des tenues
-- de Config/Npcs (Players:CreateHumanoidModelFromDescription, R15) :
--   * ReplicatedStorage.NpcTemplates.Customer<n> : copies par les clients (CustomerController) ;
--   * employes (Collector, Server, Operator = operateurs des mixeurs) : gardes ici, copies par Spawn().
-- Spawn() cree un employe qui marche (Humanoid:MoveTo + PathfindingService pour contourner les
-- meubles) avec les animations de base de Roblox (Animator du serveur : repliquees a tous).
-- Tous les PNJ en R15 depuis le 2026-11-27 (avant : R6) : animations R15 des joueurs
-- (Npcs.AnimationsR15), marche + course melangees selon la vitesse comme le script Animate
-- (Util/R15Walk). Gestes (Pick, Dump, Press, Deposit) : le serveur pose l'heure de depart en
-- attributs, chaque client dessine la pose (CarryPoseController).
-- La marche ne joue que pendant MoveTo, l'attente le reste du temps. Les PNJ ne bloquent pas les
-- joueurs (groupes de collision "Npc" / "Players").
-- Doc : docs/systems/ameliorations-employes.md

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Gameplay = require(Config:WaitForChild("Gameplay"))
local Npcs = require(Config:WaitForChild("Npcs"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))
local R15Walk = require(Shared:WaitForChild("Util"):WaitForChild("R15Walk"))

local NpcRig = {}

export type Npc = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	hipOffset: number, -- hauteur du centre du HumanoidRootPart au-dessus des pieds
	held: Model?,
	connections: { RBXScriptConnection },
	walkTrack: AnimationTrack?,
	runTrack: AnimationTrack?, -- melangee a la marche selon la vitesse (R15Walk)
	idleTrack: AnimationTrack?,
	walking: boolean,
	path: Path?,
}

type StepResult = "done" | "stuck" | "cancel"

local NPC_GROUP = "Npc"
local PLAYER_GROUP = "Players"
local CARRY_TAG = "CarryPoseRig"
local DISABLED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.PlatformStanding,
}

local employeeTemplates: { [string]: Model } = {}
local prepared = false

local function applyColors(desc: HumanoidDescription, outfit: Npcs.Outfit, shirtColor: Color3, pantsColor: Color3)
	desc.HeadColor = outfit.skin
	desc.LeftArmColor = if outfit.shirt > 0 then outfit.skin else shirtColor
	desc.RightArmColor = if outfit.shirt > 0 then outfit.skin else shirtColor
	desc.TorsoColor = shirtColor
	desc.LeftLegColor = pantsColor
	desc.RightLegColor = pantsColor
end

local function buildDescription(outfit: Npcs.Outfit, shirtColor: Color3, withAssets: boolean): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	applyColors(desc, outfit, shirtColor, Color3.fromRGB(60, 70, 110))
	if withAssets then
		desc.Shirt = outfit.shirt
		desc.Pants = outfit.pants
		desc.Face = outfit.face
		if outfit.hair > 0 then
			desc.HairAccessory = tostring(outfit.hair)
		end
		if outfit.hat > 0 then
			desc.HatAccessory = tostring(outfit.hat)
		end
	end
	return desc
end

local function setGroup(model: Model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CollisionGroup = NPC_GROUP
		end
	end
end

-- Construit un rig R15 (avec les vetements ; sans eux si le chargement echoue).
local function buildRig(name: string, outfit: Npcs.Outfit, shirtColor: Color3): Model?
	local model: Model? = nil
	local rigType = Enum.HumanoidRigType.R15
	for _, withAssets in { true, false } do
		local desc = buildDescription(outfit, shirtColor, withAssets)
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, rigType)
		end)
		desc:Destroy()
		if ok and result then
			model = result
			break
		end
		warn(`[NpcRig] {name} : rig non cree (vetements={withAssets}) : {result}`)
	end
	if model == nil then
		return nil
	end
	model.Name = name
	for _, item in model:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		if humanoid:FindFirstChildOfClass("Animator") == nil then
			Instance.new("Animator").Parent = humanoid
		end
	end
	setGroup(model)
	return model
end

-- Tablier et casquette de la couleur du poste + nom au-dessus de la tete (tablier sur UpperTorso).
local function dressEmployee(model: Model, title: string, color: Color3)
	local torso = model:FindFirstChild("UpperTorso")
	local head = model:FindFirstChild("Head")
	local function weldPart(name: string, size: Vector3, offset: CFrame, to: BasePart, partColor: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = partColor
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = to.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = p
		weld.Part1 = to
		weld.Parent = p
		p.Parent = model
	end
	if torso and torso:IsA("BasePart") then
		-- Haut du tablier 0.2 sous le haut du torse
		local top, front = torso.Size.Y / 2, torso.Size.Z / 2
		local apronHeight = 1.35
		weldPart(
			"Apron",
			Vector3.new(1.6, apronHeight, 0.1),
			CFrame.new(0, top - 0.2 - apronHeight / 2, -(front + 0.05)),
			torso,
			color
		)
		weldPart("ApronStrap", Vector3.new(1.6, 0.18, 0.12), CFrame.new(0, top - 0.25, -(front + 0.06)), torso, Color3.new(1, 1, 1))
	end
	if head and head:IsA("BasePart") then
		weldPart("Cap", Vector3.new(1.25, 0.4, 1.25), CFrame.new(0, 0.62, 0), head, color)
		weldPart("CapBrim", Vector3.new(1.25, 0.12, 0.7), CFrame.new(0, 0.46, -0.85), head, color)
		local tag = Instance.new("BillboardGui")
		tag.Name = "RoleTag"
		tag.Size = UDim2.fromScale(6, 1.1)
		tag.StudsOffset = Vector3.new(0, 2.3, 0)
		tag.MaxDistance = 55
		tag.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = title
		label.TextScaled = true
		label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		label.FontFace = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		stroke.Thickness = 0.08
		stroke.Parent = label
		label.Parent = tag
		tag.Parent = head
	end
	setGroup(model)
end

-- Serveur, une fois au demarrage (attend le chargement des vetements : appeler dans un thread).
function NpcRig.Prepare()
	if prepared then
		return
	end
	prepared = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(NPC_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(NPC_GROUP, NPC_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(NPC_GROUP, PLAYER_GROUP, false)

	for role, info in Npcs.Employees do
		local rig = buildRig(role, Npcs.EmployeeOutfit, info.color)
		if rig then
			dressEmployee(rig, info.title, info.color)
			employeeTemplates[role] = rig
		end
	end

	local folder = ReplicatedStorage:FindFirstChild(Npcs.TemplateFolder)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = Npcs.TemplateFolder
		folder = created
	end
	for i, outfit in Npcs.CustomerOutfits do
		local color = Npcs.FallbackShirtColors[((i - 1) % #Npcs.FallbackShirtColors) + 1]
		local rig = buildRig("Customer" .. i, outfit, color)
		if rig then
			rig.Parent = folder
		end
	end
	if folder and folder.Parent == nil then
		folder.Parent = ReplicatedStorage
	end
end

-- Range le personnage d'un joueur dans le groupe "Players" (les PNJ passent a travers).
function NpcRig.TagPlayerCharacter(character: Model)
	local function apply(item: Instance)
		if item:IsA("BasePart") then
			item.CollisionGroup = PLAYER_GROUP
		end
	end
	for _, item in character:GetDescendants() do
		apply(item)
	end
	character.DescendantAdded:Connect(apply)
end

-- Animations : l'attente tourne en boucle ; la marche est lancee / arretee UNIQUEMENT par MoveTo
-- (avant : l'evenement Humanoid.Running, qui se declenchait aussi a l'arret, sur un petit choc ou
-- pendant un blocage -> marche sur place au mauvais moment, signale le 2026-11-19 soir).
local function loadAnimations(npc: Npc)
	local animator = npc.humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local function load(id: string, priority: Enum.AnimationPriority): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = priority
		return track
	end
	local ids = Npcs.AnimationsR15
	npc.idleTrack = load(ids.Idle, Enum.AnimationPriority.Idle)
	npc.walkTrack = load(ids.Walk, Enum.AnimationPriority.Movement)
	npc.runTrack = load(ids.Run, Enum.AnimationPriority.Movement)
	local idle = npc.idleTrack
	if idle then
		idle:Play()
	end
end

local function setWalking(npc: Npc, walking: boolean)
	if npc.walking == walking then
		return
	end
	npc.walking = walking
	local walk, run, idle = npc.walkTrack, npc.runTrack, npc.idleTrack
	if walking then
		R15Walk.Play(walk, run, npc.humanoid.WalkSpeed, 0.2)
		if idle then
			idle:Stop(0.15)
		end
	else
		if walk then
			walk:Stop(0.2)
		end
		if run then
			run:Stop(0.2)
		end
		if idle then
			idle:Play(0.2)
		end
	end
end

-- Cree un employe (role = cle de Npcs.Employees) debout a `cframe` (pieds au sol a cframe.Y).
function NpcRig.Spawn(role: string, cframe: CFrame, parent: Instance): Npc?
	local template = employeeTemplates[role]
	if template == nil then
		return nil
	end
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	local boxCFrame, size = model:GetBoundingBox()
	local hipOffset = math.max(2.5, root.Position.Y - (boxCFrame.Position.Y - size.Y / 2))
	model:PivotTo(cframe + Vector3.new(0, hipOffset + 0.1, 0))
	humanoid.WalkSpeed = Gameplay.EmployeeWalkSpeed
	for _, state in DISABLED_STATES do
		humanoid:SetStateEnabled(state, false)
	end
	CollectionService:AddTag(model, CARRY_TAG)
	model.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local npc: Npc = {
		model = model,
		humanoid = humanoid,
		root = root,
		hipOffset = hipOffset,
		held = nil,
		connections = {},
		walkTrack = nil,
		runTrack = nil,
		idleTrack = nil,
		walking = false,
		path = nil,
	}
	loadAnimations(npc)
	return npc
end

-- Le serveur simule toujours les PNJ. Souder un objet au corps (SetHeld) ou le deplacer remet la
-- propriete reseau en "automatique" : le joueur le plus proche prenait alors le controle et le PNJ
-- s'arretait ~0.8 s a chaque point de passage en jouant la marche sur place (vu le 2026-11-19 soir).
local function claim(npc: Npc)
	pcall(function()
		npc.root:SetNetworkOwner(nil)
	end)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Points de passage autour des meubles (PathfindingService). Sans chemin : ligne droite.
local function waypoints(npc: Npc, target: Vector3): { Vector3 }
	local path = npc.path
	if path == nil then
		path = PathfindingService:CreatePath({
			AgentRadius = 1.4,
			AgentHeight = 5,
			AgentCanJump = false,
			AgentCanClimb = false,
			WaypointSpacing = 5,
		})
		npc.path = path
	end
	local points: { Vector3 } = {}
	local ok = pcall(function()
		(path :: Path):ComputeAsync(npc.root.Position - Vector3.new(0, npc.hipOffset, 0), target)
	end)
	if ok and (path :: Path).Status == Enum.PathStatus.Success then
		for index, waypoint in (path :: Path):GetWaypoints() do
			if index > 1 then -- le premier point = la position de depart
				table.insert(points, waypoint.Position)
			end
		end
	end
	if #points == 0 then
		table.insert(points, target)
	end
	return points
end

-- Marche jusqu'a un point. "stuck" si le PNJ n'avance plus (bloque), "cancel" si l'employe s'arrete.
-- Verifie a chaque frame et passe au point suivant AVANT d'y arriver (`isLast` = faux) : le Humanoid
-- s'arrete net sur chaque point atteint, et l'ancienne attente de 0.1 s le laissait immobile un
-- instant tous les 5 studs -> marche a-coups (signale le 2026-11-20).
local function walkStep(npc: Npc, point: Vector3, isActive: () -> boolean, isLast: boolean): StepResult
	local reached = false
	local connection = npc.humanoid.MoveToFinished:Connect(function()
		reached = true
	end)
	npc.humanoid:MoveTo(point)
	local started = os.clock()
	local lastPos = npc.root.Position
	local stillSince = os.clock()
	local result: StepResult = "done"
	local arriveDistance = if isLast then 1 else Npcs.WaypointLookAhead
	while not reached do
		task.wait()
		if not isActive() or npc.model.Parent == nil then
			result = "cancel"
			break
		end
		local pos = npc.root.Position
		if flatDistance(pos, point) < arriveDistance then
			break
		end
		if flatDistance(pos, lastPos) > 0.25 then
			lastPos = pos
			stillSince = os.clock()
		elseif os.clock() - stillSince > Npcs.StuckSeconds or os.clock() - started > Gameplay.NpcMoveTimeout then
			result = "stuck"
			break
		end
	end
	connection:Disconnect()
	return result
end

-- Marche jusqu'a `target` (au sol) en contournant les meubles. L'animation de marche ne joue que
-- pendant le trajet. Si le PNJ est bloque, il est pose a l'arrivee. Renvoie faux si annule.
function NpcRig.MoveTo(npc: Npc, target: Vector3, isActive: () -> boolean): boolean
	if npc.model.Parent == nil then
		return false
	end
	if flatDistance(npc.root.Position, target) < 1.2 then
		return true
	end
	claim(npc)
	-- Chemin calcule AVANT de lancer l'animation : pas de marche sur place pendant le calcul
	local points = waypoints(npc, target)
	if npc.model.Parent == nil or not isActive() then
		return false
	end
	setWalking(npc, true)
	local result: StepResult = "done"
	for index, point in points do
		result = walkStep(npc, point, isActive, index == #points)
		if result ~= "done" then
			break
		end
	end
	if npc.model.Parent ~= nil then
		npc.humanoid:MoveTo(npc.root.Position) -- s'arrete net (pas de glissade apres l'animation)
	end
	setWalking(npc, false)
	if result == "cancel" or npc.model.Parent == nil then
		return false
	end
	if flatDistance(npc.root.Position, target) > 3 then
		-- Bloque contre quelque chose : on le pose a l'arrivee
		npc.model:PivotTo(CFrame.new(target.X, target.Y + npc.hipOffset + 0.1, target.Z) * npc.root.CFrame.Rotation)
		claim(npc)
	end
	return true
end

-- Tourne le PNJ vers un point.
function NpcRig.Face(npc: Npc, position: Vector3)
	local from = npc.root.Position
	local flat = Vector3.new(position.X, from.Y, position.Z)
	if (flat - from).Magnitude > 0.1 then
		npc.root.CFrame = CFrame.lookAt(from, flat)
	end
end

-- Objets portes devant le torse (fruits ou jus), bras leves par le client (attribut CarryPose).
function NpcRig.SetHeld(npc: Npc, kind: "Fruit" | "Juice" | nil, ids: { string })
	if npc.held then
		npc.held:Destroy()
		npc.held = nil
	end
	local holding = kind ~= nil and #ids > 0
	npc.model:SetAttribute("CarryPose", holding)
	if not holding then
		claim(npc)
		return
	end
	local stack = Instance.new("Model")
	stack.Name = "Held"
	local step = if kind == "Juice" then FruitModels.CupHeight + 0.02 else FruitModels.FruitSize * 0.8
	for index, id in ids do
		local item = if kind == "Juice" then FruitModels.CreateCup(id, false) else FruitModels.CreateFruit(id, false)
		local layer = (index - 1) // 2
		local half = if kind == "Juice" then 0.55 else 0.45 -- gobelets de 1.04 de large : jamais colles
		local dx = if index % 2 == 1 then -half else half
		item:PivotTo(npc.root.CFrame * CFrame.new(dx, -0.3 + layer * step, -1.5))
		local primary = item.PrimaryPart
		if primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = npc.root
			weld.Parent = primary
		end
		for _, part in item:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = NPC_GROUP
				part.CanCollide = false
				part.CanTouch = false
				part.Massless = true
				part.CastShadow = false
			end
		end
		item.Parent = stack
	end
	stack.Parent = npc.model
	npc.held = stack
	claim(npc) -- les objets soudes remettent la propriete reseau en automatique
end

NpcRig.PressReachSeconds = Npcs.PressReachSeconds -- temps entre le debut du geste et l'appui sur le bouton
NpcRig.DepositTurnSeconds = Npcs.DepositTurnSeconds -- l'operateur se tourne vers la table avant de lancer les gobelets
NpcRig.CupPopStagger = 0.06 -- ecart entre deux gobelets (meme valeur que CUP_POP_STAGGER, BlenderFxController)

-- Heure de depart d'un geste dessine par les clients (CarryPoseController) : attributs <name>Time
-- (duree) puis <name>Start (horloge GetServerTimeNow, pose en dernier : declenche le geste).
local function startGesture(npc: Npc, name: string, seconds: number)
	npc.model:SetAttribute(name .. "Time", seconds)
	npc.model:SetAttribute(name .. "Start", workspace:GetServerTimeNow())
end

-- Petit geste du bras droit (appuyer sur un bouton devant soi, R15 depuis le 2026-11-27) : le bras se
-- leve vers l'avant, appuie a Npcs.PressReachSeconds, puis redescend (Npcs.PressSeconds). Le serveur
-- pose seulement l'heure de depart (PressStart / PressTime) ; la pose est dessinee par chaque client
-- (CarryPoseController). Avant : tweens du C0 de l'epaule R6, repliques. Bloque pendant le geste.
function NpcRig.Press(npc: Npc)
	startGesture(npc, "Press", Npcs.PressSeconds)
	task.wait(Npcs.PressSeconds)
end

-- Tourne le PNJ en douceur vers un point (sur place, `seconds`). Bloque pendant la rotation.
local function turnTo(npc: Npc, position: Vector3, seconds: number)
	local start = npc.root.CFrame.Rotation
	local from = npc.root.Position
	local flat = Vector3.new(position.X, from.Y, position.Z)
	if (flat - from).Magnitude < 0.1 then
		return
	end
	local goal = CFrame.lookAt(from, flat).Rotation
	local t = 0
	while t < seconds do
		t += task.wait()
		if npc.model.Parent == nil then
			return
		end
		local a = math.clamp(t / seconds, 0, 1)
		a = a * a * (3 - 2 * a)
		npc.root.CFrame = CFrame.new(npc.root.Position) * start:Lerp(goal, a)
	end
end

-- Point devant les mains quand le PNJ regarde `toward` et tend les bras (d'ou partent les gobelets).
function NpcRig.HandsPoint(npc: Npc, toward: Vector3): Vector3
	local from = npc.root.Position
	local flat = Vector3.new(toward.X, from.Y, toward.Z)
	local facing = if (flat - from).Magnitude > 0.1 then CFrame.lookAt(from, flat) else npc.root.CFrame
	return (facing * CFrame.new(0, 0.4, -2)).Position
end

-- Operateur qui pose les jus sur la table (2026-11-27, R15) : il se tourne vers la table en tendant les
-- deux bras (DepositTurnSeconds), donne un petit coup de bras vers le haut pendant que les gobelets
-- sautent de ses mains (`throwSeconds`), baisse les bras et se retourne vers `backTo` (son bouton).
-- Bras dessines par chaque client (CarryPoseController, attributs DepositStart / DepositTime /
-- DepositToss) ; le serveur tourne seulement le corps. Bloque pendant le geste (~1.2 s + throwSeconds).
function NpcRig.Deposit(npc: Npc, toward: Vector3, backTo: Vector3?, throwSeconds: number)
	local turn = NpcRig.DepositTurnSeconds
	local toss = math.max(0.15, throwSeconds)
	-- Duree des bras : tendus (turn), lancer (toss), tenus (0.15), redescendent (0.3)
	npc.model:SetAttribute("DepositToss", toss)
	startGesture(npc, "Deposit", turn + toss + 0.45)
	turnTo(npc, toward, turn)
	task.wait(toss + 0.15 + 0.25)
	if backTo and npc.model.Parent ~= nil then
		turnTo(npc, backTo, turn)
	end
	claim(npc)
end

-- Fruit Picker R15 (2026-11-27) : geste de ramassage d'un fruit au sol, en `seconds`. Le serveur
-- pose seulement l'heure de depart (attributs PickStart / PickTime, horloge GetServerTimeNow) :
-- chaque client dessine la pose (debout, bras droit vers le fruit puis vers le plateau,
-- CarryPoseController ; plus d'accroupi depuis le 2026-11-27). Ici : il se tourne en douceur vers le fruit, a Npcs.PickGrabAt la main
-- touche le fruit -> `grab()` le retire du sol et renvoie son id ; une copie suit la main droite
-- jusqu'a Npcs.PickTrayAt, puis `toTray()` le pose sur le plateau. Bloque pendant le geste.
function NpcRig.Pick(npc: Npc, fruitPos: Vector3, seconds: number, grab: () -> string?, toTray: (string) -> ())
	turnTo(npc, fruitPos, 0.15)
	if npc.model.Parent == nil then
		return
	end
	startGesture(npc, "Pick", seconds)
	task.wait(seconds * Npcs.PickGrabAt)
	if npc.model.Parent == nil then
		return
	end
	local id = grab()
	local inHand: Model? = nil
	local hand = npc.model:FindFirstChild("RightHand")
	if id and hand and hand:IsA("BasePart") then
		local fruit = FruitModels.CreateFruit(id, false)
		fruit:PivotTo(hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - FruitModels.FruitSize * 0.35, 0))
		for _, part in fruit:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Massless = true
				part.CastShadow = false
				part.CollisionGroup = NPC_GROUP
			end
		end
		local primary = fruit.PrimaryPart
		if primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = hand
			weld.Parent = primary
		end
		fruit.Name = "PickedFruit"
		fruit.Parent = npc.model
		inHand = fruit
		claim(npc) -- les objets soudes remettent la propriete reseau en automatique
	end
	task.wait(seconds * (Npcs.PickTrayAt - Npcs.PickGrabAt))
	if inHand then
		inHand:Destroy()
	end
	if id and npc.model.Parent ~= nil then
		toTray(id)
	end
	task.wait(seconds * (1 - Npcs.PickTrayAt))
	claim(npc)
end

-- Fruit Picker R15 (2026-11-27) : depot a l'etagere. Il se tourne vers `toward` (les caisses), pousse
-- son plateau vers l'avant en penchant la tete (pose dessinee par CarryPoseController, attributs
-- DumpStart / DumpTime) ; a Npcs.DumpReleaseAt, `release(from)` vide le plateau (`from` = point
-- au-dessus de sa tete, d'ou les fruits s'envolent). Bloque pendant le geste.
function NpcRig.Dump(npc: Npc, toward: Vector3?, seconds: number, trayAbove: number, release: (Vector3) -> ())
	if toward then
		turnTo(npc, toward, 0.2)
	end
	if npc.model.Parent == nil then
		return
	end
	startGesture(npc, "Dump", seconds)
	task.wait(seconds * Npcs.DumpReleaseAt)
	if npc.model.Parent == nil then
		return
	end
	local head = npc.model:FindFirstChild("Head")
	local top = if head and head:IsA("BasePart")
		then head.Position + Vector3.new(0, head.Size.Y / 2 + trayAbove + 0.3, 0)
		else npc.root.Position + Vector3.new(0, 3, 0)
	release(top + npc.root.CFrame.LookVector * 1.2)
	task.wait(seconds * (1 - Npcs.DumpReleaseAt))
	claim(npc)
end

-- Point ou le PNJ se place pour ramasser un objet au sol : a `reach` studs de lui, du cote d'ou il
-- arrive (au sol, a la hauteur de ses pieds). Pas besoin de bouger s'il est deja a bonne distance.
function NpcRig.ReachPoint(npc: Npc, target: Vector3, reach: number): Vector3?
	local from = npc.root.Position
	local flat = Vector3.new(from.X - target.X, 0, from.Z - target.Z)
	local feetY = from.Y - npc.hipOffset
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, 1)
	end
	if math.abs(flat.Magnitude - reach) < 0.6 then
		return nil
	end
	local point = target + flat.Unit * reach
	return Vector3.new(point.X, feetY, point.Z)
end

function NpcRig.Destroy(npc: Npc)
	for _, connection in npc.connections do
		connection:Disconnect()
	end
	table.clear(npc.connections)
	if npc.path then
		npc.path:Destroy()
		npc.path = nil
	end
	npc.model:Destroy()
end

return NpcRig
