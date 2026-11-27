--!strict
-- Montagnes et volcan en fond de carte (2026-11-27, demande de l'utilisateur : "des montagnes, un
-- volcan... en fond de map, optimise et pas lourd").
-- v2 (meme jour, retour : "moches, trop proches, pas assez grandes") : plus de blocs empiles.
-- Chaque pic = une pyramide a facettes (4 CornerWedgeParts), style low-poly ; une montagne = 1 pic
-- principal + 2 pics secondaires + un pied vert large et bas + un chapeau de neige. Volcan = tronc de
-- pyramide (1 bloc + 4 Wedges + 4 CornerWedges), lac de lave Neon au sommet, coulees Neon sur les
-- pentes, panache de fumee (1 ParticleEmitter, ~25 particules).
-- Loin (1500 a 2300 studs du centre) et geants (500 a 1100 de haut).
-- Leger : ~20 pieces par montagne, toutes Anchored, sans collision / requete / toucher / ombre,
-- surfaces lisses (pas de studs : moirage au loin). Modeles "Persistent" : toujours envoyes au client
-- meme loin du joueur (StreamingEnabled, rayon 1024), sinon les montagnes disparaitraient.
-- Le mode graphismes bas (SettingsController) eteint deja la fumee comme toutes les particules.
-- Relancable : detruit et recree Workspace.Map.Mountains. Positions fixes (graine 7).
-- SAMPLE = true : seulement le volcan et 1 montagne (pour valider le look).
-- Doc : docs/systems/carte-bases.md (section Montagnes)

local SAMPLE = false

local FOOT = { Color3.fromRGB(70, 138, 66), Color3.fromRGB(82, 148, 70) }
local ROCK = { Color3.fromRGB(120, 124, 138), Color3.fromRGB(104, 108, 124), Color3.fromRGB(136, 136, 146) }
local SNOW = Color3.fromRGB(244, 247, 252)
local VOLCANO = { Color3.fromRGB(70, 58, 56), Color3.fromRGB(58, 48, 48) }
local LAVA = Color3.fromRGB(255, 104, 28)
local LAVA_HOT = Color3.fromRGB(255, 170, 46)

local PROPS = {
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
	Locked = true,
}

local function part(className: string, parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	for k, v in PROPS do
		(p :: any)[k] = v
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function newModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return m
end

local map = workspace:FindFirstChild("Map")
assert(map, "Lancer 01 d'abord")
local old = map:FindFirstChild("Mountains")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Mountains"
local rng = Random.new(7)

-- Coin "haut" d'une CornerWedgePart en repere local : (+X, -Z). On tourne chaque quart pour que ce
-- coin pointe vers le centre de la pyramide.
local QUARTERS = { 0, 90, 180, 270 }

-- Pyramide a facettes : base w x d posee a y = y0 (repere `frame`), sommet a y0 + h.
local function pyramid(parent: Instance, name: string, frame: CFrame, w: number, d: number, h: number, y0: number, color: Color3)
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local apex = rot:VectorToWorldSpace(Vector3.new(1, 0, -1))
		local swap = deg == 90 or deg == 270
		local size = if swap then Vector3.new(d / 2, h, w / 2) else Vector3.new(w / 2, h, d / 2)
		local offset = Vector3.new(-math.sign(apex.X) * w / 4, y0 + h / 2, -math.sign(apex.Z) * d / 4)
		part("CornerWedgePart", parent, name, size, frame * CFrame.new(offset) * rot, color)
	end
end

-- Montagne : pied vert, pic principal, 2 pics secondaires, neige sur les pics assez hauts.
local function mountain(cx: number, cz: number, w: number, h: number)
	local m = newModel("Mountain")
	local frame = CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0)
	local rock = ROCK[rng:NextInteger(1, #ROCK)]
	-- pied : large et bas (foret au loin)
	pyramid(m, "Foot", frame, w * 1.35, w * 1.2, h * 0.22, -2, FOOT[rng:NextInteger(1, #FOOT)])
	-- pics : { decalage x, decalage z, largeur, hauteur } relatifs
	local peaks = {
		{ 0, 0, 1, 1 },
		{ rng:NextNumber(0.3, 0.42), rng:NextNumber(-0.15, 0.15), rng:NextNumber(0.55, 0.7), rng:NextNumber(0.55, 0.72) },
		{ -rng:NextNumber(0.3, 0.42), rng:NextNumber(-0.15, 0.15), rng:NextNumber(0.5, 0.62), rng:NextNumber(0.45, 0.62) },
	}
	for i, p in peaks do
		local pf = frame * CFrame.new(p[1] * w, 0, p[2] * w)
		local pw, pd, ph = w * p[3], w * p[3] * rng:NextNumber(0.85, 1), h * p[4]
		pyramid(m, "Peak" .. i, pf, pw, pd, ph, -2, if i == 1 then rock else ROCK[rng:NextInteger(1, #ROCK)])
		-- neige : meme pente, legerement au-dessus de la roche (pas de z-fighting)
		if ph > 420 then
			local f = 0.3
			local lift = ph * 0.012
			pyramid(m, "Snow" .. i, pf, pw * f, pd * f, ph * f, ph - 2 - ph * f + lift, SNOW)
		end
	end
	m.Parent = folder
end

-- Volcan : tronc de pyramide de base w, sommet plat t x t, hauteur h. Repere local : -Z regarde le
-- centre de la carte (les coulees sont du cote des joueurs).
local function volcano(cx: number, cz: number, w: number, t: number, h: number)
	local m = newModel("Volcano")
	local frame = CFrame.lookAt(Vector3.new(cx, 0, cz), Vector3.new(0, 0, 0))
	local s = (w - t) / 2 -- largeur d'une pente
	local y0 = -2
	part("Part", m, "Core", Vector3.new(t, h, t), frame * CFrame.new(0, y0 + h / 2, 0), VOLCANO[1])
	-- 4 pentes (WedgePart : cote haut en +Z local)
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local outward = -rot:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local pos = outward * (t / 2 + s / 2) + Vector3.new(0, y0 + h / 2, 0)
		part("WedgePart", m, "Slope", Vector3.new(t, h, s), frame * CFrame.new(pos) * rot, VOLCANO[1])
	end
	-- 4 coins (CornerWedgePart, coin haut vers le centre)
	for _, deg in QUARTERS do
		local rot = CFrame.Angles(0, math.rad(deg), 0)
		local apex = rot:VectorToWorldSpace(Vector3.new(1, 0, -1))
		local pos = Vector3.new(-math.sign(apex.X) * (t / 2 + s / 2), y0 + h / 2, -math.sign(apex.Z) * (t / 2 + s / 2))
		part("CornerWedgePart", m, "Corner", Vector3.new(s, h, s), frame * CFrame.new(pos) * rot, VOLCANO[2])
	end
	local top = y0 + h
	-- Cratere : rebord sombre + lac de lave
	part("Part", m, "Rim", Vector3.new(t * 0.92, 10, t * 0.92), frame * CFrame.new(0, top + 5, 0), VOLCANO[2])
	part("Part", m, "LavaPool", Vector3.new(t * 0.7, 10, t * 0.7), frame * CFrame.new(0, top + 6, 0), LAVA_HOT, true)
	-- Coulees sur la pente face a la carte (-Z) et sur les deux pentes de cote
	local slopeLen = math.sqrt(s * s + h * h)
	local function flow(rotDeg: number, x: number, widthStud: number, frac: number)
		local rot = frame * CFrame.Angles(0, math.rad(rotDeg), 0)
		-- dans ce repere, la pente descend vers -Z : du haut (z = -t/2, y = top) au bas (z = -(t/2+s), y = y0)
		local up = Vector3.new(0, top, -t / 2)
		local down = Vector3.new(0, y0, -(t / 2 + s))
		local finish = up:Lerp(down, frac)
		local normal = Vector3.new(0, s, -h).Unit
		local a = Vector3.new(x, up.Y, up.Z) + normal * 1.5
		local b = Vector3.new(x, finish.Y, finish.Z) + normal * 1.5
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b, normal)
		part("Part", m, "LavaFlow", Vector3.new(widthStud, 3, len + 4), rot * cf, LAVA, true)
	end
	flow(0, -t * 0.18, 26, 0.85)
	flow(0, t * 0.22, 18, 0.6)
	flow(0, t * 0.02, 14, 0.4)
	flow(90, t * 0.1, 22, 0.7)
	flow(-90, -t * 0.12, 20, 0.55)
	local _ = slopeLen

	-- Fumee : un seul emetteur, peu de particules, grosses et lentes ; opaque et sombre car la
	-- brume de l'Atmosphere eclaircit tout ce qui est loin
	local source = part("Part", m, "SmokeSource", Vector3.new(4, 4, 4), frame * CFrame.new(0, top + 20, 0), LAVA)
	source.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(62, 58, 58), Color3.fromRGB(120, 118, 120))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 140), NumberSequenceKeypoint.new(1, 420) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(18, 24)
	smoke.Rate = 1.2
	smoke.Speed = NumberRange.new(25, 35)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Acceleration = Vector3.new(4, 1, 2)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-6, 6)
	smoke.LightInfluence = 0.3
	smoke.Parent = source
	m.Parent = folder
end

-- Volcan au nord-ouest, visible depuis le spawn (x -340) et les bases du nord
local VOLCANO_POS = Vector2.new(-900, 1750)
volcano(VOLCANO_POS.X, VOLCANO_POS.Y, 1150, 260, 620)

if SAMPLE then
	mountain(500, 1850, 900, 950)
else
	-- Deux rangees en anneau (ellipse) : devant plus basses, derriere plus grandes.
	local function ring(rx: number, rz: number, count: number, wMin: number, wMax: number, hMin: number, hMax: number, phase: number)
		for i = 0, count - 1 do
			local a = (i + phase + rng:NextNumber(-0.18, 0.18)) / count * math.pi * 2
			local x, z = math.cos(a) * rx, math.sin(a) * rz
			if (Vector2.new(x, z) - VOLCANO_POS).Magnitude > 700 then
				mountain(x, z, rng:NextNumber(wMin, wMax), rng:NextNumber(hMin, hMax))
			end
		end
	end
	ring(1700, 1500, 14, 650, 900, 500, 750, 0)
	task.wait()
	ring(2250, 2050, 12, 900, 1200, 800, 1100, 0.5)
end

folder.Parent = map

local count = 0
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
return "Mountains : " .. #folder:GetChildren() .. " modeles, " .. count .. " pieces"
