--!strict
-- Usine a construire (demande du 2026-11-21) : un profil NEUF arrive dans une usine vide (etage 1).
-- 4 pads verts "FREE" (FloorTemplate.Setup.<id>.Pad), un seul visible a la fois, dans l'ordre de
-- Config/Setup.Steps : Plant tree -> Build shelf -> Build blender -> Open shop. Marcher dessus =
-- l'etape est faite (gratuite, verifiee ici : proprietaire, etage 1, bonne etape, pad visible,
-- position) et sauvegardee (Data.Setup = nombre d'etapes faites ; seul module qui l'ecrit).
-- Ce que chaque etape construit / fait apparaitre (Config/Setup.Build, .Reveal) :
--   * avant : cache (Lib/Ghost, mode Hidden), PAS de fantome bleu (on decouvre en marchant sur le
--     pad) ; un pad / panneau a faire apparaitre est cache aussi ;
--   * a l'etape : remis normal + attribut BuildStamp / RevealStamp +1 (animation client,
--     SetupController). Le pad fait passe a Hidden (+ DoneStamp), le suivant apparait apres
--     Setup.NextPadDelay.
-- Attribut d'etage "Lv_Setup" (etape actuelle) : LevelLookController / SetupController / tests.
-- Etages 2+, bases libres, profils existants : etape = Setup.Done (tout construit, pads FREE caches).
-- Les autres services demandent SetupService.Allows(etage, k) avant d'agir (arbre, pads, tapis,
-- clients...) et OnStepDone(cb) previent TreeService (graine -> pommes) et UpgradeService.
-- Etape 1 "Plant tree" (Config/Setup.Steps[k].prompt + spot, 2026-11-22) : PAS de pad visible,
-- touche E (ProximityPrompt) au centre de la pelouse (Tree.TreeRoot) ; Triggered verifie ici
-- (proprietaire, etage 1, bonne etape, touche E active, distance, delai).
-- Attribut joueur "HoldingSapling" = (Setup == 0) : l'arbre niveau 1 dans les mains (SaplingController,
-- apres la cinematique d'ouverture) jusqu'a ce qu'il soit plante.
-- Doc : docs/systems/usine-a-construire.md, docs/systems/cinematique.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Setup = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Setup"))
local Gameplay = require(ReplicatedStorage.Shared.Config:WaitForChild("Gameplay"))

local DataService = require(script.Parent.DataService)
local FloorService = require(script.Parent.FloorService)
local Ghost = require(script.Parent.Parent.Lib.Ghost)
local PlayerCheck = require(script.Parent.Parent.Lib.PlayerCheck)
local Prompt = require(ReplicatedStorage.Shared:WaitForChild("Util"):WaitForChild("Prompt"))

local SetupService = {}

type StepCallback = (Player, number, Model) -> () -- (joueur, etape faite 1..Done, etage 1)

type FloorState = {
	floor: Model,
	builds: { [number]: { Ghost.Group } },
	reveals: { [number]: { Ghost.Group } },
	pads: { Ghost.Group }, -- index = etape
	zones: { BasePart? },
	prompts: { [number]: ProximityPrompt }, -- pads a touche E (Setup.Steps[k].prompt)
	gateOpened: { [number]: boolean }, -- pad deja montre (sa condition Setup.PadGates reste vraie ensuite)
	padReadyAt: number, -- os.clock : le pad de l'etape suivante n'apparait pas avant
}

local states: { [Model]: FloorState } = {}
local callbacks: { StepCallback } = {}

local function findPath(floor: Instance, path: string): Instance?
	local current: Instance? = floor
	for name in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function bump(instance: Instance, attribute: string)
	local value = instance:GetAttribute(attribute)
	instance:SetAttribute(attribute, (if type(value) == "number" then value else 0) + 1)
end

