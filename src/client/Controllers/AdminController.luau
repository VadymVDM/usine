--!strict
-- Panneau admin (tests) : un bouton "Admin" a droite de l'ecran ouvre un panneau "vite fait" :
-- en haut la cible (soi ou un autre joueur du serveur, fleches < >) et un champ "Value" (nombre
-- utilise par les boutons marques N), puis des rubriques de boutons (argent, fruits, ameliorations,
-- etages, rebirth, passes, Index, joueur). Les boutons dangereux demandent un 2e clic.
-- Visible seulement si le serveur a pose l'attribut joueur "IsAdmin" ; le serveur reverifie chaque
-- action (AdminService) et repond par une notification.
-- Doc : docs/systems/admin.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local CONFIRM_SECONDS = 3 -- temps pour cliquer une 2e fois sur un bouton dangereux
local REFRESH_SECONDS = 0.5 -- mise a jour des boutons ON / OFF quand le panneau est ouvert

local BG = Color3.fromRGB(30, 22, 40)
local TEXT = Color3.new(1, 1, 1)
local COLORS = {
	money = Color3.fromRGB(40, 170, 40),
	fruit = Color3.fromRGB(230, 120, 0),
	upgrade = Color3.fromRGB(0, 130, 220),
	floor = Color3.fromRGB(130, 40, 220),
	rebirth = Color3.fromRGB(220, 30, 140),
	pass = Color3.fromRGB(0, 160, 140),
	player = Color3.fromRGB(90, 90, 110),
	danger = Color3.fromRGB(210, 30, 30),
}

-- Un bouton : action envoyee au serveur. `useValue` = envoie le champ Value, `value` = valeur fixe.
-- `confirm` = 2e clic obligatoire. `attribute` = bouton ON / OFF qui lit cet attribut de la cible.
type ButtonDef = {
	text: string,
	action: string,
	useValue: boolean?,
	value: number?,
	confirm: boolean?,
	attribute: string?,
}
type Section = { title: string, color: Color3, buttons: { ButtonDef } }

-- Ordre des passes = PASS_ATTRIBUTES d'AdminService (valeur envoyee avec "TogglePass")
local SECTIONS: { Section } = {
	{
		title = "Money",
		color = COLORS.money,
		buttons = {
			{ text = "+$1K", action = "Money1K" },
			{ text = "+$1M", action = "Money1M" },
			{ text = "+$1B", action = "Money1B" },
			{ text = "+$N", action = "MoneyN", useValue = true },
			{ text = "Max Money", action = "MaxMoney" },
			{ text = "Money = 0", action = "ZeroMoney", confirm = true },
		},
	},
	{
		title = "Spawn (current floor)",
		color = COLORS.fruit,
		buttons = {
			{ text = "Drop 10 Fruits", action = "Drop10" },
			{ text = "Drop N Fruits", action = "DropN", useValue = true },
			{ text = "Fill Bins (20)", action = "FillBins" },
			{ text = "N Juices", action = "Juices", useValue = true },
			{ text = "Cash Pile +N", action = "PileCash", useValue = true },
			{ text = "Collect Pile", action = "CollectPile" },
			{ text = "Lucky Cash", action = "LuckyCash" },
		},
	},
	{
		title = "Upgrades",
		color = COLORS.upgrade,
		buttons = {
			{ text = "Max Floor Upg.", action = "MaxFloorUp" },
			{ text = "Reset Floor Upg.", action = "ResetFloorUp", confirm = true },
			{ text = "Max Player Upg.", action = "MaxPlayerUp" },
			{ text = "Reset Player Upg.", action = "ResetPlayerUp", confirm = true },
			{ text = "Max Elevator", action = "MaxTower" },
		},
	},
	{
		title = "Floors",
		color = COLORS.floor,
		buttons = {
			{ text = "+1 Floor", action = "AddFloor" },
			{ text = "-1 Floor", action = "RemoveFloor", confirm = true },
			{ text = "10 Floors", action = "AllFloors" },
			{ text = "1 Floor", action = "ResetFloors", confirm = true },
			{ text = "Set N Floors", action = "SetFloorsN", useValue = true, confirm = true },
			{ text = "Go To Floor N", action = "GoToFloorN", useValue = true },
		},
	},
	{
		title = "Rebirth",
		color = COLORS.rebirth,
		buttons = {
			{ text = "+1 Rebirth", action = "Rebirth", confirm = true },
			{ text = "Rebirth Keep $", action = "RebirthKeep", confirm = true },
			{ text = "Set N Rebirths", action = "SetRebirthsN", useValue = true },
		},
	},
	{
		title = "Passes (free toggle)",
		color = COLORS.pass,
		buttons = {
			{ text = "Instant Sell", action = "TogglePass", value = 1, attribute = "InstantSell" },
			{ text = "Waiter x10", action = "TogglePass", value = 2, attribute = "SpeedBoost" },
			{ text = "Billboard", action = "TogglePass", value = 3, attribute = "Billboard" },
			{ text = "Thief", action = "TogglePass", value = 4, attribute = "Thief" },
			{ text = "Rebirth Master", action = "ToggleMaster", attribute = "RebirthMaster" },
			{ text = "Auto Collect", action = "TogglePass", value = 5, attribute = "AutoCollect" },
		},
	},
	{
		title = "Index",
		color = COLORS.upgrade,
		buttons = {
			{ text = "Discover All", action = "DiscoverAll" },
			{ text = "Reset Index", action = "ResetIndex", confirm = true },
		},
	},
	{
		title = "Player",
		color = COLORS.player,
		buttons = {
			{ text = "TP To Target", action = "TpTo" },
			{ text = "Bring Target", action = "Bring" },
			{ text = "Respawn", action = "Respawn" },
			{ text = "RESET ALL (kick)", action = "ResetAll", confirm = true },
		},
	},
}

