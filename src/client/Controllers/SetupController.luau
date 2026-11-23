--!strict
-- Usine a construire, cote client seulement (le serveur, SetupService, decide de tout ; ici on ne
-- fait que montrer). Pour les etages de SA base :
--   * contour bleu qui pulse sur une racine SetupGhost = true (plus utilise depuis le 2026-11-21 :
--     les constructions des pads FREE sont cachees, pas en bleu, avant le pad) ;
--   * BuildStamp +1 sur une racine SetupBuild : les pieces tombent une par une (Fx/Reveal.Build),
--     etincelles, puis "boing" gelee (Fx/Jelly) ;
--   * RevealStamp +1 (pads de Config/Setup.Reveal, pads FREE) : apparition "pop" (Fx/Reveal.Pop) +
--     etincelles + son ; DoneStamp +1 (pad FREE fait) : bouffee d'etincelles a sa place ;
--   * Tree.PlantStamp +1 : l'arbre plante pousse depuis le sol (pop lent) + etincelles + son ;
--   * machine dont l'attribut Hidden passe a faux (mixeurs 2-4 apres "Build blender") et pad vert
--     qui redevient visible (Upgrade Tree, Fruit Picker, Waiter, operateurs) : pop.
-- Pas d'animation pendant les premieres secondes d'un etage (arrivee : tout arrive d'un coup).
-- Jamais de Neon. Doc : docs/systems/usine-a-construire.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any
local MachineModels = require(Shared:WaitForChild("Util"):WaitForChild("MachineModels"))
local Fx = script.Parent.Parent:WaitForChild("Fx")
local Jelly = require(Fx:WaitForChild("Jelly"))
local Reveal = require(Fx:WaitForChild("Reveal"))
local FloorWatch = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("FloorWatch"))

local FX_DISTANCE = 170
local QUIET_SECONDS = 2.5 -- apres l'arrivee d'un etage : pas d'animation (etat initial)
local BUILD_SECONDS = 1.0 -- duree de la chute des pieces d'une construction
local TREE_GROW_SECONDS = 1.2
local GHOST_GLOW = Color3.fromRGB(110, 185, 255)
local SPARKLE_GOLD = Color3.fromRGB(255, 225, 80)
local SPARKLE_GREEN = Color3.fromRGB(140, 255, 110)

local SetupController = {}

local started = false
local fxFolder: Folder? = nil
local glows: { [Instance]: Highlight } = {}
local quietUntil: { [Model]: number } = {}

local function camDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

local function partsOf(root: Instance): { BasePart }
	local list: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, item in root:GetDescendants() do
		-- Lattes du tapis : deplacees chaque image par LevelLookController
		if item:IsA("BasePart") and item.Name ~= "Slat" then
			table.insert(list, item)
		end
	end
	return list
end

local function centerOf(root: Instance): Vector3
	if root:IsA("BasePart") then
		return root.Position
	elseif root:IsA("Model") then
		return root:GetBoundingBox().Position
	end
	local parts = partsOf(root)
	local sum = Vector3.zero
	for _, p in parts do
		sum += p.Position
	end
	return if #parts > 0 then sum / #parts else Vector3.zero
end

local function sparkles(position: Vector3, color: Color3, count: number)
	local folder = fxFolder
	if folder == nil then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "SetupSparkles"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = folder
	emitter:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

local function canAnimate(floor: Model, position: Vector3): boolean
	return FloorWatch.IsMine(floor) and os.clock() >= (quietUntil[floor] or 0) and camDistance(position) <= FX_DISTANCE
end

---------------------------------------------------------------------------------------------
-- Effets

