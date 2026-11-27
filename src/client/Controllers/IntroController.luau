--!strict
-- Cinematique d'ouverture (2026-11-22), jouee UNE fois pour un profil neuf : le serveur
-- (IntroService) pose l'attribut joueur "IntroPending" ; a la fin on envoie IntroDone.
-- Histoire (~27 s) : plan d'ouverture sur le paysage (foret, montagnes, volcan de jus), il marche
-- dans la foret, voit l'arbre DE LOIN ("!"), "Wow!" bras en l'air, court
-- jusqu'a lui, reflechit ("?"), voit la pelle plantee ("!"), l'arrache, creuse 3 fois (lever,
-- enfoncer avec le pied, soulever la terre, la jeter sur le tas), replante la pelle ; l'arbre tombe et
-- devient l'arbre niveau 1 qui vole dans ses mains ; il le brandit au-dessus de sa tete ; l'usine.
-- Pas de Skip (retire le 2026-11-22 a la demande de l'utilisateur).
-- 2026-11-27 ("plus realiste, avec des montagnes en fond comme sur la map") : fond de carte dans le
-- decor, plan d'ouverture, lumiere du matin + fond flou sur les gros plans (Intro.Mood, remis comme
-- avant a la fin), marche et course qui suivent la distance (les pieds ne glissent plus : jambes
-- posees par un petit calcul hanche / genou / cheville).
-- Tout est local, chez ce joueur seulement :
--   * decor ReplicatedStorage.IntroSet clone a Config/Intro.SetOrigin (loin de la carte), detruit a la fin ;
--   * acteur = copie de son personnage (Archivable), sans scripts ni Animator, racine ancree ; il est
--     anime en code (angles des articulations). Marche en R6 et en R15, Motor6D ou AnimationConstraint :
--     la rotation voulue est donnee dans le repere du corps (X droite, Y haut, -Z devant) puis
--     convertie pour chaque articulation. Les bras VISENT un point (mains sur la pelle, bras en l'air,
--     arbre brandi) : petit calcul de direction depuis l'epaule, buste penche / tourne compris ;
--   * camera Scriptable (plans de Intro.Shots), bandes noires, ecran blanc au debut et a la fin ;
--   * HUD et menus caches (ceux que le Preloader rallume pendant l'intro sont recaches puis rendus),
--     controles et touches E coupes. Le vrai personnage reste dans la base.
-- Ensuite : le tutoriel (TutorialController) guide le joueur ; il attend la fin de l'intro grace a
-- l'attribut LOCAL "IntroPlaying" pose ici sur le joueur.
-- Jamais de Neon. Doc : docs/systems/cinematique.md

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Intro = require(Config:WaitForChild("Intro"))
local Sounds = require(Config:WaitForChild("Sounds"))
local Remotes = require(Shared:WaitForChild("Network"):WaitForChild("Remotes"))
local SoundFx = require(Shared:WaitForChild("Util"):WaitForChild("SoundFx")) :: any

local IntroController = {}

local player = Players.LocalPlayer
local FONT = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)
local TEXT_STROKE = Color3.fromRGB(20, 16, 28)
local DIRT = Color3.fromRGB(150, 105, 62)
local DIRT_DARK = Color3.fromRGB(110, 76, 46)
local SPARKLE_GOLD = Color3.fromRGB(255, 225, 80)
-- Jamais coupes par l'intro. TouchGui (joystick, saut) appartient aux scripts de controle de Roblox :
-- on le cache par GuiService.TouchControlsEnabled (lockPlayer), pas en touchant a son ScreenGui.
local KEEP_GUIS = { IntroGui = true, IntroBubbles = true, TouchGui = true }
local TIMES = Intro.Times
local SHOVEL_LENGTH = 5.2 * Intro.ShovelScale -- poignee -> bout de la lame (studs)
local LOWER_HAND = 1.6 -- main gauche plus bas sur le manche (studs depuis la poignee)

local playing = false
local started = false
local activeLock: any = nil -- verrou en cours (rendu meme si la cinematique plante)

---------------------------------------------------------------------------------------------
-- Outils

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- Progression 0..1 de t entre a et b (lissee)
local function between(t: number, a: number, b: number): number
	return smooth((t - a) / math.max(b - a, 1e-3))
end

-- Progression 0..1 brute (non lissee)
local function linear(t: number, a: number, b: number): number
	return math.clamp((t - a) / math.max(b - a, 1e-3), 0, 1)
end

local function flatLook(from: Vector3, to: Vector3): CFrame
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if dir.Magnitude < 1e-3 then
		return CFrame.new(from)
	end
	return CFrame.lookAt(from, from + dir.Unit)
end

local function setAllParts(model: Instance, props: { [string]: any })
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			for k, v in props do
				(item :: any)[k] = v
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Acteur : copie du personnage, articulations pilotees en code

type Joint = { inst: Instance, rot: CFrame, pivot: Vector3 } -- pivot : repere de la racine, au repos
type Rig = {
	model: Model,
	root: BasePart,
	rootHeight: number,
	joints: { [string]: Joint },
	head: BasePart?,
	headTop: number, -- haut de la tete au repos (repere de la racine)
	hipHeight: number, -- hanche au-dessus du sol, debout
	thigh: number, -- hanche -> genou (R6 : toute la jambe)
	shin: number, -- genou -> cheville (R6 : 0, pas de genou)
	ankleHeight: number, -- cheville au-dessus du sol, pied a plat (R6 : 0)
}

local JOINTS = {
	-- nom logique = { R6 (parent, nom), R15 (parent, nom) }
	RightShoulder = { "Torso", "Right Shoulder", "RightUpperArm", "RightShoulder" },
	LeftShoulder = { "Torso", "Left Shoulder", "LeftUpperArm", "LeftShoulder" },
	RightHip = { "Torso", "Right Hip", "RightUpperLeg", "RightHip" },
	LeftHip = { "Torso", "Left Hip", "LeftUpperLeg", "LeftHip" },
	Neck = { "Torso", "Neck", "Head", "Neck" },
	Waist = { "HumanoidRootPart", "RootJoint", "UpperTorso", "Waist" },
	-- Genoux et coudes : R15 seulement (un avatar R6 n'en a pas, ils restent droits)
	RightKnee = { "", "", "RightLowerLeg", "RightKnee" },
	LeftKnee = { "", "", "LeftLowerLeg", "LeftKnee" },
	RightElbow = { "", "", "RightLowerArm", "RightElbow" },
	LeftElbow = { "", "", "LeftLowerArm", "LeftElbow" },
	-- Chevilles (R15) : le pied reste a plat quand il est pose, pointe vers le bas quand il pousse
	RightAnkle = { "", "", "RightFoot", "RightAnkle" },
	LeftAnkle = { "", "", "LeftFoot", "LeftAnkle" },
}

local function jointRotation(joint: Instance): CFrame?
	if joint:IsA("Motor6D") then
		return joint.C0.Rotation
	end
	if joint:IsA("AnimationConstraint") then
		local a0 = joint.Attachment0
		return if a0 then a0.CFrame.Rotation else nil
	end
	return nil
end

-- Position de repos des pieces (repere de la racine), calculee par la chaine des articulations :
-- ne depend pas de l'image d'animation en cours au moment de la copie.
local function restFrames(model: Model, root: BasePart): (BasePart) -> CFrame
	type Link = { part0: BasePart, offset: CFrame }
	local parentOf: { [BasePart]: Link } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") then
			local p0, p1 = item.Part0, item.Part1
			if p0 and p1 then
				parentOf[p1] = { part0 = p0, offset = item.C0 * item.C1:Inverse() }
			end
		elseif item:IsA("AnimationConstraint") then
			local a0, a1 = item.Attachment0, item.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				parentOf[p1] = { part0 = p0, offset = a0.CFrame * a1.CFrame:Inverse() }
			end
		end
	end
	local cache: { [BasePart]: CFrame } = {}
	local function rest(part: BasePart, depth: number): CFrame
		if part == root then
			return CFrame.identity
		end
		local known = cache[part]
		if known then
			return known
		end
		local link = parentOf[part]
		local cf = if link and depth < 16
			then rest(link.part0, depth + 1) * link.offset
			else root.CFrame:ToObjectSpace(part.CFrame)
		cache[part] = cf
		return cf
	end
	return function(part: BasePart): CFrame
		return rest(part, 0)
	end
end

local function jointPivot(joint: Instance, rest: (BasePart) -> CFrame): Vector3
	if joint:IsA("Motor6D") and joint.Part0 then
		return (rest(joint.Part0) * joint.C0).Position
	end
	if joint:IsA("AnimationConstraint") then
		local a0 = joint.Attachment0
		local p0 = a0 and a0.Parent
		if a0 and p0 and p0:IsA("BasePart") then
			return (rest(p0) * a0.CFrame).Position
		end
	end
	return Vector3.zero
end

local function makeRig(model: Model): Rig?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local rest = restFrames(model, root)
	local r6 = model:FindFirstChild("Torso") ~= nil
	local joints: { [string]: Joint } = {}
	for name, where in JOINTS do
		local parent = model:FindFirstChild(if r6 then where[1] else where[3])
		local joint = parent and parent:FindFirstChild(if r6 then where[2] else where[4])
		local rot = joint and jointRotation(joint)
		if joint and rot then
			joints[name] = { inst = joint, rot = rot, pivot = jointPivot(joint, rest) }
		end
	end
	local cf, size = model:GetBoundingBox()
	local head = model:FindFirstChild("Head")
	local headPart = if head and head:IsA("BasePart") then head else nil
	local rootHeight = root.Position.Y - (cf.Position.Y - size.Y / 2)
	-- Hauteur de la racine, pieds au sol : mesuree sur la pose de repos (chaine des articulations).
	-- La boite englobante, elle, voit la pose d'animation du moment de la copie (genoux un peu
	-- plies) : trop courte de ~0.17 stud, les pieds s'enfoncaient dans le sol (mesure le 2026-11-27).
	local lowest = math.huge
	for _, name in { "RightFoot", "LeftFoot", "Right Leg", "Left Leg" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			lowest = math.min(lowest, rest(part).Position.Y - part.Size.Y / 2)
		end
	end
	if lowest < -0.5 then
		rootHeight = -lowest
	end
	-- Mesures de la jambe (marche et course : le pied est pose par calcul)
	-- La jambe va de la hanche a la CHEVILLE : le pied, a plat, est juste sous la cheville. (Viser
	-- la semelle au bout du tibia faisait glisser le pied pose de ~1 stud / s, mesure le 2026-11-27.)
	local hip, knee, ankle = joints.RightHip, joints.RightKnee, joints.RightAnkle
	local hipHeight = math.max(if hip then hip.pivot.Y + rootHeight else rootHeight, 0.5)
	local thigh, shin, ankleHeight = hipHeight, 0, 0
	if hip and knee then
		thigh = math.max((hip.pivot - knee.pivot).Magnitude, 0.1)
		if ankle then
			shin = math.max((knee.pivot - ankle.pivot).Magnitude, 0.1)
			ankleHeight = math.max(ankle.pivot.Y + rootHeight, 0)
		else
			shin = math.max(knee.pivot.Y + rootHeight, 0.1)
		end
	end
	return {
		model = model,
		root = root,
		rootHeight = rootHeight,
		joints = joints,
		head = headPart,
		headTop = if headPart then rest(headPart).Position.Y + headPart.Size.Y / 2 else 2.5,
		hipHeight = hipHeight,
		thigh = thigh,
		shin = shin,
		ankleHeight = ankleHeight,
	}
end

-- R : rotation voulue dans le repere du corps (X droite, Y haut, -Z devant), autour de l'articulation.
local function setJoint(rig: Rig, name: string, r: CFrame)
	local joint = rig.joints[name]
	if joint then
		(joint.inst :: any).Transform = joint.rot:Inverse() * r * joint.rot
	end
end

-- swing : bras / jambe vers l'avant (rad) ; raise : ecarte sur le cote (rad, vers l'exterieur)
local function limb(swing: number, raise: number, outward: number): CFrame
	return CFrame.Angles(swing, 0, 0) * CFrame.Angles(0, 0, raise * outward)
