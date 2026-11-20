--!strict
-- Effets des machines de l'usine, cote client seulement (rien n'est decide ici : le serveur
-- achete, construit et produit ; ce module ne fait que montrer). Lit les attributs poses par le
-- serveur (UpgradeService, ProductionService) :
--   Machines.<id> : Built, BuildStamp (construction piece par piece), Bought (pop), Denied (rouge)
--   Boards.*.<id> : Price, ComingSoon, Bought, Denied
-- Construction : les pieces tombent une par une puis la machine fait "boing" (Fx/Jelly) ; chaque
-- amelioration d'une machine deja construite la fait aussi rebondir en gelee.
-- Le mixeur est anime par BlenderFxController, l'arbre par TreeFxController.
-- Aussi : pieces qui tournent (attribut Spin), machines fantomes de SA base qui brillent en bleu
-- (Highlight qui pulse), etiquettes / pads / boutons des autres bases caches localement, fruits du
-- Fruit Picker qui volent vers les caisses (WorldFx "FruitsToBins", 1er argument = l'etage).
-- Tour d'etages : tout est inscrit PAR ETAGE ouvert (Util/FloorWatch) et oublie quand l'etage est
-- detruit (achat de l'etage suivant, depart du proprietaire).
-- (La fleche jaune du "prochain achat" a ete retiree le 2026-11-19 soir : on ne comprenait pas a
-- quoi elle servait et elle rentrait dans les panneaux. Le guidage viendra en phase 2.)
-- Doc : docs/systems/ameliorations-employes.md, docs/systems/chaine-production.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gameplay = require(Shared:WaitForChild("Config"):WaitForChild("Gameplay")) :: any
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits")) :: any
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local MachineModels = require(Shared:WaitForChild("Util"):WaitForChild("MachineModels"))
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local FX_DISTANCE = 150 -- au-dela, pas d'animation (economie)
local BUILD_RISE = 7 -- les pieces tombent de cette hauteur a la construction
local BUILD_TOTAL_SECONDS = 1.1
local DENY_COLOR = Color3.fromRGB(255, 60, 60)
local GHOST_GLOW = Color3.fromRGB(110, 185, 255)
local TAG_MIN_DISTANCE = 16 -- studs : plus pres, les etiquettes "nom + prix" ne grossissent plus

local MachineFxController = {}

local started = false
local fxFolder: Folder? = nil
local sounds: { [string]: Sound } = {}

type SpinEntry = { part: BasePart, machine: Model, base: CFrame, speed: number, angle: number }
type ClickEntry = { click: ClickDetector, range: number, floor: Model, machine: Model? }

local spins: { SpinEntry } = {}
local clicks: { ClickEntry } = {}
local machineEntries: { { machine: Model, floor: Model } } = {}
local glows: { [Model]: Highlight } = {} -- machine fantome de SA base -> Highlight bleu
local busyUntil: { [Instance]: number } = {} -- machine en cours de construction (pas de spin / bob)
local denyColors: { [BasePart]: Color3 } = {}

local function camDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

local function playSound(name: string, volume: number?)
	local template = sounds[name]
	if template == nil or not SoundFx.IsEnabled() then -- reglage Sons (menu Settings)
		return
	end
	local sound = template:Clone()
	if volume then
		sound.Volume = volume
	end
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function sparkles(position: Vector3, color: Color3, count: number)
	local folder = fxFolder
	if folder == nil then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = folder
	emitter:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- Etage de la base du joueur local (OwnerUserId est sur la base).
local function isMine(floor: Model): boolean
	return FloorWatch.IsMine(floor)
end

---------------------------------------------------------------------------------------------
-- Construction, achat, refus

local function buildParts(machine: Model): { BasePart }
	local list: { BasePart } = {}
	local build = machine:FindFirstChild("Build")
	for _, item in (if build then build:GetDescendants() else {}) do
		if item:IsA("BasePart") then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a: BasePart, b: BasePart)
		return a.Position.Y < b.Position.Y
	end)
	return list
end

-- Boing "gelee" sur toute la machine (pivot = bas de la machine, les pieces suivent).
-- Les pieces qui tournent s'arretent pendant ce temps (Jelly.IsBusy).
local function boing(machine: Model, strength: number)
	local build = machine:FindFirstChild("Build")
	if build == nil or not build:IsA("Model") then
		return
	end
	local visible: { BasePart } = {}
	for _, p in buildParts(machine) do
		if p.Transparency < 1 then
			table.insert(visible, p)
		end
	end
	if #visible == 0 then
		return
	end
	local cf, size = build:GetBoundingBox()
	if camDistance(cf.Position) > FX_DISTANCE then
		return
	end
	Jelly.Boing(machine, visible, cf * CFrame.new(0, -size.Y / 2, 0), strength)
	SoundFx.PlayAt("MachineBoing", cf.Position)