local AdminController = {}

local built = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function textOf(parent: Instance, text: string, maxSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = PackStyle.FONT
	label.Text = text
	label.TextColor3 = TEXT
	label.TextScaled = true
	label.ZIndex = 3
	PackStyle.stroke(label, 1.5, PackStyle.TEXT_STROKE)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	label.Parent = parent
	return label
end

local function flatButton(parent: Instance, text: string, color: Color3): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Text = ""
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.ZIndex = 2
	corner(button, 6)
	PackStyle.stroke(button, 2, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local label = textOf(button, text, 18)
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.04, 0.1)
	button.Parent = parent
	return button, label
end

local function build()
	if built then
		return
	end
	built = true
	local remote = Remotes.WaitClientEvent("AdminAction")
	if remote == nil then
		return
	end
	local event = remote :: RemoteEvent
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Bouton d'ouverture, colle au bord droit, sous le milieu de l'ecran
	local toggle = PackStyle.button(gui, "AdminToggle", PackStyle.PURPLE, UDim2.new(1, -50, 0.66, 0), UDim2.fromOffset(84, 34))
	PackStyle.label(toggle, "Admin", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.9, 0.76), 22).ZIndex = toggle.ZIndex + 2

	-- Panneau : a droite, centre en hauteur, taille limitee (lisible sur telephone comme sur PC)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -100, 0.5, 0)
	panel.Size = UDim2.fromScale(0.5, 0.85)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	corner(panel, 10)
	PackStyle.stroke(panel, 3, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(460, 620)
	sizeLimit.MinSize = Vector2.new(260, 240)
	sizeLimit.Parent = panel
	panel.Parent = gui

	-- Titre + fermer
	local title = textOf(panel, "Admin Panel", 26)
	title.Size = UDim2.new(1, -60, 0, 30)
	title.Position = UDim2.fromOffset(10, 6)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local close = flatButton(panel, "X", COLORS.danger)
	close.Size = UDim2.fromOffset(34, 30)
	close.Position = UDim2.new(1, -42, 0, 6)

	-- Cible : < Nom >
	local targetRow = Instance.new("Frame")
	targetRow.BackgroundTransparency = 1
	targetRow.Size = UDim2.new(1, -16, 0, 32)
	targetRow.Position = UDim2.fromOffset(8, 42)
	targetRow.Parent = panel
	local prev = flatButton(targetRow, "<", COLORS.player)
	prev.Size = UDim2.new(0, 36, 1, 0)
	local nextButton = flatButton(targetRow, ">", COLORS.player)
	nextButton.Size = UDim2.new(0, 36, 1, 0)
	nextButton.Position = UDim2.new(1, -36, 0, 0)
	local targetBox = Instance.new("Frame")
	targetBox.BackgroundColor3 = Color3.fromRGB(55, 45, 70)
	targetBox.Size = UDim2.new(1, -84, 1, 0)
	targetBox.Position = UDim2.fromOffset(42, 0)
	corner(targetBox, 6)
	targetBox.Parent = targetRow
	local targetLabel = textOf(targetBox, "", 20)
	targetLabel.AutoLocalize = false -- nom de joueur

	-- Valeur N
	local valueRow = Instance.new("Frame")
	valueRow.BackgroundTransparency = 1
	valueRow.Size = UDim2.new(1, -16, 0, 32)
	valueRow.Position = UDim2.fromOffset(8, 80)
	valueRow.Parent = panel
	local valueTitle = textOf(valueRow, "Value N:", 20)
	valueTitle.Size = UDim2.new(0, 90, 1, 0)
	valueTitle.TextXAlignment = Enum.TextXAlignment.Left
	local valueBox = Instance.new("TextBox")
	valueBox.Size = UDim2.new(1, -96, 1, 0)
	valueBox.Position = UDim2.fromOffset(96, 0)
	valueBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	valueBox.TextColor3 = Color3.fromRGB(20, 20, 20)
	valueBox.FontFace = PackStyle.FONT
	valueBox.TextSize = 20
	valueBox.Text = "10"
	valueBox.PlaceholderText = "number (1000, 1e6...)"
	valueBox.ClearTextOnFocus = false
	valueBox.AutoLocalize = false
	corner(valueBox, 6)
	valueBox.Parent = valueRow

	-- Rubriques dans une liste qui defile
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(8, 120)
	scroll.Size = UDim2.new(1, -16, 1, -128)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = scroll

	-- Cible choisie (UserId ; nil = soi-meme)
	local targets: { Player } = {}
	local targetIndex = 1
	local function currentTarget(): Player
		local target = targets[targetIndex]
		return if target and target.Parent == Players then target else player
	end
	local function refreshTargets()
		local keep = currentTarget()
		targets = Players:GetPlayers()
		table.sort(targets, function(a, b)
			if a == player or b == player then
				return a == player
			end
			return a.Name < b.Name
		end)
		targetIndex = table.find(targets, keep) or 1
		local target = currentTarget()
		targetLabel.Text = if target == player then `{target.Name} (you)` else target.Name
	end
	local function step(delta: number)
		refreshTargets()
		targetIndex = (targetIndex - 1 + delta) % math.max(#targets, 1) + 1
		refreshTargets()
	end
	prev.Activated:Connect(function()
		step(-1)
	end)
	nextButton.Activated:Connect(function()
		step(1)
	end)
	Players.PlayerAdded:Connect(refreshTargets)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshTargets)
	end)
	refreshTargets()

	local function readValue(): number?
		local n = tonumber((string.gsub(valueBox.Text, "[%s,_]", "")))
		if n == nil or n ~= n or math.abs(n) == math.huge then
			return nil
		end
		return n
	end

	-- Boutons ON / OFF : texte mis a jour depuis les attributs de la cible
	local toggles: { { label: TextLabel, def: ButtonDef } } = {}
	local function refreshToggles()
		local target = currentTarget()
		for _, item in toggles do
			local on = target:GetAttribute(item.def.attribute :: string) == true
			item.label.Text = `{item.def.text}: {if on then "ON" else "OFF"}`
		end
	end

	local function send(def: ButtonDef)
		local target = currentTarget()
		local value: number? = def.value
		if def.useValue then
			value = readValue()
			if value == nil then
				valueBox.Text = ""
				valueBox.PlaceholderText = "Type a number first!"
				return
			end
		end
		event:FireServer(def.action, if target == player then nil else target.UserId, value)
		task.delay(0.4, refreshToggles)
	end

	for order, section in SECTIONS do
		local header = textOf(scroll, section.title, 20)
		header.LayoutOrder = order * 2 - 1
		header.Size = UDim2.new(1, 0, 0, 24)
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = section.color:Lerp(TEXT, 0.45)

		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.LayoutOrder = order * 2
		grid.Size = UDim2.fromScale(1, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Parent = scroll
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(1 / 3, -6, 0, 38)
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid

		for index, def in section.buttons do
			local button, label = flatButton(grid, def.text, if def.confirm then COLORS.danger else section.color)
			button.LayoutOrder = index
			if def.attribute then
				table.insert(toggles, { label = label, def = def })
			end
			-- 2e clic pour confirmer (boutons dangereux)
			local armed = 0
			button.Activated:Connect(function()
				if not def.confirm then
					send(def)
					return
				end
				if armed > 0 then
					armed = 0
					label.Text = def.text
					send(def)
					return
				end
				armed += 1
				local token = armed
				label.Text = "Sure? Click again"
				task.delay(CONFIRM_SECONDS, function()
					if armed == token then
						armed = 0
						label.Text = def.text
					end
				end)
			end)
		end
	end

	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			refreshTargets()
			refreshToggles()
		end
	end
	toggle.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	prev.Activated:Connect(refreshToggles)
	nextButton.Activated:Connect(refreshToggles)
	task.spawn(function()
		while true do -- le panneau vit toute la partie (ResetOnSpawn = false)
			if panel.Visible then
				refreshToggles()
			end
			task.wait(REFRESH_SECONDS)
		end
	end)

	-- Cache pendant le prechargement, comme le HUD (docs/systems/chargement.md)
	gui.Enabled = player:GetAttribute("LoadingDone") == true
	if not gui.Enabled then
		local loaded: RBXScriptConnection
		loaded = player:GetAttributeChangedSignal("LoadingDone"):Connect(function()
			if player:GetAttribute("LoadingDone") == true then
				loaded:Disconnect()
				gui.Enabled = true
			end
		end)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

function AdminController:Init() end

function AdminController:Start()
	local player = Players.LocalPlayer
	if player:GetAttribute("IsAdmin") == true then
		build()
		return
	end
	local connection: RBXScriptConnection
	connection = player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
		if player:GetAttribute("IsAdmin") == true then
			connection:Disconnect()
			build()
		end
	end)
end

return AdminController
