--!strict
-- Employes R6 visibles qui travaillent vraiment (serveur) :
--   * Fruit Picker (Collector) : marche jusqu'aux fruits au sol, les pose sur son plateau (tete)
--     (jusqu'a PickerCarry fruits : 2 -> 6), les porte a l'etagere et les pose dans les caisses ;
--     sa vitesse (marche et pauses) = Gameplay.PickerBaseSpeed x PickerSpeed de l'etage. Les deux
--     niveaux viennent du panneau Fruit Picker et s'appliquent tout de suite a l'achat ;
--   * Blender Operator (Operator1..4, un par mixeur) : debout devant le panneau de SON mixeur
--     (marqueur Production.Blenders.BlenderN.BlenderNOperator) ; quand le bol est plein (ou ne
--     bouge plus depuis OperatorIdleBlendSeconds), il attend OperatorReactSeconds puis appuie sur
--     le bouton vert (petit geste du bras, NpcRig.Press) -> ProductionService.OperatorBlend ;
--     quand les jus sortent (2026-11-27, onPour), il se tourne vers la table, tend les bras et les
--     gobelets sautent de ses mains (NpcRig.Deposit), puis il se retourne vers son bouton ;
--   * Waiter (2026-11-20, de retour, argent du jeu) : volontairement LENT (Gameplay.WaiterBaseSpeed).
--     Il attend pres de la table a jus (Markers.ServerHome) ; des qu'il y a Gameplay.WaiterCarry jus
--     (ou des jus qui attendent depuis WaiterWaitSeconds), il va devant la table (ServerPallet), les
--     prend sur son plateau (attribut HandJuices, comme le joueur ; TakeFrom = d'ou ils sautent), les
--     porte au comptoir (ServerCounter) et les pose (CustomerService.AddToCounter, animation PopFrom).
--     Une fois embauche, son pad vert laisse la place au pad violet "Waiter Speed x10" (pass Robux,
--     attribut joueur "SpeedBoost" pose par PassPadService) : vitesse du Waiter x
--     Gameplay.WaiterSpeedPassMultiplier (marche et pauses), sur tous les etages, tout de suite.
-- Chaque etage a ses employes (Data.Floors[n].Upgrades). Un employe apparait des qu'il est embauche
-- (UpgradeService.OnBought) ou au demarrage de l'etage (FloorService.OnFloorStarted).
-- Rien n'est sauvegarde sauf le niveau d'embauche (Data.Floors[n].Upgrades, ecrit par UpgradeService).
-- Doc : docs/systems/ameliorations-employes.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Gameplay"))
local Upgrades = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Upgrades"))

local HandStack = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("HandStack"))

local NpcRig = require(script.Parent.Parent.Lib.NpcRig)
local CustomerService = require(script.Parent.CustomerService)
local FloorService = require(script.Parent.FloorService)
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)
local TreeService = require(script.Parent.TreeService)
local UpgradeService = require(script.Parent.UpgradeService)

local WorkerService = {}

local ROLES = { "Collector", "Waiter", "Operator1", "Operator2", "Operator3", "Operator4" }

type Worker = {
	role: string,
	npc: NpcRig.Npc,
	thread: thread?,
	active: boolean,
	speed: number, -- multiplicateur de vitesse (Fruit Picker : PickerBaseSpeed x PickerSpeed, sinon 1)
	carry: number, -- fruits portes au maximum (Fruit Picker : PickerCarry, sinon 0)
	busyUntil: number, -- operateur : en train de poser les jus sur la table jusqu'a cette heure (os.clock)
}

type FloorWorkers = {
	player: Player,
	floor: Model, -- etage (Floors.FloorN) : employes de CET etage
	index: number,
	folder: Folder,
	workers: { [string]: Worker },
	reserved: { [Model]: boolean }, -- fruits vises par le Fruit Picker
	active: boolean,
}

local floors: { [Model]: FloorWorkers } = {}
local rigsReady = false

