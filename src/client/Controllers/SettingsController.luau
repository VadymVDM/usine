--!strict
-- Menu Settings (menu "Settings" du pack, ouvert par l'engrenage en haut) :
--   Music       : curseur de volume de la musique de fond (MusicController), 0-100 % ;
--   Sounds      : curseur de volume des sons du jeu et de l'interface (SoundFx.Group) ;
--   Low Quality : interrupteur, sans ombres, effets d'eclairage, particules ni decor lointain ;
--   Forward / Back / Left / Right / Jump + Reset Keys (PC seulement, 2026-11-27) : clic sur la
--     touche, puis appui sur la nouvelle touche (Echap annule). Une touche deja prise par une autre
--     action est echangee. Lignes visibles seulement si le joueur joue clavier + souris
--     (UserInputService.PreferredInput). Le deplacement lui-meme : MovementKeysController.
-- (Music et Sounds etaient des interrupteurs ON / OFF jusqu'au 2026-11-23.)
-- Le curseur / le clic change l'attribut joueur "Setting<Cle>" tout de suite (le son suit en direct)
-- et envoie SetSetting au serveur (SettingsService), qui sauvegarde et repose l'attribut.
-- Doc : docs/systems/interface.md (Settings)

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local MovementKeys = require(script.Parent:WaitForChild("MovementKeysController"))

local SettingsController = {}

-- Interrupteurs = boutons communs de l'interface (vert ON / rouge OFF, comme YES / NO).
type Toggle = { button: TextButton, label: TextLabel, gradient: UIGradient?, stroke: UIStroke? }
-- Curseur de volume : barre, remplissage vert, bouton rond, pourcentage au-dessus.
type Slider = { fill: Frame, knob: Frame, label: TextLabel, dragging: boolean, value: number }
-- Lignes du menu : cle du reglage -> nom de la ligne dans le pack, textes affiches (anglais)
local ROWS = {
	{ key = "Music", row = "Music", title = "Music", description = "Music volume" },
	{ key = "Effects", row = "Effects", title = "Sounds", description = "Sound effects volume" },
	{ key = "LowQuality", row = "LowQuality", title = "Low Quality", description = "No shadows, faster game" },
}

local player = Players.LocalPlayer
local started = false
local setEvent: RemoteEvent? = nil
local toggles: { [string]: Toggle } = {}
local sliders: { [string]: Slider } = {}
-- Boutons des touches de deplacement (reglage Key* -> bouton) et lignes PC seulement
local keyButtons: { [string]: Toggle } = {}
local keyRows: { GuiObject } = {}
local capturing: string? = nil -- reglage Key* qui attend une touche
local captureConnection: RBXScriptConnection? = nil
local SEND_INTERVAL = 0.3 -- pendant le glissement : une demande au serveur au plus toutes les 0.3 s
local lowQualityOn = false

-- Valeur actuelle d'un reglage (attribut du serveur, sinon valeur par defaut).
local function getSetting(key: string): boolean
	local value = player:GetAttribute("Setting" .. key)
	if type(value) == "boolean" then
		return value
	end
	return GameConfig.DefaultSettings[key] == true
end

-- Valeur actuelle d'un volume 0..1 (ancien booleen false = 0).
local function getVolume(key: string): number
	local value = player:GetAttribute("Setting" .. key)
	if type(value) == "number" then
		return math.clamp(value, 0, 1)
	elseif value == false then
		return 0
	end
	local default = GameConfig.DefaultSettings[key]
	return if type(default) == "number" then default else 1
end

local function isVolume(key: string): boolean
	return type(GameConfig.DefaultSettings[key]) == "number"
end

---------------------------------------------------------------------------------------------
-- Low Quality : ombres, effets d'eclairage, particules, decor lointain

local savedLighting: { [Instance]: { [string]: any } } = {}
local emitterWanted: { [Instance]: boolean } = {} -- valeur voulue par le serveur pendant le mode
local emitterConnections: { [Instance]: RBXScriptConnection } = {}
local addedConnection: RBXScriptConnection? = nil
local hiddenDecor: Instance? = nil
local decorParent: Instance? = nil

-- Attribut KeepInLowQuality = true : effet utile au jeu (ligne de guidage du tutoriel), jamais eteint
local function isEmitter(item: Instance): boolean
	if item:GetAttribute("KeepInLowQuality") == true then
		return false
	end
	return item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") or item:IsA("Sparkles") or item:IsA("Smoke") or item:IsA("Fire")
end

local function muteEmitter(item: Instance)
	if emitterConnections[item] then
		return
	end
	local emitter = item :: any
	emitterWanted[item] = emitter.Enabled
	emitter.Enabled = false
	emitterConnections[item] = item:GetPropertyChangedSignal("Enabled"):Connect(function()
		if lowQualityOn and emitter.Enabled then
			emitterWanted[item] = true -- le serveur l'a allume : on s'en souvient, on le garde eteint
			emitter.Enabled = false
		end
	end)
end

local function saveProps(item: Instance, props: { string })
	if savedLighting[item] then
		return
	end
	local saved: { [string]: any } = {}
	for _, name in props do
		saved[name] = (item :: any)[name]
	end
	savedLighting[item] = saved
end

local function applyLowQuality(on: boolean)
	if on == lowQualityOn then
		return
	end
	lowQualityOn = on
	if on then
		saveProps(Lighting, { "GlobalShadows" })
		Lighting.GlobalShadows = false
		for _, effect in Lighting:GetChildren() do
			if effect:IsA("PostEffect") and effect.Name ~= "MenuBackgroundBlur" and not effect:IsA("ColorCorrectionEffect") then
				saveProps(effect, { "Enabled" })
				effect.Enabled = false
			elseif effect:IsA("Atmosphere") then
				saveProps(effect, { "Density", "Haze", "Glare" })
				effect.Density = 0
				effect.Haze = 0
				effect.Glare = 0
			end
		end
		for _, item in workspace:GetDescendants() do
			if isEmitter(item) then
				muteEmitter(item)
			end
		end
		addedConnection = workspace.DescendantAdded:Connect(function(item: Instance)
			if isEmitter(item) then
				muteEmitter(item)
			end
		end)
		-- Forets de la carte : cachees localement. Les collines (Decor.Hills) restent : tres
		-- legeres (60 x 3 blocs) et elles ferment l'horizon (2026-11-27).
		local map = workspace:FindFirstChild("Map")
		local decor = map and map:FindFirstChild("Decor")
		local trees = decor and decor:FindFirstChild("Trees")
		if trees then
			hiddenDecor = trees
			decorParent = decor
			trees.Parent = nil
		end
	else
		for item, props in savedLighting do
			for name, value in props do
				(item :: any)[name] = value
			end
		end
		table.clear(savedLighting)
		if addedConnection then
			addedConnection:Disconnect()
			addedConnection = nil
		end
		for item, connection in emitterConnections do
			connection:Disconnect()
			if item.Parent ~= nil then
				(item :: any).Enabled = emitterWanted[item] == true
			end
		end
		table.clear(emitterConnections)
		table.clear(emitterWanted)
		if hiddenDecor and decorParent and decorParent.Parent ~= nil then
			hiddenDecor.Parent = decorParent
		end
		hiddenDecor = nil
		decorParent = nil
	end
end

---------------------------------------------------------------------------------------------
-- Application des reglages

local function getMusic(): any
	local module = script.Parent:FindFirstChild("MusicController")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			return result
		end
	end
	return nil
end

local function paintToggle(key: string)
	local toggle = toggles[key]
	if toggle == nil then
		return
	end
	local on = getSetting(key)
	local colors = if on then PackStyle.GREEN else PackStyle.RED
	toggle.label.Text = if on then "ON" else "OFF"
	if toggle.gradient then
		toggle.gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	if toggle.stroke then
		toggle.stroke.Color = colors[3]
	end
end

local function paintSlider(key: string, value: number)
	local slider = sliders[key]
	if slider == nil then
		return
	end
	slider.value = value
	slider.fill.Size = UDim2.fromScale(value, 1)
	slider.knob.Position = UDim2.fromScale(value, 0.5)
	slider.label.Text = `{math.round(value * 100)}%`
end

local paintKey: (setting: string) -> ()

local function apply(key: string)
	if type(GameConfig.DefaultSettings[key]) == "string" then
		paintKey(key)
		return
	end
	if isVolume(key) then
		local value = getVolume(key)
		if key == "Music" then
			local music = getMusic()
			if music and music.SetVolume then
				music.SetVolume(value)
			end
		end
		-- Pendant le glissement, le curseur suit le doigt (pas l'echo du serveur, en retard)
		local slider = sliders[key]
		if slider and not slider.dragging then
			paintSlider(key, value)
		end
		return
	end
	if key == "LowQuality" then
		applyLowQuality(getSetting(key))
	end
	paintToggle(key)
end

local function onToggle(key: string)
	local wanted = not getSetting(key)
	-- Tout de suite a l'ecran ; le serveur confirme (ou remet la bonne valeur)
	player:SetAttribute("Setting" .. key, wanted)
	if setEvent then
		setEvent:FireServer(key, wanted)
	end
end

-- Curseur de volume dans la case de l'interrupteur du pack (souris et doigt).
local function buildSlider(key: string, parent: Frame, list: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "VolumeSlider"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(0.92, 0.9)
	holder.ZIndex = 3
	holder.Parent = parent

	local label = PackStyle.label(holder, "100%", UDim2.fromScale(0.5, 0.02), UDim2.fromScale(1, 0.38), 30)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.68)
	track.Size = UDim2.fromScale(0.84, 0.2)
	track.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
	track.ZIndex = 3
	track.Parent = holder
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	PackStyle.stroke(track, 2.5, PackStyle.TEXT_STROKE, Enum.ApplyStrokeMode.Border)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.ZIndex = 4
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = ColorSequence.new(PackStyle.GREEN[1], PackStyle.GREEN[2])
	gradient.Parent = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(1, 0.5)
	knob.Size = UDim2.fromScale(2.2, 2.2) -- 2.2 x la hauteur de la barre, rond
	knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 5
	knob.Parent = track
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	PackStyle.stroke(knob, 3, PackStyle.GREEN[3], Enum.ApplyStrokeMode.Border)

	-- Zone de prise large (plus facile au doigt que la barre fine)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.68)
	hit.Size = UDim2.fromScale(1, 0.7)
	hit.ZIndex = 6
	hit.Parent = holder

	local slider: Slider = { fill = fill, knob = knob, label = label, dragging = false, value = getVolume(key) }
	sliders[key] = slider

	local lastSent = 0
	local sentValue: number? = nil
	local function send(force: boolean)
		local value = slider.value
		local event = setEvent
		if value == sentValue or event == nil then
			return
		end
		if not force and os.clock() - lastSent < SEND_INTERVAL then
			return
		end
		lastSent = os.clock()
		sentValue = value
		event:FireServer(key, value)
	end
	local function setFromX(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local value = math.round(math.clamp((x - track.AbsolutePosition.X) / width, 0, 1) * 100) / 100
		paintSlider(key, value)
		player:SetAttribute("Setting" .. key, value) -- le son suit tout de suite
		send(false)
	end
	local scrolling: ScrollingFrame? = if list:IsA("ScrollingFrame") then list else nil
	local function stopDrag()
		if not slider.dragging then
			return
		end
		slider.dragging = false
		if scrolling then
			scrolling.ScrollingEnabled = true
		end
		send(true)
	end
	hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			slider.dragging = true
			sentValue = nil
			if scrolling then
				scrolling.ScrollingEnabled = false -- le doigt glisse le curseur, pas la liste
			end
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if not slider.dragging then
			return
		end
		if kind == Enum.UserInputType.MouseMovement then
			-- Bouton relache sans InputEnded (relache hors de la fenetre...) : on arrete
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				stopDrag()
				return
			end
			setFromX(input.Position.X)
		elseif kind == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			stopDrag()
		end
	end)
	paintSlider(key, slider.value)
end

---------------------------------------------------------------------------------------------
-- Menu

-- Texte d'une ligne. Les zones de texte du pack sont etroites (un titre long comme "Low Quality"
-- devenait plus petit que "Music") : on les elargit, alignees a gauche, pour la meme taille partout.
local function setText(row: Instance, name: string, text: string)
	local label = row:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
		label.Size = UDim2.fromScale(0.95, label.Size.Y.Scale)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = false
		label.TextScaled = true
	end
end

---------------------------------------------------------------------------------------------
-- Touches de deplacement (PC)

-- Noms lisibles des touches sans caractere ; les lettres passent par GetStringForKeyCode, qui
-- donne la lettre du clavier du joueur (KeyCode.W -> "Z" sur AZERTY).
local KEY_NAMES: { [string]: string } = {
	Space = "Space",
	LeftShift = "L-Shift",
	RightShift = "R-Shift",
	LeftControl = "L-Ctrl",
	RightControl = "R-Ctrl",
	Up = "Up",
	Down = "Down",
	Left = "Left",
	Right = "Right",
}

local function keyText(keyCode: Enum.KeyCode): string
	local friendly = KEY_NAMES[keyCode.Name]
	if friendly then
		return friendly
	end
	local ok, text = pcall(function()
		return UserInputService:GetStringForKeyCode(keyCode)
	end)
	if ok and type(text) == "string" and string.match(text, "%S") then
		return string.upper(text)
	end
	return keyCode.Name
end

local function colorButton(entry: Toggle, colors: { Color3 })
	if entry.gradient then
		entry.gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	if entry.stroke then
		entry.stroke.Color = colors[3]
	end
end

function paintKey(setting: string)
	local entry = keyButtons[setting]
	if entry == nil then
		return
	end
	if capturing == setting then
		entry.label.Text = "..."
		colorButton(entry, PackStyle.GREEN)
		return
	end
	entry.label.Text = keyText(MovementKeys.GetKey(setting))
	colorButton(entry, PackStyle.PURPLE)
end

local function sendSetting(key: string, value: string)
	player:SetAttribute("Setting" .. key, value) -- tout de suite ; le serveur confirme
	if setEvent then
		setEvent:FireServer(key, value)
	end
end

local function stopCapture()
	local was = capturing
	capturing = nil
	if captureConnection then
		captureConnection:Disconnect()
		captureConnection = nil
	end
	if was then
		paintKey(was)
	end
end

-- Nouvelle touche pour `setting`. Deja prise par une autre action : l'autre recoit l'ancienne.
local function assignKey(setting: string, keyCode: Enum.KeyCode)
	local old = MovementKeys.GetKey(setting)
	if keyCode == old then
		return
	end
	for _, action in MovementKeys.Actions do
		if action.setting ~= setting and MovementKeys.GetKey(action.setting) == keyCode then
			sendSetting(action.setting, old.Name)
		end
	end
	sendSetting(setting, keyCode.Name)
end

local function refuse(setting: string)
	local entry = keyButtons[setting]
	if entry == nil then
		return
	end
	entry.label.Text = "NO"
	colorButton(entry, PackStyle.RED)
	task.delay(0.8, function()
		if capturing ~= setting then
			paintKey(setting)
		end
	end)
end

local function startCapture(setting: string)
	stopCapture()
	capturing = setting
	paintKey(setting)
	captureConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			local keyCode = input.KeyCode
			stopCapture()
			if keyCode == Enum.KeyCode.Escape then
				return -- annule
			end
			if GameConfig.RebindableKeys[keyCode.Name] ~= true then
				refuse(setting) -- touche de Roblox ou du jeu (E, I, O, Tab, chiffres...)
				return
			end
			assignKey(setting, keyCode)
		elseif
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.MouseButton2
			or kind == Enum.UserInputType.Touch
		then
			stopCapture() -- clic ailleurs : annule
		end
	end)
