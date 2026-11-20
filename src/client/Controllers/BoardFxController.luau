--!strict
-- Boutons des tuiles des panneaux d'ameliorations : animations de survol et de clic + curseur
-- normal. Seuls les BOUTONS bougent, pas toute la tuile (demandes du 2026-11-20 : "pas d'animation
-- de hover et de clic", "la souris est une main au lieu du curseur", "c'est les boutons qui doivent
-- hover, pas toute l'interface"). Client seulement : l'achat reste dans BuyController / le serveur.
--   * survol (souris) : le bouton vert (ou violet) grossit (ressort "gelee", UIScale "Scale") ;
--   * appui (souris / doigt) : il s'ecrase (son TileClick), puis rebondit au relachement ;
--   * achat (compteur "Bought" du serveur) : le bouton vert rebondit ; refus ("Denied") : il
--     devient rouge un instant ;
--   * curseur : les ClickDetector des bases montrent la fleche normale au lieu de la main.
-- Seulement SA base. Bouton = Part invisible "BuyButton" / "RobuxButton" (ClickDetector) d'une tuile
-- (parent avec l'attribut UpgradeId ou TowerUpgradeId) ; dessin = Tile.Display.BuyBox / RobuxBox
-- (Shared/Util/UpgradeTile).
-- Doc : docs/systems/ameliorations-employes.md (section Panneaux)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SoundFx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))

local BoardFxController = {}

local ARROW_CURSOR = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png"
local HOVER = 0.12 -- +12 % au survol
local PRESS = -0.1 -- -10 % pendant l'appui
local RELEASE_KICK = 1.8 -- rebond au relachement
local BOUGHT_KICK = 3 -- gros rebond a l'achat
local DENIED_KICK = -1.5
local MAX_DISTANCE = 60 -- studs : au-dela, pas de survol
local DENY_COLOR = Color3.fromRGB(255, 60, 60)
local BOX_OF = { BuyButton = "BuyBox", RobuxButton = "RobuxBox" }

type Spring = typeof(Jelly.Spring(1, 1))

type ButtonFx = {
	part: BasePart,
	model: Instance,
	box: Frame,
	uiScale: UIScale,
	spring: Spring,
	connections: { RBXScriptConnection },
}

local player = Players.LocalPlayer
local buttons: { [BasePart]: ButtonFx } = {}
local moving: { [ButtonFx]: boolean } = {}
local hovered: ButtonFx? = nil
local pressed: ButtonFx? = nil
local started = false

-- Base (Workspace.Bases.BaseN) qui contient l'objet
local function baseOf(item: Instance): Instance?
	local current: Instance? = item
	while current and current.Parent do
		if current.Parent.Name == "Bases" and current.Parent.Parent == workspace then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isMine(item: Instance): boolean
	local base = baseOf(item)
	return base ~= nil and base:GetAttribute("OwnerUserId") == player.UserId
end

---------------------------------------------------------------------------------------------
-- Rendu

local function setTargets()
	for _, fx in buttons do
		local target = if fx == pressed then PRESS elseif fx == hovered then HOVER else 0
		if fx.spring.target ~= target then
			fx.spring.target = target
			moving[fx] = true
		end
	end
end

local function onRender(dt: number)
	for fx in moving do
		if fx.part.Parent == nil then
			moving[fx] = nil
			continue
		end
		Jelly.Step(fx.spring, dt)
		if Jelly.Resting(fx.spring) then
			fx.spring.x, fx.spring.v = fx.spring.target, 0
			moving[fx] = nil
		end
		fx.uiScale.Scale = math.max(1 + fx.spring.x, 0.5)
	end
end

---------------------------------------------------------------------------------------------
-- Bouton sous un point de l'ecran (le rayon traverse les autres pieces invisibles)

local function buttonAt(ray: Ray): ButtonFx?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	for _ = 1, 6 do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
		if result == nil then
			return nil
		end
		local part = result.Instance
		local fx = buttons[part]
		if fx == nil then
			if part.Transparency >= 1 or part.LocalTransparencyModifier >= 1 then
				table.insert(ignore, part)
				continue
			end
			return nil
		end
		if part.LocalTransparencyModifier >= 1 then
			return nil -- panneau cache (mixeur verrouille)
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - part.Position).Magnitude > MAX_DISTANCE then
			return nil
		end
		return if isMine(fx.model) then fx else nil
	end
	return nil
