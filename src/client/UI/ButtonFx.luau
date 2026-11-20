--!strict
-- Retour visuel commun de TOUS les boutons de l'interface (retour de test du 2026-11-20 : "des fois
-- il y a l'animation au survol, des fois non, ca depend les interfaces"). Une seule animation,
-- branchee automatiquement :
--   * survol (souris / manette) : le bouton grossit (x1.10, effet Back) + son "Hover" ;
--   * appui (souris, doigt, manette A) : il s'ecrase (x0.91), puis rebondit au relachement + son "Click" ;
--   * ecran tactile sans souris : pas de survol (un appui declencherait MouseEnter), seulement l'appui.
-- Branche par MenuController (HUD + menus du ShopGUI) et par ButtonFxController (tous les autres
-- ScreenGui, y compris ceux crees plus tard). Bind est sans effet sur un bouton deja branche.
-- Bouton ignore : attribut NoButtonFx = true (sur lui ou un parent), Selectable = false (fond qui
-- ferme une fenetre, zone de prise d'une barre de defilement), ou un UIScale qui appartient a un
-- autre effet (nom autre que "UIScale" / "ButtonFeedbackScale" / "DiscoveryBounce").
-- Les sons sont joues par la fonction donnee a SetSoundPlayer (MenuController : sons du pack UI).
-- Attribut FxTarget = nom d'un enfant : c'est cet enfant qui grossit / retrecit, pas le bouton. Pour
-- un bouton range dans un UIListLayout (bouton X des menus) : la liste recollait le bouton reduit
-- dans un coin ; l'enfant centre (plaque rouge) retrecit, lui, au centre (2026-11-20).
-- Doc : docs/systems/interface.md (section Retour des boutons)

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ButtonFx = {}

local HOVER_SCALE = 1.10
local PRESS_SCALE = 0.91
local OWN_SCALE_NAMES = { UIScale = true, ButtonFeedbackScale = true, DiscoveryBounce = true }

type State = {
	scale: UIScale,
	base: number,
	token: number,
	hovered: boolean,
	pressed: boolean,
	tween: Tween?,
	connections: { RBXScriptConnection },
}

local states: { [GuiButton]: State } = {}
local skipped: { [GuiButton]: boolean } = {}
local soundPlayer: ((name: string) -> ())? = nil

function ButtonFx.SetSoundPlayer(callback: (name: string) -> ())
	soundPlayer = callback
end

local function playSound(name: string)
	if soundPlayer then
		soundPlayer(name)
	end
end

local function optedOut(button: GuiButton): boolean
	if button.Selectable == false then
		return true
	end
	local current: Instance? = button
	while current and not current:IsA("LayerCollector") do
		if current:GetAttribute("NoButtonFx") == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function animate(state: State, factor: number, duration: number, style: Enum.EasingStyle?): Tween
	if state.tween then
		state.tween:Cancel()
	end
	local tween = TweenService:Create(
		state.scale,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = state.base * factor }
	)
	state.tween = tween
	tween:Play()
	return tween
end

local function rebound(state: State)
	state.token += 1
	local token = state.token
	local resting = if state.hovered then HOVER_SCALE else 1
	local tween = animate(state, if state.hovered then 1.14 else 1.04, 0.08, Enum.EasingStyle.Cubic)
	tween.Completed:Once(function(status)
		if token ~= state.token or state.pressed or status ~= Enum.PlaybackState.Completed then
			return
		end
		animate(state, resting, 0.135, Enum.EasingStyle.Sine)
	end)
end

local function isPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonA
end

local function forget(button: GuiButton)
	local state = states[button]
	if state then
		for _, c in state.connections do
			c:Disconnect()
		end
		states[button] = nil
	end
	skipped[button] = nil
end

