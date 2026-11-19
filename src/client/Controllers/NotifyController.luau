--!strict
-- Affiche les messages du serveur (remote Notify) en haut de l'ecran, au style de l'interface
-- (PackStyle : texte blanc, contour fonce). Un nouveau message remplace le precedent.
-- Doc : docs/systems/carte-bases.md, docs/systems/interface.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map"))
local TextUtil = require(Shared:WaitForChild("Util"):WaitForChild("TextUtil"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))

local SHOW_SECONDS = 3.5
local FADE_SECONDS = 0.4

local NotifyController = {}

local label: TextLabel? = nil
local labelStroke: UIStroke? = nil
local showToken = 0
local fadeTweens: { Tween } = {}

local function cancelFade()
	for _, tween in fadeTweens do
		tween:Cancel()
	end
	table.clear(fadeTweens)
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "NotifyGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Tout en haut au centre : au-dessus des fenetres (Welcome Back) et loin des boutons du HUD
	local text = PackStyle.label(gui, "", UDim2.fromScale(0.5, 0.03), UDim2.fromScale(0.7, 0.065), 40)
	text.Name = "Message"
	text.Visible = false
	label = text
	labelStroke = text:FindFirstChildOfClass("UIStroke")
	gui.Parent = playerGui
end

local function show(message: string)
	local text = label
	if text == nil then
		return
	end
	showToken += 1
	local token = showToken
	cancelFade() -- sinon le fondu du message precedent efface le nouveau
	text.Text = message
	text.TextTransparency = 0
	if labelStroke then
		labelStroke.Transparency = 0
	end
	text.Visible = true
	task.delay(SHOW_SECONDS, function()
		if token ~= showToken then
			return
		end
		local info = TweenInfo.new(FADE_SECONDS)
		table.insert(fadeTweens, TweenService:Create(text, info, { TextTransparency = 1 }))
		if labelStroke then
			table.insert(fadeTweens, TweenService:Create(labelStroke, info, { Transparency = 1 }))
		end
		for _, tween in fadeTweens do
			tween:Play()
		end
		task.wait(FADE_SECONDS)
		if token == showToken then
			text.Visible = false
		end
	end)
end

function NotifyController:Init() end

function NotifyController:Start()
	buildGui()
	local event = Remotes.WaitClientEvent("Notify")
	if event == nil then
		return
	end
	event.OnClientEvent:Connect(function(message: any)
		-- Le serveur n'envoie que du texte de la Config ; on verifie quand meme type et longueur.
		if typeof(message) ~= "string" then
			return
		end
		local text = TextUtil.Truncate(message, MapConfig.MaxNotifyLength)
		if text then
			show(text)
		end
	end)
end

return NotifyController
