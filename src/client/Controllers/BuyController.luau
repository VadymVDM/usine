--!strict
-- Achats d'ameliorations / employes.
--   * Tuiles des panneaux : SIMPLE CLIC / tap sur le BOUTON VERT (Part invisible BuyButton ;
--     demandes du 2026-11-20 : "on doit CLIQUER dessus et pas avec E", "c'est les boutons qui
--     doivent hover"). Le bouton violet (RobuxButton) est gere par le serveur.
--   * Dessus des pads verts : APPUI LONG souris / doigt (Gameplay.BuyHoldSeconds) avec une jauge
--     qui se remplit sous le pointeur. Relacher avant la fin ou glisser le doigt annule.
--   * Machines : prompt E maintenu (HoldDuration pose par le serveur, jauge native de Roblox).
--   * Premier achat d'une machine ou d'un employe (modele pas encore "Built") : pop-up de
--     confirmation "Buy Blender 2? $250" YES / NO avant d'envoyer la demande.
-- Envoie le remote BuyUpgrade (id) ; le serveur (UpgradeService) reverifie tout : sa base, la
-- distance, le delai, le niveau max et l'argent. Le client ne decide de rien.
-- Doc : docs/systems/ameliorations-employes.md (section Achat)

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gameplay = require(Shared:WaitForChild("Config"):WaitForChild("Gameplay"))
local Upgrades = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades")) :: any
local NumberFormat = require(Shared:WaitForChild("Util"):WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local MachineModels = require(Shared:WaitForChild("Util"):WaitForChild("MachineModels"))
local PackStyle = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PackStyle"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local BuyController = {}

local POPUP_MENU = "ConfirmBuy"
local CANCEL_MOVE = 28 -- pixels : le pointeur bouge plus que ca pendant l'appui -> annule
local MAX_CLICK_DISTANCE = 60 -- studs : au-dela on ne commence pas d'appui (le serveur verifie de toute facon)

type Target = { id: string, machine: Model?, holder: Instance, tile: boolean }

local player = Players.LocalPlayer
local buyEvent: RemoteEvent? = nil
local started = false

-- Jauge d'appui long
local holdGui: ScreenGui
local holdFrame: Frame
local holdFill: Frame
local holding: { input: InputObject, start: Vector3, began: number, target: Target }? = nil

-- Pop-up de confirmation
local popup: { frame: GuiObject, title: TextLabel, price: TextLabel }? = nil
local pendingId: string? = nil

local function menuController(): any
	return require(script.Parent:WaitForChild("MenuController")) :: any
end

local function send(id: string)
	if buyEvent then
		buyEvent:FireServer(id)
	end
end

---------------------------------------------------------------------------------------------
-- Pop-up "Buy X?" (copie du menu OfflineEarnings du pack, ouverte par MenuController)

local function buildPopup()
	local frame = menuController().CloneMenuTemplate("OfflineEarnings", POPUP_MENU)
	if not frame then
		warn("[BuyController] Modele de menu introuvable : achat sans confirmation impossible")
		return
	end
	local header = frame:FindFirstChild("Header")
	local subHeader = header and header:FindFirstChild("SubHeader")
	local headerTitle = subHeader and subHeader:FindFirstChild("TextLabel", true)
	if headerTitle and headerTitle:IsA("TextLabel") then
		headerTitle.Text = "Confirm"
	end
	local body = frame:WaitForChild("Shop") :: Frame

	local title = PackStyle.label(body, "", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.9, 0.18), 60)

	local box = Instance.new("Frame")
	box.Name = "PriceBox"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.fromScale(0.5, 0.31)
	box.Size = UDim2.fromScale(0.5, 0.22)
	box.BackgroundColor3 = Color3.fromRGB(40, 45, 70)
	box.BackgroundTransparency = 0.15
	box.ZIndex = 2
	PackStyle.stroke(box, 3, Color3.fromRGB(10, 10, 20), Enum.ApplyStrokeMode.Border)
	local price = PackStyle.label(box, "$0", UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.9, 0.8), 70)
	price.TextColor3 = PackStyle.MONEY_GREEN
	box.Parent = body

	local yes = PackStyle.button(body, "Yes", PackStyle.GREEN, UDim2.fromScale(0.32, 0.64), UDim2.fromScale(0.3, 0.22))
	PackStyle.label(yes, "YES", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 50)
	yes.Activated:Connect(function()
		local id = pendingId
		pendingId = nil
		if id then
			send(id)
		end
		menuController().Close()
	end)

	local no = PackStyle.button(body, "No", PackStyle.RED, UDim2.fromScale(0.68, 0.64), UDim2.fromScale(0.3, 0.22))
	PackStyle.label(no, "NO", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.86, 0.76), 50)
	no.Activated:Connect(function()
		pendingId = nil
		menuController().Close()
	end)

	menuController().RegisterMenu(frame)
	popup = { frame = frame, title = title, price = price }
