--!strict
-- FloorTemplate (un etage, phase 1b), morceau 5/7 : pads a acheter (arbre, employes) et decor par niveau. A lancer apres
-- 02a. Recree les dossiers Machines (pads "Upgrade Tree", Fruit Picker, Waiter + pad Robux Speed x10, pad Robux
-- Billboard de la cour) et Looks (decor
-- LookId / LookLevel, ex. panneau FRESH JUICE! de More Customers). Mixeurs : 02c ; panneaux : 02g.
-- Chaque machine : Model <UpgradeId> (attribut UpgradeId) avec
--   Build : les pieces de la machine (fantome bleu clair tant qu'elle n'est pas achetee,
--           UpgradeService : prompt E "Buy $15" + etiquette nom / prix au-dessus)
--   Pad   : employes seulement (achat unique). Style des captures de reference (2026-11-19) :
--           PadBase (dalle epaisse vert fonce a studs = bord), PadTop (dessus vert vif a studs +
--           BillboardGui Tag : Title, Price), PadGlow (4 baguettes neon autour du dessus, sans
--           requete : ne bloquent pas l'appui long), PadZone (marcher dessus = embaucher).
-- Poste d'employe : seulement le pad (Build vide) ; une fois embauche, le pad disparait et le vrai
-- employe R6 apparait (WorkerService). Plus de silhouette en blocs ni de chariot decoratif.
-- Pieces animees par le client (MachineFxController) : attribut Spin (degres / s).
-- Chaque bloc pose OFFSET (decalage de la machine dans l'usine agrandie le 2026-11-19).
-- Doc : docs/systems/ameliorations-employes.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- execute_luau garde les modules deja charges : on charge une copie pour avoir la Config a jour
local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Upgrades = freshRequire(ReplicatedStorage.Shared.Config.Upgrades)

local PAD_BASE = Color3.fromRGB(38, 128, 52) -- bord du pad (dalle)
local PAD_TOP = Color3.fromRGB(100, 204, 78) -- dessus a studs
local PAD_GLOW = Color3.fromRGB(110, 236, 84) -- baguettes neon (sature : le neon pale devient blanc)
local METAL = Color3.fromRGB(186, 192, 200)
local METAL_DARK = Color3.fromRGB(86, 92, 104)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local WHITE = Color3.fromRGB(246, 248, 252)
local GLASS = Color3.fromRGB(200, 236, 250)
local FRUIT_COLORS = {
	Color3.fromRGB(220, 40, 44),
	Color3.fromRGB(255, 150, 30),
	Color3.fromRGB(250, 220, 70),
	Color3.fromRGB(120, 200, 60),
	Color3.fromRGB(150, 70, 200),
}
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)

local STUDS = Enum.SurfaceType.Studs
local SMOOTH_SURF = Enum.SurfaceType.Smooth
local OFFSET = Vector3.zero -- decalage applique a toutes les pieces du bloc en cours

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf + OFFSET
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = STUDS
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.FrontSurface = STUDS
	p.BackSurface = STUDS
	p.LeftSurface = STUDS
	p.RightSurface = STUDS
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function box(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, props: { [string]: any }?): BasePart
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, props)
end

local SMOOTH = {
	TopSurface = SMOOTH_SURF,
	BottomSurface = SMOOTH_SURF,
	FrontSurface = SMOOTH_SURF,
	BackSurface = SMOOTH_SURF,
	LeftSurface = SMOOTH_SURF,
	RightSurface = SMOOTH_SURF,
}
local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in extra do
		t[k] = v
	end
	return t
end
local MARKER = with(SMOOTH, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }
local GLASS_PROPS = with(SMOOTH, { Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false })

local function textLabel(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT_STROKE
	stroke.Thickness = strokePx
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = t
	t.Parent = parent
	return t
end

local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3)
	(target :: any)[face.Name .. "Surface"] = STUDS -- panneaux et textes : studs aussi (style brique)
	local g = Instance.new("SurfaceGui")
	g.Name = "Display" .. face.Name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = target
	textLabel(g, "Text", text, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), color, 3)
end

local model = game:GetService("ServerStorage"):FindFirstChild("FloorTemplate")
assert(model, "Lancer 02a d'abord")
local old = model:FindFirstChild("Machines")
if old then
	old:Destroy()
end
local machines = Instance.new("Folder")
machines.Name = "Machines"
-- Decor qui change avec les niveaux (LookId / LookLevel), hors des machines achetables
local oldLooks = model:FindFirstChild("Looks")
if oldLooks then
	oldLooks:Destroy()
