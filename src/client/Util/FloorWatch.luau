--!strict
-- Suivi des etages des tours, partage par les controleurs (requis, pas lance par Main).
-- Contrat serveur : Workspace.Bases.BaseN (Model, OwnerUserId, FloorsOwned) > Floors > FloorK
-- (Model, FloorIndex, Closed). Un etage ferme (Closed = true) n'a qu'une coque : on l'ignore.
-- Les etages sont crees et detruits en jeu (achat = l'etage ferme est remplace par un nouveau
-- Model ouvert du meme nom ; depart du proprietaire = etages >= 2 detruits) : chaque controleur
-- nettoie son etat par etage avec OnRemoved. StreamingEnabled : tout peut arriver tard.
-- Doc : docs/systems/tour-etages.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Floors = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Floors"))

local FloorWatch = {}

type Callback = (floor: Model, base: Model) -> ()

local player = Players.LocalPlayer
local callbacks: { Callback } = {}
local openFloors: { [Model]: Model } = {} -- etage ouvert -> sa base
local watchedFloors: { [Model]: boolean } = {} -- etages deja suivis (ouverts ou fermes)
local watchedBases: { [Model]: boolean } = {}
local started = false

local function isAlive(floor: Instance): boolean
	return floor.Parent ~= nil and floor:IsDescendantOf(workspace)
end

-- Base d'un etage (Floors -> Base), nil si l'etage n'est plus dans une base.
function FloorWatch.BaseOf(floor: Instance): Model?
	local folder = floor.Parent
	local base = if folder then folder.Parent else nil
	if base and base:IsA("Model") then
		return base
	end
	return nil
end

-- Vrai si l'etage est dans la base du joueur local.
function FloorWatch.IsMine(floor: Instance): boolean
	local base = FloorWatch.BaseOf(floor)
	return base ~= nil and base:GetAttribute("OwnerUserId") == player.UserId
end

-- Numero de l'etage (attribut FloorIndex, sinon le nom "FloorK"), 1 par defaut.
function FloorWatch.IndexOf(floor: Instance): number
	local value = floor:GetAttribute("FloorIndex")
	if type(value) == "number" then
		return value
	end
	local fromName = tonumber(string.match(floor.Name, "^Floor(%d+)$"))
	return fromName or 1
end

-- Vrai si l'etage est ouvert (contenu complet).
function FloorWatch.IsOpen(floor: Instance): boolean
	return floor:GetAttribute("Closed") ~= true
end

-- Appelle callback une seule fois quand l'etage quitte le jeu (detruit ou retire).
-- Retourne une fonction pour annuler. Si l'etage est deja parti : appel immediat (task.spawn).
function FloorWatch.OnRemoved(floor: Instance, callback: () -> ()): () -> ()
	if not isAlive(floor) then
		task.spawn(callback)
		return function() end
	end
	local done = false
	local ancestry: RBXScriptConnection? = nil
	local destroying: RBXScriptConnection? = nil
	local function cancel()
		done = true
		if ancestry then
			ancestry:Disconnect()
			ancestry = nil
		end
		if destroying then
			destroying:Disconnect()
			destroying = nil
		end
	end
	local function fire()
		if done then
			return
		end
		cancel()
		callback()
	end
	ancestry = floor.AncestryChanged:Connect(function()
		if not isAlive(floor) then
			fire()
		end
	end)
	destroying = floor.Destroying:Connect(fire)
	return cancel
end

local function becameOpen(floor: Model, base: Model)
	if openFloors[floor] ~= nil or not isAlive(floor) then
		return
	end
	openFloors[floor] = base
	for _, callback in callbacks do
		task.spawn(callback, floor, base)
	end
end

