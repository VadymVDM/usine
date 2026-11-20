--!strict
-- Barre de defilement a droite de chaque liste qui defile dans ShopGUI (Shop, Index, Upgrade,
-- Settings, Trade...). On peut la glisser a la souris ou au doigt, ou cliquer / toucher le rail
-- pour sauter a cet endroit. La molette et le glisser sur le contenu marchent toujours.
-- Les barres vivent dans un calque a part (ScreenGui "ScrollBars", juste au-dessus de ShopGUI)
-- et suivent chaque image la position a l'ecran de leur liste : elles suivent donc l'animation
-- d'ouverture des menus sans toucher aux mises en page du pack (UIListLayout).
-- Cachee si la liste ne depasse pas (rien a faire defiler) ou si son menu est ferme.
-- Doc : docs/systems/interface.md (section Barres de defilement)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")


local ScrollBarController = {}

-- Barre = un simple rectangle blanc arrondi, long, un peu transparent (pas de rail, pas de contour).
local THUMB_COLOR = Color3.fromRGB(255, 255, 255)
local THUMB_TRANSPARENCY = 0.45
local THUMB_DRAG_TRANSPARENCY = 0.15 -- plus net pendant qu'on le tient
local EDGE_INSET = 5 -- pixels entre la barre et le bord droit de la liste
local MIN_THUMB = 70 -- hauteur minimum du curseur (pixels) : long, facile a prendre au doigt
local HIT_EXTRA = 10 -- zone de prise plus large que la barre, de chaque cote (doigt)

type Bar = {
	scroll: ScrollingFrame,
	hit: TextButton,
	track: Frame,
	thumb: Frame,
	padded: boolean,
}

local player = Players.LocalPlayer
local bars: { [ScrollingFrame]: Bar } = {}
local overlay: ScreenGui
local shopGUI: ScreenGui
local barWidth = 12
local started = false

-- Glisser en cours : barre, entree suivie (souris ou doigt), ecart entre le doigt et le haut du curseur.
local dragging: { bar: Bar, input: InputObject?, grab: number }? = nil

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Vrai si la liste et tous ses parents jusqu'au ScreenGui sont visibles.
local function isShown(scroll: ScrollingFrame): boolean
	local current: Instance? = scroll
	while current and current ~= shopGUI do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == shopGUI and shopGUI.Enabled
end

local function maxScroll(scroll: ScrollingFrame): number
	return math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
end

local function thumbHeight(bar: Bar): number
	local scroll = bar.scroll
	local trackHeight = bar.track.AbsoluteSize.Y
	local ratio = scroll.AbsoluteWindowSize.Y / math.max(1, scroll.AbsoluteCanvasSize.Y)
	return math.clamp(trackHeight * ratio, math.min(MIN_THUMB, trackHeight), trackHeight)
end

-- Place la liste pour que le haut du curseur soit a `thumbTop` pixels du haut du rail.
local function scrollToThumb(bar: Bar, thumbTop: number)
	local free = bar.track.AbsoluteSize.Y - thumbHeight(bar)
	local alpha = if free > 0 then math.clamp(thumbTop / free, 0, 1) else 0
	local scroll = bar.scroll
	scroll.CanvasPosition = Vector2.new(scroll.CanvasPosition.X, alpha * maxScroll(scroll))
end

local function setDragColor(bar: Bar, active: boolean)
	bar.thumb.BackgroundTransparency = if active then THUMB_DRAG_TRANSPARENCY else THUMB_TRANSPARENCY
end

local function stopDrag()
	if dragging then
		setDragColor(dragging.bar, false)
		dragging = nil
	end
end

local function build(scroll: ScrollingFrame): Bar
	-- Zone de prise invisible (plus large que la barre visible, pour le doigt)
	local hit = Instance.new("TextButton")
	hit.Name = "ScrollBar"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Selectable = false
	hit.Visible = false

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromScale(0.5, 0)
	track.Size = UDim2.new(0, barWidth, 1, 0)
	track.BackgroundTransparency = 1 -- rail invisible : il sert seulement a mesurer
	track.Parent = hit

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.new(1, 0, 0, MIN_THUMB)
	thumb.BackgroundColor3 = THUMB_COLOR
	thumb.BackgroundTransparency = THUMB_TRANSPARENCY
	thumb.BorderSizePixel = 0
	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb
	thumb.Parent = track

	hit.Parent = overlay

	local bar: Bar = { scroll = scroll, hit = hit, track = track, thumb = thumb, padded = false }

	hit.InputBegan:Connect(function(input: InputObject)
		if not isPress(input) or dragging then
			return
		end
		local pointerY = input.Position.Y - track.AbsolutePosition.Y
		local thumbTop = thumb.AbsolutePosition.Y - track.AbsolutePosition.Y
		local height = thumb.AbsoluteSize.Y
		local grab = pointerY - thumbTop
		if grab < 0 or grab > height then
			-- Clic sur le rail : le curseur saute sous le doigt (centre), puis on glisse
			grab = height / 2
			scrollToThumb(bar, pointerY - grab)
		end
		dragging = {
			bar = bar,
			input = if input.UserInputType == Enum.UserInputType.Touch then input else nil,
			grab = grab,
		}
		setDragColor(bar, true)
	end)
	return bar
