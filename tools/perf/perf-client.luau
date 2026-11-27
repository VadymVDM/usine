--!strict
-- Test de performance relancable, cote CLIENT. A lancer par MCP execute_luau (datamodel Client)
-- pendant un Play Studio, APRES PerfServer.Setup (qui copie ce module dans ReplicatedStorage).
-- Jamais charge par le jeu. Source : tools/perf/perf-client.luau.
-- Mode d'emploi et valeurs de reference : docs/perf-mobile.md ("Relancer le test").
--
--   local P = require(game.ReplicatedStorage:WaitForChild("PerfClient"))
--   return P.Game()                 -- carte + tours : triangles / appels de dessin par vue et par qualite
--   return P.Breakdown()            -- d'ou viennent les triangles d'une tour (PNJ, unions, blocs...)
--   return P.IntroArm(3)            -- puis PerfServer.ReplayIntro() cote serveur, puis :
--   return P.Result()               -- resultat du travail en cours (cinematique ou Game trop long)
--   return P.Scripts(require("@rbx/LibMP"))  -- cout des scripts (MicroProfiler)
--   return P.Finish()               -- a la fin : qualite 21, camera normale
--
-- Ce que ca mesure : la CHARGE demandee a l'appareil (compteurs du moteur lus a chaque image),
-- pas les FPS d'un telephone. "Qualite telephone" = niveau de qualite graphique bas (3 et 1) +
-- attribut local PerfAsPhone, qui fait prendre au jeu ses distances "telephone"
-- (WorldDetailController, Studio seulement).
-- Reperes Roblox : ~800 000 triangles et ~600 appels de dessin (ombres non comptees).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local QUALITIES = { 21, 3, 1 } -- 21 = PC au maximum ; 3 et 1 = telephone modeste en reglage automatique
local PHONE_QUALITY_MAX = 5 -- a ce niveau et en dessous : PerfAsPhone = true
local SETTLE_SECONDS = 1.2 -- attente apres avoir pose la camera (streaming, distances du jeu)
local QUALITY_SETTLE_SECONDS = 1 -- attente en plus apres un changement de qualite
local SAMPLE_SECONDS = 0.8
local WAIT_RESULT_SECONDS = 45 -- un appel execute_luau ne doit pas durer trop longtemps
local TOWER_PREFIX = "_PerfTower"
local CAMERA_STEP = "PerfClientCamera"

-- Vues fixes de la carte (bases en x = -200, 0, 200 et z = +-90, route le long de x en z = 0).
-- A revoir si la carte change.
local MAP_VIEWS: { { any } } = {
	{ "route, le long de la route", Vector3.new(-100, 6, 0), Vector3.new(300, 80, 0) },
	{ "route, fond de carte", Vector3.new(0, 8, 0), Vector3.new(-500, 60, 0) },
	{ "vue aerienne (pire cas)", Vector3.new(350, 260, -420), Vector3.new(-100, 100, 60) },
}

-- Phases de la cinematique (secondes depuis le debut). A revoir si Config/Intro.Times change.
local INTRO_PHASES: { { any } } = {
	{ 0, 3, "ouverture" },
	{ 3, 7.8, "marche, arbre au loin" },
	{ 7.8, 12.3, "wow + course" },
	{ 12.3, 16.4, "pelle" },
	{ 16.4, 20.6, "creuse" },
	{ 20.6, 24.7, "chute + arbre en main" },
	{ 24.7, 999, "blanc + arrivee dans l'usine" },
}

local PerfClient = {}

local player = Players.LocalPlayer
local jobResult: string? = nil
local jobRunning = false
local forcedCFrame: CFrame? = nil

local function rendering(): any
	return (settings() :: any).Rendering
end

local function setQuality(level: number)
	rendering().QualityLevel = (Enum.QualityLevel :: any)[string.format("Level%02d", level)]
	player:SetAttribute("PerfAsPhone", if level <= PHONE_QUALITY_MAX then true else nil)
end