-- Etape de l'etage : celle du proprietaire pour son etage 1, Done partout ailleurs.
function SetupService.FloorStep(floor: Model): number
	local owner = FloorService.GetOwner(floor)
	if owner == nil or FloorService.GetIndex(floor) ~= 1 then
		return Setup.Done
	end
	local data = DataService.GetData(owner)
	local step = data and (data :: any).Setup
	return if type(step) == "number" then step else Setup.Done
end

-- Vrai si l'etape `step` de l'etage est faite (toujours vrai hors etage 1 d'un profil neuf).
function SetupService.Allows(floor: Model, step: number): boolean
	return SetupService.FloorStep(floor) >= step
end

-- Etape du joueur (0..Done), Done si la sauvegarde n'est pas chargee.
function SetupService.PlayerStep(player: Player): number
	local data = DataService.GetData(player)
	local step = data and (data :: any).Setup
	return if type(step) == "number" then step else Setup.Done
end

function SetupService.OnStepDone(callback: StepCallback)
	table.insert(callbacks, callback)
end

---------------------------------------------------------------------------------------------
-- Etat visible de l'etage

local function prepare(floor: Model): FloorState
	local existing = states[floor]
	if existing then
		return existing
	end
	local state: FloorState = { floor = floor, builds = {}, reveals = {}, pads = {}, zones = {}, prompts = {}, gateOpened = {}, padReadyAt = 0 }
	for k, paths in Setup.Build do
		state.builds[k] = {}
		for _, path in paths do
			local root = findPath(floor, path)
			if root then
				root:SetAttribute("SetupBuild", k)
				table.insert(state.builds[k], Ghost.Capture(root))
			end
		end
	end
	for k, paths in Setup.Reveal do
		state.reveals[k] = {}
		for _, path in paths do
			local root = findPath(floor, path)
			if root then
				root:SetAttribute("SetupReveal", k)
				table.insert(state.reveals[k], Ghost.Capture(root))
			end
		end
	end
	local folder = floor:FindFirstChild("Setup")
	for i, step in Setup.Steps do
		local model = folder and folder:FindFirstChild(step.id)
		if model then
			local group = Ghost.Capture(model)
			Ghost.SetMode(group, "Hidden")
			state.pads[i] = group
			local zone = model:FindFirstChild("PadZone", true)
			if step.spot then
				-- Touche E sur une piece de l'etage (pad 1 : centre de la pelouse, Tree.TreeRoot)
				zone = findPath(floor, step.spot)
			end
			state.zones[i] = if zone and zone:IsA("BasePart") then zone else nil
			if step.prompt and zone and zone:IsA("BasePart") then
				local prompt = Prompt.Create(zone, if step.spot then Setup.PlantText else Setup.PadText, step.label, {
					name = "SetupPrompt",
					distance = Setup.PromptDistance,
				})
				Prompt.SetActive(prompt, false)
				local index = i
				prompt.Triggered:Connect(function(player: Player)
					local ok, err = pcall(SetupService._onPrompt, player, floor, index)
					if not ok then
						warn(`[SetupService] Erreur de touche E : {err}`)
					end
				end)
				state.prompts[i] = prompt
			end
		end
	end
	states[floor] = state
	return state
end

-- Tutoriel etape par etape (2026-11-22) : le pad FREE suivant n'apparait que quand c'est son tour
-- (Config/Setup.PadGates), d'apres ce que le serveur publie deja sur le joueur (InvFruits / InvMax :
-- fruits portes, HandJuices : jus portes). Une fois montre, il reste visible.
local function carriedFruits(player: Player): number
	local text = player:GetAttribute("InvFruits")
	-- Format "Apple=15;Strawberry=4" (nombre par fruit, ProductionService)
	local count = 0
	if type(text) == "string" then
		for entry in string.gmatch(text, "[^;]+") do
			local amount = tonumber(string.match(entry, "=(%d+)$"))
			count += amount or 1
		end
	end
	return count
end