end

type Pose = {
	ra: number, -- bras droit vers l'avant
	la: number,
	rr: number, -- bras droit ecarte
	lr: number,
	rl: number, -- jambe droite vers l'avant
	ll: number,
	head: number, -- tete : + regarde en haut
	yaw: number, -- tete tournee : + vers la gauche
	roll: number, -- tete penchee
	bend: number, -- buste : + penche en avant
	twist: number, -- buste tourne : - vers la droite
	rk: number, -- genou droit plie (R15)
	lk: number,
	re: number, -- coude droit plie (R15)
	le: number,
	rf: number, -- cheville droite : + = pointe du pied vers le haut (R15)
	lf: number,
}

local function newPose(): Pose
	return {
		ra = 0,
		la = 0,
		rr = 0,
		lr = 0,
		rl = 0,
		ll = 0,
		head = 0,
		yaw = 0,
		roll = 0,
		bend = 0,
		twist = 0,
		rk = 0,
		lk = 0,
		re = 0,
		le = 0,
		rf = 0,
		lf = 0,
	}
end

-- Champs des jambes : presque pas lisses pendant la marche et la course (sinon le pied pose glisse)
local LEG_FIELDS = { rl = true, ll = true, rk = true, lk = true, rf = true, lf = true }

local function waistRotation(p: Pose): CFrame
	return CFrame.fromEulerAnglesYXZ(-p.bend, p.twist, 0)
end

local function applyPose(rig: Rig, p: Pose)
	setJoint(rig, "RightShoulder", limb(p.ra, p.rr, 1))
	setJoint(rig, "LeftShoulder", limb(p.la, p.lr, -1))
	setJoint(rig, "RightHip", limb(p.rl, 0, 1))
	setJoint(rig, "LeftHip", limb(p.ll, 0, -1))
	setJoint(rig, "Neck", CFrame.Angles(0, p.yaw, 0) * CFrame.Angles(p.head, 0, 0) * CFrame.Angles(0, 0, p.roll))
	setJoint(rig, "Waist", waistRotation(p))
	setJoint(rig, "RightKnee", CFrame.Angles(-p.rk, 0, 0)) -- le bas de la jambe part en arriere
	setJoint(rig, "LeftKnee", CFrame.Angles(-p.lk, 0, 0))
	setJoint(rig, "RightElbow", CFrame.Angles(p.re, 0, 0)) -- l'avant-bras monte vers l'avant
	setJoint(rig, "LeftElbow", CFrame.Angles(p.le, 0, 0))
	setJoint(rig, "RightAnkle", CFrame.Angles(p.rf, 0, 0))
	setJoint(rig, "LeftAnkle", CFrame.Angles(p.lf, 0, 0))
end

---------------------------------------------------------------------------------------------
-- Marche et course (2026-11-27) : on dit ou est chaque pied (devant la hanche, au-dessus du sol) et
-- un petit calcul donne l'angle de la hanche et le pli du genou. Le pied pose recule exactement a la
-- vitesse du corps : il ne glisse plus. R6 (pas de genou) : la jambe pointe juste vers le pied.

type Foot = { x: number, y: number, pitch: number } -- x devant la hanche, y au-dessus du sol, pitch : pointe du pied (+ = haut)

-- Reglages pour une jambe de 1.62 stud (hanche -> cheville d'un avatar R15 normal) ; mis a l'echelle
-- de la vraie jambe de l'acteur (`scale`).
local REF_LEG = 1.62
local WALK_LIFT = 0.34 -- hauteur du pied qui avance (studs)
local WALK_HEEL = 0.2 -- le talon se leve a la fin de l'appui (le pied pousse sur la pointe)
local RUN_LAND, RUN_OFF, RUN_LIFT = 0.6, -1.1, 0.95 -- course : pied pose devant, quitte le sol derriere, monte haut
local RUN_HEEL = 0.35

-- Angle de la hanche (vers l'avant) et pli du genou pour que la cheville soit a (forward, down) de la hanche
local function solveLeg(rig: Rig, forward: number, down: number): (number, number)
	local a, b = rig.thigh, rig.shin
	local line = math.atan2(forward, math.max(down, 0.05))
	if b < 0.15 then
		return line, 0
	end
	local d = math.clamp(math.sqrt(forward * forward + down * down), math.abs(a - b) + 0.05, (a + b) * 0.999)
	local knee = math.pi - math.acos(math.clamp((a * a + b * b - d * d) / (2 * a * b), -1, 1))
	local inner = math.acos(math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1))
	return line + inner, knee -- la cuisse passe devant la ligne hanche-pied : le genou pointe vers l'avant
end

-- Marche. u = part du cycle (0..1) ; le pied est pose de 0.25 a 0.75 (il recule de +half a -half),
-- puis il revient en l'air. Pointe relevee a la pose (talon d'abord), baissee quand il quitte le sol.
local function walkFoot(u: number, half: number, scale: number): Foot
	local s = (u - 0.25) % 1
	if s < 0.5 then
		local k = s / 0.5
		local heel = smooth((k - 0.7) / 0.3) -- fin de l'appui : le talon se leve
		return { x = half * (1 - 2 * k), y = WALK_HEEL * scale * heel, pitch = 0.22 * math.max(0, 1 - k / 0.2) - 0.33 * heel }
	end
	local v = (s - 0.5) / 0.5
	return {
		x = half * (2 * smooth(v) - 1),
		y = (WALK_HEEL * (1 - smooth(v * 3)) + WALK_LIFT * math.sin(math.pi * v)) * scale,
		pitch = -0.33 * (1 - smooth(v * 2.5)) - 0.2 * math.sin(math.pi * math.min(v * 1.6, 1)) * (1 - v) + 0.22 * smooth((v - 0.6) / 0.4),
	}
end

-- Course. Le pied est pose pendant `duty` du cycle (court : il y a un temps en l'air), de `land`
-- devant a `off` derriere (le talon se leve a la fin) ; puis il monte haut et la jambe revient devant.
local function runFoot(u: number, duty: number, land: number, off: number, scale: number): Foot
	u %= 1
	if u < duty then
		local k = u / duty
		local heel = smooth((k - 0.55) / 0.45)
		return { x = lerp(land, off, k), y = RUN_HEEL * scale * heel, pitch = -0.6 * heel }
	end
	local v = (u - duty) / (1 - duty)
	return {
		x = lerp(off, land, smooth(v)),
		y = (RUN_HEEL * (1 - smooth(v * 3)) + RUN_LIFT * math.sin(math.pi * v ^ 0.75)) * scale,
		pitch = lerp(-0.6, 0.15, smooth(v * 1.5)),
	}
end

-- Regle les jambes de la pose pour que les pieds soient ou on veut. lift : racine montee / baissee.
-- w = 0..1 : melange avec la position debout (l'allure entre et sort en douceur).
local function placeFeet(rig: Rig, p: Pose, right: Foot, left: Foot, lift: number, w: number)
	local hip = rig.hipHeight - rig.ankleHeight + lift * w -- hanche au-dessus de la cheville d'un pied pose
	local a, k = solveLeg(rig, right.x * w, hip - right.y * w)
	p.rl, p.rk, p.rf = a, k, k - a + right.pitch * w -- cheville : pied a plat, puis la pointe
	a, k = solveLeg(rig, left.x * w, hip - left.y * w)
	p.ll, p.lk, p.lf = a, k, k - a + left.pitch * w
end

-- Angles (swing, raise) pour qu'un bras pointe dans la direction `dir` (repere de la racine),
-- buste de la pose compris. Bras au repos = vers le bas.
local function armAngles(p: Pose, right: boolean, dir: Vector3): (number, number)
	local d = waistRotation(p):VectorToObjectSpace(dir.Unit)
	local raise = math.asin(math.clamp(d.X, -1, 1))
	local swing = math.atan2(-d.Z, -d.Y)
	return swing, if right then raise else -raise
end

-- Position de l'epaule (repere de la racine) une fois le buste penche / tourne
local function shoulderAt(rig: Rig, p: Pose, right: boolean): Vector3?
	local joint = rig.joints[if right then "RightShoulder" else "LeftShoulder"]
	if joint == nil then
		return nil
	end
	local waist = rig.joints.Waist
	local w = if waist then waist.pivot else Vector3.zero
	return w + waistRotation(p):VectorToWorldSpace(joint.pivot - w)
end

-- Le bras vise un point (repere de la racine) ; k = 0..1 melange avec la pose deja la
local function reach(rig: Rig, p: Pose, right: boolean, target: Vector3, k: number)
	local shoulder = shoulderAt(rig, p, right)
	if shoulder == nil or k <= 0 then
		return
	end
	local dir = target - shoulder
	if dir.Magnitude < 1e-3 then
		return
	end
	local swing, raise = armAngles(p, right, dir)
	if right then
		p.ra = lerp(p.ra, swing, k)
		p.rr = lerp(p.rr, raise, k)
	else
		p.la = lerp(p.la, swing, k)
		p.lr = lerp(p.lr, raise, k)
	end
end

-- Le bras pointe dans une direction (repere de la racine)
local function aimDir(p: Pose, right: boolean, dir: Vector3, k: number)
	local swing, raise = armAngles(p, right, dir)
	if right then
		p.ra = lerp(p.ra, swing, k)
		p.rr = lerp(p.rr, raise, k)
	else
		p.la = lerp(p.la, swing, k)
		p.lr = lerp(p.lr, raise, k)
	end
end

local function cleanActor(actor: Model)
	actor.Name = "IntroActor"
	for _, item in actor:GetDescendants() do
		local unwanted = item:IsA("BaseScript") or item:IsA("Animator") or item:IsA("Sound")
		if unwanted or item:IsA("ProximityPrompt") or item:IsA("BillboardGui") then
			item:Destroy()
		elseif item:IsA("Motor6D") or item:IsA("AnimationConstraint") then
			-- Pas de reste de l'animation du vrai personnage. Les avatars R15 de 2026 ont des
			-- AnimationConstraint : sans cette remise a zero, l'articulation Root gardait le bassin
			-- abaisse de l'animation (0.09 a 0.17 stud) et les pieds s'enfoncaient dans le sol.
			(item :: any).Transform = CFrame.identity
		end
	end
	local all = actor:GetDescendants()
	table.insert(all, actor)
	for _, item in all do
		for _, tag in CollectionService:GetTags(item) do
			CollectionService:RemoveTag(item, tag)
		end
	end
	for name in actor:GetAttributes() do
		actor:SetAttribute(name, nil)
	end
	setAllParts(actor, { Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false })
	local humanoid = actor:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			(humanoid :: any).EvaluateStateMachine = false
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Interface : bandes noires, blanc, bulles

type Ui = { gui: ScreenGui, fade: Frame, bubbles: ScreenGui }

local function makeUi(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Bandes noires et blanc d'un bord a l'autre (2026-11-27) : avec IgnoreGuiInset seul, Roblox met
	-- DeviceSafeInsets et, sur un telephone a encoche ou a coins arrondis, ils s'arretaient avant les
	-- bords gauche et droit (iPhone 17 Pro simule : 750 px sur 874). None : tout l'ecran.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for i, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = if i == 1 then "TopBar" else "BottomBar"
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.fromScale(1, Intro.BarHeight)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Parent = gui
	end
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(1, 1, 1)
	fade.BackgroundTransparency = 0
	fade.BorderSizePixel = 0
	fade.ZIndex = 5
	fade.Parent = gui
	-- Bulles dans un ecran a part, reste en DeviceSafeInsets : son coin est celui de
	-- WorldToViewportPoint. Dans l'ecran None, une bulle tombait a cote de la tete sur un telephone
	-- a encoche (decalee de la largeur de l'encoche, vu au simulateur le 2026-11-27).
	local bubbles = Instance.new("ScreenGui")
	bubbles.Name = "IntroBubbles"
	bubbles.ResetOnSpawn = false
	bubbles.IgnoreGuiInset = true
	bubbles.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	bubbles.DisplayOrder = 201 -- au-dessus des bandes ; jamais en meme temps que le blanc
	bubbles.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	bubbles.Parent = playerGui
	return { gui = gui, fade = fade, bubbles = bubbles }
end

-- Bulle "Wow!" / "?" / "!" au-dessus de la tete. Dessinee dans l'ecran de l'intro (ScreenGui) et placee
-- sur la tete a chaque image : les BillboardGui proches de la camera ne s'affichaient pas en playtest.
type Bubble = { label: TextLabel, head: BasePart, born: number }
local bubbles: { Bubble } = {}

local function bubble(gui: ScreenGui, rig: Rig, text: string, color: Color3, lifetime: number)
	local head = rig.head
	if head == nil then
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "IntroBubble"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Size = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.ZIndex = 3
	label.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = TEXT_STROKE
	stroke.Parent = label
	label.Parent = gui
	local item: Bubble = { label = label, head = head, born = os.clock() }
	table.insert(bubbles, item)
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(190, 90),
	}):Play()
	task.delay(lifetime, function()
		if label.Parent then
			local out = TweenService:Create(label, TweenInfo.new(0.2), { Size = UDim2.fromOffset(0, 0) })
			out:Play()
			out.Completed:Wait()
		end
		label:Destroy()
		local index = table.find(bubbles, item)
		if index then
			table.remove(bubbles, index)
		end
	end)
end

local function placeBubbles(camera: Camera)
	local now = os.clock()
	for _, item in bubbles do
		local top = item.head.Position + Vector3.new(0, item.head.Size.Y / 2 + 0.6, 0)
		local point, onScreen = camera:WorldToViewportPoint(top)
		item.label.Visible = onScreen
		-- petit flottement + legere inclinaison (vivant)
		local age = now - item.born
		item.label.Position = UDim2.fromOffset(point.X, point.Y - math.sin(age * 5) * 4)
		item.label.Rotation = math.sin(age * 7) * 6 * math.max(0, 1 - age)
	end
end

---------------------------------------------------------------------------------------------
-- Effets du decor

local function holderPart(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	local holder = Instance.new("Part")
	holder.Name = name
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = size
	holder.CFrame = cf
	holder.Parent = parent
	return holder
end

local function sparkles(parent: Instance, position: Vector3, color: Color3, count: number)
	local holder = holderPart(parent, "IntroSparkles", Vector3.one, CFrame.new(position))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.LightEmission = 0.5
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- Petits cubes de terre qui giclent (physique locale), detruits apres 1.6 s
local function dirtBurst(parent: Instance, position: Vector3, away: Vector3, count: number, power: number?)
	local speed = power or 1
	for _ = 1, count do
		local cube = Instance.new("Part")
		cube.Name = "Dirt"
		local s = math.random(30, 55) / 100
		cube.Size = Vector3.new(s, s, s)
		cube.Color = DIRT:Lerp(DIRT_DARK, math.random())
		cube.Material = Enum.Material.Plastic
		cube.CanQuery = false
		cube.CanTouch = false
		cube.CastShadow = false
		cube.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		cube.AssemblyLinearVelocity = (
			away * math.random(6, 12) + Vector3.new(math.random(-4, 4), math.random(12, 19), math.random(-4, 4))
		) * speed
		cube.Parent = parent
		task.delay(1.6, function()
			cube:Destroy()
		end)
	end
end

-- Nuage de poussiere (chute de l'arbre, coups de pelle, pas de course)
local function dustBurst(parent: Instance, position: Vector3, count: number, size: number)
	local holder = holderPart(parent, "IntroDust", Vector3.new(size, 0.5, size), CFrame.new(position))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 215, 170))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.3)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.6, function()
		holder:Destroy()
	end)
