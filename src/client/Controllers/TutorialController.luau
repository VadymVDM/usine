--!strict
-- Tutoriel etape par etape (profil neuf, 2026-11-22, demande : "d'abord tu plantes, apres tu prends
-- les fruits, ensuite tu construis l'etagere et tu mets...").
-- Ne decide rien : lit l'etat publie par le serveur et montre UNE chose a faire a la fois :
--   * ligne de chevrons lumineux du joueur a la cible (Beam), fleche 3D qui rebondit au-dessus ;
--   * objectif court en haut de l'ecran (Config/Tutorial.Steps, anglais).
-- Etapes sauvegardees (attribut joueur TutorialStep, TutorialService ; Config/Tutorial.Phases) :
--   Factory : Plant the tree -> Pick up the fruits -> Build the shelf -> Drop the fruits -> Build the
--     blender -> Blend the fruits (E) -> Take the juices -> Open the shop -> Sell -> Collect your cash ;
--   Picker (Fruit Picker, apres avoir gagne son prix) ; OpenIndex / ClaimIndex (fleche a l'ecran sur le
--   bouton Index puis sur un CLAIM) ; Loop (un tour complet jusqu'a l'argent) ; Upgrade (bouton
--   UPGRADE puis la vitesse, gratuite une fois : serveur) ; Free (15 s sans guidage) ; Operator du
--   mixeur quand il peut le payer ; Suggest (une amelioration de panneau au hasard chaque minute).
-- Une etape finie : remote TutorialProgress (etape + 1). Rien pour les profils existants (Done).
-- Etage 2 possede : plus de tutoriel (le serveur met Done), sauf UN conseil 1 min plus tard, quand il a
-- le prix : ameliorer l'ascenseur (panneau Elevator de la terrasse), jusqu'au premier achat.
-- Attend la fin de la cinematique (attribut local IntroPlaying, IntroController). Pas de Neon.
-- Doc : docs/systems/tutoriel.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Setup = require(Config:WaitForChild("Setup"))
local Tutorial = require(Config:WaitForChild("Tutorial"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Floors = require(Config:WaitForChild("Floors"))
local Icons = require(Config:WaitForChild("Icons")) :: { [string]: string }
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local MachineModels = require(Shared:WaitForChild("Util"):WaitForChild("MachineModels"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local TutorialController = {}

local player = Players.LocalPlayer
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)
local ARROW_COLOR = Color3.fromRGB(255, 214, 40)

local started = false

-- Cible actuelle : une piece du monde (pad, fruit, tuile : ligne + fleche 3D) ou un bouton de
-- l'interface (fleche a l'ecran), et le texte en haut de l'ecran
-- ring = anneau au sol sous la cible (pads seulement)
type Target = { part: BasePart?, gui: GuiObject?, arrowHeight: number, text: string, sub: string?, ring: boolean? }

---------------------------------------------------------------------------------------------
-- Lecture de l'etat

local function findPath(root: Instance, path: string): Instance?
	local current: Instance? = root
	for name in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function myFirstFloor(): Model?
	local base = FloorWatch.MyBase()
	if base == nil then
		return nil
	end
	for _, floor in FloorWatch.FloorsOf(base) do
		if FloorWatch.IndexOf(floor) == 1 then
			return floor
		end
	end
	return nil
end

-- Zone d'un pad (PadZone) s'il est visible (les pads caches ont PadTop.Transparency = 1)
local function visiblePad(pad: Instance?): BasePart?
	if pad == nil then
		return nil
	end
	local zone = pad:FindFirstChild("PadZone", true)
	local top = pad:FindFirstChild("PadTop", true)
	if zone and zone:IsA("BasePart") and top and top:IsA("BasePart") and top.Transparency < 1 then
		return zone
	end
	return nil
end

local function freePad(floor: Model, step: number): BasePart?
	local def = Setup.Steps[step]
	if def and def.spot then
		-- Etape sans pad (Plant tree) : la piece de la touche E, quand le serveur l'a activee
		local spot: Instance? = floor
		for name in string.gmatch(def.spot, "[^%.]+") do
			spot = spot and spot:FindFirstChild(name)
		end
		local prompt = spot and spot:FindFirstChild("SetupPrompt")
		if spot and spot:IsA("BasePart") and prompt and prompt:GetAttribute("Active") == true then
			return spot
		end
		return nil
	end
	local folder = floor:FindFirstChild("Setup")
	return visiblePad(def and folder and folder:FindFirstChild(def.id))
end

local function nearestFruit(floor: Model, from: Vector3): BasePart?
	local dynamic = floor:FindFirstChild("Dynamic")
	local folder = dynamic and dynamic:FindFirstChild("GroundFruits")
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, item in (if folder then folder:GetChildren() else {}) do
		local part: BasePart? = nil
		if item:IsA("BasePart") then
			part = item
		elseif item:IsA("Model") then
			part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
		end
		if part then
			local distance = (part.Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

local function fruitsCarried(): number
	local text = player:GetAttribute("InvFruits")
	if type(text) ~= "string" or text == "" then
		return 0
	end
	-- Format "Apple=15;Strawberry=4" (nombre par fruit, ProductionService)
	local count = 0
	if type(text) == "string" then
		for entry in string.gmatch(text, "[^;]+") do
			local amount = tonumber(string.match(entry, "=(%d+)$"))
			count += amount or 1
		end
	end
	return count
end

local function numberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function money(): number
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	return if cash and cash:IsA("NumberValue") or (cash and cash:IsA("IntValue")) then (cash :: any).Value else 0
end

---------------------------------------------------------------------------------------------
-- Visuels : fleche, ligne (icone double fleche repetee, sans fond), objectif

local function decor(p: BasePart, color: Color3)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
end

-- Fleche 3D en croix qui pointe vers le bas : deux fleches plates croisees a 90 deg (lisible de
-- tous les cotes quand elle tourne), pointe triangulaire (2 WedgeParts par fleche), tige carree.
-- Contour sombre (Highlight) visible a travers les murs. Pointe en y = -0.5 (pivot en 0).
local function buildArrow(): Model
	local model = Instance.new("Model")
	model.Name = "TutorialArrow"
	local s = Tutorial.ArrowSize
	local headW, headH, thick = 3 * s, 1.9 * s, 0.9 * s
	local tip = -0.5
	local headY = tip + headH / 2
	local shaftH = 2.2 * s
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	decor(shaft, ARROW_COLOR)
	shaft.Size = Vector3.new(1.1 * s, shaftH, 1.1 * s)
	shaft.CFrame = CFrame.new(0, tip + headH + shaftH / 2 - 0.05, 0)
	shaft.Parent = model
	for _, turn in { 0, math.pi / 2 } do
		local base = CFrame.Angles(0, turn, 0)
		-- Coin retourne (haut plein, pointe en bas au bord +Z local) : deux moities en miroir
		local halves = {
			CFrame.new(0, headY, -headW / 4) * CFrame.Angles(0, 0, math.pi),
			CFrame.new(0, headY, headW / 4) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.pi),
		}
		for i, cf in halves do
			local wedge = Instance.new("WedgePart")
			wedge.Name = `Head{turn == 0 and "A" or "B"}{i}`
			decor(wedge, ARROW_COLOR)
			wedge.Size = Vector3.new(thick, headH, headW / 2)
			wedge.CFrame = base * cf
			wedge.Parent = model
		end
	end
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = TEXT_STROKE
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Adornee = model
	outline.Parent = model
	model.WorldPivot = CFrame.identity
	return model
end

-- Anneau au sol sous un pad vise : disque jaune qui grandit et s'efface en boucle
local function buildRing(): Part
	local ring = Instance.new("Part")
	ring.Name = "TutorialRing"
	ring.Shape = Enum.PartType.Cylinder
	decor(ring, ARROW_COLOR)
	ring.Size = Vector3.new(0.1, 4, 4)
	return ring
end

-- Attachment0 = la cible (le chevron de la texture pointe vers Attachment0 : l'axe vertical de
-- l'image suit la longueur du Beam, verifie en playtest le 2026-11-22), Attachment1 = le joueur.
local function buildGuide(): ({ Beam }, Attachment, Attachment)
	local from = Instance.new("Attachment")
	from.Name = "TutorialFrom"
	local to = Instance.new("Attachment")
	to.Name = "TutorialTo"
	local beam = Instance.new("Beam")
	beam.Name = "TutorialLine"
	beam.Texture = Tutorial.GuideTexture
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = Tutorial.GuideTextureLength
	beam.TextureSpeed = -Tutorial.GuideSpeed -- defile du joueur vers la cible
	beam.Width0 = Tutorial.GuideWidth
	beam.Width1 = Tutorial.GuideWidth
	beam.FaceCamera = true
	beam.LightEmission = Tutorial.GuideLightEmission
	beam.LightInfluence = 0
	beam.Brightness = 1
	beam.Segments = 1
	beam.Color = ColorSequence.new(Tutorial.GuideColor)
	beam.Transparency = NumberSequence.new(0) -- opaque partout (demande : "retire la transparence")
	beam.Attachment0 = to
	beam.Attachment1 = from
	-- Le mode Low Quality (SettingsController) eteint les Beams : celui-ci guide le joueur, il reste
	beam:SetAttribute("KeepInLowQuality", true)
	return { beam }, from, to
end

local function buildBanner(): (ScreenGui, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100 -- au-dessus des menus (l'objectif reste lisible menu ouvert)
	-- Tout en haut, a la hauteur de la barre "< Floors >" (FloorSelectorGui, cachee avec un seul
	-- etage, donc pendant le tutoriel) : demande du 2026-11-22 "met le plus haut"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local label = Instance.new("TextLabel")
	label.Name = "Objective"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, Tutorial.BannerTop)
	label.Size = UDim2.fromOffset(380, 46)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = TEXT_STROKE
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = gui
	-- Petite ligne sous l'objectif : le but de l'etape quand le geste a faire est autre chose
	-- (ex. "Fruit Picker: $20 / $25" pendant qu'on fait des jus)
	local sub = Instance.new("TextLabel")
	sub.Name = "Goal"
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0, Tutorial.BannerTop + 48)
	sub.Size = UDim2.fromOffset(320, 28)
	sub.BackgroundTransparency = 1
	sub.FontFace = FONT
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 225, 70)
	sub.Text = ""
	sub.Visible = false
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 2.5
	subStroke.Color = TEXT_STROKE
	subStroke.Parent = sub
	sub.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, label
end

-- Fleche a l'ecran (boutons du HUD et des menus) : Icons.FloorArrow tournee vers le bas, posee
-- dans le ScreenGui du bouton vise (memes coordonnees), qui rebondit au-dessus du bouton.
local function buildPointer(): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "TutorialPointer"
	image.BackgroundTransparency = 1
	image.Image = Icons.FloorArrow
	image.Rotation = 90
	image.AnchorPoint = Vector2.new(0.5, 1)
	image.Size = UDim2.fromOffset(Tutorial.PointerSize, Tutorial.PointerSize)
	image.ZIndex = 1000
	return image
end

local function isShown(gui: GuiObject): boolean
	local current: Instance? = gui
	while current and not current:IsA("ScreenGui") do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current ~= nil and (current :: ScreenGui).Enabled
end

---------------------------------------------------------------------------------------------

function TutorialController.Init() end

function TutorialController.Start()
	if started then
		return
	end
	started = true
	local arrow = buildArrow()
	local ring = buildRing()
	local beams, from, to = buildGuide()
	to.Parent = workspace.Terrain
	local _, label = buildBanner()
	local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
	local goal = (label.Parent :: Instance):FindFirstChild("Goal") :: TextLabel

	local pointer = buildPointer()
	local droppedOnce = false -- des fruits ont ete poses sur l'etagere
	local soldSeen = false -- des jus ont ete poses sur le comptoir (depuis le dernier argent encaisse)
	local lastCarried = 0
	-- Fruits en route vers le bol (tapis) : dernier depot et dernier fruit envoye (attribut Pulse du
	-- mixeur 1). Sans ca, "Pick up the fruits" s'affichait ~1 s entre le depot et l'arrivee au bol.
	local lastDropAt = -math.huge
	local lastPulse: any = nil
	local lastPulseAt = -math.huge
	local lastMoney = money()
	local target: Target? = nil
	local clock = 0
	-- Etape (sauvegardee par le serveur) et ce qui a ete vu pendant l'etape en cours
	local phaseStep = -1
	local phaseStartedAt = 0
	local sentStep = -1
	local claimSeen = false
	local noClaimSince: number? = nil
	local speedLevelAtStart = 0
	local suggestion: { id: string, startLevel: number, untilAt: number }? = nil
	local nextSuggestAt = 0
	local tileCache: { [string]: BasePart } = {}
	local tileCacheAt = -math.huge

	-- Feedback "IndexClaim" : une recompense de l'Index vient d'etre prise
	task.spawn(function()
		local feedback = Remotes.WaitClientEvent("Feedback")
		if feedback then
			feedback.OnClientEvent:Connect(function(kind: any)
				if kind == "IndexClaim" then
					claimSeen = true
				end
			end)
		end
	end)

	-- Pulsation du bouton vise. Son UIScale sert deja au survol / appui (UI/ButtonFx) et au rebond
	-- de l'Index (DiscoveryController) : on multiplie par-dessus leur valeur, sans la remplacer.
	-- Si personne n'a ecrit depuis notre derniere ecriture, la valeur "a eux" = ecrite / facteur ;
	-- sinon c'est la valeur qu'ils viennent de mettre. Attribut PulseFactor sur l'UIScale : ils le
	-- retirent quand ils lisent leur taille de repos.
	local pulse: { gui: GuiObject?, scale: UIScale?, written: number, factor: number } =
		{ gui = nil, scale = nil, written = 1, factor = 1 }
	local function ownValue(scale: UIScale): number
		return if math.abs(scale.Scale - pulse.written) < 1e-4 then pulse.written / pulse.factor else scale.Scale
	end
	local function stopPulse()
		local scale = pulse.scale
		if scale and scale.Parent then
			scale.Scale = ownValue(scale)
			scale:SetAttribute("PulseFactor", nil)
		end
		pulse.gui, pulse.scale, pulse.written, pulse.factor = nil, nil, 1, 1
	end
	local function stepPulse(gui: GuiObject)
		if pulse.gui ~= gui then
			stopPulse()
			-- Objet qui change de taille : comme ButtonFx (attribut FxTarget = enfant a agrandir)
			local fxTarget: GuiObject = gui
			local childName = gui:GetAttribute("FxTarget")
			local child = if type(childName) == "string" then gui:FindFirstChild(childName) else nil
			if child and child:IsA("GuiObject") then
				fxTarget = child
			end
			local scale = fxTarget:FindFirstChildOfClass("UIScale")
			if scale == nil then
				local created = Instance.new("UIScale")
				created.Name = "UIScale" -- nom que ButtonFx sait reprendre
				created.Parent = fxTarget
				scale = created
			end
			pulse.gui, pulse.scale = gui, scale
			pulse.written, pulse.factor = (scale :: UIScale).Scale, 1
		end
		local scale = pulse.scale :: UIScale
		local own = ownValue(scale)
		local factor = 1 + Tutorial.ButtonPulse * (0.5 - 0.5 * math.cos(clock * Tutorial.ButtonPulseSpeed * 2 * math.pi))
		pulse.factor = factor
		pulse.written = own * factor
		scale.Scale = pulse.written
		scale:SetAttribute("PulseFactor", factor)
	end

	local function show(newTarget: Target?)
		target = newTarget
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local part = newTarget and newTarget.part
		if part and root and root:IsA("BasePart") then
			if arrow.Parent ~= workspace then
				arrow.Parent = workspace
			end
			if from.Parent ~= root then
				from.Parent = root
				from.Position = Vector3.new(0, Tutorial.GuideStartHeight, 0)
			end
			for _, beam in beams do
				beam.Parent = root
			end
		else
			arrow.Parent = nil
			ring.Parent = nil
			for _, beam in beams do
				beam.Parent = nil
			end
			from.Parent = nil
		end
		local gui = newTarget and newTarget.gui
		local holder = gui and gui:FindFirstAncestorOfClass("ScreenGui")
		if pulse.gui ~= gui then
			stopPulse()
		end
		if gui and holder then
			if pointer.Parent ~= holder then
				pointer.Parent = holder
			end
		else
			pointer.Parent = nil
		end
		if newTarget then
			if label.Text ~= newTarget.text then
				label.Text = newTarget.text
				scale.Scale = 0.6
				TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
			label.Visible = newTarget.text ~= ""
			goal.Text = newTarget.sub or ""
			goal.Visible = newTarget.sub ~= nil
		else
			label.Visible = false
			goal.Visible = false
		end
	end

	-- Etape faite : on demande l'etape suivante au serveur (une seule fois)
	local function advance(step: number)
		if sentStep >= step + 1 then
			return
		end
		sentStep = step + 1
		local remote = Remotes.WaitClientEvent("TutorialProgress")
		if remote then
			remote:FireServer(step + 1)
		end
	end

	local function hud(): ScreenGui?
		local found = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HUD")
		return if found and found:IsA("ScreenGui") then found else nil
	end
	local function activeMenu(): string
		local h = hud()
		local value = h and h:GetAttribute("ActiveMenu")
		return if type(value) == "string" then value else ""
	end
	local function hudButton(name: string): GuiObject?
		local h = hud()
		local found = h and h:FindFirstChild(name, true)
		return if found and found:IsA("GuiObject") and isShown(found) then found else nil
	end
	-- Bouton X (Header.ExitButton) du menu ouvert : les boutons du HUD sont caches menu ouvert
	local function closeButton(menuName: string): GuiObject?
		local shop = player.PlayerGui:FindFirstChild("ShopGUI")
		local frames = shop and shop:FindFirstChild("MenuFrames")
		local menu = frames and frames:FindFirstChild(menuName)
		local button = menu and menu:FindFirstChild("ExitButton", true)
		return if button and button:IsA("GuiObject") and isShown(button) then button else nil
	end
	-- Bouton du HUD a viser ; si un autre menu est ouvert (HUD cache) : son bouton X
	local function pointAt(gui: GuiObject?, text: string): Target?
		return if gui then { gui = gui, arrowHeight = 0, text = text } else nil
	end
	local function hudTarget(name: string, text: string): Target?
		local button = hudButton(name)
		if button then
			return pointAt(button, text)
		end
		local open = activeMenu()
		if open ~= "" then
			return pointAt(closeButton(open), Tutorial.Steps.CloseMenu)
		end
		return nil
	end
	-- Premier bouton CLAIM visible du menu Index
	local function claimButton(): GuiObject?
		local shop = player.PlayerGui:FindFirstChild("ShopGUI")
		local frames = shop and shop:FindFirstChild("MenuFrames")
		local index = frames and frames:FindFirstChild("Index")
		for _, item in (if index then index:GetDescendants() else {}) do
			if item.Name == "Claim" and item:IsA("GuiObject") and isShown(item) then
				return item
			end
		end
		return nil
	end
	-- Tuiles d'amelioration de l'etage 1 (Boards.<Board>.<id>.Tile), recherchees au plus toutes les 10 s
	local function tileOf(floor: Model, id: string): BasePart?
		if os.clock() - tileCacheAt > 10 then
			tileCacheAt = os.clock()
			table.clear(tileCache)
			for _, item in floor:GetDescendants() do
				local upgradeId = item:GetAttribute("UpgradeId")
				local tile = type(upgradeId) == "string" and item:FindFirstChild("Tile")
				if tile and tile:IsA("BasePart") then
					tileCache[upgradeId] = tile
				end
			end
		end
		local tile = tileCache[id]
		if tile and tile.Parent and tile.Transparency < 1 and tile.LocalTransparencyModifier < 1 then
			return tile
		end
		return nil
	end
	local function machinePad(floor: Model, id: string): BasePart?
		local model = MachineModels.Find(floor, id)
		return visiblePad(model and model:FindFirstChild("Pad"))
	end

	-- Etape du tutoriel et cible (une seule chose a faire)
	local function compute(): Target?
		local saved = player:GetAttribute("TutorialStep")
		if type(saved) ~= "number" or saved >= Tutorial.Done or player:GetAttribute("IntroPlaying") == true then
			return nil
		end
		local myBase = FloorWatch.MyBase()
		if myBase and numberAttribute(myBase, "FloorsOwned", 1) >= Tutorial.StopAtFloor then
			return nil -- etage 2 : plus de tutoriel (le serveur met aussi TutorialStep = Done)
		end
		local floor = myFirstFloor()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if floor == nil or root == nil or not root:IsA("BasePart") then
			return nil
		end
		local now = os.clock()
		if saved ~= phaseStep then
			-- Nouvelle etape : on repart de zero pour ce qu'on observe
			phaseStep = saved
			phaseStartedAt = now
			claimSeen = false
			noClaimSince = nil
			soldSeen = false
			speedLevelAtStart = numberAttribute(player, "PUp_WalkSpeed", 1)
			suggestion = nil
			nextSuggestAt = now + Tutorial.SuggestEverySeconds
		end
		local phase = Tutorial.Phases[saved + 1]
		local step = numberAttribute(floor, "Lv_Setup", Setup.Done)
		local steps = Tutorial.Steps
		local carried = fruitsCarried()
		if step >= 2 and lastCarried > 0 and carried == 0 then
			droppedOnce = true
			lastDropAt = now
		end
		lastCarried = carried
		local juices = numberAttribute(player, "HandJuices", 0)
		local onCounter = numberAttribute(floor, "CounterJuices", 0)
		if onCounter > 0 then
			soldSeen = true
		end
		local cash = money()
		local cashRose = cash > lastMoney
		lastMoney = cash
		-- Argent encaisse apres une vente : le tour est fini, on repart a "faire des jus"
		local collected = soldSeen and cashRose
		if collected then
			soldSeen = false
		end
		local function at(part: BasePart?, text: string, height: number?): Target?
			return if part
				then { part = part, arrowHeight = height or Tutorial.ArrowHeight, text = text, ring = height == nil }
				else nil
		end
		local function point(gui: GuiObject?, text: string): Target?
			return if gui then { gui = gui, arrowHeight = 0, text = text } else nil
		end
		local function pad(key: string): BasePart?
			return visiblePad(findPath(floor, Tutorial.Targets[key]))
		end
		local wanted = math.min(Tutorial.PickFruits, numberAttribute(player, "InvMax", Tutorial.PickFruits))
		-- Jus (mixeur 1) : mixer (E) si son bol a des fruits ; prendre les jus s'il y en a sur la table
		-- (gobelets de Dynamic.Production) ou en cours de mixage ; sinon il faut des fruits : poser ceux
		-- qu'on porte, ou en ramasser (cas d'une reconnexion : plateau et bol vides).
		local function juiceStep(): Target?
			local blender = findPath(floor, Tutorial.Targets.Blender)
			local panel = blender and blender:FindFirstChild("Panel", true)
			local bowl = if blender then numberAttribute(blender, "BowlCount", 0) else 0
			local blending = blender ~= nil and blender:GetAttribute("Blending") == true
			local held = if blender then numberAttribute(blender, "HeldJuices", 0) else 0
			local pulse = blender and blender:GetAttribute("Pulse")
			if pulse ~= lastPulse then
				if lastPulse ~= nil then
					lastPulseAt = now
				end
				lastPulse = pulse
			end
			local production = floor:FindFirstChild("Production")
			local travel = if production then numberAttribute(production, "ConveyorTravel", 2) else 2
			local inTransit = now - lastDropAt < Tutorial.TransitGraceSeconds
				or now - lastPulseAt < travel + Tutorial.TransitGraceSeconds
			if panel and panel:IsA("BasePart") and (bowl > 0 or inTransit) and not blending then
				return at(panel, steps.Blend, Tutorial.ArrowHeightPanel)
			end
			local cups = 0
			local dynamic = floor:FindFirstChild("Dynamic")
			local production = dynamic and dynamic:FindFirstChild("Production")
			for _, item in (if production then production:GetChildren() else {}) do
				if item:IsA("Model") and item:FindFirstChild("Cup") then
					cups += 1
				end
			end
			if blending or held > 0 or cups > 0 then
				return at(pad("TakeJuices"), steps.TakeJuices)
			elseif carried > 0 then
				return at(pad("FruitDrop"), steps.DropFruits)
			end
			local fruit = nearestFruit(floor, root.Position)
			if fruit then
				return at(fruit, steps.PickFruits, Tutorial.ArrowHeightFruit)
			end
			-- (fruits sur le tapis : ils arrivent dans le bol)
			return if panel and panel:IsA("BasePart") then at(panel, steps.Blend, Tutorial.ArrowHeightPanel) else nil
		end
		-- Un tour de vente : jus en main -> comptoir ; jus poses -> encaisser ; sinon faire des jus
		local function sellStep(): Target?
			if juices > 0 then
				return at(pad("JuiceDrop"), steps.SellJuices)
			elseif soldSeen then
				return at(pad("Cash"), steps.CollectCash)
			end
			return juiceStep()
		end
		local function withGoal(found: Target?, sub: string): Target?
			if found then
				found.sub = sub
			end
			return found
		end

		if phase == "Factory" then
			if step == 0 then
				return at(freePad(floor, 1), steps.PlantTree)
			elseif step == 1 then
				local fruit = if carried < wanted then nearestFruit(floor, root.Position) else nil
				if fruit then
					return at(fruit, steps.PickFruits, Tutorial.ArrowHeightFruit)
				end
				return at(freePad(floor, 2), steps.BuildShelf)
			elseif step == 2 then
				if carried > 0 then
					return at(pad("FruitDrop"), steps.DropFruits)
				end
				local fruit = if not droppedOnce then nearestFruit(floor, root.Position) else nil
				if fruit then
					return at(fruit, steps.PickFruits, Tutorial.ArrowHeightFruit)
				end
				return at(freePad(floor, 3), steps.BuildBlender)
			elseif step == 3 then
				if juices > 0 then
					return at(freePad(floor, 4), steps.OpenShop)
				elseif carried > 0 then
					return at(pad("FruitDrop"), steps.DropFruits)
				end
				return juiceStep()
			end
			-- Usine construite : vendre puis encaisser le premier argent
			if cash > 0 then
				advance(saved)
				return nil
			end
			return sellStep()
		elseif phase == "Picker" then
			if numberAttribute(floor, "Lv_" .. Tutorial.PickerId, 0) >= 1 then
				advance(saved)
				return nil
			end
			local price = Upgrades.GetPrice(Tutorial.PickerId, 0)
			if cash >= price then
				return at(machinePad(floor, Tutorial.PickerId), steps.HirePicker)
			end
			local sub = string.gsub(steps.EarnPicker, "{cash}", NumberFormat.Money(cash))
			sub = string.gsub(sub, "{price}", NumberFormat.Price(price))
			return withGoal(sellStep(), sub)
		elseif phase == "OpenIndex" then
			if activeMenu() == "Index" then
				advance(saved)
				return nil
			end
			return hudTarget("Index", steps.OpenIndex)
		elseif phase == "ClaimIndex" then
			if claimSeen then
				advance(saved)
				return nil
			end
			if activeMenu() ~= "Index" then
				noClaimSince = nil
				return hudTarget("Index", steps.OpenIndex)
			end
			local button = claimButton()
			if button then
				noClaimSince = nil
				return point(button, steps.ClaimIndex)
			end
			-- Menu ouvert mais rien a prendre (deja tout pris) : on passe
			noClaimSince = noClaimSince or now
			if now - (noClaimSince :: number) > 1.5 then
				advance(saved)
			end
			return nil
		elseif phase == "Loop" then
			-- Ameliorer l'arbre une fois pendant ce tour (2026-11-22, demande : "le fait qu'il faut
			-- ameliorer l'arbre") : pas une etape sauvegardee a part (les numeros d'etape sauvegardes ne
			-- bougent pas) ; c'est fait quand Lv_Tree depasse 1. Pad visible seulement avec le prix,
			-- sinon on refait des jus avec la petite ligne "Tree: $x / $15".
			local treeLevel = numberAttribute(floor, "Lv_" .. Tutorial.TreeId, 1)
			if treeLevel <= 1 then
				local price = Upgrades.GetPrice(Tutorial.TreeId, treeLevel)
				local treePad = machinePad(floor, Tutorial.TreeId)
				if treePad then
					if cash >= price then
						return at(treePad, steps.UpgradeTree)
					end
					local sub = string.gsub(steps.EarnTree, "{cash}", NumberFormat.Money(cash))
					sub = string.gsub(sub, "{price}", NumberFormat.Price(price))
					return withGoal(sellStep(), sub)
				end
			end
			if collected then
				advance(saved)
				return nil
			end
			return sellStep()
		elseif phase == "Upgrade" then
			local free = player:GetAttribute("FreeSpeed") == true
			if not free or numberAttribute(player, "PUp_WalkSpeed", 1) > speedLevelAtStart then
				advance(saved)
				return nil
			end
			if activeMenu() ~= "Upgrade" then
				return hudTarget("UpgradeButton", steps.OpenUpgrades)
			end
			local menuModule = script.Parent:FindFirstChild("UpgradeMenuController")
			local menu = if menuModule then (require(menuModule :: ModuleScript) :: any) else nil
			local button = menu and menu.GetBuyButton and menu.GetBuyButton("WalkSpeed")
			return point(if button and isShown(button) then button else nil, steps.FreeSpeed)
		elseif phase == "Free" then
			if now - phaseStartedAt >= Tutorial.FreePlaySeconds then
				advance(saved)
			end
			return nil
		elseif phase == "Operator" then
			if numberAttribute(floor, "Lv_" .. Tutorial.OperatorId, 0) >= 1 then
				advance(saved)
				return nil
			end
			if cash >= Upgrades.GetPrice(Tutorial.OperatorId, 0) then
				return at(machinePad(floor, Tutorial.OperatorId), steps.HireOperator)
			end
			return nil
		elseif phase == "Suggest" then
			local current = suggestion
			if current then
				local level = numberAttribute(floor, "Lv_" .. current.id, 0)
				if level > current.startLevel or now > current.untilAt then
					suggestion = nil
					nextSuggestAt = now + Tutorial.SuggestEverySeconds
					return nil
				end
				-- Plus assez d'argent (autre chose achete entre-temps) : pas de fleche ; la proposition
				-- est gardee et revient des que le joueur peut la payer (delai remis a plein).
				if cash < Upgrades.GetPrice(current.id, level) then
					current.untilAt = now + Tutorial.SuggestTimeoutSeconds
					return nil
				end
				local upgrade = Upgrades.ById[current.id]
				local text = string.gsub(steps.BuyUpgrade, "{name}", if upgrade then upgrade.title else current.id)
				return at(tileOf(floor, current.id), text, Tutorial.ArrowHeightPanel)
			end
			if now < nextSuggestAt then
				return nil
			end
			-- Une amelioration au hasard parmi celles qu'il peut payer (tuile visible, pas au max)
			local levels: { [string]: number } = {}
			for _, id in Tutorial.SuggestIds do
				levels[id] = numberAttribute(floor, "Lv_" .. id, 0)
			end
			levels[Tutorial.PickerId] = numberAttribute(floor, "Lv_" .. Tutorial.PickerId, 0)
			local choices: { string } = {}
			for _, id in Tutorial.SuggestIds do
				local level = levels[id]
				if
					tileOf(floor, id)
					and level < Upgrades.GetMaxLevel(id, 0)
					and not Upgrades.IsLocked(id, levels)
					and cash >= Upgrades.GetPrice(id, level)
				then
					table.insert(choices, id)
				end
			end
			if #choices == 0 then
				nextSuggestAt = now + 5 -- pas assez d'argent : on regarde un peu plus tard
				return nil
			end
			local id = choices[math.random(1, #choices)]
			suggestion = { id = id, startLevel = levels[id], untilAt = now + Tutorial.SuggestTimeoutSeconds }
			return nil
		end
		return nil
	end

	RunService.PreRender:Connect(function(dt: number)
		clock += dt
		local current = target
		if current == nil then
			return
		end
		local gui = current.gui
		if gui then
			if gui.Parent == nil or not isShown(gui) then
				show(nil)
				return
			end
			stepPulse(gui)
			local bounce = math.abs(math.sin(clock * 4)) * Tutorial.PointerBounce
			-- Repere du ScreenGui de la fleche (barre du haut et zones sures comprises)
			local holder = pointer.Parent
			local origin = if holder and holder:IsA("LayerCollector") then holder.AbsolutePosition else Vector2.zero
			local spot = gui.AbsolutePosition - origin
			local size = gui.AbsoluteSize
			local camera = workspace.CurrentCamera
			local width = if camera then camera.ViewportSize.X else 1000
			if gui.AbsolutePosition.X + size.X / 2 < width * 0.25 then
				-- Bouton au bord gauche (Shop / Index empiles) : fleche a droite, qui pointe vers la gauche
				pointer.Rotation = 180
				pointer.AnchorPoint = Vector2.new(0, 0.5)
				pointer.Position = UDim2.fromOffset(spot.X + size.X + 4 + bounce, spot.Y + size.Y / 2)
			else
				-- Ailleurs : fleche au-dessus, qui pointe vers le bas
				pointer.Rotation = 90
				pointer.AnchorPoint = Vector2.new(0.5, 1)
				pointer.Position = UDim2.fromOffset(spot.X + size.X / 2, spot.Y - 4 - bounce)
			end
		end
		local part = current.part
		if part == nil then
			return
		end
		if part.Parent == nil then
			show(nil) -- (fruit ramasse : la prochaine cible arrive au prochain calcul)
			return
		end
		local position = part.Position
		to.WorldPosition = position + Vector3.new(0, 0.6, 0)
		-- Rebond : arc de balle (rapide en bas, lent en haut) + petit "pop" de taille a l'impact
		local phase = (clock * Tutorial.ArrowBounceSpeed) % 1
		local y = current.arrowHeight + 4 * phase * (1 - phase) * Tutorial.ArrowBounce
		local impact = math.max(0, 1 - math.min(phase, 1 - phase) * 8) -- 1 au point bas, 0 a 1/8 de cycle
		arrow:ScaleTo(1 + impact * Tutorial.ArrowPop)
		arrow:PivotTo(CFrame.new(position + Vector3.new(0, y, 0)) * CFrame.Angles(0, clock * 1.2, 0))
		if current.ring then
			if ring.Parent ~= workspace then
				ring.Parent = workspace
			end
			local grow = (clock * 0.8) % 1
			local base = math.max(part.Size.X, part.Size.Z)
			local size = base * (0.6 + 0.6 * grow)
			ring.Size = Vector3.new(0.1, size, size)
			ring.Transparency = 0.25 + 0.75 * grow
			ring.CFrame = CFrame.new(position.X, position.Y - part.Size.Y / 2 + 0.08, position.Z)
				* CFrame.Angles(0, 0, math.pi / 2)
		elseif ring.Parent ~= nil then
			ring.Parent = nil
		end
	end)

	-- Argent sur un tas (attribut d'etage PileCash, CustomerService) : fleche + ligne vers le pad
	-- Collect Cash le plus proche, tutoriel fini ou pas, jusqu'a ce que tout soit encaisse.
	-- Plus montree une fois l'etage 2 debloque (attribut de base FloorsOwned, FloorService) :
	-- le joueur connait le geste (2026-11-23).
	local function cashTarget(): Target?
		local base = FloorWatch.MyBase()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if base == nil or root == nil or not root:IsA("BasePart") or player:GetAttribute("IntroPlaying") == true then
			return nil
		end
		if numberAttribute(base, "FloorsOwned", 1) >= Tutorial.CashArrowUntilFloor then
			return nil
		end
		local best: BasePart? = nil
		local bestDistance = math.huge
		for _, floor in FloorWatch.FloorsOf(base) do
			if numberAttribute(floor, "PileCash", 0) > 0 then
				local zone = visiblePad(findPath(floor, Tutorial.Targets.Cash))
				local distance = if zone then (zone.Position - root.Position).Magnitude else math.huge
				if zone and distance < bestDistance then
					best, bestDistance = zone, distance
				end
			end
		end
		if best == nil then
			return nil
		end
		-- Objectif en haut de l'ecran seulement pendant le tutoriel
		local step = player:GetAttribute("TutorialStep")
		local inTutorial = type(step) == "number" and step < Tutorial.Done
		return {
			part = best,
			arrowHeight = Tutorial.ArrowHeight,
			text = if inTutorial then Tutorial.Steps.CollectCash else "",
			ring = true,
		}
	end

	-- Conseil unique apres l'etage 2 (2026-11-23, demande : "1 minute apres avoir debloque, et quand
	-- il a assez d'argent, lui montrer d'acheter l'amelioration de l'ascenseur ; ensuite plus de tuto").
	-- Montre ElevatorHintDelaySeconds apres avoir vu l'etage 2 possede (dans cette session), tant que
	-- les deux ameliorations de l'ascenseur sont a 0 (attributs de base ElevatorSpeed / ElevatorCabin,
	-- FloorService) et jamais apres un rebirth. Fait = un niveau d'ascenseur achete : plus rien.
	local floor2SeenAt: number? = nil
	local function elevatorTarget(): Target?
		local base = FloorWatch.MyBase()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if base == nil or root == nil or player:GetAttribute("IntroPlaying") == true then
			return nil
		end
		if numberAttribute(base, "FloorsOwned", 1) < Tutorial.StopAtFloor then
			floor2SeenAt = nil
			return nil
		end
		local now = os.clock()
		floor2SeenAt = floor2SeenAt or now
		if now - (floor2SeenAt :: number) < Tutorial.ElevatorHintDelaySeconds then
			return nil
		end
		if numberAttribute(player, "Rebirths", 0) > 0 then
			return nil
		end
		for _, upgrade in Floors.ElevatorUpgrades do
			if numberAttribute(base, upgrade.id, 0) > 0 then
				return nil -- deja achete : conseil fini
			end
		end
		local id = Tutorial.ElevatorHintId
		local price = Floors.TowerUpgradePrice(id, numberAttribute(base, id, 0))
		if price == nil or money() < price then
			return nil
		end
		local annex = base:FindFirstChild("Annex")
		local board = annex and findPath(annex, "Terrace.ElevatorBoard")
		for _, tile in (if board then board:GetChildren() else {}) do
			if tile:GetAttribute("TowerUpgradeId") == id then
				local part = tile:FindFirstChild("BuyButton") or tile:FindFirstChild("Tile")
				if part and part:IsA("BasePart") then
					return { part = part, arrowHeight = Tutorial.ArrowHeightPanel, text = Tutorial.Steps.UpgradeElevator }
				end
			end
		end
		return nil
	end

	task.spawn(function()
		while true do
			local ok, result = pcall(compute)
			if ok and result == nil then
				local okElevator, hint = pcall(elevatorTarget)
				if okElevator then
					result = hint
				end
			end
			-- Le tas d'argent passe avant les cibles du monde (pas avant une fleche dans un menu)
			if ok and (result == nil or result.part ~= nil) then
				local okCash, cash = pcall(cashTarget)
				if okCash and cash then
					result = cash
				end
			end
			if ok then
				-- Cible dans le monde mais un menu ouvert la cache : fleche aussi sur son X
				local open = activeMenu()
				if result and result.part and result.gui == nil and open ~= "" then
					result.gui = closeButton(open)
				end
				show(result)
			else
				warn(`[TutorialController] {result}`)
				show(nil)
			end
			task.wait(Tutorial.RefreshSeconds)
		end
	end)
end

return TutorialController
