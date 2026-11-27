--!strict
-- Touches de deplacement personnalisees (PC seulement, menu Settings, 2026-11-27).
-- Reglages Key* (attributs joueur "SettingKeyForward"... = nom d'un Enum.KeyCode, poses par
-- SettingsService). Tant que les 5 touches sont celles de Roblox (W A S D Espace), ce module ne
-- touche a rien : les controles par defaut marchent seuls.
-- Des qu'une touche change :
--   * les touches choisies et les touches par defaut W A S D Espace sont prises par
--     ContextActionService a une priorite plus haute que les controles Roblox (Sink : les controles
--     par defaut ne les voient plus) ;
--   * chaque image, APRES le module de controle Roblox (RenderPriority.Input + 1), si une touche
--     choisie est tenue : LocalPlayer:Move(direction, true) (relatif a la camera) et Humanoid.Jump.
--     Sans touche tenue on laisse faire Roblox (fleches, manette, souris restent normales).
-- KeyCode = position physique de la touche : sur AZERTY, KeyCode.W est la touche Z. L'affichage
-- passe par UserInputService:GetStringForKeyCode (SettingsController).
-- Personnage ancre (cinematique) : Move ne fait rien, rien a gerer.
-- Doc : docs/systems/interface.md (Settings > Touches)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local MovementKeysController = {}

-- Actions reglables (ordre du menu Settings). direction = vecteur relatif a la camera.
export type Action = { setting: string, title: string, description: string, direction: Vector3? }
MovementKeysController.Actions = table.freeze({
	{ setting = "KeyForward", title = "Forward", description = "Walk forward", direction = Vector3.new(0, 0, -1) },
	{ setting = "KeyBack", title = "Back", description = "Walk backward", direction = Vector3.new(0, 0, 1) },
	{ setting = "KeyLeft", title = "Left", description = "Walk left", direction = Vector3.new(-1, 0, 0) },
	{ setting = "KeyRight", title = "Right", description = "Walk right", direction = Vector3.new(1, 0, 0) },
	{ setting = "KeyJump", title = "Jump", description = "Jump in the air", direction = nil },
} :: { Action })

local BIND_NAME = "CustomMovementKeys"
local SINK_NAME = "CustomMovementSink"
local STEP_NAME = "CustomMovementStep"
local PRIORITY = Enum.ContextActionPriority.High.Value

local player = Players.LocalPlayer
local started = false
local active = false
local actionsByKey: { [Enum.KeyCode]: { Action } } = {}
local held: { [Action]: boolean } = {}

-- Touche reglee pour une action (attribut du serveur, sinon la defaut), en KeyCode.
function MovementKeysController.GetKey(setting: string): Enum.KeyCode
	local default = GameConfig.DefaultSettings[setting]
	local value = player:GetAttribute("Setting" .. setting)
	local name = if type(value) == "string" and GameConfig.RebindableKeys[value] == true then value else default
	local ok, keyCode = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and typeof(keyCode) == "EnumItem" then
		return keyCode :: Enum.KeyCode
	end
	return Enum.KeyCode.Unknown
end

local function clearHeld()
	table.clear(held)
end

local function onKey(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local list = actionsByKey[input.KeyCode]
	if list then
		for _, action in list do
			local down = state == Enum.UserInputState.Begin or (state == Enum.UserInputState.Change and held[action] == true)
			held[action] = if down then true else nil
			if action.direction == nil and state == Enum.UserInputState.Begin then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Jump = true -- tout de suite, sans attendre l'image suivante
				end
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onSink(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function step()
	local move = Vector3.zero
	local jump = false
	for action in held do
		if action.direction then
			move += action.direction
		else
			jump = true
		end
	end
	if move.Magnitude > 0 then
		player:Move(move.Unit, true)
	end
	if jump then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = true
		end
	end
end

local function stop()
	if not active then
		return
	end
	active = false
	ContextActionService:UnbindAction(BIND_NAME)
	ContextActionService:UnbindAction(SINK_NAME)
	RunService:UnbindFromRenderStep(STEP_NAME)
	table.clear(actionsByKey)
	clearHeld()
end

-- Relit les 5 touches et branche (ou debranche) le remplacement des controles.
local function rebuild()
	stop()
	local custom = false
	local keys: { Enum.KeyCode } = {}
	for _, action in MovementKeysController.Actions do
		local keyCode = MovementKeysController.GetKey(action.setting)
		if keyCode == Enum.KeyCode.Unknown then
			continue
		end
		if keyCode.Name ~= GameConfig.DefaultSettings[action.setting] then
			custom = true
		end
		local list = actionsByKey[keyCode]
		if list == nil then
			list = {}
			actionsByKey[keyCode] = list
			table.insert(keys, keyCode)
		end
		table.insert(list, action)
	end
	if not custom then
		table.clear(actionsByKey)
		return -- touches de Roblox : rien a remplacer
	end
	active = true
	ContextActionService:BindActionAtPriority(BIND_NAME, onKey, false, PRIORITY, table.unpack(keys))
	-- Touches par defaut plus utilisees par aucune action : bloquees (sinon W avancerait encore)
	local sinks: { Enum.KeyCode } = {}
	for _, action in MovementKeysController.Actions do
		local default = (Enum.KeyCode :: any)[GameConfig.DefaultSettings[action.setting]] :: Enum.KeyCode
		if actionsByKey[default] == nil and not table.find(sinks, default) then
			table.insert(sinks, default)
		end
	end
	if #sinks > 0 then
		ContextActionService:BindActionAtPriority(SINK_NAME, onSink, false, PRIORITY, table.unpack(sinks))
	end
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Input.Value + 1, step)
end

function MovementKeysController:Init() end

function MovementKeysController:Start()
	if started then
		return
	end
	started = true
	local scheduled = false
	local function schedule()
		-- Plusieurs touches changent ensemble (echange, Reset) : un seul rebranchement
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			rebuild()
		end)
	end
	for _, action in MovementKeysController.Actions do
		player:GetAttributeChangedSignal("Setting" .. action.setting):Connect(schedule)
	end
	-- Fenetre qui perd le focus : les touches relachees ailleurs ne doivent pas rester tenues
	UserInputService.WindowFocusReleased:Connect(clearHeld)
	UserInputService.TextBoxFocused:Connect(clearHeld)
	rebuild()
end

return MovementKeysController
