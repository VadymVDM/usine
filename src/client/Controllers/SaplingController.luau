--!strict
-- Arbre niveau 1 dans les mains (2026-11-22) : pour chaque joueur dont l'attribut "HoldingSapling"
-- est vrai (pose par SetupService tant que le pad "Plant tree" n'est pas fait), on montre une copie
-- locale de ReplicatedStorage.IntroSet.Sapling devant son personnage (tout le monde le voit, chacun
-- chez soi). Les bras tendus viennent de CarryPoseController. Disparait quand l'arbre est plante.
-- Purement visuel : aucun effet sur la partie. Doc : docs/systems/cinematique.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Intro = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Intro"))

local SaplingController = {}

local MAX_DISTANCE = 200 -- au-dela, pas la peine de le deplacer

type Held = { model: Model, root: BasePart }

local held: { [Player]: Held } = {}
local folder: Folder? = nil
local started = false

local function drop(player: Player)
	local item = held[player]
	if item then
		item.model:Destroy()
		held[player] = nil
	end
end

local function refresh(player: Player)
	local wanted = player:GetAttribute("HoldingSapling") == true
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local current = held[player]
	if not wanted or root == nil or not root:IsA("BasePart") then
		drop(player)
		return
	end
	if current and current.root == root then
		return
	end
	drop(player)
	local set = ReplicatedStorage:FindFirstChild("IntroSet")
	local source = set and set:FindFirstChild("Sapling")
	if source == nil or not source:IsA("Model") or folder == nil then
		return
	end
	local model = source:Clone()
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
		end
	end
	model:PivotTo(root.CFrame * Intro.HoldOffset)
	model.Parent = folder
	held[player] = { model = model, root = root }
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("HoldingSapling"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		refresh(player)
	end)
	player.CharacterRemoving:Connect(function()
		drop(player)
	end)
	refresh(player)
end

function SaplingController.Init() end

function SaplingController.Start()
	if started then
		return
	end
	started = true
	local f = Instance.new("Folder")
	f.Name = "HeldSaplings"
	f.Parent = workspace
	folder = f
	ReplicatedStorage:WaitForChild("IntroSet", 15)
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(drop)
	-- Juste avant le rendu (apres la physique) : l'arbre suit le personnage sans retard
	RunService.PreRender:Connect(function()
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for player, item in held do
			if item.root.Parent == nil then
				drop(player)
			elseif (item.root.Position - camPos).Magnitude <= MAX_DISTANCE then
				item.model:PivotTo(item.root.CFrame * Intro.HoldOffset)
			end
		end
	end)
end

return SaplingController