end

local function confirm(id: string, machine: Model?)
	local upgrade = Upgrades.ById[id]
	if upgrade == nil then
		return
	end
	if popup == nil then
		buildPopup()
	end
	local p = popup
	if p == nil then
		return
	end
	local price = machine and machine:GetAttribute("Price")
	local verb = if upgrade.kind == "Employee" then "Hire" else "Buy"
	p.title.Text = `{verb} {upgrade.machine}?`
	p.price.Text = if type(price) == "number" and price >= 0 then NumberFormat.Money(price) else "?"
	pendingId = id
	if menuController().GetActiveMenu() ~= POPUP_MENU then
		menuController().Open(POPUP_MENU)
	end
end

-- Achat demande (fin de l'appui long ou du prompt E) : confirmation si c'est un premier achat.
local function request(target: Target)
	local machine = target.machine
	if machine and machine:GetAttribute("Built") ~= true then
		confirm(target.id, machine)
	else
		send(target.id)
	end
end

---------------------------------------------------------------------------------------------
-- Appui long sur les tuiles et les pads

-- Etage (Bases.BaseN.Floors.FloorK) qui contient la piece, seulement s'il est dans SA base.
local function myFloor(part: Instance): Model?
	local current: Instance? = part
	while current do
		local parent = current.Parent
		if current:IsA("Model") and parent and parent.Name == "Floors" then
			return if FloorWatch.IsMine(current) and FloorWatch.IsOpen(current) then current else nil
		end
		current = parent
	end
	return nil
end

local function findMachine(floor: Model, id: string): Model?
	return MachineModels.Find(floor, id)
end

-- Bouton vert d'une tuile (Part invisible BuyButton) ou dessus d'un pad (PadTop) d'un
-- etage de SA base sous ce point de l'ecran.
local function targetAt(screen: Vector3): Target?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	-- On traverse les pieces invisibles (zones des pads...)
	for _ = 1, 6 do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
		if result == nil then
			return nil
		end
		local part = result.Instance
		-- Bouton violet (Part invisible devant la tuile) : son ClickDetector va au serveur, on
		-- n'achete surtout pas la tuile derriere.
		if part.Name == "RobuxButton" then
			return nil
		end
		-- (aussi les panneaux caches localement : mixeur pas encore deverrouille, LevelLookController)
		-- (BuyButton : Part invisible devant le bouton vert d'une tuile, c'est elle qu'on clique)
		if (part.Transparency >= 1 and part.Name ~= "PadTop" and part.Name ~= "BuyButton") or part.LocalTransparencyModifier >= 1 then
			table.insert(ignore, part)
			continue
		end
		local click = part:FindFirstChildOfClass("ClickDetector")
		if click == nil or click.MaxActivationDistance <= 0 then
			return nil
		end
		local holder: Instance? = nil
		local isTile = part.Name == "Tile" or part.Name == "BuyButton"
		if isTile then
			holder = part.Parent -- tuile du panneau
		elseif part.Name == "PadTop" then
			holder = part.Parent and part.Parent.Parent -- Machines.<id>.Pad.PadTop
		end
		local id = holder and holder:GetAttribute("UpgradeId")
		local floor = myFloor(part)
		if holder == nil or type(id) ~= "string" or floor == nil then
			return nil
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - part.Position).Magnitude > MAX_CLICK_DISTANCE then
			return nil
		end
		local machine = if holder:IsA("Model") and holder.Parent and holder.Parent.Name == "Machines"
			then holder
			else findMachine(floor, id)
		return { id = id, machine = machine, holder = holder, tile = isTile }
	end
	return nil
end

local function stopHold()
	holding = nil
	holdFrame.Visible = false
end

local function buildHoldGui()
	holdGui = Instance.new("ScreenGui")
	holdGui.Name = "BuyHold"
	holdGui.ResetOnSpawn = false
	holdGui.IgnoreGuiInset = false
	holdGui.DisplayOrder = 40
	holdGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	holdFrame = Instance.new("Frame")
	holdFrame.Name = "Gauge"
	holdFrame.AnchorPoint = Vector2.new(0.5, 1)
	holdFrame.Size = UDim2.fromOffset(120, 26)
	holdFrame.BackgroundColor3 = Color3.fromRGB(30, 22, 40)
	holdFrame.BackgroundTransparency = 0.2
	holdFrame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = holdFrame
	PackStyle.stroke(holdFrame, 2.5, Color3.new(0, 0, 0), Enum.ApplyStrokeMode.Border)

	holdFill = Instance.new("Frame")
	holdFill.Name = "Fill"
	holdFill.Size = UDim2.fromScale(0, 1)
	holdFill.BackgroundColor3 = Color3.new(1, 1, 1)
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = holdFill
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Color = ColorSequence.new(PackStyle.GREEN[1], PackStyle.GREEN[2])
	gradient.Parent = holdFill
	holdFill.Parent = holdFrame

	local label = PackStyle.label(holdFrame, "HOLD", UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.9, 0.84), 22)
	label.ZIndex = 5
	holdGui.Parent = player:WaitForChild("PlayerGui")
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed or holding then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local target = targetAt(input.Position)
	if target == nil then
		return
	end
	local holder = target.holder
	local price = holder:GetAttribute("Price")
	if (type(price) == "number" and price < 0) or holder:GetAttribute("ComingSoon") == true then
		send(target.id) -- max / bientot : le serveur affiche le message, pas besoin d'attendre
		return
	end
	if target.tile then
		request(target) -- tuile : un clic = un niveau (le serveur limite la cadence)
		return
	end
	holding = { input = input, start = input.Position, began = os.clock(), target = target }
	holdFrame.Position = UDim2.fromOffset(input.Position.X, input.Position.Y - 24)
	holdFill.Size = UDim2.fromScale(0, 1)
	holdFrame.Visible = true
