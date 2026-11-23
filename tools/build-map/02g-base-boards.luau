--!strict
-- FloorTemplate (un etage, phase 1b), morceau 7/7 : panneaux d'ameliorations (bois + tuiles colorees). A lancer apres 02a.
-- Recree le dossier Boards. Une tuile par amelioration a niveaux :
--   Boards.<Board>.<UpgradeId> (Model, attribut UpgradeId)
--     Tile        : fond colore + SurfaceGui "Display" dessinee par Shared/Util/UpgradeTile (Title,
--                   Icon + fleche verte, Value "actuel -> suivant", bouton vert Price, violet Robux)
--     BuyButton   : Part invisible + ClickDetector devant le bouton vert (CLIQUER = acheter un niveau)
--     RobuxButton : Part invisible + ClickDetector devant le bouton violet - phase 3
-- Les textes Value / Price / Robux sont remis a jour par UpgradeService pour le proprietaire.
-- Style (2026-11-20, captures de l'utilisateur) : tuiles larges, contour noir, en-tete avec icone.
-- Panneaux (2026-11-19 soir, demande : "un panneau a cote qu'on clique et ca ameliore") :
--   ConveyorBoard   : mur du fond, a cote de la boite du tapis (Conveyor Speed) ;
--   JuiceTableBoard : mur de droite (vu de la route), a cote de la table a jus (Juice Table) ;
--   SalesBoard      : facade, a droite du comptoir vu de l'interieur (Faster / More Customers) ;
--   PickerBoard     : mur du fond, partie pleine (x 62 -> 76) entre l'etagere a fruits et l'arbre,
--                     la ou travaille le Fruit Picker (Picker Speed, et dessous Picker Hands =
--                     fruits portes, 2026-11-20) ;
--   BlenderSign1..4 : suspendu au-dessus de chaque mixeur (Blender N, 5 niveaux), cache tant que
--                     le mixeur est verrouille (attribut HideWhenLocked, LevelLookController).
-- Depuis le 2026-11-21 (usine a construire) : Conveyor, Juice Table, Customers et Fruit Picker sont
-- aussi HideWhenLocked : caches tant que leur etape FREE n'est pas faite (tuile Unbuilt, profil
-- neuf) ou, pour Fruit Picker, tant que le Fruit Picker n'est pas embauche (tuiles Locked).
-- (Avant : un seul panneau "Juice" avec Bigger Bowl, et des machines qu'on ne comprenait pas :
-- Sprinkler, Lucky Fertilizer, Juice Cooler, Fast Register, Billboard.)
-- Doc : docs/systems/ameliorations-employes.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Upgrades = freshRequire(ReplicatedStorage.Shared.Config.Upgrades)
local Icons = freshRequire(ReplicatedStorage.Shared.Config.Icons)
local UpgradeTile = freshRequire(ReplicatedStorage.Shared.Util.UpgradeTile)

local WOOD = Color3.fromRGB(196, 116, 56)
local WOOD_DARK = Color3.fromRGB(132, 74, 36)
local METAL_DARK = Color3.fromRGB(86, 92, 104)
local PURPLE = Color3.fromRGB(176, 60, 236)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)
local TILE_W, TILE_H, GAP, MARGIN, TITLE_H = 7.2, 4, 0.35, 0.45, 1.7
local BEAM_Y = 34.6 -- dessous des poutres (fils des panneaux suspendus)

local STUDS = Enum.SurfaceType.Studs
-- Tuiles et boutons d'amelioration : surface Weld (traits en X), demandee par l'utilisateur le
-- 2026-11-19 ; le cadre en bois garde ses studs.
local WELD = Enum.SurfaceType.Weld
local WELD_ALL = { TopSurface = WELD, BottomSurface = WELD, FrontSurface = WELD, BackSurface = WELD, LeftSurface = WELD, RightSurface = WELD }
local function weld(extra: { [string]: any }): { [string]: any }
	local t: { [string]: any } = table.clone(WELD_ALL)
	for k, v in extra do
		t[k] = v
	end
	return t
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = STUDS
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.FrontSurface = STUDS -- face avec le texte : studs aussi (style brique)
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

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = TEXT_STROKE
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = value
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	stroke(t, strokePx)
	t.Parent = parent
	return t
end

local function frontGui(target: BasePart): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "Display"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 50
	g.LightInfluence = 0
	g.Parent = target
	return g
end

local model = game:GetService("ServerStorage"):FindFirstChild("FloorTemplate")
assert(model, "Lancer 02a d'abord")
local old = model:FindFirstChild("Boards")
if old then
	old:Destroy()
end
local boards = Instance.new("Folder")
boards.Name = "Boards"