end

-- La machine vient d'etre achetee : ses pieces tombent du ciel une par une.
local function playBuild(machine: Model)
	local parts = buildParts(machine)
	if #parts == 0 then
		return
	end
	local cf, size = machine:GetBoundingBox()
	if camDistance(cf.Position) > FX_DISTANCE then
		return
	end
	local stagger = math.min(0.05, BUILD_TOTAL_SECONDS / #parts)
	busyUntil[machine] = os.clock() + stagger * #parts + 0.6
	for i, p in parts do
		local finalCFrame = p.CFrame
		local finalTransparency = p.Transparency
		p.CFrame = finalCFrame + Vector3.new(0, BUILD_RISE, 0)
		p.Transparency = 1
		task.delay((i - 1) * stagger, function()
			if p.Parent == nil then
				return
			end
			TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				CFrame = finalCFrame,
				Transparency = finalTransparency,
			}):Play()
		end)
	end
	task.delay(stagger * #parts + 0.3, function()
		sparkles(cf.Position + Vector3.new(0, size.Y / 2, 0), Color3.fromRGB(255, 230, 90), 45)
	end)
	-- Toutes les pieces sont posees : la machine s'ecrase et rebondit comme de la gelee
	task.delay(stagger * #parts + 0.4, function()
		if machine.Parent ~= nil then
			boing(machine, 1.2)
		end
	end)
	playSound("Purchase")
end

local function flashRed(part: BasePart)
	local original = denyColors[part] or part.Color
	denyColors[part] = original
	part.Color = DENY_COLOR
	task.delay(Gameplay.PadDenyFlashSeconds, function()
		part.Color = original
		denyColors[part] = nil
	end)
end

---------------------------------------------------------------------------------------------
-- Inscription des etages

local function watchCounter(instance: Instance, attribute: string, callback: () -> ())
	instance:GetAttributeChangedSignal(attribute):Connect(callback)
end

local function forgetFloor(floor: Model)
	for i = #spins, 1, -1 do
		if spins[i].machine:IsDescendantOf(floor) or spins[i].machine.Parent == nil then
			table.remove(spins, i)
		end
	end
	for i = #clicks, 1, -1 do
		if clicks[i].floor == floor then
			table.remove(clicks, i)
		end
	end
	for i = #machineEntries, 1, -1 do
		local entry = machineEntries[i]
		if entry.floor == floor then
			local glow = glows[entry.machine]
			if glow then
				glow:Destroy()
				glows[entry.machine] = nil
			end
			busyUntil[entry.machine] = nil
			table.remove(machineEntries, i)
		end
	end
end

