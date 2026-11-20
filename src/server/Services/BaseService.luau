--!strict
-- Bases des joueurs. Au demarrage : clone ServerStorage.BaseTemplate dans les emplacements
-- Workspace.Map.BaseSlots.BaseSlot1..6 -> Workspace.Bases.Base1..6.
-- A l'arrivee : premiere base libre, panneau "<Nom>'s Juice Factory", le joueur apparait dedans
-- (sur son etage le plus haut : point donne par FloorService). Les etages : FloorService.
-- Sans base libre (7e joueur) : message propre, le joueur se promene et attend qu'une base se libere.
-- Au depart : les autres services nettoient (OnBaseReleased), le dossier Dynamic est vide, la base
-- redevient libre et passe au premier joueur en attente.
-- Seul module qui modifie l'attribut OwnerUserId des bases et l'attribut BaseId des joueurs.
-- Doc : docs/systems/carte-bases.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Map"))
local NotifyService = require(script.Parent.NotifyService)

local BaseService = {}

type Callback = (Player, Model) -> ()

local bases: { Model } = {} -- ordre BaseSlot1..N
local ownerOf: { [Model]: Player } = {}
local baseOf: { [Player]: Model } = {}
local waiting: { Player } = {} -- joueurs sans base, dans l'ordre d'arrivee
local reserved: { [Model]: boolean } = {} -- tests Studio seulement (DebugService)
local characterConnections: { [Player]: RBXScriptConnection } = {}
local spawnResolver: ((Player, Model) -> CFrame?)? = nil
local assignedCallbacks: { Callback } = {}
local releasedCallbacks: { Callback } = {}

local function runCallbacks(list: { Callback }, player: Player, base: Model, label: string)
	for _, callback in list do
		local ok, err = pcall(callback, player, base)
		if not ok then
			warn(`[BaseService] Erreur dans {label} : {err}`)
		end
	end
end

-- Texte du panneau d'entree (les deux faces)
local function setSignText(base: Model, text: string)
	local entrance = base:FindFirstChild("Entrance")
	if entrance == nil then
		return
	end
	for _, item in entrance:GetDescendants() do
		if item:IsA("TextLabel") and item.Name == "OwnerText" then
			item.Text = text
		end
	end
end

-- Point d'apparition dans la base : donne par FloorService (etage le plus haut du joueur).
local function getSpawnCFrame(player: Player, base: Model): CFrame?
	if spawnResolver then
		local ok, result = pcall(spawnResolver, player, base)
		if ok then
			return result
		end
		warn(`[BaseService] Erreur du point d'apparition : {result}`)
	end
	return nil
end

-- Place le personnage dans sa base (apres que le moteur l'a pose sur la SpawnLocation)
local function sendToBase(player: Player, character: Model)
	local base = baseOf[player]
	if base == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root == nil then
		return
	end
	task.wait()
	if baseOf[player] ~= base or character.Parent == nil then
		return
	end
	local target = getSpawnCFrame(player, base)
	if target then
		-- StreamingEnabled : charger l'etage d'arrivee avant (sinon chute a travers les dalles)
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 3)
		end)
		if baseOf[player] ~= base or character.Parent == nil then
			return
		end
		character:PivotTo(target)
	end
end

local function findFreeBase(): Model?
	for _, base in bases do
		if ownerOf[base] == nil and not reserved[base] then
			return base
		end
	end
	return nil
end

-- Donne une base libre au joueur. Renvoie vrai s'il a une base.
local function tryAssign(player: Player): boolean
	if baseOf[player] then
		return true
	end
	if player.Parent ~= Players then
		return false
	end
	local base = findFreeBase()
	if base == nil then
		if not table.find(waiting, player) then
			table.insert(waiting, player)
		end
		NotifyService.Notify(player, MapConfig.ServerFullMessage, true)
		return false
	end
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end
	ownerOf[base] = player
	baseOf[player] = base
	base:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("BaseId", base:GetAttribute("BaseId"))
	setSignText(base, string.format(MapConfig.OwnerSignFormat, player.DisplayName))
	runCallbacks(assignedCallbacks, player, base, "OnBaseAssigned")
	return true
end

