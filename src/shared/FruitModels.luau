--!strict
-- Modeles des fruits et des gobelets de jus (aucune attente, rien de parente).
-- Fruits : clone du fruit voxel ReplicatedStorage.FruitAssets.<FruitId> (une seule UnionOperation,
-- construite dans Studio par tools/build-assets/fruits-voxel.luau) + effets de rarete (etincelles,
-- feu, lueur...). Si le fruit voxel manque : ancienne boule (queue + feuille).
-- Pivot = centre-bas du modele : l'appelant fait model:PivotTo(CFrame.new(pointAuSol)).
-- Doc : docs/systems/fruits.md, docs/systems/chaine-production.md

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fruits = require(script.Parent.Config.Fruits)

local FruitModels = {}

FruitModels.RarityFxTag = "RarityFx" -- tag CollectionService de l'Attachment des effets de rarete

FruitModels.FruitSize = 1.9 -- hauteur totale d'un fruit voxel (corps + queue ; 1.5 avant le 2026-11-19 soir)
FruitModels.CupHeight = 1.6 -- hauteur totale d'un gobelet (couvercle + paille)
FruitModels.CupFootprint = 0.9 -- largeur d'un gobelet (grille de rangement)

-- Couleurs naturelles du corps pour les 30 premiers fruits ; les autres utilisent juiceColor.
local BODY_COLORS: { [string]: Color3 } = {
	Apple = Color3.fromRGB(225, 35, 35),
	Orange = Color3.fromRGB(255, 140, 15),
	Banana = Color3.fromRGB(255, 225, 30),
	Pear = Color3.fromRGB(190, 215, 70),
	Lemon = Color3.fromRGB(255, 240, 40),
	Lime = Color3.fromRGB(110, 210, 30),
	Grape = Color3.fromRGB(125, 45, 170),
	Plum = Color3.fromRGB(115, 35, 115),
	Peach = Color3.fromRGB(255, 170, 120),
	Apricot = Color3.fromRGB(255, 165, 50),
	Strawberry = Color3.fromRGB(240, 40, 60),
	Cherry = Color3.fromRGB(180, 10, 40),
	Blueberry = Color3.fromRGB(60, 70, 200),
	Raspberry = Color3.fromRGB(215, 30, 90),
	Kiwi = Color3.fromRGB(135, 110, 60),
	Pineapple = Color3.fromRGB(250, 200, 40),
	Mango = Color3.fromRGB(255, 160, 30),
	Coconut = Color3.fromRGB(125, 80, 45),
	Melon = Color3.fromRGB(170, 215, 120),
	Watermelon = Color3.fromRGB(40, 150, 60),
	DragonFruit = Color3.fromRGB(255, 70, 160),
	StarFruit = Color3.fromRGB(255, 215, 50),
	Lychee = Color3.fromRGB(240, 110, 110),
	PassionFruit = Color3.fromRGB(140, 60, 160),
	Papaya = Color3.fromRGB(255, 150, 50),
	Pomegranate = Color3.fromRGB(190, 25, 45),
	Guava = Color3.fromRGB(150, 205, 90),
	Fig = Color3.fromRGB(110, 50, 100),
	Rambutan = Color3.fromRGB(230, 40, 50),
	Durian = Color3.fromRGB(150, 170, 60),
}

-- Exceptions de feuille (taille ; la couleur reste verte).
local LEAF_SIZES: { [string]: Vector3 } = {
	Pineapple = Vector3.new(0.8, 0.15, 0.55),
}

local STEM_COLOR = Color3.fromRGB(110, 70, 35)
local LEAF_COLOR = Color3.fromRGB(60, 170, 50)
local CUP_COLOR = Color3.fromRGB(245, 242, 235)
local STRAW_COLOR = Color3.fromRGB(255, 70, 140)

local function getFruit(fruitId: string): Fruits.Fruit
	local fruit = Fruits.ById[fruitId]
	if fruit == nil then
		error(`FruitModels : fruit inconnu "{fruitId}"`, 3)
	end
	return fruit
end