end

-- Scintillement continu (arbre a decouvrir, pelle, objet a ramasser) ; Enabled pilote par la cinematique
local function twinkle(parent: Instance, cf: CFrame, size: Vector3, rate: number): ParticleEmitter
	local holder = holderPart(parent, "IntroTwinkle", size, cf)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(SPARKLE_GOLD, Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(0.3, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.5
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rate = rate
	emitter.Enabled = false
	emitter.Parent = holder
	return emitter
end

local function playSound(name: string, volumeScale: number?, pitchScale: number?)
	if SoundFx.IsEnabled() then
		-- plus doux que dans le jeu (demande utilisateur)
		SoundFx.Play(name, Intro.SoundVolume * (volumeScale or 1), pitchScale)
	end
end

-- Voix du personnage (reactions). maxSeconds : coupe le son en douceur (fondu 0.25 s) apres ce temps.
local function voice(name: string, volumeScale: number?, maxSeconds: number?)
	local def = Sounds[name]
	if def == nil or not SoundFx.IsEnabled() then
		return
	end
	if maxSeconds == nil then
		playSound(name, Intro.VoiceVolume * (volumeScale or 1))
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "IntroVoice"
	sound.SoundId = def.id
	sound.Volume = def.volume * Intro.SoundVolume * Intro.VoiceVolume * (volumeScale or 1)
	sound.PlaybackSpeed = def.pitch or 1
	sound.SoundGroup = SoundFx.Group() -- curseur Sons (menu Settings)
	sound.Parent = SoundService
	sound:Play()
	task.delay(maxSeconds, function()
		if sound.Parent then
			local fade = TweenService:Create(sound, TweenInfo.new(0.25), { Volume = 0 })
			fade:Play()
			fade.Completed:Wait()
		end
		sound:Destroy()
	end)
end

---------------------------------------------------------------------------------------------
-- HUD et controles

type Lock = {
	restore: { [ScreenGui]: boolean },
	connections: { RBXScriptConnection },
	anchored: BasePart?, -- racine du vrai personnage, ancree localement pendant l'intro
	prompts: boolean,
	touch: boolean, -- GuiService.TouchControlsEnabled d'avant l'intro
}

local function lockPlayer(): Lock
	local lock: Lock = { restore = {}, connections = {}, anchored = nil, prompts = true, touch = true }
	local playerGui = player:WaitForChild("PlayerGui")
	local function guard(gui: Instance)
		if not gui:IsA("ScreenGui") or KEEP_GUIS[gui.Name] then
			return
		end
		if gui.Enabled then
			gui.Enabled = false
			lock.restore[gui] = true
		end
		-- Le Preloader (ou un autre script) le rallume pendant l'intro : on le recache, rendu a la fin
		table.insert(
			lock.connections,
			gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if gui.Enabled then
					gui.Enabled = false
					lock.restore[gui] = true
				end
			end)
		)
	end
	for _, gui in playerGui:GetChildren() do
		guard(gui)
	end
	table.insert(lock.connections, playerGui.ChildAdded:Connect(guard))
	-- Le vrai personnage ne bouge pas pendant l'intro : racine ancree en local (le client a la main
	-- sur la physique de son personnage). PAS de require du PlayerModule : en 2026 il est dans
	-- StarterPlayer et le requerir cree une 2e camera qui reste bloquee en Scriptable (vu en test).
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		root.Anchored = true
		lock.anchored = root
	end
	pcall(function()
		lock.prompts = (ProximityPromptService :: any).Enabled;
		(ProximityPromptService :: any).Enabled = false
	end)
	-- Telephone : joystick et bouton de saut caches pendant la cinematique (2026-11-27, demande de
	-- l'utilisateur), rendus a la fin. Recaches si un autre script les rallume entre-temps.
	lock.touch = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	table.insert(
		lock.connections,
		GuiService:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(function()
			if GuiService.TouchControlsEnabled then
				GuiService.TouchControlsEnabled = false
			end
		end)
	)
	return lock
end

local function unlockPlayer(lock: Lock)
	for _, connection in lock.connections do
		connection:Disconnect()
	end
	for gui in lock.restore do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	if lock.anchored and lock.anchored.Parent then
		lock.anchored.Anchored = false
	end
	pcall(function()
		(ProximityPromptService :: any).Enabled = lock.prompts
	end)
	GuiService.TouchControlsEnabled = lock.touch -- apres le Disconnect (sinon recache tout de suite)
end

---------------------------------------------------------------------------------------------
-- Pelle : position de la poignee dans le repere de la racine, inclinaison du manche (deg, 0 = manche
-- vers le bas, + = lame vers l'avant), rotation (deg, - = lame vers la droite), et pose du buste.

type Grip = { pos: Vector3, tilt: number, yaw: number, bend: number, twist: number }

local CARRY: Grip = { pos = Vector3.new(0.5, 0.2, -1.1), tilt = 62, yaw = 0, bend = 0.05, twist = 0 }
local RAISE: Grip = { pos = Vector3.new(0.35, 1.2, -1.0), tilt = 58, yaw = 0, bend = -0.06, twist = 0 }
local PLUNGE: Grip = { pos = Vector3.new(0.35, 0.3, -1.5), tilt = 30, yaw = 0, bend = 0.25, twist = 0 }
local PUSHED: Grip = { pos = Vector3.new(0.35, 0.05, -1.5), tilt = 30, yaw = 0, bend = 0.28, twist = 0 } -- pied sur la lame
local PRY: Grip = { pos = Vector3.new(0.35, -0.2, -0.45), tilt = 60, yaw = 0, bend = 0.35, twist = 0 }
local THROW: Grip = { pos = Vector3.new(0.9, 1.1, -0.6), tilt = 110, yaw = -85, bend = 0.05, twist = -0.7 } -- lame vers sa droite (le tas)
-- Moments du coup de pelle (part du cycle 0..1)
local DIG_RAISE, DIG_HIT, DIG_PRY, DIG_LIFT, DIG_THROW, DIG_RELEASE = 0.25, 0.4, 0.5, 0.68, 0.8, 0.78

local function gripLerp(a: Grip, b: Grip, k: number): Grip
	return {
		pos = a.pos:Lerp(b.pos, k),
		tilt = lerp(a.tilt, b.tilt, k),
		yaw = lerp(a.yaw, b.yaw, k),
		bend = lerp(a.bend, b.bend, k),
		twist = lerp(a.twist, b.twist, k),
	}
end

-- Les poignees sont reglees pour une racine a 3 studs du sol ; corrige pour la vraie hauteur de l'acteur
local gripDrop = 0

local function gripFrame(g: Grip): CFrame
	return CFrame.new(g.pos + Vector3.new(0, gripDrop, 0)) * CFrame.Angles(0, math.rad(g.yaw), 0) * CFrame.Angles(math.rad(g.tilt), 0, 0)
end

-- Pelle plantee : bout de la lame a `tip` (enfoncee), manche penche vers `lean`
local function plantedFrame(tip: Vector3, lean: Vector3, amount: number): CFrame
	local up = (Vector3.yAxis + lean * amount).Unit
	return CFrame.lookAt(tip, tip + up) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.new(0, SHOVEL_LENGTH, 0)
end

---------------------------------------------------------------------------------------------
-- Lumiere de cinema (2026-11-27, Config/Intro.Mood) : soleil du matin, image un peu plus chaude,
-- fond flou sur les gros plans. Local (ce joueur seulement) et rendu a la fin : chaque valeur
-- changee est notee puis remise. Low Quality (ombres coupees par SettingsController) : ni flou ni
-- rayons. Atmosphere.Density / Haze / Glare ne sont PAS touches : Low Quality les sauvegarde et les
-- remet lui-meme (deux scripts qui "rendent" la meme valeur se marcheraient dessus).

type Mood = { restore: () -> (), dof: DepthOfFieldEffect? }
local activeMood: Mood? = nil -- rendue meme si la cinematique plante

local function applyMood(): Mood
	local mood = Intro.Mood
	local saved: { { inst: Instance, prop: string, value: any } } = {}
	local made: { Instance } = {}
	local function set(inst: Instance, prop: string, value: any)
		table.insert(saved, { inst = inst, prop = prop, value = (inst :: any)[prop] });
		(inst :: any)[prop] = value
	end
	local lowQuality = not Lighting.GlobalShadows
	set(Lighting, "ClockTime", mood.ClockTime)
	set(Lighting, "GeographicLatitude", mood.GeographicLatitude)
	set(Lighting, "Brightness", mood.Brightness)
	set(Lighting, "ColorShift_Top", mood.ColorShiftTop)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		set(atmosphere, "Color", mood.AtmosphereColor)
		set(atmosphere, "Decay", mood.AtmosphereDecay)
	end
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "IntroGrade"
	grade.Contrast = mood.Contrast
	grade.Saturation = mood.Saturation
	grade.TintColor = mood.Tint
	grade.Parent = Lighting
	table.insert(made, grade)
	local dof: DepthOfFieldEffect? = nil
	if not lowQuality then
		local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
		if rays then
			set(rays, "Intensity", mood.SunRaysIntensity)
			set(rays, "Spread", mood.SunRaysSpread)
		end
		local effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "IntroDof"
		effect.Enabled = false
		effect.NearIntensity = 0
		effect.FarIntensity = 0
		effect.InFocusRadius = mood.FocusRadius
		effect.Parent = Lighting
		table.insert(made, effect)
		dof = effect
	end
	local restored = false
	return {
		dof = dof,
		restore = function()
			if restored then
				return
			end
			restored = true
			for i = #saved, 1, -1 do
				local item = saved[i]
				pcall(function()
					(item.inst :: any)[item.prop] = item.value
				end)
			end
			for _, inst in made do
				inst:Destroy()
			end
		end,
	}
end

---------------------------------------------------------------------------------------------
-- La cinematique

local function waitForAppearance(character: Model)
	local startedAt = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - startedAt < Intro.AppearanceWaitSeconds do
		task.wait(0.1)
	end
	character:WaitForChild("HumanoidRootPart", 5)
end

-- Arrivee dans l'usine sans a-coup (2026-11-27). Appele sous le blanc de la fin, camera Scriptable.
-- Avant, l'usine n'etait dessinee que 0.15 s sous le blanc : sa premiere image (maillages, textures,
-- ecrans 3D) tombait pendant que le blanc s'effacait. Ici : tour de camera autour du personnage
-- (chaque cote de l'usine dessine une fois), puis attente de la carte (streaming, prechargement du
-- Preloader : attribut "PreloadDone") et d'une image fluide. Jamais plus de ArrivalMaxWait.
-- task.wait (pas RenderStepped) : si le rendu est en pause (fenetre reduite), le delai max joue.
local function warmArrival(camera: Camera, focus: Vector3, final: CFrame)
	local startedAt = os.clock()
	local streamed = false
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(focus, Intro.ArrivalMaxWait)
		end)
		streamed = true
	end)
	local smoothFrames = 0
	local worstFrame = 0
	local frames = RunService.PreRender:Connect(function(dt: number)
		worstFrame = math.max(worstFrame, dt)
		smoothFrames = if dt <= Intro.ArrivalSmoothFrameSeconds then smoothFrames + 1 else 0
	end)
	camera.CameraType = Enum.CameraType.Scriptable
	local offset = final.Position - focus
	for i = 1, Intro.ArrivalSweepSteps do
		local turn = CFrame.Angles(0, i / Intro.ArrivalSweepSteps * math.pi * 2, 0)
		camera.CFrame = CFrame.lookAt(focus + turn:VectorToWorldSpace(offset), focus)
		task.wait()
	end
	camera.CFrame = final
	local holdFrom = os.clock()
	smoothFrames = 0
	while os.clock() - startedAt < Intro.ArrivalMaxWait do
		task.wait()
		if
			os.clock() - holdFrom >= Intro.ArrivalMinHold
			and streamed
			and player:GetAttribute("PreloadDone") == true
			and smoothFrames >= Intro.ArrivalSmoothFrames
		then
			break
		end
	end
	frames:Disconnect()
	if RunService:IsStudio() then
		print(
			`[IntroController] arrivee : blanc tenu {math.floor((os.clock() - startedAt) * 100) / 100} s,`
				.. ` streaming {streamed}, prechargement {player:GetAttribute("PreloadDone") == true},`
				.. ` pire image {math.floor(worstFrame * 1000)} ms`
		)
	end
