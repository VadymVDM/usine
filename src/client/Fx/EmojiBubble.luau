--!strict
-- Bulle ronde avec un emoji au-dessus de la tete d'un client (CustomerController) : boule blanche a
-- contour fonce, deux petites bulles dessous (bulle de pensee), pastille rouge "?" en option.
-- Apparait avec un rebond (UIScale), disparait en se reduisant. Taille en studs : elle rapetisse
-- avec la distance comme le client. Le controleur decide quand la montrer / la cacher.
-- Doc : docs/systems/clients.md

local TweenService = game:GetService("TweenService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local EmojiBubble = {}

export type Bubble = {
	gui: BillboardGui,
	scale: UIScale,
	label: TextLabel,
	badge: Frame,
	shown: boolean,
	token: number,
}

local INK = Color3.fromRGB(40, 36, 52)
local SIZE_STUDS = 2.6
local HEIGHT_ABOVE_HEAD = 3.1 -- centre de la bulle au-dessus du centre de la tete (studs)
local MAX_DISTANCE = 90
local POP_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BUMP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Rond blanc a contour fonce (taille relative a la hauteur du parent : reste rond).
local function circle(parent: Instance, name: string, size: number, x: number, y: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(size, size)
	frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

function EmojiBubble.new(head: BasePart): Bubble
	local gui = Instance.new("BillboardGui")
	gui.Name = "EmojiBubble"
	gui.Size = UDim2.fromScale(SIZE_STUDS, SIZE_STUDS)
	gui.StudsOffsetWorldSpace = Vector3.new(0, HEIGHT_ABOVE_HEAD, 0)
	gui.MaxDistance = MAX_DISTANCE
	gui.LightInfluence = 0
	gui.AutoLocalize = false -- emojis : rien a traduire
	gui.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 1) -- le rebond part du bas (de la tete)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = root

	-- Petites bulles de pensee entre la tete et la boule
	circle(root, "DotSmall", 0.1, 0.42, 0.95)
	circle(root, "DotBig", 0.16, 0.47, 0.84)
	local ball = circle(root, "Ball", 0.74, 0.5, 0.39)

	local label = Instance.new("TextLabel")
	label.Name = "Emoji"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.53)
	label.Size = UDim2.fromScale(0.7, 0.7)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = INK
	label.Text = ""
	label.AutoLocalize = false
	label.Parent = ball

	-- Pastille "?" (comptoir vide : le client attend des jus)
	local badge = circle(ball, "Badge", 0.36, 0.88, 0.12)
	badge.BackgroundColor3 = Color3.fromRGB(235, 52, 52)
	badge.Visible = false
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.52)
	mark.Size = UDim2.fromScale(0.75, 0.75)
	mark.BackgroundTransparency = 1
	mark.TextScaled = true
	mark.Text = "?"
	mark.TextColor3 = Color3.new(1, 1, 1)
	mark.FontFace = PackStyle.FONT
	mark.AutoLocalize = false
	mark.Parent = badge

	root.Parent = gui
	gui.Parent = head
	return {
		gui = gui,
		scale = scale,
		label = label,
		badge = badge,
		shown = false,
		token = 0,
	}
end

-- Montre (ou change) l'emoji. Deja visible : petit rebond.
function EmojiBubble.Show(bubble: Bubble, emoji: string, badge: boolean)
	bubble.token += 1
	bubble.label.Text = emoji
	bubble.badge.Visible = badge
	bubble.gui.Enabled = true
	if bubble.shown then
		bubble.scale.Scale = 0.85
		TweenService:Create(bubble.scale, BUMP, { Scale = 1 }):Play()
	else
		bubble.shown = true
		bubble.scale.Scale = 0
		TweenService:Create(bubble.scale, POP_IN, { Scale = 1 }):Play()
	end
end

-- Cache la bulle (elle se reduit puis s'eteint).
function EmojiBubble.Hide(bubble: Bubble)
	if not bubble.shown then
		return
	end
	bubble.shown = false
	bubble.token += 1
	local token = bubble.token
	local tween = TweenService:Create(bubble.scale, POP_OUT, { Scale = 0 })
	tween.Completed:Connect(function()
		if bubble.token == token and bubble.gui.Parent then
			bubble.gui.Enabled = false
		end
	end)
	tween:Play()
end

return EmojiBubble
