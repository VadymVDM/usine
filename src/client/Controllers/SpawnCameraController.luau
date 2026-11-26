--!strict
-- Camera tournee vers l'interieur de l'usine a l'apparition (client seulement, rien n'est envoye).
-- Demande du 2026-11-23 : "quand on join ou rejoin le serv, la cam doit etre vers l'usine".
--
-- Pourquoi : le moteur fait d'abord apparaitre le personnage sur la SpawnLocation et la camera de
-- Roblox se place derriere lui a cet endroit. Ensuite le serveur (BaseService) le pose dans sa base,
-- face a l'interieur de l'usine, mais la camera garde son ancien angle -> elle regardait dehors.
-- Ici : pendant WatchSeconds apres l'apparition, on guette ce saut de position ; des qu'il arrive,
-- on place la camera derriere le personnage, dans le sens ou il regarde.
-- Rien n'est fait si la camera est en Scriptable (cinematique : elle replace la camera elle-meme).
-- Doc : docs/systems/camera.md

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpawnCamera = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SpawnCamera"))

local SpawnCameraController = {}

local player = Players.LocalPlayer
local watchConnection: RBXScriptConnection? = nil

local function stopWatch()
	if watchConnection then
		watchConnection:Disconnect()
		watchConnection = nil
	end
end

local function faceForward(root: BasePart)
	local camera = workspace.CurrentCamera
	if camera == nil or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	camera.CFrame = CFrame.lookAt(focus - flat * SpawnCamera.Distance + Vector3.new(0, SpawnCamera.Height, 0), focus)
	camera.Focus = CFrame.new(focus)
end

local function onCharacter(character: Model)
	stopWatch()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") or player.Character ~= character then
		return
	end
	-- Le serveur a peut-etre deja pose le personnage dans sa base avant qu'on le voie : on aligne
	-- la camera une premiere fois tout de suite (sans effet visible s'il est encore sur la SpawnLocation)
	task.defer(faceForward, root)
	local last = root.Position
	local startedAt = os.clock()
	watchConnection = RunService.Heartbeat:Connect(function()
		if root.Parent == nil or player.Character ~= character or os.clock() - startedAt > SpawnCamera.WatchSeconds then
			stopWatch()
			return
		end
		local position = root.Position
		if (position - last).Magnitude >= SpawnCamera.TeleportDistance then
			stopWatch()
			-- Une image plus tard : la camera de Roblox a fini sa mise a jour de cette image
			task.defer(faceForward, root)
			return
		end
		last = position
	end)
end

function SpawnCameraController.Init() end

function SpawnCameraController.Start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return SpawnCameraController