end
local looks = Instance.new("Folder")
looks.Name = "Looks"

-- Pads qui ne sont pas des ameliorations (pas d'UpgradeId) : passes Robux (PassPadService, prix dans
-- Config/Shop.Passes). "Speed x10" (2026-11-20, remplace le pad Auto Sell : apparait a la place du
-- pad du Waiter une fois le Waiter embauche) et "Billboard" (2X Sell Price, dans la cour de l'etage 1).
-- Redessines en violet par Util/RobuxPad ; prix remis a jour par le serveur.
local Shop = freshRequire(ReplicatedStorage.Shared.Config.Shop)
local function passPrice(key: string): number
	for _, pass in Shop.Passes do
		if pass.key == key then
			return pass.price
		end
	end
	error("Pass inconnu " .. key)
end
local PAD_OVERRIDES: { [string]: { machine: string, price: string } } = {
	SpeedBoost = { machine = "Waiter Speed x10", price = `R$ {passPrice("SpeedBoost")}` },
	Billboard = { machine = "Billboard", price = `R$ {passPrice("Billboard")}` },
}

-- Cree le modele d'une machine (+ son pad vert si padX : employes ; sol du pad a floorY).
local function newMachine(id: string, padX: number?, padZ: number?, floorY: number?, withLevel: boolean?): (Model, Model)
	local override = PAD_OVERRIDES[id]
	local upgrade: any = if override then { machine = override.machine, startLevel = 0 } else Upgrades.ById[id]
	assert(upgrade, "Upgrade inconnu " .. id)
	local priceText = if override then override.price else "$" .. Upgrades.GetPrice(id, upgrade.startLevel)
	local m = Instance.new("Model")
	m.Name = id
	if override == nil then
		m:SetAttribute("UpgradeId", id)
	end
	local build = Instance.new("Model")
	build.Name = "Build"
	build.Parent = m
	if padX == nil or padZ == nil or floorY == nil then
		return m, build
	end

	local pad = Instance.new("Model")
	pad.Name = "Pad"
	-- Dalle epaisse (bord fonce) + dessus clair a studs, comme les pads des captures de reference
	box(pad, "PadBase", padX - 3, padX + 3, floorY, floorY + 0.6, padZ - 3, padZ + 3, PAD_BASE, { CastShadow = false })
	local top = box(pad, "PadTop", padX - 2.45, padX + 2.45, floorY + 0.6, floorY + 0.95, padZ - 2.45, padZ + 2.45, PAD_TOP, {
		CastShadow = false,
	})
	-- Baguettes neon sur le bord, autour du dessus (pas de requete : l'appui long vise PadTop)
	local GLOW = with(SMOOTH, { Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
	box(pad, "PadGlow", padX - 2.75, padX + 2.75, floorY + 0.6, floorY + 0.72, padZ - 2.75, padZ - 2.55, PAD_GLOW, GLOW)
	box(pad, "PadGlow", padX - 2.75, padX + 2.75, floorY + 0.6, floorY + 0.72, padZ + 2.55, padZ + 2.75, PAD_GLOW, GLOW)
	box(pad, "PadGlow", padX - 2.75, padX - 2.55, floorY + 0.6, floorY + 0.72, padZ - 2.55, padZ + 2.55, PAD_GLOW, GLOW)
	box(pad, "PadGlow", padX + 2.55, padX + 2.75, floorY + 0.6, floorY + 0.72, padZ - 2.55, padZ + 2.55, PAD_GLOW, GLOW)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(9, 3.6)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	tag.Adornee = top
	if withLevel then
		-- Pad qui reste (Upgrade Tree) : titre, "Lv 3 > 4", prix
		tag.Size = UDim2.fromScale(9, 4.8)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
		textLabel(tag, "Title", upgrade.machine, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.4), Color3.new(1, 1, 1), 3)
		textLabel(tag, "Level", `Lv {upgrade.startLevel} > {upgrade.startLevel + 1}`, UDim2.fromScale(0.15, 0.4), UDim2.fromScale(0.7, 0.26), Color3.fromRGB(255, 244, 170), 3)
		textLabel(tag, "Price", priceText, UDim2.fromScale(0.15, 0.66), UDim2.fromScale(0.7, 0.34), Color3.fromRGB(120, 255, 90), 3)
	else
		textLabel(tag, "Title", upgrade.machine, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55), Color3.new(1, 1, 1), 3)
		textLabel(tag, "Price", priceText, UDim2.fromScale(0.15, 0.55), UDim2.fromScale(0.7, 0.45), Color3.fromRGB(120, 255, 90), 3)
	end
	tag.Parent = top
	box(pad, "PadZone", padX - 3, padX + 3, floorY, floorY + 5, padZ - 3, padZ + 3, Color3.new(1, 0, 0), MARKER)
	pad.PrimaryPart = top
	pad.Parent = m
	return m, build
end

-- (2026-11-19 soir : Sprinkler / Lucky Fertilizer / Juice Cooler / Fast Register / Billboard retires
-- comme machines a acheter : "on comprend pas a quoi ca sert". L'arbre s'ameliore sur un pad, les
-- autres sur des panneaux muraux (02g). Le panneau "FRESH JUICE!" revient en decor qui grandit avec
-- More Customers, voir plus bas.)

-- Pieces de decor d'un niveau (LevelLookController, client) : visibles a partir de `level`.
local function look(p: BasePart, id: string, level: number, maxLevel: number?): BasePart
	p:SetAttribute("LookId", id)
	p:SetAttribute("LookLevel", level)
	if maxLevel then
		p:SetAttribute("LookMaxLevel", maxLevel)
	end
	p.CanCollide = false
	p.CanTouch = false
	return p
end

-- ===== 1. Pad "Upgrade Tree" : devant la jardiniere, aligne avec l'arbre (x 87) =====
-- Se tenir dessus = 1 niveau d'arbre (nouveau fruit + chute plus rapide), puis 1 de plus toutes
-- les PadRepeatSeconds tant qu'on reste dessus (UpgradeService, repeatPad). Etiquette : titre,
-- "Lv 3 > 4", prix.
do
	OFFSET = Vector3.zero
	local tree = newMachine("Tree", 87, 93, 0.5, true)
	tree.Parent = machines
end

-- ===== 2. Decor "More Customers" : panneau FRESH JUICE! dans la cour (cote route) =====
-- Il n'existe pas au niveau 1 ; il apparait au niveau 2 puis s'enrichit (lampes, neon, fruit geant).
do
	OFFSET = Vector3.new(22, 0, 0)
	local id = "CustomerCount"
	local decor = Instance.new("Model")
	decor.Name = "Billboard"
	look(box(decor, "LegA", 72, 73, 0.3, 7.5, 4.6, 5.4, WOOD_DARK), id, 2)
	look(box(decor, "LegB", 83, 84, 0.3, 7.5, 4.6, 5.4, WOOD_DARK), id, 2)
	local board = look(box(decor, "Board", 71, 85, 7.5, 13.5, 4.6, 5.4, Color3.fromRGB(255, 132, 40)), id, 2)
	surfaceText(board, Enum.NormalId.Front, "FRESH JUICE!", Color3.fromRGB(255, 246, 160))
	look(box(decor, "FrameTop", 70.7, 85.3, 13.5, 14, 4.5, 5.5, WHITE), id, 2)
	look(box(decor, "FrameBottom", 70.7, 85.3, 7.1, 7.5, 4.5, 5.5, WHITE), id, 2)
	for _, x in { 74, 82 } do
		look(box(decor, "LampArm", x - 0.15, x + 0.15, 13.9, 14.2, 3, 5, METAL_DARK), id, 3)
		look(box(decor, "Lamp", x - 0.5, x + 0.5, 13.6, 14.3, 2.6, 3.4, Color3.fromRGB(255, 240, 180), with(SMOOTH, { Material = Enum.Material.Neon })), id, 3)
	end
	-- (plus de cadre neon rose depuis le 2026-11-20 : "un neon autour bizarre". Niveau 4 = orange
	-- geante, niveau 5 = pomme geante.)
	look(part(decor, "GiantOrange", Vector3.new(2.6, 2.6, 2.6), CFrame.new(85, 15.4, 5) * CFrame.Angles(0, math.rad(20), 0), FRUIT_COLORS[2]), id, 4)
	look(part(decor, "GiantOrangeLeaf", Vector3.new(1.2, 0.3, 0.7), CFrame.new(85, 16.85, 5) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(80, 170, 60)), id, 4)
	look(part(decor, "GiantApple", Vector3.new(2.2, 2.2, 2.2), CFrame.new(71, 15.2, 5) * CFrame.Angles(0, math.rad(-15), 0), FRUIT_COLORS[1]), id, 5)
	-- Rez-de-chaussee seulement (dans la cour). Aux etages, z 0 -> 14 est le balcon : le panneau s'y
	-- retrouvait au milieu (2026-11-20 : "il doit etre tout en bas").
	local groundOnly = Instance.new("Folder")
	groundOnly.Name = "OnlyGround"
	groundOnly.Parent = looks
	decor.Parent = groundOnly
end

-- ===== 7-9. Employes : seulement le pad vert (nom + prix) a leur poste. =====
-- Plus de silhouette d'employe en blocs ni de chariot de fruits / gobelets decoratifs (2026-11-19
-- soir : "il sert a rien", on les prenait pour de vrais fruits). A l'embauche, le pad disparait et le
-- vrai employe R6 apparait a cote (Markers.<Role>Home, WorkerService).
do
	OFFSET = Vector3.zero
	-- Fruit Picker : devant le verger, cote etagere (il fait l'aller-retour verger -> etagere)
	local picker = newMachine("Collector", 70, 91, 0.5)
	picker.Parent = machines
	-- Blender Operator : plus ici depuis la refonte du mixeur (2026-11-19) : un pad par mixeur,
	-- devant son panneau (Production.Blenders.BlenderN.Operator, 02c).
	-- Waiter + pad violet (2026-11-20, demande : "le pad a cote de la ou on prend les boissons ; d'abord
	-- un pad en argent : on paye l'employe lent qui ramene les boissons au comptoir ; des qu'on
	-- l'achete, le pad se transforme en pad violet"). Le pad violet etait "Auto Sell" ; depuis le
	-- 2026-11-20 (soir) c'est "Speed x10" (demande : "tu fais speed fois 10"). Auto Sell reste
	-- dans la boutique. Les deux pads sont a la MEME place, a cote du pad Take Juices (x 22, z 70),
	-- cote mur (x 12) :
	--   * Machines.Waiter.Pad : pad vert (UpgradeId Waiter), cache par UpgradeService a l'embauche ;
	--   * Machines.SpeedBoost.Pad : pad violet (pass Robux), pieces LookId "Waiter" / LookLevel 1 :
	--     invisible avant l'embauche, puis apparait en fondu + etincelles (LevelLookController).
	--     PadZone sans LookId (marqueur invisible) ; PassPadService l'ignore tant que Lv_Waiter < 1.
	local WAITER_X, WAITER_Z = 12, 70
	local waiter = newMachine("Waiter", WAITER_X, WAITER_Z, 0.5)
	waiter.Parent = machines
	local speed = newMachine("SpeedBoost", WAITER_X, WAITER_Z, 0.5)
	-- Style des pads Robux (2026-11-20) : forme des pads verts, en violet (Util/RobuxPad)
	local RobuxPad = freshRequire(ReplicatedStorage.Shared.Util.RobuxPad)
	local speedPad = speed:FindFirstChild("Pad") :: Model
	RobuxPad.Style(speedPad, "Waiter Speed x10", passPrice("SpeedBoost"))
	for _, item in speedPad:GetChildren() do
		if item:IsA("BasePart") and item.Name ~= "PadZone" then
			-- Pas look() : il enleverait la collision (on doit pouvoir marcher sur le pad)
			item:SetAttribute("LookId", "Waiter")
			item:SetAttribute("LookLevel", 1)
		end
	end
	speed.Parent = machines

	-- Pad Robux "Billboard" (2026-11-20, demande : "un pad dehors qui s'appelle Billboard, 2X Sell
	-- Price", capture d'un autre jeu adaptee a notre style) : dans la cour de l'etage 1, a cote du
	-- panneau FRESH JUICE! (Looks.Billboard, x 93 -> 107), entre la place et ce panneau. Sol de la
	-- cour : herbe a 0.3. Toujours visible. Etage 1 seulement (OnlyGround : aux etages, z 0 -> 14 est
	-- le balcon).
	local billboard = newMachine("Billboard", 89.5, 8.5, 0.3)
	RobuxPad.Style(billboard:FindFirstChild("Pad") :: Model, "Billboard", passPrice("Billboard"), "2X Sell Price")
	local groundOnly = Instance.new("Folder")
	groundOnly.Name = "OnlyGround"
	groundOnly.Parent = machines
	billboard.Parent = groundOnly
end

machines.Parent = model
looks.Parent = model
return "Machines OK: " .. #machines:GetChildren() .. " machines, " .. #machines:GetDescendants() .. " objets"
