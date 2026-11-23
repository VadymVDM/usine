--!strict
-- L'usine change de look a chaque amelioration (demande du 2026-11-19 soir : "on doit voir notre
-- restaurant s'ameliorer"). Cote client seulement : le serveur (UpgradeService) pose sur chaque ETAGE
-- (Model Bases.BaseN.Floors.FloorK, tour d'etages) l'attribut "Lv_<id>" = niveau du proprietaire
-- pour cet etage ; ce module montre / cache les pieces de decor de l'etage :
--   * piece avec les attributs LookId (id d'amelioration) et LookLevel (niveau minimum), et
--     optionnellement LookMaxLevel : visible seulement si LookLevel <= niveau <= LookMaxLevel
--     (LookMaxLevel permet de remplacer une piece par une autre, ex. table plus grande) ;
--   * une piece qui apparait apres un achat arrive en fondu + etincelles ;
--   * panneau d'un mixeur pas encore deverrouille ou pas encore achete (tuile avec Locked ou Unbuilt,
--     panneau HideWhenLocked) : cache (achat du mixeur seulement par E sur la machine) ;
--   * lattes du tapis (Production.Conveyor, pieces "Slat") : elles defilent, plus vite quand le tapis
--     est ameliore (attribut ConveyorRate de Production, pose par ProductionService).
-- Depuis le 2026-11-21 (usine a construire) : un panneau qui apparait (HideWhenLocked : mixeur
-- achete, Fruit Picker embauche, etape FREE faite) et un pad de decor (Pad avec LookId, ex. Waiter
-- Speed x10) apparaissent en "pop" (Fx/Reveal) au lieu du fondu, dans SA base.
-- Pieces cachees avec LocalTransparencyModifier et sans collision pour ce joueur (rien ne change
-- cote serveur : les employes voient toutes les variantes). Rien au-dela de FX_DISTANCE pour le tapis.
-- Doc : docs/systems/ameliorations-employes.md (section Ce qui se voit a chaque niveau)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))
local Reveal = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Reveal"))

local FX_DISTANCE = 150
local FADE_SECONDS = 0.45
local SLAT_SPACING = 2 -- ecart entre deux lattes (tools/build-map/02c, beltBetween)
local SLAT_SPEED_BASE = 2.5 -- studs / s du tapis au niveau 1, + SLAT_SPEED_PER_RATE par fruit / s
local SLAT_SPEED_PER_RATE = 1.6
-- Arrivee d'un proprietaire : ses niveaux arrivent d'un coup, pas d'effet pendant ce temps
local OWNER_QUIET_SECONDS = 8

local LevelLookController = {}

type LookPart = { part: BasePart, id: string, min: number, max: number, collide: boolean, extras: { Instance } }
type Slat = { part: BasePart, base: CFrame }
type BaseLook = {
	base: Model, -- l'ETAGE (porte les attributs Lv_<id>)
	parts: { [string]: { LookPart } }, -- id -> pieces
	boards: { { tile: Model, board: Model } },
	slats: { Slat },
	production: Instance?,
	slatOffset: number,
	known: { [string]: number }, -- dernier niveau vu par id (fondu seulement quand il monte)
	quietUntil: number, -- os.clock : pas d'effet avant (arrivee / depart du proprietaire)
	connections: { RBXScriptConnection }, -- coupees quand l'etage est detruit
}

local looks: { [Model]: BaseLook } = {}
local fades: { { part: BasePart, t: number } } = {}
local started = false
local fxFolder: Folder? = nil

local function camDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

-- Cache / montre une piece et ses textes, effets et lumieres.
local function setShown(look: LookPart, shown: boolean)
	look.part.LocalTransparencyModifier = if shown then 0 else 1
	look.part.CanCollide = shown and look.collide
	for _, extra in look.extras do
		if extra:IsA("SurfaceGui") or extra:IsA("BillboardGui") then
			extra.Enabled = shown
		elseif extra:IsA("ParticleEmitter") or extra:IsA("Light") or extra:IsA("Beam") or extra:IsA("Trail") then
			(extra :: any).Enabled = shown
		elseif extra:IsA("Decal") then
			extra.LocalTransparencyModifier = if shown then 0 else 1
		end
	end
end

