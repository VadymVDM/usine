--!strict
-- Animation "NEW FRUIT!" quand le joueur decouvre un fruit (client seulement, rien n'est decide ici).
-- Le serveur decide de la decouverte et previent ce joueur : remote Feedback, kind "Discover",
-- payload { fruit = "<id>" } (verifie ici : chaine + fruit connu dans Config/Fruits).
--   1. le fond s'assombrit un peu ; le fruit en 3D (ViewportFrame, il tourne sur lui-meme) arrive au
--      centre en grossissant (pop "gelee") ;
--   2. au-dessus "NEW FRUIT!" (degrade dore comme "NEW FLOOR!"), en dessous le nom, la rarete dans sa
--      couleur et "1 in X" (pas pour le Common) ; ces textes tombent / montent a leur place en
--      fondu, sans jamais grossir (UI/TextPop : sinon ils clignotent sur telephone) ;
--   3. confettis aux couleurs de la rarete + son ; Legendary+ : rayons qui tournent derriere le
--      fruit, 2e salve de confettis et 2e son ;
--   4. apres ~2 s (ou un clic / tap / bouton A), le fruit rapetisse et vole jusqu'au bouton Index du
--      HUD, qui rebondit et prend la pastille rouge (MenuController.SetBadge). Pas de bouton Index
--      trouve : le fruit vole vers le bord gauche et disparait.
-- Le joueur peut toujours bouger (pas de Modal, rien d'Active). Plusieurs decouvertes = file
-- d'attente. Tout est detruit a la fin de chaque decouverte.
-- Test (barre de commande, client) : require(<ce module>).Play("<id du fruit>")
-- Doc : docs/systems/fruits.md (section "Decouverte et Index"), docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes")) :: any
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local FruitModels = require(Shared:WaitForChild("FruitModels")) :: any
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))
local Celebration = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Celebration"))
local TextPop = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("TextPop"))

local DISPLAY_ORDER = 48 -- au-dessus de "NEW FLOOR!" (45), sous les confettis (50)
local DIM_TRANSPARENCY = 0.6 -- fond noir
local HOLD_SECONDS = 2 -- temps au centre avant le vol
local FLY_SECONDS = 0.5 -- vol jusqu'au bouton Index (total ~2.5 s)
local SKIP_DELAY = 0.35 -- s : un clic avant ce delai ne passe pas (evite le clic "en trop")
local SAFETY_SECONDS = 8 -- securite : une decouverte ne bloque jamais la file plus longtemps
local SPIN_SPEED = 1.1 -- rad/s : rotation lente du fruit
local FRUIT_Y = 0.45 -- centre du fruit dans la carte (fraction de la hauteur)
local TEXT_DROP = 0.3 -- chute des textes a l'arrivee (fraction de la hauteur de la carte)
local BIG_RARITY = 5 -- Legendary et plus : rayons + effets plus forts
local RAY_COUNT = 10 -- barres (2 rayons chacune)
local RAY_SPEED = 28 -- degres / s
local INDEX_BUTTON = "Index"
local SOUND = "NewFruit" -- "Cute level up" (Config/Sounds)
local BIG_SOUND = "TreeChime" -- "Bright Plucks" : 2e son pour Legendary+
local ARRIVE_SOUND = "Pickup" -- pop a l'arrivee sur le bouton
local GOLD = { Color3.fromRGB(255, 245, 120), Color3.fromRGB(255, 170, 30) } -- comme "NEW FLOOR!"

local DiscoveryController = {}

local player = Players.LocalPlayer
local started = false

-- File d'attente des decouvertes
local queue: { string } = {}
local running = false
local current: string? = nil

---------------------------------------------------------------------------------------------
-- Aides

local function menuController(): any?
	local module = script.Parent:FindFirstChild("MenuController")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

-- 1000 -> "1,000"
local withCommas = NumberFormat.Commas

local function fadeLabel(label: TextLabel, info: TweenInfo)
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
end

