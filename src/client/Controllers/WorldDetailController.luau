--!strict
-- Details du monde alleges pour les telephones (client seulement, rien n'est envoye au serveur).
-- Test du 2026-11-27 (docs/perf-mobile.md) : une base au max faisait jusqu'a 2 144 appels de dessin,
-- dont 1 324 pour les ecrans 3D, et 786 emetteurs de particules actifs.
--   1. Ecrans 3D (SurfaceGui) du Workspace sans distance max (MaxDistance = 0 = visibles de
--      partout) : on leur donne une distance max selon la taille du panneau (Config/Gameplay).
--      Les ecrans qui ont deja une distance (murs des classements : 300) ne sont pas touches.
--   2. Effets de rarete des fruits (Attachment tague FruitModels.RarityFxTag : particules + lumiere) :
--      coupes au-dela de Gameplay.RarityFxMaxDistance de la camera, remis en s'approchant.
--      Ce controleur est le seul a changer Enabled sur ces effets.
--   3. PNJ (employes, clients : modeles tagues Npcs.FarHideTag) : invisibles au-dela de
--      Gameplay.NpcMaxDistance de la camera (NpcMaxDistancePhone sur telephone ou en Low Quality).
--      Test du 2026-11-27 (soir) : 110 PNJ par tour au maximum = 440 000 triangles et ~200 appels
--      de dessin, que la qualite basse n'allege pas. On met Transparency = 1 (en local) sur leurs
--      pieces et decalcomanies, et on remet la valeur d'avant en s'approchant. Pas
--      LocalTransparencyModifier : CustomerController, CameraFadeController et Fx/Reveal l'animent.
--   4. Mini fruits des gobelets (tag FruitModels.MiniFruitTag) : le fruit voxel entier reduit a
--      0.3 stud, 3 300 a 4 500 triangles chacun, 980 par tour au maximum. Invisibles au-dela de
--      Gameplay.MiniFruitMaxDistance de la camera (meme moyen que les PNJ : Transparency = 1).
--   5. Fruits entiers (tag FruitModels.FruitPartTag : au sol, caisses, portes, plateaux) : ~400 par
--      tour au maximum, jusqu'a 1 400 000 triangles en qualite telephone. Invisibles au-dela de
--      Gameplay.FruitMaxDistance, la hauteur comptant FruitVerticalWeight fois plus, jamais a moins
--      de FruitMinDistance (et du zoom max de la camera) : on ne peut pas les voir disparaitre.
-- Passage toutes les CHECK_SECONDS, et tout de suite quand la camera saute (teleport d'etage,
-- reapparition) : un objet cache ne doit pas apparaitre sous les yeux du joueur.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gameplay = require(Shared:WaitForChild("Config"):WaitForChild("Gameplay"))
local Npcs = require(Shared:WaitForChild("Config"):WaitForChild("Npcs"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))

local CHECK_SECONDS = 0.3 -- frequence du test de distance
local HYSTERESIS = 8 -- studs : evite que l'effet clignote a la limite
local NPC_HYSTERESIS = 15 -- studs : meme chose pour les PNJ (ils marchent)
local FRUIT_HYSTERESIS = 15 -- studs : meme chose pour les fruits entiers (portes par les PNJ)
local NPC_HIDES_PER_CHECK = 40 -- PNJ caches au plus par passage (etale le travail a l'arrivee)
local MINI_HIDES_PER_CHECK = 400 -- mini fruits caches au plus par passage
local FRUIT_HIDES_PER_CHECK = 400 -- fruits entiers caches au plus par passage
local ZOOM_MARGIN = 30 -- studs : un fruit a moins de (zoom max + marge) de la camera reste visible
local CAMERA_JUMP_STUDS = 40 -- la camera a bouge de plus depuis le dernier passage : passage tout de suite
local JUMP_STEP = "WorldDetailCameraJump"
local IS_STUDIO = RunService:IsStudio()

local WorldDetailController = {}

-- Effet suivi -> vrai si affiche, faux si coupe, nil si pas encore regle.
local rarityShown: { [Attachment]: boolean? } = {}
local rarityTracked: { [Attachment]: true } = {}

local function fitSurfaceGui(gui: SurfaceGui)
	if gui.MaxDistance ~= 0 then
		return
	end
	local target = gui.Adornee or gui.Parent
	local size = 0
	if target ~= nil and target:IsA("BasePart") then
		size = math.max(target.Size.X, target.Size.Y, target.Size.Z)
	end
	gui.MaxDistance = math.clamp(
		size * Gameplay.SurfaceGuiDistancePerStud,
		Gameplay.SurfaceGuiMinDistance,
		Gameplay.SurfaceGuiMaxDistance
	)
end

local function setRarityShown(attachment: Attachment, shown: boolean)
	rarityShown[attachment] = shown
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") or child:IsA("PointLight") then
			child.Enabled = shown
		end
	end
end

local function trackRarity(instance: Instance)
	-- Seulement dans le monde (pas les fruits des fenetres d'interface, ou rien ne s'affiche)
	if instance:IsA("Attachment") and instance:IsDescendantOf(Workspace) then
		rarityTracked[instance] = true
	end
end

local function untrackRarity(instance: Instance)
	if instance:IsA("Attachment") then
		rarityTracked[instance] = nil
		rarityShown[instance] = nil
	end
end

local function updateRarity(origin: Vector3)
	local near = Gameplay.RarityFxMaxDistance
	local far = near + HYSTERESIS
	for attachment in rarityTracked do
		local distance = (attachment.WorldPosition - origin).Magnitude
		local shown = rarityShown[attachment]
		if distance > far and shown ~= false then
			setRarityShown(attachment, false)
		elseif distance < near and shown ~= true then
			setRarityShown(attachment, true)
		elseif shown == nil then
			-- entre les deux au premier passage : on choisit le plus proche des deux seuils
			setRarityShown(attachment, distance < far)
		end
	end
end

-- 3. PNJ loin de la camera ------------------------------------------------------------------

type HiddenNpc = {
	saved: { [Instance]: number }, -- piece ou decalcomanie -> Transparency d'avant
	added: RBXScriptConnection,
}

local npcTracked: { [Model]: true } = {}
local npcHidden: { [Model]: HiddenNpc } = {}

local function hideNpcItem(saved: { [Instance]: number }, item: Instance)
	if (item:IsA("BasePart") or item:IsA("Decal")) and saved[item] == nil and item.Transparency < 1 then
		saved[item] = item.Transparency
		item.Transparency = 1
	end
end

local function hideNpc(model: Model)
	local saved: { [Instance]: number } = {}
	for _, item in model:GetDescendants() do
		hideNpcItem(saved, item)
	end
	npcHidden[model] = {
		saved = saved,
		-- Pieces qui arrivent apres coup (streaming, accessoire, objet porte)
		added = model.DescendantAdded:Connect(function(item: Instance)
			hideNpcItem(saved, item)
		end),
	}
end

local function showNpc(model: Model)
	local hidden = npcHidden[model]
	if hidden == nil then
		return
	end
	npcHidden[model] = nil
	hidden.added:Disconnect()
	for item, transparency in hidden.saved do
		-- Seulement si personne d'autre n'y a touche entre-temps
		if (item:IsA("BasePart") or item:IsA("Decal")) and item.Transparency == 1 then
			item.Transparency = transparency
		end
	end
end

local function trackNpc(instance: Instance)
	if instance:IsA("Model") and instance:IsDescendantOf(Workspace) then
		npcTracked[instance] = true
	end
end

local function untrackNpc(instance: Instance)
	if instance:IsA("Model") then
		npcTracked[instance] = nil
		-- Rend ses pieces visibles : un modele sorti par le streaming revient avec les memes
		-- pieces, il resterait invisible pour toujours.
		showNpc(instance)
	end
end

local function npcMaxDistance(): number
	local player = Players.LocalPlayer
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if
		phone
		or player:GetAttribute("SettingLowQuality") == true
		-- Studio seulement : le test de performance (tools/perf) simule un telephone
		or (IS_STUDIO and player:GetAttribute("PerfAsPhone") == true)
	then
		return Gameplay.NpcMaxDistancePhone
	end
	return Gameplay.NpcMaxDistance
end

local function updateNpcs(origin: Vector3)
	local near = npcMaxDistance()
	local far = near + NPC_HYSTERESIS
	local weight = Gameplay.NpcVerticalWeight
	local hides = 0
	for model in npcTracked do
		local offset = model:GetPivot().Position - origin
		local distance = math.sqrt(offset.X * offset.X + offset.Z * offset.Z + (offset.Y * weight) ^ 2)
		local hidden = npcHidden[model] ~= nil
		if hidden and distance < near then
			showNpc(model)
		elseif not hidden and distance > far and hides < NPC_HIDES_PER_CHECK then
			hides += 1
			hideNpc(model)
		end
	end
end

-- 4 et 5. Pieces taguees cachees loin de la camera (mini fruits, fruits entiers) ---------------
-- Une piece du monde devient invisible (Transparency = 1, en local) quand sa distance a la camera
-- depasse near + hysteresis ET sa vraie distance depasse minDistance + hysteresis ; elle reprend
-- sa transparence d'avant sous near, ou sous minDistance. Distance = racine(dx2 + dz2 +
-- (dy x verticalWeight)2). Seules les pieces opaques (Transparency = 0) sont cachees : une piece
-- deja transparente est animee ou cachee par un autre script (construction d'etage, PNJ cache,
-- gobelets voles), on n'y touche pas.

type PartHider = {
	tracked: { [BasePart]: true },
	hidden: { [BasePart]: number }, -- piece cachee -> Transparency d'avant
	near: number,
	minDistance: number,
	hysteresis: number,
	verticalWeight: number,
	hidesPerCheck: number,
}

local function newHider(near: number, hysteresis: number, verticalWeight: number, hidesPerCheck: number): PartHider
	return {
		tracked = {},
		hidden = {},
		near = near,
		minDistance = 0,
		hysteresis = hysteresis,
		verticalWeight = verticalWeight,
		hidesPerCheck = hidesPerCheck,
	}
end

local miniHider = newHider(Gameplay.MiniFruitMaxDistance, HYSTERESIS, 1, MINI_HIDES_PER_CHECK)
local fruitHider =
	newHider(Gameplay.FruitMaxDistance, FRUIT_HYSTERESIS, Gameplay.FruitVerticalWeight, FRUIT_HIDES_PER_CHECK)

local function showPart(hider: PartHider, part: BasePart)
	local transparency = hider.hidden[part]
	if transparency == nil then
		return
	end
	hider.hidden[part] = nil
	-- Seulement si personne d'autre n'y a touche entre-temps
	if part.Transparency == 1 then
		part.Transparency = transparency
	end
end

local function watchTag(hider: PartHider, tag: string)
	local function track(instance: Instance)
		-- Seulement dans le monde (pas les fruits et gobelets des fenetres d'interface)
		if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
			hider.tracked[instance] = true
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			hider.tracked[instance] = nil
			-- Une piece sortie par le streaming revient la meme : elle resterait invisible
			showPart(hider, instance)
		end
	end)
	for _, item in CollectionService:GetTagged(tag) do
		track(item)
	end
end

local function updateHider(hider: PartHider, origin: Vector3)
	local near = hider.near
	local far = near + hider.hysteresis
	local minDistance = hider.minDistance
	local minHide = minDistance + hider.hysteresis
	local weight = hider.verticalWeight
	local hides = 0
	for part in hider.tracked do
		local offset = part.Position - origin
		local flat = offset.X * offset.X + offset.Z * offset.Z
		local distance = math.sqrt(flat + (offset.Y * weight) ^ 2)
		local straight = math.sqrt(flat + offset.Y * offset.Y)
		local saved = hider.hidden[part]
		if saved ~= nil and part.Transparency ~= 1 then
			-- Un autre script l'a remise visible ou l'anime : on la lui laisse
			hider.hidden[part] = nil
			saved = nil
		end
		if saved ~= nil then
			if distance < near or straight < minDistance then
				showPart(hider, part)
			end
		elseif distance > far and straight > minHide and hides < hider.hidesPerCheck and part.Transparency == 0 then
			hides += 1
			hider.hidden[part] = part.Transparency
			part.Transparency = 1
		end
	end
end

-- Passage complet --------------------------------------------------------------------------------

local lastOrigin: Vector3? = nil

local function updateAll()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local origin = camera.CFrame.Position
	lastOrigin = origin
	-- Les fruits portes par le joueur ne doivent jamais etre caches, meme camera au zoom max
	fruitHider.minDistance =
		math.max(Gameplay.FruitMinDistance, Players.LocalPlayer.CameraMaxZoomDistance + ZOOM_MARGIN)
	updateRarity(origin)
	updateNpcs(origin)
	updateHider(miniHider, origin)
	updateHider(fruitHider, origin)
end

function WorldDetailController:Init() end

function WorldDetailController:Start()
	-- 1. Ecrans 3D
	for _, item in Workspace:GetDescendants() do
		if item:IsA("SurfaceGui") then
			fitSurfaceGui(item)
		end
	end
	Workspace.DescendantAdded:Connect(function(item: Instance)
		if item:IsA("SurfaceGui") then
			fitSurfaceGui(item)
		end
	end)

	-- 2. Effets de rarete des fruits
	local tag = FruitModels.RarityFxTag
	CollectionService:GetInstanceAddedSignal(tag):Connect(trackRarity)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(untrackRarity)
	for _, item in CollectionService:GetTagged(tag) do
		trackRarity(item)
	end
	-- 3. PNJ loin de la camera
	local npcTag = Npcs.FarHideTag
	CollectionService:GetInstanceAddedSignal(npcTag):Connect(trackNpc)
	CollectionService:GetInstanceRemovedSignal(npcTag):Connect(untrackNpc)
	for _, item in CollectionService:GetTagged(npcTag) do
		trackNpc(item)
	end

	-- 4. Mini fruits des gobelets, 5. fruits entiers
	watchTag(miniHider, FruitModels.MiniFruitTag)
	watchTag(fruitHider, FruitModels.FruitPartTag)

	-- Camera qui saute (teleport d'etage, reapparition, outils de test) : passage avant l'image,
	-- sinon les objets caches reapparaitraient jusqu'a CHECK_SECONDS plus tard, sous les yeux.
	RunService:BindToRenderStep(JUMP_STEP, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if camera and lastOrigin and (camera.CFrame.Position - lastOrigin).Magnitude > CAMERA_JUMP_STUDS then
			updateAll()
		end
	end)

	task.spawn(function()
		while true do
			updateAll()
			task.wait(CHECK_SECONDS)
		end
	end)
end

return WorldDetailController
