--!strict
-- Pose des bras quand un personnage porte quelque chose : joueurs, employes, clients.
--   * plateau sur la tete (attribut TrayFruits ou HandJuices non vide, joueurs) : bras leves, mains
--     sous le plateau, comme si on le tenait (2026-11-20, demande utilisateur) ;
--   * objets devant le torse (attribut CarryPose = true, employes / clients) : bras tendus devant ;
--   * arbre niveau 1 dans les mains (attribut JOUEUR HoldingSapling, SaplingController, 2026-11-22) :
--     bras tendus devant, un peu plus bas (Config/Intro.HoldArmDegrees).
-- Le serveur (ou CustomerController en local) pose le tag "CarryPoseRig" sur le modele. Ici on
-- ecrase seulement l'angle des epaules apres les animations de Roblox (RunService.Stepped), pour
-- tous les personnages proches. Passage d'une pose a l'autre en douceur.
-- Doc : docs/systems/chaine-production.md (section Mains)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Intro = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Intro"))

local CarryPoseController = {}

local TAG = "CarryPoseRig"
local FRONT_ANGLE = math.rad(78) -- bras presque a l'horizontale (objets portes devant)
local TRAY_ANGLE = math.rad(155) -- bras leves, mains un peu devant, juste sous le plateau
local BLEND_SPEED = 12 -- vitesse du passage d'une pose a l'autre
local SAPLING_ANGLE = math.rad(Intro.HoldArmDegrees)
local MAX_DISTANCE = 160

-- Epaule : Motor6D (anciens rigs) ou AnimationConstraint (Avatar Joint Upgrade de Roblox, 2026) ;
-- les deux ont une propriete Transform ecrasee par les animations.
type Joint = Motor6D | AnimationConstraint
type Rig = { model: Model, right: Joint?, left: Joint?, r15: boolean, angle: number }

local rigs: { [Model]: Rig } = {}
local started = false

local function findMotor(parent: Instance?, name: string): Joint?
	local joint = parent and parent:FindFirstChild(name)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint :: any
	end
	return nil
end

local function setTransform(joint: Joint, cf: CFrame)
	local anyJoint: any = joint
	anyJoint.Transform = cf
end

local function resolve(rig: Rig)
	local model = rig.model
	local torso = model:FindFirstChild("Torso")
	if torso then
		rig.right = findMotor(torso, "Right Shoulder")
		rig.left = findMotor(torso, "Left Shoulder")
		rig.r15 = false
	else
		rig.right = findMotor(model:FindFirstChild("RightUpperArm"), "RightShoulder")
		rig.left = findMotor(model:FindFirstChild("LeftUpperArm"), "LeftShoulder")
		rig.r15 = true
	end
end

local function add(instance: Instance)
	if not instance:IsA("Model") or rigs[instance] then
		return
	end
	local rig: Rig = { model = instance, right = nil, left = nil, r15 = false, angle = 0 }
	rigs[instance] = rig
	resolve(rig)
end

local function remove(instance: Instance)
	if instance:IsA("Model") then
		rigs[instance] = nil
	end
end

local function hasItems(value: any): boolean
	return type(value) == "string" and value ~= ""
end

-- Angle voulu des epaules (0 = on laisse les animations de Roblox).
local function targetAngle(model: Model): number
	if hasItems(model:GetAttribute("TrayFruits")) or hasItems(model:GetAttribute("HandJuices")) then
		return TRAY_ANGLE
	end
	if model:GetAttribute("CarryPose") == true then
		return FRONT_ANGLE
	end
	local owner = Players:GetPlayerFromCharacter(model)
	if owner and owner:GetAttribute("HoldingSapling") == true then
		return SAPLING_ANGLE
	end
	return 0
end

function CarryPoseController.Init() end

function CarryPoseController.Start()
	if started then
		return
	end
	started = true
	for _, instance in CollectionService:GetTagged(TAG) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)

	RunService.Stepped:Connect(function(_time: number, dt: number)
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local blend = math.min(1, dt * BLEND_SPEED)
		for model, rig in rigs do
			local target = targetAngle(model)
			if target == 0 and rig.angle < 0.01 then
				rig.angle = 0
				continue -- rien a porter : animations normales
			end
			rig.angle += (target - rig.angle) * blend
			if rig.right == nil or rig.right.Parent == nil then
				resolve(rig) -- personnage pas encore complet (chargement) : on reessaie
			end
			local right, left = rig.right, rig.left
			local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if right == nil or root == nil then
				continue
			end
			if (root.Position - camPos).Magnitude > MAX_DISTANCE then
				continue
			end
			local angle = rig.angle
			if rig.r15 then
				local both = CFrame.Angles(angle, 0, 0)
				setTransform(right, both)
				if left then
					setTransform(left, both)
				end
			else
				setTransform(right, CFrame.Angles(0, 0, angle))
				if left then
					setTransform(left, CFrame.Angles(0, 0, -angle))
				end
			end
		end
	end)
end

return CarryPoseController