-- Modele 3D du fruit (FruitAssets via FruitModels) ; boule de la couleur du jus si rien ne marche.
local function buildModel(fruitId: string, color: Color3): Model
	local ok, result = pcall(FruitModels.CreateFruit, fruitId, true)
	if ok and typeof(result) == "Instance" and result:IsA("Model") and result:FindFirstChildWhichIsA("BasePart", true) then
		return result
	end
	if ok and typeof(result) == "Instance" then
		result:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = fruitId
	local ball = Instance.new("Part")
	ball.Name = "Body"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2, 2, 2)
	ball.Color = color
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.Parent = model
	model.PrimaryPart = ball
	return model
end

-- Bouton Index du HUD (PlayerGui.HUD.Canvas.Buttons.FourButtons.Index, comme MenuController.SetBadge),
-- sinon le premier GuiButton du HUD dont le nom contient "Index". nil s'il n'est pas a l'ecran.
local function findIndexButton(): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("HUD")
	if hud == nil or not hud:IsA("ScreenGui") or not hud.Enabled then
		return nil
	end
	local found: Instance? = nil
	local canvas = hud:FindFirstChild("Canvas")
	local column = canvas and canvas:FindFirstChild("Buttons")
	local four = column and column:FindFirstChild("FourButtons")
	found = four and four:FindFirstChild(INDEX_BUTTON)
	if found == nil or not found:IsA("GuiObject") then
		found = nil
		for _, item in hud:GetDescendants() do
			if item:IsA("GuiButton") and string.find(item.Name, INDEX_BUTTON, 1, true) then
				found = item
				break
			end
		end
	end
	if found == nil or not found:IsA("GuiObject") or not found.Visible then
		return nil
	end
	local size = found.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return nil
	end
	return found
end

-- Rebond "gelee" du bouton Index : on prend son UIScale (celui du survol de MenuController) et on
-- le remet exactement a sa valeur de depart a la fin.
type Bounce = { scale: UIScale, base: number, spring: Jelly.Spring, connection: RBXScriptConnection }
local bounces: { [GuiObject]: Bounce } = {}

local function bounceButton(button: GuiObject)
	local state = bounces[button]
	if state == nil then
		local scale = button:FindFirstChildOfClass("UIScale")
		if scale == nil then
			local newScale = Instance.new("UIScale")
			newScale.Name = "DiscoveryBounce"
			newScale.Parent = button
			scale = newScale
		end
		local uiScale = scale :: UIScale
		local spring = Jelly.Spring(380, 10)
		-- Taille de repos sans la pulsation du tutoriel (attribut PulseFactor, TutorialController)
		local pulseFactor = uiScale:GetAttribute("PulseFactor")
		local base = uiScale.Scale / (if type(pulseFactor) == "number" and pulseFactor > 0 then pulseFactor else 1)
		local connection = RunService.RenderStepped:Connect(function(dt: number)
			local live = bounces[button]
			if live == nil then
				return
			end
			Jelly.Step(live.spring, dt)
			if Jelly.Resting(live.spring) or uiScale.Parent == nil then
				uiScale.Scale = live.base
				live.connection:Disconnect()
				bounces[button] = nil
				return
			end
			uiScale.Scale = live.base * math.max(0.3, 1 + live.spring.x)
		end)
		state = { scale = uiScale, base = base, spring = spring, connection = connection }
		bounces[button] = state
	end
	local active = state :: Bounce
	active.spring.v += 6 -- un 2e fruit pendant le rebond relance le ressort
end

---------------------------------------------------------------------------------------------
-- Une decouverte (bloque jusqu'a la fin de l'animation)