-- Point au sol d'un marqueur de l'etage (Markers.<name>), sinon d'une piece de secours.
local function markerPoint(floor: Model, name: string, fallback: string?): Vector3?
	local markers = floor:FindFirstChild("Markers")
	local part = markers and markers:FindFirstChild(name)
	if (part == nil or not part:IsA("BasePart")) and fallback then
		local machines = floor:FindFirstChild("Machines")
		local machine = machines and machines:FindFirstChild(fallback)
		local pad = machine and machine:FindFirstChild("Pad")
		part = pad and pad:FindFirstChild("PadTop")
	end
	if part and part:IsA("BasePart") then
		return part.Position - Vector3.new(0, part.Size.Y / 2, 0)
	end
	return nil
end

local function pause(worker: Worker)
	if worker.active then
		task.wait(Gameplay.EmployeePauseSeconds / worker.speed)
	end
end

-- Rien a faire : l'employe retourne a son poste et regarde son travail (pas de marche sur place).
local function waitAtHome(worker: Worker, home: Vector3?, lookAt: Vector3?, seconds: number)
	local npc = worker.npc
	if home then
		NpcRig.MoveTo(npc, home, function(): boolean
			return worker.active
		end)
	end
	if lookAt and worker.active then
		NpcRig.Face(npc, lookAt)
	end
	if worker.active then
		task.wait(seconds)
	end
end

-- Centre de l'arbre du verger (le Fruit Picker le regarde quand il attend).
local function treePoint(floor: Model): Vector3?
	local tree = floor:FindFirstChild("Tree")
	local anchor = tree and tree:FindFirstChild("FruitArea")
	return if anchor and anchor:IsA("BasePart") then anchor.Position else nil
end

-- Centre des caisses a fruits de l'etage (Production.Bins) : le Fruit Picker s'y tourne pour deposer.
local function binsPoint(floor: Model): Vector3?
	local production = floor:FindFirstChild("Production")
	local bins = production and production:FindFirstChild("Bins")
	if bins == nil then
		return nil
	end
	local sum, count = Vector3.zero, 0
	for _, part in bins:GetChildren() do
		if part:IsA("BasePart") then
			sum += part.Position
			count += 1
		end
	end
	return if count > 0 then sum / count else nil
end

-- Mixeur N de l'etage (Production.Blenders.BlenderN).
local function blenderModel(floor: Model, index: number): Model?
	local production = floor:FindFirstChild("Production")
	local blenders = production and production:FindFirstChild("Blenders")
	local model = blenders and blenders:FindFirstChild("Blender" .. index)
	return if model and model:IsA("Model") then model else nil
end

-- Place de l'operateur devant le panneau (marqueur BlenderNOperator, bas = sol) et bouton vert.
local function operatorPoints(floor: Model, index: number): (Vector3?, Vector3?)
	local model = blenderModel(floor, index)
	if model == nil then
		return nil, nil
	end
	local marker = model:FindFirstChild("Blender" .. index .. "Operator", true)
	local button = model:FindFirstChild("ButtonGo", true)
	local home = if marker and marker:IsA("BasePart") then marker.Position - Vector3.new(0, marker.Size.Y / 2, 0) else nil
	local press = if button and button:IsA("BasePart") then button.Position else nil
	return home, press
end

---------------------------------------------------------------------------------------------
-- Boucles de travail

-- Fruits portes sur un plateau au-dessus de la tete, comme le joueur (2026-11-20, demande
-- utilisateur) : meme attribut TrayFruits ; TrayController (client) dessine le plateau et
-- CarryPoseController leve les bras dessous.
local function setTray(npc: NpcRig.Npc, held: { string })
	npc.model:SetAttribute("TrayFruits", table.concat(held, ";"))
end