local function valueText(id: string, level: number): string
	if level < Upgrades.BuiltAt(id) then
		return "NEW!"
	end
	return Upgrades.FormatValue(id, Upgrades.GetValue(id, level)) .. UpgradeTile.ARROW .. Upgrades.FormatValue(id, Upgrades.GetValue(id, level + 1))
end

type BoardOptions = {
	posts: boolean?, -- pieds sous le panneau (panneau pose au sol)
	hang: boolean?, -- fils jusqu'aux poutres (panneau suspendu)
	noTitle: boolean?, -- pas de bandeau titre (la tuile a deja son titre)
	hideWhenLocked: boolean?, -- cache tant que l'amelioration est verrouillee (LevelLookController)
}

-- Panneau : face avant (-Z local) vers `facing`. `bottom` = point sous le centre du panneau (le
-- bas du panneau est a bottom.Y + liftY).
local function board(name: string, title: string, ids: { string }, cols: number, bottom: Vector3, facing: Vector3, liftY: number, options: BoardOptions?)
	local opts: BoardOptions = options or {}
	local m = Instance.new("Model")
	m.Name = name
	if opts.hideWhenLocked then
		m:SetAttribute("HideWhenLocked", true)
	end
	local titleH = if opts.noTitle then 0 else TITLE_H
	local rows = math.ceil(#ids / cols)
	local w = cols * TILE_W + (cols - 1) * GAP + 2 * MARGIN
	local h = rows * TILE_H + (rows - 1) * GAP + 2 * MARGIN + titleH
	local base = CFrame.lookAt(bottom, bottom + facing)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, liftY + y, z)
	end
	local back = part(m, "Back", Vector3.new(w, h, 0.5), at(0, h / 2, 0), WOOD)
	part(m, "FrameTop", Vector3.new(w + 0.4, 0.4, 0.7), at(0, h + 0.1, -0.05), WOOD_DARK)
	part(m, "FrameBottom", Vector3.new(w + 0.4, 0.4, 0.7), at(0, -0.1, -0.05), WOOD_DARK)
	part(m, "FrameLeft", Vector3.new(0.4, h - 0.2, 0.74), at(-w / 2 - 0.05, h / 2, -0.06), WOOD_DARK)
	part(m, "FrameRight", Vector3.new(0.4, h - 0.2, 0.74), at(w / 2 + 0.05, h / 2, -0.06), WOOD_DARK)
	if not opts.noTitle then
		-- Titre en gros (blanc, contour noir) + icone de la premiere tuile a droite (comme les captures)
		local titlePart = part(m, "Title", Vector3.new(w - 1, TITLE_H - 0.2, 0.1), at(0, h - MARGIN - (TITLE_H - 0.2) / 2 + 0.05, -0.3), WOOD, { CanCollide = false })
		local titleGui = frontGui(titlePart)
		text(titleGui, "Text", title, UDim2.fromScale(0.03, 0.02), UDim2.new(1, -titleGui.PixelsPerStud * (TITLE_H + 0.2), 0.96, 0), 4)
		local first = Upgrades.ById[ids[1]]
		local headIcon = Instance.new("ImageLabel")
		headIcon.Name = "Icon"
		headIcon.BackgroundTransparency = 1
		headIcon.AnchorPoint = Vector2.new(1, 0)
		headIcon.Position = UDim2.fromScale(0.99, 0)
		headIcon.Size = UDim2.fromScale(1, 1)
		headIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		headIcon.ScaleType = Enum.ScaleType.Fit
		headIcon.Image = if first then Icons[first.icon] or "" else ""
		headIcon.Parent = titleGui
	end
	if opts.posts then
		-- Pieds droits SOUS le panneau (dans son epaisseur, plus decales derriere : 2026-11-19 soir),
		-- poses sur un petit socle. Le pied s'arrete juste sous le cadre du bas.
		local legTop = liftY - 0.3
		for _, sx in { -w / 2 + 0.7, w / 2 - 0.7 } do
			part(m, "Post", Vector3.new(0.8, legTop, 0.6), base * CFrame.new(sx, legTop / 2, -0.05), WOOD_DARK)
			part(m, "Foot", Vector3.new(1.4, 0.3, 2), base * CFrame.new(sx, 0.15, -0.05), WOOD_DARK)
		end
	end
	if opts.hang then
		-- Deux fils du haut du cadre jusqu'aux poutres (comme les panneaux de zone)
		local top = liftY + h + 0.3
		local length = BEAM_Y - bottom.Y - top
		for _, sx in { -w / 2 + 0.6, w / 2 - 0.6 } do
			part(m, "Wire", Vector3.new(0.15, length, 0.15), base * CFrame.new(sx, top + length / 2, 0), METAL_DARK, {
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
			})
		end
	end
	for i, id in ids do
		local upgrade = Upgrades.ById[id]
		assert(upgrade, "Upgrade inconnu " .. id)
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		-- Vu de face, +X local est a GAUCHE : on place les colonnes de droite a gauche en X local.
		local cx = w / 2 - MARGIN - TILE_W / 2 - col * (TILE_W + GAP)
		local cy = h - MARGIN - titleH - TILE_H / 2 - row * (TILE_H + GAP)
		local tileModel = Instance.new("Model")
		tileModel.Name = id
		tileModel:SetAttribute("UpgradeId", id)
		local tile = part(tileModel, "Tile", Vector3.new(TILE_W, TILE_H, 0.2), at(cx, cy, -0.35), upgrade.color, weld({ CanCollide = false }))
		UpgradeTile.Build(tile, Enum.NormalId.Front, {
			title = upgrade.title,
			color = upgrade.color,
			icon = Icons[upgrade.icon],
			value = valueText(id, upgrade.startLevel),
			price = "$" .. Upgrades.GetPrice(id, upgrade.startLevel),
			robux = tostring(Upgrades.GetRobuxPrice(id, upgrade.startLevel)),
			robuxIcon = Icons.Robux,
		})
		-- Boutons : Part invisible + ClickDetector juste devant chaque bouton dessine (BUY_RECT,
		-- ROBUX_RECT). On clique le BOUTON (pas toute la tuile) ; seul le bouton s'anime (BoardFxController).
		for _, button in { { name = "BuyButton", rect = UpgradeTile.BUY_RECT }, { name = "RobuxButton", rect = UpgradeTile.ROBUX_RECT } } do
			local r = button.rect
			local bx = cx + TILE_W / 2 - (r.x + r.w / 2) * TILE_W
			local by = cy + TILE_H / 2 - (r.y + r.h / 2) * TILE_H
			local p = part(tileModel, button.name, Vector3.new(r.w * TILE_W, r.h * TILE_H, 0.1), at(bx, by, -0.6), PURPLE, weld({
				CanCollide = false,
				CanTouch = false,
				CastShadow = false,
				Transparency = 1,
			}))
			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = 36
			click.Parent = p
		end
		tileModel.PrimaryPart = tile
		tileModel.Parent = m
	end
	m.PrimaryPart = back
	m.Parent = boards
