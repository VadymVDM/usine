--!strict
-- Touche E : montre les ProximityPrompt des bases seulement dans SA base et seulement quand le
-- serveur dit que l'action est possible (attribut "Active" ~= false). Le serveur ne change jamais
-- `Enabled` : ce module est le seul a le faire, en local. Le serveur reverifie chaque action.
-- Exception (2026-11-27) : les prompts avec l'attribut "ForOthers" (Steal du pass Thief,
-- ThiefService) se montrent au contraire seulement dans les bases des AUTRES joueurs.
-- Doc : docs/systems/interface.md (section Touche E)

local Players = game:GetService("Players")

local PromptController = {}

local player = Players.LocalPlayer
local promptBase: { [ProximityPrompt]: Model } = {}
local started = false

local function isMine(base: Model): boolean
	return base:GetAttribute("OwnerUserId") == player.UserId
end

local function refresh(prompt: ProximityPrompt)
	local base = promptBase[prompt]
	if base == nil then
		return
	end
	local forOthers = prompt:GetAttribute("ForOthers") == true
	local ownerId = base:GetAttribute("OwnerUserId")
	local owned = type(ownerId) == "number" and ownerId > 0
	local inRightBase = if forOthers then owned and not isMine(base) else isMine(base)
	local wanted = inRightBase and prompt:GetAttribute("Active") ~= false
	if prompt.Enabled ~= wanted then
		prompt.Enabled = wanted
	end
end

local function track(prompt: ProximityPrompt, base: Model)
	if promptBase[prompt] ~= nil then
		return
	end
	promptBase[prompt] = base
	refresh(prompt)
	local attributeConnection = prompt:GetAttributeChangedSignal("Active"):Connect(function()
		refresh(prompt)
	end)
	prompt.AncestryChanged:Connect(function()
		if not prompt:IsDescendantOf(workspace) then
			promptBase[prompt] = nil
			attributeConnection:Disconnect()
		end
	end)
end

local function registerBase(base: Instance)
	if not base:IsA("Model") then
		return
	end
	for _, item in base:GetDescendants() do
		if item:IsA("ProximityPrompt") then
			track(item, base)
		end
	end
	base.DescendantAdded:Connect(function(item: Instance)
		if item:IsA("ProximityPrompt") then
			track(item, base)
		end
	end)
	base:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		for prompt, owner in promptBase do
			if owner == base then
				refresh(prompt)
			end
		end
	end)
end

function PromptController.Init() end

function PromptController.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local bases = workspace:WaitForChild("Bases", 60)
		if bases == nil then
			return
		end
		for _, base in bases:GetChildren() do
			registerBase(base)
		end
		bases.ChildAdded:Connect(registerBase)
	end)
end

return PromptController
