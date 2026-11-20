--!strict
-- Nametag au-dessus de la tete des joueurs (demande utilisateur du 2026-11-20) : le pseudo
-- (DisplayName, comme Roblox) et, dessous, "Rebirth N" en or des le premier rebirth.
--   * Remplace le nom affiche par Roblox (Humanoid.DisplayDistanceType = None) : pas de double nom.
--   * Visible seulement par les AUTRES joueurs (BillboardGui.PlayerToHideFrom = le joueur), comme
--     le nom de Roblox : on ne voit jamais son propre nametag.
-- Cree par le serveur (vu par tout le monde) ; appele par RebirthService a chaque apparition du
-- personnage et apres un rebirth. Pass VIP (attribut joueur "VIP", RobuxShopService) : "[VIP]" dore
-- devant le pseudo (RobuxShopService rappelle Apply quand le pass arrive).
-- Doc : docs/systems/rebirth.md (section Nametag)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rebirth = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Rebirth"))

local NameTag = {}

local NAME = "NameTag"
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(30, 22, 40) -- = PackStyle.TEXT_STROKE (style du jeu)
local RANK_STROKE = Color3.fromRGB(70, 40, 0)
local VIP_COLOR = "#FFC81E" -- or du tag VIP (meme couleur que le tag du chat, ChatTagController)

local function makeLabel(parent: Instance, name: string, color: Color3, stroke: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Thickness = 2
	uiStroke.Color = stroke
	uiStroke.Parent = label
	label.Parent = parent
	return label
end

-- Pose ou met a jour le nametag du personnage. `rebirths` = 0 : seulement le pseudo.
function NameTag.Apply(player: Player, rebirths: number)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if character == nil or head == nil or not head:IsA("BasePart") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local gui = head:FindFirstChild(NAME)
	if gui == nil or not gui:IsA("BillboardGui") then
		local created = Instance.new("BillboardGui")
		created.Name = NAME
		created.Size = UDim2.fromScale(Rebirth.NameTagWidth, Rebirth.NameTagHeight)
		created.StudsOffset = Vector3.new(0, Rebirth.NameTagLift, 0)
		created.MaxDistance = Rebirth.NameTagMaxDistance
		created.LightInfluence = 0
		created.PlayerToHideFrom = player
		makeLabel(created, "PlayerName", Color3.new(1, 1, 1), TEXT_STROKE)
		makeLabel(created, "Rank", Rebirth.TitleColor, RANK_STROKE)
		created.Parent = head
		gui = created
	end
	local nameLabel = gui:FindFirstChild("PlayerName") :: TextLabel?
	local rankLabel = gui:FindFirstChild("Rank") :: TextLabel?
	local hasRank = rebirths >= 1
	if nameLabel then
		nameLabel.RichText = true
		local vip = if player:GetAttribute("VIP") == true then `<font color="{VIP_COLOR}">[VIP]</font> ` else ""
		nameLabel.Text = vip .. player.DisplayName
		-- Sans rang : le pseudo descend en bas du nametag (juste au-dessus de la tete)
		nameLabel.Position = if hasRank then UDim2.fromScale(0.5, 0) else UDim2.fromScale(0.5, 0.45)
		nameLabel.Size = UDim2.fromScale(1, 0.55)
	end
	if rankLabel then
		rankLabel.Visible = hasRank
		rankLabel.Text = string.format(Rebirth.Texts.Title, rebirths)
		rankLabel.Position = UDim2.fromScale(0.5, 0.55)
		rankLabel.Size = UDim2.fromScale(1, 0.45)
	end
end

return NameTag