-- La camera est reposee a chaque image : un appel execute_luau qui se termine remet le type de
-- camera du debut de l'appel, ce qui rendrait la main a la camera du jeu au milieu d'une mesure.
local function holdCamera(cframe: CFrame?)
	forcedCFrame = cframe
	pcall(function()
		RunService:UnbindFromRenderStep(CAMERA_STEP)
	end)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if cframe == nil then
		camera.CameraType = Enum.CameraType.Custom
		return
	end
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Last.Value, function()
		local current = Workspace.CurrentCamera
		if current and forcedCFrame then
			current.CameraType = Enum.CameraType.Scriptable
			current.CFrame = forcedCFrame
		end
	end)
end

-- Remet la camera du jeu un peu apres la fin de l'appel (voir holdCamera).
local function releaseCameraSoon()
	task.delay(0.5, function()
		if jobRunning or player:GetAttribute("IntroPlaying") == true then
			return
		end
		holdCamera(nil)
	end)
end

type Sample = {
	frames: number,
	triangles: number,
	drawcalls: number,
	shadowTriangles: number,
	shadowDrawcalls: number,
	cpuMs: number,
	trianglesMax: number,
	drawcallsMax: number,
}

local function sample(seconds: number): Sample
	local stats = Stats :: any
	local n, tri, dc, stri, sdc, cpu, triMax, dcMax = 0, 0, 0, 0, 0, 0, 0, 0
	local connection = RunService.RenderStepped:Connect(function()
		local t, d = stats.SceneTriangleCount, stats.SceneDrawcallCount
		n += 1
		tri += t
		dc += d
		stri += stats.ShadowsTriangleCount
		sdc += stats.ShadowsDrawcallCount
		cpu += stats.RenderCPUFrameTime
		triMax = math.max(triMax, t)
		dcMax = math.max(dcMax, d)
	end)
	task.wait(seconds)
	connection:Disconnect()
	local count = math.max(n, 1)
	return {
		frames = n,
		triangles = tri / count,
		drawcalls = dc / count,
		shadowTriangles = stri / count,
		shadowDrawcalls = sdc / count,
		cpuMs = cpu / count * 1000,
		trianglesMax = triMax,
		drawcallsMax = dcMax,
	}
end

-- PNJ du monde (modeles avec un Humanoid, hors personnages des joueurs).
local function collectNpcs(): { Model }
	local list = {}
	for _, item in Workspace:GetDescendants() do
		if item:IsA("Humanoid") then
			local model = item.Parent
			if model and model:IsA("Model") and Players:GetPlayerFromCharacter(model) == nil then
				table.insert(list, model)
			end
		end
	end
	return list
end

local function countVisibleNpcs(npcs: { Model }): number
	local visible = 0
	for _, model in npcs do
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") and head.Transparency < 1 and head.LocalTransparencyModifier < 1 then
			visible += 1
		end
	end
	return visible
end

-- Tour regardee : la premiere tour au maximum du test, sinon la base du joueur.
local function focusTower(): Model?
	local towers = {}
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child.Name:sub(1, #TOWER_PREFIX) == TOWER_PREFIX then
			table.insert(towers, child)
		end
	end
	table.sort(towers, function(a, b)
		return a.Name < b.Name
	end)
	if towers[1] then
		return towers[1]
	end
	local bases = Workspace:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild("Base" .. tostring(player:GetAttribute("BaseId")))
	return if base and base:IsA("Model") then base else nil
end

local function towerViews(tower: Model): { { any } }
	local center = tower:GetBoundingBox().Position
	local front = if center.Z >= 0 then -1 else 1 -- la facade regarde la route (z = 0)
	local x, z = center.X, center.Z
	return {
		-- De derriere : devant, la tour d'en face (de l'autre cote de la route) boucherait la vue.
		{ "tour, dehors (entiere, de derriere)", Vector3.new(x, 80, z - front * 290), Vector3.new(x, 200, z) },
		{ "tour, devant le rez-de-chaussee", Vector3.new(x, 6, z + front * 110), Vector3.new(x, 12, z) },
		{ "tour, dans l'etage 1", Vector3.new(x, 9, z + front * 30), Vector3.new(x, 9, z - front * 30) },
		{ "tour, dans un etage du milieu", Vector3.new(x, 170, z + front * 30), Vector3.new(x, 170, z - front * 30) },
	}
end

local function thousands(value: number): string
	return string.format("%dk", math.round(value / 1000))
end

