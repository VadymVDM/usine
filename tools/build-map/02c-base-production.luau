--!strict
-- BaseTemplate, morceau 3/6 : etal a fruits (30 caisses = 30 bacs), presse-fruits, palette de jus.
-- A lancer apres 02a. Recree le dossier Production.
-- Bacs : Bin1..10 (rang du bas, Common), Bin11..20 (milieu, Uncommon), Bin21..30 (haut, Rare).
-- Les fruits se posent sur le dessus de chaque BinN. Zones pour le code : BinsPad, JuicePile (invisibles).
-- Doc : docs/systems/carte-bases.md

local WOOD = Color3.fromRGB(168, 126, 84)
local WOOD_LIGHT = Color3.fromRGB(186, 146, 102)
local WOOD_DARK = Color3.fromRGB(120, 86, 58)
local CRATE = Color3.fromRGB(196, 152, 98)
local CRATE_INSIDE = Color3.fromRGB(140, 100, 64)
local ROOF = { Color3.fromRGB(178, 92, 66), Color3.fromRGB(192, 106, 76) }
local BODY = Color3.fromRGB(196, 98, 62)
local BODY_DARK = Color3.fromRGB(168, 80, 50)
local CREAM = Color3.fromRGB(232, 222, 200)
local METAL = Color3.fromRGB(176, 182, 190)
local METAL_DARK = Color3.fromRGB(110, 116, 126)
local GLASS = Color3.fromRGB(200, 230, 240)
local JUICE = Color3.fromRGB(240, 150, 40)
local KNOB = Color3.fromRGB(200, 56, 48)

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
local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }

local model = game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
assert(model, "Lancer 02a d'abord")
local old = model:FindFirstChild("Production")
if old then
	old:Destroy()
end
local production = Instance.new("Folder")
production.Name = "Production"

-- ETAL A FRUITS (x 46..66, z 38..44), 3 gradins
local rack = Instance.new("Model")
rack.Name = "FruitRack"
box(rack, "SideLeft", 45.4, 46, 0.3, 5.2, 37.6, 44.4, WOOD_DARK)
box(rack, "SideRight", 66, 66.6, 0.3, 5.2, 37.6, 44.4, WOOD_DARK)
box(rack, "Back", 46, 66, 0.3, 8, 44, 44.4, WOOD)
for i = 0, 2 do
	local top = 1 + i * 1.2
	local z0 = 38 + i * 2
	box(rack, "Tier" .. i, 46, 66, 0.3, top, z0, z0 + 2, if i % 2 == 0 then WOOD_LIGHT else WOOD)
	box(rack, "TierLip" .. i, 46, 66, top - 0.35, top + 0.1, z0 - 0.1, z0 + 0.15, WOOD_DARK)
end
-- Poteaux et toit en planches inclinees (fond plus haut)
box(rack, "PostLeft", 45.5, 46.1, 0.3, 7.3, 37.4, 38, WOOD_DARK)
box(rack, "PostRight", 65.9, 66.5, 0.3, 7.3, 37.4, 38, WOOD_DARK)
local roofAngle = math.atan(1.2 / 7.8)
for i = 0, 4 do
	local cx = 45 + 2.2 + i * 4.4
	part(rack, "Roof" .. i, Vector3.new(4.4, 0.4, 8.8), CFrame.new(cx, 7.85, 40.9) * CFrame.Angles(-roofAngle, 0, 0), ROOF[(i % 2) + 1])
end
box(rack, "RoofFascia", 45, 67, 6.65, 7.15, 36.45, 36.75, WOOD_DARK)
rack.Parent = production
task.wait()

-- Caisses : fond (BinN, ou se posent les fruits) + 4 rebords
local bins = Instance.new("Folder")
bins.Name = "Bins"
local rims = Instance.new("Folder")
rims.Name = "BinRims"
for i = 0, 2 do
	local base = 1 + i * 1.2 -- dessus du gradin
	local cz = 39 + i * 2
	for c = 0, 9 do
		local cx = 47 + c * 2
		local n = i * 10 + c + 1
		box(bins, "Bin" .. n, cx - 0.7, cx + 0.7, base, base + 0.45, cz - 0.65, cz + 0.65, CRATE_INSIDE)
		box(rims, "Rim", cx - 0.85, cx + 0.85, base, base + 0.85, cz - 0.8, cz - 0.65, CRATE)
		box(rims, "Rim", cx - 0.85, cx + 0.85, base, base + 0.85, cz + 0.65, cz + 0.8, CRATE)
		box(rims, "Rim", cx - 0.85, cx - 0.7, base, base + 0.85, cz - 0.65, cz + 0.65, CRATE)
		box(rims, "Rim", cx + 0.7, cx + 0.85, base, base + 0.85, cz - 0.65, cz + 0.65, CRATE)
	end
	task.wait()
end
bins.Parent = production
rims.Parent = production