local function registerFloor(floor: Model)
	-- Streaming : laisse arriver les dossiers de l'etage (absents = rien a animer)
	if floor:FindFirstChild("Machines") == nil then
		floor:WaitForChild("Machines", 10)
	end
	if floor:FindFirstChild("Boards") == nil then
		floor:WaitForChild("Boards", 5)
	end
	if floor.Parent == nil then
		return
	end
	local base = floor -- (nom garde : les fonctions ci-dessous travaillent sur l'etage)
	-- Machines (Machines.<id>, et les mixeurs 2-4 + leurs operateurs dans Production.Blenders)
	for _, machine in MachineModels.List(base) do
		local build = machine:FindFirstChild("Build")
		for _, item in (if build then build:GetDescendants() else {}) do
			if item:IsA("BasePart") then
				local speed = item:GetAttribute("Spin")
				if type(speed) == "number" then
					table.insert(spins, { part = item, machine = machine, base = item.CFrame, speed = speed, angle = 0 })
				end
			end
		end
		local pad = machine:FindFirstChild("Pad")
		local padTop = pad and pad:FindFirstChild("PadTop")
		table.insert(machineEntries, { machine = machine, floor = base })
		watchCounter(machine, "BuildStamp", function()
			playBuild(machine)
		end)
		watchCounter(machine, "Bought", function()
			-- Premier achat : la construction s'en charge (BuildStamp arrive avant Bought)
			if (busyUntil[machine] or 0) > os.clock() or machine:GetAttribute("Built") ~= true then
				return
			end
			boing(machine, 1)
			local cf = machine:GetBoundingBox()
			sparkles(cf.Position, Color3.fromRGB(255, 230, 90), 18)
		end)
		watchCounter(machine, "Denied", function()
			if isMine(base) and padTop and padTop:IsA("BasePart") then
				flashRed(padTop)
			end
		end)
	end

	-- Tuiles des panneaux
	local boards = base:FindFirstChild("Boards")
	for _, item in (if boards then boards:GetDescendants() else {}) do
		if not item:IsA("Model") or item:GetAttribute("UpgradeId") == nil then
			continue
		end
		-- Bouton d'achat = la tuile entiere (style 2026-11-20) ; BuyButton = ancien panneau
		local buy = item:FindFirstChild("BuyButton") or item:FindFirstChild("Tile")
		for _, name in { "BuyButton", "Tile", "RobuxButton" } do
			local button = item:FindFirstChild(name)
			local click = button and button:FindFirstChildOfClass("ClickDetector")
			if click then
				table.insert(clicks, { click = click, range = click.MaxActivationDistance, floor = base, machine = nil })
			end
		end
		if buy and buy:IsA("BasePart") then
			-- Rebond et fond rouge de la tuile : BoardFxController (ressort, survol, clic)
			watchCounter(item, "Bought", function()
				if isMine(base) then
					sparkles(buy.Position, Color3.fromRGB(120, 255, 90), 25)
					playSound("Purchase")
				end
			end)
		end
	end

	-- Etage detruit : retirer ses entrees (spins, clics, machines, contours bleus)
	FloorWatch.OnRemoved(floor, function()
		forgetFloor(floor)
	end)
end

---------------------------------------------------------------------------------------------
-- Pads / boutons des autres bases : desactives localement (le serveur verifie de toute facon)

-- Etiquette flottante d'une machine : "Tag" du pad (employes) ou "MachineTag" (machines).
local function findTag(machine: Model): BillboardGui?
	local pad = machine:FindFirstChild("Pad")
	local padTop = pad and pad:FindFirstChild("PadTop")
	local tag = padTop and padTop:FindFirstChild("Tag")
	if tag == nil then
		local anchor = machine:FindFirstChild("PromptAnchor")
		tag = anchor and anchor:FindFirstChild("MachineTag")
	end
	return if tag and tag:IsA("BillboardGui") then tag else nil
end

local function setGlow(machine: Model, wanted: boolean)
	local glow = glows[machine]
	if wanted and glow == nil then
		local build = machine:FindFirstChild("Build")
		if build == nil then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "GhostGlow"
		highlight.Adornee = build
		-- Contour clair + un peu de bleu par-dessus la machine (style "objet a acheter")
		highlight.FillColor = GHOST_GLOW
		highlight.OutlineColor = Color3.fromRGB(205, 235, 255)
		highlight.FillTransparency = 0.75
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = fxFolder
		glows[machine] = highlight
	elseif not wanted and glow ~= nil then
		glow:Destroy()
		glows[machine] = nil
	end
end

local function refreshOwnership()
	for _, entry in clicks do
		local built = entry.machine ~= nil and entry.machine:GetAttribute("Built") == true
		local wanted = if isMine(entry.floor) and not built then entry.range else 0
		if entry.click.MaxActivationDistance ~= wanted then
			entry.click.MaxActivationDistance = wanted
		end
	end
	for _, entry in machineEntries do
		local ghost = entry.machine:GetAttribute("Built") ~= true
		-- Pad "Upgrade Tree" (Repeat) : il reste a acheter tant qu'il n'est pas au max
		local price = entry.machine:GetAttribute("Price")
		local repeatPad = entry.machine:GetAttribute("Repeat") == true and type(price) == "number" and price >= 0
		-- Verrouillee (mixeur suivant pas encore achete...) : ni etiquette ni contour
		local wanted = isMine(entry.floor) and (ghost or repeatPad) and entry.machine:GetAttribute("Locked") ~= true
		local tag = findTag(entry.machine)
		if tag and tag.Enabled ~= wanted then
			tag.Enabled = wanted
		end
		-- De pres, l'etiquette arrete de grossir (elle ne cache plus l'ecran)
		if tag and tag.DistanceLowerLimit ~= TAG_MIN_DISTANCE then
			tag.DistanceLowerLimit = TAG_MIN_DISTANCE
		end
		setGlow(entry.machine, wanted and ghost and entry.machine:GetAttribute("ComingSoon") ~= true and (busyUntil[entry.machine] or 0) <= os.clock())
	end
end