local function playBuild(floor: Model, root: Instance)
	local center = centerOf(root)
	if not canAnimate(floor, center) then
		return
	end
	-- Une image : les proprietes remises par le serveur (fin du fantome) sont toutes arrivees
	task.defer(function()
		local parts = partsOf(root)
		local seconds = Reveal.Build(root, parts, BUILD_SECONDS)
		SoundFx.PlayAt("MachineBoing", center, nil, 0.9)
		task.delay(seconds, function()
			if root.Parent == nil then
				return
			end
			sparkles(center + Vector3.new(0, 3, 0), SPARKLE_GOLD, 40)
			SoundFx.PlayAt("MachineBoing", center, nil, 1.2)
			local visible: { BasePart } = {}
			for _, p in partsOf(root) do
				if p.Transparency < 1 and p.LocalTransparencyModifier < 1 then
					table.insert(visible, p)
				end
			end
			if #visible > 0 then
				-- Pivot = pied du groupe (le plus bas), sous son centre
				local low = math.huge
				for _, p in visible do
					low = math.min(low, p.Position.Y - p.Size.Y / 2)
				end
				Jelly.Boing(root, visible, CFrame.new(center.X, low, center.Z), 0.9)
			end
		end)
	end)
end

local function playPop(floor: Model, root: Instance, parts: { BasePart }?)
	local center = centerOf(root)
	if not canAnimate(floor, center) then
		return
	end
	task.defer(function()
		local foot = Reveal.Pop(root, parts or partsOf(root))
		if foot then
			sparkles(foot + Vector3.new(0, 1, 0), SPARKLE_GREEN, 22)
			SoundFx.PlayAt("Pickup", foot, nil, 0.8)
		end
	end)
end

local function playDone(floor: Model, root: Instance)
	local center = centerOf(root)
	if canAnimate(floor, center) then
		sparkles(center, SPARKLE_GOLD, 30)
		SoundFx.PlayAt("GreenPadStep", center, nil, 1.3)
	end
end

local function playPlant(floor: Model, tree: Instance)
	task.defer(function()
		local body = tree:FindFirstChild("Body")
		if body == nil then
			return
		end
		local center = centerOf(body)
		if not canAnimate(floor, center) then
			return
		end
		local foot = Reveal.Pop(body, partsOf(body), TREE_GROW_SECONDS)
		SoundFx.PlayAt("TreeBoing", center)
		if foot then
			sparkles(foot + Vector3.new(0, 1, 0), SPARKLE_GREEN, 35)
		end
		task.delay(TREE_GROW_SECONDS * 0.8, function()
			sparkles(center + Vector3.new(0, 2, 0), SPARKLE_GOLD, 30)
			SoundFx.PlayAt("TreeChime", center)
		end)
	end)
end

---------------------------------------------------------------------------------------------
-- Contours bleus des fantomes de SA base

local function setGlow(root: Instance, wanted: boolean)
	local glow = glows[root]
	if wanted and glow == nil then
		local highlight = Instance.new("Highlight")
		highlight.Name = "SetupGlow"
		highlight.Adornee = root
		highlight.FillColor = GHOST_GLOW
		highlight.OutlineColor = Color3.fromRGB(205, 235, 255)
		highlight.FillTransparency = 0.75
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = fxFolder
		glows[root] = highlight
	elseif not wanted and glow ~= nil then
		glow:Destroy()
		glows[root] = nil
	end
end

local function refreshGlows()
	for root, glow in glows do
		if root.Parent == nil or root:GetAttribute("SetupGhost") ~= true then
			glow:Destroy()
			glows[root] = nil
		end
	end
	local base = FloorWatch.MyBase()
	if base == nil then
		return
	end
	for _, floor in FloorWatch.FloorsOf(base) do
		if FloorWatch.IndexOf(floor) ~= 1 then
			continue
		end
		local roots: { Instance } = {}
		for _, folderName in { "Production", "Counter" } do
			local folder = floor:FindFirstChild(folderName)
			for _, item in (if folder then folder:GetChildren() else {}) do
				if item:GetAttribute("SetupBuild") ~= nil then
					table.insert(roots, item)
				end
			end
		end
		local tree = floor:FindFirstChild("Tree")
		local body = tree and tree:FindFirstChild("Body")
		if body then
			table.insert(roots, body)
		end
		for _, root in roots do
			-- Pendant la construction : pas de contour (il suivrait les pieces qui tombent)
			setGlow(root, root:GetAttribute("SetupGhost") == true and not Reveal.IsBusy(root))
		end
	end
