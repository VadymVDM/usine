--!strict
-- Apercu de TOUTE l'usine en mode Edit (sans Play). Demande du 2026-11-27 : "voir mes trucs
-- directement, pas seulement au Play", "tout achete", "bien tout me representer, meme la fleche jaune".
-- Workspace._Preview = BaseTemplate + les FLOORS etages, "tout achete" (niveaux max), a
-- l'emplacement BaseSlot<SLOT> :
--   * etages assembles par Lib/FloorAssembly (le meme code que le jeu) ;
--   * machines construites, employes embauches (silhouettes GhostOnly et pads retires), decor du
--     niveau max (LookId / LookLevel / LookMaxLevel, comme LevelLookController), tuiles "MAX",
--     pads FREE de l'usine a construire retires, salle du Rebirth ouverte ;
--   * arbre de chaque etage au niveau max (Lib/TreeBuilder) + fruits au sol ("Tree full!") ;
--   * PNJ immobiles : employes (Fruit Picker, Waiter, 4 Blender Operators) et 5 clients au comptoir ;
--   * interface dans le monde : textes "Tree full!" + nom de l'arbre, "x12" des caisses + fruit pose
--     dessus, "n/max" des bols et de la table a jus, gobelets sur la table et le comptoir, "xN" du
--     comptoir, tas de billets + "$" ; etage 1 : fleche jaune du tutoriel + anneau + ligne de
--     chevrons (vers le pad Collect Cash), liasse Lucky Cash ; logo du proprietaire en haut de la tour.
-- Archivable = false sur _Preview : jamais sauvegarde dans la place, jamais copie dans le Play.
-- Relancer pour reconstruire. REMOVE = true : supprime l'apercu.
-- Lancer via MCP execute_luau (Edit) ou la barre de commande de Studio.
-- Doc : docs/systems/apercu-edit.md

local FLOORS = 10
local SLOT = 1
local REMOVE = false

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local old = workspace:FindFirstChild("_Preview")
if old then
	old:Destroy()
end
if REMOVE then
	return "Apercu supprime"
end

-- Copie fraiche d'un module (le cache de require garderait une vieille version apres un Rojo sync)
local function freshRequire(module: Instance): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy :: ModuleScript)
	copy:Destroy()
	assert(ok, result)
	return result
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Server = ServerScriptService:WaitForChild("Server")
local Client = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
local FloorAssembly = freshRequire(Server.Lib.FloorAssembly)
-- Passee a FloorAssembly.Build : son propre require(Config.Floors) peut etre une vieille version en cache
local FloorsConfig = freshRequire(Config.Floors)
local TreeBuilder = freshRequire(Server.Lib.TreeBuilder)
local OwnerBadge = freshRequire(Server.Lib.OwnerBadge)
local Upgrades = freshRequire(Config.Upgrades)
local FruitsConfig = freshRequire(Config.Fruits)
local TreeConfig = freshRequire(Config.Tree)
local Npcs = freshRequire(Config.Npcs)
local Gameplay = freshRequire(Config.Gameplay)
local Tutorial = freshRequire(Config.Tutorial)
local LuckyCash = freshRequire(Config.LuckyCash)
local FruitModels = freshRequire(Shared.FruitModels)
local MachineModels = freshRequire(Util.MachineModels)
local WorldLabel = freshRequire(Util.WorldLabel)
local NumberFormat = freshRequire(Util.NumberFormat)
local PackStyle = freshRequire(Client.UI.PackStyle)

local baseTemplate = ServerStorage:FindFirstChild("BaseTemplate") :: Model
local floorTemplate = ServerStorage:FindFirstChild("FloorTemplate") :: Model
assert(baseTemplate and floorTemplate, "ServerStorage.BaseTemplate / FloorTemplate manquant")
local slot = workspace.Map.BaseSlots:FindFirstChild("BaseSlot" .. SLOT) :: BasePart
assert(slot, "Workspace.Map.BaseSlots.BaseSlot" .. SLOT .. " manquant")

local function maxLevel(id: string): number
	return Upgrades.GetMaxLevel(id, 0)
end

local function floorFruits(n: number): { any }
	local list = {}
	for _, fruit in FruitsConfig.List do
		if fruit.floor == n then
			table.insert(list, fruit)
		end
	end
	return list
end

local function decor(p: BasePart, color: Color3)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
end