-- Cree une piece blocky ; cframe = position relative a l'origine (centre-bas du modele).
local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	anchored: boolean,
	_small: boolean -- (garde pour les appels ; plus d'ombre sur aucun fruit)
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Anchored = anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = not anchored
	part.CastShadow = false -- pas d'ombre sur les fruits ni les petits objets (demande utilisateur)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.LeftSurface = Enum.SurfaceType.Smooth
	part.RightSurface = Enum.SurfaceType.Smooth
	part.FrontSurface = Enum.SurfaceType.Smooth
	part.BackSurface = Enum.SurfaceType.Smooth
	return part
end

-- Assemble le modele : parente les pieces, soude les secondaires si non ancre, fixe le pivot au centre-bas.
local function assemble(fruitId: string, primary: Part, others: { Part }, anchored: boolean): Model
	local model = Instance.new("Model")
	model.Name = fruitId
	model:SetAttribute("FruitId", fruitId)
	-- StreamingEnabled : sans Atomic, les pieces arrivent une par une chez le client ; un effet qui
	-- deplace le modele (PivotTo) avant la fin laissait les pieces en retard a 10-16 studs
	-- ("morceaux de jus par terre", 2026-11-19). Atomic = le modele arrive entier, d'un coup.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	primary.Parent = model
	for _, part in others do
		if not anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = primary
			weld.Parent = part
		end
		part.Parent = model
	end
	model.PrimaryPart = primary
	-- Le pivot suit la PrimaryPart : on le descend au bas du modele (origine = centre-bas).
	primary.PivotOffset = CFrame.new(0, -primary.Size.Y / 2, 0)
	model.WorldPivot = CFrame.new()
	return model
end

-- Fruit voxel construit dans Studio (nil s'il manque).
local function getTemplate(fruitId: string): BasePart?
	local folder = ReplicatedStorage:FindFirstChild("FruitAssets")
	local template = folder and folder:FindFirstChild(fruitId)
	return if template and template:IsA("BasePart") then template else nil
end

function FruitModels.GetBodyColor(fruitId: string): Color3
	local fruit = getFruit(fruitId)
	local template = getTemplate(fruitId)
	local color = template and template:GetAttribute("BodyColor")
	if typeof(color) == "Color3" then
		return color
	end
	return BODY_COLORS[fruitId] or fruit.juiceColor
end

------------------------------------------------------------------------------------------------
-- Effets de rarete (attaches au fruit : visibles au sol, dans les mains, sur le tapis...)
------------------------------------------------------------------------------------------------

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
-- Halo doux (teste le 2026-11-19 : forcefield_glow ne se voyait pas en plein jour)
local GLOW = "rbxasset://textures/particles/explosion01_core_main.dds"

local function seq(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

local RAINBOW = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(90, 230, 90),
	Color3.fromRGB(60, 170, 255),
	Color3.fromRGB(190, 90, 255),
}

type FxDef = {
	sparkle: { Color3 }?, -- etincelles
	rate: number?,
	size: number?,
	fire: { Color3 }?, -- petites flammes qui montent
	glow: { Color3 }?, -- halo doux derriere le fruit
	light: Color3?, -- petite lumiere (raretes hautes seulement)
	flicker: boolean?, -- etincelles tres courtes (Glitched)
}

-- Index = rarete (1 Common .. 10 Infinity). Common : rien.
local RARITY_FX: { [number]: FxDef } = {
	[2] = { sparkle = { Color3.fromRGB(120, 255, 120) }, rate = 2.5, size = 0.6 },
	[3] = { sparkle = { Color3.fromRGB(110, 190, 255) }, rate = 3.5, size = 0.7, glow = { Color3.fromRGB(60, 140, 255) } },
	[4] = { sparkle = { Color3.fromRGB(205, 130, 255) }, rate = 5, size = 0.8, glow = { Color3.fromRGB(170, 70, 245) } },
	[5] = {
		sparkle = { Color3.fromRGB(255, 230, 120) },
		rate = 6,
		size = 0.9,
		glow = { Color3.fromRGB(255, 200, 40) },
		light = Color3.fromRGB(255, 205, 80),
	},
	[6] = {
		fire = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 90, 30), Color3.fromRGB(200, 20, 20) },
		glow = { Color3.fromRGB(245, 50, 40) },
		light = Color3.fromRGB(255, 100, 60),
	},
	[7] = {
		sparkle = { Color3.fromRGB(255, 255, 255) },
		rate = 6,
		size = 0.9,
		glow = { Color3.fromRGB(255, 250, 225) },
		light = Color3.fromRGB(255, 250, 230),
	},
	[8] = {
		sparkle = { Color3.fromRGB(150, 235, 255), Color3.fromRGB(255, 255, 255) },
		rate = 7,
		size = 0.85,
		glow = { Color3.fromRGB(120, 200, 255) },
		light = Color3.fromRGB(150, 225, 255),
	},
	[9] = {
		sparkle = { Color3.fromRGB(255, 40, 220), Color3.fromRGB(40, 255, 240), Color3.fromRGB(80, 255, 90) },
		rate = 16,
		size = 0.75,
		flicker = true,
		glow = { Color3.fromRGB(255, 40, 220), Color3.fromRGB(40, 255, 240) },
		light = Color3.fromRGB(255, 60, 220),
	},
	[10] = { sparkle = RAINBOW, rate = 9, size = 1, glow = RAINBOW, light = Color3.fromRGB(255, 200, 230) },
}

