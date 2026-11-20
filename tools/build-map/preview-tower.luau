--!strict
-- Apercu de la tour dans Studio (mode Edit) : Workspace._PreviewBase = BaseTemplate + les etages
-- 1..OWNED (ouverts) + l'etage OWNED+1 ferme (coque bleue + vitre rouge), a l'emplacement BaseSlot1.
-- Utilise ServerScriptService.Server.Lib.FloorAssembly (le meme code que le jeu).
-- Relancer pour reconstruire. REMOVE = true : supprime l'apercu.
-- A NE PAS LAISSER dans la place (BaseService cree les vraies bases en jeu ; une copie oubliee
-- tombe pile sur la Base1 = z-fighting partout). Voir docs/systems/carte-bases.md.

local OWNED = 2
local REMOVE = false

local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local old = workspace:FindFirstChild("_PreviewBase")
if old then
	old:Destroy()
end
if REMOVE then
	return "Apercu supprime"
end

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local FloorAssembly = freshRequire(ServerScriptService.Server.Lib.FloorAssembly)

local baseTemplate = ServerStorage:FindFirstChild("BaseTemplate") :: Model
local floorTemplate = ServerStorage:FindFirstChild("FloorTemplate") :: Model
assert(baseTemplate and floorTemplate, "Lancer 02a ... 02h d'abord")
local slot = workspace.Map.BaseSlots.BaseSlot1 :: BasePart

local base = baseTemplate:Clone()
base.Name = "_PreviewBase"
base:PivotTo(slot.CFrame * baseTemplate:GetPivot())
local floors = base:FindFirstChild("Floors") :: Folder
local counts = {}
for n = 1, OWNED + 1 do
	local closed = n > OWNED
	local floor = FloorAssembly.Build(floorTemplate, n, closed, base:GetPivot())
	local parts = 0
	for _, d in floor:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	table.insert(counts, `etage {n}{if closed then " (ferme)" else ""} : {parts} pieces`)
	floor.Parent = floors
	task.wait()
end
base.Parent = workspace
local baseParts = 0
for _, d in base:GetDescendants() do
	if d:IsA("BasePart") and not d:IsDescendantOf(floors) then
		baseParts += 1
	end
end
return `Apercu OK. Base seule : {baseParts} pieces ; ` .. table.concat(counts, " ; ")
