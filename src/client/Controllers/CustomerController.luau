--!strict
-- Clients de la buvette, dessines cote client seulement (le serveur decide de chaque vente).
-- Pour chaque base avec proprietaire et proche de la camera, SEULEMENT l'etage ou se trouve le
-- proprietaire (attribut de base ActiveFloor, 1 si absent).
-- Rez-de-chaussee (2026-11-27, demande : "vraies queues plus naturelles") : une vraie file par
-- place du comptoir (Npcs.CustomerLineLength clients, ecarts et decalages au hasard). Les clients
-- apparaissent en fondu loin sur le trottoir (Npcs.CustomerSpawnFar), marchent jusqu'au bout de
-- leur file ; la file avance client par client (effet accordeon), les clients qui attendent
-- regardent autour d'eux. Sur "Sale", le premier prend un gobelet ("+$", bulle contente), longe
-- le comptoir jusqu'au bord des files, repart dans l'herbe le long de la rue et disparait en
-- fondu au loin (Npcs.CustomerLeaveFar).
-- Etages 2+ : file en serpentin dans la terrasse (Annex.Terrace.QueuePath.Point1..N), clients venus
-- de loin par le trottoir -> cabine de l'ascenseur (animee en local) -> balcon (place, achat) ->
-- attente a cote de la porte de l'ascenseur -> descente dans la cabine -> depart dans la rue et
-- fondu au loin.
-- Bulles rondes avec un emoji au-dessus des clients qui attendent (Fx/EmojiBubble) ; au comptoir
-- vide : "🥤" avec une pastille "?".
-- Vente sans client pret au comptoir : elle attend le client qui arrive (PENDING_MAX par place),
-- sinon "+$" et son seuls (jamais de teleportation).
-- Deplacement sans physique : HumanoidRootPart ancre, deplace a la main a chaque image (Heartbeat).
-- Etats d'un client : Walking -> Standing (arrive) ; -> Leaving -> fondu -> detruit.
-- Ascenseur : une "Lift" par etage dessine ; la cabine (Annex.ElevatorBase.Cabin si elle existe,
-- sinon une cabine simple creee ici) est deplacee EN LOCAL (pieces ancrees, rien n'est envoye au
-- serveur). Les places (front / waiting) des etages 2+ sont reservees a l'embarquement.
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
local EmojiBubble = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("EmojiBubble")) :: any
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits")) :: any
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))
local R15Walk = require(Shared:WaitForChild("Util"):WaitForChild("R15Walk"))

local MAX_SPOTS = 5
local POLL_SECONDS = 0.5
local SPAWN_GAP_SECONDS = 1.5 -- etages 2+ sans terrasse : delai entre deux arrivees au balcon
local INSTANT_WINDOW_SECONDS = 2 -- apres l'affichage d'une base : clients places directement
local INSTANT_FADE_SECONDS = 0.35 -- clients places d'emblee : petit fondu (pas d'apparition seche)
local CUP_FLY_SECONDS = 0.25
local LEAVE_DELAY_SECONDS = 0.4
local FADE_SECONDS = 0.4
local SWITCH_FADE_SECONDS = 0.25 -- fondu des clients de l'ancien etage quand ActiveFloor change
local SIDESTEP = 3
local HAND_OFFSET = CFrame.new(0, -0.3, -1.3)
local SALE_COLOR = PackStyle.MONEY_GREEN
local TURN_RATE = 12
local SERVE_PAUSE = 0.15 -- vente en attente : le client arrive au comptoir puis prend son gobelet
local PENDING_MAX = 2 -- ventes en attente par place (client pas encore au comptoir)
-- Clients qui attendent : coups d'oeil autour d'eux
local FIDGET_EVERY = { 3, 9 }
local FIDGET_SECONDS = { 1, 2.6 }
local FIDGET_ANGLE = 0.75 -- radians au plus
local FIDGET_TURN_RATE = 3.5
-- Sons contents (Config/Sounds : CustomerHappy, CustomerSip)
local HAPPY_SOUND_GAP = 0.1 -- ding au plus toutes les 0.1 s par etage
local HAPPY_COMBO_SECONDS = 1.5 -- ventes rapprochees : le ding monte d'une note
local HAPPY_COMBO_STEP = 0.05 -- +5 % de hauteur par vente enchainee
local HAPPY_COMBO_MAX = 8
local SIP_DELAY = 0.55 -- le slurp arrive apres le ding (gobelet dans les mains)
local SIP_SOUND_GAP = 0.3
local HAPPY_MIN_WAIT = 1 -- jus qui arrivent : bulle contente si le client attendait depuis 1 s

-- Rue : voies paralleles a la route, mesurees depuis CustomerEntry du rez-de-chaussee (trottoir) :
-- + vers la route, - vers les bases. Les lampadaires sont cote bases du trottoir.
local LANE_IN = { 1.1, 1.5 } -- arrivees : sur le trottoir, cote route
local LANE_OUT = { -6, -5 } -- departs : dans l'herbe entre le trottoir et les bases
local LAMP_CLEARANCE = 3.2 -- on traverse le trottoir a au moins 3.2 studs d'un lampadaire
local ROAD_END_MARGIN = 15 -- aucun point a moins de 15 studs du bout de la route
-- Files du rez-de-chaussee
local LINE_EDGE = 4.5 -- les clients servis sortent a 4.5 studs de la premiere / derniere file
local COUNTER_LANE = 2.1 -- ... en passant entre le comptoir et le premier rang
local LINE_TAIL_CLEARANCE = 4.5 -- le bout de la file reste a 4.5 studs de la voie des departs
local LINE_STEP_SPEED = 0.55 -- avancer dans la file : plus lentement (fraction de la vitesse)
local ACCORDION = { 0.12, 0.22 } -- delai entre deux clients qui avancent (secondes)
local YAW_JITTER = 0.22 -- radians : les clients d'une file ne regardent pas tous droit devant
-- Files en eventail : chaque file s'ouvre de 6 degres de plus vers l'exterieur (places a 5 studs
-- seulement : droites, 5 files collees faisaient une masse)
local LINE_FAN = math.rad(6)

