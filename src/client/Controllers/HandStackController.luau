--!strict
-- Jus portes (plateau sur la tete, comme les fruits) + effets "prendre / poser", client seulement.
-- Le serveur decide de tout (ProductionService / CustomerService) ; il pose sur le personnage :
--   HandJuices = "Apple;Orange;..." (jus portes, dans l'ordre de la pile).
-- Ici, pour chaque joueur proche :
--   1. un plateau de jus (couches de 3 x 3 gobelets ANCRES : aucune physique, rien ne peut tomber
--      par terre) suit la tete a chaque image, au-dessus du plateau des fruits s'il y en a un ;
--      il arrive en tombant, penche un peu quand on court et rebondit comme de la gelee ;
--   2. prendre (Feedback "TakeJuice", positions `from`) : les gobelets sautent un par un de la table
--      jusqu'a leur place dans la pile, "pop" de plus en plus aigu, la pile s'ecrase a chaque arrivee ;
--   3. poser : les gobelets du comptoir (attributs PopFrom / PopIndex / PopAt, CustomerService)
--      sautent un par un du haut de la pile jusqu'au comptoir ; la pile se vide au meme rythme.
-- Employes (modeles tagues "CarryPoseRig", ex. le Waiter, 2026-11-20) : meme plateau ; les gobelets
-- ajoutes sautent depuis l'attribut TakeFrom (Vector3, pose par WorkerService juste avant HandJuices).
-- Doc : docs/systems/chaine-production.md (section Mains)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local Util = Shared:WaitForChild("Util")
local HandStack = require(Util:WaitForChild("HandStack"))
local SoundFx = require(Util:WaitForChild("SoundFx")) :: any
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local ATTRIBUTE = "HandJuices"
local RIG_TAG = "CarryPoseRig" -- pose par NpcRig (employes) ; = TrayController
local MAX_DISTANCE = 200 -- au-dela, la pile n'est plus mise a jour (economie)
local FLY_SECONDS = 0.32 -- saut d'un gobelet (table -> mains, mains -> comptoir)
local FLY_STAGGER = 0.06 -- ecart entre deux gobelets
local FLY_HEIGHT = 3 -- hauteur de l'arc
local FROM_MAX_AGE = 1 -- positions de depart recues il y a plus longtemps : ignorees
local POP_MAX_AGE = 1.5 -- gobelets du comptoir poses il y a plus longtemps : pas d'animation
local LAND_IMPULSE = 1.4 -- ecrasement de la pile a l'arrivee d'un gobelet
local PITCH_STEP = 0.045 -- chaque "pop" un peu plus aigu
local TRAY_COLOR = Color3.fromRGB(226, 190, 140) -- = plateau des fruits (TrayController)
local RIM_COLOR = Color3.fromRGB(168, 120, 76)
local RIM_HEIGHT = 0.3
local TRAY_DROP = 1.4 -- le plateau arrive de 1.4 stud plus haut et rebondit
local MAX_LEAN = math.rad(9) -- penche max de la pile quand on court
local LEAN_PER_SPEED = math.rad(0.45) -- par stud/s

local HandStackController = {}

type Cup = {
	id: string,
	model: Model,
	parts: { BasePart },
	offsets: { CFrame }, -- chaque piece par rapport au pivot (pied du gobelet)
	index: number, -- place dans la pile (1 = en bas)
	flyFrom: Vector3?,
	flyT: number,
	flyDelay: number,
	pitch: number,
	removeAt: number?, -- gobelet qui part au comptoir : detruit a cette heure (os.clock)
}

type Stack = {
	character: Model,
	isLocal: boolean,
	isRig: boolean, -- employe (PNJ) : depart des gobelets = attribut TakeFrom
	cups: { Cup },
	leaving: { Cup },
	squash: Jelly.Spring,
	drop: Jelly.Spring, -- hauteur en plus du plateau (arrivee)
	tray: Model?,
	trayParts: { BasePart },
	trayOffsets: { CFrame },
	leanX: Jelly.Spring,
	leanZ: Jelly.Spring,
	connections: { RBXScriptConnection },
}

local started = false
local folder: Folder? = nil
local stacks: { [Model]: Stack } = {}
local localPlayer = Players.LocalPlayer
-- Positions de depart du dernier "TakeJuice" (si l'attribut arrive apres le remote)
local pendingFrom: { Vector3 }? = nil
local pendingAt = 0
-- Derniers gobelets ajoutes a la pile du joueur (si le remote arrive apres l'attribut)
local recentCups: { Cup } = {}
local recentAt = 0

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "HandStacks"
	created.Parent = workspace
	folder = created
	return created
end

local function makeCup(id: string, index: number): Cup?
	local ok, model = pcall(FruitModels.CreateCup, id, true)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local pivot = model:GetPivot()
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			table.insert(parts, part)
			table.insert(offsets, pivot:ToObjectSpace(part.CFrame))
		end
	end
	model.Parent = getFolder()
	return {
		id = id,
		model = model,
		parts = parts,
		offsets = offsets,
		index = index,
		flyFrom = nil,
		flyT = 0,
		flyDelay = 0,
		pitch = 1,
		removeAt = nil,
	}
end

-- Donne un vol (depart -> place dans la pile) aux gobelets qui viennent d'arriver.
local function launch(cups: { Cup }, from: { Vector3 })
	for k, cup in cups do
		local start = from[k]
		if start then
			cup.flyFrom = start
			cup.flyT = 0
			cup.flyDelay = (k - 1) * FLY_STAGGER
			cup.pitch = 1 + (k - 1) * PITCH_STEP
		end
	end
end

local function sync(stack: Stack)
	local ids = HandStack.Decode(stack.character:GetAttribute(ATTRIBUTE))
	local cups = stack.cups
	-- Partie commune (le bas de la pile ne bouge pas)
	local same = 0
	while same < #cups and same < #ids and cups[same + 1].id == ids[same + 1] do
		same += 1
	end
	-- Gobelets retires (le haut de la pile) : ils partent un par un, du haut vers le bas, au meme
	-- rythme que les gobelets qui sautent sur le comptoir.
	local now = os.clock()
	local order = 0
	for i = #cups, same + 1, -1 do
		local cup = table.remove(cups, i) :: Cup
		cup.removeAt = now + order * FLY_STAGGER
		order += 1
		table.insert(stack.leaving, cup)
	end
	-- Gobelets ajoutes
	local added: { Cup } = {}
	for i = same + 1, #ids do
		local cup = makeCup(ids[i], i)
		if cup then
			table.insert(cups, cup)
			table.insert(added, cup)
		end
	end
	if #added == 0 then
		return
	end
	if stack.isRig then
		local from = stack.character:GetAttribute("TakeFrom")
		if typeof(from) == "Vector3" then
			local list: { Vector3 } = {}
			for k = 1, #added do
				-- Petit ecart pour que les gobelets ne partent pas tous du meme point
				list[k] = from + Vector3.new(((k - 1) % 3 - 1) * 0.6, 0, 0)
			end
			launch(added, list)
		end
	elseif stack.isLocal then
		if pendingFrom and now - pendingAt <= FROM_MAX_AGE then
			launch(added, pendingFrom)
			pendingFrom = nil
		else
			recentCups = added
			recentAt = now
		end
	end
	-- Gobelets sans vol (autre joueur, reapparition) : la pile fait juste un petit rebond
	if added[1].flyFrom == nil then
		stack.squash.v -= LAND_IMPULSE
	end
end

local function onTakeJuice(payload: any)
	if typeof(payload) ~= "table" or type(payload.from) ~= "table" then
		return
	end
	local from: { Vector3 } = {}
	for _, position in payload.from do
		if typeof(position) == "Vector3" and position.Magnitude < 1e6 then
			table.insert(from, position)
		end
		if #from >= 40 then
			break
		end
	end
	local now = os.clock()
	if #recentCups > 0 and now - recentAt <= FROM_MAX_AGE then
		launch(recentCups, from)
		recentCups = {}
	else
		pendingFrom = from
		pendingAt = now
	end
end

local function removeStack(character: Model)
	local stack = stacks[character]
	if stack == nil then
		return
	end
	stacks[character] = nil
	for _, connection in stack.connections do
		connection:Disconnect()
	end
	for _, cup in stack.cups do
		cup.model:Destroy()
	end
	for _, cup in stack.leaving do
		cup.model:Destroy()
	end
	if stack.tray then
		stack.tray:Destroy()
	end
end

local function addCharacter(player: Player?, character: Model)
	if stacks[character] then
		return
	end
	local stack: Stack = {
		character = character,
		isLocal = player ~= nil and player == localPlayer,
		isRig = player == nil,
		cups = {},
		leaving = {},
		squash = Jelly.Spring(320, 11),
		drop = Jelly.Spring(260, 13),
		tray = nil,
		trayParts = {},
		trayOffsets = {},
		leanX = Jelly.Spring(90, 7),
		leanZ = Jelly.Spring(90, 7),
		connections = {},
	}
	stacks[character] = stack
	table.insert(
		stack.connections,
		character:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			sync(stack)
		end)
	)
	table.insert(
		stack.connections,
		character.AncestryChanged:Connect(function()
			if character.Parent == nil then
				removeStack(character)
			end
		end)
	)
	sync(stack)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		addCharacter(player, character)
	end)
	if player.Character then
		addCharacter(player, player.Character)
	end
end

---------------------------------------------------------------------------------------------
-- Mise a jour de chaque image

local partsBuffer: { BasePart } = {}
local cframesBuffer: { CFrame } = {}

local function place(cup: Cup, pivot: CFrame)
	for k, part in cup.parts do
		table.insert(partsBuffer, part)
		table.insert(cframesBuffer, pivot * cup.offsets[k])
	end
end

-- Plateau vide (dessus = pivot du modele), memes couleurs que le plateau des fruits.
local function makeTray(stack: Stack)
	local model = Instance.new("Model")
	model.Name = "JuiceTray"
	local size = HandStack.TraySize
	local thick = HandStack.TrayThick
	local half = size / 2
	local out = half + 0.05
	local w = 0.22
	local rimH = thick + 0.1 + RIM_HEIGHT
	local rimY = -thick + rimH / 2 - 0.05
	local pieces = {
		{ "TrayBase", Vector3.new(size, thick, size), CFrame.new(0, -thick / 2, 0), TRAY_COLOR },
		{ "Rim", Vector3.new(out * 2, rimH, w), CFrame.new(0, rimY, -out + w / 2), RIM_COLOR },
		{ "Rim", Vector3.new(out * 2, rimH, w), CFrame.new(0, rimY, out - w / 2), RIM_COLOR },
		{ "Rim", Vector3.new(w, rimH - 0.04, (out - w) * 2), CFrame.new(-out + w / 2, rimY - 0.02, 0), RIM_COLOR },
		{ "Rim", Vector3.new(w, rimH - 0.04, (out - w) * 2), CFrame.new(out - w / 2, rimY - 0.02, 0), RIM_COLOR },
	}
	table.clear(stack.trayParts)
	table.clear(stack.trayOffsets)
	for _, piece in pieces do
		local part = Instance.new("Part")
		part.Name = piece[1] :: string
		part.Size = piece[2] :: Vector3
		part.Color = piece[4] :: Color3
		part.Material = Enum.Material.Plastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		table.insert(stack.trayParts, part)
		table.insert(stack.trayOffsets, piece[3] :: CFrame)
	end
	model.Parent = getFolder()
	stack.tray = model
	stack.drop.x = TRAY_DROP
	stack.drop.v = 0
end

-- Dessus du plateau (tete + decalage, arrivee, penche).
local function trayTop(stack: Stack, head: BasePart): CFrame
	local fruits = stack.character:GetAttribute("TrayFruits")
	local hasFruits = type(fruits) == "string" and fruits ~= ""
	return head.CFrame * HandStack.TrayOffset(head, hasFruits) * CFrame.new(0, stack.drop.x, 0)
		* CFrame.Angles(stack.leanZ.x, 0, stack.leanX.x)
end

-- Place du gobelet n, avec l'ecrasement du moment.
local function slotCFrame(stack: Stack, top: CFrame, index: number): CFrame
	local slot = HandStack.SlotOffset(index)
	local scaleY = math.max(0.55, 1 + stack.squash.x)
	return top * CFrame.new(slot.X, slot.Y * scaleY, slot.Z)
end

local function updateStack(stack: Stack, root: BasePart, head: BasePart, dt: number, now: number)
	-- Penche : la pile "traine" un peu derriere quand on court (ressort -> balancement a l'arret)
	local velocity = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	stack.leanX.target = math.clamp(velocity.X * LEAN_PER_SPEED, -MAX_LEAN, MAX_LEAN)
	stack.leanZ.target = math.clamp(-velocity.Z * LEAN_PER_SPEED, -MAX_LEAN, MAX_LEAN)
	Jelly.Step(stack.squash, dt)
	Jelly.Step(stack.drop, dt)
	Jelly.Step(stack.leanX, dt)
	Jelly.Step(stack.leanZ, dt)

	if #stack.cups == 0 and #stack.leaving == 0 then
		if stack.tray then
			stack.tray:Destroy()
			stack.tray = nil
		end
		return
	end
	if stack.tray == nil then
		makeTray(stack)
	end
	local top = trayTop(stack, head)
	for k, part in stack.trayParts do
		table.insert(partsBuffer, part)
		table.insert(cframesBuffer, top * stack.trayOffsets[k])
	end

	for _, cup in stack.cups do
		local target = slotCFrame(stack, top, cup.index)
		local from = cup.flyFrom
		if from == nil then
			place(cup, target)
			continue
		end
		cup.flyT += dt
		local u = math.clamp((cup.flyT - cup.flyDelay) / FLY_SECONDS, 0, 1)
		if u >= 1 then
			cup.flyFrom = nil
			place(cup, target)
			stack.squash.v -= LAND_IMPULSE
			if stack.isLocal then
				SoundFx.Play("CounterDrop", nil, cup.pitch) -- meme son que le comptoir
			end
			continue
		end
		local eased = 1 - (1 - u) * (1 - u)
		local position = from:Lerp(target.Position, eased) + Vector3.new(0, FLY_HEIGHT * 4 * u * (1 - u), 0)
		local spin = (1 - u) * math.pi * 2
		place(cup, CFrame.new(position) * target.Rotation * CFrame.Angles(spin, 0, 0))
	end

	for i = #stack.leaving, 1, -1 do
		local cup = stack.leaving[i]
		if now >= (cup.removeAt :: number) then
			cup.model:Destroy()
			table.remove(stack.leaving, i)
		else
			place(cup, slotCFrame(stack, top, cup.index))
		end
	end
end

local function onRender(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	table.clear(partsBuffer)
	table.clear(cframesBuffer)
	for character, stack in stacks do
		if #stack.cups == 0 and #stack.leaving == 0 and stack.tray == nil then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local head = character:FindFirstChild("Head")
		if root == nil or not root:IsA("BasePart") or head == nil or not head:IsA("BasePart") then
			continue
		end
		if (root.Position - camPos).Magnitude > MAX_DISTANCE then
			continue
		end
		updateStack(stack, root, head, dt, now)
	end
	if #partsBuffer > 0 then
		workspace:BulkMoveTo(partsBuffer, cframesBuffer, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------------------------
-- Comptoir : les gobelets poses sautent du plateau (tete) jusqu'a leur place

type Hop = { model: Model, from: Vector3, to: CFrame, t: number, delay: number, pitch: number }
local hops: { Hop } = {}

local function onCounterCup(item: Instance)
	if not item:IsA("Model") then
		return
	end
	local from = item:GetAttribute("PopFrom")
	local index = item:GetAttribute("PopIndex")
	local at = item:GetAttribute("PopAt")
	if typeof(from) ~= "Vector3" or type(at) ~= "number" or workspace:GetServerTimeNow() - at > POP_MAX_AGE then
		return
	end
	local to = item:GetPivot()
	local camera = workspace.CurrentCamera
	-- Le gobelet peut voler vers le comptoir d'un autre etage : on l'anime si le depart OU l'arrivee est proche
	local eye = camera and camera.CFrame.Position
	if eye and (eye - to.Position).Magnitude > MAX_DISTANCE and (eye - from).Magnitude > MAX_DISTANCE then
		return
	end
	local k = if type(index) == "number" then math.clamp(index, 1, 60) else 1
	item:PivotTo(CFrame.new(from) * to.Rotation)
	table.insert(hops, {
		model = item,
		from = from,
		to = to,
		t = 0,
		delay = (k - 1) * FLY_STAGGER,
		pitch = 1 + (k - 1) * PITCH_STEP,
	})
end

local function updateHops(dt: number)
	for i = #hops, 1, -1 do
		local hop = hops[i]
		if hop.model.Parent == nil then
			table.remove(hops, i)
			continue
		end
		hop.t += dt
		local u = math.clamp((hop.t - hop.delay) / FLY_SECONDS, 0, 1)
		if u >= 1 then
			hop.model:PivotTo(hop.to)
			table.remove(hops, i)
			SoundFx.PlayAt("CounterDrop", hop.to.Position, nil, hop.pitch)
			local parts: { BasePart } = {}
			for _, part in hop.model:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(parts, part)
				end
			end
			Jelly.Boing(hop.model, parts, hop.to, 0.7)
			continue
		end
		local eased = 1 - (1 - u) * (1 - u)
		local position = hop.from:Lerp(hop.to.Position, eased) + Vector3.new(0, FLY_HEIGHT * 4 * u * (1 - u), 0)
		local spin = (1 - u) * math.pi * 2
		hop.model:PivotTo(CFrame.new(position) * hop.to.Rotation * CFrame.Angles(spin, 0, 0))
	end
end

-- Gobelets poses sur le comptoir d'un etage ouvert (FloorK.Dynamic.Counter)
local function watchFloor(floor: Model)
	task.spawn(function()
		local dynamic = floor:FindFirstChild("Dynamic") or floor:WaitForChild("Dynamic", 10)
		if dynamic == nil then
			return
		end
		local function watchFolder(child: Instance)
			if child.Name == "Counter" and child:IsA("Folder") then
				child.ChildAdded:Connect(onCounterCup)
			end
		end
		dynamic.ChildAdded:Connect(watchFolder)
		for _, child in dynamic:GetChildren() do
			watchFolder(child)
		end
	end)
end

---------------------------------------------------------------------------------------------

function HandStackController.Init() end

function HandStackController.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- Employes (Waiter) : meme plateau de jus que les joueurs
	local function addRig(instance: Instance)
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
			addCharacter(nil, instance)
		end
	end
	for _, instance in CollectionService:GetTagged(RIG_TAG) do
		addRig(instance)
	end
	CollectionService:GetInstanceAddedSignal(RIG_TAG):Connect(addRig)
	RunService.RenderStepped:Connect(function(dt)
		onRender(dt)
		updateHops(dt)
	end)
	-- Les connexions sont sur les dossiers de l'etage : detruites avec lui
	FloorWatch.Watch(watchFloor)
	task.spawn(function()
		local event = Remotes.WaitClientEvent("Feedback")
		if event then
			event.OnClientEvent:Connect(function(kind, payload)
				if kind == "TakeJuice" then
					onTakeJuice(payload)
				end
			end)
		end
	end)
end

return HandStackController