end

-- Mur du fond (face interieure z = 135), a droite de la boite du tapis (x 23.4 -> 28.6) : vitesse du tapis
board("ConveyorBoard", "Conveyor", { "ConveyorSpeed" }, 1, Vector3.new(15, 0.5, 134.7), Vector3.new(0, 0, -1), 3, { hideWhenLocked = true })
-- Mur de droite vu de la route (face interieure x = 1), a cote de la table a jus : capacite de la table
board("JuiceTableBoard", "Juice Table", { "JuiceLimit" }, 1, Vector3.new(1.3, 0.5, 78.5), Vector3.new(1, 0, 0), 3, { hideWhenLocked = true })
-- Facade (face interieure z = 15), entre le cadre de fenetre (x 18.5) et la fenetre du comptoir (x 47.5 -> 80) : clients
board("SalesBoard", "Customers", { "CustomerSpeed", "CustomerCount" }, 2, Vector3.new(38.8, 0.5, 15.3), Vector3.new(0, 0, 1), 3, { hideWhenLocked = true })
-- Mur du fond (face interieure z = 135), partie pleine x 62 -> 76 (fenetres a gauche et a droite),
-- derriere la zone du Fruit Picker : vitesse (haut) et fruits portes (bas) du Fruit Picker. Seul mur present a tous les etages
-- pres de son pad (le cote de l'escalier change d'un etage a l'autre : voie A / B).
board("PickerBoard", "Fruit Picker", { "PickerSpeed", "PickerCarry" }, 1, Vector3.new(67, 0.5, 134.7), Vector3.new(0, 0, -1), 3, { hideWhenLocked = true })
-- Un panneau suspendu au-dessus de chaque mixeur (devant le bol, au-dessus du rebord a y 15)
for n, x in { 12.5, 23, 33.5, 44 } do
	board("BlenderSign" .. n, "", { "Blender" .. n }, 1, Vector3.new(x, 0.5, 90.3), Vector3.new(0, 0, -1), 14.8, {
		hang = true,
		noTitle = true,
		hideWhenLocked = true,
	})
end

boards.Parent = model
return "Boards OK: " .. #boards:GetDescendants()