local function gateOpen(player: Player?, index: number): boolean
	local gate = Setup.PadGates[index]
	if gate == nil then
		return true
	end
	if player == nil then
		return false
	end
	if gate.minFruits then
		local max = player:GetAttribute("InvMax")
		local need = math.min(gate.minFruits, if type(max) == "number" and max > 0 then max else gate.minFruits)
		return carriedFruits(player) >= need
	elseif gate.emptyTray then
		return carriedFruits(player) == 0
	elseif gate.minJuices then
		local juices = player:GetAttribute("HandJuices")
		return type(juices) == "number" and juices >= gate.minJuices
	end
	return true
end

-- Met l'etage dans l'etat de son etape. `animate` : attributs d'animation pour ce qui change
-- (seulement quand le proprietaire avance, pas a son arrivee ni a son depart).
local function apply(floor: Model, animate: boolean)
	local state = states[floor]
	if state == nil then
		return
	end
	local step = SetupService.FloorStep(floor)
	floor:SetAttribute("Lv_Setup", step)
	-- Pas de fantome bleu pour les constructions des pads FREE (demande du 2026-11-21 : "on decouvre
	-- seulement quand on se met sur le pad") : cachees, puis construites piece par piece.
	for k, groups in state.builds do
		for _, group in groups do
			local before = group.mode
			Ghost.SetMode(group, if step >= k then "Normal" else "Hidden")
			if animate and before ~= "Normal" and group.mode == "Normal" then
				bump(group.root, "BuildStamp")
			end
		end
	end
	for k, groups in state.reveals do
		for _, group in groups do
			local before = group.mode
			Ghost.SetMode(group, if step >= k then "Normal" else "Hidden")
			if animate and before == "Hidden" and group.mode == "Normal" then
				bump(group.root, "RevealStamp")
			end
		end
	end
	local owned = FloorService.GetOwner(floor) ~= nil and FloorService.GetIndex(floor) == 1
	local ready = os.clock() >= state.padReadyAt
	local owner = FloorService.GetOwner(floor)
	for i, group in state.pads do
		local before = group.mode
		local turn = owned and i == step + 1 and ready
		if turn and not state.gateOpened[i] and gateOpen(owner, i) then
			state.gateOpened[i] = true
		end
		local shown = turn and state.gateOpened[i] == true
		local padless = Setup.Steps[i].spot ~= nil -- (pad toujours cache, seule la touche E compte)
		Ghost.SetMode(group, if shown and not padless then "Normal" else "Hidden")
		Prompt.SetActive(state.prompts[i], shown)
		if before == "Hidden" and group.mode == "Normal" then
			bump(group.root, "RevealStamp")
		elseif animate and before == "Normal" and group.mode == "Hidden" then
			bump(group.root, "DoneStamp")
		end
	end
end

local function advance(player: Player, floor: Model)
	local data = DataService.GetData(player) :: any
	if data == nil or type(data.Setup) ~= "number" or data.Setup >= Setup.Done then
		return
	end
	data.Setup += 1
	local step = data.Setup
	player:SetAttribute("HoldingSapling", step == 0)
	local state = states[floor]
	if state then
		state.padReadyAt = os.clock() + Setup.NextPadDelay
	end
	apply(floor, true)
	for _, callback in callbacks do
		local ok, err = pcall(callback, player, step, floor)
		if not ok then
			warn(`[SetupService] Erreur dans OnStepDone : {err}`)
		end
	end
	-- Pad suivant : apparait un peu apres (le temps de voir la construction)
	if step < Setup.Done then
		task.delay(Setup.NextPadDelay + 0.05, function()
			if states[floor] == state and FloorService.GetOwner(floor) == player then
				apply(floor, true)
			end
		end)
	end
end

-- Le proprietaire marche sur le pad FREE de son etape (etage 1 seulement).
local function checkPlayer(player: Player)
	local step = SetupService.PlayerStep(player)
	if step >= Setup.Done then
		return
	end
	local floor = FloorService.GetFloor(player, 1)
	local state = floor and states[floor]
	local root = PlayerCheck.GetRoot(player)
	if floor == nil or state == nil or root == nil then
		return
	end
	local group = state.pads[step + 1]
	local zone = state.zones[step + 1]
	if group == nil or zone == nil or group.mode ~= "Normal" or state.prompts[step + 1] ~= nil then
		return -- (pad a touche E : voir _onPrompt)
	end
	if PlayerCheck.IsOver(zone, root.Position) and PlayerCheck.Cooldown(player, "SetupPad", 0.5) then
		advance(player, floor)
	end
end

-- Touche E sur un pad FREE (pad 1 "Plant tree") : memes regles que le contact, plus la distance.
function SetupService._onPrompt(player: Player, floor: Model, index: number)
	if FloorService.GetOwner(floor) ~= player or FloorService.GetIndex(floor) ~= 1 then
		return
	end
	if SetupService.PlayerStep(player) ~= index - 1 then
		return
	end
	local state = states[floor]
	local prompt = state and state.prompts[index]
	local zone = state and state.zones[index]
	local root = PlayerCheck.GetRoot(player)
	if state == nil or prompt == nil or zone == nil or root == nil or prompt:GetAttribute("Active") ~= true then
		return
	end
	local flat = Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z)
	if flat.Magnitude > Setup.PromptDistance + 4 or math.abs(root.Position.Y - zone.Position.Y) > 12 then
		return
	end
	if PlayerCheck.Cooldown(player, "SetupPad", 0.5) then
		advance(player, floor)
	end
