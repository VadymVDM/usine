--!strict
-- Fleche jaune 3D du tutoriel, style "simulateur Roblox" (2026-11-27, demande : "rends-la plus
-- qualitative, toujours dans le style de Roblox").
-- Une seule fleche plate et epaisse (dans le plan YZ, epaisseur sur X) qui pointe vers le bas :
--   * contour sombre en pieces (plus large, un peu moins epais : il depasse tout autour) ;
--   * corps orange (les tranches), face jaune claire en retrait (effet biseau), bout du manche arrondi ;
--   * reflet blanc sur le manche.
-- Pointe en y = -0.5 (pivot en 0). Pas de Neon, pas d'ombre, rien de cliquable.
-- Pose(model, cframe, scale) : place la fleche (son +X vers la camera) et l'ecrase / l'etire depuis
-- la pointe (rebond "squash & stretch"). Utilisee par TutorialController et tools/build-map/preview-factory.
-- Doc : docs/systems/tutoriel.md

local TutorialArrow = {}

local OUTLINE = Color3.fromRGB(20, 16, 28)
local SIDE = Color3.fromRGB(255, 140, 0)
local FACE = Color3.fromRGB(255, 226, 50)
local SHINE = Color3.fromRGB(255, 248, 200)

local TIP = Vector3.new(0, -0.5, 0)
TutorialArrow.Tip = TIP

type Piece = { part: BasePart, offset: CFrame, size: Vector3 }
local pieces: { [Model]: { Piece } } = setmetatable({}, { __mode = "k" }) :: any

local function decor(p: BasePart, color: Color3)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function add(parent: Instance, list: { Piece }, part: BasePart, color: Color3, size: Vector3, offset: CFrame)
	decor(part, color)
	part.Size = size
	part.CFrame = offset
	part.Parent = parent
	table.insert(list, { part = part, offset = offset, size = size })
end

-- Triangle (pointe en bas, au centre) : haut a yTop, demi-largeur w, pointe a yTip ; deux coins
-- retournes en miroir (meme montage que l'ancienne fleche)
local function triangle(parent: Instance, list: { Piece }, name: string, color: Color3, depth: number, yTop: number, yTip: number, w: number)
	local h = yTop - yTip
	local y = (yTop + yTip) / 2
	local halves = {
		CFrame.new(0, y, -w / 2) * CFrame.Angles(0, 0, math.pi),
		CFrame.new(0, y, w / 2) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.pi),
	}
	for i, cf in halves do
		local wedge = Instance.new("WedgePart")
		wedge.Name = `{name}{i}`
		add(parent, list, wedge, color, Vector3.new(depth, h, w), cf)
	end
end

-- Meme triangle agrandi (d > 0) ou retreci (d < 0) de d sur chaque bord (homothetie autour du
-- centre du cercle inscrit) : renvoie yTop, yTip, w
local function offsetTriangle(yTop: number, yTip: number, w: number, d: number): (number, number, number)
	local h = yTop - yTip
	local side = math.sqrt(w * w + h * h)
	local r = (2 * w * h) / (2 * w + 2 * side) -- rayon inscrit (aire / demi-perimetre)
	local cy = yTop - r
	local k = (r + d) / r
	return cy + (yTop - cy) * k, cy + (yTip - cy) * k, w * k
end

-- size : 1 = fleche de ~3.2 studs de large
function TutorialArrow.Build(size: number): Model
	local s = size
	local model = Instance.new("Model")
	model.Name = "TutorialArrow"
	local list: { Piece } = {}

	local depth = 0.85 * s
	local headW = 1.6 * s -- demi-largeur de la tete
	local tip = TIP.Y
	local headTop = tip + 2.0 * s
	local shaftW = 1.3 * s
	local shaftTop = headTop + 1.7 * s -- centre du bout arrondi
	local margin = 0.2 * s -- contour
	local bevel = 0.14 * s -- retrait de la face claire

	-- Contour sombre (un peu moins epais : les faces passent devant, il depasse sur les bords ;
	-- presque aussi epais que le corps, sinon un gros pave noir se voit de biais)
	local od = depth * 0.9
	local oTop, oTip, oW = offsetTriangle(headTop, tip, headW, margin)
	triangle(model, list, "OutlineHead", OUTLINE, od, oTop, oTip, oW)
	local oShaftH = shaftTop - headTop + 0.1 * s
	add(model, list, Instance.new("Part"), OUTLINE, Vector3.new(od, oShaftH, shaftW + 2 * margin),
		CFrame.new(0, headTop - 0.1 * s + oShaftH / 2, 0))
	local oCap = Instance.new("Part")
	oCap.Shape = Enum.PartType.Cylinder
	add(model, list, oCap, OUTLINE, Vector3.new(od, shaftW + 2 * margin, shaftW + 2 * margin), CFrame.new(0, shaftTop, 0))

	-- Corps orange (on voit ses tranches)
	triangle(model, list, "Head", SIDE, depth, headTop, tip, headW)
	local shaftH = shaftTop - headTop + 0.05 * s
	add(model, list, Instance.new("Part"), SIDE, Vector3.new(depth, shaftH, shaftW),
		CFrame.new(0, headTop - 0.05 * s + shaftH / 2, 0))
	local cap = Instance.new("Part")
	cap.Shape = Enum.PartType.Cylinder
	add(model, list, cap, SIDE, Vector3.new(depth, shaftW, shaftW), CFrame.new(0, shaftTop, 0))

	-- Face jaune en retrait des bords, un peu plus epaisse (devant et derriere) : biseau
	local face = model
	local fd = depth + 0.08 * s
	local fTop, fTip, fW = offsetTriangle(headTop, tip, headW, -bevel)
	triangle(face, list, "FaceHead", FACE, fd, fTop, fTip, fW)
	local fShaftH = shaftTop - fTop + 0.05 * s
	add(face, list, Instance.new("Part"), FACE, Vector3.new(fd, fShaftH, shaftW - 2 * bevel),
		CFrame.new(0, fTop - 0.05 * s + fShaftH / 2, 0))
	local fCap = Instance.new("Part")
	fCap.Shape = Enum.PartType.Cylinder
	add(face, list, fCap, FACE, Vector3.new(fd, shaftW - 2 * bevel, shaftW - 2 * bevel), CFrame.new(0, shaftTop, 0))

	-- Reflet : trait clair sur le cote gauche du manche vu de face (+Z : la droite de la camera est -Z)
	local shineH = shaftTop - headTop - 0.2 * s
	add(model, list, Instance.new("Part"), SHINE, Vector3.new(fd + 0.04 * s, shineH, 0.2 * s),
		CFrame.new(0, headTop + 0.2 * s + shineH / 2, (shaftW / 2 - bevel - 0.22 * s)))
	local dot = Instance.new("Part")
	dot.Shape = Enum.PartType.Cylinder
	add(model, list, dot, SHINE, Vector3.new(fd + 0.04 * s, 0.2 * s, 0.2 * s),
		CFrame.new(0, shaftTop + 0.12 * s, (shaftW / 2 - bevel - 0.22 * s)))

	for i, piece in list do
		if piece.part.Name == "Part" then
			piece.part.Name = `Piece{i}`
		end
	end

	-- Contour fin toujours visible (a travers les murs)
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = OUTLINE
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Adornee = model
	outline.Parent = model
	model.WorldPivot = CFrame.identity
	pieces[model] = list
	return model
end

-- Place la fleche : cframe = pivot (le +X local regarde la camera), scale = etirement par axe
-- (Y = hauteur), depuis la pointe
function TutorialArrow.Pose(model: Model, cframe: CFrame, scale: Vector3?)
	local list = pieces[model]
	if list == nil then
		model:PivotTo(cframe)
		return
	end
	local k = scale or Vector3.one
	for _, piece in list do
		local offset = piece.offset
		local position = TIP + (offset.Position - TIP) * k
		-- Pieces alignees sur les axes : l'etirement de chaque axe local = celui de l'axe du modele
		local localScale = offset:VectorToObjectSpace(k)
		piece.part.Size = piece.size * Vector3.new(math.abs(localScale.X), math.abs(localScale.Y), math.abs(localScale.Z))
		piece.part.CFrame = cframe * CFrame.new(position) * offset.Rotation
	end
	model.WorldPivot = cframe
end

return TutorialArrow
