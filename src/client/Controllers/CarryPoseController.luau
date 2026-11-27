--!strict
-- Pose des bras quand un personnage porte quelque chose : joueurs, employes, clients.
--   * plateau sur la tete (attribut TrayFruits ou HandJuices non vide, joueurs) : bras leves, mains
--     sous le plateau, comme si on le tenait (2026-11-20, demande utilisateur) ;
--   * objets devant le torse (attribut CarryPose = true, employes / clients) : bras tendus devant ;
--   * arbre niveau 1 dans les mains (attribut JOUEUR HoldingSapling, SaplingController, 2026-11-22) :
--     bras tendus devant, un peu plus bas (Config/Intro.HoldArmDegrees).
--   * ramassage d'un fruit (Fruit Picker R15, 2026-11-27 : attributs PickStart / PickTime poses par
--     NpcRig.Pick) : il plie les genoux, penche le buste, tend le bras droit jusqu'au sol, puis se
--     releve en montant le fruit vers le plateau. Les pieds restent au sol (hanches baissees de
--     la longueur de jambe x (1 - cos angle)) ; avec un plateau garni la tete reste droite.
--   * depot a l'etagere (Fruit Picker R15, 2026-11-27 : DumpStart / DumpTime, NpcRig.Dump) : il
--     pousse le plateau vers l'avant, penche la tete (le plateau, soude a la tete, bascule vers les
--     caisses) en pliant un peu les genoux ; les fruits partent a Npcs.DumpReleaseAt, puis il
--     baisse les bras.
--   * appui sur le bouton du mixeur (Blender Operator R15, 2026-11-27 : PressStart / PressTime,
--     NpcRig.Press) : bras droit leve vers l'avant, coude plie, qui se tend pour appuyer, redescend ;
--   * depot des jus sur la table (Blender Operator R15 : DepositStart / DepositTime / DepositToss,
--     NpcRig.Deposit) : deux bras tendus pendant qu'il se tourne, petit lancer vers le haut (les
--     gobelets sautent de ses mains), puis bras baisses.
-- Le serveur (ou CustomerController en local) pose le tag "CarryPoseRig" sur le modele. Ici on
-- ecrase seulement l'angle des epaules apres les animations de Roblox (RunService.Stepped), pour
-- tous les personnages proches. Passage d'une pose a l'autre en douceur.
-- Doc : docs/systems/chaine-production.md (section Mains)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Npcs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Npcs"))
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
type Body = {
	root: Joint?,
	waist: Joint?,
	neck: Joint?,
	rightElbow: Joint?,
	hips: { Joint },
	knees: { Joint },
	ankles: { Joint },
	legLength: number, -- hanche -> cheville (studs)
}
type Rig = {
	model: Model,
	right: Joint?,
	left: Joint?,
	r15: boolean,
	angle: number,
	body: Body?, -- articulations R15 du geste de ramassage (cherchees au premier geste)
	picking: boolean,
}

