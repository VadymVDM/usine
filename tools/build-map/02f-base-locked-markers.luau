--!strict
-- BaseTemplate, morceau 6/6 : zones 2 et 3 fermees (bloc rouge transparent + carte "a debloquer"
-- cliquable + apercu du contenu), marqueurs pour le code (apparition, clients), dossier Dynamic.
-- A lancer apres 02a. Textes depuis Config/Map.luau (BaseService les remet aussi au clonage).
-- Le clic sur une zone (ClickDetector du bloc "Barrier") est gere par BaseService -> message
-- "Coming soon" (remote Notify).
-- Doc : docs/systems/carte-bases.md

-- execute_luau garde les modules deja charges : on charge une copie pour avoir la Config a jour
local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local MapConfig = freshRequire(game:GetService("ReplicatedStorage").Shared.Config.Map)

local BARRIER = Color3.fromRGB(226, 64, 64)
local BARRIER_EDGE = Color3.fromRGB(200, 40, 40)
local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local WOOD_TOP = Color3.fromRGB(214, 180, 130)
local FABRIC = { Color3.fromRGB(70, 140, 190), Color3.fromRGB(238, 226, 204) }
local BOTTLES = { Color3.fromRGB(120, 190, 90), Color3.fromRGB(230, 120, 60), Color3.fromRGB(200, 70, 120), Color3.fromRGB(240, 200, 70) }
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40)

local STUDS = Enum.SurfaceType.Studs
local SMOOTH_SURF = Enum.SurfaceType.Smooth

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
local MARKER = table.clone(SMOOTH)
MARKER.Transparency = 1
MARKER.CanCollide = false
MARKER.CanQuery = false
MARKER.CanTouch = false
MARKER.CastShadow = false

local function withSmooth(extra: { [string]: any }): { [string]: any }
	local t = table.clone(SMOOTH)
	for k, v in extra do
		t[k] = v
	end
	return t
end

-- ===== Interface (briques de PackStyle) =====
local function stroke(parent: Instance, thickness: number, color: Color3, mode: Enum.ApplyStrokeMode?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, strokePx: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = value
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.ZIndex = 5
	stroke(t, strokePx, TEXT_STROKE)
	t.Parent = parent
	return t
end

local function gradientBox(parent: Instance, name: string, bottom: Color3, top: Color3, border: Color3, pos: UDim2, size: UDim2, borderPx: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.ZIndex = 2
	stroke(f, borderPx, border, Enum.ApplyStrokeMode.Border)
	local g = Instance.new("UIGradient")
	g.Rotation = -90
	g.Color = ColorSequence.new(bottom, top)
	g.Parent = f
	local inner = Instance.new("Frame")
	inner.Name = "Shine"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -5, 1, -5)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 2
	stroke(inner, 1.5, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border).Transparency = 0.35
	inner.Parent = f
	f.Parent = parent
	return f
end

-- Cadenas dessine en cadres (anse grise + corps dore + serrure)
local function drawLock(parent: Instance, pos: UDim2, size: UDim2)
	local holder = Instance.new("Frame")
	holder.Name = "Lock"
	holder.BackgroundTransparency = 1
	holder.Position = pos
	holder.Size = size
	holder.ZIndex = 3
	local shackle = Instance.new("Frame")
	shackle.Name = "Shackle"
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0.04)
	shackle.Size = UDim2.fromScale(0.56, 0.56)
	shackle.BackgroundTransparency = 1
	shackle.ZIndex = 3
	Instance.new("UICorner", shackle).CornerRadius = UDim.new(0.5, 0)
	stroke(shackle, 9, TEXT_STROKE, Enum.ApplyStrokeMode.Border)
	local shackleInner = Instance.new("Frame")
	shackleInner.Size = UDim2.fromScale(1, 1)
	shackleInner.BackgroundTransparency = 1
	shackleInner.ZIndex = 3
	Instance.new("UICorner", shackleInner).CornerRadius = UDim.new(0.5, 0)
	stroke(shackleInner, 4, Color3.fromRGB(172, 188, 206), Enum.ApplyStrokeMode.Border)
	shackleInner.Parent = shackle
	shackle.Parent = holder
	local body = gradientBox(holder, "Body", Color3.fromRGB(240, 150, 30), Color3.fromRGB(255, 214, 80), TEXT_STROKE, UDim2.fromScale(0.04, 0.4), UDim2.fromScale(0.92, 0.56), 3)
	body.ZIndex = 4
	Instance.new("UICorner", body).CornerRadius = UDim.new(0.18, 0)
	local hole = Instance.new("Frame")
	hole.Name = "Keyhole"
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.42)
	hole.Size = UDim2.fromScale(0.22, 0.3)
	hole.BackgroundColor3 = Color3.fromRGB(110, 54, 24)
	hole.ZIndex = 5
	Instance.new("UICorner", hole).CornerRadius = UDim.new(0.5, 0)
	hole.Parent = body
	local slot = Instance.new("Frame")
	slot.Name = "KeySlot"
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.fromScale(0.5, 0.5)
	slot.Size = UDim2.fromScale(0.1, 0.28)
	slot.BackgroundColor3 = Color3.fromRGB(110, 54, 24)
	slot.BorderSizePixel = 0
	slot.ZIndex = 5
	slot.Parent = body
	holder.Parent = parent
