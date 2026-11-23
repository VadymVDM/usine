--!strict
-- FloorTemplate : les 4 pads verts "FREE" de l'usine a construire (2026-11-21). A lancer apres 02a
-- (relancable : detruit et recree FloorTemplate.Setup). Positions et textes : Config/Setup.Steps.
-- Chaque pad : Setup.<id> (Model) > Pad (Model, nom lu par PadController pour l'effet "pad vert") :
--   PadBase (dalle vert fonce), PadTop (dessus vert vif a studs + BillboardGui Tag : Title, Price
--   "FREE"), PadGlow (4 baguettes claires, PAS de Neon : regle du ressenti), PadZone (invisible,
--   testee par SetupService). Tout est cache par SetupService sauf le pad de l'etape en cours.
-- Doc : docs/systems/usine-a-construire.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Setup = freshRequire(ReplicatedStorage.Shared.Config.Setup)

local PAD_BASE = Color3.fromRGB(34, 140, 50)
local PAD_TOP = Color3.fromRGB(90, 225, 70)
local PAD_GLOW = Color3.fromRGB(200, 255, 120) -- clair et sature, SmoothPlastic (pas de Neon)
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)
local STUDS = Enum.SurfaceType.Studs
local SMOOTH = Enum.SurfaceType.Smooth

local function box(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	p.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = STUDS
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.CastShadow = false
	p.CanTouch = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function textLabel(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3)
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
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = t
	t.Parent = parent
end

local model = ServerStorage:FindFirstChild("FloorTemplate")
assert(model, "Lancer 02a d'abord")
local old = model:FindFirstChild("Setup")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Setup"

for _, step in Setup.Steps do
	local x, z, y = step.x, step.z, step.floorY
	local m = Instance.new("Model")
	m.Name = step.id
	local pad = Instance.new("Model")
	pad.Name = "Pad"
	box(pad, "PadBase", x - 3, x + 3, y, y + 0.6, z - 3, z + 3, PAD_BASE)
	local top = box(pad, "PadTop", x - 2.45, x + 2.45, y + 0.6, y + 0.95, z - 2.45, z + 2.45, PAD_TOP)
	local glow = {
		Material = Enum.Material.SmoothPlastic,
		TopSurface = SMOOTH,
		BottomSurface = SMOOTH,
		CanCollide = false,
		CanQuery = false,
	}
	box(pad, "PadGlow", x - 2.75, x + 2.75, y + 0.6, y + 0.72, z - 2.75, z - 2.55, PAD_GLOW, glow)
	box(pad, "PadGlow", x - 2.75, x + 2.75, y + 0.6, y + 0.72, z + 2.55, z + 2.75, PAD_GLOW, glow)
	box(pad, "PadGlow", x - 2.75, x - 2.55, y + 0.6, y + 0.72, z - 2.55, z + 2.55, PAD_GLOW, glow)
	box(pad, "PadGlow", x + 2.55, x + 2.75, y + 0.6, y + 0.72, z - 2.55, z + 2.55, PAD_GLOW, glow)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(10, 4)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0)
	tag.MaxDistance = 120 -- se voit de loin : c'est le chemin du joueur
	tag.LightInfluence = 0
	tag.Adornee = top
	textLabel(tag, "Title", step.label, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55), Color3.new(1, 1, 1))
	textLabel(tag, "Price", Setup.PadText, UDim2.fromScale(0.2, 0.55), UDim2.fromScale(0.6, 0.45), Color3.fromRGB(120, 255, 90))
	tag.Parent = top
	box(pad, "PadZone", x - 3, x + 3, y, y + 5, z - 3, z + 3, Color3.new(1, 0, 0), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		TopSurface = SMOOTH,
		BottomSurface = SMOOTH,
	})
	pad.PrimaryPart = top
	pad.Parent = m
	m.Parent = folder
end

folder.Parent = model
return "Setup OK: " .. #folder:GetChildren() .. " pads, " .. #folder:GetDescendants() .. " objets"