local function runJob(work: () -> string)
	jobResult = nil
	jobRunning = true
	task.spawn(function()
		local ok, result = pcall(work)
		jobResult = if ok then result else "KO : " .. tostring(result)
		jobRunning = false
		holdCamera(nil)
	end)
end

-- Resultat du travail en cours. Attend au plus WAIT_RESULT_SECONDS, sinon dit de rappeler.
function PerfClient.Result(): string
	local started = os.clock()
	while jobRunning and os.clock() - started < WAIT_RESULT_SECONDS do
		task.wait(0.25)
	end
	releaseCameraSoon()
	if jobRunning then
		return "EN COURS : rappeler PerfClient.Result()"
	end
	return jobResult or "aucun resultat"
end

-- Carte + tour : triangles / appels de dessin (sans les ombres), rendu processeur du PC et PNJ
-- affiches, pour chaque vue et chaque niveau de qualite.
-- options.qualities : liste de niveaux (defaut 21, 3, 1).
function PerfClient.Game(options: { qualities: { number }? }?): string
	if jobRunning then
		return PerfClient.Result()
	end
	local qualities = (options and options.qualities) or QUALITIES
	runJob(function()
		local tower = focusTower()
		local views: { { any } } = { { "vue de jeu normale", nil, nil } }
		for _, view in MAP_VIEWS do
			table.insert(views, view)
		end
		if tower then
			for _, view in towerViews(tower) do
				table.insert(views, view)
			end
		end
		local npcs = collectNpcs()
		local parts = 0
		for _, item in Workspace:GetDescendants() do
			if item:IsA("BasePart") then
				parts += 1
			end
		end
		local cells: { { string } } = {}
		for index = 1, #views do
			cells[index] = {}
		end
		for _, quality in qualities do
			setQuality(quality)
			task.wait(QUALITY_SETTLE_SECONDS)
			for index, view in views do
				holdCamera(if view[2] then CFrame.lookAt(view[2], view[3]) else nil)
				task.wait(SETTLE_SECONDS)
				local s = sample(SAMPLE_SECONDS)
				table.insert(
					cells[index],
					string.format(
						"%s/%d %.1fms %dpnj",
						thousands(s.triangles),
						math.round(s.drawcalls),
						s.cpuMs,
						countVisibleNpcs(npcs)
					)
				)
			end
		end
		setQuality(21)
		local header = {}
		for _, quality in qualities do
			table.insert(header, "Q" .. quality)
		end
		local lines = {
			string.format(
				"tour regardee : %s | client : %d pieces, %d instances, %d PNJ, Luau %.1f Mo",
				if tower then tower.Name else "aucune",
				parts,
				(Stats :: any).InstanceCount,
				#npcs,
				gcinfo() / 1024
			),
			"vue | "
				.. table.concat(header, " | ")
				.. "   (triangles / appels de dessin, rendu processeur du PC, PNJ affiches)",
		}
		for index, view in views do
			table.insert(lines, view[1] .. " | " .. table.concat(cells[index], " | "))
		end
		return table.concat(lines, "\n")
	end)
	return PerfClient.Result()
end