---------------------------------------------------------------------------------------------
-- PNJ (immobiles). Meme tenue que Lib/NpcRig (EmployeeOutfit, tablier + casquette du poste).

-- Pose chaque accessoire (cheveux, chapeau) sur son point d'accroche du corps.
-- En mode Edit, la soudure de l'accessoire (AccessoryWeld) n'est resolue que par la physique du
-- Play : la poignee restait a sa position brute, jusqu'a 30 studs de la tete, puis etait ancree la
-- (cheveux par terre a cote des clients, signale le 2026-11-27).
local function snapAccessories(rig: Model)
	local bodyAttachments: { [string]: Attachment } = {}
	for _, part in rig:GetChildren() do
		if part:IsA("BasePart") then
			for _, att in part:GetChildren() do
				if att:IsA("Attachment") then
					bodyAttachments[att.Name] = att
				end
			end
		end
	end
	for _, accessory in rig:GetChildren() do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				for _, att in handle:GetChildren() do
					local target = att:IsA("Attachment") and bodyAttachments[att.Name]
					if target then
						handle.CFrame = target.WorldCFrame * (att :: Attachment).CFrame:Inverse()
						break
					end
				end
			end
		end
	end
end

local function buildRig(outfit: any, shirtColor: Color3): Model?
	for _, withAssets in { true, false } do
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = outfit.skin
		desc.LeftArmColor = if outfit.shirt > 0 then outfit.skin else shirtColor
		desc.RightArmColor = if outfit.shirt > 0 then outfit.skin else shirtColor
		desc.TorsoColor = shirtColor
		desc.LeftLegColor = Color3.fromRGB(60, 70, 110)
		desc.RightLegColor = Color3.fromRGB(60, 70, 110)
		if withAssets then
			desc.Shirt = outfit.shirt
			desc.Pants = outfit.pants
			desc.Face = outfit.face
			if outfit.hair > 0 then
				desc.HairAccessory = tostring(outfit.hair)
			end
			if outfit.hat > 0 then
				desc.HatAccessory = tostring(outfit.hat)
			end
		end
		local ok, rig = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
		end)
		desc:Destroy()
		if ok and rig then
			snapAccessories(rig)
			for _, item in rig:GetDescendants() do
				if item:IsA("Script") or item:IsA("LocalScript") then
					item:Destroy()
				elseif item:IsA("BasePart") then
					item.Anchored = true
				end
			end
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			return rig
		end
	end
	return nil
end