end

local function resetKeys()
	stopCapture()
	for _, action in MovementKeys.Actions do
		local default = GameConfig.DefaultSettings[action.setting]
		if type(default) == "string" and MovementKeys.GetKey(action.setting).Name ~= default then
			sendSetting(action.setting, default)
		end
	end
end

-- Joueur clavier + souris ? (PreferredInput change en cours de partie : manette, ecran tactile...)
local function isKeyboardPlayer(): boolean
	local ok, preferred = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and preferred ~= nil then
		return preferred == (Enum :: any).PreferredInput.KeyboardAndMouse
	end
	return UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
end

local function updateKeyRows()
	local pc = isKeyboardPlayer()
	for _, row in keyRows do
		row.Visible = pc
	end
	if not pc then
		stopCapture()
	end
end

-- Bouton commun PackStyle dans la case du bouton du pack (comme les interrupteurs).
local function makeRowButton(row: Instance, colors: { Color3 }, text: string): Toggle?
	local toggleFrame = row:FindFirstChild("Toggle", true)
	local packButton = toggleFrame and toggleFrame:FindFirstChildWhichIsA("GuiButton", true)
	if packButton == nil or packButton:FindFirstChild("Switch") then
		return nil
	end
	packButton.Name = "KeyButton"
	for _, child in packButton:GetChildren() do
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end
	local button = PackStyle.button(packButton, "Switch", colors, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 1))
	local label = PackStyle.label(button, text, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 40)
	return {
		button = button,
		label = label,
		gradient = button:FindFirstChildOfClass("UIGradient"),
		stroke = button:FindFirstChildOfClass("UIStroke"),
	}