-- D'ou viennent les triangles de la tour regardee, vue de dehors : on retire un groupe a la fois
-- (cote client seulement, remis ensuite) et on regarde ce qui disparait.
function PerfClient.Breakdown(options: { qualities: { number }? }?): string
	if jobRunning then
		return PerfClient.Result()
	end
	local qualities = (options and options.qualities) or { 21, 3 }
	runJob(function()
		local tower = focusTower()
		assert(tower, "aucune tour a regarder")
		local npcs: { Instance } = {}
		local inNpc: { [Instance]: boolean } = {}
		for _, item in tower:GetDescendants() do
			if item:IsA("Humanoid") and item.Parent then
				table.insert(npcs, item.Parent)
				for _, part in item.Parent:GetDescendants() do
					inNpc[part] = true
				end
			end
		end
		local meshes: { Instance }, round: { Instance }, unions: { Instance }, blocks: { Instance } = {}, {}, {}, {}
		for _, item in tower:GetDescendants() do
			if item:IsA("BasePart") and not inNpc[item] then
				if item:IsA("MeshPart") then
					table.insert(meshes, item)
				elseif item:IsA("UnionOperation") then
					table.insert(unions, item)
				elseif item:IsA("Part") and item.Shape ~= Enum.PartType.Block then
					table.insert(round, item)
				else
					table.insert(blocks, item)
				end
			end
		end
		local groups: { { any } } = {
			{ "PNJ", npcs },
			{ "MeshPart hors PNJ", meshes },
			{ "pieces rondes", round },
			{ "unions", unions },
			{ "blocs et coins", blocks },
		}
		local view = towerViews(tower)[1]
		holdCamera(CFrame.lookAt(view[2], view[3]))
		local lines = {}
		for _, quality in qualities do
			setQuality(quality)
			task.wait(QUALITY_SETTLE_SECONDS + SETTLE_SECONDS)
			local base = sample(SAMPLE_SECONDS)
			local row = {
				string.format("Q%d total %s / %d", quality, thousands(base.triangles), math.round(base.drawcalls)),
			}
			for _, group in groups do
				local saved: { [Instance]: Instance? } = {}
				for _, item in group[2] do
					saved[item] = item.Parent
					item.Parent = nil
				end
				task.wait(0.8)
				local s = sample(0.4)
				for item, parent in saved do
					item.Parent = parent
				end
				table.insert(
					row,
					string.format(
						"%s (%d) : %s tri, %d appels",
						group[1],
						#group[2],
						thousands(base.triangles - s.triangles),
						math.round(base.drawcalls - s.drawcalls)
					)
				)
			end
			table.insert(lines, table.concat(row, " | "))
		end
		setQuality(21)
		table.insert(lines, "(un nombre negatif = le groupe cachait autre chose : le retirer ajoute des triangles)")
		return table.concat(lines, "\n")
	end)
	return PerfClient.Result()
end

-- Arme l'enregistreur de la cinematique au niveau de qualite donne, puis rend la main. Lancer
-- ensuite PerfServer.ReplayIntro() cote serveur, puis PerfClient.Result() (deux fois si besoin).
function PerfClient.IntroArm(quality: number?): string
	if jobRunning then
		return "un travail est deja en cours : PerfClient.Result()"
	end
	local level = quality or 21
	setQuality(level)
	runJob(function()
		local waited = os.clock()
		while player:GetAttribute("IntroPlaying") ~= true do
			if os.clock() - waited > 30 then
				error("la cinematique n'a pas demarre (PerfServer.ReplayIntro() lance ?)")
			end
			task.wait()
		end
		local stats = Stats :: any
		local start = os.clock()
		local last = start
		local frames = 0
		local acc = {}
		for index = 1, #INTRO_PHASES do
			acc[index] = { n = 0, tri = 0, dc = 0, cpu = 0, triMax = 0, dcMax = 0, dtMax = 0 }
		end
		local connection = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			local dt = now - last
			last = now
			frames += 1
			local t = now - start
			for index, phase in INTRO_PHASES do
				if t >= phase[1] and t < phase[2] then
					local a = acc[index]
					local tri, dc = stats.SceneTriangleCount, stats.SceneDrawcallCount
					a.n += 1
					a.tri += tri
					a.dc += dc
					a.cpu += stats.RenderCPUFrameTime
					a.triMax = math.max(a.triMax, tri)
					a.dcMax = math.max(a.dcMax, dc)
					a.dtMax = math.max(a.dtMax, dt)
					break
				end
			end
		end)
		task.wait(1.5)
		local set = Workspace:FindFirstChild("IntroSet", true)
		local setParts, setEmitters = 0, 0
		if set then
			for _, item in set:GetDescendants() do
				if item:IsA("BasePart") then
					setParts += 1
				elseif item:IsA("ParticleEmitter") then
					setEmitters += 1
				end
			end
		end
		while player:GetAttribute("IntroPlaying") == true and os.clock() - start < 60 do
			task.wait(0.1)
		end
		local total = os.clock() - start
		task.wait(1.5) -- premieres images dans l'usine
		connection:Disconnect()
		local lines = {
			string.format(
				"cinematique Q%d : %.1f s, %d images, decor %d pieces et %d emetteurs",
				level,
				total,
				frames,
				setParts,
				setEmitters
			),
			"phase | triangles moy (max) | appels moy (max) | rendu processeur PC | pire image",
		}
		for index, phase in INTRO_PHASES do
			local a = acc[index]
			local n = math.max(a.n, 1)
			table.insert(
				lines,
				string.format(
					"%s | %s (%s) | %d (%d) | %.1f ms | %d ms",
					phase[3],
					thousands(a.tri / n),
					thousands(a.triMax),
					math.round(a.dc / n),
					a.dcMax,
					a.cpu / n * 1000,
					math.round(a.dtMax * 1000)
				)
			)
		end
		local camera = Workspace.CurrentCamera
		table.insert(
			lines,
			string.format(
				"fin : camera %s, ClockTime %s (attendu : Custom, 12)",
				tostring(camera and camera.CameraType),
				tostring(game:GetService("Lighting").ClockTime)
			)
		)
		setQuality(21)
		return table.concat(lines, "\n")
	end)
	return string.format("enregistreur arme (qualite %d) : lancer PerfServer.ReplayIntro() cote serveur", level)
