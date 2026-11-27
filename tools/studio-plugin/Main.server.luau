--!strict
-- Plugin Studio "UsineTools" (onglet Plugins, barre "Usine"), deux boutons :
-- - "Factory Preview" : 1er clic, construit Workspace._Preview avec tools/build-map/preview-factory.luau
--   (meme fichier, copie dans le plugin a l'installation) ; 2e clic, supprime l'apercu.
--   Doc : docs/systems/apercu-edit.md
-- - "Rojo Unlock" (RojoLock.luau) : retire le verrou Rojo de l'autre dev dans Team Create.
--   Doc : docs/travailler-a-deux.md
-- Installe ou mis a jour par start-rojo.bat (rojo build --plugin).

local RunService = game:GetService("RunService")

-- Le plugin tourne aussi dans les DataModel du Play : bouton seulement en mode Edit
if not RunService:IsEdit() then
	return
end

local PREVIEW_NAME = "_Preview"
local factory = script.Parent:WaitForChild("PreviewFactory") :: ModuleScript

local toolbar = plugin:CreateToolbar("Usine")
local button = toolbar:CreateButton(
	"FactoryPreview",
	"Show or hide the whole factory in Edit mode (Workspace._Preview)",
	"rbxasset://textures/ui/GuiImagePlaceholder.png",
	"Factory Preview"
)
button.ClickableWhenViewportHidden = true

-- Bouton "Rojo Unlock" + bandeau si l'autre nous prend le verrou. Protege : une erreur ici ne doit
-- pas empecher Factory Preview de marcher.
local lockOk, lockErr = pcall(function()
	local RojoLock = require(script.Parent:WaitForChild("RojoLock") :: ModuleScript) :: any
	RojoLock.Start(toolbar)
end)
if not lockOk then
	warn("[Rojo Unlock] failed to start:", lockErr)
end

local busy = false

local function refresh()
	button:SetActive(workspace:FindFirstChild(PREVIEW_NAME) ~= nil)
end

-- Ce dont le script d'apercu a besoin. Sans ce test, ses WaitForChild attendraient pour toujours
-- (ex. place vide, ou place perso pas encore synchronisee par Rojo).
local REQUIRED = {
	{ "ReplicatedStorage", "Shared" },
	{ "ServerScriptService", "Server" },
	{ "StarterPlayer", "StarterPlayerScripts", "Client" },
	{ "ServerStorage", "BaseTemplate" },
	{ "ServerStorage", "FloorTemplate" },
	{ "Workspace", "Map", "BaseSlots" },
}

local function missingPart(): string?
	for _, path in REQUIRED do
		local node: Instance? = game:GetService(path[1] :: any)
		for i = 2, #path do
			node = if node then node:FindFirstChild(path[i]) else nil
		end
		if not node then
			return table.concat(path, ".")
		end
	end
	return nil
end

local function build()
	local missing = missingPart()
	if missing then
		warn(
			`[Factory Preview] {missing} not found. Open the shared place, or your own place with Rojo connected.`
		)
		return
	end
	print("[Factory Preview] building... (a few seconds)")
	-- Copie fraiche a chaque clic : require garde en cache le resultat du premier appel
	local copy = factory:Clone()
	copy.Parent = script.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	if ok then
		print("[Factory Preview]", result)
	else
		warn("[Factory Preview] failed:", result)
	end
end

button.Click:Connect(function()
	if busy then
		return
	end
	busy = true
	local old = workspace:FindFirstChild(PREVIEW_NAME)
	if old then
		old:Destroy()
		print("[Factory Preview] removed")
	else
		build()
	end
	busy = false
	refresh()
end)

-- Garde le bouton allume / eteint si l'apercu est cree ou supprime autrement (MCP, barre de commande)
workspace.ChildAdded:Connect(function(child)
	if child.Name == PREVIEW_NAME then
		refresh()
	end
end)
workspace.ChildRemoved:Connect(function(child)
	if child.Name == PREVIEW_NAME then
		refresh()
	end
end)
refresh()