end

local function play()
	local ui = makeUi()
	local lock = lockPlayer()
	activeLock = lock
	local origin = CFrame.new(Intro.SetOrigin)
	local character = player.Character or player.CharacterAdded:Wait()
	waitForAppearance(character)
	local template = ReplicatedStorage:WaitForChild("IntroSet", 10)
	local camera = workspace.CurrentCamera
	local cameraBefore = camera.CFrame -- (secours si le personnage n'a plus de racine a la fin)

	-- Decor et acteur ---------------------------------------------------------------------
	local set: Model? = nil
	local rig: Rig? = nil
	if template and template:IsA("Model") and character.Parent then
		local clone = template:Clone()
		clone:PivotTo(origin)
		local ground = clone:FindFirstChild("Ground")
		if ground and ground:IsA("BasePart") then
			ground.CanCollide = true -- les cubes de terre et les fruits rebondissent dessus
		end
		clone.Parent = workspace
		set = clone
		local wasArchivable = character.Archivable
		character.Archivable = true
		local ok, actor = pcall(function()
			return character:Clone()
		end)
		character.Archivable = wasArchivable
		if ok and actor then
			cleanActor(actor)
			rig = makeRig(actor)
			if rig then
				rig.root.Anchored = true
				actor.Parent = clone
			else
				actor:Destroy()
			end
		end
	end

	local birds: Sound? = nil
	local finished = false
	local connections: { RBXScriptConnection } = {}

	local function finish()
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		-- Blanc (deja blanc en fin normale), puis retour dans l'usine
		local fade = ui.fade
		if fade.BackgroundTransparency > 0.01 then
			local tween = TweenService:Create(fade, TweenInfo.new(0.25), { BackgroundTransparency = 0 })
			tween:Play()
			tween.Completed:Wait()
		end
		if birds then
			birds:Destroy()
		end
		if set then
			set:Destroy()
		end
		-- Lumiere du jeu remise sous le blanc, avant de dessiner l'usine
		if activeMood then
			activeMood.restore()
			activeMood = nil
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		camera.FieldOfView = 70
		local live = player.Character
		local liveRoot = live and live:FindFirstChild("HumanoidRootPart")
		local exitFrame = cameraBefore
		local exitFocus: Vector3? = nil
		if liveRoot and liveRoot:IsA("BasePart") then
			-- Camera derriere le personnage, dans le sens ou il regarde (vers l'usine). Pas la vue d'avant
			-- l'intro : le serveur pose le personnage dans sa base APRES le debut de l'intro (vu en test :
			-- camera de cote contre un mur).
			local look = liveRoot.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
			local focus = liveRoot.Position + Vector3.new(0, 1.5, 0)
			exitFrame = CFrame.lookAt(focus - flat * Intro.ExitCameraDistance + Vector3.new(0, Intro.ExitCameraHeight, 0), focus)
			exitFocus = focus
		end
		-- Sous le blanc : l'usine est dessinee et chargee avant d'etre montree (pas d'a-coup a l'arrivee)
		if exitFocus then
			pcall(warmArrival, camera, exitFocus, exitFrame)
		end
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CFrame = exitFrame
		if exitFocus then
			camera.Focus = CFrame.new(exitFocus)
		end
		-- Arrivee dans l'usine : etincelles autour de l'arbre niveau 1 dans les mains
		if liveRoot and liveRoot:IsA("BasePart") then
			sparkles(workspace, (liveRoot.CFrame * Intro.HoldOffset).Position + Vector3.new(0, 1.5, 0), SPARKLE_GOLD, 30)
		end
		for _, child in ui.gui:GetChildren() do
			if child ~= fade then
				child:Destroy()
			end
		end
		ui.bubbles:Destroy()
		unlockPlayer(lock)
		activeLock = nil
		local remote = Remotes.WaitClientEvent("IntroDone")
		if remote then
			remote:FireServer()
		end
		task.wait(0.15)
		local out = TweenService:Create(fade, TweenInfo.new(Intro.FadeOutSeconds), { BackgroundTransparency = 1 })
		out:Play()
		out.Completed:Wait()
		ui.gui:Destroy()
		playing = false
		player:SetAttribute("IntroPlaying", false)
	end

	if set == nil or rig == nil then
		finish()
		return
	end
	local actorRig: Rig = rig
	local setModel: Model = set
	gripDrop = math.clamp(3 - actorRig.rootHeight, -2, 1)

	-- Lumiere de cinema (sous le blanc du debut) ; rendue dans finish()
	local mood = applyMood()
	activeMood = mood
	-- Fumee du volcan deja la au 1er plan (sinon le panache met 10 s a se former) : des bouffees
	-- "deja vieilles" posees le long du panache (taille et transparence de leur age), qui finissent
	-- leur vie normalement. (ParticleEmitter:FastForward est reserve a Roblox.) Pas en Low Quality.
	local volcano = setModel:FindFirstChild("Backdrop") and (setModel :: any).Backdrop:FindFirstChild("Volcano")
	local smoke = volcano and volcano:FindFirstChild("Smoke", true)
	local smokeSource = smoke and smoke.Parent
	if smoke and smoke:IsA("ParticleEmitter") and smokeSource and smokeSource:IsA("BasePart") and Lighting.GlobalShadows then
		local life = smoke.Lifetime.Max
		local speed = (smoke.Speed.Min + smoke.Speed.Max) / 2
		local sizes = smoke.Size.Keypoints
		local size0, size1 = sizes[1].Value, sizes[#sizes].Value
		for age = 1.2, life - 1.5, 1.2 do
			local k = age / life
			local puff = smoke:Clone()
			puff.Rate = 0
			puff.Lifetime = NumberRange.new(life - age)
			puff.Size = NumberSequence.new(lerp(size0, size1, k), size1)
			puff.Transparency = NumberSequence.new(if k < 0.6 then lerp(0.1, 0.35, k / 0.6) else lerp(0.35, 1, (k - 0.6) / 0.4), 1)
			local where = smokeSource.Position + Vector3.yAxis * (speed * age) + smoke.Acceleration * (age * age / 2)
			puff.Parent = holderPart(volcano :: Instance, "SmokePuff", Vector3.one, CFrame.new(where))
			puff:Emit(2)
		end
	end

	-- Pieces du decor
	local bigTree = setModel:FindFirstChild("BigTree") :: Model?
	local sapling = setModel:FindFirstChild("Sapling") :: Model?
	local shovel = setModel:FindFirstChild("Shovel") :: Model?
	local hole = setModel:FindFirstChild("Hole") :: BasePart?
	local pile = setModel:FindFirstChild("DirtPile") :: BasePart?
	local holeSize = if hole then hole.Size else Vector3.one
	local pileSize = if pile then pile.Size else Vector3.one
	-- Trou et tas de terre places depuis la Config (au pied de l'acteur)
	if hole then
		hole.CFrame = origin * CFrame.new(Intro.DigSpot + Intro.HoleOffset + Vector3.new(0, hole.Size.Y / 2, 0))
	end
	local pileBase = origin * CFrame.new(Intro.DigSpot + Intro.PileOffset)
	if pile then
		pile.CFrame = pileBase * CFrame.new(0, pile.Size.Y / 2, 0)
	end
	local saplingScale = if sapling then sapling:GetScale() else 1
	local bigScale = if bigTree then bigTree:GetScale() else 1
	local function hide(model: Model?)
		if model then
			model:PivotTo(origin * CFrame.new(0, -500, 0))
		end
	end
	hide(sapling)

	-- Positions de l'histoire (repere du decor)
	local treeSpot = Intro.TreeSpot
	local shovelSpot = Intro.ShovelSpot
	local toActor = Vector3.new(Intro.ActorStop.X - shovelSpot.X, 0, Intro.ActorStop.Z - shovelSpot.Z).Unit
	local grabSpot = shovelSpot + toActor * Intro.ShovelReach
	local walkDir = flatLook(Intro.ActorStart, Intro.NoticeSpot)
	local noticeLook = flatLook(Intro.NoticeSpot, treeSpot)
	local runDir = flatLook(Intro.NoticeSpot, Intro.ActorStop)
	local toTree = flatLook(Intro.ActorStop, treeSpot)
	local faceShovel = flatLook(grabSpot, shovelSpot)
	local digLook = flatLook(Intro.DigSpot, treeSpot)
	-- Pelle plantee au depart (penchee vers lui), puis replantee a sa gauche apres le creusage
	local stuckCf = origin * plantedFrame(shovelSpot - Vector3.new(0, Intro.ShovelDepth, 0), toActor, 0.22)
	local restSpot = Intro.DigSpot - digLook.RightVector * Intro.ShovelRestSide + digLook.LookVector * 0.4
	local restCf = origin * plantedFrame(restSpot - Vector3.new(0, Intro.ShovelDepth * 0.7, 0), -digLook.RightVector, 0.18)
	if shovel then
		shovel:ScaleTo(Intro.ShovelScale)
		shovel:PivotTo(stuckCf)
	end

	-- L'arbre a decouvrir scintille ; la pelle et l'objet a ramasser brillent
	local treeTwinkle: ParticleEmitter? = nil
	if bigTree then
		local cf, size = bigTree:GetBoundingBox()
		treeTwinkle = twinkle(setModel, cf * CFrame.new(0, size.Y * 0.2, 0), Vector3.new(size.X, size.Y * 0.55, size.Z), 30)
	end
	local shovelTwinkle = twinkle(setModel, stuckCf * CFrame.new(0, -SHOVEL_LENGTH / 2, 0), Vector3.new(1.5, SHOVEL_LENGTH, 1.5), 18)
	local itemTwinkle = twinkle(setModel, origin * CFrame.new(Intro.ItemSpot + Vector3.new(0, 0.8, 0)), Vector3.new(2.5, 2.5, 2.5), 30)

	-- Secousses de camera et "coups de zoom" (os.clock de depart, force, duree)
	type Kick = { at: number, amount: number, seconds: number }
	local shakes: { Kick } = {}
	local fovKicks: { Kick } = {}
	local function shake(def: { degrees: number, seconds: number })
		table.insert(shakes, { at = os.clock(), amount = def.degrees, seconds = def.seconds })
	end
	local function fovKick(amount: number, seconds: number)
		table.insert(fovKicks, { at = os.clock(), amount = amount, seconds = seconds })
	end

	if SoundFx.IsEnabled() then
		local def = Sounds.IntroBirds
		local sound = Instance.new("Sound")
		sound.Name = "IntroBirds"
		sound.SoundId = def.id
		sound.Volume = def.volume * Intro.BirdsVolume
		sound.Looped = true
		sound.SoundGroup = SoundFx.Group() -- curseur Sons (menu Settings)
		sound.Parent = SoundService
		sound:Play()
		birds = sound
	end

	-- Position de l'acteur (repere du decor, y = 0 au sol), direction et allure.
	-- Marche et course suivent la DISTANCE parcourue (2026-11-27) : `phase` avance de pi a chaque pas
	-- (un nombre entier de pas par trajet), `stride` = longueur d'un cycle (2 pas), `weight` = l'allure
	-- entre et sort en douceur. `id` : numero du trajet (bruits de pas).
	type Gait = "idle" | "walk" | "run"
	type Move = { gait: Gait, id: number, phase: number, weight: number, stride: number }
	local IDLE: Move = { gait = "idle", id = 0, phase = 0, weight = 0, stride = 1 }
	local function moving(gait: Gait, id: number, dist: number, k: number, weight: number): Move
		local wanted = if gait == "run" then Intro.RunStride else Intro.WalkStride
		local steps = math.max(1, math.round(dist / (wanted / 2) + 0.2)) -- plutot un pas de plus que des pas trop grands
		return { gait = gait, id = id, phase = math.pi * steps * k, weight = weight, stride = 2 * dist / steps }
	end
	local function edge(t: number, from: number, to: number): number
		return smooth(math.min((t - from) / 0.25, (to - t) / 0.25, 1))
	end
	local walkDist = (Intro.NoticeSpot - Intro.ActorStart).Magnitude
	local runDist = (Intro.ActorStop - Intro.NoticeSpot).Magnitude
	local shovelDist = (grabSpot - Intro.ActorStop).Magnitude
	local carryDist = (Intro.DigSpot - grabSpot).Magnitude
	local WALK_BRAKE = 0.92 -- part du trajet a vitesse constante, puis il ralentit jusqu'a l'arret
	local function turn(a: CFrame, b: CFrame, k: number): CFrame
		return a.Rotation:Lerp(b.Rotation, k)
	end
	local function actorBase(t: number): (CFrame, Move)
		if t < TIMES.notice then
			-- vitesse constante, puis freinage doux sur la fin (vitesse nulle a l'arret, sans a-coup)
			local u = math.max(t, 0) / TIMES.notice
			local speed = 2 / (1 + WALK_BRAKE)
			local k = speed * u
			if u > WALK_BRAKE then
				k -= speed * (u - WALK_BRAKE) ^ 2 / (2 * (1 - WALK_BRAKE))
			end
			local move = moving("walk", 1, walkDist, k, edge(t, -1, TIMES.notice))
			return walkDir.Rotation + Intro.ActorStart:Lerp(Intro.NoticeSpot, k), move
		elseif t < TIMES.run then
			local k = between(t, TIMES.notice + 0.15, TIMES.notice + 0.5)
			return turn(walkDir, noticeLook, k) + Intro.NoticeSpot, IDLE
		elseif t < TIMES.arrive then
			local u = linear(t, TIMES.run, TIMES.arrive)
			local k = 0.6 * (1 - (1 - u) ^ 1.6) + 0.4 * u -- depart rapide, freine un peu a l'arrivee
			local rot = turn(noticeLook, runDir, between(t, TIMES.run, TIMES.run + 0.2))
			local move = moving("run", 2, runDist, k, edge(t, TIMES.run - 0.1, TIMES.arrive + 0.1))
			return rot + Intro.NoticeSpot:Lerp(Intro.ActorStop, k), move
		elseif t < TIMES.toShovel then
			local k = between(t, TIMES.arrive, TIMES.arrive + 0.5)
			return turn(runDir, toTree, k) + Intro.ActorStop, IDLE
		elseif t < TIMES.pull then
			local k = smooth(linear(t, TIMES.toShovel, TIMES.pull))
			local rot = turn(toTree, faceShovel, between(t, TIMES.toShovel, TIMES.toShovel + 0.3))
			local move = moving("walk", 3, shovelDist, k, edge(t, TIMES.toShovel, TIMES.pull))
			return rot + Intro.ActorStop:Lerp(grabSpot, k), move
		elseif t < TIMES.carry then
			return faceShovel.Rotation + grabSpot, IDLE
		elseif t < TIMES.digStart then
			local k = smooth(linear(t, TIMES.carry, TIMES.digStart))
			local rot = turn(faceShovel, flatLook(grabSpot, Intro.DigSpot), between(t, TIMES.carry, TIMES.carry + 0.2))
			rot = turn(rot, digLook, between(t, TIMES.digStart - 0.25, TIMES.digStart))
			local move = moving("walk", 4, carryDist, k, edge(t, TIMES.carry, TIMES.digStart))
			return rot + grabSpot:Lerp(Intro.DigSpot, k), move
		end
		return digLook.Rotation + Intro.DigSpot, IDLE
	end

	-- Repere de l'acteur pour la camera (hauteur du centre, sans rebond)
	local function actorFrame(t: number): CFrame
		local base = actorBase(t)
		return origin * (base + Vector3.new(0, actorRig.rootHeight, 0))
	end

	-- Coup de pelle : poignee et buste a l'instant t (repere de la racine)
	local cycle = (TIMES.digEnd - TIMES.digStart) / Intro.Digs
	local function digGrip(t: number): Grip
		if t < TIMES.digStart then
			return CARRY
		end
		local index = math.min(math.floor((t - TIMES.digStart) / cycle), Intro.Digs - 1)
		local u = math.clamp((t - TIMES.digStart - index * cycle) / cycle, 0, 1)
		local from = if index == 0 then CARRY else THROW
		if u < DIG_RAISE then
			return gripLerp(from, RAISE, smooth(u / DIG_RAISE))
		elseif u < DIG_HIT then
			local k = (u - DIG_RAISE) / (DIG_HIT - DIG_RAISE)
			return gripLerp(RAISE, PLUNGE, k * k) -- acceleration : on sent l'impact
		elseif u < DIG_PRY then
			-- le pied appuie sur la lame : elle s'enfonce encore un peu
			return gripLerp(PLUNGE, PUSHED, smooth((u - DIG_HIT) / (DIG_PRY - DIG_HIT)))
		elseif u < DIG_LIFT then
			return gripLerp(PUSHED, PRY, smooth((u - DIG_PRY) / (DIG_LIFT - DIG_PRY)))
		elseif u < DIG_THROW then
			return gripLerp(PRY, THROW, smooth((u - DIG_LIFT) / (DIG_THROW - DIG_LIFT)))
		end
		return THROW
	end
	-- Pied droit sur la lame pendant le coup (lever puis appuyer)
	local function digFoot(t: number): number
		if t < TIMES.digStart or t >= TIMES.digEnd then
			return 0
		end
		local u = ((t - TIMES.digStart) % cycle) / cycle
		if u > DIG_RAISE and u < DIG_HIT then
			return 0.55 * smooth((u - DIG_RAISE) / (DIG_HIT - DIG_RAISE))
		elseif u >= DIG_HIT and u < DIG_LIFT then
			return lerp(0.55, 0, smooth((u - DIG_HIT) / (DIG_LIFT - DIG_HIT)))
		end
		return 0
	end

	-- Pelle dans le monde a l'instant t ; hands = 0..1 (mains sur le manche)
	local function shovelAt(t: number, rootCf: CFrame): (CFrame, number)
		if t < TIMES.pull then
			-- plantee ; il tend les mains vers elle juste avant de l'attraper
			return stuckCf, between(t, TIMES.pull - 0.25, TIMES.pull)
		elseif t < TIMES.pull + 0.2 then
			return stuckCf, 1
		elseif t < TIMES.pull + 0.4 then
			-- il l'arrache : elle sort du sol et se redresse
			local k = between(t, TIMES.pull + 0.2, TIMES.pull + 0.4)
			local yanked = (stuckCf.Rotation:Lerp(faceShovel.Rotation, 0.6) + stuckCf.Position) + Vector3.new(0, 1.6, 0)
			return stuckCf:Lerp(yanked, k), 1
		elseif t < TIMES.carry then
			local yanked = (stuckCf.Rotation:Lerp(faceShovel.Rotation, 0.6) + stuckCf.Position) + Vector3.new(0, 1.6, 0)
			return yanked:Lerp(rootCf * gripFrame(CARRY), between(t, TIMES.pull + 0.4, TIMES.carry)), 1
		elseif t < TIMES.digEnd then
			return rootCf * gripFrame(digGrip(t)), 1
		elseif t < TIMES.digEnd + 0.3 then
			-- il la replante a cote de lui
			local k = between(t, TIMES.digEnd, TIMES.digEnd + 0.3)
			return (rootCf * gripFrame(THROW)):Lerp(restCf, k), 1 - between(t, TIMES.digEnd + 0.15, TIMES.digEnd + 0.3)
		end
		return restCf, 0
	end

	-- Pose de l'acteur a l'instant t (+ rebond vertical). Les bras qui tiennent quelque chose sont
	-- regles ensuite (reach) dans step().
	local holdAngle = math.rad(Intro.HoldArmDegrees)
	local legLength = actorRig.thigh + actorRig.shin
	local standReach = actorRig.hipHeight - actorRig.ankleHeight -- hanche -> cheville, debout
	local legScale = math.clamp(legLength / REF_LEG, 0.5, 1.6)
	local function poseAt(t: number, move: Move): (Pose, number)
		local p = newPose()
		local lift = 0
		local w = move.weight
		local u = (move.phase / (math.pi * 2)) % 1 -- part du cycle (2 pas)
		if move.gait == "walk" then
			-- Marche (2026-11-27) : les pieds sont poses par calcul (voir walkFoot / placeFeet), le pied
			-- d'appui ne glisse pas ; le corps descend un peu quand les jambes sont ecartees. Bras qui
			-- balancent a l'oppose des jambes, coudes un peu plies, epaules qui tournent a l'oppose du bassin.
			local half = math.min(move.stride / 4, legLength * 0.7)
			local right, left = walkFoot(u, half, legScale), walkFoot(u + 0.5, half, legScale)
			local planted = if (u - 0.25) % 1 < 0.5 then right.x else left.x
			lift = math.min(0, math.sqrt(math.max((legLength * 0.985) ^ 2 - planted ^ 2, 0.04)) - standReach)
			placeFeet(actorRig, p, right, left, lift, w)
			lift *= w
			local swing = math.sin(move.phase) -- + : jambe droite devant
			p.ra = -swing * 0.42 * w
			p.la = swing * 0.42 * w
			p.rr = 0.07
			p.lr = 0.07
			p.re = 0.2 + math.max(0, -swing) * 0.3 * w -- le bras qui passe devant plie davantage
			p.le = 0.2 + math.max(0, swing) * 0.3 * w
			p.bend = 0.05 * w
			p.twist = -swing * 0.09 * w
			p.roll = -swing * 0.03 * w
			p.head = -0.02 * w
			if move.id == 1 then
				-- il regarde la foret autour de lui en marchant (puis droit devant avant de voir l'arbre)
				local curious = between(t, 0.4, 1.2) * (1 - between(t, TIMES.notice - 1.3, TIMES.notice - 0.6))
				p.yaw = math.sin(t * 1.35 + 0.6) * 0.45 * curious
				p.head += (0.1 + math.sin(t * 0.9) * 0.06) * curious
			end
		elseif move.gait == "run" then
			-- Course (2026-11-27) : grandes foulees avec un temps en l'air (pied pose court, talon qui
			-- monte haut derriere), le corps s'ecrase a l'appui et decolle entre deux pas ; buste en
			-- avant, bras plies a angle droit qui pompent.
			local land, off = RUN_LAND * legScale, RUN_OFF * legScale
			local duty = math.clamp((land - off) / move.stride, 0.15, 0.45)
			local right, left = runFoot(u, duty, land, off, legScale), runFoot(u + 0.5, duty, land, off, legScale)
			local half = (u * 2) % 1 -- un pas
			local ground = duty * 2
			lift = if half < ground
				then (-0.18 - 0.2 * math.sin(math.pi * half / ground)) * legScale
				else (-0.18 + 0.38 * math.sin(math.pi * (half - ground) / (1 - ground))) * legScale
			placeFeet(actorRig, p, right, left, lift, w)
			lift *= w
			local swing = math.cos(move.phase) -- + : jambe droite devant (elle se pose a u = 0)
			p.ra = (0.2 - swing * 0.8) * w
			p.la = (0.2 + swing * 0.8) * w
			p.re = 1.4 * w
			p.le = 1.4 * w
			p.rr = 0.15
			p.lr = 0.15
			p.bend = 0.3 * w
			p.twist = -swing * 0.13 * w
			p.head = 0.17 * w
		else
			-- Debout : respiration, poids qui passe doucement d'une jambe a l'autre, bras detendus
			p.bend = math.sin(t * 2.4) * 0.02
			p.twist = math.sin(t * 0.9) * 0.02
			p.rr = 0.05
			p.lr = 0.05
			p.re = 0.12
			p.le = 0.12
		end

		if t >= TIMES.notice and t < TIMES.wow then
			-- Il s'arrete net, leve la tete d'un coup (double prise), puis fixe l'arbre au loin
			local snap = between(t, TIMES.notice, TIMES.notice + 0.12)
			local take = (t - TIMES.notice) / 0.35
			p.head = 0.32 * snap
			p.yaw = if take < 1 then math.sin(take * math.pi * 2) * 0.25 * (1 - take) else 0
			p.bend += -0.08 * snap -- recule un peu le buste (surpris)
			local k = between(t, TIMES.notice, TIMES.notice + 0.2)
			p.ra = lerp(p.ra, 0.15, k)
			p.la = lerp(p.la, 0.15, k)
			p.rr = 0.12 * k
			p.lr = 0.12 * k
			if t < TIMES.notice + 0.3 then
				p.rl *= 1 - k
				p.ll *= 1 - k
			else
				p.rl, p.ll = 0, 0
			end
		elseif t >= TIMES.wow and t < TIMES.run then
			-- Wow ! petite prise d'elan (accroupi), puis saut bras tendus en V au-dessus de la tete,
			-- mains qui tremblent de joie ; les bras redescendent avant la course
			local crouch = between(t, TIMES.wow, TIMES.wow + 0.12) * (1 - between(t, TIMES.wow + 0.12, TIMES.wow + 0.2))
			local up = between(t, TIMES.wow + 0.1, TIMES.wow + 0.25) * (1 - between(t, TIMES.run - 0.35, TIMES.run))
			p.bend = 0.2 * crouch - 0.12 * up
			p.head = 0.15 * crouch + 0.35 * up
			lift = -0.25 * crouch
			local hop = (t - TIMES.wow - 0.15) / 0.5
			if hop > 0 and hop < 1 then
				lift = math.sin(hop * math.pi) * 1.2
				p.rl = 0.5 * math.sin(hop * math.pi) -- jambes repliees en l'air
				p.ll = -0.3 * math.sin(hop * math.pi)
			end
			-- bras d'abord vers le bas-arriere (elan), puis en V
			p.ra = -0.4 * crouch
			p.la = -0.4 * crouch
			local wiggle = math.sin((t - TIMES.wow) * 34) * 0.1 * up
			aimDir(p, true, Vector3.new(0.4 + wiggle, 1, -0.1), up)
			aimDir(p, false, Vector3.new(-0.4 - wiggle, 1, -0.1), up)
		elseif t >= TIMES.arrive and t < TIMES.think then
			-- Il freine (buste en arriere, bras ecartes), puis leve la tete vers l'arbre immense
			local skid = between(t, TIMES.arrive, TIMES.arrive + 0.1) * (1 - between(t, TIMES.arrive + 0.25, TIMES.arrive + 0.55))
			p.bend = -0.25 * skid
			p.rr = 0.7 * skid
			p.lr = 0.7 * skid
			p.ra = 0.3 * skid
			p.la = 0.3 * skid
			p.rl = 0.35 * skid
			p.head = 0.45 * between(t, TIMES.arrive + 0.3, TIMES.arrive + 0.8)
		elseif t >= TIMES.think and t < TIMES.idea then
			-- Il reflechit : main droite sous le menton, bras gauche plie dessous, tete penchee qui
			-- regarde en l'air et se balance (le visage reste visible : camera de trois-quarts)
			local k = between(t, TIMES.think, TIMES.think + 0.3)
			local sway = math.sin((t - TIMES.think) * 4)
			p.ra = 1.5 * k
			p.rr = -0.55 * k
			p.la = 0.75 * k
			p.lr = -0.3 * k
			p.roll = (0.2 + 0.06 * sway) * k
			p.head = 0.18 * k
		elseif t >= TIMES.idea and t < TIMES.toShovel then
			-- "!" : la tete se tourne d'un coup vers la pelle, le doigt (bras droit) la montre
			local k = between(t, TIMES.idea, TIMES.idea + 0.12)
			p.yaw = -0.7 * k
			p.head = -0.1 * k
			p.bend += -0.05 * k
			aimDir(p, true, Vector3.new(0.9, 0.1, -0.4), k)
		elseif t >= TIMES.toShovel and t < TIMES.digEnd + 0.3 then
			-- Pelle : buste du coup de pelle, regard vers la lame / le trou ; bras regles dans step()
			local g = digGrip(t)
			if t >= TIMES.digStart then
				p.bend = g.bend
				p.twist = g.twist
				p.head = -0.3
				p.yaw = g.twist * 0.6
				p.rl = digFoot(t)
			elseif t >= TIMES.pull and t < TIMES.carry then
				-- arrache : penche vers la pelle puis tire en arriere
				local pullBack = between(t, TIMES.pull + 0.15, TIMES.pull + 0.4) * (1 - between(t, TIMES.pull + 0.45, TIMES.carry))
				p.bend = 0.18 * (1 - pullBack) - 0.2 * pullBack
				p.head = -0.15
				lift = 0.15 * pullBack
			end
		elseif t >= TIMES.digEnd + 0.3 and t < TIMES.item then
			-- L'arbre tombe : surprise (mains pres du visage, recule la tete)
			local k = between(t, TIMES.digEnd + 0.2, TIMES.digEnd + 0.45)
			p.ra = 1.2 * k
			p.la = 1.2 * k
			p.rr = 0.35 * k
			p.lr = 0.35 * k
			p.head = 0.15
			p.bend = -0.1 * k
		elseif t >= TIMES.item and t < TIMES.grab then
			-- Il tend les bras vers l'arbre niveau 1
			local k = between(t, TIMES.item + 0.2, TIMES.grab)
			p.ra = holdAngle * k
			p.la = holdAngle * k
			p.head = -0.25
			p.bend = 0.12 * k
		elseif t >= TIMES.grab then
			p.ra = holdAngle
			p.la = holdAngle
			p.head = -0.1
			if t >= TIMES.raise and t < TIMES.lower + 0.3 then
				-- Il le brandit au-dessus de sa tete (bras regles dans step()), regarde en haut, sautille
				local up = between(t, TIMES.raise, TIMES.raise + 0.25) * (1 - between(t, TIMES.lower, TIMES.lower + 0.3))
				p.head = lerp(-0.1, 0.35, up)
				p.bend = -0.08 * up
				local joy = (t - TIMES.raise - 0.25) / 0.35
				if joy > 0 and joy < 2 then
					lift = math.abs(math.sin(joy * math.pi)) * 0.55
				end
			end
		end
		return p, lift
	end

	-- Camera : plan a l'instant t
	local function shotPoint(shot: Intro.Shot, t: number, field: "pos" | "look"): Vector3
		local v: Vector3 = if field == "pos" then shot.pos else shot.look
		if shot.space == "Actor" then
			return (actorFrame(t) * CFrame.new(v)).Position
		end
		return (origin * CFrame.new(v)).Position
	end
	-- Rend aussi le flou du fond voulu par le plan (0 = net)
	local function cameraAt(t: number): (CFrame, number, number)
		local shots = Intro.Shots
		local index = 1
		for i, shot in shots do
			if shot.t <= t then
				index = i
			end
		end
		local a = shots[index]
		local b = shots[index + 1]
		local pos = shotPoint(a, t, "pos")
		local look = shotPoint(a, t, "look")
		local fov = a.fov or 60
		local blur = a.blur or 0
		if b and not b.cut and b.t > a.t then
			local k = between(t, a.t, b.t)
			if a.ease == "slow" then
				k = smooth(k) -- grand mouvement de grue : depart et arrivee tres doux
			end
			pos = pos:Lerp(shotPoint(b, t, "pos"), k)
			look = look:Lerp(shotPoint(b, t, "look"), k)
			fov = lerp(fov, b.fov or fov, k)
			blur = lerp(blur, b.blur or 0, k)
		end
		return CFrame.lookAt(pos, look), fov, blur
	end

	-- Mottes de terre : sur la lame (soulevee), puis lancees en arc sur le tas
	type Clump = { part: BasePart, flying: boolean, from: Vector3, at: number }
	local clumps: { Clump } = {}
	local landed = 0
	local lastShovel = stuckCf
	local function bladePoint(cf: CFrame): CFrame
		return cf * CFrame.new(0, -4.25 * Intro.ShovelScale, -0.4)
	end
	local function newClump()
		local part = Instance.new("Part")
		part.Name = "Clump"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Size = Vector3.new(0.95, 0.5, 0.8)
		part.Color = DIRT
		part.Material = Enum.Material.Plastic
		part.CFrame = bladePoint(lastShovel)
		part.Parent = setModel
		table.insert(clumps, { part = part, flying = false, from = part.Position, at = 0 })
	end
	local function throwClump()
		local item = clumps[#clumps]
		if item and not item.flying then
			item.flying = true
			item.from = item.part.Position
			item.at = os.clock()
		end
	end
	local pileTop = (pileBase * CFrame.new(0, pileSize.Y * 0.9, 0)).Position
	local FLIGHT = 0.4
	local function updateClumps()
		local now = os.clock()
		for i = #clumps, 1, -1 do
			local item = clumps[i]
			if not item.flying then
				item.part.CFrame = bladePoint(lastShovel)
			else
				local k = (now - item.at) / FLIGHT
				if k >= 1 then
					item.part:Destroy()
					table.remove(clumps, i)
					landed += 1
					local grow = landed / Intro.Digs
					if pile then
						pile.Transparency = 0
						pile.Size = pileSize * (0.45 + 0.55 * grow)
						pile.CFrame = pileBase * CFrame.new(0, pile.Size.Y / 2, 0)
					end
					dirtBurst(setModel, pileTop, Vector3.zero, 5, 0.5)
					dustBurst(setModel, pileTop, 4, 1.5)
					playSound("FruitLand")
				else
					local pos = item.from:Lerp(pileTop, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0)
					item.part.CFrame = CFrame.new(pos) * CFrame.Angles(k * 5, k * 3, 0)
				end
			end
		end
	end

	-- Evenements (une fois chacun)
	local events: { { at: number, run: () -> (), done: boolean } } = {}
	local function at(time: number, run: () -> ())
		table.insert(events, { at = time, run = run, done = false })
	end
	local function feet(): Vector3
		local root = actorRig.root.Position
		return Vector3.new(root.X, origin.Position.Y + 0.2, root.Z)
	end
	at(TIMES.notice, function()
		-- Il a vu quelque chose au loin
		bubble(ui.bubbles, actorRig, Intro.NoticeText, Color3.fromRGB(255, 220, 60), 0.9)
		playSound("Notify")
		fovKick(Intro.NoticeFovKick, 0.35)
		if treeTwinkle then
			treeTwinkle.Enabled = true
		end
	end)
	at(TIMES.reveal + 0.1, function()
		playSound("TreeChime")
	end)
	at(TIMES.wow + 0.15, function()
		bubble(ui.bubbles, actorRig, Intro.WowText, Color3.fromRGB(255, 220, 60), 1.0)
		playSound("NewFruit")
		fovKick(Intro.WowFovKick, 0.45)
		local head = actorRig.head
		if head then
			sparkles(setModel, head.Position + Vector3.new(0, 1.5, 0), SPARKLE_GOLD, 30)
		end
	end)
	-- Pas dans l'herbe (2026-11-23) : un son par pas, une des 4 variantes au hasard (jamais 2 fois la meme).
	-- Plus doux quand la camera est loin (plan d'ouverture vu du ciel).
	local lastStep = 0
	local function footstep(volume: number, pitch: number)
		local pick = math.random(1, 3)
		lastStep = if pick >= lastStep then pick + 1 else pick
		local away = (camera.CFrame.Position - actorRig.root.Position).Magnitude
		playSound(`IntroGrass{lastStep}`, Intro.StepVolume * volume * math.clamp(16 / away, 0.15, 1), pitch)
	end
	-- Les pas de la marche et de la course sonnent quand le pied se pose (2026-11-27) : voir
	-- `strikes` dans step(), cale sur l'animation et plus sur l'horloge.
	-- Petits pas en plus (2026-11-23) : il s'arrete net, se tourne, recule, s'avance
	for _, def in
		{
			{ TIMES.notice + 0.05, 0.8, 0.95 }, -- il s'arrete net (pied qui se pose)
			{ TIMES.notice + 0.3, 0.5, 1 }, -- il se tourne vers l'arbre
			{ TIMES.notice + 0.45, 0.5, 1.05 },
			{ TIMES.arrive + 0.6, 0.6, 1 }, -- il se tourne vers l'arbre apres le freinage
			{ TIMES.toShovel + 0.02, 0.6, 1 }, -- premier pas vers la pelle
			{ TIMES.pull + 0.32, 0.7, 0.9 }, -- il recule en arrachant la pelle
			{ TIMES.carry + 0.05, 0.6, 1 }, -- il se tourne, pelle en main
			{ TIMES.digEnd + 0.4, 0.8, 0.95 }, -- il recule, surpris (l'arbre bascule)
			{ TIMES.digEnd + 0.6, 0.6, 1 },
			{ TIMES.item + 0.35, 0.6, 1.05 }, -- il s'avance vers l'arbre niveau 1
		}
	do
		local stepAt, volume, pitch = def[1], def[2], def[3]
		at(stepAt, function()
			footstep(volume, pitch)
		end)
	end

	-- Reactions du personnage (voix, 2026-11-23)
	at(TIMES.notice + 0.08, function()
		voice("IntroGasp", 0.9) -- il a vu quelque chose
	end)
	at(TIMES.wow + 0.12, function()
		voice("IntroWowVoice")
	end)
	at(TIMES.arrive + 0.35, function()
		voice("IntroPant", 0.7) -- essouffle apres la course
	end)
	at(TIMES.think + 0.1, function()
		voice("IntroHmm", 0.9, Intro.HmmSeconds)
	end)
	at(TIMES.pull + 0.18, function()
		voice("IntroGrunt2", Intro.GruntVolume) -- il tire sur la pelle
	end)
	at(TIMES.digEnd + 0.35, function()
		voice("IntroWhoa") -- l'arbre bascule
	end)
	-- Wow : saut (whoosh) puis atterrissage
	at(TIMES.wow + 0.15, function()
		playSound("IntroJump")
		playSound("IntroWhoosh", Intro.WhooshVolume, 1.15)
	end)
	at(TIMES.wow + 0.63, function()
		playSound("IntroLand")
	end)
	-- Course : gros nuage au depart et au freinage (petits nuages a chaque pas : voir `strikes`)
	at(TIMES.run, function()
		dustBurst(setModel, feet(), 6, 2)
		playSound("IntroWhoosh", Intro.WhooshVolume * 0.7, 0.9) -- il demarre en trombe
	end)
	-- Un pied se pose : bruit de pas (et poussiere en courant). Marche : le pied droit se pose a
	-- phase = pi / 2, le gauche a 3 pi / 2 ; course : a 0 et pi.
	local strikeMove, strikeIndex = 0, 0
	local function strikes(move: Move)
		if move.gait == "idle" then
			strikeMove = 0
			return
		end
		local index = math.floor((move.phase - (if move.gait == "walk" then math.pi / 2 else 0)) / math.pi)
		if move.id ~= strikeMove then
			strikeMove, strikeIndex = move.id, index
		elseif index > strikeIndex then
			strikeIndex = index
			if move.gait == "run" then
				dustBurst(setModel, feet(), 2, 1)
				footstep(1.2, 1.15) -- pas plus forts en courant
			else
				footstep(1, 1)
			end
		end
	end
	at(TIMES.arrive + 0.05, function()
		playSound("IntroSkid", 0.8, 1.2) -- freinage dans l'herbe
		dustBurst(setModel, feet() + actorRig.root.CFrame.LookVector * 0.8, 8, 2.5)
		dirtBurst(setModel, feet() + actorRig.root.CFrame.LookVector, actorRig.root.CFrame.LookVector, 5, 0.5)
	end)
	at(TIMES.think, function()
		bubble(ui.bubbles, actorRig, Intro.ThinkText, Color3.new(1, 1, 1), 0.9)
		playSound("Notify")
	end)
	at(TIMES.idea, function()
		bubble(ui.bubbles, actorRig, Intro.IdeaText, Color3.fromRGB(255, 220, 60), 0.9)
		playSound("Notify")
		shovelTwinkle.Enabled = true
		sparkles(setModel, stuckCf.Position, SPARKLE_GOLD, 15)
	end)
	at(TIMES.pull + 0.22, function()
		-- La pelle sort du sol : terre, poussiere, "pop", etincelles
		local base = (origin * CFrame.new(shovelSpot)).Position
		dirtBurst(setModel, base, Vector3.zero, 8, 0.7)
		dustBurst(setModel, base, 6, 2)
		shake(Intro.PullShake)
		shovelTwinkle.Enabled = false
		playSound("Pickup")
		playSound("CashPop", Intro.ShovelPopVolume, 0.9) -- "pop" bien net (2026-11-23)
		sparkles(setModel, stuckCf.Position, SPARKLE_GOLD, 25)
	end)
	at(TIMES.pull + 0.3, function()
		playSound("IntroWhoosh", Intro.WhooshVolume * 0.8, 0.85) -- la pelle sort d'un coup
	end)
	for i = 1, Intro.Digs do
		local start = TIMES.digStart + (i - 1) * cycle
		local hitTime = start + cycle * DIG_HIT
		at(hitTime - 0.12, function()
			playSound("IntroDig")
		end)
		at(hitTime - 0.05, function()
			-- petit effort a chaque coup de pelle (un son different a chaque fois)
			voice(if i == 1 then "IntroGrunt1" elseif i == 2 then "IntroGrunt3" else "IntroGrunt2", Intro.GruntVolume)
		end)
		at(hitTime, function()
			-- La lame entre dans le sol : terre, poussiere, secousse, le trou grandit
			local tip = lastShovel * CFrame.new(0, -SHOVEL_LENGTH, 0)
			local ground = Vector3.new(tip.Position.X, origin.Position.Y, tip.Position.Z)
			dirtBurst(setModel, ground, Vector3.zero, 7, 0.7)
			dustBurst(setModel, ground, 6, 2)
			shake(Intro.DigShake)
			local k = i / Intro.Digs
			if hole then
				hole.Transparency = 0
				hole.Size = Vector3.new(holeSize.X * (0.5 + 0.5 * k), holeSize.Y, holeSize.Z * (0.5 + 0.5 * k))
			end
		end)
		at(start + cycle * DIG_PRY, newClump)
		at(start + cycle * DIG_RELEASE, function()
			throwClump()
			playSound("IntroWhoosh", Intro.WhooshVolume * 0.6, 1.25) -- la terre part sur le tas
		end)
	end
	at(TIMES.digEnd + 0.28, function()
		-- Pelle replantee a cote de lui
		local base = (origin * CFrame.new(restSpot)).Position
		dustBurst(setModel, base, 4, 1.5)
		playSound("FruitLand")
	end)
	at(TIMES.fall - 0.05, function()
		playSound("IntroTreeCrack", Intro.CrackVolume) -- le tronc craque, il bascule
	end)
	at(TIMES.fall + 0.05, function()
		playSound("TreeBoing")
		if treeTwinkle then
			treeTwinkle.Enabled = false
		end
	end)
	at(TIMES.fallEnd, function()
		playSound("IntroTreeFall")
		playSound("IntroLeaves") -- le feuillage s'ecrase dans l'herbe
		local landing = origin * CFrame.new(treeSpot + Vector3.new(14, 0, 0))
		dirtBurst(setModel, landing.Position, Vector3.new(0, 0, 1), 12)
		dirtBurst(setModel, landing.Position, Vector3.new(0, 0, -1), 12)
		for x = 4, 22, 6 do
			dustBurst(setModel, (origin * CFrame.new(treeSpot + Vector3.new(x, 0.3, 0))).Position, 10, 4)
		end
		shake(Intro.LandShake)
		-- Les fruits sautent de l'arbre et roulent dans l'herbe
		local fruits = bigTree and bigTree:FindFirstChild("Fruits")
		for _, fruit in (if fruits then fruits:GetChildren() else {}) do
			if fruit:IsA("BasePart") then
				fruit.Parent = setModel
				fruit.Anchored = false
				fruit.CanCollide = true
				fruit.AssemblyLinearVelocity = Vector3.new(math.random(-6, 6), math.random(10, 20), math.random(-8, 8))
				fruit.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
			end
		end
	end)
	-- Les fruits retombent dans l'herbe : quelques "plocs" decales
	for i, delay in { 0.25, 0.4, 0.5, 0.65, 0.8 } do
		at(TIMES.fallEnd + delay, function()
			playSound("FruitLand", 0.7, 0.9 + i * 0.06)
		end)
	end
	at(TIMES.item, function()
		itemTwinkle.Enabled = true
		playSound("TreeChime")
		-- Le grand arbre disparait dans un nuage (vu dans le plan large)
		for x = 2, 20, 6 do
			dustBurst(setModel, (origin * CFrame.new(treeSpot + Vector3.new(x, 1, 0))).Position, 8, 4)
		end
		sparkles(setModel, (origin * CFrame.new(Intro.ItemSpot)).Position, SPARKLE_GOLD, 35)
	end)
	at(TIMES.grab, function()
		itemTwinkle.Enabled = false
		playSound("Pickup")
		playSound("IntroWhoosh", Intro.WhooshVolume, 1.1) -- il vole dans ses mains
	end)
	at(TIMES.grab + 0.3, function()
		-- Arrive dans les mains : etincelles + "boing"
		sparkles(setModel, (actorRig.root.CFrame * Intro.HoldOffset).Position + Vector3.new(0, 1.5, 0), SPARKLE_GOLD, 25)
		playSound("TreeBoing")
	end)
	at(TIMES.raise + 0.25, function()
		-- Brandi au-dessus de la tete : grosse gerbe d'etincelles, son de recompense
		local top = (actorRig.root.CFrame * CFrame.new(0, actorRig.headTop + 2, -0.3)).Position
		sparkles(setModel, top, SPARKLE_GOLD, 45)
		sparkles(setModel, top, Color3.new(1, 1, 1), 20)
		playSound("NewFruit")
		fovKick(5, 0.4)
	end)
	-- Il sautille de joie (2 petits sauts, voir poseAt)
	at(TIMES.raise + 0.6, function()
		playSound("IntroLand", 0.8, 1.1)
	end)
	at(TIMES.raise + 0.95, function()
		playSound("IntroLand", 0.8, 1.2)
	end)
	at(TIMES.fade, function()
		playSound("IntroRise", Intro.WhooshVolume) -- whoosh montant pendant le fondu au blanc
		TweenService:Create(ui.fade, TweenInfo.new(Intro.FadeInSeconds), { BackgroundTransparency = 0 }):Play()
	end)

	-- Image par image ---------------------------------------------------------------------
	camera.CameraType = Enum.CameraType.Scriptable
	local startedAt = os.clock()
	local lastFrame = startedAt
	local smoothed: Pose? = nil
	local shovelPopping = false
	local function step()
		local handsOn = 0
		local t = os.clock() - startedAt
		-- Test Studio seulement : attribut joueur "IntroFreezeAt" = seconde a figer (captures image par image)
		local freeze = player:GetAttribute("IntroFreezeAt")
		if type(freeze) == "number" and RunService:IsStudio() then
			t = freeze
		end
		if t >= TIMES.stop then
			task.spawn(finish)
			return
		end
		for _, event in events do
			if not event.done and t >= event.at then
				event.done = true
				local ok, err = pcall(event.run)
				if not ok then
					warn(`[IntroController] {err}`)
				end
			end
		end
		local base, move = actorBase(t)
		local pose, lift = poseAt(t, move)
		local rootCf = origin * (base + Vector3.new(0, actorRig.rootHeight + lift, 0))
		actorRig.root.CFrame = rootCf
		strikes(move)

		-- Pelle : placee, puis les mains vont dessus (droite sur la poignee, gauche plus bas)
		if shovel then
			local shovelCf, hands = shovelAt(t, rootCf)
			shovel:PivotTo(shovelCf)
			-- "Pop" quand il l'arrache : la pelle grossit d'un coup puis revient (rebond gelee)
			local u = (t - TIMES.pull - 0.22) / 0.4
			if u > 0 and u < 1 then
				shovelPopping = true
				shovel:ScaleTo(Intro.ShovelScale * (1 + math.sin(u * math.pi) * (1 - u) * Intro.ShovelPop))
			elseif shovelPopping then
				shovelPopping = false
				shovel:ScaleTo(Intro.ShovelScale)
			end
			lastShovel = shovelCf
			handsOn = hands
			if hands > 0 then
				local grip = rootCf:PointToObjectSpace(shovelCf.Position)
				local lower = rootCf:PointToObjectSpace((shovelCf * CFrame.new(0, -LOWER_HAND, 0)).Position)
				reach(actorRig, pose, true, grip, hands)
				reach(actorRig, pose, false, lower, hands)
			end
		end

		-- Arbre niveau 1 brandi : mains de chaque cote du pot, au-dessus de la tete
		local overhead = 0
		if t >= TIMES.raise then
			overhead = between(t, TIMES.raise, TIMES.raise + 0.25) * (1 - between(t, TIMES.lower, TIMES.lower + 0.3))
		end
		local overheadCf = rootCf * CFrame.new(0, actorRig.headTop + 0.35, -0.3)
		if overhead > 0 then
			local y = actorRig.headTop + 0.75
			reach(actorRig, pose, true, Vector3.new(0.55, y, -0.3), overhead)
			reach(actorRig, pose, false, Vector3.new(-0.55, y, -0.3), overhead)
		end
		-- Bras qui tiennent quelque chose : coudes droits (le calcul des mains suppose un bras tendu)
		local straight = 1 - math.max(handsOn, overhead)
		pose.re *= straight
		pose.le *= straight
		-- Lissage : chaque angle rejoint sa cible en douceur (pas de saut entre deux poses). Presque
		-- rien quand les mains tiennent la pelle (sinon elles quittent le manche).
		local frameAt = os.clock()
		local dt = math.min(frameAt - lastFrame, 0.1)
		lastFrame = frameAt
		local held = handsOn > 0.5 or overhead > 0.5
		local follow = 1 - math.exp(-dt / math.max(if held then 0.015 else Intro.PoseSmoothing, 1e-3))
		-- jambes : presque pas lissees quand il marche ou court (le pied pose doit rester ou il est)
		local legFollow = if move.gait == "idle" then follow else 1 - math.exp(-dt / 0.012)
		local target = pose :: any
		local shown = smoothed :: any
		if shown == nil then
			smoothed = table.clone(pose)
		else
			for field, value in target do
				shown[field] = lerp(shown[field], value, if LEG_FIELDS[field] then legFollow else follow)
			end
		end
		applyPose(actorRig, smoothed or pose)
		updateClumps()

		-- Grand arbre : tombe vers +X, puis disparait (il devient l'arbre niveau 1)
		if bigTree then
			if t >= TIMES.fall and t < TIMES.item then
				local u = math.clamp((t - TIMES.fall) / (TIMES.fallEnd - TIMES.fall), 0, 1)
				local angle = math.rad(88) * u * u
				if t > TIMES.fallEnd then
					angle = math.rad(88)
						+ math.sin((t - TIMES.fallEnd) * 18) * math.rad(3) * (1 - between(t, TIMES.fallEnd, TIMES.item))
				end
				bigTree:PivotTo(origin * CFrame.new(treeSpot) * CFrame.Angles(0, 0, -angle))
			elseif t >= TIMES.item and bigTree.Parent then
				local k = between(t, TIMES.item, TIMES.item + 0.3)
				if k >= 1 then
					bigTree:Destroy()
				else
					bigTree:ScaleTo(bigScale * math.max(0.02, 1 - k))
				end
			end
		end

		-- Arbre niveau 1 : tourne en flottant (comme un objet a ramasser), vole dans les mains, puis
		-- brandi au-dessus de la tete et redescendu devant lui
		if sapling and t >= TIMES.item then
			local hold = rootCf * Intro.HoldOffset
			if t < TIMES.grab then
				local pop = between(t, TIMES.item, TIMES.item + 0.3)
				local bob = math.sin((t - TIMES.item) * 6) * 0.25
				local spin = CFrame.Angles(0, (t - TIMES.item) * 4, 0)
				sapling:PivotTo(origin * CFrame.new(Intro.ItemSpot + Vector3.new(0, bob, 0)) * spin)
				sapling:ScaleTo(saplingScale * math.max(0.05, pop))
			else
				local k = between(t, TIMES.grab, TIMES.grab + 0.3)
				local from = origin * CFrame.new(Intro.ItemSpot)
				-- Arc (il saute vers les mains) puis rebond "gelee" (grossit, revient)
				local arc = Vector3.new(0, math.sin(k * math.pi) * 1.2, 0)
				local cf = from:Lerp(hold, k) + arc
				if overhead > 0 then
					cf = hold:Lerp(overheadCf, overhead)
				end
				sapling:PivotTo(cf)
				local u = (t - TIMES.grab - 0.3) / 0.45
				local boing = if u > 0 and u < 1 then math.sin(u * math.pi) * (1 - u) * 0.45 else 0
				local v = (t - TIMES.raise - 0.25) / 0.45
				boing += if v > 0 and v < 1 then math.sin(v * math.pi) * (1 - v) * 0.35 else 0
				sapling:ScaleTo(saplingScale * (1 + boing))
			end
		end

		local cf, fov, blur = cameraAt(t)
		-- Fin : la camera s'approche peu a peu de sa tete pendant le fondu au blanc (2026-11-23)
		local zoom = Intro.HeadZoom
		local head = actorRig.head
		-- Fond flou des gros plans : la mise au point suit sa tete
		local dof = mood.dof
		if dof then
			dof.Enabled = blur > 0.01
			if dof.Enabled then
				local subject = if head then head.Position else actorRig.root.Position
				dof.FarIntensity = blur
				dof.FocusDistance = (cf.Position - subject).Magnitude
			end
		end
		if head and t >= zoom.start then
			local k = between(t, zoom.start, TIMES.stop)
			local face = head.Position + Vector3.new(0, 0.15, 0)
			local away = cf.Position - face
			away = if away.Magnitude > 1e-3 then away.Unit else -cf.LookVector
			-- un peu d'en haut : le pot de l'arbre tenu devant lui ne cache pas le visage
			away = (away + Vector3.new(0, zoom.rise, 0)).Unit
			cf = cf:Lerp(CFrame.lookAt(face + away * zoom.distance, face), k)
			fov = lerp(fov, zoom.fov, k)
		end
		local now = os.clock()
		for i, kick in shakes do
			local u = (now - kick.at) / kick.seconds
			if u < 1 then
				local a = math.rad(kick.amount) * (1 - u)
				cf *= CFrame.Angles(math.noise(now * 28, i) * a * 2, math.noise(i, now * 28) * a * 2, 0)
			end
		end
		for _, kick in fovKicks do
			local u = (now - kick.at) / kick.seconds
			if u < 1 then
				fov -= kick.amount * math.sin(u * math.pi)
			end
		end
		camera.CFrame = cf
		camera.FieldOfView = fov
		placeBubbles(camera)
	end
	table.insert(
		connections,
		RunService.PreRender:Connect(function()
			if finished then
				return
			end
			local ok, err = pcall(step)
			if not ok then
				warn(`[IntroController] {err}`)
				task.spawn(finish)
			end
		end)
	)

	-- Le blanc du debut s'efface sur la foret
	TweenService:Create(ui.fade, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

---------------------------------------------------------------------------------------------

function IntroController.Init() end

function IntroController.Start()
	if started then
		return
	end
	started = true
	local function tryPlay()
		if playing or player:GetAttribute("IntroPending") ~= true then
			return
		end
		playing = true
		player:SetAttribute("IntroPlaying", true)
		local ok, err = pcall(play) -- (rend la main tout de suite ; la fin pose IntroPlaying = false)
		if not ok then
			-- Jamais bloque : on rend la main et la camera, on ne rejoue pas
			warn(`[IntroController] La cinematique a echoue : {err}`)
			if activeLock then
				unlockPlayer(activeLock)
				activeLock = nil
			end
			if activeMood then
				activeMood.restore()
				activeMood = nil
			end
			local playerGui = player:FindFirstChild("PlayerGui")
			for _, name in { "IntroGui", "IntroBubbles" } do
				local gui = playerGui and playerGui:FindFirstChild(name)
				if gui then
					gui:Destroy()
				end
			end
			local set = workspace:FindFirstChild("IntroSet")
			if set then
				set:Destroy()
			end
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			local remote = Remotes.WaitClientEvent("IntroDone")
			if remote then
				remote:FireServer()
			end
			playing = false
			player:SetAttribute("IntroPlaying", false)
		end
	end
	-- Attribut pose par le serveur au chargement de la sauvegarde ; aussi remis a vrai par les
	-- tests Studio (commande serveur : joueur:SetAttribute("IntroPending", true)) pour rejouer.
	player:GetAttributeChangedSignal("IntroPending"):Connect(function()
		task.spawn(tryPlay)
	end)
	task.spawn(tryPlay)
end

return IntroController