end

local function watch(scroll: Instance)
	if not scroll:IsA("ScrollingFrame") or bars[scroll] then
		return
	end
	bars[scroll] = build(scroll)
	scroll.AncestryChanged:Connect(function()
		if not scroll:IsDescendantOf(shopGUI) then
			local bar = bars[scroll]
			if bar then
				if dragging and dragging.bar == bar then
					stopDrag()
				end
				bar.hit:Destroy()
				bars[scroll] = nil
			end
		end
	end)
end

-- Laisse de la place a droite du contenu pour la barre (une seule fois, quand la liste depasse).
local function reserveSpace(bar: Bar)
	if bar.padded then
		return
	end
	bar.padded = true
	local padding = bar.scroll:FindFirstChildOfClass("UIPadding")
	if padding == nil then
		local created = Instance.new("UIPadding")
		created.Parent = bar.scroll
		padding = created
	end
	local p = padding :: UIPadding
	p.PaddingRight = UDim.new(p.PaddingRight.Scale, p.PaddingRight.Offset + barWidth + EDGE_INSET * 2)
end

local function update()
	if overlay.DisplayOrder ~= shopGUI.DisplayOrder + 1 then
		overlay.DisplayOrder = shopGUI.DisplayOrder + 1
	end
	local origin = overlay.AbsolutePosition
	for scroll, bar in bars do
		local scrollable = maxScroll(scroll) > 1
		local show = scrollable and isShown(scroll)
		if bar.hit.Visible ~= show then
			bar.hit.Visible = show
			if not show and dragging and dragging.bar == bar then
				stopDrag()
			end
		end
		if not show then
			continue
		end
		reserveSpace(bar)
		local pos = scroll.AbsolutePosition - origin
		local size = scroll.AbsoluteWindowSize
		local inset = math.max(EDGE_INSET, math.floor(size.Y * 0.02))
		local hitWidth = barWidth + HIT_EXTRA * 2
		bar.hit.Position = UDim2.fromOffset(pos.X + size.X - EDGE_INSET - barWidth / 2 - hitWidth / 2, pos.Y + inset)
		bar.hit.Size = UDim2.fromOffset(hitWidth, size.Y - inset * 2)
		local height = thumbHeight(bar)
		local free = bar.track.AbsoluteSize.Y - height
		local alpha = scroll.CanvasPosition.Y / math.max(1, maxScroll(scroll))
		bar.thumb.Size = UDim2.new(1, 0, 0, height)
		bar.thumb.Position = UDim2.fromOffset(0, math.clamp(alpha, 0, 1) * free)
	end
end

function ScrollBarController:Init() end

function ScrollBarController:Start()
	if started then
		return
	end
	started = true
	local playerGui = player:WaitForChild("PlayerGui")
	shopGUI = playerGui:WaitForChild("ShopGUI") :: ScreenGui

	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	barWidth = math.floor(math.clamp(height * 0.014, 7, 11))

	overlay = Instance.new("ScreenGui")
	overlay.Name = "ScrollBars"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = shopGUI.IgnoreGuiInset
	overlay.ScreenInsets = shopGUI.ScreenInsets
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.DisplayOrder = shopGUI.DisplayOrder + 1
	overlay.Parent = playerGui

	for _, item in shopGUI:GetDescendants() do
		watch(item)
	end
	shopGUI.DescendantAdded:Connect(watch)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = dragging
		if drag == nil then
			return
		end
		local follows = if drag.input
			then input == drag.input
			else input.UserInputType == Enum.UserInputType.MouseMovement
		if follows then
			local bar = drag.bar
			scrollToThumb(bar, input.Position.Y - bar.track.AbsolutePosition.Y - drag.grab)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = dragging
		if drag == nil then
			return
		end
		if (drag.input and input == drag.input) or (drag.input == nil and input.UserInputType == Enum.UserInputType.MouseButton1) then
			stopDrag()
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return ScrollBarController
