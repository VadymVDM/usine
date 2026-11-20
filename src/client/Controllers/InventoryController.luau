--!strict
-- Inventaire des fruits : c'est le PLATEAU sur la tete du joueur (TrayController, 2026-11-19 ;
-- avant : la barre Roblox de base avec un outil par fruit, retiree : la barre Roblox est cachee).
-- Ici : seulement les effets du remote "Feedback" :
--   Pickup     : les fruits ramasses volent du sol jusqu'au plateau, son, texte "+3 Apple" ;
--   Deposit    : les fruits volent du plateau jusqu'a leur caisse de l'etagere (pad "Drop Fruits") ;
--                payload.floor = l'etage (Model FloorK) ; caisse du fruit = Bin<rarete> de
--                l'etage dont FloorIndex == fruit.floor (lot 4b ; sinon pas de caisse : pas de vol) ;
--   (TakeJuice / PlaceJuice : effets dans HandStackController.)
-- Doc : docs/systems/interface.md (Inventaire), docs/systems/chaine-production.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fruits = require(Shared:WaitForChild("Config"):WaitForChild("Fruits"))
local FruitModels = require(Shared:WaitForChild("FruitModels"))
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local MAX_PAYLOAD_ITEMS = 30
local MAX_DEPOSIT_ITEMS = 20
local MAX_WORLD_FLIGHTS = 60
local FLY_TIME_PICKUP = 0.35
local FLY_TIME_DEPOSIT = 0.5
local TEXT_BOTTOM_OFFSET = 110 -- px au-dessus du bas de l'ecran

local InventoryController = {}

local player = Players.LocalPlayer
local started = false
local worldFolder: Folder? = nil
local textLayer: ScreenGui? = nil
local worldFlights = 0

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) ~= math.huge
end

local function isFiniteVector(v: any): boolean
	return typeof(v) == "Vector3" and isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
end

local function getWorldFolder(): Folder
	if worldFolder and worldFolder.Parent then
		return worldFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "InventoryFx"
	folder.Parent = workspace
	worldFolder = folder
	return folder
end

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Sommet du tas de fruits sur le plateau (au-dessus de la tete), nil sans personnage.
local function getTrayTop(): Vector3?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, head.Size.Y / 2 + 1, 0)
	end
	local root = getRoot()
	return if root then root.Position + Vector3.new(0, 3.5, 0) else nil
end

-- Fait voler un modele de `from` vers `getTarget()` (cloche), puis `done`.
local function fly(model: Model, from: Vector3, getTarget: () -> Vector3, seconds: number, height: number, done: () -> ())
	model:PivotTo(CFrame.new(from))
	model.Parent = getWorldFolder()
	worldFlights += 1
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local alpha = math.min(elapsed / seconds, 1)
		local a = alpha * alpha * (3 - 2 * alpha)
		local target = getTarget()
		local pos = from:Lerp(target, a) + Vector3.new(0, 4 * alpha * (1 - alpha) * height, 0)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(540) * alpha, math.rad(25) * alpha))
		if alpha >= 1 then
			connection:Disconnect()
			worldFlights -= 1
			model:Destroy()
			done()
		end
	end)
end

local function makeFruit(id: string): Model?
	local ok, model = pcall(FruitModels.CreateFruit, id, true)
	if not ok then
		return nil
	end
	for _, part in (model :: Model):GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	return model
end

-- Texte "+3 Apple" qui monte et s'efface en bas de l'ecran.
local function floatText(text: string)
	local screen = textLayer
	if screen == nil then
		return
	end
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local k = if phone then 0.8 else 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Size = UDim2.fromOffset(math.floor(240 * k), math.floor(34 * k))
	local startY = -TEXT_BOTTOM_OFFSET * k
	label.Position = UDim2.new(0.5, 0, 1, startY)
	label.FontFace = PackStyle.FONT
	label.Text = text
	label.TextColor3 = PackStyle.MONEY_GREEN
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.floor(28 * k)
	limit.Parent = label
	local stroke = PackStyle.stroke(label, 2.5, PackStyle.TEXT_STROKE)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	label.Parent = screen
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(label, info, { Position = UDim2.new(0.5, 0, 1, startY - 44 * k), TextTransparency = 1 }):Play()
	local fade = TweenService:Create(stroke, info, { Transparency = 1 })
	fade.Completed:Once(function()
		label:Destroy()
	end)
	fade:Play()
end

-- ===== Pickup : les fruits volent du sol jusqu'au plateau (le meme fruit s'y pose a l'arrivee) =====