---------------------------------------------------------------------------------------------
-- Fruits du Fruit Picker qui volent jusqu'a leur caisse (vu par tous les joueurs proches)

local function flyFruitsToBins(floor: Model, from: Vector3, ids: { string })
	local folder = fxFolder
	local production = floor:FindFirstChild("Production")
	local bins = production and production:FindFirstChild("Bins")
	if folder == nil or bins == nil or camDistance(from) > FX_DISTANCE then
		return
	end
	local floorIndex = FloorWatch.IndexOf(floor)
	for i, fruitId in ids do
		if i > 20 then
			break
		end
		-- Caisse Bin<1..10> seulement sur l'etage de la rarete du fruit
		local fruit = Fruits.ById[fruitId]
		local bin = if fruit and fruit.floor == floorIndex then bins:FindFirstChild("Bin" .. fruit.rarity) else nil
		if bin == nil or not bin:IsA("BasePart") then
			continue
		end
		task.delay((i - 1) * 0.06, function()
			if not bin:IsDescendantOf(workspace) then
				return
			end
			local ok, model = pcall(FruitModels.CreateFruit, fruitId, true)
			if not ok then
				return
			end
			local target = bin.Position + Vector3.new(0, bin.Size.Y / 2 + 0.6, 0)
			local peak = (from + target) / 2 + Vector3.new(0, 4, 0)
			model:PivotTo(CFrame.new(from))
			model.Parent = folder
			local elapsed = 0
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function(dt: number)
				elapsed += dt
				local t = math.min(elapsed / 0.5, 1)
				local pos = from:Lerp(peak, t):Lerp(peak:Lerp(target, t), t)
				model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, elapsed * 8, 0))
				if t >= 1 then
					connection:Disconnect()
					model:Destroy()
					SoundFx.PlayAt("Deposit", target)
				end
			end)
		end)
	end
end

-- 1er argument = l'etage (Model Bases.BaseN.Floors.FloorK)
local function onWorldFx(floor: any, kind: any, payload: any)
	if kind ~= "FruitsToBins" or typeof(floor) ~= "Instance" or not floor:IsA("Model") or type(payload) ~= "table" then
		return
	end
	local bases = workspace:FindFirstChild("Bases")
	if bases == nil or not floor:IsDescendantOf(bases) or FloorWatch.BaseOf(floor) == nil then
		return
	end
	local from = payload.from
	local ids = payload.ids
	if typeof(from) ~= "Vector3" or type(ids) ~= "table" then
		return
	end
	local clean: { string } = {}
	for _, id in ids do
		if type(id) == "string" and Fruits.ById[id] ~= nil then
			table.insert(clean, id)
		end
		if #clean >= 20 then
			break
		end
	end
	flyFruitsToBins(floor, from, clean)
end

---------------------------------------------------------------------------------------------

function MachineFxController.Init() end

function MachineFxController.Start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "MachineFx"
	folder.Parent = workspace
	fxFolder = folder

	local assets = Shared:WaitForChild("Assets", 10)
	local soundFolder = assets and assets:WaitForChild("UISounds", 10)
	for _, name in { "Purchase", "Click" } do
		local sound = soundFolder and soundFolder:FindFirstChild(name)
		if sound and sound:IsA("Sound") then
			sounds[name] = sound
		end
	end

	FloorWatch.Watch(function(floor)
		registerFloor(floor)
	end)
	task.spawn(function()
		local event = Remotes.WaitClientEvent("WorldFx")
		if event then
			event.OnClientEvent:Connect(onWorldFx)
		end
	end)

	-- Proprietaires (etiquettes, contours bleus) : 2 fois par seconde suffit
	task.spawn(function()
		while true do
			refreshOwnership()
			task.wait(0.5)
		end
	end)

	local clock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		clock += dt
		local now = os.clock()
		-- Pieces qui tournent (arroseur...)
		for _, entry in spins do
			if entry.machine:GetAttribute("Built") ~= true or (busyUntil[entry.machine] or 0) > now or Jelly.IsBusy(entry.machine) then
				continue
			end
			if camDistance(entry.base.Position) > FX_DISTANCE then
				continue
			end
			entry.angle += math.rad(entry.speed) * dt
			entry.part.CFrame = entry.base * CFrame.Angles(0, entry.angle, 0)
		end
		-- Machines fantomes de SA base : la lueur bleue pulse doucement
		local pulse = 0.72 + 0.12 * math.sin(clock * 3)
		for _, glow in glows do
			glow.FillTransparency = pulse
		end
	end)
end

return MachineFxController
