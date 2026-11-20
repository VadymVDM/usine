--!strict
-- Clients de la buvette, dessines cote client seulement (le serveur decide de chaque vente).
-- Pour chaque base avec proprietaire et proche de la camera, SEULEMENT l'etage ou se trouve le
-- proprietaire (attribut de base ActiveFloor, 1 si absent) : un client "devant" (au comptoir) et
-- un client "qui attend" (derriere) par emplacement actif. Sur l'evenement WorldFx "Sale", le client
-- devant prend un gobelet, montre "+$", puis repart et disparait.
-- Deplacement sans physique : HumanoidRootPart ancre, deplace a la main dans RenderStepped.
-- Etats d'un client : Walking -> Standing (arrive) ; Standing/Walking -> Leaving -> fondu -> detruit.
-- Etape (stage) : "Street" (etage 1, rue) ; etages 2+ : "Queue" (file en serpentin dans toute la
-- terrasse, Annex.Terrace.QueuePath.Point1..N) -> "Board" (marche vers la cabine) -> "Ride" (dans la cabine qui
-- monte) -> "Balcony" (sorti sur le balcon : va a sa place, achete, repart vers la sortie de
-- l'ascenseur et disparait en fondu).
-- Ascenseur : une "Lift" par etage dessine ; la cabine (Annex.ElevatorBase.Cabin si elle existe,
-- sinon une cabine simple creee ici) est deplacee EN LOCAL (pieces ancrees, rien n'est envoye au
-- serveur). Les places (front / waiting) des etages 2+ sont reservees a l'embarquement.
-- Vente sur un etage 2+ sans client pret au comptoir : "+$" et son seuls (pas de teleportation).
-- WorldFx "Sale" : 1er argument = l'etage. Attributs CounterJuices / CustomerSlots sur l'etage ;
-- OwnerUserId, ActiveFloor, ElevatorSpeed, ElevatorCabin sur la base.
-- Doc : docs/systems/clients.md

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Npcs = require(Shared:WaitForChild("Config"):WaitForChild("Npcs")) :: any
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits")) :: any
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local MAX_SPOTS = 5
local POLL_SECONDS = 0.5
local SPAWN_GAP_SECONDS = 1.5 -- delai minimum entre deux arrivees d'une meme base
local INSTANT_WINDOW_SECONDS = 2 -- apres l'affichage d'une base : clients places directement
local CUP_FLY_SECONDS = 0.25
local LEAVE_DELAY_SECONDS = 0.4
local FADE_SECONDS = 0.4
local SWITCH_FADE_SECONDS = 0.25 -- fondu des clients de l'ancien etage quand ActiveFloor change
local EXIT_DISTANCE = 25
local SIDESTEP = 3
local HAND_OFFSET = CFrame.new(0, -0.3, -1.3)
local SALE_COLOR = PackStyle.MONEY_GREEN

-- Ascenseur des clients (etages 2+). A VALIDER en jeu.
local LIFT_BASE_SECONDS = 3 -- montee jusqu'a l'etage 2 (niveau ElevatorSpeed 0)
local LIFT_PER_FLOOR_SECONDS = 0.6 -- + par etage au-dessus du 2
local LIFT_SPEED_BONUS = 0.04 -- duree = (base + par etage) / (1 + 0.04 * ElevatorSpeed)
local LIFT_DOWN_FACTOR = 0.6 -- la descente a vide va plus vite
local LIFT_CAPACITY_BASE = 2 -- clients par voyage = 2 + floor(ElevatorCabin / 5)
local LIFT_CAPACITY_STEP = 5
local LIFT_DOOR_SECONDS = 0.6 -- pause portes avant de monter
local LIFT_UNLOAD_SECONDS = 1.2 -- les clients sortent avant que la cabine redescende
local LIFT_BOARD_TIMEOUT = 15 -- embarquement trop long : la cabine part sans les retardataires
-- File de la terrasse (2026-11-20, retour de test : "la file doit occuper toute la terrasse") :
-- le chemin serpente dans la longueur de la terrasse (Point1..N). L'ecart entre deux clients =
-- longueur du chemin / QUEUE_MAX : la file pleine (Customers au max) couvre toute la terrasse, et
-- elle s'allonge a chaque niveau de clients (QUEUE_BASE + QUEUE_PER_SLOT par emplacement).
local QUEUE_GAP = 2.6 -- ecart minimum entre deux clients de la file (studs)
local QUEUE_MAX = 40 -- clients max dans la file de la terrasse
local QUEUE_BASE = 10
local QUEUE_PER_SLOT = 6
local QUEUE_STREET = 7 -- les clients de la terrasse arrivent de la rue (studs devant Point1)
-- Ascenseur : la cage est 6 studs apres ElevatorEntry (vers le balcon), 8 x 8, porte a 4 du centre
local CAGE_FROM_ENTRY = 6
local CAGE_DOOR = 4.5
local CABIN_FLOOR_RISE = 0.2 -- dessus du plancher de la cabine au-dessus du fond de la cage
local CABIN_SPOTS = { -- places dans la cabine (x vers la sortie, z), le fond d'abord
	Vector2.new(1.8, -1.8),
	Vector2.new(1.8, 1.8),
	Vector2.new(1.8, 0),
	Vector2.new(0, -1.8),
	Vector2.new(0, 1.8),
	Vector2.new(0, 0),
	Vector2.new(-1.8, -1.8),
	Vector2.new(-1.8, 1.8),
	Vector2.new(-1.8, 0),
}

local CustomerController = {}

type Status = "Walking" | "Standing" | "Leaving"
type Role = "Front" | "Waiting"
type Stage = "Street" | "Queue" | "Board" | "Ride" | "Balcony"
type LiftPhase = "Idle" | "Boarding" | "Closing" | "Up" | "Unloading" | "Down"

-- File de la terrasse + geometrie de l'ascenseur (positions monde, au sol).
type Route = {
	pts: { Vector3 }, -- Point1..PointN puis ElevatorEntry
	gap: number, -- ecart entre deux clients de la file
	arcs: { number }, -- distance depuis Point1
	length: number,
	street: Vector3, -- apparition (rue, devant Point1)
	entry: Vector3, -- ElevatorEntry (tete de la file)
	xAxis: Vector3, -- de la terrasse vers le balcon
	cage: Vector3, -- centre du fond de la cage (en bas)
	height: number, -- hauteur de la montee (etage dessine)
	exit: Vector3, -- CustomerEntry de l'etage (balcon)
}

type Lift = {
	phase: LiftPhase,
	offset: number,
	from: number,
	to: number,
	t: number,
	duration: number,
	timer: number,
	riders: { Customer },
	cabin: Model?,
	rest: CFrame?,
	fallback: Model?,
	floorTop: Vector3, -- centre du dessus du plancher de la cabine, en bas
}

type BaseState = {
	base: Model, -- l'ETAGE (Markers, Counter, CounterJuices, CustomerSlots)
	owner: Model, -- la base (OwnerUserId, ActiveFloor, ElevatorSpeed, ElevatorCabin)
	index: number, -- numero de l'etage
	ownerId: number,
	rendered: boolean,
	slots: number,
	instantUntil: number,
	lastSpawn: number,
	count: number,
	front: { [number]: Customer },
	waiting: { [number]: Customer },
	customers: { [Customer]: boolean },
	queue: { Customer },
	route: Route?,
	lift: Lift?,
	conns: { RBXScriptConnection },
}

type Customer = {
	home: BaseState,
	model: Model,
	hrp: BasePart,
	head: BasePart,
	torso: BasePart?,
	parts: { BasePart },
	hip: number,
	spot: number,
	role: Role,
	stage: Stage,
	status: Status,
	speed: number,
	pos: Vector3, -- au sol (hauteur du marqueur)
	yaw: number,
	targetYaw: number,
	faceYaw: number,
	path: { Vector3 },
	pathIndex: number,
	onArrive: (() -> ())?,
	timer: number,
	onTimer: (() -> ())?,
	walkTrack: AnimationTrack?,
	idleTrack: AnimationTrack?,
	moving: boolean,
	dirty: boolean,
	sold: boolean,
	fading: boolean,
	fadeT: number,
	fadeSeconds: number,
	queueArc: number, -- file : distance (depuis Point1) du dernier point vise
	ridePos: Vector3, -- place dans la cabine, cabine en bas
	cup: Model?,
	cupParts: { BasePart },
	cupStart: Vector3,
	cupT: number,
	torsoRel: CFrame,
	bubble: BillboardGui?,
	destroyed: boolean,
}

local started = false
local rng = Random.new()
local customersFolder: Folder? = nil
local templateFolder: Folder? = nil
local states: { [Model]: BaseState } = {}
local active: { [Customer]: boolean } = {}
local liftStates: { [BaseState]: boolean } = {}
local cabinOwner: { [Model]: BaseState } = {} -- base -> etage qui utilise sa cabine
local cabinRest: { [Model]: { pivot: CFrame, top: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any
local pending: { () -> () } = {}
local hipCache: { [Instance]: number } = {}
local clipCache: { [string]: Animation } = {}
local saleConn: RBXScriptConnection? = nil
local stepConn: RBXScriptConnection? = nil

local destroyCustomer: (c: Customer) -> ()
local startLeaving: (c: Customer) -> ()
local fill: (state: BaseState, k: number, instant: boolean) -> ()
local refreshBubble: (c: Customer) -> ()

---------------------------------------------------------------------------------------------
-- Aides geometriques

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function floorPos(part: BasePart): Vector3
	return Vector3.new(part.Position.X, part.Position.Y - part.Size.Y / 2, part.Position.Z)
end

local function getMarker(state: BaseState, name: string): BasePart?
	local markers = state.base:FindFirstChild("Markers")
	local marker = if markers then markers:FindFirstChild(name) else nil
	if marker and marker:IsA("BasePart") then
		return marker
	end
	return nil
end

-- Etage 2+ avec terrasse et ascenseur trouves (sinon : clients depuis le balcon, comme avant).
local function usesLift(state: BaseState): boolean
	return state.index >= 2 and state.route ~= nil
end

-- Position au sol et orientation d'une place (devant = au comptoir, attente = derriere).
local function placeOf(state: BaseState, k: number, role: Role): (Vector3?, number?)
	local spot = getMarker(state, "CustomerSpot" .. k)
	if spot == nil then
		return nil, nil
	end
	local cf = spot.CFrame
	if role == "Waiting" then
		cf = cf * CFrame.new(0, 0, Npcs.CustomerQueueGap)
	end
	local floor = Vector3.new(cf.Position.X, cf.Position.Y - spot.Size.Y / 2, cf.Position.Z)
	return floor, yawOf(spot.CFrame.LookVector)
end

-- Entree -> (chemin) -> destination, tout au sol.
local function inboundRoute(state: BaseState, dest: Vector3): { Vector3 }?
	local entry = getMarker(state, "CustomerEntry")
	if entry == nil then
		return nil
	end
	local route = { floorPos(entry) }
	local waypoint = getMarker(state, "CustomerPath")
	if waypoint then
		table.insert(route, floorPos(waypoint))
	end
	table.insert(route, dest)
	return route
end

local function flatRight(part: BasePart): Vector3
	local r = part.CFrame.RightVector
	local flat = Vector3.new(r.X, 0, r.Z)
	if flat.Magnitude < 0.001 then
		return Vector3.xAxis
	end
	return flat.Unit
end

---------------------------------------------------------------------------------------------
-- File de la terrasse et geometrie de l'ascenseur (StreamingEnabled : tout peut manquer)

local function findPath(root: Instance, names: { string }): Instance?
	local node: Instance? = root
	for _, name in names do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

local function buildRoute(state: BaseState): Route?
	local annex = state.owner:FindFirstChild("Annex")
	if annex == nil then
		return nil
	end
	local queueFolder = findPath(annex, { "Terrace", "QueuePath" })
	local entry = findPath(annex, { "ElevatorBase", "ElevatorEntry" })
	local exit = getMarker(state, "CustomerEntry")
	if queueFolder == nil or entry == nil or not entry:IsA("BasePart") or exit == nil then
		return nil
	end
	local pts: { Vector3 } = {}
	local index = 1
	while true do
		local point = queueFolder:FindFirstChild("Point" .. index)
		if point == nil or not point:IsA("BasePart") then
			break
		end
		table.insert(pts, floorPos(point))
		index += 1
	end
	if #pts < 1 then
		return nil
	end
	local entryFloor = floorPos(entry)
	table.insert(pts, entryFloor)
	local arcs: { number } = { 0 }
	for i = 2, #pts do
		arcs[i] = arcs[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	local exitFloor = floorPos(exit)
	local flat = Vector3.new(exitFloor.X - entryFloor.X, 0, exitFloor.Z - entryFloor.Z)
	if flat.Magnitude < 1 then
		return nil
	end
	local xAxis = flat.Unit
	local zAxis = xAxis:Cross(Vector3.yAxis)
	return {
		pts = pts,
		gap = math.max(QUEUE_GAP, arcs[#arcs] / QUEUE_MAX),
		arcs = arcs,
		length = arcs[#arcs],
		street = pts[1] - zAxis * QUEUE_STREET,
		entry = entryFloor,
		xAxis = xAxis,
		cage = entryFloor + xAxis * CAGE_FROM_ENTRY,
		height = exitFloor.Y - entryFloor.Y,
		exit = exitFloor,
	}
end

-- Point de la file a la distance arc (depuis Point1) et direction de la file a cet endroit.
local function pointAt(route: Route, arc: number): (Vector3, Vector3)
	local pts, arcs = route.pts, route.arcs
	for i = 2, #pts do
		if arc <= arcs[i] or i == #pts then
			local a, b = pts[i - 1], pts[i]
			local len = arcs[i] - arcs[i - 1]
			local f = if len > 0 then math.clamp((arc - arcs[i - 1]) / len, 0, 1) else 1
			local dir = b - a
			return a:Lerp(b, f), if dir.Magnitude > 0.001 then dir.Unit else route.xAxis
		end
	end
	return pts[#pts], route.xAxis
end

-- Sommets de la file strictement entre deux distances.
local function cornersBetween(route: Route, a0: number, a1: number, into: { Vector3 })
	for i, arc in route.arcs do
		if arc > a0 + 0.01 and arc < a1 - 0.01 then
			table.insert(into, route.pts[i])
		end
	end
end

-- Place i de la file (1 = tete, devant la cabine).
local function slotArc(route: Route, i: number): number
	return math.max(route.length - (i - 1) * route.gap, 0)
end

---------------------------------------------------------------------------------------------
-- Creation d'un client

local function pickTemplate(): Model?
	local folder = templateFolder
	if folder == nil then
		return nil
	end
	local list: { Model } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and string.sub(child.Name, 1, 8) == "Customer" then
			table.insert(list, child)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Distance entre HumanoidRootPart et le point le plus bas du rig (hors accessoires).
local function computeHip(template: Model, clone: Model, hrp: BasePart): number
	local cached = hipCache[template]
	if cached then
		return cached
	end
	local lowest = math.huge
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and not (d.Parent and d.Parent:IsA("Accessory")) then
			local cf = d.CFrame
			local s = d.Size
			local ext = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
				/ 2
			lowest = math.min(lowest, d.Position.Y - ext)
		end
	end
	local hip = hrp.Position.Y - lowest
	if lowest == math.huge or hip <= 0.5 or hip > 10 then
		hip = 3
	end
	hipCache[template] = hip
	return hip
end

local function loadTrack(animator: Animator, name: string, id: string): AnimationTrack?
	local anim = clipCache[name]
	if anim == nil then
		anim = Instance.new("Animation")
		anim.AnimationId = id
		clipCache[name] = anim
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or track == nil then
		return nil
	end
	local loaded = track :: AnimationTrack
	loaded.Looped = true
	return loaded
end

local function createCustomer(
	state: BaseState,
	spot: number,
	role: Role,
	stage: Stage,
	startPos: Vector3,
	startYaw: number
): Customer?
	local folder = customersFolder
	local template = pickTemplate()
	if folder == nil or template == nil then
		return nil
	end
	local model = template:Clone()
	local hrpInst = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if hrpInst == nil or not hrpInst:IsA("BasePart") or humanoid == nil then
		model:Destroy()
		return nil
	end
	local hrp: BasePart = hrpInst
	local hip = computeHip(template, model, hrp)

	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d == hrp
			table.insert(parts, d)
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	;(humanoid :: any).EvaluateStateMachine = false

	model.Name = "Customer"
	model.PrimaryPart = hrp
	model:PivotTo(CFrame.new(startPos.X, startPos.Y + hip, startPos.Z) * CFrame.Angles(0, startYaw, 0))
	model.Parent = folder

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local walkTrack = loadTrack(animator :: Animator, "Walk", Npcs.Animations.Walk)
	local idleTrack = loadTrack(animator :: Animator, "Idle", Npcs.Animations.Idle)
	if idleTrack then
		idleTrack:Play(0)
	end

	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("Torso")
	local customer: Customer = {
		home = state,
		model = model,
		hrp = hrp,
		head = if head and head:IsA("BasePart") then head else hrp,
		torso = if torso and torso:IsA("BasePart") then torso else nil,
		parts = parts,
		hip = hip,
		spot = spot,
		role = role,
		stage = stage,
		status = "Standing",
		speed = Npcs.CustomerWalkSpeed * rng:NextNumber(0.92, 1.08),
		pos = startPos,
		yaw = startYaw,
		targetYaw = startYaw,
		faceYaw = startYaw,
		path = {},
		pathIndex = 1,
		onArrive = nil,
		timer = 0,
		onTimer = nil,
		walkTrack = walkTrack,
		idleTrack = idleTrack,
		moving = false,
		dirty = false,
		sold = false,
		fading = false,
		fadeT = 0,
		fadeSeconds = FADE_SECONDS,
		queueArc = 0,
		ridePos = startPos,
		cup = nil,
		cupParts = {},
		cupStart = startPos,
		cupT = 0,
		torsoRel = CFrame.new(),
		bubble = nil,
		destroyed = false,
	}
	state.customers[customer] = true
	state.count += 1
	active[customer] = true
	return customer
end

local function removeFrom(list: { Customer }, c: Customer)
	local i = table.find(list, c)
	if i then
		table.remove(list, i)
	end
end

destroyCustomer = function(c: Customer)
	if c.destroyed then
		return
	end
	c.destroyed = true
	local state = c.home
	active[c] = nil
	if state.customers[c] then
		state.customers[c] = nil
		state.count -= 1
	end
	if state.front[c.spot] == c then
		state.front[c.spot] = nil
	end
	if state.waiting[c.spot] == c then
		state.waiting[c.spot] = nil
	end
	removeFrom(state.queue, c)
	local lift = state.lift
	if lift then
		removeFrom(lift.riders, c)
	end
	if c.cup then
		c.cup:Destroy()
		c.cup = nil
	end
	c.model:Destroy() -- detruit aussi les animations, la bulle et les pistes
	c.onArrive = nil
	c.onTimer = nil
end

-- Fondu sur place (sans marcher), puis destruction.
local function fadeAway(c: Customer, seconds: number)
	if c.destroyed then
		return
	end
	removeFrom(c.home.queue, c)
	c.status = "Leaving"
	c.path = {}
	c.pathIndex = 1
	c.onArrive = nil
	c.onTimer = nil
	if not c.fading then
		c.fading = true
		c.fadeT = 0
		c.fadeSeconds = seconds
	end
	local bubble = c.bubble
	if bubble then
		bubble.Enabled = false
	end
end

---------------------------------------------------------------------------------------------
-- Deplacements

local function walkTo(c: Customer, points: { Vector3 }, final: () -> ())
	c.path = points
	c.pathIndex = 1
	c.dirty = true
	if c.status ~= "Leaving" then
		c.status = "Walking"
	end
	c.onArrive = function()
		if not c.destroyed then
			final()
		end
	end
end

-- Points restant a parcourir sur le chemin en cours (pour le prolonger sans couper les virages).
local function remainingPath(c: Customer): { Vector3 }
	local points: { Vector3 } = {}
	for i = c.pathIndex, #c.path do
		table.insert(points, c.path[i])
	end
	return points
end

local function setMoving(c: Customer, moving: boolean)
	c.moving = moving
	local walk, idle = c.walkTrack, c.idleTrack
	if moving then
		if idle then
			idle:Stop(0.15)
		end
		if walk then
			walk:Play(0.15)
			walk:AdjustSpeed(c.speed / Npcs.WalkAnimSpeed)
		end
	else
		if walk then
			walk:Stop(0.15)
		end
		if idle then
			idle:Play(0.15)
		end
	end
end

local function arrivedAtPlace(c: Customer)
	c.status = "Standing"
	c.targetYaw = c.faceYaw
	refreshBubble(c)
end

-- Place le client directement a sa place (pas de marche).
local function snapToPlace(c: Customer)
	local pos, yaw = placeOf(c.home, c.spot, c.role)
	if pos == nil or yaw == nil then
		return
	end
	c.path = {}
	c.pathIndex = 1
	c.onArrive = nil
	c.pos = pos
	c.yaw = yaw
	c.targetYaw = yaw
	c.faceYaw = yaw
	c.status = "Standing"
	c.dirty = true
	refreshBubble(c)
end

-- Avance d'un client pour cette image. Les rappels sont ranges dans `pending` (executes apres la boucle).
local function updateCustomer(c: Customer, dt: number)
	local moving = false
	local path = c.path
	local idx = c.pathIndex
	local count = #path
	if idx <= count then
		local delta = path[idx] - c.pos
		local dist = delta.Magnitude
		local step = c.speed * dt
		if dist <= step then
			c.pos = path[idx]
			c.pathIndex = idx + 1
			if idx == count then
				local cb = c.onArrive
				c.onArrive = nil
				if cb then
					table.insert(pending, cb)
				end
			else
				moving = true
			end
		else
			c.pos += delta * (step / dist)
			if delta.X * delta.X + delta.Z * delta.Z > 0.0001 then
				c.targetYaw = yawOf(delta)
			end
			moving = true
		end
	end
	if moving ~= c.moving then
		setMoving(c, moving)
	end

	local diff = (c.targetYaw - c.yaw + math.pi) % (2 * math.pi) - math.pi
	local turning = math.abs(diff) > 0.002
	if turning then
		c.yaw += diff * math.min(1, dt * 12)
	end
	local hrp = c.hrp
	if moving or turning or c.dirty then
		c.dirty = false
		hrp.CFrame = CFrame.new(c.pos.X, c.pos.Y + c.hip, c.pos.Z) * CFrame.Angles(0, c.yaw, 0)
	end

	local cup = c.cup
	if cup then
		local hands = hrp.CFrame * c.torsoRel * HAND_OFFSET
		if c.cupT < CUP_FLY_SECONDS then
			c.cupT += dt
			local a = math.min(c.cupT / CUP_FLY_SECONDS, 1)
			local p = c.cupStart:Lerp(hands.Position, a) + Vector3.yAxis * (math.sin(a * math.pi) * 0.8)
			cup:PivotTo(CFrame.new(p) * hands.Rotation)
		else
			cup:PivotTo(hands)
		end
	end

	if c.onTimer then
		c.timer -= dt
		if c.timer <= 0 then
			local cb = c.onTimer
			c.onTimer = nil
			if cb then
				table.insert(pending, cb)
			end
		end
	end

	if c.fading then
		c.fadeT += dt / c.fadeSeconds
		local a = math.min(c.fadeT, 1)
		for _, p in c.parts do
			p.LocalTransparencyModifier = a
		end
		for _, p in c.cupParts do
			p.LocalTransparencyModifier = a
		end
		if a >= 1 then
			c.fading = false
			table.insert(pending, function()
				destroyCustomer(c)
			end)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Depart

startLeaving = function(c: Customer)
	if c.destroyed or c.status == "Leaving" then
		return
	end
	local state = c.home
	if state.front[c.spot] == c then
		state.front[c.spot] = nil
	end
	if state.waiting[c.spot] == c then
		state.waiting[c.spot] = nil
	end
	-- Etage 2+ : pas encore sur le balcon (file, cabine) -> fondu sur place
	if state.index >= 2 and c.stage ~= "Balcony" then
		fadeAway(c, FADE_SECONDS)
		return
	end
	c.status = "Leaving"
	refreshBubble(c)
	local entry = getMarker(state, "CustomerEntry")
	if entry == nil then
		destroyCustomer(c)
		return
	end
	local sign = if rng:NextInteger(0, 1) == 0 then -1 else 1
	local points: { Vector3 } = {}
	-- Petit pas de cote pour ne pas croiser de face le client qui avance au comptoir
	local spot = getMarker(state, "CustomerSpot" .. c.spot)
	if spot and c.role == "Front" and (c.pos - floorPos(spot)).Magnitude < 1.5 then
		table.insert(points, floorPos(spot) + flatRight(spot) * (SIDESTEP * sign))
	end
	local entryFloor = floorPos(entry)
	if state.index >= 2 then
		-- Balcon : retour vers la sortie de l'ascenseur, fondu la-bas
		table.insert(points, entryFloor)
	else
		local waypoint = getMarker(state, "CustomerPath")
		if waypoint then
			table.insert(points, floorPos(waypoint))
		end
		table.insert(points, entryFloor)
		table.insert(points, entryFloor + flatRight(entry) * (EXIT_DISTANCE * sign))
	end
	walkTo(c, points, function()
		c.fading = true
	end)
end

---------------------------------------------------------------------------------------------
-- Bulle d'attente

local function createBubble(c: Customer): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "WaitBubble"
	gui.Size = UDim2.fromScale(2.2, 1.4)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Enabled = false
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.85, 0.6)
	label.BackgroundTransparency = 1
	label.Text = "Juice?"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(40, 40, 50)
	label.FontFace = PackStyle.FONT
	label.Parent = frame
	frame.Parent = gui
	gui.Parent = c.head
	return gui
end

refreshBubble = function(c: Customer)
	if c.destroyed then
		return
	end
	local state = c.home
	local juices = state.base:GetAttribute("CounterJuices")
	local show = c.role == "Front"
		and c.status == "Standing"
		and not c.sold
		and state.front[c.spot] == c
		and juices == 0
	if show then
		local bubble = c.bubble
		if bubble == nil then
			bubble = createBubble(c)
			c.bubble = bubble
		end
		bubble.Enabled = true
	elseif c.bubble then
		c.bubble.Enabled = false
	end
end

local function refreshBubbles(state: BaseState)
	for k = 1, MAX_SPOTS do
		local c = state.front[k]
		if c then
			refreshBubble(c)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Apparition des clients

local function canSpawn(state: BaseState, instant: boolean): boolean
	local cap = 2 * state.slots + 6 + (if usesLift(state) then QUEUE_MAX else 0)
	if state.count >= cap then
		return false
	end
	if not instant and os.clock() - state.lastSpawn < SPAWN_GAP_SECONDS then
		return false
	end
	return templateFolder ~= nil
end

-- Cree un client a sa place (instant) ou a l'entree, en marche vers sa place.
local function spawnFor(state: BaseState, k: number, role: Role, instant: boolean): Customer?
	local pos, yaw = placeOf(state, k, role)
	if pos == nil or yaw == nil then
		return nil
	end
	local stage: Stage = if state.index >= 2 then "Balcony" else "Street"
	local c: Customer?
	if instant then
		c = createCustomer(state, k, role, stage, pos, yaw)
		if c then
			c.dirty = true
		end
	else
		local route = inboundRoute(state, pos)
		if route == nil then
			return nil
		end
		local second = route[2] or pos
		local start = route[1]
		c = createCustomer(state, k, role, stage, start, yawOf(second - start))
		if c then
			state.lastSpawn = os.clock()
			c.faceYaw = yaw
			local customer = c
			walkTo(customer, route, function()
				arrivedAtPlace(customer)
			end)
		end
	end
	if c == nil then
		return nil
	end
	c.faceYaw = yaw
	if role == "Front" then
		state.front[k] = c
	else
		state.waiting[k] = c
	end
	if instant then
		arrivedAtPlace(c)
	end
	return c
end

fill = function(state: BaseState, k: number, instant: boolean)
	if k > state.slots then
		return
	end
	local lifted = usesLift(state)
	if state.front[k] == nil then
		local waiter = state.waiting[k]
		if waiter then
			-- Le client qui attend avance au comptoir (encore dans l'ascenseur : il ira directement
			-- au comptoir en sortant, voir unload)
			state.waiting[k] = nil
			state.front[k] = waiter
			waiter.role = "Front"
			local pos, yaw = placeOf(state, k, "Front")
			if pos and yaw then
				waiter.faceYaw = yaw
				if waiter.stage == "Balcony" or waiter.stage == "Street" then
					walkTo(waiter, { pos }, function()
						arrivedAtPlace(waiter)
					end)
				end
			end
		elseif (instant or not lifted) and canSpawn(state, instant) then
			spawnFor(state, k, "Front", instant)
		end
	end
	if state.waiting[k] == nil and state.front[k] ~= nil and (instant or not lifted) and canSpawn(state, instant) then
		spawnFor(state, k, "Waiting", instant)
	end
end

-- Etages 2+ : la file de la terrasse se remplit (clients venus de la rue, ou places d'emblee).
local function fillQueue(state: BaseState, instant: boolean)
	local route = state.route
	if route == nil or state.slots <= 0 then
		return
	end
	local target = math.min(QUEUE_MAX, QUEUE_BASE + QUEUE_PER_SLOT * state.slots)
	while #state.queue < target and canSpawn(state, instant) do
		local i = #state.queue + 1
		local arc = slotArc(route, i)
		local pos, dir = pointAt(route, arc)
		local c: Customer?
		if instant then
			c = createCustomer(state, 0, "Waiting", "Queue", pos, yawOf(dir))
			if c then
				c.dirty = true
			end
		else
			local start = route.street
			c = createCustomer(state, 0, "Waiting", "Queue", start, yawOf(route.pts[1] - start))
			if c then
				state.lastSpawn = os.clock()
				local points: { Vector3 } = { route.pts[1] }
				cornersBetween(route, 0, arc, points)
				table.insert(points, pos)
				local customer = c
				walkTo(customer, points, function()
					customer.status = "Standing"
				end)
			end
		end
		if c == nil then
			return
		end
		c.queueArc = arc
		table.insert(state.queue, c)
		if not instant then
			return -- un seul a la fois (SPAWN_GAP_SECONDS)
		end
	end
end

-- Les clients de la file avancent vers leur nouvelle place.
local function advanceQueue(state: BaseState)
	local route = state.route
	if route == nil then
		return
	end
	for i, c in state.queue do
		local arc = slotArc(route, i)
		if arc > c.queueArc + 0.01 then
			local points = remainingPath(c)
			cornersBetween(route, c.queueArc, arc, points)
			table.insert(points, (pointAt(route, arc)))
			c.queueArc = arc
			local customer = c
			walkTo(customer, points, function()
				customer.status = "Standing"
			end)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Ascenseur (etages 2+, anime en local)

local function liftCapacity(state: BaseState): number
	local level = state.owner:GetAttribute("ElevatorCabin")
	local n = if type(level) == "number" then math.max(level, 0) else 0
	return math.min(LIFT_CAPACITY_BASE + math.floor(n / LIFT_CAPACITY_STEP), #CABIN_SPOTS)
end

local function rideSeconds(state: BaseState): number
	local level = state.owner:GetAttribute("ElevatorSpeed")
	local n = if type(level) == "number" then math.max(level, 0) else 0
	local base = LIFT_BASE_SECONDS + LIFT_PER_FLOOR_SECONDS * math.max(state.index - 2, 0)
	return base / (1 + LIFT_SPEED_BONUS * n)
end

-- Cabine simple (si la carte n'a pas encore Annex.ElevatorBase.Cabin) : plancher, toit, 4 poteaux.
local function makeFallbackCabin(route: Route): Model?
	local folder = customersFolder
	if folder == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "LocalCabin"
	local frame = CFrame.lookAlong(route.cage + Vector3.new(0, CABIN_FLOOR_RISE, 0), route.xAxis)
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3, transparency: number): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = color
		p.Transparency = transparency
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = frame * CFrame.new(offset)
		p.Parent = model
		return p
	end
	local trim = Color3.fromRGB(70, 74, 86)
	local floor = piece("CabinFloor", Vector3.new(7.2, 0.4, 7.2), Vector3.new(0, -0.2, 0), trim, 0)
	piece("CabinRoof", Vector3.new(7.2, 0.3, 7.2), Vector3.new(0, 8.6, 0), trim, 0)
	for _, c in { Vector2.new(-3.4, -3.4), Vector2.new(3.4, -3.4), Vector2.new(-3.4, 3.4), Vector2.new(3.4, 3.4) } do
		piece("CabinPost", Vector3.new(0.3, 8.6, 0.3), Vector3.new(c.X, 4.3, c.Y), trim, 0)
	end
	-- Cote local Z : vitres (cote terrasse et balcon ouverts)
	for _, x in { -3.5, 3.5 } do
		piece("CabinGlass", Vector3.new(0.15, 8.4, 6.8), Vector3.new(x, 4.3, 0), Color3.fromRGB(190, 225, 255), 0.75)
	end
	model.PrimaryPart = floor
	model.Parent = folder
	return model
end

local function releaseLift(state: BaseState)
	local lift = state.lift
	liftStates[state] = nil
	if lift == nil then
		return
	end
	state.lift = nil
	if cabinOwner[state.owner] == state then
		cabinOwner[state.owner] = nil
		local cabin, rest = lift.cabin, lift.rest
		if cabin and rest and cabin.Parent then
			cabin:PivotTo(rest)
		end
	end
	local fallback = lift.fallback
	if fallback then
		fallback:Destroy()
		lift.fallback = nil
	end
	table.clear(lift.riders)
end

-- Choisit la cabine pour le prochain voyage (la vraie si elle est la). Faux si rien d'utilisable.
local function acquireCabin(state: BaseState, lift: Lift, route: Route): boolean
	local real = findPath(state.owner, { "Annex", "ElevatorBase", "Cabin" })
	if real and real:IsA("Model") then
		local rest = cabinRest[real]
		if rest == nil then
			local floor = real.PrimaryPart or real:FindFirstChild("CabinFloor")
			local top = route.cage + Vector3.new(0, CABIN_FLOOR_RISE, 0)
			if floor and floor:IsA("BasePart") then
				top = Vector3.new(floor.Position.X, floor.Position.Y + floor.Size.Y / 2, floor.Position.Z)
			end
			rest = { pivot = real:GetPivot(), top = top }
			cabinRest[real] = rest
		end
		local oldFallback = lift.fallback
		if oldFallback then
			oldFallback:Destroy()
			lift.fallback = nil
		end
		local info = rest :: { pivot: CFrame, top: Vector3 }
		lift.cabin = real
		lift.rest = info.pivot
		lift.floorTop = info.top
	else
		local fallback = lift.fallback
		if fallback == nil or fallback.Parent == nil then
			fallback = makeFallbackCabin(route)
			lift.fallback = fallback
		end
		if fallback == nil then
			return false
		end
		lift.cabin = fallback
		lift.rest = CFrame.lookAlong(route.cage + Vector3.new(0, CABIN_FLOOR_RISE, 0), route.xAxis)
			* CFrame.new(0, -0.2, 0)
		lift.floorTop = route.cage + Vector3.new(0, CABIN_FLOOR_RISE, 0)
	end
	cabinOwner[state.owner] = state
	return true
end

local function setLiftOffset(lift: Lift, offset: number)
	lift.offset = offset
	local cabin, rest = lift.cabin, lift.rest
	if cabin and rest and cabin.Parent then
		cabin:PivotTo(rest + Vector3.new(0, offset, 0))
	end
	for _, c in lift.riders do
		if c.stage == "Ride" and not c.destroyed then
			c.pos = c.ridePos + Vector3.new(0, offset, 0)
			c.dirty = true
		end
	end
end

-- Places libres de l'etage (le comptoir d'abord), pour les clients qui vont embarquer.
local function freePlaces(state: BaseState, n: number): { { k: number, role: Role } }
	local list: { { k: number, role: Role } } = {}
	for k = 1, state.slots do
		if #list >= n then
			return list
		end
		if state.front[k] == nil and state.waiting[k] == nil then
			table.insert(list, { k = k, role = "Front" })
		end
	end
	for k = 1, state.slots do
		if #list >= n then
			return list
		end
		if state.waiting[k] == nil then
			table.insert(list, { k = k, role = "Waiting" })
		end
	end
	return list
end

local function startBoarding(state: BaseState, lift: Lift, route: Route): boolean
	local cap = math.min(liftCapacity(state), #state.queue)
	if cap <= 0 then
		return false
	end
	local places = freePlaces(state, cap)
	if #places == 0 or not acquireCabin(state, lift, route) then
		return false
	end
	local frame = CFrame.lookAlong(lift.floorTop, route.xAxis)
	local door = route.entry + route.xAxis * (CAGE_FROM_ENTRY - CAGE_DOOR)
	for i, place in places do
		local c = table.remove(state.queue, 1)
		if c == nil then
			break
		end
		-- Reservation de la place (destination calculee a la sortie de la cabine)
		c.spot = place.k
		c.role = place.role
		if place.role == "Front" then
			state.front[place.k] = c
		else
			state.waiting[place.k] = c
		end
		local local2 = CABIN_SPOTS[i]
		-- lookAlong : -Z local = xAxis (vers la sortie) ; local2.X = vers la sortie
		c.ridePos = (frame * CFrame.new(local2.Y, 0, -local2.X)).Position
		c.stage = "Board"
		table.insert(lift.riders, c)
		local points = remainingPath(c)
		cornersBetween(route, c.queueArc, route.length, points)
		table.insert(points, route.entry)
		table.insert(points, door)
		table.insert(points, c.ridePos)
		c.queueArc = route.length
		local customer = c
		walkTo(customer, points, function()
			customer.stage = "Ride"
			customer.status = "Standing"
			customer.targetYaw = yawOf(route.xAxis)
		end)
	end
	advanceQueue(state)
	lift.phase = "Boarding"
	lift.timer = LIFT_BOARD_TIMEOUT
	return true
end

local function moveLift(lift: Lift, phase: LiftPhase, to: number, duration: number)
	lift.phase = phase
	lift.from = lift.offset
	lift.to = to
	lift.t = 0
	lift.duration = math.max(duration, 0.1)
end

local function unload(state: BaseState, lift: Lift, route: Route)
	local doorTop = route.entry + route.xAxis * (CAGE_FROM_ENTRY + CAGE_DOOR) + Vector3.new(0, route.height, 0)
	for _, c in lift.riders do
		if not c.destroyed and c.status ~= "Leaving" then
			c.stage = "Balcony"
			local pos, yaw = placeOf(state, c.spot, c.role)
			if pos == nil or yaw == nil then
				startLeaving(c)
			else
				c.faceYaw = yaw
				local customer = c
				walkTo(customer, { doorTop, route.exit, pos }, function()
					arrivedAtPlace(customer)
				end)
			end
		end
	end
	table.clear(lift.riders)
end

local function updateLift(state: BaseState, lift: Lift, dt: number)
	local route = state.route
	if route == nil then
		return
	end
	-- Clients partis (vente annulee, places en moins) : retires de la cabine
	for i = #lift.riders, 1, -1 do
		local c = lift.riders[i]
		if c.destroyed or c.status == "Leaving" then
			table.remove(lift.riders, i)
		end
	end
	local phase = lift.phase
	if phase == "Idle" then
		startBoarding(state, lift, route)
	elseif phase == "Boarding" then
		lift.timer -= dt
		local ready = true
		for _, c in lift.riders do
			if c.stage ~= "Ride" then
				ready = false
				break
			end
		end
		if #lift.riders == 0 then
			lift.phase = "Idle"
		elseif ready or lift.timer <= 0 then
			for i = #lift.riders, 1, -1 do
				local c = lift.riders[i]
				if c.stage ~= "Ride" then
					startLeaving(c) -- retardataire : fondu, sa place se liberera
					table.remove(lift.riders, i)
				end
			end
			lift.phase = "Closing"
			lift.timer = LIFT_DOOR_SECONDS
		end
	elseif phase == "Closing" then
		lift.timer -= dt
		if lift.timer <= 0 then
			moveLift(lift, "Up", route.height, rideSeconds(state))
		end
	elseif phase == "Up" or phase == "Down" then
		lift.t += dt
		local a = math.min(lift.t / lift.duration, 1)
		local eased = TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		setLiftOffset(lift, lift.from + (lift.to - lift.from) * eased)
		if a >= 1 then
			if phase == "Up" then
				unload(state, lift, route)
				lift.phase = "Unloading"
				lift.timer = LIFT_UNLOAD_SECONDS
			else
				lift.phase = "Idle"
			end
		end
	elseif phase == "Unloading" then
		lift.timer -= dt
		if lift.timer <= 0 then
			moveLift(lift, "Down", 0, rideSeconds(state) * LIFT_DOWN_FACTOR)
		end
	end
end

local function onStep(dt: number)
	for state in liftStates do
		local lift = state.lift
		if lift and state.rendered then
			updateLift(state, lift, dt)
		end
	end
	for c in active do
		updateCustomer(c, dt)
	end
	if #pending > 0 then
		local list = table.clone(pending)
		table.clear(pending)
		for _, cb in list do
			cb()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Vente

local function nearestCounterPoint(state: BaseState, from: Vector3): Vector3
	local counter = state.base:FindFirstChild("Counter")
	local top = if counter then counter:FindFirstChild("CounterTopArea", true) else nil
	if top and top:IsA("BasePart") then
		local lp = top.CFrame:PointToObjectSpace(from)
		local half = top.Size / 2
		local clamped = Vector3.new(math.clamp(lp.X, -half.X, half.X), half.Y, math.clamp(lp.Z, -half.Z, half.Z))
		return top.CFrame:PointToWorldSpace(clamped)
	end
	return from + Vector3.new(0, 1, 0)
end

local function floatText(position: Vector3, amount: number)
	local folder = customersFolder
	if folder == nil then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "SaleText"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.MaxDistance = 100
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "+$" .. NumberFormat.Abbreviate(amount)
	label.TextScaled = true
	label.TextColor3 = SALE_COLOR
	label.FontFace = PackStyle.FONT
	local saleStroke = Instance.new("UIStroke")
	saleStroke.Color = PackStyle.TEXT_STROKE
	saleStroke.Thickness = 2.5
	saleStroke.LineJoinMode = Enum.LineJoinMode.Round
	saleStroke.Parent = label
	label.Parent = gui
	gui.Parent = holder
	holder.Parent = folder
	TweenService:Create(gui, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 2.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4), {
		TextTransparency = 1,
	}):Play()
	TweenService:Create(saleStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4), {
		Transparency = 1,
	}):Play()
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

local function serve(c: Customer, fruitId: string, amount: number)
	local state = c.home
	c.sold = true
	refreshBubble(c)

	local folder = customersFolder
	local ok, cupModel = pcall(FruitModels.CreateCup, fruitId, true)
	if ok and cupModel and folder then
		local cup = cupModel :: Model
		for _, d in cup:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(c.cupParts, d)
			end
		end
		c.cup = cup
		c.cupStart = nearestCounterPoint(state, c.hrp.Position)
		c.cupT = 0
		if c.torso then
			c.torsoRel = c.hrp.CFrame:ToObjectSpace(c.torso.CFrame)
		end
		cup:PivotTo(CFrame.new(c.cupStart))
		cup.Parent = folder
	end
	c.model:SetAttribute("CarryPose", true)
	CollectionService:AddTag(c.model, "CarryPoseRig")
	floatText(c.hrp.Position + Vector3.new(0, 3, 0), amount)
	SoundFx.PlayAt("Sale", c.hrp.Position)

	c.timer = LEAVE_DELAY_SECONDS
	c.onTimer = function()
		startLeaving(c)
	end
end

local function onSale(state: BaseState, k: number, fruitId: string, amount: number)
	if not state.rendered then
		return
	end
	local c: Customer? = state.front[k]
	if state.index >= 2 then
		-- Etage 2+ : pas de teleportation depuis la file ou la cabine ; vente sans client = "+$" seul
		if c == nil or c.stage ~= "Balcony" or c.status ~= "Standing" then
			local pos = placeOf(state, k, "Front")
			if pos then
				floatText(pos + Vector3.new(0, 5, 0), amount)
				SoundFx.PlayAt("Sale", pos)
			end
			return
		end
	elseif c == nil then
		-- Pas de client pret : on en place un directement au comptoir
		c = spawnFor(state, k, "Front", true)
	elseif c.status ~= "Standing" then
		snapToPlace(c)
	end
	if c == nil then
		return
	end
	state.front[k] = nil
	serve(c, fruitId, amount)
	fill(state, k, false)
end

-- 1er argument = l'etage (Model Bases.BaseN.Floors.FloorK)
local function handleWorldFx(floor: any, kind: any, payload: any)
	if kind ~= "Sale" then
		return
	end
	if typeof(floor) ~= "Instance" or not floor:IsA("Model") then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local spot, fruit, amount = payload.spot, payload.fruit, payload.amount
	if type(spot) ~= "number" or spot % 1 ~= 0 or spot < 1 or spot > MAX_SPOTS then
		return
	end
	if type(fruit) ~= "string" or Fruits.ById[fruit] == nil then
		return
	end
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount < 0 then
		return
	end
	local state = states[floor]
	if state then
		onSale(state, spot, fruit, amount)
	end
end

---------------------------------------------------------------------------------------------
-- Etages : affichage selon proprietaire (de la base), etage actif et distance

-- Retire les clients de l'etage : fondu rapide (fadeSeconds) ou destruction immediate (nil).
local function clearBase(state: BaseState, fadeSeconds: number?)
	releaseLift(state)
	for c in state.customers do
		if fadeSeconds then
			fadeAway(c, fadeSeconds)
		else
			destroyCustomer(c)
		end
	end
	table.clear(state.front)
	table.clear(state.waiting)
	table.clear(state.queue)
	state.route = nil
	state.rendered = false
end

local function isNear(state: BaseState): boolean
	local camera = workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local entry = getMarker(state, "CustomerEntry")
	local position = if entry then entry.Position else state.base:GetPivot().Position
	return (camera.CFrame.Position - position).Magnitude <= Npcs.CustomerRenderDistance
end

-- Etage dessine pour la base : celui du proprietaire (ActiveFloor), 1 par defaut.
local function activeIndex(state: BaseState): number
	local value = state.owner:GetAttribute("ActiveFloor")
	if type(value) == "number" and value >= 1 then
		return math.floor(value)
	end
	return 1
end

local function evaluate(state: BaseState)
	local owner = state.owner:GetAttribute("OwnerUserId")
	local ownerId = if type(owner) == "number" then owner else 0
	if ownerId ~= state.ownerId then
		clearBase(state, nil)
		state.ownerId = ownerId
	end
	state.index = FloorWatch.IndexOf(state.base)
	local slotsAttr = state.base:GetAttribute("CustomerSlots")
	state.slots = if type(slotsAttr) == "number" then math.clamp(math.floor(slotsAttr), 0, MAX_SPOTS) else 0

	local onActive = activeIndex(state) == state.index
	local want = ownerId ~= 0 and onActive and isNear(state)
	if not want then
		if state.rendered then
			-- Changement d'etage du proprietaire : fondu rapide ; sinon (loin, base libre) : retrait direct
			clearBase(state, if ownerId ~= 0 and not onActive then SWITCH_FADE_SECONDS else nil)
		end
		return
	end
	if not state.rendered then
		state.rendered = true
		state.instantUntil = os.clock() + INSTANT_WINDOW_SECONDS
	end
	-- Etages 2+ : terrasse + ascenseur (essaye a chaque passage tant que la carte n'est pas recue)
	if state.index >= 2 and state.route == nil then
		state.route = buildRoute(state)
	end
	if usesLift(state) and state.lift == nil then
		state.lift = {
			phase = "Idle",
			offset = 0,
			from = 0,
			to = 0,
			t = 0,
			duration = 1,
			timer = 0,
			riders = {},
			cabin = nil,
			rest = nil,
			fallback = nil,
			floorTop = Vector3.zero,
		}
		liftStates[state] = true
	end
	-- Emplacements en trop : les clients repartent
	for k = state.slots + 1, MAX_SPOTS do
		local front, waiting = state.front[k], state.waiting[k]
		if front then
			startLeaving(front)
		end
		if waiting then
			startLeaving(waiting)
		end
	end
	local instant = os.clock() < state.instantUntil
	for k = 1, state.slots do
		fill(state, k, instant)
	end
	if usesLift(state) then
		fillQueue(state, instant)
	end
	refreshBubbles(state)
end

local function newState(floor: Model, base: Model): BaseState
	local state: BaseState = {
		base = floor,
		owner = base,
		index = FloorWatch.IndexOf(floor),
		ownerId = 0,
		rendered = false,
		slots = 0,
		instantUntil = 0,
		lastSpawn = 0,
		count = 0,
		front = {},
		waiting = {},
		customers = {},
		queue = {},
		route = nil,
		lift = nil,
		conns = {},
	}
	local function reevaluate()
		evaluate(state)
	end
	table.insert(state.conns, base:GetAttributeChangedSignal("OwnerUserId"):Connect(reevaluate))
	table.insert(state.conns, base:GetAttributeChangedSignal("ActiveFloor"):Connect(reevaluate))
	table.insert(state.conns, floor:GetAttributeChangedSignal("CustomerSlots"):Connect(reevaluate))
	table.insert(
		state.conns,
		floor:GetAttributeChangedSignal("CounterJuices"):Connect(function()
			refreshBubbles(state)
		end)
	)
	return state
end

local function dropState(floor: Model, state: BaseState)
	clearBase(state, nil)
	for _, conn in state.conns do
		conn:Disconnect()
	end
	table.clear(state.conns)
	if states[floor] == state then
		states[floor] = nil
	end
end

-- Nouvel etage ouvert : un etat ; detruit (achat de l'etage suivant, depart) : clients retires.
local function addFloor(floor: Model, base: Model)
	if states[floor] ~= nil or floor.Parent == nil then
		return
	end
	local state = newState(floor, base)
	states[floor] = state
	FloorWatch.OnRemoved(floor, function()
		dropState(floor, state)
	end)
end

local function pollFloors()
	for floor, state in states do
		if not floor:IsDescendantOf(workspace) then
			dropState(floor, state)
		else
			evaluate(state)
		end
	end
end

---------------------------------------------------------------------------------------------

function CustomerController.Init() end

function CustomerController.Start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "Customers"
	folder.Parent = workspace
	customersFolder = folder

	stepConn = RunService.RenderStepped:Connect(onStep)

	-- Les modeles de clients arrivent quelques secondes apres le demarrage du serveur
	task.spawn(function()
		local templates = ReplicatedStorage:WaitForChild(Npcs.TemplateFolder, 60)
		if templates and templates:IsA("Folder") then
			templateFolder = templates
		else
			warn("[CustomerController] Modeles de clients introuvables : pas de clients.")
		end
	end)

	task.spawn(function()
		local event = Remotes.WaitClientEvent("WorldFx") :: RemoteEvent?
		if event then
			saleConn = event.OnClientEvent:Connect(handleWorldFx)
		end
	end)

	FloorWatch.Watch(addFloor)
	task.spawn(function()
		while true do
			pollFloors()
			task.wait(POLL_SECONDS)
		end
	end)

	-- Le joueur local part : on range tout (Players est garde pour une extension eventuelle)
	Players.PlayerRemoving:Connect(function(leaving: Player)
		if leaving == Players.LocalPlayer then
			if stepConn then
				stepConn:Disconnect()
			end
			if saleConn then
				saleConn:Disconnect()
			end
		end
	end)
end

return CustomerController
