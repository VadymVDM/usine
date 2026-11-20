--!strict
-- Effet pendant la fenetre d'achat Roblox (Robux), pour donner envie d'acheter (2026-11-20) :
--   * contour de l'ecran arc-en-ciel qui tourne, avec un halo plus doux vers l'interieur, qui pulse ;
--   * petites etincelles blanches qui scintillent le long du bord ;
--   * la camera se rapproche un peu du joueur (zoom), puis revient a la fermeture.
-- Show() : a appeler juste apres MarketplaceService:Prompt...Purchase (client : Donation, Offres ;
-- serveur : Feedback "PurchasePrompt" envoye par Lib/PurchasePrompt, ecoute par PurchaseFxController).
-- Fin : fenetre fermee (Prompt*PurchaseFinished cote client), ou au bout de MAX_SECONDS.
-- Zoom : la camera est avancee vers sa cible APRES le script de camera de Roblox, chaque image
-- (comme un tremblement de camera) : rien ne s'accumule et le FieldOfView des menus n'est pas touche.
-- Rien si la camera est Scriptable (menus avec camera fixe) : sinon le decalage s'additionnerait.
-- Doc : docs/systems/interface.md (section "Envie d'acheter")

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PurchaseFx = {}

local MAX_SECONDS = 60 -- securite si l'evenement de fin n'arrive jamais
local FADE_IN = 0.25
local FADE_OUT = 0.35
local ZOOM_IN = 0.45 -- secondes pour arriver au zoom
local ZOOM_SHARE = 0.28 -- part de la distance camera -> joueur gagnee au zoom
local ZOOM_MAX = 9 -- studs au maximum
local SPIN_SPEED = 90 -- degres par seconde (rotation des couleurs)
local SPARK_COUNT = 14
local RENDER_NAME = "PurchaseFxZoom"

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 40, 80)),
	ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 150, 20)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 235, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 230, 90)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(30, 190, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(150, 70, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 80)),
})

type Spark = { frame: Frame, phase: number, speed: number }

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local strokes: { { stroke: UIStroke, gradient: UIGradient, base: number, alpha: number } } = {}
local sparks: { Spark } = {}
local active = false
local level = 0 -- 0 -> 1 (apparition / disparition)
local zoom = 0 -- 0 -> 1
local shownAt = 0
local renderBound = false
local listening = false

local function makeBorder(parent: ScreenGui, name: string, inset: number, thickness: number, alpha: number)
	-- Le trait (UIStroke) est dessine a l'exterieur du cadre : cadre en retrait de `inset` pixels
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromOffset(inset, inset)
	frame.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Thickness = thickness
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 1
	local gradient = Instance.new("UIGradient")
	gradient.Color = RAINBOW
	gradient.Parent = stroke
	stroke.Parent = frame
	frame.Parent = parent
	table.insert(strokes, { stroke = stroke, gradient = gradient, base = thickness, alpha = alpha })
end

local function build(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	table.clear(strokes)
	table.clear(sparks)
	local screen = Instance.new("ScreenGui")
	screen.Name = "PurchaseFx"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 1000
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	-- Trait net au bord + halo plus large et transparent vers l'interieur
	makeBorder(screen, "Border", 9, 9, 0)
	makeBorder(screen, "Glow", 34, 25, 0.6)
	for i = 1, SPARK_COUNT do
		local spark = Instance.new("Frame")
		spark.Name = "Spark"
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.BackgroundColor3 = Color3.new(1, 1, 1)
		spark.BorderSizePixel = 0
		spark.Rotation = 45
		spark.Size = UDim2.fromOffset(10, 10)
		spark.BackgroundTransparency = 1
		spark.ZIndex = 2
		spark.Parent = screen
		table.insert(sparks, { frame = spark, phase = (i - 1) / SPARK_COUNT, speed = 0.6 + (i % 3) * 0.25 })
	end
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	return screen
end

-- Position d'une etincelle sur le tour de l'ecran (t de 0 a 1), un peu a l'interieur du bord
local function edgePoint(t: number, size: Vector2): UDim2
	local pad = 20
	local w, h = size.X - 2 * pad, size.Y - 2 * pad
	local d = (t % 1) * 2 * (w + h)
	if d < w then
		return UDim2.fromOffset(pad + d, pad)
	end
	d -= w
	if d < h then
		return UDim2.fromOffset(pad + w, pad + d)
	end
	d -= h
	if d < w then
		return UDim2.fromOffset(pad + w - d, pad + h)
	end
	d -= w
	return UDim2.fromOffset(pad, pad + h - d)
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- Ressort qui depasse un peu puis revient (zoom "pop")
local function backOut(x: number): number
	local c = 1.7
	return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
end

local function step(dt: number)
	local now = os.clock()
	if active and now - shownAt > MAX_SECONDS then
		active = false
	end
	if active then
		level = math.min(1, level + dt / FADE_IN)
		zoom = math.min(1, zoom + dt / ZOOM_IN)
	else
		level = math.max(0, level - dt / FADE_OUT)
		zoom = math.max(0, zoom - dt / FADE_OUT)
	end
	local screen = gui
	-- Contour et etincelles
	if screen then
		if level <= 0 and not active then
			screen.Enabled = false
		else
			screen.Enabled = true
			local fade = smooth(level)
			local pulse = 1 + 0.18 * math.sin(now * 7)
			for i, info in strokes do
				info.stroke.Transparency = 1 - fade * (1 - info.alpha)
				info.stroke.Thickness = info.base * pulse * (0.6 + 0.4 * fade)
				info.gradient.Rotation = (now * SPIN_SPEED + (i - 1) * 40) % 360
			end
			local size = screen.AbsoluteSize
			for _, spark in sparks do
				local t = spark.phase + now * 0.04 * spark.speed
				local twinkle = 0.5 + 0.5 * math.sin(now * 6 * spark.speed + spark.phase * 20)
				spark.frame.Position = edgePoint(t, size)
				local px = 4 + 10 * twinkle
				spark.frame.Size = UDim2.fromOffset(px, px)
				spark.frame.BackgroundTransparency = 1 - fade * (0.3 + 0.7 * twinkle)
			end
		end
	end
	-- Zoom : la camera avance vers sa cible (apres le script de camera de Roblox)
	local camera = workspace.CurrentCamera
	if zoom > 0 and camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		local eased = if active then backOut(zoom) else smooth(zoom)
		local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		local offset = math.min(distance * ZOOM_SHARE, ZOOM_MAX) * eased
		if offset > 0.01 then
			camera.CFrame *= CFrame.new(0, 0, -offset)
		end
	end
	if level <= 0 and zoom <= 0 and not active and renderBound then
		renderBound = false
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end
end

function PurchaseFx.Hide()
	active = false
end

local function listen()
	if listening then
		return
	end
	listening = true
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number)
		if userId == player.UserId then
			PurchaseFx.Hide()
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player)
		if who == player then
			PurchaseFx.Hide()
		end
	end)
	MarketplaceService.PromptPurchaseFinished:Connect(function(who: Player)
		if who == player then
			PurchaseFx.Hide()
		end
	end)
end

-- Montre l'effet (fenetre d'achat Roblox qui vient de s'ouvrir).
function PurchaseFx.Show()
	listen()
	build()
	active = true
	shownAt = os.clock()
	if not renderBound then
		renderBound = true
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, step)
	end
end

return PurchaseFx