end

local model = game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
assert(model, "Lancer 02a d'abord")
for _, name in { "ZoneLocks", "Markers" } do
	local old = model:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
if not model:FindFirstChild("Dynamic") then
	local dyn = Instance.new("Folder")
	dyn.Name = "Dynamic"
	dyn.Parent = model
end

local locks = Instance.new("Folder")
locks.Name = "ZoneLocks"

local X0, X1 = -43.5, -0.5 -- largeur du bloc rouge (zones 2-3 : x -44..0)
local EDGE = withSmooth({ Transparency = 0.15, CanCollide = false, CanQuery = false, CastShadow = false })

local function lockedZone(zoneId: string, z0: number, z1: number): Model
	local zone = Instance.new("Model")
	zone.Name = zoneId
	zone:SetAttribute("ZoneId", zoneId)
	local za, zb = z0 + 0.5, z1 - 0.5
	local barrier = box(zone, "Barrier", X0, X1, 0.3, 10.3, za, zb, BARRIER, withSmooth({
		Transparency = 0.62,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	}))
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 80
	click.Parent = barrier
	-- Aretes plus marquees (aucune face au meme endroit que le bloc ou qu'une autre arete)
	for _, x in { X0, X1 } do
		for _, z in { za, zb } do
			box(zone, "EdgeV", x - 0.2, x + 0.2, 0.7, 10.1, z - 0.2, z + 0.2, BARRIER_EDGE, EDGE)
		end
	end
	for _, y in { 0.3, 10.1 } do
		for _, z in { za, zb } do
			box(zone, "EdgeX", X0 - 0.2, X1 + 0.2, y, y + 0.4, z - 0.2, z + 0.2, BARRIER_EDGE, EDGE)
		end
		for _, x in { X0, X1 } do
			box(zone, "EdgeZ", x - 0.18, x + 0.18, y + 0.02, y + 0.38, za + 0.2, zb - 0.2, BARRIER_EDGE, EDGE)
		end
	end
	-- Carte "a debloquer" au-dessus
	local anchor = box(zone, "CardAnchor", (X0 + X1) / 2 - 0.5, (X0 + X1) / 2 + 0.5, 10.3, 11.3, (za + zb) / 2 - 0.5, (za + zb) / 2 + 0.5, Color3.new(1, 0, 0), MARKER)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Card"
	bb.Size = UDim2.fromScale(11, 5.4)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	bb.MaxDistance = 160
	bb.LightInfluence = 0
	bb.Adornee = anchor
	local panel = gradientBox(bb, "Panel", Color3.fromRGB(176, 28, 40), Color3.fromRGB(255, 104, 96), TEXT_STROKE, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 3)
	drawLock(panel, UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.24, 0.8))
	text(panel, "ZoneName", MapConfig.LockedZoneNames[zoneId], UDim2.fromScale(0.63, 0.08), UDim2.fromScale(0.66, 0.38), 3)
	local button = gradientBox(panel, "StatusButton", Color3.fromRGB(240, 150, 30), Color3.fromRGB(255, 214, 80), Color3.fromRGB(110, 50, 0), UDim2.fromScale(0.33, 0.56), UDim2.fromScale(0.6, 0.32), 3)
	text(button, "Status", MapConfig.LockedZoneText, UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.9, 0.84), 2.5)
	bb.Parent = anchor
	return zone
