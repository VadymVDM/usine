--!strict
-- Test de performance relancable, cote SERVEUR. A lancer par MCP execute_luau (ou la barre de
-- commande) pendant un Play Studio. Jamais charge par le jeu.
-- Synchronise par Rojo dans ServerScriptService.DevTools.Perf["perf-server"].
-- Mode d'emploi et valeurs de reference : docs/perf-mobile.md ("Relancer le test").
--
--   local P = require(game.ServerScriptService.DevTools.Perf["perf-server"])
--   return P.Setup({ 2, 3, 5, 6 })   -- installe le module client + construit des tours au maximum
--   return P.ReplayIntro()            -- rejoue la cinematique chez le joueur
--   return P.Heartbeat(4)             -- cadence du serveur
--
-- Les tours au maximum sont des copies de l'apercu (tools/build-map/preview-factory.luau) :
-- 10 etages, tout achete, 110 PNJ immobiles. Elles sont jetees au Stop. Ne pas donner l'emplacement
-- de la base du joueur (attribut BaseId) : la tour se poserait sur sa vraie base.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CLIENT_MODULE_NAME = "PerfClient" -- nom de la copie dans ReplicatedStorage (lue par le client)
local TOWER_PREFIX = "_PerfTower" -- Workspace._PerfTower<emplacement>
local SLOT_LINE = "local SLOT = 1" -- ligne de preview-factory remplacee pour changer d'emplacement

local PerfServer = {}

local function firstPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- Copie le module client dans ReplicatedStorage (le client ne voit pas ServerScriptService).
function PerfServer.Install(): string
	assert(RunService:IsRunning(), "A lancer pendant un Play")
	local old = ReplicatedStorage:FindFirstChild(CLIENT_MODULE_NAME)
	if old then
		old:Destroy()
	end
	local copy = script.Parent:FindFirstChild("perf-client")
	assert(copy, "perf-client introuvable a cote de perf-server (Rojo connecte ?)")
	local clone = copy:Clone()
	clone.Name = CLIENT_MODULE_NAME
	clone.Parent = ReplicatedStorage
	return "module client installe : ReplicatedStorage." .. CLIENT_MODULE_NAME
end

-- Construit une tour au maximum a l'emplacement `slot` (1 a 6). Renvoie une ligne de resume.
function PerfServer.BuildTower(slot: number): string
	assert(RunService:IsRunning(), "A lancer pendant un Play")
	local player = firstPlayer()
	if player and player:GetAttribute("BaseId") == slot then
		return string.format("emplacement %d : c'est la base du joueur, pas de tour", slot)
	end
	local name = TOWER_PREFIX .. slot
	local old = Workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local devTools = ServerScriptService:FindFirstChild("DevTools")
	local source = devTools and devTools:FindFirstChild("PreviewFactory")
	assert(source and source:IsA("ModuleScript"), "DevTools.PreviewFactory introuvable")
	local module = source:Clone()
	local patched, count = module.Source:gsub(SLOT_LINE, "local SLOT = " .. slot, 1)
	assert(count == 1, "preview-factory a change : ligne '" .. SLOT_LINE .. "' introuvable")
	module.Source = patched
	module.Name = "PerfTowerBuilder" .. slot
	module.Parent = devTools
	local started = os.clock()
	local ok, result = pcall(require, module)
	module:Destroy()
	local tower = Workspace:FindFirstChild("_Preview")
	if not ok or tower == nil then
		return string.format("emplacement %d : KO %s", slot, tostring(result):sub(1, 160))
	end
	tower.Name = name
	local parts, npcs, emitters = 0, 0, 0
	for _, item in tower:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
		elseif item:IsA("Humanoid") then
			npcs += 1
		elseif item:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	return string.format(
		"emplacement %d : %d pieces, %d PNJ, %d emetteurs (%.1f s)",
		slot,
		parts,
		npcs,
		emitters,
		os.clock() - started
	)
end

-- Cadence du serveur sur `seconds` secondes.
function PerfServer.Heartbeat(seconds: number?): string
	local duration = seconds or 4
	local count, sum, worst = 0, 0, 0
	local connection = RunService.Heartbeat:Connect(function(dt: number)
		count += 1
		sum += dt
		worst = math.max(worst, dt)
	end)
	task.wait(duration)
	connection:Disconnect()
	return string.format(
		"serveur : %.1f / s, moyenne %.1f ms, pire %.1f ms, Luau %.1f Mo",
		count / duration,
		sum / math.max(count, 1) * 1000,
		worst * 1000,
		gcinfo() / 1024
	)
end

-- Installe le module client, construit les tours demandees (liste d'emplacements, peut etre vide)
-- et mesure le serveur. Un seul appel pour preparer tout le test.
function PerfServer.Setup(slots: { number }?): string
	local lines = { PerfServer.Install() }
	for _, slot in slots or {} do
		table.insert(lines, PerfServer.BuildTower(slot))
		task.wait(1) -- laisse le serveur envoyer la tour avant la suivante
	end
	table.insert(lines, PerfServer.Heartbeat(4))
	return table.concat(lines, "\n")
end

-- Rejoue la cinematique d'ouverture chez le premier joueur, sans toucher a sa sauvegarde.
-- Armer d'abord l'enregistreur cote client (PerfClient.IntroArm).
function PerfServer.ReplayIntro(): string
	local player = firstPlayer()
	assert(player, "Aucun joueur")
	player:SetAttribute("IntroPending", true)
	return "cinematique relancee pour " .. player.Name
end

-- Apres le Stop, en mode Edit : remet Studio comme avant (qualite 21, camera libre) et verifie
-- qu'il ne reste rien du test. Lancer une copie fraiche :
--   return require(game.ServerScriptService.DevTools.Perf["perf-server"]:Clone()).EditCheck()
function PerfServer.EditCheck(): string
	assert(not RunService:IsRunning(), "A lancer en mode Edit, apres le Stop")
	local rendering = (settings() :: any).Rendering
	rendering.QualityLevel = Enum.QualityLevel.Level21
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Fixed
	end
	local leftovers = {}
	for _, child in Workspace:GetChildren() do
		if child.Name:sub(1, #TOWER_PREFIX) == TOWER_PREFIX then
			table.insert(leftovers, child.Name)
		end
	end
	if ReplicatedStorage:FindFirstChild(CLIENT_MODULE_NAME) then
		table.insert(leftovers, CLIENT_MODULE_NAME)
	end
	return string.format(
		"qualite %s, camera %s, restes du test : %d %s",
		tostring(rendering.QualityLevel),
		tostring(camera and camera.CameraType),
		#leftovers,
		table.concat(leftovers, ", ")
	)
end

return PerfServer