-- Plancher devant l'etal : marcher dessus = deposer les fruits
local deck = Instance.new("Model")
deck.Name = "BinsDeck"
for i = 0, 9 do
	local x0 = 46 + i * 2
	box(deck, "Plank", x0 + 0.05, x0 + 1.95, 0.3, 0.55, 32.7, 37.5, if i % 2 == 0 then WOOD else WOOD_LIGHT)
end
deck.Parent = production
box(production, "BinsPad", 46, 66, 0.3, 4.3, 32.6, 38, Color3.new(1, 0, 0), MARKER)
task.wait()

-- PRESSE-FRUITS (x 18.5..27.5, z 34.5..41.5)
local press = Instance.new("Model")
press.Name = "Press"
for _, f in { { 19, 35 }, { 27, 35 }, { 19, 41 }, { 27, 41 } } do
	box(press, "Foot", f[1] - 0.5, f[1] + 0.5, 0.3, 0.9, f[2] - 0.5, f[2] + 0.5, METAL_DARK)
end
local cabinet = box(press, "Cabinet", 18.5, 27.5, 0.9, 4.5, 34.5, 41.5, BODY)
box(press, "FrontPanel", 19.5, 26.5, 1.4, 4, 34.35, 34.5, BODY_DARK)
box(press, "Trim", 18.3, 27.7, 4.5, 4.9, 34.3, 41.7, CREAM)
box(press, "UpperBody", 19.3, 26.7, 4.9, 7.4, 35.3, 40.7, BODY)
box(press, "Lid", 20, 26, 7.4, 7.9, 36, 40, CREAM)
box(press, "Funnel1", 21, 25, 7.9, 8.6, 36.5, 39.5, METAL)
box(press, "Funnel2", 20.3, 25.7, 8.6, 9.3, 35.8, 40.2, METAL)
box(press, "FunnelRim", 19.6, 26.4, 9.3, 9.9, 35.1, 40.9, METAL_DARK)
part(press, "FruitOrange", Vector3.new(1.2, 1.2, 1.2), CFrame.new(22, 10.5, 37.6) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(236, 140, 40), DECOR)
part(press, "FruitLemon", Vector3.new(1.1, 1.1, 1.1), CFrame.new(24.2, 10.45, 38.6) * CFrame.Angles(0, math.rad(50), 0), Color3.fromRGB(236, 212, 72), DECOR)
part(press, "FruitApple", Vector3.new(1.1, 1.1, 1.1), CFrame.new(23.3, 10.45, 36.8) * CFrame.Angles(0, math.rad(-15), 0), Color3.fromRGB(200, 48, 42), DECOR)
-- Reservoir en verre plein de jus, cote palette
box(press, "TankBase", 15.4, 18.5, 0.3, 1.2, 35.8, 40.2, METAL_DARK)
box(press, "TankGlass", 15.6, 18.5, 1.2, 5.6, 36, 40, GLASS, {
	Material = Enum.Material.Glass,
	Transparency = 0.55,
	TopSurface = SMOOTH_SURF,
	BottomSurface = SMOOTH_SURF,
	FrontSurface = SMOOTH_SURF,
	BackSurface = SMOOTH_SURF,
	LeftSurface = SMOOTH_SURF,
	RightSurface = SMOOTH_SURF,
})
box(press, "TankJuice", 15.8, 18.3, 1.25, 4.2, 36.2, 39.8, JUICE, SMOOTH)
box(press, "TankLid", 15.4, 18.7, 5.6, 6, 35.8, 40.2, METAL)
box(press, "Tap", 14.8, 15.4, 2, 2.5, 37.7, 38.3, METAL)
box(press, "TapSpout", 14.85, 15.25, 1.6, 2, 37.8, 38.2, METAL)
-- Levier
box(press, "LeverBase", 27.5, 27.9, 2.8, 3.6, 37.7, 38.3, METAL_DARK)
box(press, "LeverStick", 27.9, 28.2, 3, 6.4, 37.85, 38.15, METAL)
box(press, "LeverKnob", 27.7, 28.4, 6.4, 7.1, 37.65, 38.35, KNOB)
press.PrimaryPart = cabinet
press.Parent = production

-- PALETTE DE JUS (les gobelets s'empilent dessus ; marcher dessus = prendre les jus)
local pallet = Instance.new("Model")
pallet.Name = "JuicePallet"
for _, z in { 34.4, 37.6, 40.8 } do
	box(pallet, "Runner", 7, 15, 0.3, 0.7, z, z + 0.8, WOOD_DARK)
end
for i = 0, 4 do
	local z0 = 34.2 + i * 1.6
	box(pallet, "Board", 6.8, 15.2, 0.7, 1, z0, z0 + 1.4, if i % 2 == 0 then WOOD_LIGHT else WOOD)
end
pallet.Parent = production
box(production, "JuicePile", 6.8, 15.2, 0.3, 5, 34, 42, Color3.new(1, 0, 0), MARKER)
box(production, "JuiceLabelAnchor", 10.5, 11.5, 7.5, 8.5, 37.5, 38.5, Color3.new(1, 0, 0), MARKER)

production.Parent = model
return "Production OK: " .. #production:GetDescendants()