end

function SetupService:Init() end

function SetupService:Start()
	DataService.OnPlayerLoaded(function(player: Player, data)
		player:SetAttribute("HoldingSapling", (data :: any).Setup == 0)
		-- Fruits / jus portes qui changent : le pad suivant peut apparaitre (Setup.PadGates)
		local function recheck()
			if SetupService.PlayerStep(player) >= Setup.Done then
				return
			end
			local floor = FloorService.GetFloor(player, 1)
			if floor and states[floor] then
				apply(floor, false)
			end
		end
		player:GetAttributeChangedSignal("InvFruits"):Connect(recheck)
		player:GetAttributeChangedSignal("HandJuices"):Connect(recheck)
	end)
	FloorService.OnFloorAdded(function(floor: Model, _index: number)
		prepare(floor)
		apply(floor, false)
	end)
	FloorService.OnFloorRemoving(function(floor: Model)
		states[floor] = nil
	end)
	FloorService.OnFloorStarted(function(_player: Player, floor: Model, _index: number)
		local state = prepare(floor)
		state.padReadyAt = 0
		state.gateOpened = {} -- (nouveau proprietaire / retour : conditions recalculees)
		apply(floor, false)
	end)
	FloorService.OnFloorStopped(function(_player: Player, floor: Model)
		if floor.Parent ~= nil then
			apply(floor, false)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Gameplay.ContactCheckSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkPlayer, player)
				if not ok then
					warn(`[SetupService] Erreur de pad : {err}`)
				end
			end
		end
	end)
end

-- Tests Studio (DebugService) : met l'etape du joueur a n (ECRIT la sauvegarde) et redessine.
function SetupService.DebugSet(player: Player, n: number): boolean
	local data = DataService.GetData(player) :: any
	local floor = FloorService.GetFloor(player, 1)
	if data == nil or floor == nil then
		return false
	end
	data.Setup = math.clamp(math.floor(n), 0, Setup.Done)
	player:SetAttribute("HoldingSapling", data.Setup == 0)
	local state = states[floor]
	if state then
		state.padReadyAt = 0
	end
	apply(floor, true)
	for _, callback in callbacks do
		pcall(callback, player, data.Setup, floor)
	end
	return true
end

return SetupService
