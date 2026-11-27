--!strict
-- Prechargement invisible (LocalScript de ReplicatedFirst : il tourne avant tout le reste).
-- Pas d'ecran de chargement a nous : Roblox affiche le sien jusqu'a ce que le jeu soit charge,
-- puis le joueur voit tout de suite le monde. Le HUD reste cache juste le temps que :
--   1. le personnage arrive ;
--   2. les controleurs client construisent l'interface (attribut joueur "ClientReady", pose par Main) ;
--   3. les images de l'interface et les icones soient prechargees (court, delai max HUD_PRELOAD_TIMEOUT).
-- Le HUD apparait alors d'un coup (attribut joueur "LoadingDone" = true).
-- Le reste (carte, fruits, PNJ, sons, animations, avatars) est precharge ENSUITE, en arriere-plan :
-- avant le 2026-11-20 le HUD attendait aussi tout ca (jusqu'a ~20 s de plus sur une connexion lente).
-- Chaque etape a un delai maximum : le joueur n'est jamais bloque.
-- Doc : docs/systems/chargement.md

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Reglages (cote client seulement : pas de Config partagee necessaire)
local HIDDEN_GUIS = { "HUD" } -- ScreenGuis caches jusqu'a la fin (ShopGUI est gere par MenuController)
local CHARACTER_TIMEOUT = 15
local CLIENT_READY_TIMEOUT = 15
local HUD_PRELOAD_TIMEOUT = 3 -- images du HUD et icones : au-dela, on montre le HUD quand meme
local STREAM_SETTLE_SECONDS = 0.6 -- la carte est "arrivee" quand rien de nouveau pendant ce temps
local STREAM_TIMEOUT = 8

-- Attend `check()` vrai, au plus `timeout` secondes.
local function waitUntil(check: () -> boolean, timeout: number)
	local startedAt = os.clock()
	while not check() and os.clock() - startedAt < timeout do
		task.wait(0.1)
	end
end

-- Cacher les menus des qu'ils arrivent dans PlayerGui (ils viennent de StarterGui).
local playerGui = player:WaitForChild("PlayerGui")
local hidden: { ScreenGui } = {}
local function hide(child: Instance)
	if child:IsA("ScreenGui") and table.find(HIDDEN_GUIS, child.Name) and not table.find(hidden, child) then
		child.Enabled = false
		table.insert(hidden, child)
	end
end
for _, child in playerGui:GetChildren() do
	hide(child)
end
local guiAdded = playerGui.ChildAdded:Connect(hide)

-- 1. Jeu et personnage
if not game:IsLoaded() then
	game.Loaded:Wait()
end
waitUntil(function()
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end, CHARACTER_TIMEOUT)

-- 2. Interface construite par les controleurs (Main pose "ClientReady")
waitUntil(function()
	return player:GetAttribute("ClientReady") == true
end, CLIENT_READY_TIMEOUT)

-- Outils de prechargement ------------------------------------------------------------------------
local shared = ReplicatedStorage:FindFirstChild("Shared")
local config = shared and shared:FindFirstChild("Config")

-- Lit un module de Config sans jamais planter le prechargement.
local function readConfig(name: string): { [string]: any }?
	local module = config and config:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

-- Instance "porteuse" d'un id (pas parentee : PreloadAsync lit juste sa propriete).
local function holder(list: { Instance }, className: string, property: string, id: string)
	local instance = Instance.new(className)
	pcall(function()
		(instance :: any)[property] = id
	end)
	table.insert(list, instance)
end

-- Precharge `list`, attend au plus `timeout` secondes (le chargement continue apres si besoin).
local function preload(list: { Instance }, timeout: number)
	local finished = false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		finished = true
	end)
	waitUntil(function()
		return finished
	end, timeout)
end

-- 3. Interface seulement : ce que le joueur voit des que le HUD apparait.
do
	local list: { Instance } = { playerGui }
	-- Icones pas encore affichees (ex. offres qui apparaissent plus tard)
	for _, id in readConfig("Icons") or {} do
		if type(id) == "string" then
			holder(list, "ImageLabel", "Image", id)
		end
	end
	preload(list, HUD_PRELOAD_TIMEOUT)
end

-- Montrer l'interface, prevenir les autres scripts.
guiAdded:Disconnect()
for _, screenGui in hidden do
	screenGui.Enabled = true
end
player:SetAttribute("LoadingDone", true)

-- 4. En arriere-plan (HUD deja visible) : tout ce qui peut apparaitre plus tard, pour que rien ne
--    "pope" en jeu : carte, ciel, tout ReplicatedStorage (fruits voxel FruitAssets, PNJ NpcTemplates
--    avec vetements et accessoires, sons), sons de jeu, animations des PNJ, avatars.
do
	-- Carte autour du joueur (streaming) : attendre qu'il n'arrive plus rien de nouveau
	local lastArrival = os.clock()
	local arrivals = workspace.DescendantAdded:Connect(function()
		lastArrival = os.clock()
	end)
	waitUntil(function()
		return os.clock() - lastArrival >= STREAM_SETTLE_SECONDS
	end, STREAM_TIMEOUT)
	arrivals:Disconnect()

	local list: { Instance } = { workspace, Lighting, ReplicatedStorage }
	-- Sons de jeu (crees a la volee par les controleurs) : { id = "rbxassetid://..." }
	for _, sound in readConfig("Sounds") or {} do
		if type(sound) == "table" and type(sound.id) == "string" then
			holder(list, "Sound", "SoundId", sound.id)
		end
	end
	-- Animations des PNJ (clients, employes ; R15 depuis le 2026-11-27)
	local npcs = readConfig("Npcs")
	if npcs and type(npcs.AnimationsR15) == "table" then
		for _, id in npcs.AnimationsR15 do
			if type(id) == "string" then
				holder(list, "Animation", "AnimationId", id)
			end
		end
	end
	-- Photos d'avatar des joueurs presents (logo au-dessus des bases, classements, dons)
	for _, other in Players:GetPlayers() do
		for _, size in { 60, 420 } do
			holder(list, "ImageLabel", "Image", `rbxthumb://type=AvatarHeadShot&id={other.UserId}&w={size}&h={size}`)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end