end

-- Lignes des touches : copies de la ligne "Effects" du pack, apres les 3 reglages.
local function buildKeyRows(list: Instance, template: Instance)
	local entries: { { name: string, title: string, description: string } } = {}
	local defaults: { string } = {}
	for _, action in MovementKeys.Actions do
		table.insert(entries, { name = action.setting, title = action.title, description = action.description })
		local keyCode = (Enum.KeyCode :: any)[GameConfig.DefaultSettings[action.setting]] :: Enum.KeyCode
		table.insert(defaults, keyText(keyCode))
	end
	table.insert(entries, { name = "ResetKeys", title = "Reset Keys", description = "Back to " .. table.concat(defaults, " ") })

	for index, entry in entries do
		if list:FindFirstChild(entry.name) then
			continue
		end
		local row = template:Clone()
		row.Name = entry.name
		if row:IsA("GuiObject") then
			row.LayoutOrder = #ROWS + index
			table.insert(keyRows, row)
		end
		row.Parent = list
		setText(row, "SettingName", entry.title)
		setText(row, "Description", entry.description)
		if entry.name == "ResetKeys" then
			local made = makeRowButton(row, PackStyle.RED, "RESET")
			if made then
				made.button.Activated:Connect(resetKeys)
			end
		else
			local made = makeRowButton(row, PackStyle.PURPLE, "")
			if made then
				local setting = entry.name
				keyButtons[setting] = made
				made.button.Activated:Connect(function()
					if capturing == setting then
						stopCapture()
					else
						startCapture(setting)
					end
				end)
				paintKey(setting)
			end
		end
	end
	updateKeyRows()
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput" :: any):Connect(updateKeyRows)
	end)