local function runCollector(state: FloorWorkers, worker: Worker)
	local npc = worker.npc
	local held: { string } = {}
	local home = markerPoint(state.floor, "CollectorHome", "Collector")
	local shelf = markerPoint(state.floor, "ShelfDrop")
	local function isActive(): boolean
		return worker.active
	end
	while worker.active do
		local target = if #held < worker.carry
			then TreeService.FindNearest(state.floor, npc.root.Position, state.reserved, true)
			else nil
		if target then
			state.reserved[target] = true
			local pos = target:GetPivot().Position
			-- 2026-11-27 : il s'arrete DEVANT le fruit (pas dessus), se tourne en douceur et se baisse
			-- pour le prendre (NpcRig.Pick) au lieu de pivoter d'un coup sur place
			local stand = NpcRig.ReachPoint(npc, pos, Gameplay.PickerReach)
			if stand then
				NpcRig.MoveTo(npc, stand, isActive)
			end
			if worker.active then
				NpcRig.Pick(npc, pos, Gameplay.PickerPickSeconds / worker.speed, function(): string?
					-- Jamais de fruit pas encore decouvert (FindNearest knownOnly) : c'est au joueur de
					-- le ramasser et de voir l'animation NEW FRUIT!
					local item = if target.Parent then TreeService.TakeFruit(state.floor, target) else nil
					return if item then item.id else nil
				end, function(id: string)
					table.insert(held, id)
					setTray(npc, held)
				end)
			end
			state.reserved[target] = nil
		elseif #held > 0 and shelf then
			NpcRig.MoveTo(npc, shelf, isActive)
			if not worker.active then
				break
			end
			-- 2026-11-27 : il se tourne vers les caisses et bascule son plateau ; les fruits s'envolent
			-- du plateau au moment ou il penche (NpcRig.Dump)
			local carried = held
			NpcRig.Dump(npc, binsPoint(state.floor), Gameplay.PickerDumpSeconds / worker.speed, Gameplay.TrayAboveHead, function(from: Vector3)
				ProductionService.AddFruitsToBins(state.floor, carried, from)
				held = {}
				setTray(npc, held)
			end)
			if #held > 0 then
				-- Geste coupe (etage retire) : les fruits sont quand meme poses
				ProductionService.AddFruitsToBins(state.floor, held, nil)
				held = {}
				setTray(npc, held)
			end
		else
			waitAtHome(worker, home, treePoint(state.floor), 1)
		end
	end
end

local function runOperator(state: FloorWorkers, worker: Worker, index: number)
	local npc = worker.npc
	local home, button = operatorPoints(state.floor, index)
	local function isActive(): boolean
		return worker.active
	end
	while worker.active do
		-- En train de poser les jus sur la table (NpcRig.Deposit) : on ne le retourne pas
		if os.clock() < worker.busyUntil then
			task.wait(0.1)
			continue
		end
		-- Toujours a sa place, face au panneau
		if home and (Vector3.new(npc.root.Position.X, home.Y, npc.root.Position.Z) - home).Magnitude > 1.5 then
			NpcRig.MoveTo(npc, home, isActive)
		end
		if button then
			NpcRig.Face(npc, button)
		end
		local bowl = ProductionService.GetBowl(state.floor, index)
		local ready = bowl ~= nil
			and bowl.owned
			and not bowl.blending
			and bowl.held == 0 -- du jus attend encore de la place sur la table
			and bowl.count > 0
			and (bowl.count >= bowl.max or bowl.idleSeconds >= Gameplay.OperatorIdleBlendSeconds)
		if not ready then
			task.wait(0.25)
			continue
		end
		-- Il reagit un peu moins vite qu'un joueur (le geste du bras compte dans ce delai)
		task.wait(math.max(0, Gameplay.OperatorReactSeconds - NpcRig.PressReachSeconds))
		if not worker.active then
			break
		end
		if os.clock() < worker.busyUntil then
			continue -- les jus sortent pendant qu'il allait appuyer : il les pose d'abord
		end
		task.spawn(NpcRig.Press, npc)
		task.wait(NpcRig.PressReachSeconds) -- le doigt touche le bouton
		local ok, reason = ProductionService.OperatorBlend(state.floor, index)
		if not ok then
			-- Jus en attente dans le mixeur (ou le joueur a deja appuye) : il attend un peu
			task.wait(if reason == "Holding" then 1.5 else 0.5)
		else
			task.wait(Gameplay.BlendSeconds)
		end
	end
