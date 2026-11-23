--!strict
-- "Choses a construire" (bleu clair transparent) visibles seulement dans SA base (demande du
-- 2026-11-20). Dans les autres bases (et les bases libres), cache en local, cote client seulement :
--   * machines fantomes (attribut Built ~= true) : pieces de Machines.<id>.Build et des mixeurs ;
--   * pads d'achat / d'embauche (Machines.<id>.Pad, Blenders.BlenderN.Operator.Pad), pad "Upgrade
--     Tree" compris : ce sont des points d'achat, inutiles chez les autres ;
--   * etage ferme (Closed = true, l'etage a acheter) : depuis le 2026-11-20 il n'a plus que ses
--     dalles "Floor" (plafond de l'etage du dessous, jamais cachees) et la vitre rouge d'achat en
--     haut de l'escalier (Stairs.BuyGate) : la vitre et ses textes sont caches chez les autres.
--   * usine a construire (2026-11-21, SetupService) : fantomes SetupGhost (etagere, comptoir, arbre
--     pas plante...) et pads FREE (dossier Setup) caches chez les autres (les machines Hidden sont
--     deja invisibles cote serveur, UpgradeService).
-- Moyens : LocalTransparencyModifier = 1 (pieces), Enabled = false (SurfaceGui, Highlight).
-- Collisions : une piece cachee ne bloque plus personne (CanCollide = false en local, pour le
-- personnage de ce joueur ; remis a la valeur d'origine quand elle reapparait). Demande du
-- 2026-11-20 : "murs invisibles sur les bases vides". Le serveur ne sait rien de tout ca et
-- reverifie chaque achat.
-- Le jus des mixeurs construits (piece "Juice") reste gere par BlenderFxController.
-- Etiquettes flottantes et contours bleus des fantomes : deja caches par MachineFxController.
-- Doc : docs/systems/ameliorations-employes.md, docs/systems/tour-etages.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineModels = require(Shared:WaitForChild("Util"):WaitForChild("MachineModels"))

local REFRESH_SECONDS = 0.5

local GhostVisibilityController = {}

local player = Players.LocalPlayer
local started = false

-- Liste des pieces d'un modele, recalculee seulement quand quelque chose y arrive (streaming).
type Cache = { parts: { BasePart }, guis: { Instance }, dirty: boolean, conn: RBXScriptConnection }
local caches: { [Instance]: Cache } = {}

local hiddenParts: { [BasePart]: boolean } = {} -- valeur = CanCollide d'origine
local hiddenGuis: { [Instance]: boolean } = {} -- SurfaceGui / Highlight coupes par ce module

local function contentOf(root: Instance): Cache
	local cache = caches[root]
	if cache == nil then
		local created: Cache = { parts = {}, guis = {}, dirty = true, conn = nil :: any }
		created.conn = root.DescendantAdded:Connect(function()
			created.dirty = true
		end)
		caches[root] = created
		cache = created
	end
	local c = cache :: Cache
	if c.dirty then
		c.dirty = false
		local parts: { BasePart } = {}
		local guis: { Instance } = {}
		for _, item in root:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(parts, item)
			elseif item:IsA("SurfaceGui") or item:IsA("Highlight") then
				table.insert(guis, item)
			end
		end
		c.parts = parts
		c.guis = guis
	end
	return c
end

local function hidePart(part: BasePart)
	if hiddenParts[part] == nil then
		hiddenParts[part] = part.CanCollide
	end
	if part.LocalTransparencyModifier ~= 1 then
		part.LocalTransparencyModifier = 1
	end
	if part.CanCollide then
		part.CanCollide = false
	end
end

-- Piece de decor d'un niveau (LevelLookController : LookId, LookLevel, LookMaxLevel) : visible
-- seulement si le niveau de l'etage (attribut Lv_<id>) est dans sa plage.
local function lookShown(part: BasePart, floor: Instance?): boolean
	local id = part:GetAttribute("LookId")
	local min = part:GetAttribute("LookLevel")
	if floor == nil or type(id) ~= "string" or type(min) ~= "number" then
		return true
	end
	local max = part:GetAttribute("LookMaxLevel")
	local level = floor:GetAttribute("Lv_" .. id)
	local lv = if type(level) == "number" then level else 0
	return lv >= min and lv <= (if type(max) == "number" then max else math.huge)
end

-- leaveJuice : le jus d'un mixeur construit appartient a BlenderFxController (bol vide = cache).
-- floor : etage de la piece, pour rendre aux pieces de decor de niveau le choix de LevelLookController.
local function showPart(part: BasePart, leaveJuice: boolean, floor: Instance?)
	local collide = hiddenParts[part]
	if collide ~= nil then
		hiddenParts[part] = nil
		local shown = lookShown(part, floor)
		part.CanCollide = collide and shown
		if not (leaveJuice and part.Name == "Juice") then
			part.LocalTransparencyModifier = if shown then 0 else 1
		end
	end
end

local function hideGui(gui: Instance)
	local g = gui :: any
	if g.Enabled then
		hiddenGuis[gui] = true
		g.Enabled = false
	end
end

local function showGui(gui: Instance)
	if hiddenGuis[gui] then
		hiddenGuis[gui] = nil;
		(gui :: any).Enabled = true
	end
end

-- Etat deja applique a un modele : rien a refaire tant que rien n'y arrive et que l'etat ne change pas.
local applied: { [Instance]: string } = {}

local function unchanged(root: Instance, state: string): boolean
	local cache = caches[root]
	if cache and not cache.dirty and applied[root] == state then
		return true
	end
	applied[root] = state
	return false
end

local function setContainer(root: Instance?, floor: Instance, hide: boolean, leaveJuice: boolean)
	-- Cacher : repasse a chaque tour (LevelLookController ou BlenderFxController peuvent remettre
	-- une piece visible) ; montrer : une seule fois.
	local state = if hide then "hide" elseif leaveJuice then "built" else "show"
	if root == nil or (unchanged(root, state) and not hide) then
		return
	end
	local c = contentOf(root)
	for _, part in c.parts do
		if hide then
			hidePart(part)
		else
			showPart(part, leaveJuice, floor)
		end
	end
end

local function refreshClosedFloor(floor: Model, mine: boolean)
	if unchanged(floor, if mine then "mine" else "other") then
		return
	end
	local c = contentOf(floor)
	for _, part in c.parts do
		if part.Name == "Floor" then
			continue -- plafond de l'etage du dessous : toujours visible et solide
		elseif mine then
			showPart(part, false, floor)
		else
			hidePart(part)
		end
	end
	for _, gui in c.guis do
		if mine then
			showGui(gui)
		else
			hideGui(gui)
		end
	end
end

local function refreshOpenFloor(floor: Model, mine: boolean)
	for _, machine in MachineModels.List(floor) do
		local built = machine:GetAttribute("Built") == true
		setContainer(machine:FindFirstChild("Build"), floor, not mine and not built, built)
		-- (l'operateur d'un mixeur est liste a part par MachineModels, avec son propre Pad)
		setContainer(machine:FindFirstChild("Pad"), floor, not mine, false)
	end
	-- Usine a construire (SetupService) : fantomes bleus (etagere, tapis, table, comptoir, arbre pas
	-- plante : racines SetupGhost) et pads FREE (dossier Setup) caches chez les autres
	for _, folderName in { "Production", "Counter" } do
		local folder = floor:FindFirstChild(folderName)
		for _, item in (if folder then folder:GetChildren() else {}) do
			if item:GetAttribute("SetupBuild") ~= nil then
				setContainer(item, floor, not mine and item:GetAttribute("SetupGhost") == true, false)
			end
		end
	end
	local tree = floor:FindFirstChild("Tree")
	local body = tree and tree:FindFirstChild("Body")
	if body then
		setContainer(body, floor, not mine and body:GetAttribute("SetupGhost") == true, false)
	end
	setContainer(floor:FindFirstChild("Setup"), floor, not mine, false)
end

local function sweep()
	for root, cache in caches do
		if not root:IsDescendantOf(workspace) then
			cache.conn:Disconnect()
			caches[root] = nil
		end
	end
	for root in applied do
		if caches[root] == nil then
			applied[root] = nil
		end
	end
	for part in hiddenParts do
		if part.Parent == nil then
			hiddenParts[part] = nil
		end
	end
	for gui in hiddenGuis do
		if gui.Parent == nil then
			hiddenGuis[gui] = nil
		end
	end
end

local function refresh()
	local bases = workspace:FindFirstChild("Bases")
	if bases == nil then
		return
	end
	for _, base in bases:GetChildren() do
		local floors = base:FindFirstChild("Floors")
		if floors == nil then
			continue
		end
		local mine = base:GetAttribute("OwnerUserId") == player.UserId
		for _, floor in floors:GetChildren() do
			if not floor:IsA("Model") then
				continue
			end
			if floor:GetAttribute("Closed") == true then
				refreshClosedFloor(floor, mine)
			else
				refreshOpenFloor(floor, mine)
			end
		end
	end
	sweep()
end

function GhostVisibilityController.Init() end

function GhostVisibilityController.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		workspace:WaitForChild("Bases", 60)
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn(`[GhostVisibilityController] {err}`)
			end
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return GhostVisibilityController
