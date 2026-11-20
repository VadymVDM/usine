--!strict
-- Menu Settings (menu "Settings" du pack, ouvert par l'engrenage en haut) : 3 interrupteurs
--   Music       : musique de fond (MusicController) ;
--   Sounds      : sons du jeu et de l'interface (SoundFx / MenuController lisent SettingEffects) ;
--   Low Quality : sans ombres, effets d'eclairage, particules ni decor lointain (telephones lents).
-- Le clic change l'interrupteur tout de suite et envoie SetSetting au serveur (SettingsService),
-- qui sauvegarde et pose les attributs joueur "Setting<Cle>". On applique toujours ces attributs.
-- Doc : docs/systems/interface.md (Settings)

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local SettingsController = {}

-- Interrupteurs = boutons communs de l'interface (vert ON / rouge OFF, comme YES / NO).
type Toggle = { button: TextButton, label: TextLabel, gradient: UIGradient?, stroke: UIStroke? }
-- Lignes du menu : cle du reglage -> nom de la ligne dans le pack, textes affiches (anglais)
local ROWS = {
	{ key = "Music", row = "Music", title = "Music", description = "Background music" },
	{ key = "Effects", row = "Effects", title = "Sounds", description = "Game and button sounds" },
	{ key = "LowQuality", row = "LowQuality", title = "Low Quality", description = "No shadows, faster game" },
}

local player = Players.LocalPlayer
local started = false
local setEvent: RemoteEvent? = nil
local toggles: { [string]: Toggle } = {}
local lowQualityOn = false

-- Valeur actuelle d'un reglage (attribut du serveur, sinon valeur par defaut).
local function getSetting(key: string): boolean
	local value = player:GetAttribute("Setting" .. key)
	if type(value) == "boolean" then
		return value
	end
	return GameConfig.DefaultSettings[key] == true
end

---------------------------------------------------------------------------------------------
-- Low Quality : ombres, effets d'eclairage, particules, decor lointain

local savedLighting: { [Instance]: { [string]: any } } = {}
local emitterWanted: { [Instance]: boolean } = {} -- valeur voulue par le serveur pendant le mode
local emitterConnections: { [Instance]: RBXScriptConnection } = {}
local addedConnection: RBXScriptConnection? = nil
local hiddenDecor: Instance? = nil
local decorParent: Instance? = nil

local function isEmitter(item: Instance): boolean
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
		-- Decor de la carte (forets, collines) : cache localement
		local map = workspace:FindFirstChild("Map")
		local decor = map and map:FindFirstChild("Decor")
		if decor then
			hiddenDecor = decor
			decorParent = map
			decor.Parent = nil
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

local function apply(key: string)
	local on = getSetting(key)
	if key == "Music" then
		local music = getMusic()
		if music and music.SetEnabled then
			music.SetEnabled(on)
		end
	elseif key == "LowQuality" then
		applyLowQuality(on)
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

local function buildRows(list: Instance)
	-- Le pack donne une zone de defilement de 5.5 ecrans pour 2 lignes : on la cale sur le contenu
	if list:IsA("ScrollingFrame") then
		list.CanvasSize = UDim2.new()
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		-- Lignes du pack collees entre elles et a l'en-tete : un vrai espace partout
		PackStyle.spaceList(list, 0.045)
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
