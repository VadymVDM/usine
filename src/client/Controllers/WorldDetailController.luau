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

local CHECK_SECONDS = 0.3 -- frequence du test de distance des effets de rarete
local HYSTERESIS = 8 -- studs : evite que l'effet clignote a la limite
local NPC_HYSTERESIS = 15 -- studs : meme chose pour les PNJ (ils marchent)
local NPC_HIDES_PER_CHECK = 40 -- PNJ caches au plus par passage (etale le travail a l'arrivee)
local MINI_HIDES_PER_CHECK = 400 -- mini fruits caches au plus par passage
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

local function updateRarity()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local origin = camera.CFrame.Position
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

local function updateNpcs()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local origin = camera.CFrame.Position
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

-- 4. Mini fruits des gobelets -----------------------------------------------------------------

local miniTracked: { [BasePart]: true } = {}
local miniHidden: { [BasePart]: number } = {} -- mini fruit cache -> Transparency d'avant

local function showMini(part: BasePart)
	local transparency = miniHidden[part]
	if transparency == nil then
		return
	end
	miniHidden[part] = nil
	-- Seulement si personne d'autre n'y a touche entre-temps
	if part.Transparency == 1 then
		part.Transparency = transparency
	end
end

local function trackMini(instance: Instance)
	-- Seulement dans le monde (pas les gobelets des fenetres d'interface)
	if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
		miniTracked[instance] = true
	end
end

local function untrackMini(instance: Instance)
	if instance:IsA("BasePart") then
		miniTracked[instance] = nil
		showMini(instance) -- un gobelet sorti par le streaming revient avec la meme piece
	end
end

local function updateMinis()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local origin = camera.CFrame.Position
	local near = Gameplay.MiniFruitMaxDistance
	local far = near + HYSTERESIS
	local hides = 0
	for part in miniTracked do
		local distance = (part.Position - origin).Magnitude
		local hidden = miniHidden[part] ~= nil
		if hidden and distance < near then
			showMini(part)
		elseif not hidden and distance > far and hides < MINI_HIDES_PER_CHECK and part.Transparency < 1 then
			hides += 1
			miniHidden[part] = part.Transparency
			part.Transparency = 1
		end
	end
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

	-- 4. Mini fruits des gobelets
	local miniTag = FruitModels.MiniFruitTag
	CollectionService:GetInstanceAddedSignal(miniTag):Connect(trackMini)
	CollectionService:GetInstanceRemovedSignal(miniTag):Connect(untrackMini)
	for _, item in CollectionService:GetTagged(miniTag) do
		trackMini(item)
	end

	task.spawn(function()
		while true do
			updateRarity()
			updateNpcs()
			updateMinis()
			task.wait(CHECK_SECONDS)
		end
	end)
end

return WorldDetailController
