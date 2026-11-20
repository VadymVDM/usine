--!strict
-- Classements : 2 grands murs-ecrans aux deux bouts de la route (style demande par l'utilisateur le
-- 2026-11-20, captures : cadre blanc a studs, ecran noir, 2 classements cote a cote).
--   WestWall : derriere la place du spawn, regarde vers l'est (MONEY + JUICES SOLD)
--   EastWall : au bout est de la route, regarde vers l'ouest (TIME PLAYED + ROBUX SPENT)
-- Chaque colonne : Map.Leaderboards.<Wall>.Screen.Display.<id> avec Title et Rows.Row1..RowN
-- (Rank, Avatar, PlayerName, Value) remplis par LeaderboardService.
-- A lancer dans Studio (mode Edit) apres 01 et 03 ; relancable (detruit et recree Map.Leaderboards).
-- Doc : docs/systems/classements.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function freshRequire(module: ModuleScript): any
	local copy = module:Clone()
	copy.Parent = module.Parent
	local result = require(copy) :: any
	copy:Destroy()
	return result
end
local Leaderboards = freshRequire(ReplicatedStorage.Shared.Config.Leaderboards)

-- Centre du pied de chaque mur et direction ou il regarde
local WALLS = {
	WestWall = { center = Vector3.new(-352, 0, 0), facing = Vector3.new(1, 0, 0) },
	EastWall = { center = Vector3.new(304, 0, 0), facing = Vector3.new(-1, 0, 0) },
}
local W, H, D = 66, 32, 3 -- mur : largeur (le long de z), hauteur, epaisseur
local B = 3 -- largeur du cadre blanc autour de l'ecran
local PPU = 25

local FRAME = Color3.fromRGB(214, 220, 230)
local SCREEN = Color3.fromRGB(16, 20, 30)
local DIVIDER = Color3.fromRGB(44, 52, 72)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(10, 10, 20)

local STUDS = Enum.SurfaceType.Studs
local INLET = Enum.SurfaceType.Inlet
local SMOOTH = Enum.SurfaceType.Smooth

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, surface: Enum.SurfaceType): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = surface
	p.BottomSurface = if surface == STUDS then INLET else surface
	p.FrontSurface = surface
	p.BackSurface = surface
	p.LeftSurface = surface
	p.RightSurface = surface
	p.Parent = parent
	return p
end

local function stroke(parent: Instance, thickness: number, color: Color3)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, color: Color3, strokePx: number, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.FontFace = FONT
	t.Text = value
	t.TextScaled = true
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	stroke(t, strokePx, TEXT_STROKE)
	t.Parent = parent
	return t
end

local function buildColumn(gui: SurfaceGui, board: any)
	local color: Color3 = board.color
	local column = Instance.new("Frame")
	column.Name = board.id
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromScale(if board.column == 1 then 0.035 else 0.525, 0.04)
	column.Size = UDim2.fromScale(0.44, 0.92)

	-- Titre : texte de la couleur du classement, sans fond (demande du 2026-11-20 : "retire le fond")
	local pill = Instance.new("Frame")
	pill.Name = "Title"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.Size = UDim2.fromScale(0.8, 0.14)
	pill.BackgroundTransparency = 1
	text(pill, "Text", board.title, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.9), color, 4)
	pill.Parent = column

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromScale(0, 0.18)
	rows.Size = UDim2.fromScale(1, 0.82)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows
	for i = 1, Leaderboards.Rows do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 1 / Leaderboards.Rows)
		text(row, "Rank", "#" .. i, UDim2.fromScale(0, 0.1), UDim2.fromScale(0.11, 0.8), Color3.new(1, 1, 1), 2, Enum.TextXAlignment.Right)
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
		avatar.Position = UDim2.fromScale(0.14, 0.1)
		avatar.Size = UDim2.fromScale(0.8, 0.8)
		avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
		avatar.Image = ""
		avatar.Visible = false
		corner(avatar, 0.5)
		avatar.Parent = row
		text(row, "PlayerName", if i == 1 then Leaderboards.EmptyRow else "---", UDim2.fromScale(0.25, 0.12), UDim2.fromScale(0.43, 0.76), Color3.new(1, 1, 1), 2, Enum.TextXAlignment.Left)
		text(row, "Value", "", UDim2.fromScale(0.69, 0.12), UDim2.fromScale(0.31, 0.76), color, 2, Enum.TextXAlignment.Right)
		row.Parent = rows
	end
	rows.Parent = column
	column.Parent = gui
end

local map = workspace:FindFirstChild("Map")
assert(map, "Lancer 01-ground-road d'abord")
local old = map:FindFirstChild("Leaderboards")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Leaderboards"

for wallName, spot in WALLS do
	-- Repere local : X le long du mur, Y vers le haut, -Z = devant (ecran)
	local root = CFrame.lookAt(spot.center, spot.center + spot.facing)
	local function at(lx: number, ly: number, lz: number): CFrame
		return root * CFrame.new(lx, ly, lz)
	end
	local wall = Instance.new("Model")
	wall.Name = wallName

	-- Cadre blanc a studs (4 pieces) ; dos et ecran dans l'ouverture (aucune face en commun)
	part(wall, "FrameBottom", Vector3.new(W, B, D), at(0, B / 2, 0), FRAME, STUDS)
	part(wall, "FrameTop", Vector3.new(W, B, D), at(0, H - B / 2, 0), FRAME, STUDS)
	part(wall, "FrameLeft", Vector3.new(B, H - 2 * B, D), at(-(W - B) / 2, H / 2, 0), FRAME, STUDS)
	part(wall, "FrameRight", Vector3.new(B, H - 2 * B, D), at((W - B) / 2, H / 2, 0), FRAME, STUDS)
	part(wall, "Backing", Vector3.new(W - 2 * B, H - 2 * B, 1), at(0, H / 2, D / 2 - 0.5), FRAME, STUDS)
	local screen = part(wall, "Screen", Vector3.new(W - 2 * B, H - 2 * B, 0.4), at(0, H / 2, D / 2 - 1.2), SCREEN, SMOOTH)
	screen.Material = Enum.Material.SmoothPlastic

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPU
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BorderSizePixel = 0
	divider.BackgroundColor3 = DIVIDER
	divider.Position = UDim2.fromScale(0.4985, 0.06)
	divider.Size = UDim2.fromScale(0.003, 0.88)
	divider.Parent = gui
	for _, board in Leaderboards.Boards do
		if board.wall == wallName then
			buildColumn(gui, board)
		end
	end
	gui.Parent = screen

	wall.Parent = folder
end

folder.Parent = map
return "Leaderboards OK : 2 murs"
