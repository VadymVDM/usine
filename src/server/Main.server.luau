--!strict
-- Point d'entree serveur. Charge chaque ModuleScript de Services/,
-- appelle Init() sur tous, puis Start() sur tous.
-- Doc : docs/architecture.md

-- Rojo ne cree pas les dossiers vides : Services/ peut ne pas exister au debut.
local servicesFolder = script.Parent:FindFirstChild("Services")
local modules = if servicesFolder then servicesFolder:GetChildren() else {}

type Service = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local loaded: { [string]: Service } = {}

for _, child in modules do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			loaded[child.Name] = result
		else
			warn(`[Server] Echec du chargement de {child.Name}: {result}`)
		end
	end
end

for name, service in loaded do
	if service.Init then
		local ok, err = pcall(service.Init, service)
		if not ok then
			warn(`[Server] {name}.Init a echoue: {err}`)
		end
	end
end

for name, service in loaded do
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(`[Server] {name}.Start a echoue: {err}`)
			end
		end)
	end
end

print("[Server] Mon usine de boissons : serveur demarre")
