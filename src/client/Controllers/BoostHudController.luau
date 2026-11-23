--!strict
-- Boosts Robux en cours (2026-11-20) : une petite potion par boost actif, en ligne tout en bas a
-- droite de l'ecran (HUD.Canvas.Boosts, deplace le 2026-11-22) : "x2" jaune + temps restant. Lit seulement les attributs joueur
-- poses par le serveur (RobuxShopService) : "Boost<Stat>" (multiplicateur) et "Boost<Stat>End"
-- (fin, en workspace:GetServerTimeNow). Aucune decision ici.
-- Aussi : tag "[VIP]" dore devant le nom dans le chat pour les joueurs qui ont le pass VIP
-- (attribut joueur "VIP", meme couleur que le nametag, Lib/NameTag).
-- Doc : docs/systems/achats-robux.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local BoostHudController = {}

local player = Players.LocalPlayer
local STAT_ICONS = { Money = "PotionGreen", Luck = "PotionBlue", Speed = "PotionPurple" }
local MULT_YELLOW = Color3.fromRGB(255, 225, 40)
local VIP_COLOR = "#FFC81E"

type Tile = { frame: Frame, mult: TextLabel, timer: TextLabel }

local tiles: { [string]: Tile } = {}

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

local function makeTile(row: Frame, stat: string, order: number, icons: { [string]: string }): Tile
	local frame = Instance.new("Frame")
	frame.Name = stat
	frame.LayoutOrder = order
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.Size = UDim2.fromScale(1, 1)
	frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	frame.Visible = false
	PackStyle.stroke(frame, 2, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = frame
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.02)
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = icons[STAT_ICONS[stat] or ""] or ""
	icon.ZIndex = 2
	icon.Parent = frame
	local mult = PackStyle.label(frame, "x2", UDim2.fromScale(0.72, 0.0), UDim2.fromScale(0.6, 0.38), 40)
	mult.Rotation = -10
	mult.TextColor3 = MULT_YELLOW
	mult.ZIndex = 5
	local timer = PackStyle.label(frame, "", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.96, 0.28), 30)
	timer.ZIndex = 5
	frame.Parent = row
	return { frame = frame, mult = mult, timer = timer }
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	for stat, tile in tiles do
		local mult = player:GetAttribute("Boost" .. stat)
		local finish = player:GetAttribute("Boost" .. stat .. "End")
		local active = type(mult) == "number" and type(finish) == "number" and finish > now
		tile.frame.Visible = active
		if active then
			tile.mult.Text = "x" .. tostring(mult)
			tile.timer.Text = formatTime((finish :: number) - now)
		end
	end
end

local function setupChatTag()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		local speaker = if source then Players:GetPlayerByUserId(source.UserId) else nil
		if speaker and speaker:GetAttribute("VIP") == true then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = `<font color="{VIP_COLOR}">[VIP]</font> ` .. message.PrefixText
			return properties
		end
		return nil
	end
end

function BoostHudController:Init() end

function BoostHudController:Start()
	local ok, err = pcall(setupChatTag)
	if not ok then
		warn(`[BoostHud] tag VIP du chat : {err}`)
	end
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	local shop = require(config:WaitForChild("Shop")) :: any
	local icons = require(config:WaitForChild("Icons")) :: any
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
	local canvas = hud:WaitForChild("Canvas", 15)
	if canvas == nil then
		warn("[BoostHud] HUD.Canvas introuvable")
		return
	end
	local row = Instance.new("Frame")
	row.Name = "Boosts"
	row.BackgroundTransparency = 1
	-- Tout en bas a droite, sous la colonne des offres. Telephone : decale a gauche pour laisser
	-- libre le bouton de saut (coin bas droit).
	local camera = workspace.CurrentCamera
	local phone = camera ~= nil and camera.ViewportSize.Y < 450
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = if phone then UDim2.fromScale(0.74, 0.98) else UDim2.fromScale(0.992, 0.985)
	row.Size = UDim2.fromScale(0.4, 0.085)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	for index, stat in shop.BoostStats do
		tiles[stat] = makeTile(row, stat, index, icons)
	end
	row.Parent = canvas
	refresh()
	task.spawn(function()
		while row.Parent do
			task.wait(0.5)
			refresh()
		end
	end)
end

return BoostHudController