end

local function onInputChanged(input: InputObject)
	local hold = holding
	if hold == nil then
		return
	end
	local same = input == hold.input
		or (hold.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
	if same and (input.Position - hold.start).Magnitude > CANCEL_MOVE then
		stopHold()
	end
end

local function onInputEnded(input: InputObject)
	local hold = holding
	if hold and (input == hold.input or input.UserInputType == hold.input.UserInputType) then
		stopHold()
	end
end

local function onRender()
	local hold = holding
	if hold == nil then
		return
	end
	local alpha = (os.clock() - hold.began) / Gameplay.BuyHoldSeconds
	holdFill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	if alpha >= 1 then
		local target = hold.target
		stopHold()
		request(target)
	end
end

---------------------------------------------------------------------------------------------

function BuyController:Init() end

function BuyController:Start()
	if started then
		return
	end
	started = true
	buildHoldGui()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.RenderStepped:Connect(onRender)

	-- Prompt E maintenu sur une machine fantome : le serveur attend la confirmation
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player or prompt.Name ~= "BuyPrompt" or prompt:GetAttribute("Confirm") ~= true then
			return
		end
		local id = prompt:GetAttribute("UpgradeId")
		local machine = prompt:FindFirstAncestorWhichIsA("Model")
		while machine and machine:GetAttribute("UpgradeId") == nil do
			machine = machine.Parent and machine.Parent:FindFirstAncestorWhichIsA("Model")
		end
		if type(id) == "string" then
			confirm(id, machine)
		end
	end)

	task.spawn(function()
		buyEvent = Remotes.WaitClientEvent("BuyUpgrade")
	end)
end

return BuyController