local function weld(rig: Model, name: string, size: Vector3, offset: CFrame, to: BasePart, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = to.CFrame * offset
	p.Parent = rig
end

local function dressEmployee(rig: Model, title: string, color: Color3)
	local torso = rig:FindFirstChild("Torso") :: BasePart?
	local head = rig:FindFirstChild("Head") :: BasePart?
	if torso then
		weld(rig, "Apron", Vector3.new(1.6, 1.7, 0.1), CFrame.new(0, -0.1, -0.55), torso, color)
		weld(rig, "ApronStrap", Vector3.new(1.6, 0.18, 0.12), CFrame.new(0, 0.75, -0.56), torso, Color3.new(1, 1, 1))
	end
	if head then
		weld(rig, "Cap", Vector3.new(1.25, 0.4, 1.25), CFrame.new(0, 0.62, 0), head, color)
		weld(rig, "CapBrim", Vector3.new(1.25, 0.12, 0.7), CFrame.new(0, 0.46, -0.85), head, color)
		local tag = Instance.new("BillboardGui")
		tag.Name = "RoleTag"
		tag.Size = UDim2.fromScale(6, 1.1)
		tag.StudsOffset = Vector3.new(0, 2.3, 0)
		tag.MaxDistance = 55
		tag.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = title
		label.TextScaled = true
		label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		label.FontFace = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 0.08
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		stroke.Parent = label
		label.Parent = tag
		tag.Parent = head
	end
end

-- Modeles prepares une seule fois, clones ensuite (les vetements se chargent une fois)
local employeeRigs: { [string]: Model } = {}
for role, info in Npcs.Employees do
	local rig = buildRig(Npcs.EmployeeOutfit, info.color)
	if rig then
		dressEmployee(rig, info.title, info.color)
		rig.Name = role
		employeeRigs[role] = rig
	end
end
local customerRigs: { Model } = {}
for i, outfit in Npcs.CustomerOutfits do
	local color = Npcs.FallbackShirtColors[((i - 1) % #Npcs.FallbackShirtColors) + 1]
	local rig = buildRig(outfit, color)
	if rig then
		rig.Name = "Customer" .. i
		table.insert(customerRigs, rig)
	end
end

-- Pose un PNJ debout sur `ground` (point au sol), tourne vers `facing` (direction).
-- Les pieds (bas des jambes R6) sont poses sur le sol : le pivot du rig et sa boite englobante
-- ne sont pas fiables (accessoires mal charges = boite de 20 studs de haut, vu le 2026-11-27).
local function placeNpc(template: Model?, ground: Vector3, facing: Vector3?, parent: Instance)
	if template == nil then
		return
	end
	local rig = template:Clone()
	local dir = if facing then Vector3.new(facing.X, 0, facing.Z) else Vector3.new(0, 0, -1)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	rig:PivotTo(CFrame.lookAt(ground, ground + dir.Unit))
	local lowest = math.huge
	for _, name in { "Left Leg", "Right Leg" } do
		local leg = rig:FindFirstChild(name)
		if leg and leg:IsA("BasePart") then
			lowest = math.min(lowest, leg.Position.Y - leg.Size.Y / 2)
		end
	end
	if lowest ~= math.huge then
		rig:PivotTo(rig:GetPivot() + Vector3.new(0, ground.Y + 0.05 - lowest, 0))
	end
	rig.Parent = parent
end

local function toward(from: Vector3?, to: Instance?): Vector3?
	if from and to and to:IsA("BasePart") then
		return to.Position - from
	end
	return nil
end

local function bottomOf(part: Instance?): Vector3?
	if part and part:IsA("BasePart") then
		return part.Position - Vector3.new(0, part.Size.Y / 2, 0)
	end
	return nil
end

local function findPart(root: Instance?, name: string): BasePart?
	local found = root and root:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

---------------------------------------------------------------------------------------------
-- Interface dans le monde (memes appels WorldLabel que les services du jeu)

-- Tas de billets du comptoir (copie de CustomerService.addBill / targetBills)
local BILL_COLORS = { Color3.fromRGB(150, 220, 120), Color3.fromRGB(118, 196, 96) }
local BILL_SIZE = Vector3.new(1.7, 0.18, 0.85)
local COIN_COLOR = Color3.fromRGB(255, 205, 50)
local CASH_COLOR = Color3.fromRGB(120, 255, 110)

local function moneyPile(pile: BasePart, cash: number, parent: Instance)
	local wanted = math.clamp(math.floor(Gameplay.MoneyBillsPerDoubling * math.log(cash + 1, 2)), 1, Gameplay.MoneyBillsMax)
	local rng = Random.new(7)
	local stacks = Gameplay.MoneyStacks
	local cols = 4
	local rows = math.ceil(stacks / cols)
	local usable = Vector3.new(pile.Size.X * 0.8, 0, pile.Size.Z * 0.8)
	local floorY = -pile.Size.Y / 2
	for index = 1, wanted do
		local stack = (index - 1) % stacks
		local layer = (index - 1) // stacks
		local x = -usable.X / 2 + ((stack % cols) + 0.5) * usable.X / cols
		local z = -usable.Z / 2 + ((stack // cols) + 0.5) * usable.Z / rows
		local coin = index % 7 == 0
		local bill = Instance.new("Part")
		bill.Name = if coin then "Coin" else "Bill"
		decor(bill, if coin then COIN_COLOR else BILL_COLORS[(layer % 2) + 1])
		local jitter = CFrame.new(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
			* CFrame.Angles(0, math.rad(rng:NextNumber(-14, 14)), 0)
		if coin then
			bill.Shape = Enum.PartType.Cylinder
			bill.Size = Vector3.new(0.14, 0.6, 0.6)
			bill.Material = Enum.Material.Metal
			bill.CFrame = pile.CFrame
				* CFrame.new(x + 0.55, floorY + 0.09 + layer * 0.19, z + 0.3)
				* jitter
				* CFrame.Angles(0, 0, math.rad(90))
		else
			bill.Size = BILL_SIZE
			bill.CFrame = pile.CFrame * CFrame.new(x, floorY + 0.09 + layer * 0.19, z) * jitter
		end
		bill.Parent = parent
	end
end

local function worldUi(floor: Model, n: number, folder: Folder)
	local fruits = floorFruits(n)
	local production = floor:FindFirstChild("Production")

	-- Caisses de l'etagere : le fruit de la rarete pose dessus + "xN" (ProductionService.updateBin)
	local bins = production and production:FindFirstChild("Bins")
	for _, fruit in fruits do
		local bin = bins and bins:FindFirstChild("Bin" .. fruit.rarity)
		if bin and bin:IsA("BasePart") then
			local model = FruitModels.CreateFruit(fruit.id, true)
			model:PivotTo(bin.CFrame * CFrame.new(0, bin.Size.Y / 2, 0))
			model.Parent = folder
			local label = WorldLabel.Create(folder, bin, "BinLabel" .. fruit.rarity, {
				maxDistance = Gameplay.BinLabelMaxDistance,
				size = UDim2.fromScale(2.4, 1),
				offset = Vector3.new(0, 2.2, 0),
			})
			WorldLabel.SetPlainText(label, "x" .. math.max(1, 13 - fruit.rarity))
		end
	end

	-- Bols des mixeurs : "n/max" (ProductionService, BowlLabelAnchor)
	local blenders = production and production:FindFirstChild("Blenders")
	for i = 1, Gameplay.MaxBlenders do
		local blender = blenders and blenders:FindFirstChild("Blender" .. i)
		local anchor = findPart(blender, "BowlLabelAnchor")
		if anchor then
			local id = "Blender" .. i
			local capacity = math.floor(Upgrades.GetValue(id, maxLevel(id)))
			local label = WorldLabel.Create(folder, anchor, "BowlLabel" .. i, {
				maxDistance = Gameplay.LabelMaxDistance,
				size = UDim2.fromScale(4.5, 1.5),
			})
			WorldLabel.SetCount(label, math.max(1, capacity // 2), capacity)
		end
	end

	-- Table a jus : gobelets en grille (ProductionService.juiceCupCFrame) + "n/max" + "$"
	local pile = production and production:FindFirstChild("JuicePile")
	if pile and pile:IsA("BasePart") and #fruits > 0 then
		local topY = pile.Position.Y - pile.Size.Y / 2
		local pallet = production and production:FindFirstChild("JuicePallet")
		if pallet and pallet:IsA("Model") and pallet:GetAttribute("Raised") ~= true then
			local cf, size = pallet:GetBoundingBox()
			topY = cf.Position.Y + size.Y / 2
		end
		local corner = pile.CFrame * CFrame.new(-pile.Size.X / 2, 0, -pile.Size.Z / 2)
		local origin = corner + Vector3.new(0, topY - corner.Position.Y, 0)
		local spacing = Gameplay.JuiceCupSpacing
		local colsByTier = Gameplay.JuicePileColsByTier
		local cols = math.clamp(math.floor(pile.Size.X / spacing), 1, colsByTier[#colsByTier])
		local rows = math.clamp(math.floor(pile.Size.Z / spacing), 1, Gameplay.JuicePileRows)
		local marginX = (pile.Size.X - cols * spacing) / 2
		local marginZ = (pile.Size.Z - rows * spacing) / 2
		local limit = math.floor(Upgrades.GetValue("JuiceLimit", maxLevel("JuiceLimit")))
		local count = math.min(limit, cols * rows * 2)
		local total = 0
		for index = 1, count do
			local fruit = fruits[((index - 1) % #fruits) + 1]
			local i = index - 1
			local layer = i // (cols * rows)
			local inLayer = i % (cols * rows)
			local cup = FruitModels.CreateCup(fruit.id, true)
			cup:PivotTo(origin * CFrame.new(
				marginX + ((inLayer % cols) + 0.5) * spacing,
				layer * (FruitModels.CupHeight + 0.05),
				marginZ + ((inLayer // cols) + 0.5) * spacing
			))
			cup.Parent = folder
			total += fruit.value
		end
		local anchor = findPart(production, "JuiceLabelAnchor")
		if anchor then
			local label = WorldLabel.Create(folder, anchor, "JuiceLabel", {
				maxDistance = Gameplay.LabelMaxDistance,
				size = UDim2.fromScale(6, 2),
			})
			WorldLabel.SetCount(label, count, limit)
			local valueLabel = WorldLabel.Create(folder, anchor, "JuiceValueLabel", {
				maxDistance = Gameplay.LabelMaxDistance,
				size = UDim2.fromScale(7, 2.2),
				offset = Vector3.new(0, Gameplay.JuiceValueLabelLift, 0),
			})
			WorldLabel.SetPlainText(valueLabel, "$" .. NumberFormat.Abbreviate(total), Gameplay.JuiceValueColor)
		end
	end

	-- Comptoir : gobelets (CustomerService.cupCFrame) + "xN" ; tas d'argent + "$"
	local counter = floor:FindFirstChild("Counter")
	local top = findPart(counter, "CounterTopArea") or findPart(floor, "CounterTopArea")
	local counterCups = 8
	if top and #fruits > 0 then
		local spacing = Gameplay.JuiceCupSpacing
		local cols = math.max(1, math.floor(top.Size.X / spacing))
		local rows = math.max(1, math.floor(top.Size.Z / spacing))
		local corner = top.CFrame * CFrame.new(-top.Size.X / 2, -top.Size.Y / 2, -top.Size.Z / 2)
		for index = 1, counterCups do
			local i = index - 1
			local layer = i // (cols * rows)
			local inLayer = i % (cols * rows)
			local cup = FruitModels.CreateCup(fruits[((index - 1) % #fruits) + 1].id, true)
			cup:PivotTo(corner * CFrame.new(
				((inLayer % cols) + 0.5) * spacing,
				layer * (FruitModels.CupHeight + 0.05),
				((inLayer // cols) + 0.5) * spacing
			))
			cup.Parent = folder
		end
	end
	local counterAnchor = findPart(counter, "CounterLabelAnchor") or findPart(floor, "CounterLabelAnchor")
	if counterAnchor then
		local label = WorldLabel.Create(folder, counterAnchor, "CounterLabel", {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(6, 2),
		})
		WorldLabel.SetPlainText(label, `x{counterCups}`)
	end
	local cash = (FruitsConfig.FloorValues[n] or 5) * 40
	local moneyTray = findPart(counter, "MoneyPile") or findPart(floor, "MoneyPile")
	if moneyTray then
		moneyPile(moneyTray, cash, folder)
	end
	local moneyAnchor = findPart(counter, "MoneyLabelAnchor") or findPart(floor, "MoneyLabelAnchor")
	if moneyAnchor then
		local label = WorldLabel.Create(folder, moneyAnchor, "MoneyLabel", {
			maxDistance = Gameplay.LabelMaxDistance,
			size = UDim2.fromScale(7, 2.2),
		})
		WorldLabel.SetPlainText(label, "$" .. NumberFormat.Abbreviate(cash), CASH_COLOR)
	end
end

---------------------------------------------------------------------------------------------
-- Fleche jaune du tutoriel, anneau et ligne de chevrons (copie de TutorialController :
-- buildArrow, buildRing, buildGuide ; immobiles ici)

local ARROW_COLOR = Color3.fromRGB(255, 214, 40)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)

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

local function tutorialGuide(floor: Model, folder: Folder)
	local cashPad = floor:FindFirstChild("CashPad", true)
	local target = findPart(cashPad, "PadTop") or findPart(cashPad, "PadZone")
	if target == nil then
		return
	end
	local topPos = target.Position + Vector3.new(0, target.Size.Y / 2, 0)
	local arrow = buildArrow()
	arrow:PivotTo(CFrame.new(topPos + Vector3.new(0, Tutorial.ArrowHeight, 0)))
	arrow.Parent = folder
	local ring = Instance.new("Part")
	ring.Name = "TutorialRing"
	ring.Shape = Enum.PartType.Cylinder
	decor(ring, ARROW_COLOR)
	ring.Size = Vector3.new(0.1, 4, 4)
	ring.Transparency = 0.35
	ring.CFrame = CFrame.new(topPos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	-- Ligne : du point d'apparition de l'etage (le joueur) jusqu'au pad
	local start = findPart(floor:FindFirstChild("Markers"), "SpawnPoint")
	if start then
		local holder = Instance.new("Part")
		holder.Name = "TutorialLineHolder"
		decor(holder, ARROW_COLOR)
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(start.Position + Vector3.new(0, 0.3, 0))
		holder.Parent = folder
		local from = Instance.new("Attachment")
		from.Name = "TutorialFrom"
		from.Parent = holder
		local to = Instance.new("Attachment")
		to.Name = "TutorialTo"
		to.Parent = holder
		to.WorldPosition = topPos + Vector3.new(0, 0.3, 0)
		local beam = Instance.new("Beam")
		beam.Name = "TutorialLine"
		beam.Texture = Tutorial.GuideTexture
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = Tutorial.GuideTextureLength
		beam.TextureSpeed = -Tutorial.GuideSpeed
		beam.Width0 = Tutorial.GuideWidth
		beam.Width1 = Tutorial.GuideWidth
		beam.FaceCamera = true
		beam.LightEmission = Tutorial.GuideLightEmission
		beam.LightInfluence = 0
		beam.Brightness = 1
		beam.Segments = 1
		beam.Color = ColorSequence.new(Tutorial.GuideColor)
		beam.Transparency = NumberSequence.new(0)
		beam.Attachment0 = to
		beam.Attachment1 = from
		beam.Parent = holder
	end
end

---------------------------------------------------------------------------------------------
-- Liasse Lucky Cash (copie de LuckyCashController.buildCash / buildPile, immobile)

local LC_BILL = Color3.fromRGB(46, 196, 64)
local LC_BAND = Color3.fromRGB(170, 255, 120)
local LC_DARK = Color3.fromRGB(30, 150, 50)

local function lcPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	decor(p, color)
	p.Parent = parent
	return p
end

local function luckyCash(floor: Model, folder: Folder)
	local origin = floor:GetPivot() * CFrame.new(LuckyCash.Spot)
	local model = Instance.new("Model")
	model.Name = "LuckyCash_" .. floor.Name
	local cash = Instance.new("Model")
	cash.Name = "Cash"
	for i = 0, 4 do
		local cf = CFrame.new(0, (i - 2) * 0.23, 0) * CFrame.Angles(0, if i % 2 == 0 then 0 else math.rad(4), 0)
		lcPart(cash, "Bill", Vector3.new(2.6, 0.22, 1.25), cf, LC_BILL)
		lcPart(cash, "Edge", Vector3.new(2.66, 0.2, 1.31), cf, LC_DARK)
	end
	local band = lcPart(cash, "Band", Vector3.new(0.7, 1.22, 1.36), CFrame.identity, LC_BAND)
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(100, 100)
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "$"
		label.TextScaled = true
		label.TextColor3 = LC_DARK
		label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
		label.Parent = gui
		gui.Parent = band
	end
	cash.WorldPivot = CFrame.identity
	cash:ScaleTo(2)
	cash:PivotTo(origin * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(15)))
	cash.Parent = model
	local anchor = lcPart(model, "Anchor", Vector3.new(1, 1, 1), origin * CFrame.new(0, 2, 0), LC_BILL)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromScale(7, 3.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local title = PackStyle.label(gui, "LUCKY CASH!", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.45), 60)
	title.TextColor3 = Color3.fromRGB(255, 230, 40)
	local amount = PackStyle.label(gui, "+" .. NumberFormat.Money(25000), UDim2.fromScale(0.5, 0.45), UDim2.fromScale(1, 0.55), 80)
	amount.TextColor3 = Color3.fromRGB(110, 255, 80)
	gui.Parent = anchor
	model.Parent = folder
end

---------------------------------------------------------------------------------------------
-- Un etage "tout achete"

local function maxOut(floor: Model, n: number)
	local dynamic = floor:FindFirstChild("Dynamic") or floor
	local markers = floor:FindFirstChild("Markers")
	local machines = floor:FindFirstChild("Machines")

	-- 1. PNJ (avant de retirer les pads : le Waiter se place sur le sien, comme WorkerService)
	local npcFolder = Instance.new("Folder")
	npcFolder.Name = "PreviewNpcs"
	local treeArea = floor:FindFirstChild("FruitArea", true)
	local collectorHome = bottomOf(markers and markers:FindFirstChild("CollectorHome"))
	if collectorHome then
		placeNpc(employeeRigs.Collector, collectorHome, toward(collectorHome, treeArea), npcFolder)
	end
	local waiterPad = machines and machines:FindFirstChild("Waiter")
	local waiterTop = waiterPad and waiterPad:FindFirstChild("PadTop", true)
	local waiterHome = bottomOf(markers and markers:FindFirstChild("WaiterHome")) or bottomOf(waiterTop)
	-- Le pad est retire plus bas : le Waiter se pose au niveau du sol de l'etage (marqueur SpawnPoint)
	local floorLevel = bottomOf(markers and markers:FindFirstChild("SpawnPoint"))
	if waiterHome and floorLevel then
		waiterHome = Vector3.new(waiterHome.X, floorLevel.Y, waiterHome.Z)
	end
	if waiterHome then
		placeNpc(employeeRigs.Waiter, waiterHome, toward(waiterHome, markers and markers:FindFirstChild("ServerCounter")), npcFolder)
	end
	local production = floor:FindFirstChild("Production")
	local blenders = production and production:FindFirstChild("Blenders")
	for i = 1, 4 do
		local blender = blenders and blenders:FindFirstChild("Blender" .. i)
		local mark = blender and blender:FindFirstChild("Blender" .. i .. "Operator", true)
		local button = blender and blender:FindFirstChild("ButtonGo", true)
		local home = bottomOf(mark)
		if home then
			placeNpc(employeeRigs.Operator, home, toward(home, button), npcFolder)
		end
	end
	-- Clients : tournes comme leur place (CustomerController.placeOf : LookVector du marqueur)
	for i = 1, 5 do
		local spot = markers and markers:FindFirstChild("CustomerSpot" .. i)
		local ground = bottomOf(spot)
		if spot and spot:IsA("BasePart") and ground and #customerRigs > 0 then
			local rig = customerRigs[((n + i - 2) % #customerRigs) + 1]
			placeNpc(rig, ground, spot.CFrame.LookVector, npcFolder)
		end
	end

	-- 2. Machines construites, employes embauches : silhouettes bleues et pads retires
	for _, model in MachineModels.List(floor) do
		local id = model:GetAttribute("UpgradeId")
		if type(id) ~= "string" or Upgrades.ById[id] == nil then
			continue
		end
		for _, item in model:GetDescendants() do
			if item:GetAttribute("GhostOnly") then
				item:Destroy()
			end
		end
		local pad = model:FindFirstChild("Pad")
		if pad then
			pad:Destroy()
		end
		model:SetAttribute("Built", true)
		model:SetAttribute("Level", maxLevel(id))
	end

	-- 3. Decor du niveau max (regle de LevelLookController)
	for _, item in floor:GetDescendants() do
		local id = item:GetAttribute("LookId")
		if type(id) ~= "string" or item.Parent == nil then
			continue
		end
		local level = if Upgrades.ById[id] then maxLevel(id) else 0
		local min = item:GetAttribute("LookLevel")
		local max = item:GetAttribute("LookMaxLevel")
		local minOk = type(min) ~= "number" or level >= min
		local maxOk = type(max) ~= "number" or level <= max
		if not (minOk and maxOk) then
			item:Destroy()
		end
	end
	for id in Upgrades.ById do
		floor:SetAttribute("Lv_" .. id, maxLevel(id))
	end

	-- 4. Tuiles des panneaux au max
	local boards = floor:FindFirstChild("Boards")
	for _, item in (if boards then boards:GetDescendants() else {}) do
		local id = item:GetAttribute("UpgradeId")
		if not item:IsA("Model") or type(id) ~= "string" or Upgrades.ById[id] == nil then
			continue
		end
		local top = maxLevel(id)
		local texts = {
			Value = Upgrades.FormatValue(id, Upgrades.GetValue(id, top)) .. " MAX",
			Level = "MAX",
			Price = "MAX",
			Robux = "-",
		}
		for name, text in texts do
			local label = item:FindFirstChild(name, true)
			if label and label:IsA("TextLabel") then
				label.Text = text
			end
		end
	end

	-- 5. Usine a construire finie : pads FREE retires
	local setup = floor:FindFirstChild("Setup")
	if setup then
		setup:Destroy()
	end

	-- 6. Arbre au niveau max, textes "Tree full!" + nom (TreeService), fruits au sol (arbre plein)
	local uiFolder = Instance.new("Folder")
	uiFolder.Name = "PreviewUi"
	local tree = floor:FindFirstChild("Tree")
	local root = tree and tree:FindFirstChild("TreeRoot")
	local metrics = nil
	if tree and root and root:IsA("BasePart") then
		local placeholder = tree:FindFirstChild("Body")
		if placeholder then
			placeholder:Destroy()
		end
		local body
		body, metrics = TreeBuilder.Build(n, TreeConfig.LevelsPerFloor)
		body:PivotTo(root.CFrame)
		body.Parent = tree
		local anchor = tree:FindFirstChild("TreeLabelAnchor")
		if anchor and anchor:IsA("BasePart") then
			anchor.CFrame = root.CFrame * CFrame.new(0, metrics.labelHeight, 0)
			local full = WorldLabel.Create(uiFolder, anchor, "TreeFullLabel", {
				maxDistance = Gameplay.LabelMaxDistance + 30,
				size = UDim2.fromScale(10, 2.5),
				alwaysOnTop = true,
			})
			WorldLabel.SetPlainText(full, Gameplay.TreeFullText, Color3.fromRGB(255, 110, 110))
			local levelLabel = WorldLabel.Create(uiFolder, anchor, "TreeLevelLabel", {
				maxDistance = Gameplay.LabelMaxDistance + 30,
				size = UDim2.fromScale(13, 2),
				offset = Vector3.new(0, -Gameplay.TreeLevelLabelDrop, 0),
				alwaysOnTop = true,
			})
			WorldLabel.SetPlainText(
				levelLabel,
				string.format(Gameplay.TreeLevelText, TreeConfig.NameFor(n), TreeConfig.DisplayLevel(n, TreeConfig.LevelsPerFloor))
			)
		end
	end
	local area = tree and tree:FindFirstChild("FruitArea")
	local list = floorFruits(n)
	if area and area:IsA("BasePart") and #list > 0 then
		local fruitFolder = Instance.new("Folder")
		fruitFolder.Name = "PreviewFruits"
		local rng = Random.new(n)
		local half = math.min(area.Size.X, area.Size.Z) / 2
		local inner = if metrics then metrics.trunkClear + 0.5 else 2
		local outer = math.min(half - 0.8, if metrics then metrics.dropRadius else half)
		local count = Gameplay.MaxGroundFruits
		for i = 1, count do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(inner, math.max(inner + 0.5, outer))
			local ground = (area.CFrame * CFrame.new(0, -area.Size.Y / 2, 0)).Position
			local fruit = list[((i - 1) % #list) + 1]
			local ok, model = pcall(FruitModels.CreateFruit, fruit.id, true)
			if ok and model then
				model:PivotTo(
					CFrame.new(ground + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
						* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
				)
				model.Parent = fruitFolder
			end
		end
		fruitFolder.Parent = dynamic
	end

	-- 7. Interface dans le monde : caisses, bols, table a jus, comptoir, argent
	worldUi(floor, n, uiFolder)
	if n == 1 then
		tutorialGuide(floor, uiFolder)
		luckyCash(floor, uiFolder)
	end

	uiFolder.Parent = dynamic
	npcFolder.Parent = dynamic
end

---------------------------------------------------------------------------------------------
-- Construction : la base d'abord (vide), puis un etage a la fois (Studio reste fluide)

local base = baseTemplate:Clone()
base.Name = "_Preview"
base.Archivable = false
base:PivotTo(slot.CFrame * baseTemplate:GetPivot())
base:SetAttribute("Preview", true)
-- Tous les etages achetes : salle du Rebirth ouverte (FloorService.refreshAnnex)
local rebirthGate = base:FindFirstChild("RebirthGate", true)
if rebirthGate then
	rebirthGate:Destroy()
end
local floorsFolder = base:FindFirstChild("Floors") :: Folder
base.Parent = workspace

local parts = 0
for n = 1, FLOORS do
	local floor = FloorAssembly.Build(floorTemplate, n, false, base:GetPivot(), FloorsConfig)
	maxOut(floor, n)
	for _, d in floor:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	floor.Parent = floorsFolder
	task.wait()
end

-- Logo du proprietaire en haut de la tour (Lib/OwnerBadge, le vrai code) : avatar de la personne
-- connectee a Studio
local okId, userId = pcall(function()
	return game:GetService("StudioService"):GetUserId()
end)
if okId and type(userId) == "number" and userId > 0 then
	local okName, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	OwnerBadge.Update(base, { UserId = userId, DisplayName = if okName then name else "Player" } :: any, FLOORS, 0)
end

for _, rig in employeeRigs do
	rig:Destroy()
end
for _, rig in customerRigs do
	rig:Destroy()
end

return `Apercu OK : {FLOORS} etages, {parts} pieces dans les etages. Archivable = {base.Archivable}`