-- Branche l'animation sur un bouton. Renvoie vrai si le bouton est (ou etait deja) branche.
-- force = reprendre l'UIScale du bouton quel que soit son nom (boutons du pack UI, MenuController).
function ButtonFx.Bind(button: GuiButton, force: boolean?): boolean
	if states[button] then
		return true
	end
	if not force and (skipped[button] or optedOut(button)) then
		return false
	end
	-- Objet qui change de taille : le bouton, ou l'enfant nomme par l'attribut FxTarget
	local target: GuiObject = button
	local targetName = button:GetAttribute("FxTarget")
	if type(targetName) == "string" then
		local child = button:FindFirstChild(targetName)
		if child and child:IsA("GuiObject") then
			target = child
		end
	end
	local scale = target:FindFirstChildOfClass("UIScale")
	if scale and not force and not OWN_SCALE_NAMES[scale.Name] then
		skipped[button] = true -- UIScale d'un autre effet (pulsation...) : on ne s'y melange pas
		return false
	end
	if scale == nil then
		local created = Instance.new("UIScale")
		created.Name = "ButtonFeedbackScale"
		created.Parent = target
		scale = created
	end
	button.AutoButtonColor = false
	local state: State = {
		scale = scale :: UIScale,
		base = (scale :: UIScale).Scale,
		token = 0,
		hovered = false,
		pressed = false,
		tween = nil,
		connections = {},
	}
	states[button] = state
	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(state.connections, signal:Connect(callback))
	end

	local function setHovered(hovered: boolean)
		if state.hovered == hovered then
			return
		end
		state.hovered = hovered
		state.token += 1
		if hovered then
			playSound("Hover")
		end
		if not state.pressed then
			animate(
				state,
				if hovered then HOVER_SCALE else 1,
				if hovered then 0.105 else 0.12,
				if hovered then Enum.EasingStyle.Back else Enum.EasingStyle.Sine
			)
		end
	end

	connect(button.MouseEnter, function()
		-- Ecran tactile sans souris : un appui declenche MouseEnter (bouton bloque agrandi)
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		setHovered(true)
	end)
	connect(button.MouseLeave, function()
		setHovered(false)
	end)
	connect(button.SelectionGained, function()
		setHovered(true)
	end)
	connect(button.SelectionLost, function()
		setHovered(false)
	end)
	connect(button.InputBegan, function(input: InputObject)
		if not isPressInput(input) then
			return
		end
		state.pressed = true
		state.token += 1
		animate(state, PRESS_SCALE, 0.045, Enum.EasingStyle.Cubic)
	end)
	connect(button.InputEnded, function(input: InputObject)
		if not isPressInput(input) or not state.pressed then
			return
		end
		state.pressed = false
		rebound(state)
	end)
	connect(button.Activated, function()
		state.pressed = false
		if button.Name ~= "ExitButton" then
			playSound("Click")
		end
		rebound(state)
	end)
	-- Bouton cache ou detruit : retour a sa taille de repos (sinon il reste agrandi a la reouverture)
	connect(button:GetPropertyChangedSignal("Visible"), function()
		if not button.Visible then
			ButtonFx.Reset(button)
		end
	end)
	connect(button.AncestryChanged, function()
		if button.Parent == nil then
			forget(button)
		end
	end)
	return true
end

-- Debranche un bouton (et retire l'UIScale cree par ButtonFx) : pour le rebrancher autrement,
-- ex. apres avoir pose l'attribut FxTarget (bouton X des menus, MenuController).
function ButtonFx.Unbind(button: GuiButton)
	local state = states[button]
	if state and state.scale.Name == "ButtonFeedbackScale" then
		state.scale:Destroy()
	end
	forget(button)
end

-- Remet un bouton a sa taille de repos (menu ferme pendant un survol...).
function ButtonFx.Reset(button: GuiButton)
	local state = states[button]
	if state == nil then
		return
	end
	state.token += 1
	state.hovered = false
	state.pressed = false
	if state.tween then
		state.tween:Cancel()
	end
	state.scale.Scale = state.base
end

-- Remet a leur taille de repos tous les boutons branches sous `root`.
function ButtonFx.ResetUnder(root: Instance)
	for button in states do
		if button:IsDescendantOf(root) then
			ButtonFx.Reset(button)
		end
	end
end

-- Branche tous les boutons sous `root`, maintenant et ceux ajoutes plus tard. `filter` (optionnel)
-- dit si un bouton doit etre branche. Renvoie la connexion (a deconnecter si root disparait).
function ButtonFx.AutoBind(root: Instance, filter: ((button: GuiButton) -> boolean)?): RBXScriptConnection
	local function consider(item: Instance)
		if item:IsA("GuiButton") and (filter == nil or filter(item)) then
			-- differe : le controleur qui cree le bouton finit de le remplir (attributs, UIScale...)
			task.defer(function()
				if item.Parent ~= nil then
					ButtonFx.Bind(item)
				end
			end)
		end
	end
	for _, item in root:GetDescendants() do
		consider(item)
	end
	return root.DescendantAdded:Connect(consider)
end

return ButtonFx