local function sparkles(position: Vector3)
	local folder = fxFolder
	if folder == nil then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "LookSparkles"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 235, 120), Color3.fromRGB(255, 255, 255))
	emitter.Size = NumberSequence.new(0.9, 0)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 11)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Brightness = 3
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = folder
	emitter:Emit(22)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

local function levelOf(base: Model, id: string): number
	local value = base:GetAttribute("Lv_" .. id)
	return if type(value) == "number" then value else 0
end

-- Applique le niveau actuel aux pieces d'un id. `animate` : fondu + etincelles sur les nouvelles.
local function applyId(look: BaseLook, id: string, animate: boolean)
	local level = levelOf(look.base, id)
	local appeared: { BasePart } = {}
	local pads: { [Instance]: { BasePart } } = {} -- pads de decor qui apparaissent : pop
	for _, item in look.parts[id] or {} do
		local shown = level >= item.min and level <= item.max
		local wasShown = item.part.LocalTransparencyModifier < 1
		setShown(item, shown)
		if shown and not wasShown and animate then
			local parent = item.part.Parent
			if parent and parent.Name == "Pad" and parent:IsA("Model") then
				pads[parent] = pads[parent] or {}
				table.insert(pads[parent], item.part)
			else
				item.part.LocalTransparencyModifier = 1
				table.insert(fades, { part = item.part, t = 0 })
			end
			table.insert(appeared, item.part)
		end
	end
	for pad, list in pads do
		Reveal.Pop(pad, list)
	end
	if #appeared > 0 and camDistance(appeared[1].Position) <= FX_DISTANCE then
		local sum = Vector3.zero
		for _, part in appeared do
			sum += part.Position
		end
		sparkles(sum / #appeared)
		SoundFx.PlayAt("MachineBoing", sum / #appeared, nil, 1.3)
	end
end

-- Panneaux d'un mixeur verrouille (Blender 3 tant que le 2 n'est pas achete) : caches.
-- Collision d'origine des pieces d'un panneau cache (un panneau cache ne bloque personne)
local boardCollide: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Dernier etat de chaque panneau (pop quand il apparait)
local boardHidden: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function applyBoards(look: BaseLook)
	for _, entry in look.boards do
		-- Cache aussi tant que le mixeur n'est pas construit (achat seulement par E sur la machine)
		local hidden = entry.tile:GetAttribute("Locked") == true or entry.tile:GetAttribute("Unbuilt") == true
		local was = boardHidden[entry.board]
		boardHidden[entry.board] = hidden
		for _, item in entry.board:GetDescendants() do
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = if hidden then 1 else 0
				if boardCollide[item] == nil then
					boardCollide[item] = item.CanCollide
				end
				item.CanCollide = not hidden and boardCollide[item]
			elseif item:IsA("SurfaceGui") then
				item.Enabled = not hidden
			end
		end
		-- Il vient d'apparaitre (achat, etape FREE) : pop + etincelles, seulement dans SA base
		if was == true and not hidden and os.clock() > look.quietUntil and FloorWatch.IsMine(look.base) then
			local parts: { BasePart } = {}
			for _, item in entry.board:GetDescendants() do
				if item:IsA("BasePart") then
					table.insert(parts, item)
				end
			end
			local foot = Reveal.Pop(entry.board, parts)
			if foot and camDistance(foot) <= FX_DISTANCE then
				sparkles(foot + Vector3.new(0, 2, 0))
				SoundFx.PlayAt("Pickup", foot, nil, 0.8)
			end
		end
	end
end

-- Ajoute une piece de la base (au demarrage ou quand le streaming l'amene). Renvoie l'id si
-- c'est une piece de decor d'un niveau.
local function addItem(look: BaseLook, item: Instance): string?
	if item:IsA("BasePart") then
		local id = item:GetAttribute("LookId")
		local min = item:GetAttribute("LookLevel")
		if type(id) == "string" and type(min) == "number" then
			local max = item:GetAttribute("LookMaxLevel")
			local list = look.parts[id]
			if list == nil then
				list = {}
				look.parts[id] = list
			end
			local entry: LookPart = {
				part = item,
				id = id,
				min = min,
				max = if type(max) == "number" then max else math.huge,
				collide = item.CanCollide,
				extras = item:GetDescendants(),
			}
			table.insert(list, entry)
			local level = levelOf(look.base, id)
			setShown(entry, level >= entry.min and level <= entry.max)
			return id
		elseif item.Name == "Slat" and item.Parent and item.Parent.Name == "Conveyor" then
			table.insert(look.slats, { part = item, base = item.CFrame })
		end
	elseif item:IsA("Model") and item:GetAttribute("UpgradeId") ~= nil and item.Parent and item.Parent:IsA("Model") then
		local board = item.Parent :: Model
		if board:GetAttribute("HideWhenLocked") == true then
			table.insert(look.boards, { tile = item, board = board })
			item:GetAttributeChangedSignal("Locked"):Connect(function()
				applyBoards(look)
			end)
			item:GetAttributeChangedSignal("Unbuilt"):Connect(function()
				applyBoards(look)
			end)
		end
	end
	return nil
end

local function watchId(look: BaseLook, id: string)
	if look.known[id] ~= nil then
		return
	end
	local base = look.base
	look.known[id] = levelOf(base, id)
	local connection = base:GetAttributeChangedSignal("Lv_" .. id):Connect(function()
		local level = levelOf(base, id)
		-- Fondu seulement pour un achat (+1 niveau), pas a l'arrivee / au depart d'un joueur
		local before = look.known[id] or 0
		look.known[id] = level
		applyId(look, id, level == before + 1 and os.clock() > look.quietUntil)
	end)
	table.insert(look.connections, connection)
end

local function register(floor: Model, base: Model)
	if looks[floor] then
		return
	end
	local look: BaseLook = {
		base = floor,
		parts = {},
		boards = {},
		slats = {},
		production = floor:FindFirstChild("Production"),
		slatOffset = 0,
		known = {},
		quietUntil = os.clock() + OWNER_QUIET_SECONDS,
		connections = {},
	}
	looks[floor] = look
	-- OwnerUserId reste sur la base
	table.insert(
		look.connections,
		base:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			look.quietUntil = os.clock() + OWNER_QUIET_SECONDS
		end)
	)
	for _, item in floor:GetDescendants() do
		addItem(look, item)
	end
	for id in look.parts do
		watchId(look, id)
	end
	applyBoards(look)
	table.insert(
		look.connections,
		floor.DescendantAdded:Connect(function(item)
			local id = addItem(look, item)
			if id then
				watchId(look, id)
			end
			local boards = floor:FindFirstChild("Boards")
			if boards and item:IsA("BasePart") and item:IsDescendantOf(boards) then
				applyBoards(look)
			end
		end)
	)
	-- Etage detruit (achat de l'etage suivant, depart du proprietaire) : tout oublier
	FloorWatch.OnRemoved(floor, function()
		for _, connection in look.connections do
			connection:Disconnect()
		end
		table.clear(look.connections)
		if looks[floor] == look then
			looks[floor] = nil
		end
	end)
end

local function step(dt: number)
	-- Fondus des pieces qui apparaissent
	for i = #fades, 1, -1 do
		local fade = fades[i]
		fade.t += dt
		local alpha = math.clamp(fade.t / FADE_SECONDS, 0, 1)
		fade.part.LocalTransparencyModifier = 1 - alpha
		if alpha >= 1 then
			table.remove(fades, i)
		end
	end
	-- Lattes du tapis qui defilent
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, look in looks do
		local first = look.slats[1]
		if first == nil or camDistance(first.base.Position) > FX_DISTANCE then
			continue
		end
		if look.production == nil or look.production.Parent == nil then
			look.production = look.base:FindFirstChild("Production") -- streaming : arrive tard
		end
		local rate = look.production and look.production:GetAttribute("ConveyorRate")
		if type(rate) ~= "number" then
			continue -- base libre : le tapis ne tourne pas
		end
		look.slatOffset = (look.slatOffset + dt * (SLAT_SPEED_BASE + SLAT_SPEED_PER_RATE * rate)) % SLAT_SPACING
		for _, slat in look.slats do
			table.insert(parts, slat.part)
			table.insert(cframes, slat.base + slat.base.LookVector * look.slatOffset)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function LevelLookController.Init() end

function LevelLookController.Start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "LevelLookFx"
	folder.Parent = workspace
	fxFolder = folder
	-- Tout de suite (pas d'attente) : un etage qui vient d'etre achete ne doit pas montrer toutes
	-- ses variantes ; les pieces qui arrivent plus tard (streaming) passent par DescendantAdded.
	FloorWatch.Watch(register)
	RunService.RenderStepped:Connect(step)
end

return LevelLookController