end

-- Zone 3 (devant, terrasse) : tables et parasols visibles a travers le rouge
local zone3 = lockedZone("Zone3", 0, 40)
local function terraceTable(cx: number, cz: number)
	box(zone3, "TableLeg", cx - 0.3, cx + 0.3, 0.3, 2.8, cz - 0.3, cz + 0.3, WOOD_DARK)
	box(zone3, "TableTop", cx - 1.8, cx + 1.8, 2.8, 3.2, cz - 1.8, cz + 1.8, WOOD_TOP)
	box(zone3, "ParasolPole", cx - 0.15, cx + 0.15, 3.2, 7.5, cz - 0.15, cz + 0.15, WOOD_DARK, SMOOTH)
	for i = 0, 3 do
		local yaw = i * 90
		local cf = CFrame.new(cx, 7.2, cz) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(-18), 0, 0)
		part(zone3, "Parasol", Vector3.new(3.2, 0.3, 3.4), cf, FABRIC[(i % 2) + 1], SMOOTH)
	end
	for _, o in { Vector2.new(2.8, 0), Vector2.new(-2.8, 0) } do
		box(zone3, "Stool", cx + o.X - 0.7, cx + o.X + 0.7, 0.3, 1.8, cz + o.Y - 0.7, cz + o.Y + 0.7, WOOD)
	end
end
terraceTable(-30, 12)
terraceTable(-14, 26)
zone3.Parent = locks

-- Zone 2 (fond, bar a cocktails) : comptoir, etagere, bouteilles
local zone2 = lockedZone("Zone2", 40, 80)
box(zone2, "BarBody", -36, -18, 0.3, 3.6, 60, 63, WOOD_DARK)
box(zone2, "BarTop", -36.4, -17.6, 3.6, 4.1, 59.6, 63.4, WOOD_TOP)
box(zone2, "Shelf", -36, -18, 4, 4.4, 72.5, 74.5, WOOD)
box(zone2, "ShelfBack", -36, -18, 0.3, 7, 74.5, 75, WOOD_DARK)
for i = 0, 8 do
	local bx = -35 + i * 2
	box(zone2, "Bottle", bx - 0.35, bx + 0.35, 4.4, 5.8, 73.2, 73.9, BOTTLES[(i % #BOTTLES) + 1], SMOOTH)
end
for i = 0, 3 do
	local sx = -33 + i * 4.5
	box(zone2, "BarStool", sx - 0.7, sx + 0.7, 0.3, 2.4, 56.6, 58, WOOD)
end
zone2.Parent = locks
locks.Parent = model

-- MARQUEURS
local markers = Instance.new("Folder")
markers.Name = "Markers"
-- Apparition du joueur (sur le chemin, tourne vers l'interieur de la base)
part(markers, "SpawnPoint", Vector3.new(2, 1, 2), CFrame.lookAt(Vector3.new(22, 0.85, 22), Vector3.new(40, 0.85, 50)), Color3.new(0, 1, 0), MARKER)
-- Les clients arrivent du trottoir et se placent devant le comptoir
part(markers, "CustomerEntry", Vector3.new(2, 1, 2), CFrame.new(45, 0.9, -16), Color3.new(0, 1, 0), MARKER)
for i = 1, 5 do
	local x = 34 + i * 3
	part(markers, "CustomerSpot" .. i, Vector3.new(2, 1, 2), CFrame.lookAt(Vector3.new(x, 0.8, 2.6), Vector3.new(x, 0.8, 6)), Color3.new(0, 1, 0), MARKER)
end
markers.Parent = model

return "Locked zones + markers OK: " .. #model:GetDescendants() .. " objets dans le modele"
