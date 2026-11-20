--!strict
-- Point d'entree client. Charge chaque ModuleScript de Controllers/,
-- appelle Init() sur tous, puis Start() sur tous, puis Prewarm() (optionnel) une fois Start fini.
-- Quand tout est pret, pose l'attribut joueur "ClientReady" : le prechargement
-- (ReplicatedFirst/Preloader) attend ce signal avant de montrer l'interface.
-- Doc : docs/architecture.md, docs/systems/chargement.md

local Players = game:GetService("Players")

-- Delai max pour qu'un Start() se termine avant son Prewarm (certains Start bouclent pour toujours).
local START_TIMEOUT = 10

-- Rojo ne cree pas les dossiers vides : Controllers/ peut ne pas exister au debut.
local controllersFolder = script.Parent:FindFirstChild("Controllers")
local modules = if controllersFolder then controllersFolder:GetChildren() else {}

type Controller = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	-- Prepare en coulisse ce qui serait moche a la premiere ouverture (ex. mise en page du Shop).
	-- Appele pendant que l'interface est encore cachee, apres la fin de Start().
	Prewarm: ((self: any) -> ())?,
}

local loaded: { [string]: Controller } = {}

for _, child in modules do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			loaded[child.Name] = result
		else
			warn(`[Client] Echec du chargement de {child.Name}: {result}`)
		end
	end
end

for name, controller in loaded do
	if controller.Init then
		local ok, err = pcall(controller.Init, controller)
		if not ok then
			warn(`[Client] {name}.Init a echoue: {err}`)
		end
	end
end

local startDone: { [string]: boolean } = {}

for name, controller in loaded do
	if controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn(`[Client] {name}.Start a echoue: {err}`)
			end
			startDone[name] = true
		end)
	else
		startDone[name] = true
	end
end

task.spawn(function()
	for name, controller in loaded do
		local prewarm = controller.Prewarm
		if prewarm then
			local startedAt = os.clock()
			while not startDone[name] and os.clock() - startedAt < START_TIMEOUT do
				task.wait(0.1)
			end
			if startDone[name] then
				local ok, err = pcall(prewarm, controller)
				if not ok then
					warn(`[Client] {name}.Prewarm a echoue: {err}`)
				end
			end
		end
	end
	Players.LocalPlayer:SetAttribute("ClientReady", true)
end)

print("[Client] Mon usine de boissons : client demarre")