-- Ascenseur des clients (etages 2+). A VALIDER en jeu.
local LIFT_BASE_SECONDS = 3 -- montee jusqu'a l'etage 2 (niveau ElevatorSpeed 0)
local LIFT_PER_FLOOR_SECONDS = 0.6 -- + par etage au-dessus du 2
local LIFT_SPEED_BONUS = 0.04 -- duree = (base + par etage) / (1 + 0.04 * ElevatorSpeed)
local LIFT_DOWN_FACTOR = 0.6 -- la descente va plus vite
local LIFT_CAPACITY_BASE = 2 -- clients par voyage = 2 + floor(ElevatorCabin / 5)
local LIFT_CAPACITY_STEP = 5
local LIFT_DOOR_SECONDS = 0.6 -- pause portes avant de partir
local LIFT_UNLOAD_SECONDS = 1.2 -- les clients sortent avant que la cabine reparte
local LIFT_BOARD_TIMEOUT = 15 -- embarquement trop long : la cabine part sans les retardataires
local LIFT_TOP_TIMEOUT = 8 -- embarquement en haut (clients qui repartent)
local LEAVERS_MAX = 12 -- clients qui attendent la cabine en haut ; au-dela : fondu a la porte
local LEAVER_WAIT_SIDE = { 4.0, 4.6 } -- en haut, ils attendent a cote de la porte (studs de cote)
-- File de la terrasse : vraie file (ecarts Npcs.CustomerLineGap), sa longueur grandit avec le
-- nombre de places (QUEUE_BASE + QUEUE_PER_SLOT par place, QUEUE_MAX au plus).
local QUEUE_MAX = 40 -- clients max dans la file de la terrasse
local QUEUE_BASE = 10
local QUEUE_PER_SLOT = 6
local QUEUE_STREET = 7 -- point d'entree de la terrasse (studs devant Point1, cote rue)
local QUEUE_HEAD_BACK = 3.5 -- le premier attend a 3.5 studs de la porte (place pour ceux qui sortent)
-- Ascenseur : la cage est 6 studs apres ElevatorEntry (vers le balcon), 8 x 8, porte a 4 du centre
local CAGE_FROM_ENTRY = 6
local CAGE_DOOR = 4.5
local CABIN_FLOOR_RISE = 0.2 -- dessus du plancher de la cabine au-dessus du fond de la cage
local CABIN_SPOTS = { -- places dans la cabine (x vers le balcon, z), le fond d'abord
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
-- Street = file du rez-de-chaussee ; Queue = terrasse ; Board = vers la cabine ; Ride = dans la
-- cabine ; Balcony = sur le balcon ; BoardDown = remonte dans la cabine pour partir ; Exit = sorti
-- de la cabine en bas, s'en va dans la rue.
type Stage = "Street" | "Queue" | "Board" | "Ride" | "Balcony" | "BoardDown" | "Exit"
type LiftPhase =
	"Idle"
	| "Boarding"
	| "Closing"
	| "Up"
	| "Unloading"
	| "TopBoarding"
	| "TopClosing"
	| "Down"
	| "BottomUnloading"

type Sale = { fruit: string, amount: number }

-- Rue devant la base (positions au sol) : origine = CustomerEntry du rez-de-chaussee (trottoir).
type Street = {
	origin: Vector3,
	along: Vector3, -- le long de la rue, dans le sens des places 1 -> 5
	toRoad: Vector3, -- des places vers la route
	minS: number, -- limites le long de la rue (bouts de la route)
	maxS: number,
	lamps: { number }, -- lampadaires de ce cote (coordonnee le long de la rue)
}

-- File d'une place du comptoir (rez-de-chaussee). members[1] = au comptoir.
type Line = {
	members: { Customer },
	target: number,
	rerollAt: number,
	pending: { Sale },
}

type Slot = { pos: Vector3, yaw: number }

-- File de la terrasse + geometrie de l'ascenseur (positions monde, au sol).
type Route = {
	pts: { Vector3 }, -- Point1..PointN puis ElevatorEntry
	arcs: { number }, -- distance depuis Point1
	length: number,
	street: Vector3, -- entree de la terrasse (cote rue, devant Point1)
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
	riders: { Customer }, -- montent
	downRiders: { Customer }, -- descendent (clients servis)
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
	instantDone: boolean,
	lastSpawn: number,
	nextSpawnAt: number,
	count: number,
	bubbles: number, -- bulles emoji affichees
	lastJuices: number, -- CounterJuices au dernier changement (0 -> plus : bulles contentes)
	happyAt: number, -- dernier ding de client servi
	happyCombo: number,
	sipAt: number,
	front: { [number]: Customer }, -- etages 2+ : au comptoir du balcon
	waiting: { [number]: Customer }, -- etages 2+ : juste derriere
	pending: { [number]: { Sale } }, -- etages 2+ : ventes en attente par place
	customers: { [Customer]: boolean },
	lines: { [number]: Line }, -- rez-de-chaussee
	queue: { Customer }, -- terrasse
	leavers: { Customer }, -- etages 2+ : servis, attendent la cabine en haut
	route: Route?,
	street: Street?,
	rayParams: RaycastParams?,
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
	decals: { Decal },
	hip: number,
	spot: number,
	role: Role,
	stage: Stage,
	status: Status,
	speed: number,
	moveSpeed: number, -- vitesse du trajet en cours
	animSpeed: number,
	pos: Vector3, -- au sol
	yaw: number,
	targetYaw: number,
	faceYaw: number,
	turnRate: number,
	path: { Vector3 },
	pathIndex: number,
	delay: number, -- attente avant de partir (file qui avance en accordeon)
	onArrive: (() -> ())?,
	timer: number,
	onTimer: (() -> ())?,
	walkTrack: AnimationTrack?,
	runTrack: AnimationTrack?, -- melangee a la marche selon la vitesse (R15Walk, comme le script Animate)
	idleTrack: AnimationTrack?,
	moving: boolean,
	dirty: boolean,
	sold: boolean,
	fading: boolean,
	fadeT: number,
	fadeSeconds: number,
	fadeIn: number, -- 0 -> 1 : apparition en fondu
	fadeInSeconds: number,
	fadeAtIndex: number, -- point du chemin ou commence la disparition en fondu (0 = aucun)
	fadeOutSeconds: number,
	line: number, -- file du rez-de-chaussee (0 = aucune)
	lastLine: number,
	inLine: boolean, -- arrive a sa place dans la file
	gap: number, -- ecart avec le client de devant
	jitter: number, -- decalage de cote
	yawJitter: number,
	queueArc: number, -- terrasse : distance (depuis Point1) du dernier point vise
	ridePos: Vector3, -- place dans la cabine, cabine en bas
	waitingLift: boolean, -- servi, attend la cabine en haut
	cup: Model?,
	cupParts: { BasePart },
	cupStart: Vector3,
	cupT: number,
	torsoRel: CFrame,
	bubble: any?, -- EmojiBubble.Bubble
	bubbleOn: boolean,
	bubbleLeft: number, -- secondes ; < 0 : reste affichee
	wantOn: boolean, -- bulle "il faut des jus"
	wantSince: number,
	emojiT: number,
	fidgetT: number,
	fidgetLeft: number,
	waitSince: number,
	destroyed: boolean,
}

local started = false
local rng = Random.new()
local customersFolder: Folder? = nil
local templateFolder: Folder? = nil
local states: { [Model]: BaseState } = {}
local renderedStates: { [BaseState]: boolean } = {}
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
local serveLineFront: (state: BaseState, k: number, c: Customer, sale: Sale) -> ()
local serveBalcony: (state: BaseState, k: number, c: Customer, sale: Sale) -> ()

---------------------------------------------------------------------------------------------
-- Aides

local function between(range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function pick(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

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

local function flatRight(part: BasePart): Vector3
	local r = part.CFrame.RightVector
	local f = Vector3.new(r.X, 0, r.Z)
	if f.Magnitude < 0.001 then
		return Vector3.xAxis
	end
	return f.Unit
end

local function loadOf(state: BaseState): number
	return math.clamp(state.count / Npcs.CustomerMaxPerFloor, 0, 1)
end

---------------------------------------------------------------------------------------------
-- Rue devant la base (StreamingEnabled : tout peut manquer)

-- CustomerEntry du rez-de-chaussee (trottoir), aussi pour les etages 2+.
local function groundEntry(state: BaseState): BasePart?
	if state.index == 1 then
		return getMarker(state, "CustomerEntry")
	end
	local entry = findPath(state.owner, { "Floors", "Floor1", "Markers", "CustomerEntry" })
	if entry and entry:IsA("BasePart") then
		return entry
	end
	return nil
end

local function buildStreet(state: BaseState): Street?
	local entry = groundEntry(state)
	local spot1 = getMarker(state, "CustomerSpot1")
	local spot2 = getMarker(state, "CustomerSpot2")
	if entry == nil or spot1 == nil or spot2 == nil then
		return nil
	end
	local toRoad = flat(-spot1.CFrame.LookVector) -- les places regardent le comptoir
	if toRoad.Magnitude < 0.01 then
		return nil
	end
	toRoad = toRoad.Unit
	local d = flat(spot2.Position - spot1.Position)
	local along = d - toRoad * d:Dot(toRoad)
	if along.Magnitude < 0.01 then
		along = toRoad:Cross(Vector3.yAxis)
	end
	along = along.Unit
	local origin = floorPos(entry)
	local minS, maxS = -math.huge, math.huge
	local lamps: { number } = {}
	local road = findPath(workspace, { "Map", "Road" })
	if road then
		local asphalt = road:FindFirstChild("Asphalt")
		if asphalt and asphalt:IsA("BasePart") then
			local size = asphalt.Size
			local half = if size.X >= size.Z
				then asphalt.CFrame.RightVector * (size.X / 2)
				else asphalt.CFrame.LookVector * (size.Z / 2)
			local a = (asphalt.Position + half - origin):Dot(along)
			local b = (asphalt.Position - half - origin):Dot(along)
			minS, maxS = math.min(a, b) + ROAD_END_MARGIN, math.max(a, b) - ROAD_END_MARGIN
		end
		for _, lamp in road:GetChildren() do
			local post = lamp:FindFirstChild("Post")
			if post and post:IsA("BasePart") then
				local rel = post.Position - origin
				if math.abs(rel:Dot(toRoad)) < 6 then
					table.insert(lamps, rel:Dot(along))
				end
			end
		end
	end
	return {
		origin = origin,
		along = along,
		toRoad = toRoad,
		minS = minS,
		maxS = maxS,
		lamps = lamps,
	}
end

local function sOf(st: Street, p: Vector3): number
	return (p - st.origin):Dot(st.along)
end

-- Hauteur du sol sous p (herbe, trottoir, cour, terrasse). Seulement la carte et cette base.
local function groundAt(state: BaseState, p: Vector3): Vector3
	local params = state.rayParams
	if params == nil then
		local list: { Instance } = { state.owner }
		local map = workspace:FindFirstChild("Map")
		if map then
			for _, name in { "Ground", "Road" } do
				local child = map:FindFirstChild(name)
				if child then
					table.insert(list, child)
				end
			end
		end
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Include
		made.FilterDescendantsInstances = list
		made.RespectCanCollide = true
		state.rayParams = made
		params = made
	end
	local hit = workspace:Raycast(p + Vector3.new(0, 2.5, 0), Vector3.new(0, -6, 0), params)
	if hit then
		return Vector3.new(p.X, hit.Position.Y, p.Z)
	end
	return p
end

local function streetPoint(state: BaseState, st: Street, s: number, u: number): Vector3
	local clamped = math.clamp(s, math.min(st.minS, st.maxS), math.max(st.minS, st.maxS))
	return groundAt(state, st.origin + st.along * clamped + st.toRoad * u)
end

-- On traverse le trottoir loin des lampadaires.
local function safeCross(st: Street, s: number): number
	for _, lamp in st.lamps do
		if math.abs(s - lamp) < LAMP_CLEARANCE then
			s = lamp + (if s >= lamp then LAMP_CLEARANCE else -LAMP_CLEARANCE)
		end
	end
	return s
end

-- Coordonnee a `dist` de s0 le long de la rue, du cote `sign` (au hasard si nil) ; l'autre cote si
-- la route s'arrete avant.
local function farS(st: Street, s0: number, dist: number, sign: number?): number
	local first = sign or (if rng:NextInteger(0, 1) == 0 then -1 else 1)
	for _, side in { first, -first } do
		local s = s0 + side * dist
		if s >= st.minS and s <= st.maxS then
			return s
		end
	end
	if st.maxS - s0 >= s0 - st.minS then
		return st.maxS
	end
	return st.minS
end

---------------------------------------------------------------------------------------------
-- File de la terrasse et geometrie de l'ascenseur

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
	local f = Vector3.new(exitFloor.X - entryFloor.X, 0, exitFloor.Z - entryFloor.Z)
	if f.Magnitude < 1 then
		return nil
	end
	local xAxis = f.Unit
	local zAxis = xAxis:Cross(Vector3.yAxis)
	return {
		pts = pts,
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

local function loadTrack(animator: Animator, name: string, id: string, priority: Enum.AnimationPriority): AnimationTrack?
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
	loaded.Priority = priority
	return loaded
end

-- fadeInSeconds > 0 : le client apparait en fondu.
local function createCustomer(
	state: BaseState,
	spot: number,
	role: Role,
	stage: Stage,
	startPos: Vector3,
	startYaw: number,
	fadeInSeconds: number
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
	local decals: { Decal } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d == hrp
			table.insert(parts, d)
		elseif d:IsA("Decal") then
			table.insert(decals, d)
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	if fadeInSeconds > 0 then
		for _, p in parts do
			p.LocalTransparencyModifier = 1
		end
		for _, d in decals do
			d.LocalTransparencyModifier = 1
		end
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	;(humanoid :: any).EvaluateStateMachine = false

	model.Name = "Customer"
	model.PrimaryPart = hrp
	CollectionService:AddTag(model, Npcs.FarHideTag) -- invisible loin de la camera (WorldDetailController)
	model:PivotTo(CFrame.new(startPos.X, startPos.Y + hip, startPos.Z) * CFrame.Angles(0, startYaw, 0))
	model.Parent = folder

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	-- Animations R15 des joueurs (rigs R15 depuis le 2026-11-27 ; avant : R6)
	local walkTrack = loadTrack(animator :: Animator, "Walk", Npcs.AnimationsR15.Walk, Enum.AnimationPriority.Movement)
	local runTrack = loadTrack(animator :: Animator, "Run", Npcs.AnimationsR15.Run, Enum.AnimationPriority.Movement)
	local idleTrack = loadTrack(animator :: Animator, "Idle", Npcs.AnimationsR15.Idle, Enum.AnimationPriority.Idle)
	if idleTrack then
		-- Pas tous en meme temps : vitesse et moment de l'animation d'attente au hasard
		idleTrack:Play(0)
		idleTrack:AdjustSpeed(rng:NextNumber(0.85, 1.15))
		if idleTrack.Length > 0 then
			idleTrack.TimePosition = rng:NextNumber(0, idleTrack.Length)
		end
	end

	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local speed = Npcs.CustomerWalkSpeed * rng:NextNumber(0.92, 1.08)
	local customer: Customer = {
		home = state,
		model = model,
		hrp = hrp,
		head = if head and head:IsA("BasePart") then head else hrp,
		torso = if torso and torso:IsA("BasePart") then torso else nil,
		parts = parts,
		decals = decals,
		hip = hip,
		spot = spot,
		role = role,
		stage = stage,
		status = "Standing",
		speed = speed,
		moveSpeed = speed,
		animSpeed = speed,
		pos = startPos,
		yaw = startYaw,
		targetYaw = startYaw,
		faceYaw = startYaw,
		turnRate = TURN_RATE,
		path = {},
		pathIndex = 1,
		delay = 0,
		onArrive = nil,
		timer = 0,
		onTimer = nil,
		walkTrack = walkTrack,
		runTrack = runTrack,
		idleTrack = idleTrack,
		moving = false,
		dirty = false,
		sold = false,
		fading = false,
		fadeT = 0,
		fadeSeconds = FADE_SECONDS,
		fadeIn = if fadeInSeconds > 0 then 0 else 1,
		fadeInSeconds = math.max(fadeInSeconds, 0.05),
		fadeAtIndex = 0,
		fadeOutSeconds = FADE_SECONDS,
		line = 0,
		lastLine = 0,
		inLine = false,
		gap = between(Npcs.CustomerLineGap),
		jitter = rng:NextNumber(-Npcs.CustomerLineJitter, Npcs.CustomerLineJitter),
		yawJitter = rng:NextNumber(-YAW_JITTER, YAW_JITTER),
		queueArc = 0,
		ridePos = startPos,
		waitingLift = false,
		cup = nil,
		cupParts = {},
		cupStart = startPos,
		cupT = 0,
		torsoRel = CFrame.new(),
		bubble = nil,
		bubbleOn = false,
		bubbleLeft = 0,
		wantOn = false,
		wantSince = 0,
		emojiT = between(Npcs.CustomerEmojiEvery),
		fidgetT = between(FIDGET_EVERY),
		fidgetLeft = 0,
		waitSince = os.clock(),
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

local function setAlpha(c: Customer, a: number)
	for _, p in c.parts do
		p.LocalTransparencyModifier = a
	end
	for _, d in c.decals do
		d.LocalTransparencyModifier = a
	end
	for _, p in c.cupParts do
		p.LocalTransparencyModifier = a
	end
end

---------------------------------------------------------------------------------------------
-- Bulles emoji

local function hideEmoji(c: Customer)
	c.wantOn = false
	if not c.bubbleOn then
		return
	end
	c.bubbleOn = false
	c.home.bubbles -= 1
	local bubble = c.bubble
	if bubble then
		EmojiBubble.Hide(bubble)
	end
end

-- seconds < 0 : la bulle reste (bulle "il faut des jus").
local function showEmoji(c: Customer, emoji: string, seconds: number, badge: boolean)
	if c.destroyed then
		return
	end
	local bubble = c.bubble
	if bubble == nil then
		bubble = EmojiBubble.new(c.head)
		c.bubble = bubble
	end
	if not c.bubbleOn then
		c.bubbleOn = true
		c.home.bubbles += 1
	end
	c.bubbleLeft = seconds
	EmojiBubble.Show(bubble, emoji, badge)
end

-- Premier de sa file (rez-de-chaussee) ou au comptoir du balcon (etages 2+).
local function atCounter(c: Customer): boolean
	local state = c.home
	if c.line > 0 then
		local line = state.lines[c.line]
		return line ~= nil and line.members[1] == c
	end
	return c.role == "Front" and c.stage == "Balcony" and state.front[c.spot] == c
end

refreshBubble = function(c: Customer)
	if c.destroyed then
		return
	end
	local juices = c.home.base:GetAttribute("CounterJuices")
	local want = c.status == "Standing" and not c.sold and not c.fading and juices == 0 and atCounter(c)
	if want then
		if not c.wantOn then
			showEmoji(c, Npcs.CustomerEmojis.Want, -1, true)
			c.wantOn = true
			c.wantSince = os.clock()
		end
	elseif c.wantOn then
		hideEmoji(c)
	end
end

local function refreshBubbles(state: BaseState)
	for k = 1, MAX_SPOTS do
		local line = state.lines[k]
		local first = if line then line.members[1] else nil
		if first then
			refreshBubble(first)
		end
		local c = state.front[k]
		if c then
			refreshBubble(c)
		end
	end
end

-- Bulle de temps en temps pour un client qui attend (pas trop a la fois).
local function idleEmoji(c: Customer)
	if c.destroyed or c.status ~= "Standing" or c.sold or c.fading or c.bubbleOn then
		return
	end
	local state = c.home
	if state.bubbles >= Npcs.CustomerEmojiMax + state.slots or rng:NextNumber() > 0.6 then
		return
	end
	local juices = state.base:GetAttribute("CounterJuices")
	local impatient = juices == 0 or os.clock() - c.waitSince > Npcs.CustomerImpatientSeconds
	local list = if impatient then Npcs.CustomerEmojis.Impatient else Npcs.CustomerEmojis.Waiting
	showEmoji(c, pick(list), Npcs.CustomerEmojiSeconds, false)
end

---------------------------------------------------------------------------------------------
-- Disparition

local function startFade(c: Customer, seconds: number)
	if c.fading or c.destroyed then
		return
	end
	c.fading = true
	c.fadeT = 1 - c.fadeIn -- s'il apparaissait encore : on repart de sa transparence
	c.fadeIn = 1
	c.fadeSeconds = math.max(seconds, 0.05)
	hideEmoji(c)
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
	if c.bubbleOn then
		c.bubbleOn = false
		state.bubbles -= 1
	end
	if state.front[c.spot] == c then
		state.front[c.spot] = nil
	end
	if state.waiting[c.spot] == c then
		state.waiting[c.spot] = nil
	end
	if c.line > 0 then
		local line = state.lines[c.line]
		if line then
			removeFrom(line.members, c)
		end
	end
	removeFrom(state.queue, c)
	removeFrom(state.leavers, c)
	local lift = state.lift
	if lift then
		removeFrom(lift.riders, c)
		removeFrom(lift.downRiders, c)
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
	removeFrom(c.home.leavers, c)
	c.status = "Leaving"
	c.path = {}
	c.pathIndex = 1
	c.onArrive = nil
	c.onTimer = nil
	c.fadeAtIndex = 0
	startFade(c, seconds)
end

---------------------------------------------------------------------------------------------
-- Deplacements

-- delay : attente avant de partir ; speedFactor : fraction de la vitesse du client.
local function walkTo(c: Customer, points: { Vector3 }, final: () -> (), delay: number?, speedFactor: number?)
	c.path = points
	c.pathIndex = 1
	c.dirty = true
	c.delay = delay or 0
	c.moveSpeed = c.speed * (speedFactor or 1)
	c.fidgetLeft = 0
	c.turnRate = TURN_RATE
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

-- Vrai si le client est au bout de son chemin (pas un ancien rappel d'arrivee).
local function arrived(c: Customer): boolean
	return c.pathIndex > #c.path
end

-- Depart a pied dans la rue : disparait en fondu sur les derniers studs puis est detruit.
local function leaveAlongStreet(c: Customer, points: { Vector3 }, fadeIndex: number, fadeStuds: number)
	c.fadeAtIndex = fadeIndex
	c.fadeOutSeconds = math.max(fadeStuds / c.speed, 0.3)
	walkTo(c, points, function()
		destroyCustomer(c)
	end)
end

-- Ajoute a `points` la voie des departs (herbe le long de la rue) a sStart puis un point au loin.
-- Renvoie l'index du point ou commence le fondu et la longueur du fondu.
local function appendStreetExit(state: BaseState, st: Street, points: { Vector3 }, sStart: number, sign: number?): (number, number)
	local u = between(LANE_OUT)
	table.insert(points, streetPoint(state, st, sStart, u))
	local dist = lerp(Npcs.CustomerLeaveFar[1], Npcs.CustomerLeaveFar[2], loadOf(state)) * rng:NextNumber(0.85, 1.15)
	local sFar = farS(st, sStart, dist, sign)
	local span = sFar - sStart
	local fadeStuds = math.min(Npcs.CustomerFadeOutStuds, math.abs(span) * 0.5)
	local sFade = sFar - math.sign(span) * fadeStuds
	table.insert(points, streetPoint(state, st, sFade, u))
	table.insert(points, streetPoint(state, st, sFar, u))
	return #points - 1, fadeStuds
end

local function setMoving(c: Customer, moving: boolean)
	c.moving = moving
	local walk, run, idle = c.walkTrack, c.runTrack, c.idleTrack
	if moving then
		if idle then
			idle:Stop(0.15)
		end
		R15Walk.Play(walk, run, c.moveSpeed, 0.15)
		c.animSpeed = c.moveSpeed
	else
		if walk then
			walk:Stop(0.15)
		end
		if run then
			run:Stop(0.15)
		end
		if idle then
			idle:Play(0.15)
		end
	end
end

-- Avance d'un client pour cette image. Les rappels sont ranges dans `pending` (executes apres la boucle).
local function updateCustomer(c: Customer, dt: number)
	local moving = false
	if c.delay > 0 then
		c.delay -= dt
	else
		local path = c.path
		local idx = c.pathIndex
		local count = #path
		if idx <= count then
			local target = path[idx]
			local delta = target - c.pos
			local dist = delta.Magnitude
			local step = c.moveSpeed * dt
			if dist <= step then
				c.pos = target
				c.pathIndex = idx + 1
				if idx == c.fadeAtIndex then
					startFade(c, c.fadeOutSeconds)
				end
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
	end
	if moving ~= c.moving then
		setMoving(c, moving)
	elseif moving and c.animSpeed ~= c.moveSpeed then
		-- vitesse changee en marchant : nouveau melange marche / course sans relancer les pistes
		c.animSpeed = c.moveSpeed
		local speed, walkWeight, runWeight = R15Walk.Blend(c.moveSpeed)
		local walk, run = c.walkTrack, c.runTrack
		if walk then
			walk:AdjustSpeed(speed)
			walk:AdjustWeight(walkWeight, 0.2)
		end
		if run then
			run:AdjustSpeed(speed)
			run:AdjustWeight(runWeight, 0.2)
		end
	end

	local diff = (c.targetYaw - c.yaw + math.pi) % (2 * math.pi) - math.pi
	local turning = math.abs(diff) > 0.002
	if turning then
		c.yaw += diff * math.min(1, dt * c.turnRate)
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

	-- Bulle emoji a duree limitee
	if c.bubbleOn and c.bubbleLeft > 0 then
		c.bubbleLeft -= dt
		if c.bubbleLeft <= 0 then
			hideEmoji(c)
		end
	end
	-- Client qui attend : bulle de temps en temps, coups d'oeil autour (pas au comptoir)
	if c.status == "Standing" and not c.sold and not c.fading then
		c.emojiT -= dt
		if c.emojiT <= 0 then
			c.emojiT = between(Npcs.CustomerEmojiEvery)
			idleEmoji(c)
		end
		if c.fidgetLeft > 0 then
			c.fidgetLeft -= dt
			if c.fidgetLeft <= 0 then
				c.turnRate = TURN_RATE
				c.targetYaw = c.faceYaw
			end
		else
			c.fidgetT -= dt
			if c.fidgetT <= 0 then
				c.fidgetT = between(FIDGET_EVERY)
				if not atCounter(c) then
					c.fidgetLeft = between(FIDGET_SECONDS)
					c.turnRate = FIDGET_TURN_RATE
					c.targetYaw = c.faceYaw + rng:NextNumber(-FIDGET_ANGLE, FIDGET_ANGLE)
				end
			end
		end
	end

	if c.fadeIn < 1 and not c.fading then
		c.fadeIn = math.min(c.fadeIn + dt / c.fadeInSeconds, 1)
		setAlpha(c, 1 - c.fadeIn)
	end
	if c.fading then
		c.fadeT += dt / c.fadeSeconds
		local a = math.min(c.fadeT, 1)
		setAlpha(c, a)
		if a >= 1 then
			c.fading = false
			table.insert(pending, function()
				destroyCustomer(c)
			end)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Vente (effets)

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

-- Vente sans client pret (et plus de place dans les ventes en attente) : "+$" et son seuls.
local function saleWithoutCustomer(state: BaseState, k: number, amount: number)
	local pos = placeOf(state, k, "Front")
	if pos then
		floatText(pos + Vector3.new(0, 5, 0), amount)
		SoundFx.PlayAt("Sale", pos)
	end
end

-- Client servi : ding scintillant (plus aigu quand les ventes s'enchainent), puis slurp quand il
-- goute son jus. Limites par etage pour ne pas faire une bouillie de sons aux ventes rapides.
local function playHappySounds(c: Customer)
	local state = c.home
	local now = os.clock()
	if now - state.happyAt >= HAPPY_SOUND_GAP then
		state.happyCombo = if now - state.happyAt < HAPPY_COMBO_SECONDS
			then math.min(state.happyCombo + 1, HAPPY_COMBO_MAX)
			else 0
		state.happyAt = now
		SoundFx.PlayAt("CustomerHappy", c.hrp.Position, nil, 1 + state.happyCombo * HAPPY_COMBO_STEP)
	end
	if now - state.sipAt >= SIP_SOUND_GAP then
		state.sipAt = now
		task.delay(SIP_DELAY, function()
			if not c.destroyed then
				SoundFx.PlayAt("CustomerSip", c.hrp.Position)
			end
		end)
	end
end

-- Des jus arrivent sur le comptoir vide alors que des clients attendaient au comptoir : ils se
-- rejouissent (bulle contente, sans son : le "Yeah !" a ete retire le 2026-11-27).
local function onJuicesChanged(state: BaseState)
	local value = state.base:GetAttribute("CounterJuices")
	local juices = if type(value) == "number" then value else 0
	local before = state.lastJuices
	state.lastJuices = juices
	if state.rendered and before == 0 and juices > 0 then
		local now = os.clock()
		for c in state.customers do
			if c.wantOn and not c.destroyed and now - c.wantSince >= HAPPY_MIN_WAIT then
				c.wantOn = false
				showEmoji(c, pick(Npcs.CustomerEmojis.Happy), Npcs.CustomerHappySeconds, false)
			end
		end
	end
	refreshBubbles(state)
end

local function serve(c: Customer, fruitId: string, amount: number)
	local state = c.home
	c.sold = true
	c.wantOn = false

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
	showEmoji(c, pick(Npcs.CustomerEmojis.Happy), Npcs.CustomerHappySeconds, false)
	playHappySounds(c)

	c.timer = LEAVE_DELAY_SECONDS
	c.onTimer = function()
		startLeaving(c)
	end
end

---------------------------------------------------------------------------------------------
-- Rez-de-chaussee : une file par place du comptoir

local function getLine(state: BaseState, k: number): Line
	local line = state.lines[k]
	if line == nil then
		local made: Line = { members = {}, target = 0, rerollAt = 0, pending = {} }
		state.lines[k] = made
		return made
	end
	return line
end

-- Longueur max d'une file : le bout reste loin de la voie des departs (herbe le long de la rue).
local function lineMaxArc(st: Street, spot: Vector3): number
	local depth = -(spot - st.origin):Dot(st.toRoad) -- distance trottoir -> place
	return math.max(depth + LANE_OUT[1] - LINE_TAIL_CLEARANCE, 6)
end

-- Angle de la file k (eventail) : 0 au milieu, vers l'exterieur sur les cotes.
local function lineAngle(state: BaseState, k: number): number
	return (k - (math.max(state.slots, 1) + 1) / 2) * LINE_FAN
end

-- Place de chaque client de la file k (1 = au comptoir), avec ecarts et decalages au hasard.
local function layoutLine(state: BaseState, k: number): { Slot }?
	local st = state.street
	local base, yaw = placeOf(state, k, "Front")
	local line = state.lines[k]
	if st == nil or base == nil or yaw == nil or line == nil then
		return nil
	end
	local angle = lineAngle(state, k)
	local dir = st.toRoad * math.cos(angle) + st.along * math.sin(angle) -- du comptoir vers le bout de la file
	local side = dir:Cross(Vector3.yAxis)
	local arcs: { number } = {}
	local arc = 0
	for i, c in line.members do
		if i > 1 then
			arc += c.gap
		end
		arcs[i] = arc
	end
	local maxArc = lineMaxArc(st, base) / math.cos(angle)
	local squeeze = if arc > maxArc then maxArc / arc else 1
	local backYaw = yawOf(-dir) -- regarde vers l'avant de la file
	local slots: { Slot } = {}
	for i, c in line.members do
		local offset = if i == 1 then c.jitter * 0.3 else c.jitter
		local p = base + dir * (arcs[i] * squeeze) + side * offset
		slots[i] = { pos = groundAt(state, p), yaw = if i == 1 then yaw else backYaw + c.yawJitter }
	end
	return slots
end

local function arriveInLine(c: Customer)
	if c.destroyed or not arrived(c) then
		return
	end
	c.status = "Standing"
	c.inLine = true
	c.targetYaw = c.faceYaw
	local state = c.home
	local line = state.lines[c.line]
	if line and line.members[1] == c and c.onTimer == nil then
		local sale = table.remove(line.pending, 1)
		if sale then
			-- Une vente l'attendait : il prend son gobelet en arrivant
			local k = c.line
			c.timer = SERVE_PAUSE
			c.onTimer = function()
				serveLineFront(state, k, c, sale)
			end
			return
		end
	end
	refreshBubble(c)
end

-- Chacun va a sa place ; accordion : ils partent l'un apres l'autre, en marchant doucement.
local function relayoutLine(state: BaseState, k: number, accordion: boolean)
	local slots = layoutLine(state, k)
	local line = state.lines[k]
	if slots == nil or line == nil then
		return
	end
	local moved = 0
	for i, c in line.members do
		local slot = slots[i]
		c.faceYaw = slot.yaw
		if c.status == "Walking" and c.pathIndex <= #c.path then
			c.path[#c.path] = slot.pos -- deja en chemin : seul le point d'arrivee change
		elseif (c.pos - slot.pos).Magnitude > 0.05 then
			local delay = if accordion then moved * between(ACCORDION) + rng:NextNumber(0.03, 0.12) else 0
			moved += 1
			c.inLine = false
			local customer = c
			walkTo(customer, { slot.pos }, function()
				arriveInLine(customer)
			end, delay, LINE_STEP_SPEED)
		elseif c.status == "Standing" and c.fidgetLeft <= 0 then
			c.targetYaw = slot.yaw
		end
	end
end

serveLineFront = function(state: BaseState, k: number, c: Customer, sale: Sale)
	local line = state.lines[k]
	if c.destroyed or line == nil or line.members[1] ~= c then
		return
	end
	table.remove(line.members, 1)
	c.lastLine = k
	c.line = 0
	serve(c, sale.fruit, sale.amount)
	relayoutLine(state, k, true)
end

-- Nouveau client pour la file k : au loin sur le trottoir (ou directement a sa place).
local function spawnLineCustomer(state: BaseState, k: number, instant: boolean): Customer?
	local st = state.street
	local spotPos, spotYaw = placeOf(state, k, "Front")
	if st == nil or spotPos == nil or spotYaw == nil then
		return nil
	end
	local line = getLine(state, k)
	local c: Customer?
	local turn = spotPos
	if instant then
		c = createCustomer(state, k, "Waiting", "Street", spotPos, spotYaw, INSTANT_FADE_SECONDS)
	else
		local u = between(LANE_IN)
		local cross = safeCross(st, sOf(st, spotPos) + rng:NextNumber(-1.5, 1.5))
		local dist = lerp(Npcs.CustomerSpawnFar[1], Npcs.CustomerSpawnFar[2], loadOf(state)) * rng:NextNumber(0.85, 1.15)
		local start = streetPoint(state, st, farS(st, cross, dist, nil), u)
		turn = streetPoint(state, st, cross, u)
		c = createCustomer(state, k, "Waiting", "Street", start, yawOf(turn - start), Npcs.CustomerFadeInSeconds)
	end
	if c == nil then
		return nil
	end
	local customer = c :: Customer
	customer.line = k
	table.insert(line.members, customer)
	if instant then
		local slots = layoutLine(state, k)
		local slot = if slots then slots[#line.members] else nil
		if slot then
			customer.pos = slot.pos
			customer.yaw = slot.yaw
			customer.targetYaw = slot.yaw
			customer.faceYaw = slot.yaw
			customer.dirty = true
		end
		arriveInLine(customer)
	else
		walkTo(customer, { turn, turn }, function()
			arriveInLine(customer)
		end)
		relayoutLine(state, k, false) -- le nouveau prend le bout de la file
	end
	return customer
end

local function lineTarget(state: BaseState): number
	local lengths = Npcs.CustomerLineLength
	return lengths[math.clamp(state.slots, 1, #lengths)]
end

-- Arrivees : la file la plus en retard sur sa longueur voulue (+ ventes en attente) d'abord.
local function tickLines(state: BaseState, instant: boolean)
	if state.street == nil or state.slots <= 0 or templateFolder == nil then
		return
	end
	local now = os.clock()
	for k = 1, state.slots do
		local line = getLine(state, k)
		if now >= line.rerollAt then
			line.target = math.max(lineTarget(state) + rng:NextInteger(-1, 1), 2)
			line.rerollAt = now + rng:NextNumber(8, 18)
		end
	end
	if instant then
		for k = 1, state.slots do
			local line = getLine(state, k)
			while #line.members < line.target and state.count < Npcs.CustomerMaxPerFloor do
				if spawnLineCustomer(state, k, true) == nil then
					break
				end
			end
		end
		return
	end
	if now < state.nextSpawnAt or state.count >= Npcs.CustomerMaxPerFloor then
		return
	end
	local best, bestNeed = 0, 0
	for k = 1, state.slots do
		local line = getLine(state, k)
		local need = line.target + #line.pending - #line.members
		if need > bestNeed or (need == bestNeed and need > 0 and rng:NextNumber() < 0.5) then
			best, bestNeed = k, need
		end
	end
	if best == 0 then
		return
	end
	spawnLineCustomer(state, best, false)
	state.nextSpawnAt = now + between(Npcs.CustomerSpawnGap)
end

local function lineSale(state: BaseState, k: number, sale: Sale)
	local line = state.lines[k]
	local first = if line then line.members[1] else nil
	if line and first and first.inLine and first.status == "Standing" and first.onTimer == nil and not first.sold then
		serveLineFront(state, k, first, sale)
	elseif line and first and #line.pending < PENDING_MAX then
		table.insert(line.pending, sale) -- le prochain client au comptoir la prendra en arrivant
	else
		saleWithoutCustomer(state, k, sale.amount)
	end
end

-- Client servi : longe le comptoir jusqu'au bord des files, descend vers la rue, part au loin.
local function lineLeave(c: Customer)
	local state = c.home
	local st = state.street
	local first = placeOf(state, 1, "Front")
	local last = placeOf(state, math.max(state.slots, 1), "Front")
	if st == nil or first == nil or last == nil then
		fadeAway(c, FADE_SECONDS)
		return
	end
	c.status = "Leaving"
	local sCur = sOf(st, c.pos)
	local sLeft = sOf(st, first) - LINE_EDGE
	local sRight = sOf(st, last) + LINE_EDGE
	local dLeft, dRight = sCur - sLeft, sRight - sCur
	local goRight = if math.abs(dLeft - dRight) < 1 then rng:NextNumber() < 0.5 else dRight < dLeft
	local sEdge = if goRight then sRight else sLeft
	local edgeLine = if goRight then math.max(state.slots, 1) else 1
	local points: { Vector3 } = {}
	if c.lastLine == edgeLine then
		table.insert(points, c.pos + st.along * (sEdge - sCur) - st.toRoad * 0.6)
	else
		local p1 = c.pos - st.toRoad * COUNTER_LANE
		table.insert(points, p1)
		table.insert(points, p1 + st.along * (sEdge - sCur))
	end
	-- Il descend vers la rue en suivant l'eventail de la file du bord (sans la traverser)
	local depth = math.max(-(first - st.origin):Dot(st.toRoad) + LANE_OUT[1], 0)
	local sign = if goRight then 1 else -1
	local sDown = sEdge + sign * depth * math.tan(math.abs(lineAngle(state, edgeLine)))
	local fadeIndex, fadeStuds = appendStreetExit(state, st, points, sDown, sign)
	leaveAlongStreet(c, points, fadeIndex, fadeStuds)
end

-- Places en moins (rare) : les files en trop s'effacent.
local function trimLines(state: BaseState)
	for k, line in state.lines do
		if k > state.slots then
			state.lines[k] = nil
			for _, c in table.clone(line.members) do
				c.line = 0
				fadeAway(c, 0.6)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Etages 2+ : balcon (places devant / derriere)

local function canSpawn(state: BaseState, instant: boolean): boolean
	local cap = 2 * state.slots + 6 + (if usesLift(state) then QUEUE_MAX + LEAVERS_MAX else 0)
	if state.count >= cap then
		return false
	end
	if not instant and os.clock() - state.lastSpawn < SPAWN_GAP_SECONDS then
		return false
	end
	return templateFolder ~= nil
end

local function arrivedAtPlace(c: Customer)
	if not arrived(c) then
		return
	end
	c.status = "Standing"
	c.targetYaw = c.faceYaw
	local state = c.home
	if c.role == "Front" and state.front[c.spot] == c and c.onTimer == nil then
		local list = state.pending[c.spot]
		local sale = if list then table.remove(list, 1) else nil
		if sale then
			local k = c.spot
			c.timer = SERVE_PAUSE
			c.onTimer = function()
				serveBalcony(state, k, c, sale)
			end
			return
		end
	end
	refreshBubble(c)
end

-- Entree -> (chemin) -> destination, tout au sol (balcon sans ascenseur).
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

-- Cree un client a sa place (instant) ou a l'entree du balcon, en marche vers sa place.
local function spawnFor(state: BaseState, k: number, role: Role, instant: boolean): Customer?
	local pos, yaw = placeOf(state, k, role)
	if pos == nil or yaw == nil then
		return nil
	end
	local c: Customer?
	if instant then
		c = createCustomer(state, k, role, "Balcony", pos, yaw, INSTANT_FADE_SECONDS)
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
		c = createCustomer(state, k, role, "Balcony", start, yawOf(second - start), 0.6)
		if c then
			state.lastSpawn = os.clock()
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
				if waiter.stage == "Balcony" then
					local delay = if waiter.status == "Standing" then rng:NextNumber(0.1, 0.3) else 0
					walkTo(waiter, { pos }, function()
						arrivedAtPlace(waiter)
					end, delay, LINE_STEP_SPEED)
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

serveBalcony = function(state: BaseState, k: number, c: Customer, sale: Sale)
	if c.destroyed or state.front[k] ~= c then
		return
	end
	state.front[k] = nil
	serve(c, sale.fruit, sale.amount)
	fill(state, k, false)
end

---------------------------------------------------------------------------------------------
-- Etages 2+ : file de la terrasse

-- Distance (depuis Point1) de chaque client de la file : le premier a QUEUE_HEAD_BACK de la porte,
-- puis l'ecart de chacun avec celui de devant.
local function queueArcs(state: BaseState, route: Route): { number }
	local arcs: { number } = {}
	local arc = route.length - QUEUE_HEAD_BACK
	for i, c in state.queue do
		if i > 1 then
			arc -= c.gap
		end
		arcs[i] = math.max(arc, 0)
	end
	return arcs
end

local function queuePos(route: Route, arc: number, c: Customer): (Vector3, Vector3)
	local pos, dir = pointAt(route, arc)
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude > 0.001 then
		pos += side.Unit * (c.jitter * 0.8)
	end
	return pos, dir
end

local function arriveInQueue(c: Customer)
	if c.destroyed or not arrived(c) then
		return
	end
	c.status = "Standing"
	c.targetYaw = c.faceYaw
end

local function spawnQueueCustomer(state: BaseState, instant: boolean): Customer?
	local route = state.route
	if route == nil then
		return nil
	end
	local st = state.street
	local points: { Vector3 } = {}
	local c: Customer?
	if instant then
		c = createCustomer(state, 0, "Waiting", "Queue", route.pts[1], 0, INSTANT_FADE_SECONDS)
	else
		local start = route.street
		local fadeIn = 0.6
		if st then
			-- de loin sur le trottoir, puis on entre dans la terrasse
			local u = between(LANE_IN)
			local cross = safeCross(st, sOf(st, route.street))
			local dist = lerp(Npcs.CustomerSpawnFar[1], Npcs.CustomerSpawnFar[2], loadOf(state)) * rng:NextNumber(0.85, 1.15)
			start = streetPoint(state, st, farS(st, cross, dist, nil), u)
			table.insert(points, streetPoint(state, st, cross, u))
			table.insert(points, route.street)
			fadeIn = Npcs.CustomerFadeInSeconds
		end
		table.insert(points, route.pts[1])
		c = createCustomer(state, 0, "Waiting", "Queue", start, yawOf(points[1] - start), fadeIn)
	end
	if c == nil then
		return nil
	end
	local customer = c :: Customer
	table.insert(state.queue, customer)
	local arcs = queueArcs(state, route)
	local arc = arcs[#state.queue]
	local pos, dir = queuePos(route, arc, customer)
	customer.queueArc = arc
	customer.faceYaw = yawOf(dir) + customer.yawJitter
	if instant then
		customer.pos = pos
		customer.yaw = customer.faceYaw
		customer.targetYaw = customer.faceYaw
		customer.dirty = true
	else
		state.lastSpawn = os.clock()
		cornersBetween(route, 0, arc, points)
		table.insert(points, pos)
		walkTo(customer, points, function()
			arriveInQueue(customer)
		end)
	end
	return customer
end

-- Les clients de la file avancent vers leur nouvelle place, l'un apres l'autre.
local function advanceQueue(state: BaseState)
	local route = state.route
	if route == nil then
		return
	end
	local arcs = queueArcs(state, route)
	local moved = 0
	for i, c in state.queue do
		local arc = arcs[i]
		if arc > c.queueArc + 0.01 then
			local pos, dir = queuePos(route, arc, c)
			local walking = c.status == "Walking" and c.pathIndex <= #c.path
			local points = remainingPath(c)
			cornersBetween(route, c.queueArc, arc, points)
			table.insert(points, pos)
			c.queueArc = arc
			c.faceYaw = yawOf(dir) + c.yawJitter
			local delay, factor = 0, 1
			if not walking then
				delay = moved * between(ACCORDION) + rng:NextNumber(0.03, 0.12)
				moved += 1
				if (pos - c.pos).Magnitude < 6 then
					factor = LINE_STEP_SPEED
				end
			end
			local customer = c
			walkTo(customer, points, function()
				arriveInQueue(customer)
			end, delay, factor)
		end
	end
end

local function queueCap(state: BaseState): number
	return 2 * state.slots + 6 + QUEUE_MAX + LEAVERS_MAX
end

local function tickQueue(state: BaseState, instant: boolean)
	local route = state.route
	if route == nil or state.slots <= 0 or templateFolder == nil then
		return
	end
	local target = math.min(QUEUE_MAX, QUEUE_BASE + QUEUE_PER_SLOT * state.slots)
	if instant then
		while #state.queue < target and state.count < queueCap(state) do
			if spawnQueueCustomer(state, true) == nil then
				break
			end
		end
		return
	end
	local now = os.clock()
	if #state.queue >= target or now < state.nextSpawnAt or state.count >= queueCap(state) then
		return
	end
	spawnQueueCustomer(state, false)
	state.nextSpawnAt = now + between(Npcs.CustomerSpawnGap)
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
	table.clear(lift.downRiders)
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
	for _, list in { lift.riders, lift.downRiders } do
		for _, c in list do
			if c.stage == "Ride" and not c.destroyed then
				c.pos = c.ridePos + Vector3.new(0, offset, 0)
				c.dirty = true
			end
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
		-- lookAlong : -Z local = xAxis (vers le balcon) ; local2.X = vers le balcon
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

-- En haut : les clients servis qui attendent a cote de la porte montent dans la cabine.
local function startTopBoarding(state: BaseState, lift: Lift, route: Route): boolean
	local cap = liftCapacity(state)
	local frame = CFrame.lookAlong(lift.floorTop, route.xAxis)
	local doorTop = route.entry + route.xAxis * (CAGE_FROM_ENTRY + CAGE_DOOR) + Vector3.new(0, route.height, 0)
	local n = 0
	local i = 1
	while i <= #state.leavers and n < cap do
		local c = state.leavers[i]
		if c.waitingLift and not c.destroyed then
			table.remove(state.leavers, i)
			n += 1
			local local2 = CABIN_SPOTS[n]
			-- Ils entrent cote balcon : le fond de la cabine est cote terrasse (ou ils sortiront)
			c.ridePos = (frame * CFrame.new(local2.Y, 0, local2.X)).Position
			c.stage = "BoardDown"
			c.waitingLift = false
			table.insert(lift.downRiders, c)
			local customer = c
			walkTo(customer, { route.exit, doorTop, c.ridePos + Vector3.new(0, route.height, 0) }, function()
				customer.stage = "Ride"
				customer.targetYaw = yawOf(-route.xAxis)
			end)
		else
			i += 1
		end
	end
	return n > 0
end

local function hasReadyLeavers(state: BaseState): boolean
	for _, c in state.leavers do
		if c.waitingLift and not c.destroyed then
			return true
		end
	end
	return false
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

-- En bas : les clients qui repartent sortent cote terrasse, contournent la cage et s'en vont.
local function unloadBottom(state: BaseState, lift: Lift, route: Route)
	local st = state.street
	local door = route.entry + route.xAxis * (CAGE_FROM_ENTRY - CAGE_DOOR)
	for _, c in lift.downRiders do
		if not c.destroyed then
			c.stage = "Exit"
			if st == nil then
				fadeAway(c, FADE_SECONDS)
			else
				local outA = groundAt(state, door - route.xAxis * 1.7 + st.toRoad * 2)
				local outB = groundAt(state, door - route.xAxis * 2.1 + st.toRoad * 7)
				local points = { door, outA, outB }
				local fadeIndex, fadeStuds = appendStreetExit(state, st, points, sOf(st, outB), nil)
				leaveAlongStreet(c, points, fadeIndex, fadeStuds)
			end
		end
	end
	table.clear(lift.downRiders)
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
	for i = #lift.downRiders, 1, -1 do
		if lift.downRiders[i].destroyed then
			table.remove(lift.downRiders, i)
		end
	end
	local phase = lift.phase
	if phase == "Idle" then
		if not startBoarding(state, lift, route) and hasReadyLeavers(state) and acquireCabin(state, lift, route) then
			-- personne a monter mais des clients attendent en haut : la cabine monte a vide
			lift.phase = "Closing"
			lift.timer = LIFT_DOOR_SECONDS
		end
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
			elseif #lift.downRiders > 0 then
				unloadBottom(state, lift, route)
				lift.phase = "BottomUnloading"
				lift.timer = LIFT_UNLOAD_SECONDS
			else
				lift.phase = "Idle"
			end
		end
	elseif phase == "Unloading" then
		lift.timer -= dt
		if lift.timer <= 0 then
			if startTopBoarding(state, lift, route) then
				lift.phase = "TopBoarding"
				lift.timer = LIFT_TOP_TIMEOUT
			else
				moveLift(lift, "Down", 0, rideSeconds(state) * LIFT_DOWN_FACTOR)
			end
		end
	elseif phase == "TopBoarding" then
		lift.timer -= dt
		local ready = true
		for _, c in lift.downRiders do
			if c.stage ~= "Ride" then
				ready = false
				break
			end
		end
		if ready or lift.timer <= 0 then
			for i = #lift.downRiders, 1, -1 do
				local c = lift.downRiders[i]
				if c.stage ~= "Ride" then
					table.remove(lift.downRiders, i)
					fadeAway(c, FADE_SECONDS) -- retardataire
				end
			end
			lift.phase = "TopClosing"
			lift.timer = LIFT_DOOR_SECONDS
		end
	elseif phase == "TopClosing" then
		lift.timer -= dt
		if lift.timer <= 0 then
			moveLift(lift, "Down", 0, rideSeconds(state) * LIFT_DOWN_FACTOR)
		end
	elseif phase == "BottomUnloading" then
		lift.timer -= dt
		if lift.timer <= 0 then
			lift.phase = "Idle"
		end
	end
end

-- Client servi sur le balcon : longe le comptoir vers l'ascenseur et attend la cabine a cote de
-- la porte (sans ascenseur ou trop de monde : retour a la sortie et fondu, comme avant).
local function balconyLeave(c: Customer)
	local state = c.home
	local route, lift, st = state.route, state.lift, state.street
	c.status = "Leaving"
	if route == nil or lift == nil or st == nil or #state.leavers >= LEAVERS_MAX then
		local entry = getMarker(state, "CustomerEntry")
		if entry == nil then
			destroyCustomer(c)
			return
		end
		local points: { Vector3 } = {}
		local spot = getMarker(state, "CustomerSpot" .. c.spot)
		if spot and (c.pos - floorPos(spot)).Magnitude < 1.5 then
			local sign = if rng:NextInteger(0, 1) == 0 then -1 else 1
			table.insert(points, floorPos(spot) + flatRight(spot) * (SIDESTEP * sign))
		end
		table.insert(points, floorPos(entry))
		walkTo(c, points, function()
			startFade(c, FADE_SECONDS)
		end)
		return
	end
	local points: { Vector3 } = {}
	local first = placeOf(state, 1, "Front")
	local last = placeOf(state, math.max(state.slots, 1), "Front")
	if first and last then
		local sCur = sOf(st, c.pos)
		local exitS = sOf(st, route.exit)
		local toFirst = math.abs(exitS - sOf(st, first)) <= math.abs(exitS - sOf(st, last))
		local sEdge = if toFirst then sOf(st, first) - LINE_EDGE else sOf(st, last) + LINE_EDGE
		local edgeSpot = if toFirst then 1 else math.max(state.slots, 1)
		if c.spot == edgeSpot then
			table.insert(points, c.pos + st.along * (sEdge - sCur) - st.toRoad * 0.6)
		else
			local p1 = c.pos - st.toRoad * COUNTER_LANE
			table.insert(points, p1)
			table.insert(points, p1 + st.along * (sEdge - sCur))
		end
	end
	local zAxis = route.xAxis:Cross(Vector3.yAxis)
	local side = if rng:NextInteger(0, 1) == 0 then -1 else 1
	local wait = route.exit + route.xAxis * rng:NextNumber(0.6, 2) + zAxis * (side * between(LEAVER_WAIT_SIDE))
	table.insert(points, wait)
	table.insert(state.leavers, c)
	walkTo(c, points, function()
		c.waitingLift = true
		c.targetYaw = yawOf(-route.xAxis)
	end)
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
	if c.stage == "Street" then
		if c.sold then
			lineLeave(c)
		else
			fadeAway(c, 0.6)
		end
		return
	end
	-- Etage 2+ : pas encore sur le balcon (file, cabine) -> fondu sur place
	if state.index >= 2 and c.stage ~= "Balcony" then
		fadeAway(c, FADE_SECONDS)
		return
	end
	if c.sold then
		balconyLeave(c)
	else
		fadeAway(c, 0.6)
	end
end

---------------------------------------------------------------------------------------------
-- Boucle

local function onStep(dt: number)
	for state in liftStates do
		local lift = state.lift
		if lift and state.rendered then
			updateLift(state, lift, dt)
		end
	end
	for state in renderedStates do
		if state.rendered then
			if state.index == 1 then
				tickLines(state, false)
			elseif usesLift(state) then
				tickQueue(state, false)
			end
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

local function onSale(state: BaseState, k: number, fruitId: string, amount: number)
	if not state.rendered then
		return
	end
	local sale: Sale = { fruit = fruitId, amount = amount }
	if state.index == 1 then
		lineSale(state, k, sale)
		return
	end
	-- Etage 2+ : pas de teleportation depuis la file ou la cabine ; le client reserve prendra la
	-- vente en arrivant a sa place, sinon "+$" seul
	local c: Customer? = state.front[k]
	if c and c.stage == "Balcony" and c.status == "Standing" and c.onTimer == nil and not c.sold then
		serveBalcony(state, k, c, sale)
		return
	end
	local list = state.pending[k]
	if list == nil then
		list = {}
		state.pending[k] = list
	end
	if c and c.status ~= "Leaving" and #(list :: { Sale }) < PENDING_MAX then
		table.insert(list :: { Sale }, sale)
	else
		saleWithoutCustomer(state, k, amount)
	end
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
	table.clear(state.pending)
	table.clear(state.lines)
	table.clear(state.queue)
	table.clear(state.leavers)
	state.route = nil
	state.street = nil
	state.rayParams = nil
	state.rendered = false
	renderedStates[state] = nil
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
		state.instantDone = false
		renderedStates[state] = true
	end
	-- Rue et terrasse (essayees a chaque passage tant que la carte n'est pas recue)
	if state.street == nil then
		state.street = buildStreet(state)
		state.rayParams = nil
	end
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
			downRiders = {},
			cabin = nil,
			rest = nil,
			fallback = nil,
			floorTop = Vector3.zero,
		}
		liftStates[state] = true
	end
	local instant = os.clock() < state.instantUntil
	if state.index == 1 then
		trimLines(state)
		-- A l'affichage : files deja la ; ensuite les arrivees se font dans onStep
		if instant and not state.instantDone and state.street and templateFolder then
			tickLines(state, true)
			state.instantDone = true
		end
	else
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
		for k = 1, state.slots do
			fill(state, k, instant)
		end
		if usesLift(state) and instant and not state.instantDone and templateFolder then
			tickQueue(state, true)
			state.instantDone = true
		end
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
		instantDone = false,
		lastSpawn = 0,
		nextSpawnAt = 0,
		count = 0,
		bubbles = 0,
		lastJuices = 0,
		happyAt = 0,
		happyCombo = 0,
		sipAt = 0,
		front = {},
		waiting = {},
		pending = {},
		customers = {},
		lines = {},
		queue = {},
		leavers = {},
		route = nil,
		street = nil,
		rayParams = nil,
		lift = nil,
		conns = {},
	}
	local function reevaluate()
		evaluate(state)
	end
	table.insert(state.conns, base:GetAttributeChangedSignal("OwnerUserId"):Connect(reevaluate))
	table.insert(state.conns, base:GetAttributeChangedSignal("ActiveFloor"):Connect(reevaluate))
	table.insert(state.conns, floor:GetAttributeChangedSignal("CustomerSlots"):Connect(reevaluate))
	local juices = floor:GetAttribute("CounterJuices")
	state.lastJuices = if type(juices) == "number" then juices else 0
	table.insert(
		state.conns,
		floor:GetAttributeChangedSignal("CounterJuices"):Connect(function()
			onJuicesChanged(state)
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

	-- Heartbeat (pas RenderStepped) : les files et l'ascenseur avancent meme quand l'image n'est
	-- pas dessinee (fenetre reduite) ; on ne voit aucune difference a l'ecran.
	stepConn = RunService.Heartbeat:Connect(onStep)

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
