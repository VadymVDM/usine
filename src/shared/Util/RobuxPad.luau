--!strict
-- Style des pads payants en Robux (Auto Collect, Speed x10, Billboard) : EXACTEMENT la forme des pads verts
-- (tools/build-map/02e : dalle epaisse a studs + dessus a studs + 4 baguettes neon), en violet
-- (bord violet fonce, dessus violet, neon violet clair). Demandes du 2026-11-20 : "remets comme
-- c'etait, juste la couleur en violet et pas jaune" ; "trop de styles de pads differents,
-- appuie-toi sur les verts mais change la couleur par violet" (avant : bord dore, neon rose).
-- Etiquette : nom en blanc + "R$ 199" en vert (ou "ACTIVE" quand le joueur a le pass) ; ligne
-- optionnelle entre les deux (jaune, ex. "2X Sell Price" du pad Billboard, 2026-11-20).
-- Utilise par : tools/build-map/02d (Auto Collect), 02e (Speed x10, Billboard) pour dessiner le pad ;
-- CustomerService et PassPadService pour le prix (SetPrice).
-- Un pad = Model avec PadBase, PadTop (+ BillboardGui Tag), PadGlow x4, PadZone.
-- Doc : docs/systems/pads-robux.md (Speed x10, Billboard), docs/systems/clients.md (Auto Collect)

local RobuxPad = {}

RobuxPad.BaseColor = Color3.fromRGB(95, 35, 185) -- bord violet fonce (avant : dore)
RobuxPad.TopColor = Color3.fromRGB(150, 70, 255) -- dessus violet a studs
RobuxPad.GlowColor = Color3.fromRGB(190, 110, 255) -- baguettes neon violet clair (sature)
RobuxPad.PriceColor = Color3.fromRGB(120, 255, 90)
RobuxPad.SubtitleColor = Color3.fromRGB(255, 226, 60) -- "2X Sell Price" : jaune vif

local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local STROKE = Color3.fromRGB(20, 16, 28)
local STUDS = Enum.SurfaceType.Studs
local SMOOTH = Enum.SurfaceType.Smooth

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.FontFace = FONT
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 3
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function glow(pad: Model, size: Vector3, cf: CFrame)
	local p = Instance.new("Part")
	p.Name = "PadGlow"
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = RobuxPad.GlowColor
	p.Material = Enum.Material.Neon
	p.CastShadow = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Parent = pad
end

-- Redessine un pad existant (pieces + etiquette) au style Robux. A lancer au build (Studio).
-- La dalle PadBase (6 x 0.6 x 6) reste ou elle est ; le reste est remis par-dessus.
function RobuxPad.Style(pad: Model, title: string, price: number, subtitle: string?)
	local base = pad:FindFirstChild("PadBase")
	local top = pad:FindFirstChild("PadTop")
	assert(base and base:IsA("BasePart") and top and top:IsA("BasePart"), "PadBase / PadTop manquant")
	for _, item in pad:GetChildren() do
		if item.Name == "PadGlow" then
			item:Destroy()
		end
	end
	base.Color = RobuxPad.BaseColor
	base.Material = Enum.Material.Plastic
	base.TopSurface = STUDS
	local rot = base.CFrame.Rotation
	local baseTop = base.Position.Y + base.Size.Y / 2
	local center = Vector3.new(base.Position.X, baseTop, base.Position.Z)
	local hx, hz = base.Size.X / 2, base.Size.Z / 2 -- 3 x 3 pour un pad standard
	-- Dessus a studs, 0.55 stud en retrait du bord, 0.35 d'epaisseur (comme les pads verts)
	top.Size = Vector3.new(base.Size.X - 1.1, 0.35, base.Size.Z - 1.1)
	top.CFrame = CFrame.new(center + Vector3.new(0, 0.175, 0)) * rot
	top.Color = RobuxPad.TopColor
	top.Material = Enum.Material.Plastic
	top.TopSurface = STUDS
	-- 4 baguettes neon autour du dessus
	local y = 0.06
	glow(pad, Vector3.new(hx * 2 - 0.5, 0.12, 0.2), CFrame.new(center) * rot * CFrame.new(0, y, -(hz - 0.35)))
	glow(pad, Vector3.new(hx * 2 - 0.5, 0.12, 0.2), CFrame.new(center) * rot * CFrame.new(0, y, hz - 0.35))
	glow(pad, Vector3.new(0.2, 0.12, hz * 2 - 0.9), CFrame.new(center) * rot * CFrame.new(-(hx - 0.35), y, 0))
	glow(pad, Vector3.new(0.2, 0.12, hz * 2 - 0.9), CFrame.new(center) * rot * CFrame.new(hx - 0.35, y, 0))

	local old = top:FindFirstChild("Tag")
	if old then
		old:Destroy()
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(9, 3.6)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	tag.Adornee = top
	if subtitle then
		-- 3 lignes : nom, effet ("2X Sell Price"), prix
		tag.Size = UDim2.fromScale(10, 5)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 4.3, 0)
		label(tag, "Title", title, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.38), Color3.new(1, 1, 1))
		label(tag, "Subtitle", subtitle, UDim2.fromScale(0, 0.38), UDim2.fromScale(1, 0.3), RobuxPad.SubtitleColor)
		label(tag, "Price", `R$ {price}`, UDim2.fromScale(0.15, 0.68), UDim2.fromScale(0.7, 0.32), RobuxPad.PriceColor)
	else
		label(tag, "Title", title, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55), Color3.new(1, 1, 1))
		label(tag, "Price", `R$ {price}`, UDim2.fromScale(0.15, 0.55), UDim2.fromScale(0.7, 0.45), RobuxPad.PriceColor)
	end
	tag.Parent = top
end

-- Prix affiche, ou "ACTIVE" si le joueur a deja le pass. Serveur, a chaque changement.
function RobuxPad.SetPrice(pad: Instance, price: number, owned: boolean)
	local top = pad:FindFirstChild("PadTop")
	local tag = top and top:FindFirstChild("Tag")
	local priceLabel = tag and tag:FindFirstChild("Price")
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = if owned then "ACTIVE" else `R$ {price}`
	end
end

return RobuxPad
