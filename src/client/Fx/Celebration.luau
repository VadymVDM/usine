--!strict
-- Effets de fete (client seulement) : confettis a l'ecran et feux d'artifice dans le monde.
-- Demande utilisateur du 2026-11-20 : "des confettis et des fireworks smooth" sur "NEW FLOOR!".
--   * Confetti(playerGui, colors) : ~70 petits rectangles qui partent du haut de l'ecran, tombent
--     en ralentissant (frottement de l'air), se balancent, tournent et disparaissent en fondu.
--   * Fireworks(center, colors) : quelques fusees (neon + trainee) montent en douceur autour de
--     `center`, puis eclatent en etincelles (ParticleEmitter:Emit, frein, fondu) et en flash lumineux.
-- Tout est detruit tout seul (une seule boucle RenderStepped par effet). Rien ne passe par le serveur.
-- Doc : docs/systems/interface.md (section "Fenetre FLOORS et NEW FLOOR!")

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Celebration = {}

local rng = Random.new()

local CONFETTI_COUNT = 70
local CONFETTI_SECONDS = 3.2
local DEFAULT_COLORS = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(80, 220, 110),
	Color3.fromRGB(70, 170, 255),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 255, 255),
}

local function pick(colors: { Color3 }?): Color3
	local list = if colors and #colors > 0 then colors else DEFAULT_COLORS
	return list[rng:NextInteger(1, #list)]
end

type Piece = {
	frame: Frame,
	x: number, -- position en fraction de l'ecran
	y: number,
	vx: number, -- vitesse (fraction d'ecran / s)
	vy: number,
	spin: number, -- degres / s
	sway: number, -- phase du balancement
	flip: number, -- vitesse du "retournement" (largeur qui oscille)
	width: number, -- pixels
	delay: number,
}

-- Confettis a l'ecran, au-dessus du reste (DisplayOrder 50).
function Celebration.Confetti(playerGui: Instance, colors: { Color3 }?)
	local screen = Instance.new("ScreenGui")
	screen.Name = "ConfettiFx"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 50
	local pieces: { Piece } = {}
	for i = 1, CONFETTI_COUNT do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = pick(colors)
		local width = rng:NextNumber(9, 15) -- pixels (taille fixe : pas deformee par l'ecran)
		frame.Size = UDim2.fromOffset(width, width * 1.8)
		if i % 3 == 0 then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0) -- quelques ronds
			corner.Parent = frame
		end
		frame.Position = UDim2.fromScale(-1, -1)
		frame.Parent = screen
		-- Deux canons (gauche et droite) qui tirent vers le haut et le centre, puis tout retombe
		local fromLeft = i % 2 == 0
		table.insert(pieces, {
			frame = frame,
			x = if fromLeft then rng:NextNumber(-0.02, 0.08) else rng:NextNumber(0.92, 1.02),
			y = rng:NextNumber(0.75, 1.0),
			vx = (if fromLeft then 1 else -1) * rng:NextNumber(0.15, 0.55),
			vy = -rng:NextNumber(0.9, 1.5),
			spin = rng:NextNumber(-360, 360),
			sway = rng:NextNumber(0, math.pi * 2),
			flip = rng:NextNumber(5, 10),
			width = width,
			delay = rng:NextNumber(0, 0.25),
		})
	end
	screen.Parent = playerGui

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		dt = math.min(dt, 1 / 20) -- pas de saut apres un gel d'image
		elapsed += dt
		local fade = math.clamp((CONFETTI_SECONDS - elapsed) / 0.8, 0, 1)
		for _, piece in pieces do
			local t = elapsed - piece.delay
			if t < 0 then
				continue
			end
			-- Gravite douce + frottement : montee rapide, puis chute lente qui flotte
			piece.vy += 1.1 * dt
			piece.vx *= (1 - 1.6 * dt)
			piece.vy = math.min(piece.vy, 0.32)
			piece.x += (piece.vx + math.sin(t * 3 + piece.sway) * 0.03) * dt
			piece.y += piece.vy * dt
			local frame = piece.frame
			frame.Position = UDim2.fromScale(piece.x, piece.y)
			frame.Rotation += piece.spin * dt
			-- Retournement : la largeur oscille (effet papier qui tourne sur lui-meme)
			local flip = math.abs(math.cos(t * piece.flip))
			frame.Size = UDim2.fromOffset(piece.width * (0.25 + 0.75 * flip), piece.width * 1.8)
			frame.BackgroundTransparency = 1 - fade
		end
		if elapsed >= CONFETTI_SECONDS then
			connection:Disconnect()
			screen:Destroy()
		end
	end)
end

-- Etincelles d'une explosion (texture d'etincelle de Roblox, frein, fondu).
local function burst(at: Vector3, color: Color3, folder: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "FireworkBurst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = folder
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(0.7, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(1.2, 1.8)
	sparks.Speed = NumberRange.new(28, 40)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 3.5 -- les etincelles freinent : boule qui s'ouvre en douceur
	sparks.Acceleration = Vector3.new(0, -9, 0) -- puis retombent un peu
	sparks.RotSpeed = NumberRange.new(-180, 180)
	sparks.Enabled = false
	sparks.Parent = attachment
	sparks:Emit(90)

	local glitter = sparks:Clone()
	glitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180))
	glitter.Size = NumberSequence.new(0.5, 0)
	glitter.Speed = NumberRange.new(10, 20)
	glitter.Lifetime = NumberRange.new(1.6, 2.4)
	glitter.Parent = attachment
	glitter:Emit(50)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 40
	light.Brightness = 6
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(anchor, 3)
end

-- Une fusee : petit neon avec une trainee qui monte en ralentissant, puis eclate.
local function rocket(from: Vector3, to: Vector3, color: Color3, folder: Instance, launchDelay: number)
	task.delay(launchDelay, function()
		if folder.Parent == nil then
			return
		end
		local head = Instance.new("Part")
		head.Name = "FireworkRocket"
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(0.8, 0.8, 0.8)
		head.Material = Enum.Material.Neon
		head.Color = color
		head.Anchored = true
		head.CanCollide = false
		head.CanQuery = false
		head.CanTouch = false
		head.CastShadow = false
		head.CFrame = CFrame.new(from)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.35, 0)
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.35, 0)
		a1.Parent = head
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Lifetime = 0.45
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = head
		head.Parent = folder
		local flight = rng:NextNumber(0.75, 0.95)
		local tween = TweenService:Create(head, TweenInfo.new(flight, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(to) })
		tween:Play()
		tween.Completed:Wait()
		if folder.Parent == nil then
			return
		end
		burst(to, color, folder)
		head.Transparency = 1
		Debris:AddItem(head, 0.5)
	end)
end

-- Feux d'artifice : les fusees partent du sol autour de `center` (ex. le sol du nouvel etage) et
-- eclatent a `height` studs au-dessus. `radius` = ecart des fusees (studs).
function Celebration.Fireworks(center: Vector3, colors: { Color3 }?, radius: number?, count: number?, height: number?)
	local folder = Instance.new("Folder")
	folder.Name = "FireworksFx"
	folder.Parent = workspace
	local spread = radius or 40
	local total = count or 7
	local top = height or 36
	for i = 1, total do
		local angle = (i / total) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * spread * rng:NextNumber(0.6, 1)
		local from = center + offset
		local to = center + offset * 0.8 + Vector3.new(0, rng:NextNumber(top * 0.7, top), 0)
		-- Par vagues : 2-3 fusees, puis les suivantes (plus agreable qu'un seul gros boum)
		rocket(from, to, pick(colors), folder, (i - 1) * 0.28 + rng:NextNumber(0, 0.1))
	end
	Debris:AddItem(folder, total * 0.28 + 5)
end

return Celebration
