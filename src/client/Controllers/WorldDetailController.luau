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

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gameplay = require(Shared:WaitForChild("Config"):WaitForChild("Gameplay"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))

local CHECK_SECONDS = 0.3 -- frequence du test de distance des effets de rarete
local HYSTERESIS = 8 -- studs : evite que l'effet clignote a la limite

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
	task.spawn(function()
		while true do
			updateRarity()
			task.wait(CHECK_SECONDS)
		end
	end)
end

return WorldDetailController
