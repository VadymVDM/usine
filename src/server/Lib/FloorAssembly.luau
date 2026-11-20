--!strict
-- Construit un etage a partir de ServerStorage.FloorTemplate (tour d'etages, phase 1b).
-- Utilise par FloorService (en jeu) et par l'outil tools/build-map/preview-tower.luau (Studio).
--
-- Regles du modele (scripts tools/build-map/02*) :
-- - Dossiers de variantes "Only<Tag>" n'importe ou dans le modele : gardes si le tag est actif pour
--   cet etage (leurs enfants remontent dans le dossier parent, le dossier disparait), sinon detruits.
--   Tags : Ground / Upper, StairA / StairB, HoleA / HoleB, SolidA / SolidB, Open / Closed
--   (voir Config/Floors.Tags).
-- - Etage ferme (le suivant, a acheter) : demande utilisateur du 2026-11-20 "pas de truc bleu
--   transparent pour les etages, juste la porte rouge fermee". On garde seulement les dalles "Floor"
--   (le plafond de l'etage du dessous) et l'escalier (Shell = true dans Stairs : trou, garde-corps,
--   murs invisibles, vitre rouge BuyGate), avec leur vraie couleur. Murs, balcon, cage d'ascenseur :
--   retires. Le bleu transparent reste reserve aux machines a acheter.
-- Doc : docs/systems/tour-etages.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Floors = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Floors"))

local FloorAssembly = {}

local function variantTag(inst: Instance): string?
	if inst:IsA("Folder") and string.sub(inst.Name, 1, 4) == "Only" then
		return string.sub(inst.Name, 5)
	end
	return nil
end

local function resolveVariants(inst: Instance, tags: { [string]: boolean })
	-- D'abord les dossiers de variantes de ce niveau, jusqu'a ce qu'il n'y en ait plus (un dossier
	-- garde peut en contenir d'autres, ex. OnlyHoleA > OnlyClosed : ils remontent ici)
	local found = true
	while found do
		found = false
		for _, child in inst:GetChildren() do
			local tag = variantTag(child)
			if tag then
				found = true
				if tags[tag] then
					local shell = child:GetAttribute("Shell") == true
					for _, grandChild in child:GetChildren() do
						-- l'attribut Shell du dossier passe a son contenu (le dossier disparait)
						if shell and grandChild:GetAttribute("Shell") == nil then
							grandChild:SetAttribute("Shell", true)
						end
						grandChild.Parent = inst
					end
				end
				child:Destroy()
			end
		end
	end
	for _, child in inst:GetChildren() do
		resolveVariants(child, tags)
	end
end

-- Garde seulement la coque (attribut Shell = true, et tout ce qu'il contient sauf Shell = false).
-- Renvoie vrai si inst reste.
local function keepShell(inst: Instance): boolean
	if inst:GetAttribute("Shell") == true then
		for _, d in inst:GetDescendants() do
			if d:GetAttribute("Shell") == false and d.Parent then
				d:Destroy()
			end
		end
		return true
	end
	if inst:IsA("BasePart") then
		inst:Destroy()
		return false
	end
	local kept = false
	for _, child in inst:GetChildren() do
		if keepShell(child) then
			kept = true
		end
	end
	if not kept then
		inst:Destroy()
	end
	return kept
end

-- Etage ferme : dans Building, ne garder que les dalles "Floor" (le reste de la coque disparait).
local function keepSlabsOnly(building: Instance)
	for _, child in building:GetChildren() do
		if not (child:IsA("BasePart") and child.Name == "Floor") then
			child:Destroy()
		end
	end
end

-- Clone le modele pour l'etage n de la base (pivot de la base = basePivot). closed = etage a acheter.
function FloorAssembly.Build(template: Model, n: number, closed: boolean, basePivot: CFrame): Model
	local floor = template:Clone()
	floor.Name = "Floor" .. n
	resolveVariants(floor, Floors.Tags(n, closed))
	if closed then
		for _, child in floor:GetChildren() do
			if child ~= floor.PrimaryPart then
				keepShell(child)
			end
		end
		local building = floor:FindFirstChild("Building")
		if building then
			keepSlabsOnly(building)
		end
	end
	floor:SetAttribute("FloorIndex", n)
	floor:SetAttribute("Closed", closed)
	floor:PivotTo(basePivot * CFrame.new(0, Floors.FloorHeight * (n - 1), 0))
	return floor
end

return FloorAssembly