end

-- Jus portes sur le plateau de la tete (meme attribut que le joueur, dessine par HandStackController).
local function setHands(npc: NpcRig.Npc, held: { string })
	npc.model:SetAttribute("HandJuices", table.concat(held, ";"))
end

local function runWaiter(state: FloorWorkers, worker: Worker)
	local npc = worker.npc
	local held: { string } = {}
	local home = markerPoint(state.floor, "ServerHome")
	local pallet = markerPoint(state.floor, "ServerPallet")
	local counter = markerPoint(state.floor, "ServerCounter")
	local function isActive(): boolean
		return worker.active
	end
	local waitingSince: number? = nil -- heure ou des jus ont commence a attendre sur la table
	while worker.active do
		if pallet == nil or counter == nil then
			warn(`[WorkerService] {state.floor.Name} : marqueurs ServerPallet / ServerCounter manquants`)
			task.wait(5)
			continue
		end
		if #held > 0 then
			-- Comptoir pas pret (etage en cours de chargement) : il garde ses jus et attend
			if not CustomerService.HasCounter(state.floor) then
				task.wait(1)
				continue
			end
			NpcRig.MoveTo(npc, counter, isActive)
			pause(worker)
			if not worker.active then
				break
			end
			-- Les gobelets sautent du haut du plateau jusqu'au comptoir (comme pour le joueur)
			local from: { Vector3 } = {}
			local count = #held
			local ids: { string } = {}
			for k = count, 1, -1 do
				table.insert(ids, held[k])
				local slot = HandStack.WorldSlot(npc.model, k)
				if slot then
					table.insert(from, slot.Position)
				end
			end
			CustomerService.AddToCounter(state.floor, ids, if #from == #ids then from else nil)
			held = {}
			setHands(npc, held)
			continue
		end
		local count = ProductionService.GetJuiceCount(state.floor)
		local now = os.clock()
		if count > 0 then
			waitingSince = waitingSince or now
		else
			waitingSince = nil
		end
		local ready = count >= Gameplay.WaiterCarry
			or (waitingSince ~= nil and now - (waitingSince :: number) >= Gameplay.WaiterWaitSeconds)
		if not ready then
			waitAtHome(worker, home, pallet, 0.5)
			continue
		end
		NpcRig.MoveTo(npc, pallet, isActive)
		NpcRig.Face(npc, pallet + Vector3.new(0, 0, 5))
		pause(worker)
		if not worker.active then
			break
		end
		local ids, positions = ProductionService.TakeJuices(state.floor, Gameplay.WaiterCarry)
		waitingSince = nil
		if #ids > 0 then
			for _, id in ids do
				table.insert(held, id)
			end
			-- D'ou partent les gobelets (le client les fait sauter de la table au plateau)
			if positions[1] then
				npc.model:SetAttribute("TakeFrom", positions[1])
			end
			setHands(npc, held)
			pause(worker)
		end
	end
end

-- Les jus sortent du mixeur N (ProductionService.pourToTable) : si son operateur est a son poste et
-- libre, il se tourne vers la table et les gobelets sautent de ses mains (sinon : du bec, comme avant).
-- Renvoie (point de depart des gobelets, attente avant le 1er saut).
local function onPour(floor: Model, index: number, count: number, tableCenter: Vector3?): (Vector3?, number?)
	local state = floors[floor]
	local worker = if state then state.workers["Operator" .. index] else nil
	if worker == nil or not worker.active or worker.npc.model.Parent == nil or os.clock() < worker.busyUntil then
		return nil, nil
	end
	local npc = worker.npc
	local home, button = operatorPoints(floor, index)
	local target = tableCenter or markerPoint(floor, "ServerPallet")
	if target == nil then
		return nil, nil
	end
	if home and (Vector3.new(npc.root.Position.X, home.Y, npc.root.Position.Z) - home).Magnitude > 3 then
		return nil, nil -- pas a sa place (il y retourne) : les jus sortent du bec
	end
	local throw = (count - 1) * NpcRig.CupPopStagger
	worker.busyUntil = os.clock() + NpcRig.DepositTurnSeconds * 2 + throw + 0.8
	local hands = NpcRig.HandsPoint(npc, target)
	task.spawn(NpcRig.Deposit, npc, target, button, throw)
	return hands, NpcRig.DepositTurnSeconds
end

local RUNNERS: { [string]: (FloorWorkers, Worker) -> () } = {
	Collector = runCollector,
	Waiter = runWaiter,
}
for index = 1, Gameplay.MaxBlenders do
	RUNNERS["Operator" .. index] = function(state: FloorWorkers, worker: Worker)
		runOperator(state, worker, index)
	end
end

-- Modele R6 a copier (Config/Npcs.Employees) et point d'apparition de chaque poste.
local function rigRole(role: string): string
	return if string.sub(role, 1, 8) == "Operator" then "Operator" else role
end

local function homePoint(floor: Model, role: string): Vector3?
	if string.sub(role, 1, 8) == "Operator" then
		local index = tonumber(string.sub(role, 9))
		local home = if index then operatorPoints(floor, index) else nil
		return home
	end
	return markerPoint(floor, role .. "Home", role)
end

---------------------------------------------------------------------------------------------
-- Apparition / depart

-- Effet d'une amelioration de l'etage (niveau sauvegarde, sinon niveau de depart).
local function floorValue(state: FloorWorkers, id: string): number
	local data = DataService.GetData(state.player)
	local levels = if data then DataService.FloorUpgrades(data, state.index) else nil
	local level = if levels then levels[id] else nil
	return Upgrades.GetValue(id, level or Upgrades.ById[id].startLevel)
end

-- Vitesse et nombre de fruits portes du Fruit Picker (panneau Fruit Picker), appliques tout de suite.
local function applyStats(state: FloorWorkers, worker: Worker)
	if worker.role == "Waiter" then
		-- Lent expres ; le pass "Waiter Speed x10" (attribut joueur SpeedBoost) le rend x10 plus rapide
		worker.speed = Gameplay.WaiterBaseSpeed
		if state.player:GetAttribute("SpeedBoost") == true then
			worker.speed *= Gameplay.WaiterSpeedPassMultiplier
		end
		worker.npc.humanoid.WalkSpeed = Gameplay.EmployeeWalkSpeed * worker.speed
		return
	end
	if worker.role ~= "Collector" then
		return
	end
	worker.speed = Gameplay.PickerBaseSpeed * floorValue(state, "PickerSpeed")
	worker.carry = math.floor(floorValue(state, "PickerCarry"))
	worker.npc.humanoid.WalkSpeed = Gameplay.EmployeeWalkSpeed * worker.speed
end

local function spawnWorker(state: FloorWorkers, role: string)
	-- Lot 5 : les employes R6 n'existent que sur l'etage ou se trouve le joueur (les autres etages
	-- produisent en nombres, Lib/FloorIncome)
	if state.workers[role] ~= nil or not state.active or not rigsReady or not FloorService.IsLive(state.floor) then
		return
	end
	local home = homePoint(state.floor, role)
	if home == nil then
		warn(`[WorkerService] {state.floor.Name} : pas de point de depart pour {role}`)
		return
	end
	local npc = NpcRig.Spawn(rigRole(role), CFrame.new(home), state.folder)
	if npc == nil then
		return
	end
	local worker: Worker = { role = role, npc = npc, thread = nil, active = true, speed = 1, carry = 0, busyUntil = 0 }
	applyStats(state, worker)
	state.workers[role] = worker
	worker.thread = task.spawn(function()
		-- Une erreur ne doit pas arreter l'employe pour toute la session : on relance la boucle.
		while worker.active do
			local ok, err = pcall(RUNNERS[role], state, worker)
			if not ok then
				warn(`[WorkerService] {role} ({state.floor.Name}) : {err}`)
				task.wait(1)
			end
		end
	end)
end

local function hired(player: Player, index: number, role: string): boolean
	local data = DataService.GetData(player)
	local levels = if data then DataService.FloorUpgrades(data, index) else nil
	return levels ~= nil and (levels[role] or 0) >= 1
end

local function startFloor(player: Player, floor: Model, index: number)
	if DataService.GetData(player) == nil or floors[floor] ~= nil then
		return
	end
	local dynamic = floor:FindFirstChild("Dynamic")
	if dynamic == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Workers"
	folder.Parent = dynamic
	local state: FloorWorkers = {
		player = player,
		floor = floor,
		index = index,
		folder = folder,
		workers = {},
		reserved = {},
		active = true,
	}
	floors[floor] = state
	for _, role in ROLES do
		if hired(player, index, role) then
			spawnWorker(state, role)
		end
	end
end

-- Retire les employes dessines (depart, ou le joueur change d'etage). Ce qu'ils portaient est perdu
-- (au plus PickerCarry fruits, WaiterCarry jus).
local function despawnAll(state: FloorWorkers)
	for _, worker in state.workers do
		worker.active = false
		if worker.thread and coroutine.status(worker.thread) == "suspended" then
			task.cancel(worker.thread)
		end
		NpcRig.Destroy(worker.npc)
	end
	table.clear(state.workers)
	table.clear(state.reserved)
end

local function spawnHired(state: FloorWorkers)
	for _, role in ROLES do
		if hired(state.player, state.index, role) then
			spawnWorker(state, role)
		end
	end
end

local function stopFloor(floor: Model)
	local state = floors[floor]
	if state == nil then
		return
	end
	floors[floor] = nil
	state.active = false
	despawnAll(state)
end

function WorkerService:Init() end

function WorkerService:Start()
	ProductionService.SetPourHandler(onPour)
	FloorService.OnFloorStarted(startFloor)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		stopFloor(floor)
	end)
	-- Le joueur change d'etage : on retire les employes de l'ancien, on dessine ceux du nouveau
	FloorService.OnLiveFloorChanged(function(_player: Player, old: Model?, new: Model?)
		local oldState = if old then floors[old] else nil
		if oldState then
			despawnAll(oldState)
		end
		local newState = if new then floors[new] else nil
		if newState then
			spawnHired(newState)
		end
	end)
	UpgradeService.OnBought(function(_player: Player, id: string, level: number, floor: Model)
		local state = floors[floor]
		if state and RUNNERS[id] and level >= 1 then
			spawnWorker(state, id)
		end
		-- Panneau Fruit Picker : le Fruit Picker deja dessine accelere / porte plus tout de suite
		local picker = if state and (id == "PickerSpeed" or id == "PickerCarry") then state.workers.Collector else nil
		if state and picker then
			applyStats(state, picker)
		end
	end)

	local function onCharacter(character: Model)
		NpcRig.TagPlayerCharacter(character)
	end
	local function onPlayer(player: Player)
		-- Pass "Waiter Speed x10" achete (ou retire en test) : les Waiters deja dessines accelerent tout de suite
		player:GetAttributeChangedSignal("SpeedBoost"):Connect(function()
			for _, state in floors do
				local waiter = state.workers.Waiter
				if state.player == player and waiter then
					applyStats(state, waiter)
				end
			end
		end)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- Les vetements se chargent depuis Roblox : en arriere-plan, puis les employes deja embauches.
	task.spawn(function()
		NpcRig.Prepare()
		rigsReady = true
		for _, state in floors do
			spawnHired(state)
		end
	end)
end

return WorkerService