-- Geste de ramassage (R15) : angles au plus bas
local PICK_SQUAT = math.rad(58) -- cuisses vers l'avant (genoux plies de 2x)
local PICK_LEAN = math.rad(18) -- bassin penche en avant
local PICK_WAIST = math.rad(22) -- buste penche en plus
local PICK_REACH = math.rad(62) -- bras droit vers l'avant (par rapport au buste)
local PICK_ELBOW = math.rad(12)
local PICK_LOOK = math.rad(12) -- tete qui regarde le fruit (sans plateau garni)
-- Depot a l'etagere (R15) : au moment ou les fruits partent
local DUMP_ARMS = math.rad(100) -- bras qui poussent le plateau vers l'avant
local DUMP_NECK = math.rad(30) -- tete (et plateau) penchee vers les caisses
local DUMP_WAIST = math.rad(10)
local DUMP_SQUAT = math.rad(14) -- petite flexion des genoux
-- Appui sur le bouton (R15, memes angles et durees que l'ancien geste R6 de NpcRig.Press)
local PRESS_UP = math.rad(80) -- bras leve devant soi
local PRESS_PUSH = math.rad(65) -- bras qui appuie (descend un peu)
local PRESS_ELBOW = math.rad(35) -- coude plie en levant le bras, tendu a l'appui
-- Depot des jus (R15, memes angles que l'ancien geste R6 de NpcRig.Deposit)
local DEPOSIT_HOLD = math.rad(85) -- bras tendus devant pendant qu'il se tourne
local DEPOSIT_TOSS = math.rad(110) -- petit lancer vers le haut

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
	if torso then -- joueur avec un avatar R6 (les PNJ sont tous R15 depuis le 2026-11-27)
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
	local rig: Rig = { model = instance, right = nil, left = nil, r15 = false, angle = 0, body = nil, picking = false }
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

-- Distance entre deux articulations d'un meme membre (C1 de celle du haut -> C0 de celle du bas).
local function segment(upper: Joint?, lower: Joint?): number
	if upper == nil or lower == nil then
		return 0
	end
	local a: any, b: any = upper, lower
	local ok, length = pcall(function(): number
		if a:IsA("Motor6D") and b:IsA("Motor6D") then
			return (a.C1.Position - b.C0.Position).Magnitude
		end
		return (a.Attachment1.Position - b.Attachment0.Position).Magnitude
	end)
	return if ok then length else 0
end

local function findBody(model: Model): Body?
	local lowerTorso = model:FindFirstChild("LowerTorso")
	if lowerTorso == nil then
		return nil
	end
	local body: Body = {
		root = findMotor(lowerTorso, "Root"),
		waist = findMotor(model:FindFirstChild("UpperTorso"), "Waist"),
		neck = findMotor(model:FindFirstChild("Head"), "Neck"),
		rightElbow = findMotor(model:FindFirstChild("RightLowerArm"), "RightElbow"),
		hips = {},
		knees = {},
		ankles = {},
		legLength = 0,
	}
	for _, side in { "Left", "Right" } do
		local hip = findMotor(model:FindFirstChild(side .. "UpperLeg"), side .. "Hip")
		local knee = findMotor(model:FindFirstChild(side .. "LowerLeg"), side .. "Knee")
		local ankle = findMotor(model:FindFirstChild(side .. "Foot"), side .. "Ankle")
		if hip and knee and ankle then
			table.insert(body.hips, hip)
			table.insert(body.knees, knee)
			table.insert(body.ankles, ankle)
			body.legLength = segment(hip, knee) + segment(knee, ankle)
		end
	end
	if body.legLength < 0.5 then
		body.legLength = 2.2 -- R15 classique
	end
	return body
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function quadOut(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

local function quadIn(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x
end

-- Leger depassement a l'arrivee (comme Enum.EasingStyle.Back, Out)
local function backOut(x: number): number
	x = math.clamp(x, 0, 1)
	local c1 = 1.70158
	return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- Progression d'un geste (0..1) : attributs <name>Start / <name>Time, nil s'il n'y en a pas en cours.
local function gestureProgress(model: Model, name: string): number?
	local start, length = model:GetAttribute(name .. "Start"), model:GetAttribute(name .. "Time")
	if type(start) ~= "number" or type(length) ~= "number" or length <= 0 then
		return nil
	end
	local p = (workspace:GetServerTimeNow() - start) / length
	return if p >= 0 and p < 1 then p else nil
end

-- Pose R15 du ramassage a la progression p. `trayHeld` : plateau deja garni (tete gardee droite).
-- Renvoie l'angle du bras droit (le gauche suit rig.angle comme d'habitude).
local function applyPick(body: Body, p: number, trayHeld: boolean, carryAngle: number): number
	local grab, tray = Npcs.PickGrabAt, Npcs.PickTrayAt
	-- Accroupi : descend jusqu'a la prise, tient un instant, remonte avant que le fruit arrive au plateau
	local hold = 0.04
	local crouch = if p < grab then smooth(p / grab) else 1 - smooth((p - grab - hold) / (tray - grab - hold))
	local squat, lean, waist = PICK_SQUAT * crouch, PICK_LEAN * crouch, PICK_WAIST * crouch
	if body.root then
		local drop = body.legLength * (1 - math.cos(squat))
		setTransform(body.root, CFrame.new(0, -drop, 0) * CFrame.Angles(-lean, 0, 0))
	end
	if body.waist then
		setTransform(body.waist, CFrame.Angles(-waist, 0, 0))
	end
	if body.neck then
		local head = if trayHeld then lean + waist else -PICK_LOOK * crouch
		setTransform(body.neck, CFrame.Angles(head, 0, 0))
	end
	for _, hip in body.hips do
		setTransform(hip, CFrame.Angles(squat + lean, 0, 0))
	end
	for _, knee in body.knees do
		setTransform(knee, CFrame.Angles(-2 * squat, 0, 0))
	end
	for _, ankle in body.ankles do
		setTransform(ankle, CFrame.Angles(squat, 0, 0))
	end
	if body.rightElbow then
		setTransform(body.rightElbow, CFrame.Angles(PICK_ELBOW * crouch, 0, 0))
	end
	-- Bras droit : vers le fruit (compense le buste penche), puis monte vers le plateau
	local reach = PICK_REACH + lean + waist
	if p < grab then
		return carryAngle + (reach - carryAngle) * smooth(p / grab)
	end
	return reach + (TRAY_ANGLE - reach) * smooth((p - grab) / (tray - grab))
end

-- Pose R15 du depot a l'etagere a la progression p. Renvoie l'angle des deux bras.
local function applyDump(body: Body, p: number): number
	local release = Npcs.DumpReleaseAt
	local tilt = if p < release then smooth(p / release) else 1 - smooth((p - release) / (1 - release))
	local squat = DUMP_SQUAT * tilt
	if body.root then
		setTransform(body.root, CFrame.new(0, -body.legLength * (1 - math.cos(squat)), 0))
	end
	if body.waist then
		setTransform(body.waist, CFrame.Angles(-DUMP_WAIST * tilt, 0, 0))
	end
	if body.neck then
		setTransform(body.neck, CFrame.Angles(-DUMP_NECK * tilt, 0, 0))
	end
	for _, hip in body.hips do
		setTransform(hip, CFrame.Angles(squat, 0, 0))
	end
	for _, knee in body.knees do
		setTransform(knee, CFrame.Angles(-2 * squat, 0, 0))
	end
	for _, ankle in body.ankles do
		setTransform(ankle, CFrame.Angles(squat, 0, 0))
	end
	-- Bras : du plateau (en haut) vers l'avant, puis ils redescendent le long du corps
	if p < release then
		return TRAY_ANGLE + (DUMP_ARMS - TRAY_ANGLE) * smooth(p / release)
	end
	return DUMP_ARMS * (1 - smooth((p - release) / (1 - release)))
end

-- Appui sur le bouton a `t` secondes du debut (Npcs.PressSeconds au total). Renvoie (bras droit, coude).
-- 0 -> 0.2 : le bras se leve (coude plie) ; 0.2 -> reach : il appuie (coude tendu) ; tenu 0.05 s ;
-- puis il redescend jusqu'a la fin.
local function pressPose(t: number, length: number): (number, number)
	local reach = Npcs.PressReachSeconds
	local up = math.min(0.2, reach)
	if t < up then
		local a = quadOut(t / up)
		return PRESS_UP * a, PRESS_ELBOW * a
	elseif t < reach then
		local a = quadIn((t - up) / (reach - up))
		return PRESS_UP + (PRESS_PUSH - PRESS_UP) * a, PRESS_ELBOW * (1 - a)
	end
	local down = reach + 0.05
	if t < down then
		return PRESS_PUSH, 0
	end
	return PRESS_PUSH * (1 - smooth((t - down) / math.max(0.05, length - down))), 0
end

-- Depot des jus a `t` secondes du debut. Renvoie l'angle des deux bras.
-- 0 -> turn : bras tendus devant ; turn -> turn + toss : petit lancer (depasse un peu) ; tenu 0.15 s ;
-- puis ils redescendent (0.3 s).
local function depositPose(t: number, length: number, toss: number): number
	local turn = Npcs.DepositTurnSeconds
	if t < turn then
		return DEPOSIT_HOLD * quadOut(t / turn)
	elseif t < turn + toss then
		return DEPOSIT_HOLD + (DEPOSIT_TOSS - DEPOSIT_HOLD) * backOut((t - turn) / toss)
	end
	local down = turn + toss + 0.15
	if t < down then
		return DEPOSIT_TOSS
	end
	return DEPOSIT_TOSS * (1 - smooth((t - down) / math.max(0.05, length - down)))
end

-- Fin du geste : articulations remises a zero (l'animation d'attente reprend la main).
local function resetPick(body: Body)
	for _, joint in { body.root, body.waist, body.neck, body.rightElbow } do
		if joint then
			setTransform(joint, CFrame.identity)
		end
	end
	for _, list in { body.hips, body.knees, body.ankles } do
		for _, joint in list do
			setTransform(joint, CFrame.identity)
		end
	end
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
			local pick = if rig.r15 then gestureProgress(model, "Pick") else nil
			local dump = if rig.r15 and pick == nil then gestureProgress(model, "Dump") else nil
			local press = if rig.r15 and pick == nil and dump == nil then gestureProgress(model, "Press") else nil
			local deposit = if rig.r15 and pick == nil and dump == nil and press == nil
				then gestureProgress(model, "Deposit")
				else nil
			local gesture = pick ~= nil or dump ~= nil or press ~= nil or deposit ~= nil
			if not gesture and rig.picking then
				rig.picking = false
				if rig.body then
					resetPick(rig.body)
				end
				rig.angle = math.max(rig.angle, target) -- le bras droit est deja en haut : pas de saut
			end
			if target == 0 and rig.angle < 0.01 and not gesture then
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
				local rightAngle = angle
				if pick then
					if rig.body == nil then
						rig.body = findBody(model)
					end
					local body = rig.body
					if body then
						rig.picking = true
						rightAngle = applyPick(body, pick, target ~= 0, angle)
					end
				elseif dump then
					if rig.body == nil then
						rig.body = findBody(model)
					end
					local body = rig.body
					if body then
						rig.picking = true
						angle = applyDump(body, dump)
						rig.angle = angle -- apres le geste, les bras repartent de la (pas de saut)
						rightAngle = angle
					end
				elseif press then
					if rig.body == nil then
						rig.body = findBody(model)
					end
					local length = model:GetAttribute("PressTime") :: number
					local elbow: number
					rightAngle, elbow = pressPose(press * length, length)
					rightAngle = math.max(rightAngle, angle)
					local body = rig.body
					if body and body.rightElbow then
						rig.picking = true -- coude remis a zero a la fin
						setTransform(body.rightElbow, CFrame.Angles(elbow, 0, 0))
					end
				elseif deposit then
					local length = model:GetAttribute("DepositTime") :: number
					local toss = model:GetAttribute("DepositToss")
					angle = depositPose(deposit * length, length, if type(toss) == "number" then toss else 0.15)
					rig.angle = angle -- apres le geste, les bras repartent de la (pas de saut)
					rightAngle = angle
				end
				setTransform(right, CFrame.Angles(rightAngle, 0, 0))
				if left then
					setTransform(left, CFrame.Angles(angle, 0, 0))
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