local function playOne(fruitId: string)
	local fruit = Fruits.ById[fruitId]
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if fruit == nil or playerGui == nil then
		return
	end
	local rarity = Fruits.Rarities[fruit.rarity]
	local rarityName = if rarity then rarity.name else "???"
	local rarityColor = if rarity then rarity.color else Color3.fromRGB(200, 200, 200)
	local big = fruit.rarity >= BIG_RARITY

	local screen = Instance.new("ScreenGui")
	screen.Name = "DiscoveryFx"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = DISPLAY_ORDER
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Fond assombri : ne capte rien (le joueur bouge et clique au travers)
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Active = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	dim.Parent = screen

	-- Carte invisible : titre en haut, fruit au milieu, infos en bas (tailles relatives + limites)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Active = false
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.9, 0.84)
	card.BackgroundTransparency = 1
	card.ZIndex = 2
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.85
	ratio.Parent = card
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(200, 235)
	limit.MaxSize = Vector2.new(480, 565)
	limit.Parent = card
	card.Parent = screen

	-- Rayons qui tournent derriere le fruit (Legendary+), en Frames (pas d'image a uploader)
	local rays: CanvasGroup? = nil
	if big then
		local group = Instance.new("CanvasGroup")
		group.Name = "Rays"
		group.AnchorPoint = Vector2.new(0.5, 0.5)
		group.Position = UDim2.fromScale(0.5, FRUIT_Y)
		group.Size = UDim2.fromScale(1.05, 1.05)
		group.SizeConstraint = Enum.SizeConstraint.RelativeXX
		group.BackgroundTransparency = 1
		group.GroupTransparency = 1
		group.ZIndex = 1
		local light = rarityColor:Lerp(Color3.new(1, 1, 1), 0.55)
		for i = 1, RAY_COUNT do
			local ray = Instance.new("Frame")
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.fromScale(0.08, 1)
			ray.Rotation = (i - 1) * 180 / RAY_COUNT
			ray.BackgroundColor3 = if i % 2 == 0 then rarityColor else light
			ray.BorderSizePixel = 0
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			gradient.Parent = ray
			ray.Parent = group
		end
		group.Parent = card
		rays = group
	end

	-- Fruit 3D
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Fruit"
	viewport.Active = false
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, FRUIT_Y)
	viewport.Size = UDim2.fromScale(0.62, 0.62)
	viewport.SizeConstraint = Enum.SizeConstraint.RelativeXX
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(175, 175, 175)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.5, -1)
	viewport.ZIndex = 3
	local fruitScale = Instance.new("UIScale")
	fruitScale.Scale = 0.05
	fruitScale.Parent = viewport
	local model = buildModel(fruitId, fruit.juiceColor)
	model:PivotTo(CFrame.new())
	local boxCFrame, boxSize = model:GetBoundingBox()
	local toCenter = CFrame.new(-boxCFrame.Position) -- centre du fruit sur l'origine
	model:PivotTo(toCenter)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local radius = math.max(boxSize.Magnitude / 2, 0.1)
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 1.02
	camera.CFrame = CFrame.lookAt(Vector3.new(0, distance * 0.22, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = card

	-- Textes
	local title = PackStyle.label(card, "NEW FRUIT!", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.17), 100)
	title.ZIndex = 6
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Rotation = 90
	titleGradient.Color = ColorSequence.new(GOLD[1], GOLD[2])
	titleGradient.Parent = title

	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Active = false
	info.AnchorPoint = Vector2.new(0.5, 0)
	info.Position = UDim2.fromScale(0.5, 0.74)
	info.Size = UDim2.fromScale(1, 0.26)
	info.BackgroundTransparency = 1
	info.ZIndex = 6
	info.Parent = card
	local labels: { TextLabel } = { title }
	local nameLabel = PackStyle.label(info, fruit.name, UDim2.fromScale(0.5, 0), UDim2.fromScale(0.95, 0.42), 54)
	nameLabel.ZIndex = 7
	table.insert(labels, nameLabel)
	local rarityLabel = PackStyle.label(info, rarityName, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.8, 0.3), 38)
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.ZIndex = 7
	table.insert(labels, rarityLabel)
	local oneIn = if fruit.rarity > 1 then Fruits.OneIn(fruit.rarity, Fruits.FloorLuckFor(fruit.floor)) else 0
	if oneIn > 1 then
		local chance = PackStyle.label(info, `1 in {withCommas(oneIn)}`, UDim2.fromScale(0.5, 0.72), UDim2.fromScale(0.7, 0.26), 30)
		chance.ZIndex = 7
		table.insert(labels, chance)
	end
	-- Les textes arrivent en "gelee" SANS grossir (sur telephone, un texte qui grossit clignote :
	-- UI/TextPop) : "NEW FRUIT!" tombe d'en haut, les infos montent d'en bas, en fondu. Le fruit 3D,
	-- lui, garde son pop qui grossit (pas de texte dedans).
	local titleSpring = Jelly.Spring(300, 12)
	titleSpring.x = -0.95
	local titleDrop = TextPop.NewDrop(title, titleSpring, TEXT_DROP)
	local infoSpring = Jelly.Spring(300, 12)
	infoSpring.x = -0.95
	local infoDrop = TextPop.NewDrop(info, infoSpring, -TEXT_DROP)

	screen.Parent = playerGui

	-- Son + confettis
	SoundFx.Play(SOUND)
	local party = {
		rarityColor,
		rarityColor:Lerp(Color3.new(1, 1, 1), 0.45),
		if rarity and rarity.outline then rarity.outline else rarityColor:Lerp(Color3.new(0, 0, 0), 0.25),
		Color3.fromRGB(255, 205, 50),
		Color3.fromRGB(255, 255, 255),
	}
	Celebration.Confetti(playerGui, party)
	if big then
		SoundFx.Play(BIG_SOUND)
		task.delay(0.35, function()
			if screen.Parent ~= nil then
				Celebration.Confetti(playerGui, party)
			end
		end)
	end
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = DIM_TRANSPARENCY }):Play()
	if rays then
		TweenService:Create(rays, TweenInfo.new(0.4), { GroupTransparency = 0.15 }):Play()
	end

	-- Etat de l'animation
	local done = Instance.new("BindableEvent")
	local finished = false
	local phase = "show" -- "show" -> "fly" -> "done"
	local elapsed = 0
	local angle = 0
	local fruitSpring = Jelly.Spring(240, 11)
	fruitSpring.x = -0.95
	-- Vol (rempli par beginFly)
	local flyStart = 0
	local from, control, target = Vector2.zero, Vector2.zero, Vector2.zero
	local startScale, endScale = 1, 0.2
	local button: GuiObject? = nil
	local renderConnection: RBXScriptConnection? = nil
	local inputConnection: RBXScriptConnection? = nil

	local function finish()
		if finished then
			return
		end
		finished = true
		phase = "done"
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		screen:Destroy()
		done:Fire()
	end

	local function arrive()
		local hudButton = button
		if hudButton and hudButton.Parent ~= nil then
			bounceButton(hudButton)
			SoundFx.Play(ARRIVE_SOUND)
			-- Pastille rouge du HUD (la meme que celle du Shop) ; enlevee a l'ouverture de l'Index
			local menu = menuController()
			if menu and menu.SetBadge and (menu.GetActiveMenu == nil or menu.GetActiveMenu() ~= INDEX_BUTTON) then
				pcall(menu.SetBadge, INDEX_BUTTON, true)
			end
		end
		finish()
	end

	local function beginFly()
		if phase ~= "show" then
			return
		end
		phase = "fly"
		flyStart = elapsed
		-- Le fruit sort de la carte : position et taille en pixels dans l'ecran
		local origin = screen.AbsolutePosition
		local scaleNow = math.max(fruitScale.Scale, 0.05)
		local basePixels = math.max(viewport.AbsoluteSize.X / scaleNow, 1)
		from = viewport.AbsolutePosition + viewport.AbsoluteSize / 2 - origin
		viewport.SizeConstraint = Enum.SizeConstraint.RelativeXY
		viewport.Size = UDim2.fromOffset(basePixels, basePixels)
		viewport.Position = UDim2.fromOffset(from.X, from.Y)
		viewport.ZIndex = 10
		viewport.Parent = screen
		startScale = scaleNow
		local screenSize = screen.AbsoluteSize
		button = findIndexButton()
		local hudButton = button
		local onScreen = false
		if hudButton then
			-- Meme repere pour tous les ScreenGui : on retire l'origine de notre ecran
			target = hudButton.AbsolutePosition + hudButton.AbsoluteSize / 2 - origin
			onScreen = target.X >= 0 and target.Y >= 0 and target.X <= screenSize.X and target.Y <= screenSize.Y
		end
		if hudButton and onScreen then
			local side = math.min(hudButton.AbsoluteSize.X, hudButton.AbsoluteSize.Y)
			endScale = math.clamp(side * 0.8 / basePixels, 0.03, 1)
		else
			button = nil
			target = Vector2.new(screenSize.X * 0.03, screenSize.Y * 0.5)
			endScale = 0.12
		end
		control = Vector2.new((from.X + target.X) / 2, math.min(from.Y, target.Y) - screenSize.Y * 0.12)
		-- Le reste disparait
		local fade = TweenInfo.new(0.25)
		for _, label in labels do
			fadeLabel(label, fade)
		end
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		if rays then
			TweenService:Create(rays, fade, { GroupTransparency = 1 }):Play()
		end
	end

	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if phase == "show" then
			angle += dt * SPIN_SPEED
			Jelly.Step(fruitSpring, dt)
			fruitScale.Scale = math.max(0.05, 1 + fruitSpring.x)
			if elapsed > 0.06 then
				TextPop.StepDrop(titleDrop, dt)
			end
			if elapsed > 0.14 then
				TextPop.StepDrop(infoDrop, dt)
			end
			title.Rotation = math.sin(elapsed * 5) * 3 * math.max(0, 1 - elapsed / HOLD_SECONDS)
			if elapsed >= HOLD_SECONDS then
				beginFly()
			end
		elseif phase == "fly" then
			angle += dt * SPIN_SPEED * 4
			local u = math.clamp((elapsed - flyStart) / FLY_SECONDS, 0, 1)
			local e = u * u * (3 - 2 * u)
			local a = 1 - e
			local p = from * (a * a) + control * (2 * a * e) + target * (e * e)
			viewport.Position = UDim2.fromOffset(p.X, p.Y)
			local s = math.min(1, u * 1.4)
			fruitScale.Scale = startScale + (endScale - startScale) * s
			if button == nil then
				viewport.ImageTransparency = math.clamp((u - 0.6) / 0.4, 0, 1)
			end
			if u >= 1 then
				arrive()
				return
			end
		end
		if rays then
			rays.Rotation = (rays.Rotation + dt * RAY_SPEED) % 360
		end
		model:PivotTo(CFrame.Angles(0, angle, 0) * toCenter)
	end)

	-- Clic / tap / bouton A n'importe ou : on passe au vol (sans bloquer le deplacement)
	inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if phase ~= "show" or elapsed < SKIP_DELAY then
			return
		end
		local kind = input.UserInputType
		local pointer = kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
		-- Souris / doigt sur un bouton ou le joystick : on laisse faire (gameProcessed)
		if (pointer and not gameProcessed) or input.KeyCode == Enum.KeyCode.ButtonA then
			beginFly()
		end
	end)

	task.delay(SAFETY_SECONDS, finish)
	if not finished then
		done.Event:Wait()
	end
	done:Destroy()