end

---------------------------------------------------------------------------------------------
-- Inscription des etages

local function watchStamp(instance: Instance, attribute: string, callback: () -> ()): RBXScriptConnection
	return instance:GetAttributeChangedSignal(attribute):Connect(callback)
end

local function registerFloor(floor: Model)
	quietUntil[floor] = os.clock() + QUIET_SECONDS
	local connections: { RBXScriptConnection } = {}
	local watched: { [Instance]: boolean } = {}

	local function watchItem(item: Instance)
		if watched[item] then
			return
		end
		if item:GetAttribute("SetupBuild") ~= nil then
			watched[item] = true
			table.insert(connections, watchStamp(item, "BuildStamp", function()
				playBuild(floor, item)
			end))
			-- (cache -> visible sans construction : pop)
			table.insert(connections, watchStamp(item, "RevealStamp", function()
				playPop(floor, item)
			end))
		elseif item:GetAttribute("SetupReveal") ~= nil or (item.Parent and item.Parent.Name == "Setup") then
			watched[item] = true
			table.insert(connections, watchStamp(item, "RevealStamp", function()
				playPop(floor, item)
			end))
			table.insert(connections, watchStamp(item, "DoneStamp", function()
				playDone(floor, item)
			end))
		elseif item.Name == "Tree" and item.Parent == floor then
			watched[item] = true
			table.insert(connections, watchStamp(item, "PlantStamp", function()
				playPlant(floor, item)
			end))
		end
	end

	for _, item in floor:GetDescendants() do
		if item:IsA("Model") or item:IsA("Folder") then
			watchItem(item)
		end
	end
	table.insert(connections, floor.DescendantAdded:Connect(function(item)
		if item:IsA("Model") or item:IsA("Folder") then
			-- Attributs poses juste apres la creation (streaming) : on attend une image
			task.defer(watchItem, item)
		end
	end))

	-- Machines : Hidden -> visible (mixeurs 2-4), pad vert qui reapparait
	for _, machine in MachineModels.List(floor) do
		table.insert(connections, watchStamp(machine, "Hidden", function()
			if machine:GetAttribute("Hidden") == false then
				local build = machine:FindFirstChild("Build")
				if build then
					playPop(floor, build) -- (task.defer dans playPop : le serveur l'a deja rendue visible)
				end
			end
		end))
		local pad = machine:FindFirstChild("Pad")
		local top = pad and pad:FindFirstChild("PadTop")
		if pad and top and top:IsA("BasePart") then
			local wasHidden = top.Transparency >= 1
			table.insert(connections, top:GetPropertyChangedSignal("Transparency"):Connect(function()
				local hidden = top.Transparency >= 1
				if wasHidden and not hidden then
					playPop(floor, pad)
				end
				wasHidden = hidden
			end))
		end
	end

	FloorWatch.OnRemoved(floor, function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		quietUntil[floor] = nil
	end)
end

function SetupController.Init() end

function SetupController.Start()
	if started then
		return
	end
	started = true
	local folder = Instance.new("Folder")
	folder.Name = "SetupFx"
	folder.Parent = workspace
	fxFolder = folder
	FloorWatch.Watch(function(floor)
		registerFloor(floor)
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(refreshGlows)
			if not ok then
				warn(`[SetupController] {err}`)
			end
			task.wait(0.25)
		end
	end)
	local clock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		clock += dt
		local pulse = 0.72 + 0.12 * math.sin(clock * 3)
		for _, glow in glows do
			glow.FillTransparency = pulse
		end
	end)
end

return SetupController