local function trackFloor(floor: Instance, base: Model)
	if not floor:IsA("Model") or watchedFloors[floor] then
		return
	end
	watchedFloors[floor] = true
	local closedConnection: RBXScriptConnection? = nil
	if FloorWatch.IsOpen(floor) then
		becameOpen(floor, base)
	else
		-- Etage ferme : traite seulement s'il s'ouvre (en principe le serveur le remplace)
		closedConnection = floor:GetAttributeChangedSignal("Closed"):Connect(function()
			if FloorWatch.IsOpen(floor) then
				if closedConnection then
					closedConnection:Disconnect()
					closedConnection = nil
				end
				becameOpen(floor, base)
			end
		end)
	end
	FloorWatch.OnRemoved(floor, function()
		if closedConnection then
			closedConnection:Disconnect()
			closedConnection = nil
		end
		watchedFloors[floor] = nil
		openFloors[floor] = nil
	end)
end

local function trackBase(base: Instance)
	if not base:IsA("Model") or watchedBases[base] then
		return
	end
	watchedBases[base] = true
	local floorsFolder = base:FindFirstChild("Floors") or base:WaitForChild("Floors", 30)
	if floorsFolder == nil then
		watchedBases[base] = nil
		warn(`[FloorWatch] {base.Name}.Floors introuvable : etages ignores.`)
		return
	end
	floorsFolder.ChildAdded:Connect(function(floor)
		trackFloor(floor, base)
	end)
	for _, floor in floorsFolder:GetChildren() do
		trackFloor(floor, base)
	end
end

local function ensureStarted()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local bases = workspace:WaitForChild("Bases", 60)
		if bases == nil then
			warn("[FloorWatch] Workspace.Bases introuvable : pas d'etages.")
			return
		end
		bases.ChildAdded:Connect(function(base)
			task.spawn(trackBase, base)
		end)
		for _, base in bases:GetChildren() do
			task.spawn(trackBase, base)
		end
	end)
end

-- Appelle onFloor(floor, base) pour chaque etage ouvert de chaque base, existant ou futur
-- (chaque appel dans un task.spawn). Un etage remplace (nouvelle instance) est un nouvel appel.
function FloorWatch.Watch(onFloor: Callback)
	table.insert(callbacks, onFloor)
	for floor, base in openFloors do
		task.spawn(onFloor, floor, base)
	end
	ensureStarted()
end

-- Etages ouverts connus d'une base, tries par numero.
function FloorWatch.FloorsOf(base: Model): { Model }
	local list: { Model } = {}
	for floor, owner in openFloors do
		if owner == base and isAlive(floor) then
			table.insert(list, floor)
		end
	end
	table.sort(list, function(a, b)
		return FloorWatch.IndexOf(a) < FloorWatch.IndexOf(b)
	end)
	return list
end

-- Base du joueur local (nil s'il n'en a pas encore).
function FloorWatch.MyBase(): Model?
	local bases = workspace:FindFirstChild("Bases")
	if bases == nil then
		return nil
	end
	for _, base in bases:GetChildren() do
		if base:IsA("Model") and base:GetAttribute("OwnerUserId") == player.UserId then
			return base
		end
	end
	return nil
end

-- Numero d'etage a la hauteur y dans une base (1..MaxFloors), d'apres le pivot de la base.
function FloorWatch.FloorOfPosition(base: Model, y: number): number
	local relative = y - base:GetPivot().Y
	local index = math.floor((relative + 2) / Floors.FloorHeight) + 1
	return math.clamp(index, 1, Floors.MaxFloors)
end

-- Etage ouvert de la base le plus proche de la hauteur y (celui ou se trouve le joueur), ou nil.
function FloorWatch.FloorAt(base: Model, y: number): Model?
	local wanted = FloorWatch.FloorOfPosition(base, y)
	local best: Model? = nil
	local bestGap = math.huge
	for _, floor in FloorWatch.FloorsOf(base) do
		local gap = math.abs(FloorWatch.IndexOf(floor) - wanted)
		if gap < bestGap then
			best, bestGap = floor, gap
		end
	end
	return best
end

return FloorWatch
