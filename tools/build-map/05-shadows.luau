--!strict
-- Ombres : coupe l'ombre (CastShadow) de tout ce qui n'en a pas besoin, pour un rendu plus propre et
-- plus leger. A lancer EN DERNIER, apres 01 ... 04 (relancable).
-- 2026-11-19 soir : decor, fruits, petits trucs sans ombre.
-- 2026-11-20 (soleil au zenith ; utilisateur : "retire tous les shadows inutiles, par exemple les murs
-- et decorations") : LISTE BLANCHE. Seuls gardent leur ombre l'arbre fruitier (dossier Tree et les
-- modeles TreeStages), les mixeurs (Blenders) et les machines (Machines). Tout le reste perd son
-- ombre : murs, balcons, terrasse, ascenseur, escaliers, comptoir, convoyeur, palettes, panneaux,
-- dons, lot, carte et decor. Dans les dossiers gardes, les petites pieces, les pieces fines et les
-- pieces transparentes restent sans ombre.
-- Les objets crees pendant le jeu (fruits, gobelets, billets, PNJ) coupent leur ombre dans le code.
-- Doc : docs/systems/carte-bases.md (section Ombres)

local ServerStorage = game:GetService("ServerStorage")

local SMALL = 2.6 -- studs : plus petit = pas d'ombre
local THIN = 0.35 -- studs : plus fin = pas d'ombre (planches, tuiles, vitres)
-- Dossiers (ou modeles) dont les pieces gardent leur ombre
local KEEP_SHADOW_FOLDERS = {
	Tree = true,
	Blenders = true,
	Machines = true,
}

local function underKeepFolder(item: Instance, root: Instance): boolean
	local node = item.Parent
	while node and node ~= root do
		if KEEP_SHADOW_FOLDERS[node.Name] then
			return true
		end
		node = node.Parent
	end
	return false
end

local function wantsShadow(item: BasePart, root: Instance, keepAll: boolean): boolean
	if not keepAll and not underKeepFolder(item, root) then
		return false
	end
	local size = item.Size
	local biggest = math.max(size.X, size.Y, size.Z)
	local smallest = math.min(size.X, size.Y, size.Z)
	if biggest < SMALL or smallest < THIN then
		return false
	end
	if item.Transparency > 0.3 then
		return false
	end
	-- Pieces decoratives sans collision ni requete (feuilles, effets)
	if not item.CanCollide and not item.CanQuery then
		return false
	end
	return true
end

local function apply(root: Instance, keepAll: boolean?): (number, number)
	local off, on = 0, 0
	for i, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			local shadow = wantsShadow(item, root, keepAll == true)
			item.CastShadow = shadow
			if shadow then
				on += 1
			else
				off += 1
			end
		end
		if i % 2000 == 0 then
			task.wait()
		end
	end
	return off, on
end

local report = {}
local template = ServerStorage:FindFirstChild("BaseTemplate")
if template then
	local off, on = apply(template)
	table.insert(report, `BaseTemplate: {off} sans ombre, {on} avec`)
end
local floorTemplate = ServerStorage:FindFirstChild("FloorTemplate")
if floorTemplate then
	local off, on = apply(floorTemplate)
	table.insert(report, `FloorTemplate: {off} sans ombre, {on} avec`)
end
-- Etapes de l'arbre (copiees dans la base par TreeService) : tout l'arbre garde son ombre
local treeStages = ServerStorage:FindFirstChild("TreeStages")
if treeStages then
	local off, on = apply(treeStages, true)
	table.insert(report, `TreeStages: {off} sans ombre, {on} avec`)
end
local map = workspace:FindFirstChild("Map")
if map then
	local off, on = apply(map)
	table.insert(report, `Map: {off} sans ombre, {on} avec`)
end
return table.concat(report, " | ")