local function onPickup(payload: any)
	if typeof(payload) ~= "table" or typeof((payload :: any).items) ~= "table" then
		return
	end
	local items = (payload :: any).items :: { any }
	local valid: { { id: string, pos: Vector3 } } = {}
	for i = 1, math.min(#items, MAX_PAYLOAD_ITEMS) do
		local item = items[i]
		if typeof(item) == "table" then
			local id = (item :: any).id
			local pos = (item :: any).pos
			if typeof(id) == "string" and Fruits.ById[id] ~= nil and isFiniteVector(pos) then
				table.insert(valid, { id = id, pos = pos :: Vector3 })
			end
		end
	end
	if #valid == 0 then
		return
	end
	for i, item in valid do
		task.delay((i - 1) * 0.05, function()
			local model = if worldFlights < MAX_WORLD_FLIGHTS then makeFruit(item.id) else nil
			if model == nil or getRoot() == nil then
				SoundFx.Play("Pickup")
				return
			end
			fly(model, item.pos, function(): Vector3
				return getTrayTop() or item.pos
			end, FLY_TIME_PICKUP, 2.5, function()
				SoundFx.Play("Pickup")
			end)
		end)
	end
	local firstId = valid[1].id
	local sameType = true
	for _, item in valid do
		if item.id ~= firstId then
			sameType = false
			break
		end
	end
	local text = if sameType then `+{#valid} {Fruits.ById[firstId].name}` else `+{#valid} fruits`
	task.delay(FLY_TIME_PICKUP, function()
		floatText(text)
	end)
end

-- ===== Deposit : les fruits volent du plateau jusqu'a leur caisse =====

-- Caisse du fruit (une par rarete) sur SON etage : le serveur l'y a range meme si le depot a eu
-- lieu a un autre etage (FloorK voisin dans le meme dossier Floors) ; le fruit vole jusque-la.
local function findBin(depositFloor: Model, fruit: Fruits.Fruit): BasePart?
	local floor: Instance? = depositFloor
	if FloorWatch.IndexOf(depositFloor) ~= fruit.floor then
		floor = nil
		local parent = depositFloor.Parent
		if parent then
			for _, other in parent:GetChildren() do
				if other:IsA("Model") and FloorWatch.IndexOf(other) == fruit.floor then
					floor = other
					break
				end
			end
		end
	end
	if floor == nil then
		return nil
	end
	local production = floor:FindFirstChild("Production")
	local bins = if production then production:FindFirstChild("Bins") else nil
	local bin = if bins then bins:FindFirstChild("Bin" .. fruit.rarity) else nil
	return if bin and bin:IsA("BasePart") then bin else nil
end

local function onDeposit(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local floor = (payload :: any).floor
	local ids = (payload :: any).ids
	if typeof(floor) ~= "Instance" or typeof(ids) ~= "table" then
		return
	end
	local basesFolder = workspace:FindFirstChild("Bases")
	if not (floor :: Instance):IsA("Model") or basesFolder == nil or not (floor :: Instance):IsDescendantOf(basesFolder) then
		return
	end
	local model = floor :: Model
	local list = ids :: { any }
	local count = 0
	for i = 1, math.min(#list, MAX_DEPOSIT_ITEMS) do
		local id = list[i]
		if typeof(id) == "string" and Fruits.ById[id] ~= nil then
			count += 1
			local fruitId = id :: string
			task.delay((count - 1) * 0.04, function()
				local start = getTrayTop()
				local bin = if model:IsDescendantOf(workspace) then findBin(model, Fruits.ById[fruitId]) else nil
				if start == nil or bin == nil or worldFlights >= MAX_WORLD_FLIGHTS then
					return
				end
				local fruit = makeFruit(fruitId)
				if fruit == nil then
					return
				end
				local target = bin.Position + Vector3.new(0, bin.Size.Y / 2 + 0.7, 0)
				fly(fruit, start, function(): Vector3
					return target
				end, FLY_TIME_DEPOSIT, 3 + (start - target).Magnitude * 0.12, function()
					SoundFx.PlayAt("Deposit", target)
				end)
			end)
		end
	end
end

local function onFeedback(kind: any, payload: any)
	if typeof(kind) ~= "string" then
		return
	end
	if kind == "Pickup" then
		onPickup(payload)
	elseif kind == "Deposit" then
		onDeposit(payload)
	end
end

-- ===== Cycle de vie =====

function InventoryController.Init() end

function InventoryController.Start()
	if started then
		return
	end
	started = true

	-- Barre Roblox par defaut (Backpack) : cachee, les fruits sont sur le plateau (peut echouer tres
	-- tot : on reessaie)
	task.spawn(function()
		for _ = 1, 8 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then
				return
			end
			task.wait(1)
		end
	end)

	local screen = Instance.new("ScreenGui")
	screen.Name = "PickupText"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.DisplayOrder = 2
	screen.Parent = player:WaitForChild("PlayerGui")
	textLayer = screen

	task.spawn(function()
		local event = Remotes.WaitClientEvent("Feedback")
		if event then
			event.OnClientEvent:Connect(onFeedback)
		end
	end)
end

return InventoryController
