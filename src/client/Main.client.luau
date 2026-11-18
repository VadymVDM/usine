--!strict
-- Point d'entree client. Charge chaque ModuleScript de Controllers/,
-- appelle Init() sur tous, puis Start() sur tous.
-- Doc : docs/architecture.md

-- Rojo ne cree pas les dossiers vides : Controllers/ peut ne pas exister au debut.
local controllersFolder = script.Parent:FindFirstChild("Controllers")
local modules = if controllersFolder then controllersFolder:GetChildren() else {}

type Controller = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
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

for name, controller in loaded do
	if controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn(`[Client] {name}.Start a echoue: {err}`)
			end
		end)
	end
end

print("[Client] Mon usine de boissons : client demarre")
