--!strict
-- Contours des panneaux 3D (BillboardGui) proportionnels au panneau.
-- Un BillboardGui en studs grandit et rapetisse avec la distance, mais un UIStroke en pixels fixes
-- garde la meme epaisseur : de loin le panneau devient tout noir, de pres le contour disparait.
-- Ce controleur passe chaque contour en StrokeSizingMode.ScaledSize (fraction du plus petit cote
-- de son parent), avec l'epaisseur qu'il avait quand le panneau est vu a la distance "ideale"
-- (PIXELS_PER_STUD). Le rendu est alors le meme a toutes les distances.
-- Concerne les panneaux construits en pixels fixes (cartes des pads, zones verrouillees...).
-- Doc : docs/systems/interface.md

local BillboardStrokeController = {}

-- Pixels par stud a la distance ou les panneaux ont ete regles (environ 18 studs, ecran de 580 px).
local PIXELS_PER_STUD = 25

-- Taille en pixels d'un element du panneau quand celui-ci est vu a la distance ideale.
local function referenceSize(gui: Instance): Vector2?
	if gui:IsA("BillboardGui") then
		local size = gui.Size
		return Vector2.new(
			size.X.Scale * PIXELS_PER_STUD + size.X.Offset,
			size.Y.Scale * PIXELS_PER_STUD + size.Y.Offset
		)
	end
	if not gui:IsA("GuiObject") then
		return nil
	end
	local parent = gui.Parent
	if parent == nil then
		return nil
	end
	local parentSize = referenceSize(parent)
	if parentSize == nil then
		return nil
	end
	local base = parentSize
	if gui.SizeConstraint == Enum.SizeConstraint.RelativeXX then
		base = Vector2.new(parentSize.X, parentSize.X)
	elseif gui.SizeConstraint == Enum.SizeConstraint.RelativeYY then
		base = Vector2.new(parentSize.Y, parentSize.Y)
	end
	local size = gui.Size
	return Vector2.new(base.X * size.X.Scale + size.X.Offset, base.Y * size.Y.Scale + size.Y.Offset)
end

local function convert(stroke: UIStroke)
	if stroke.StrokeSizingMode ~= Enum.StrokeSizingMode.FixedSize then
		return -- deja proportionnel (ex. WorldLabel)
	end
	if stroke:FindFirstAncestorWhichIsA("BillboardGui") == nil then
		return
	end
	local parent = stroke.Parent
	if parent == nil then
		return
	end
	local size = referenceSize(parent)
	if size == nil then
		return
	end
	local smallest = math.min(size.X, size.Y)
	if smallest <= 0 then
		return
	end
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = stroke.Thickness / smallest
end

function BillboardStrokeController:Init() end

function BillboardStrokeController:Start()
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("UIStroke") then
			convert(descendant)
		end
	end)
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("UIStroke") then
			convert(descendant)
		end
	end
end

return BillboardStrokeController