local function emitter(attachment: Attachment, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = attachment
	return e
end

local function addRarityFx(model: Model, body: BasePart, rarity: number)
	local fx = RARITY_FX[rarity]
	if fx == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RarityFx"
	-- Tag : WorldDetailController coupe ces effets loin de la camera (perf mobile, 2026-11-27).
	-- Le tag suit les Clone() et la replication.
	CollectionService:AddTag(attachment, FruitModels.RarityFxTag)
	-- centre du fruit (le pivot est en bas)
	attachment.CFrame = body.PivotOffset * CFrame.new(0, FruitModels.FruitSize * 0.4, 0)
	attachment.Parent = body
	model:SetAttribute("Rarity", rarity)

	if fx.sparkle then
		local e = emitter(attachment, "Sparkles")
		e.Texture = SPARKLE
		e.Color = seq(fx.sparkle)
		local size = fx.size or 0.4
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, size), NumberSequenceKeypoint.new(1, 0) })
		e.Rate = fx.rate or 2
		e.Lifetime = if fx.flicker then NumberRange.new(0.08, 0.2) else NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(0.6, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		-- visibles en plein jour : plus lumineuses, dessinees devant le fruit
		e.Brightness = 3
		e.LightEmission = 0.6
		e.ZOffset = 0.8
	end
	if fx.fire then
		local e = emitter(attachment, "Fire")
		e.Texture = FIRE
		e.Color = seq(fx.fire)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Brightness = 4
		e.LightEmission = 0.2
		e.ZOffset = 0.6
		e.Rate = 12
		e.Lifetime = NumberRange.new(0.4, 0.7)
		e.Speed = NumberRange.new(1, 2)
		e.Acceleration = Vector3.new(0, 2, 0)
		e.SpreadAngle = Vector2.new(25, 25)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rotation = NumberRange.new(0, 360)
	end
	if fx.glow then
		local e = emitter(attachment, "Glow")
		e.Texture = GLOW
		e.Color = seq(fx.glow)
		e.Size = NumberSequence.new(3.2)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		e.Brightness = 2
		e.LightEmission = 0.3
		e.Rate = 2.5
		e.Lifetime = NumberRange.new(0.8, 1.2)
		e.Speed = NumberRange.new(0, 0)
		e.LockedToPart = true
		e.ZOffset = -0.5
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-30, 30)
	end
	if fx.light then
		local light = Instance.new("PointLight")
		light.Name = "RarityLight"
		light.Color = fx.light
		light.Brightness = 1.2
		light.Range = 6
		light.Shadows = false
		light.Parent = attachment
	end
end

-- Ancien fruit rond (boule, queue, feuille) : seulement si le fruit voxel manque.
local function createBallFruit(fruitId: string, anchored: boolean): Model
	local body = makePart(
		"Body",
		Vector3.new(1.2, 1.2, 1.2),
		CFrame.new(0, 0.6, 0),
		FruitModels.GetBodyColor(fruitId),
		anchored,
		false
	)
	body.Shape = Enum.PartType.Ball
	body.Material = Enum.Material.SmoothPlastic
	body.Reflectance = 0.05

	-- Petit creux sombre en haut (comme une pomme) sous la queue
	local dimple = makePart(
		"Dimple",
		Vector3.new(0.34, 0.34, 0.34),
		CFrame.new(0, 1.12, 0),
		FruitModels.GetBodyColor(fruitId):Lerp(Color3.new(0, 0, 0), 0.35),
		anchored,
		true
	)
	dimple.Shape = Enum.PartType.Ball

	local stem = makePart(
		"Stem",
		Vector3.new(0.14, 0.42, 0.14),
		CFrame.new(0.02, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-8)),
		STEM_COLOR,
		anchored,
		true
	)

	local leafSize = LEAF_SIZES[fruitId] or Vector3.new(0.5, 0.08, 0.28)
	local leaf = makePart(
		"Leaf",
		leafSize,
		CFrame.new(0.28, 1.36, 0.04) * CFrame.Angles(0, math.rad(15), math.rad(-22)),
		LEAF_COLOR,
		anchored,
		true
	)
	leaf.Material = Enum.Material.SmoothPlastic

	return assemble(fruitId, body, { dimple, stem, leaf }, anchored)
end

-- Fruit voxel (une seule piece) + effets de rarete. Meme signature qu'avant (MachineFx, NpcRig...).
function FruitModels.CreateFruit(fruitId: string, anchored: boolean): Model
	local fruit = getFruit(fruitId)
	local template = getTemplate(fruitId)
	local model: Model
	local body: BasePart
	if template then
		body = template:Clone()
		body.Name = "Body"
		body.Anchored = anchored
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.Massless = not anchored
		body.CastShadow = false
		model = Instance.new("Model")
		model.Name = fruitId
		model:SetAttribute("FruitId", fruitId)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- voir assemble()
		body.Parent = model
		model.PrimaryPart = body -- pivot = celui du modele voxel (centre-bas)
	else
		model = createBallFruit(fruitId, anchored)
		body = model.PrimaryPart :: BasePart
	end
	addRarityFx(model, body, fruit.rarity)
	return model