end

---------------------------------------------------------------------------------------------

-- Joue l'animation d'un fruit (file d'attente). Aussi pour tester depuis la barre de commande client.
function DiscoveryController.Play(fruitId: string)
	if type(fruitId) ~= "string" or Fruits.ById[fruitId] == nil then
		warn(`[DiscoveryController] Fruit inconnu : {fruitId}`)
		return
	end
	if current == fruitId or table.find(queue, fruitId) then
		return
	end
	table.insert(queue, fruitId)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local id = table.remove(queue, 1) :: string
			current = id
			local ok, err = pcall(playOne, id)
			if not ok then
				warn(`[DiscoveryController] {id} : {err}`)
			end
			current = nil
			task.wait(0.15)
		end
		running = false
	end)
end

local function onFeedback(kind: any, payload: any)
	if kind ~= "Discover" or type(payload) ~= "table" then
		return
	end
	local fruitId = payload.fruit
	if type(fruitId) ~= "string" or Fruits.ById[fruitId] == nil then
		return
	end
	DiscoveryController.Play(fruitId)
end

function DiscoveryController:Init() end

function DiscoveryController:Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local event = Remotes.WaitClientEvent("Feedback")
		if event then
			event.OnClientEvent:Connect(onFeedback)
		end
	end)
end

return DiscoveryController
