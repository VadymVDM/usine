--!strict
-- Construit un etage a partir de ServerStorage.FloorTemplate (tour d'etages, phase 1b).
-- Utilise par FloorService (en jeu) et par l'outil tools/build-map/preview-tower.luau (Studio).
--
-- Regles du modele (scripts tools/build-map/02*) :
-- - Dossiers de variantes "Only<Tag>" n'importe ou dans le modele : gardes si le tag est actif pour
--   cet etage (leurs enfants remontent dans le dossier parent, le dossier disparait), sinon detruits.
--   Tags : Ground / Upper, StairA / StairB, HoleA / HoleB, SolidA / SolidB, Open / Closed, Top / NotTop
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

-- Dernier etage de la tour (demande utilisateur du 2026-11-27 : "supprimer ce qui sert a aller a
-- l'etage superieur, l'ascenseur s'arrete au dernier etage"). L'escalier qui monte est deja retire
-- par les tags (Config/Floors.Tags). Ici : plus de lampes (ciel ouvert, rien au-dessus) et un toit
-- sur la cage vitree de l'ascenseur (elle s'arrete la au lieu de rester ouverte vers le haut).
local SHAFT_ROOF_THICKNESS = 0.6
local SHAFT_ROOF_OVERHANG = 0.4

local function trimTopFloor(floor: Model)
	local building = floor:FindFirstChild("Building")
	if not building then
		return
	end
	local lamps = building:FindFirstChild("Lamps")
	if lamps then
		lamps:Destroy()
	end
	local elevator = building:FindFirstChild("Elevator")
	if not elevator or elevator:FindFirstChild("ShaftRoof") then
		return
	end
	-- Toit pose sur le haut des 4 poteaux de la cage (memes couleur et matiere)
	local minV, maxV, post = nil :: Vector3?, nil :: Vector3?, nil :: BasePart?
	for _, child in elevator:GetChildren() do
		if child:IsA("BasePart") and child.Name == "ShaftPost" then
			local half = child.Size / 2
			local lo, hi = child.Position - half, child.Position + half
			minV = if minV then minV:Min(lo) else lo
			maxV = if maxV then maxV:Max(hi) else hi
			post = child
		end
	end
	if not (minV and maxV and post) then
		return
	end
	local roof = Instance.new("Part")
	roof.Name = "ShaftRoof"
	roof.Anchored = true
	roof.CanCollide = true
	roof.CastShadow = false
	roof.TopSurface = Enum.SurfaceType.Smooth
	roof.BottomSurface = Enum.SurfaceType.Smooth
	roof.Color = post.Color
	roof.Material = post.Material
	local o = SHAFT_ROOF_OVERHANG * 2
	roof.Size = Vector3.new(maxV.X - minV.X + o, SHAFT_ROOF_THICKNESS, maxV.Z - minV.Z + o)
	roof.Position = Vector3.new((minV.X + maxV.X) / 2, maxV.Y + SHAFT_ROOF_THICKNESS / 2, (minV.Z + maxV.Z) / 2)
	roof.Parent = elevator
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
	elseif n >= Floors.MaxFloors then
		trimTopFloor(floor)
	end
	floor:SetAttribute("FloorIndex", n)
	floor:SetAttribute("Closed", closed)
	floor:PivotTo(basePivot * CFrame.new(0, Floors.FloorHeight * (n - 1), 0))
	return floor
end

return FloorAssembly