end

-- Met des studs (bosses) sur les 4 cotes ; dessus / dessous au choix.
local function studSides(part: Part, top: Enum.SurfaceType?, bottom: Enum.SurfaceType?)
	local studs = Enum.SurfaceType.Studs
	part.Material = Enum.Material.Plastic
	part.FrontSurface = studs
	part.BackSurface = studs
	part.LeftSurface = studs
	part.RightSurface = studs
	part.TopSurface = top or Enum.SurfaceType.Smooth
	part.BottomSurface = bottom or Enum.SurfaceType.Smooth
end

-- Gobelet "brique a studs" (2026-11-19) : pied blanc, 2 etages de jus a studs (le haut plus large :
-- forme evasee), bord et couvercle blancs, paille coudee, et le fruit voxel en miniature sur le
-- couvercle (on reconnait le jus de loin). Largeur 1.04 max (grille JuiceCupSpacing 1.1, mains
-- JuiceCupSpacing), hauteur CupHeight 1.6 : rien ne depasse dans le gobelet du dessus.
-- Faces : aucune face commune visible (etages de largeurs differentes, pas de z-fighting).
local MINI_FRUIT_HEIGHT = 0.3

function FruitModels.CreateCup(fruitId: string, anchored: boolean): Model
	local fruit = getFruit(fruitId)
	local juiceColor = fruit.juiceColor

	-- Pied blanc (y 0 -> 0.14)
	local foot = makePart("Foot", Vector3.new(0.78, 0.14, 0.78), CFrame.new(0, 0.07, 0), CUP_COLOR, anchored, true)
	studSides(foot, nil, Enum.SurfaceType.Inlet)

	-- Jus, etage bas (y 0.14 -> 0.6)
	local low = makePart("JuiceLow", Vector3.new(0.88, 0.46, 0.88), CFrame.new(0, 0.37, 0), juiceColor, anchored, true)
	studSides(low)

	-- Jus, etage haut (y 0.6 -> 1.1) : piece principale
	local cup = makePart("Cup", Vector3.new(1, 0.5, 1), CFrame.new(0, 0.85, 0), juiceColor, anchored, false)
	studSides(cup)

	-- Bord blanc (y 1.1 -> 1.24) et couvercle (y 1.24 -> 1.3)
	local rim = makePart("Rim", Vector3.new(1.04, 0.14, 1.04), CFrame.new(0, 1.17, 0), CUP_COLOR, anchored, true)
	studSides(rim)
	local lid = makePart("Lid", Vector3.new(0.86, 0.06, 0.86), CFrame.new(0, 1.27, 0), CUP_COLOR, anchored, true)

	-- Paille coudee (sommet a 1.6 = CupHeight)
	local straw = makePart("Straw", Vector3.new(0.11, 0.33, 0.11), CFrame.new(0.27, 1.38, -0.27), STRAW_COLOR, anchored, true)
	local strawTip =
		makePart("StrawTip", Vector3.new(0.11, 0.11, 0.26), CFrame.new(0.27, 1.545, -0.345), STRAW_COLOR, anchored, true)

	local model = assemble(fruitId, cup, { foot, low, rim, lid, straw, strawTip }, anchored)
	cup.PivotOffset = CFrame.new(0, -0.85, 0) -- pivot au sol (centre-bas)

	-- Mini fruit voxel sur le couvercle (y 1.3 -> 1.6) ; boule de la couleur du fruit s'il manque.
	local template = getTemplate(fruitId)
	local mini: BasePart
	if template then
		mini = template:Clone()
		mini.Size *= MINI_FRUIT_HEIGHT / mini.Size.Y
		mini.CanCollide = false
		mini.CanQuery = false
		mini.CanTouch = false
		mini.CastShadow = false
	else
		local ball = makePart("MiniFruit", Vector3.one * MINI_FRUIT_HEIGHT, CFrame.new(), FruitModels.GetBodyColor(fruitId), anchored, true)
		ball.Shape = Enum.PartType.Ball
		mini = ball
	end
	mini.Name = "MiniFruit"
	mini.Anchored = anchored
	mini.Massless = not anchored
	mini.CFrame = cup.CFrame
		* CFrame.new(-0.12, 1.3 + mini.Size.Y / 2 - 0.85, 0.12)
		* CFrame.Angles(0, math.rad(30), 0)
	if not anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = mini
		weld.Part1 = cup
		weld.Parent = mini
	end
	mini.Parent = model
	return model
end

return FruitModels