-- Donne les bases libres aux joueurs en attente (ordre d'arrivee).
local function serveWaiting()
	while #waiting > 0 and findFreeBase() ~= nil do
		local nextPlayer = table.remove(waiting, 1) :: Player
		if nextPlayer.Parent == Players and tryAssign(nextPlayer) then
			NotifyService.Notify(nextPlayer, MapConfig.StandAssignedMessage)
			if nextPlayer.Character then
				task.spawn(sendToBase, nextPlayer, nextPlayer.Character)
			end
		end
	end
end

-- Libere la base du joueur, la nettoie, puis la donne au premier joueur en attente.
local function release(player: Player)
	local base = baseOf[player]
	if base == nil then
		return
	end
	-- Retire le lien tout de suite (un 2e appel pendant un rappel qui attend ne fait rien) ;
	-- ownerOf reste rempli jusqu'a la fin du nettoyage : personne ne recoit une base sale.
	baseOf[player] = nil
	if player.Parent == Players then
		player:SetAttribute("BaseId", nil)
	end
	runCallbacks(releasedCallbacks, player, base, "OnBaseReleased")
	local dynamic = base:FindFirstChild("Dynamic")
	if dynamic then
		dynamic:ClearAllChildren()
	end
	base:SetAttribute("OwnerUserId", 0)
	setSignText(base, MapConfig.FreeSignText)
	ownerOf[base] = nil
	serveWaiting()
end

local function onPlayerAdded(player: Player)
	-- Deja parti (arrive avant le Start) ou deja traite
	if player.Parent ~= Players or characterConnections[player] then
		return
	end
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		sendToBase(player, character)
	end)
	tryAssign(player)
	if player.Character then
		task.spawn(sendToBase, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end
	release(player)
end

function BaseService:Init()
	local template = ServerStorage:FindFirstChild("BaseTemplate")
	local map = workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("BaseSlots")
	if template == nil or not template:IsA("Model") or slots == nil then
		warn("[BaseService] ServerStorage.BaseTemplate ou Workspace.Map.BaseSlots manquant : aucune base."
			.. " Relancer les scripts de tools/build-map/ dans Studio.")
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Bases"
	-- Le modele est construit au repere d'origine : son pivot est donc le decalage a appliquer.
	local pivotOffset = template:GetPivot()
	for i = 1, MapConfig.MaxBases do
		local slot = slots:FindFirstChild("BaseSlot" .. i)
		if slot == nil or not slot:IsA("BasePart") then
			warn(`[BaseService] BaseSlot{i} manquant : base {i} ignoree`)
			continue
		end
		local base = template:Clone()
		base.Name = "Base" .. i
		base:SetAttribute("BaseId", i)
		base:SetAttribute("OwnerUserId", 0)
		base:PivotTo(slot.CFrame * pivotOffset)
		-- Les etages (base.Floors.FloorN) sont construits par FloorService au Start.
		setSignText(base, MapConfig.FreeSignText)
		base.Parent = folder
		table.insert(bases, base)
	end
	folder.Parent = workspace
end

function BaseService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Base du joueur (nil s'il n'en a pas).
function BaseService.GetBase(player: Player): Model?
	return baseOf[player]
end

-- Proprietaire d'une base (nil si libre).
function BaseService.GetOwner(base: Model): Player?
	return ownerOf[base]
end

-- Toutes les bases (copie).
function BaseService.GetBases(): { Model }
	return table.clone(bases)
end

-- Appele quand un joueur recoit une base (aussi pour les bases deja attribuees).
function BaseService.OnBaseAssigned(callback: Callback)
	table.insert(assignedCallbacks, callback)
	for player, base in baseOf do
		task.spawn(callback, player, base)
	end
end

-- Appele quand une base est liberee, AVANT que son dossier Dynamic soit vide : chaque service
-- arrete ici ses boucles et oublie l'etat de cette base. GetBase(player) renvoie deja nil :
-- utiliser le parametre base.
function BaseService.OnBaseReleased(callback: Callback)
	table.insert(releasedCallbacks, callback)
end

-- FloorService donne le point d'apparition (etage le plus haut du joueur). Sans lui : pas de deplacement.
function BaseService.SetSpawnResolver(resolver: (Player, Model) -> CFrame?)
	spawnResolver = resolver
end

-- Tests Studio (DebugService) : simule un serveur plein pour ce joueur, puis revient a la normale.
function BaseService.DebugSimulateFull(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	release(player)
	for _, base in bases do
		if ownerOf[base] == nil then
			reserved[base] = true
		end
	end
	return tryAssign(player)
end

function BaseService.DebugEndSimulation(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	table.clear(reserved)
	local ok = tryAssign(player)
	if ok and player.Character then
		task.spawn(sendToBase, player, player.Character)
	end
	serveWaiting()
	return ok
end

return BaseService
