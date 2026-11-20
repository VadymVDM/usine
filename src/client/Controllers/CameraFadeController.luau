--!strict
-- Camera qui passe a travers les OBJETS et les rend transparents (client seulement, rien n'est decide
-- ici, rien n'est envoye au serveur). Demande du 2026-11-20 : "quand la camera est derriere un
-- objet, l'objet devient transparent" + "la camera peut passer a travers l'arbre".
--
-- Objet = un Model range dans un dossier de Config/CameraFade (arbre, machines, comptoir, arbres de
-- la carte). Chaque image (juste apres la camera de Roblox) :
--   1. deux lignes epaisses : tete -> camera (prolongee de PopMargin derriere la camera) et
--      bassin -> camera ; test geometrique sur les boites des pieces (marche aussi pour les pieces
--      CanQuery = false, comme le feuillage) ;
--   2. un objet touche s'efface EN ENTIER (fondu vers Transparency) ; il revient opaque HoldSeconds
--      apres ne plus etre touche.
-- Pourquoi la camera passe au travers : la camera de Roblox (Poppercam) ne s'arrete pas devant une
-- piece sans collision ni devant une piece transparente a plus de 25 %. L'arbre n'a plus de
-- collision ; une machine s'efface des qu'elle fait avancer la camera (elle est alors juste derriere
-- la camera, dans la marge PopMargin) et la camera repart en arriere.
-- Murs, sols, plafonds, escaliers : jamais effaces (la camera s'arrete devant comme avant).
-- LocalTransparencyModifier (ce joueur seul). D'autres scripts s'en servent (machines fantomes,
-- decor par niveau, jus du mixeur) : une piece deja cachee (>= 0.99) ou modifiee par un autre script
-- pendant le fondu n'est plus touchee. SurfaceGui de l'objet coupee pendant le fondu (meme regle).
-- Doc : docs/systems/camera.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraFade = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CameraFade"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local CameraFadeController = {}

local player = Players.LocalPlayer

type Group = {
	model: Model,
	parts: { BasePart },
	decals: { Decal }, -- Decal et Texture
	guis: { SurfaceGui },
	min: Vector3,
	max: Vector3,
}

type Root = {
	folder: Instance,
	dynamic: boolean, -- etage : les objets bougent / changent (boites recalculees regulierement)
	groups: { Group },
	min: Vector3,
	max: Vector3,
	built: boolean,
	dirty: boolean,
	builtAt: number,
	connections: { RBXScriptConnection },
}

-- Valeur d'origine et derniere valeur posee ; false = un autre script s'en occupe (on n'y touche plus)
type Saved = { orig: number, set: number }
type Fade = {
	group: Group,
	applied: Group?, -- liste de pieces deja traitee (le groupe change quand l'objet est refait)
	alpha: number, -- 0 = opaque, 1 = efface (Transparency)
	lastHit: number,
	parts: { [BasePart]: Saved | false },
	decals: { [Decal]: Saved | false },
	guis: { [SurfaceGui]: boolean }, -- true = on l'a coupee ; false = pas a nous
}

local roots: { [Instance]: Root } = {}
local fades: { [Model]: Fade } = {}
local started = false

-- Fondu minimum des qu'un objet est touche : il franchit tout de suite le seuil de Poppercam
-- (transparence totale >= 0.25) et la camera ne s'arrete plus devant lui.
local START_ALPHA = math.min(1, 0.36 / CameraFade.Transparency)
-- SurfaceGui coupee au-dela de ce fondu (rallumee en dessous)
local GUI_ALPHA = 0.5
local EPSILON = 0.002

---------------------------------------------------------------------------------------------
-- Geometrie

-- Boite alignee sur le monde d'une piece (min, max).
local function partBounds(part: BasePart): (Vector3, Vector3)
	local cf = part.CFrame
	local h = part.Size * 0.5
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	local extent = Vector3.new(
		math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
		math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
		math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z
	)
	return cf.Position - extent, cf.Position + extent
end

-- Un axe de la methode des "plaques" : resserre [t0, t1], renvoie nil si le segment rate la boite.
local function slab(p: number, d: number, lo: number, hi: number, t0: number, t1: number): (number?, number)
	if math.abs(d) < 1e-6 then
		if p < lo or p > hi then
			return nil, t1
		end
		return t0, t1
	end
	local ta = (lo - p) / d
	local tb = (hi - p) / d
	if ta > tb then
		ta, tb = tb, ta
	end
	if ta > t0 then
		t0 = ta
	end
	if tb < t1 then
		t1 = tb
	end
	if t0 > t1 then
		return nil, t1
	end
	return t0, t1
end

-- Le segment a -> b traverse-t-il la boite [lo, hi] ?
local function segmentHitsBox(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3): boolean
	local d = b - a
	local t0: number? = 0
	local t1 = 1
	t0, t1 = slab(a.X, d.X, lo.X, hi.X, t0 :: number, t1)
	if t0 == nil then
		return false
	end
	t0, t1 = slab(a.Y, d.Y, lo.Y, hi.Y, t0, t1)
	if t0 == nil then
		return false
	end
	t0, t1 = slab(a.Z, d.Z, lo.Z, hi.Z, t0, t1)
	return t0 ~= nil
end

-- Le segment a -> b, epaissi de `radius`, touche-t-il la piece (sa boite orientee) ?
local function segmentHitsPart(a: Vector3, b: Vector3, radius: number, part: BasePart): boolean
	local cf = part.CFrame
	local h = part.Size * 0.5 + Vector3.new(radius, radius, radius)
	return segmentHitsBox(cf:PointToObjectSpace(a), cf:PointToObjectSpace(b), -h, h)
end

---------------------------------------------------------------------------------------------
-- Objets (groupes) d'un dossier

-- Groupe = un Model : ses pieces visibles, decals, SurfaceGui et sa boite. nil si rien de visible
-- ou trop plat (dalle, tapis : la camera passerait sous le sol).
local function buildGroup(model: Model): Group?
	local parts: { BasePart } = {}
	local decals: { Decal } = {}
	local guis: { SurfaceGui } = {}
	local lo: Vector3? = nil
	local hi: Vector3? = nil
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			if item.Transparency < 0.99 then
				table.insert(parts, item)
				local a, b = partBounds(item)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
		elseif item:IsA("Decal") then
			table.insert(decals, item)
		elseif item:IsA("SurfaceGui") then
			table.insert(guis, item)
		end
	end
	if lo == nil or hi == nil or hi.Y - lo.Y < CameraFade.MinHeight then
		return nil
	end
	return { model = model, parts = parts, decals = decals, guis = guis, min = lo, max = hi }
end

-- Models du dossier (on descend dans les sous-dossiers ; une piece seule n'est pas un objet).
local function collectGroups(folder: Instance, out: { Group })
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local group = buildGroup(child)
			if group then
				table.insert(out, group)
			end
		elseif child:IsA("Folder") then
			collectGroups(child, out)
		end
	end
end

local function rebuild(root: Root, now: number)
	local groups: { Group } = {}
	collectGroups(root.folder, groups)
	local lo: Vector3? = nil
	local hi: Vector3? = nil
	for _, group in groups do
		lo = if lo then lo:Min(group.min) else group.min
		hi = if hi then hi:Max(group.max) else group.max
		-- Un objet en plein fondu suit la nouvelle liste de pieces (machine construite, arbre refait)
		local fade = fades[group.model]
		if fade then
			fade.group = group
		end
	end
	root.groups = groups
	root.min = lo or Vector3.zero
	root.max = hi or Vector3.zero
	root.built = true
	root.dirty = false
	root.builtAt = now
end

local function removeRoot(folder: Instance)
	local root = roots[folder]
	if root == nil then
		return
	end
	roots[folder] = nil
	for _, connection in root.connections do
		connection:Disconnect()
	end
end

local function addRoot(folder: Instance, dynamic: boolean)
	if roots[folder] ~= nil then
		return
	end
	local root: Root = {
		folder = folder,
		dynamic = dynamic,
		groups = {},
		min = Vector3.zero,
		max = Vector3.zero,
		built = false,
		dirty = true,
		builtAt = -math.huge,
		connections = {},
	}
	local function markDirty()
		root.dirty = true
	end
	table.insert(root.connections, folder.DescendantAdded:Connect(markDirty))
	table.insert(root.connections, folder.DescendantRemoving:Connect(markDirty))
	table.insert(
		root.connections,
		folder.AncestryChanged:Connect(function()
			if not folder:IsDescendantOf(workspace) then
				removeRoot(folder)
			end
		end)
	)
	roots[folder] = root
end

-- Dossiers d'objets d'un etage (ils peuvent arriver apres l'etage : StreamingEnabled).
local function watchFloor(floor: Model)
	local wanted: { [string]: boolean } = {}
	for _, name in CameraFade.FloorFolders do
		wanted[name] = true
	end
	local function consider(child: Instance)
		if wanted[child.Name] and child:IsA("Folder") then
			addRoot(child, true)
		end
	end
	for _, child in floor:GetChildren() do
		consider(child)
	end
	local childAdded = floor.ChildAdded:Connect(consider)
	FloorWatch.OnRemoved(floor, function()
		childAdded:Disconnect()
		for folder in roots do
			if folder.Parent == floor or not folder:IsDescendantOf(workspace) then
				removeRoot(folder)
			end
		end
	end)
end

-- Dossiers de la carte ("Decor/Trees" = Workspace.Map.Decor.Trees), attendus sans limite.
local function watchMap()
	local map = workspace:WaitForChild("Map")
	for _, path in CameraFade.MapFolders do
		task.spawn(function()
			local node: Instance = map
			for name in string.gmatch(path, "[^/]+") do
				node = node:WaitForChild(name)
			end
			addRoot(node, false)
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Detection

-- Marque comme "touches maintenant" les objets traverses par le segment a -> b (epaisseur radius).
local function markHits(a: Vector3, b: Vector3, radius: number, now: number)
	local pad = Vector3.new(radius, radius, radius)
	local segMin = a:Min(b) - pad
	local segMax = a:Max(b) + pad
	for _, root in roots do
		-- Boites a jour : apres un ajout / retrait, et regulierement pour un etage (animations,
		-- arbre qui grandit), au plus toutes les RebuildSeconds
		if (root.dirty or not root.built) and now - root.builtAt >= CameraFade.RebuildSeconds then
			rebuild(root, now)
		end
		if root.max.X < segMin.X or root.min.X > segMax.X then
			continue
		end
		if root.max.Y < segMin.Y or root.min.Y > segMax.Y then
			continue
		end
		if root.max.Z < segMin.Z or root.min.Z > segMax.Z then
			continue
		end
		if root.dynamic and now - root.builtAt >= CameraFade.RebuildSeconds then
			rebuild(root, now)
		end
		for _, group in root.groups do
			if not segmentHitsBox(a, b, group.min - pad, group.max + pad) then
				continue
			end
			local fade = fades[group.model]
			if fade and now - fade.lastHit < 1e-6 then
				continue -- deja touche par l'autre ligne cette image
			end
			for _, part in group.parts do
				if part.Parent == nil or part.Transparency >= 0.99 then
					continue
				end
				-- Cachee par un autre script (nos valeurs restent sous 0.99)
				if part.LocalTransparencyModifier >= 0.99 then
					continue
				end
				if segmentHitsPart(a, b, radius, part) then
					if fade == nil then
						local newFade: Fade = {
							group = group,
							applied = nil,
							alpha = 0,
							lastHit = now,
							parts = {},
							decals = {},
							guis = {},
						}
						fades[group.model] = newFade
					else
						fade.lastHit = now
					end
					break
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Fondu

local function fadeValue(entry: Saved, v: number): number
	return 1 - (1 - entry.orig) * (1 - v)
end

local function applyFade(fade: Fade)
	local v = fade.alpha * CameraFade.Transparency
	local group = fade.group
	for _, part in group.parts do
		local entry = fade.parts[part]
		if entry == false then
			continue
		end
		if entry == nil then
			if part.LocalTransparencyModifier >= 0.99 then
				fade.parts[part] = false -- deja cachee par un autre script
				continue
			end
			local newEntry: Saved = { orig = part.LocalTransparencyModifier, set = -1 }
			fade.parts[part] = newEntry
			entry = newEntry
		end
		local saved = entry :: Saved
		if saved.set >= 0 and math.abs(part.LocalTransparencyModifier - saved.set) > EPSILON then
			fade.parts[part] = false -- un autre script vient de la changer : on le laisse faire
			continue
		end
		local value = fadeValue(saved, v)
		if math.abs(value - saved.set) > EPSILON / 2 then
			part.LocalTransparencyModifier = value
			saved.set = part.LocalTransparencyModifier
		end
	end
	for _, decal in group.decals do
		local entry = fade.decals[decal]
		if entry == false then
			continue
		end
		if entry == nil then
			if decal.LocalTransparencyModifier >= 0.99 then
				fade.decals[decal] = false
				continue
			end
			local newEntry: Saved = { orig = decal.LocalTransparencyModifier, set = -1 }
			fade.decals[decal] = newEntry
			entry = newEntry
		end
		local saved = entry :: Saved
		if saved.set >= 0 and math.abs(decal.LocalTransparencyModifier - saved.set) > EPSILON then
			fade.decals[decal] = false
			continue
		end
		local value = fadeValue(saved, v)
		if math.abs(value - saved.set) > EPSILON / 2 then
			decal.LocalTransparencyModifier = value
			saved.set = decal.LocalTransparencyModifier
		end
	end
	-- Textes des panneaux (SurfaceGui) : pas de transparence possible, on les coupe pendant le fondu
	local hide = fade.alpha >= GUI_ALPHA
	for _, gui in group.guis do
		local mine = fade.guis[gui]
		if mine == false then
			continue
		end
		if mine == true and gui.Enabled then
			fade.guis[gui] = false -- rallumee par un autre script
			continue
		end
		if hide and mine == nil then
			if gui.Enabled then
				gui.Enabled = false
				fade.guis[gui] = true
			else
				fade.guis[gui] = false -- deja eteinte par un autre script
			end
		elseif not hide and mine == true then
			gui.Enabled = true
			fade.guis[gui] = nil
		end
	end
end

-- Fin du fondu (alpha 0) : remet ce qui est encore a nous (les valeurs d'origine sont deja posees
-- par applyFade ; ici seulement les SurfaceGui et les pieces sorties du groupe entre-temps).
local function releaseFade(fade: Fade)
	for part, entry in fade.parts do
		if entry and part.Parent and math.abs(part.LocalTransparencyModifier - entry.set) <= EPSILON then
			part.LocalTransparencyModifier = entry.orig
		end
	end
	for decal, entry in fade.decals do
		if entry and decal.Parent and math.abs(decal.LocalTransparencyModifier - entry.set) <= EPSILON then
			decal.LocalTransparencyModifier = entry.orig
		end
	end
	for gui, mine in fade.guis do
		if mine == true and gui.Parent and not gui.Enabled then
			gui.Enabled = true
		end
	end
end

local function updateFades(dt: number, now: number)
	for model, fade in fades do
		if model.Parent == nil then
			fades[model] = nil
			continue
		end
		local wanted = now - fade.lastHit <= CameraFade.HoldSeconds
		local before = fade.alpha
		if wanted then
			fade.alpha = math.min(1, math.max(fade.alpha, START_ALPHA) + dt / CameraFade.FadeOutSeconds)
		else
			fade.alpha = math.max(0, fade.alpha - dt / CameraFade.FadeInSeconds)
		end
		if fade.alpha ~= before or fade.applied ~= fade.group then
			fade.applied = fade.group
			applyFade(fade)
		end
		if fade.alpha <= 0 then
			releaseFade(fade)
			fades[model] = nil
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if camera and rootPart and rootPart:IsA("BasePart") and camera.CameraType ~= Enum.CameraType.Scriptable then
		local camPos = camera.CFrame.Position
		local focus = camera.Focus.Position
		local offset = camPos - focus
		local distance = offset.Magnitude
		if distance > CameraFade.FirstPersonDistance then
			local dir = offset / distance
			-- Tete -> camera, prolongee derriere la camera (objet qui vient de la faire avancer)
			markHits(focus + dir * CameraFade.StartOffset, camPos + dir * CameraFade.PopMargin, CameraFade.HeadRadius, now)
			-- Bassin -> camera (objet bas qui cache les jambes)
			local hips = rootPart.Position - Vector3.new(0, CameraFade.BodyDrop, 0)
			local toCamera = camPos - hips
			if toCamera.Magnitude > CameraFade.StartOffset + 0.1 then
				markHits(hips + toCamera.Unit * CameraFade.StartOffset, camPos, CameraFade.BodyRadius, now)
			end
		end
	end
	updateFades(dt, now)
end

function CameraFadeController.Init() end

function CameraFadeController.Start()
	if started then
		return
	end
	started = true
	FloorWatch.Watch(function(floor: Model)
		watchFloor(floor)
	end)
	task.spawn(watchMap)
	-- Juste apres la camera de Roblox (meme image)
	RunService:BindToRenderStep("CameraFade", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok then
			warn(`[CameraFade] {err}`)
		end
	end)
end

-- Tests Studio : nombre d'objets en fondu et nombre de dossiers suivis.
function CameraFadeController.Stats(): (number, number)
	local faded, watched = 0, 0
	for _ in fades do
		faded += 1
	end
	for _ in roots do
		watched += 1
	end
	return faded, watched
end

return CameraFadeController