end

local function buildRows(list: Instance)
	-- Le pack donne une zone de defilement de 5.5 ecrans pour 2 lignes : on la cale sur le contenu
	if list:IsA("ScrollingFrame") then
		-- Hauteur calee a la main sur le contenu de la liste : AutomaticCanvasSize se trompe avec
		-- les lignes du pack (hauteur fixee par un UIAspectRatioConstraint) et coupait les 2
		-- dernieres lignes des que la liste depasse la fenetre (vu le 2026-11-27 avec les touches).
		list.AutomaticCanvasSize = Enum.AutomaticSize.None
		-- Lignes du pack collees entre elles et a l'en-tete : un vrai espace partout
		PackStyle.spaceList(list, 0.045)
		local layout = list:FindFirstChildOfClass("UIListLayout")
		local padding = list:FindFirstChildOfClass("UIPadding")
		local function fitCanvas()
			local height = if layout then layout.AbsoluteContentSize.Y else 0
			if padding then
				height += padding.PaddingTop.Offset + padding.PaddingBottom.Offset
			end
			list.CanvasSize = UDim2.fromOffset(0, math.ceil(height))
		end
		if layout then
			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitCanvas)
		end
		if padding then
			padding.Changed:Connect(fitCanvas)
		end
		fitCanvas()
	end
	local template = list:FindFirstChild("Effects")
	if template and list:FindFirstChild("LowQuality") == nil then
		local copy = template:Clone()
		copy.Name = "LowQuality"
		if copy:IsA("GuiObject") and template:IsA("GuiObject") then
			copy.LayoutOrder = template.LayoutOrder + 1
		end
		copy.Parent = list
	end
	-- Lignes des touches (PC) : copiees ici, avant que la ligne Effects recoive son curseur
	if template then
		buildKeyRows(list, template)
	end
	for index, info in ROWS do
		local row = list:FindFirstChild(info.row)
		if row == nil then
			continue
		end
		if row:IsA("GuiObject") then
			row.LayoutOrder = index -- Music, Sounds, Low Quality dans cet ordre
		end
		setText(row, "SettingName", info.title)
		setText(row, "Description", info.description)
		-- Bouton "ToggleButtonON" ou "ToggleButtonOFF" selon la ligne du pack : le premier bouton
		local toggleFrame = row:FindFirstChild("Toggle", true)
		local packButton = toggleFrame and toggleFrame:FindFirstChildWhichIsA("GuiButton", true)
		if isVolume(info.key) then
			-- Volume : le bouton du pack est cache, un curseur prend sa place
			if packButton and toggleFrame and toggleFrame:IsA("Frame") and toggleFrame:FindFirstChild("VolumeSlider") == nil then
				packButton.Visible = false
				buildSlider(info.key, toggleFrame, list)
			end
			continue
		end
		if packButton and packButton:FindFirstChild("Switch") == nil then
			packButton.Name = "ToggleButton"
			-- Le bouton du pack (relief a ombre, autre contour) est cache : on met dedans le bouton
			-- commun PackStyle, qui recoit les clics.
			for _, child in packButton:GetChildren() do
				if child:IsA("GuiObject") then
					child.Visible = false
				end
			end
			local button = PackStyle.button(packButton, "Switch", PackStyle.GREEN, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 1))
			local label = PackStyle.label(button, "ON", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 40)
			toggles[info.key] = {
				button = button,
				label = label,
				gradient = button:FindFirstChildOfClass("UIGradient"),
				stroke = button:FindFirstChildOfClass("UIStroke"),
			}
			button.Activated:Connect(function()
				onToggle(info.key)
			end)
		end
	end
end

function SettingsController:Start()
	if started then
		return
	end
	started = true
	for key in GameConfig.DefaultSettings do
		player:GetAttributeChangedSignal("Setting" .. key):Connect(function()
			apply(key)
		end)
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local shopGui = playerGui:WaitForChild("ShopGUI", 30)
	local frames = shopGui and shopGui:WaitForChild("MenuFrames", 10)
	local menu = frames and frames:WaitForChild("Settings", 10)
	local list = menu and menu:FindFirstChild("ScrollingFrame", true)
	if menu and menu:IsA("GuiObject") then
		menu:GetPropertyChangedSignal("Visible"):Connect(function()
			if not menu.Visible then
				stopCapture() -- menu ferme : la prochaine touche ne doit rien changer
			end
		end)
	end
	if list then
		buildRows(list)
	else
		warn("[SettingsController] Menu Settings introuvable : interrupteurs non branches.")
	end
	for key in GameConfig.DefaultSettings do
		apply(key)
	end

	task.spawn(function()
		setEvent = Remotes.WaitClientEvent("SetSetting")
	end)
end

return SettingsController