end

local function updateHover()
	local camera = workspace.CurrentCamera
	local newHover: ButtonFx? = nil
	if camera and UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
		local mouse = UserInputService:GetMouseLocation()
		newHover = buttonAt(camera:ViewportPointToRay(mouse.X, mouse.Y))
	end
	if newHover ~= hovered then
		hovered = newHover
		setTargets()
	end
end

---------------------------------------------------------------------------------------------
-- Inscription des boutons

local function flashRed(box: Frame)
	local original = box:GetAttribute("BaseColor")
	if typeof(original) ~= "Color3" then
		original = box.BackgroundColor3
		box:SetAttribute("BaseColor", original)
	end
	local gradient = box:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Enabled = false -- le degrade vert assombrirait le rouge
	end
	box.BackgroundColor3 = DENY_COLOR
	local tween = TweenService:Create(box, TweenInfo.new(0.45), { BackgroundColor3 = original :: Color3 })
	tween.Completed:Once(function()
		if gradient then
			gradient.Enabled = true
		end
	end)
	tween:Play()
end

local function addButton(part: BasePart)
	if buttons[part] then
		return
	end
	local model = part.Parent
	local tile = model and model:FindFirstChild("Tile")
	local display = tile and tile:FindFirstChild("Display")
	local box = display and display:FindFirstChild(BOX_OF[part.Name])
	local uiScale = box and box:FindFirstChild("Scale")
	if model == nil or box == nil or not box:IsA("Frame") or uiScale == nil or not uiScale:IsA("UIScale") then
		return -- ancien panneau (pas de bouton dessine centre)
	end
	local fx: ButtonFx = {
		part = part,
		model = model,
		box = box,
		uiScale = uiScale,
		spring = Jelly.Spring(380, 14),
		connections = {},
	}
	buttons[part] = fx
	if part.Name == "BuyButton" then
		local function kick(amount: number, deny: boolean)
			if not isMine(model) then
				return
			end
			fx.spring.v += amount
			moving[fx] = true
			if deny then
				flashRed(box)
			end
		end
		table.insert(fx.connections, model:GetAttributeChangedSignal("Bought"):Connect(function()
			kick(BOUGHT_KICK, false)
		end))
		table.insert(fx.connections, model:GetAttributeChangedSignal("Denied"):Connect(function()
			kick(DENIED_KICK, true)
		end))
	end
	table.insert(
		fx.connections,
		part.AncestryChanged:Connect(function()
			if part:IsDescendantOf(workspace) then
				return
			end
			for _, c in fx.connections do
				c:Disconnect()
			end
			buttons[part] = nil
			moving[fx] = nil
			if hovered == fx then
				hovered = nil
			end
			if pressed == fx then
				pressed = nil
			end
		end)
	)
end

local function onDescendant(item: Instance)
	if item:IsA("ClickDetector") then
		-- Fleche normale au lieu de la main (boutons des tuiles, pads)
		item.CursorIcon = ARROW_CURSOR
	elseif item:IsA("BasePart") and BOX_OF[item.Name] ~= nil then
		local parent = item.Parent
		if parent and (parent:GetAttribute("UpgradeId") ~= nil or parent:GetAttribute("TowerUpgradeId") ~= nil) then
			-- La SurfaceGui de la tuile peut arriver apres (streaming) : on attend un peu
			task.defer(addButton, item)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Appui

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local fx = buttonAt(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	if fx == nil then
		return
	end
	pressed = fx
	setTargets()
	SoundFx.Play("TileClick")
end

local function onInputEnded(input: InputObject)
	local fx = pressed
	if fx == nil then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pressed = nil
		setTargets()
		fx.spring.v += RELEASE_KICK
		moving[fx] = true
	end
end

---------------------------------------------------------------------------------------------

function BoardFxController:Init() end

function BoardFxController:Start()
	if started then
		return
	end
	started = true
	local bases = workspace:WaitForChild("Bases")
	bases.DescendantAdded:Connect(onDescendant)
	for _, item in bases:GetDescendants() do
		onDescendant(item)
	end
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.RenderStepped:Connect(function(dt: number)
		updateHover()
		onRender(dt)
	end)
end

return BoardFxController