end

-- Cout des scripts sur le fil principal (serveur + client ensemble en Play Studio), lu dans le
-- MicroProfiler. Passer LibMP en argument : require("@rbx/LibMP") ne marche que depuis
-- execute_luau ou la barre de commande. A lancer SANS tours au maximum (sinon le tampon du
-- MicroProfiler ne garde qu'une image).
function PerfClient.Scripts(LibMP: any, seconds: number?): string
	LibMP.Control:EnableProfiler(true)
	LibMP.Control:EnableCapture(true)
	LibMP.Control:SetFrameLimit(64)
	task.wait(seconds or 4)
	local buffer = LibMP.Control:CaptureToBufferSync()
	LibMP.Control:EnableCapture(false)
	LibMP.Control:EnableProfiler(false)
	local session = LibMP.Session.OpenFromBuffer(buffer)
	if not session then
		return "KO : pas de donnees du MicroProfiler"
	end
	local toMs = session:FetchGlobalDesc().TickToMsCpu
	local first, last = session:GetFrameIdMin(), session:GetFrameIdMax()
	local frames = last - first + 1
	if frames < 3 then
		-- Scene trop lourde : le tampon du MicroProfiler ne garde qu'une image (vu avec 4 tours).
		session:Dispose()
		releaseCameraSoon()
		return "KO : le MicroProfiler n'a garde que "
			.. frames
			.. " image(s). Relancer dans un Play sans tours au maximum (PerfServer.Setup({}))."
	end
	local iterator = session:CreateLogIterator()
	iterator:Configure({ SkipEvents = true, SkipGpuThreads = true, ThreadIds = session:FindThreadIds("*Main*") })
	local state = iterator:GetState()
	iterator:RewindTo(first, last)
	local totals: { [number]: number } = {}
	local steps = 0
	while iterator:Step() do
		steps += 1
		if steps % 20000 == 0 then
			task.wait()
		end
		if state:IsExit() and not state:ThreadStackIsUnderflowed() and not state:ThreadStackWasOverflowed() then
			local element = iterator:GetCurrentThreadStackElement(state:ThreadStackDepth())
			if element then
				local id = state:TimerId()
				totals[id] = (totals[id] or 0) + (state:Timestamp() - element:EnterTimestamp())
			end
		end
	end
	local scripts, sum = {}, 0
	for id, ticks in totals do
		local name: string = session:FetchTimerDesc(id).TimerName
		local ms = ticks * toMs / frames
		if name:sub(1, 7) == "Script_" and ms >= 0.01 then
			table.insert(scripts, string.format("%s %.2f", name:sub(8), ms))
			sum += ms
		end
	end
	iterator:Dispose()
	session:Dispose()
	releaseCameraSoon()
	return string.format(
		"scripts (serveur + client) : %.2f ms par image sur %d images | %s",
		sum,
		frames,
		table.concat(scripts, ", ")
	)
end

-- Fin du test : qualite 21, distances normales, camera du jeu.
function PerfClient.Finish(): string
	if jobRunning then
		return "un travail est encore en cours : PerfClient.Result()"
	end
	setQuality(21)
	holdCamera(nil)
	releaseCameraSoon()
	return "qualite remise a 21, camera rendue au jeu. Faire Stop, puis PerfServer.EditCheck() en mode Edit."
end

return PerfClient
