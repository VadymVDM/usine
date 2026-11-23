--!strict
-- Apparition "pop" d'un groupe de pieces, cote client seulement (demande du 2026-11-21 : chaque
-- pad, panneau, tuile ou machine qui apparait monte du sol / grossit avec un petit rebond).
-- Pop(cle, pieces) : le groupe part de tout petit au pied de sa boite englobante, grossit avec un
-- depassement (Back) puis revient exactement a sa forme d'origine, en apparaissant en fondu.
-- Les pieces invisibles (zones, variantes cachees : Transparency ou LocalTransparencyModifier a 1)
-- ne sont pas touchees. Relancer Pop sur la meme cle repart des positions d'origine.
-- Utilise par SetupController et LevelLookController. Doc : docs/systems/usine-a-construire.md

local RunService = game:GetService("RunService")

local Reveal = {}

local DEFAULT_SECONDS = 0.5
local START_SCALE = 0.05
local FADE_PART = 0.35 -- part de la duree pour le fondu
local OVERSHOOT = 1.9 -- force du rebond (Back)

type Entry = { part: BasePart, cframe: CFrame, size: Vector3, rel: CFrame }
type Anim = { entries: { Entry }, pivot: CFrame, t: number, duration: number, delay: number }

local anims: { [Instance]: Anim } = {}
local connection: RBXScriptConnection? = nil

local function backOut(x: number): number
	local c3 = OVERSHOOT + 1
	return 1 + c3 * (x - 1) ^ 3 + OVERSHOOT * (x - 1) ^ 2
end

local function restore(anim: Anim)
	for _, e in anim.entries do
		if e.part.Parent ~= nil then
			e.part.Size = e.size
			e.part.CFrame = e.cframe
			e.part.LocalTransparencyModifier = 0
		end
	end
end

local function step(dt: number)
	for key, anim in anims do
		if anim.delay > 0 then
			anim.delay -= dt
			continue
		end
		anim.t += dt
		local x = math.clamp(anim.t / anim.duration, 0, 1)
		if x >= 1 then
			restore(anim)
			anims[key] = nil
			continue
		end
		local scale = START_SCALE + (1 - START_SCALE) * backOut(x)
		local fade = 1 - math.clamp(x / FADE_PART, 0, 1)
		for _, e in anim.entries do
			local p = e.part
			if p.Parent == nil then
				continue
			end
			local rel = e.rel
			p.Size = Vector3.new(math.max(e.size.X * scale, 0.05), math.max(e.size.Y * scale, 0.05), math.max(e.size.Z * scale, 0.05))
			p.CFrame = anim.pivot * (CFrame.new(rel.Position * scale) * rel.Rotation)
			p.LocalTransparencyModifier = fade
		end
	end
	if next(anims) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Fait apparaitre les pieces visibles de `parts`. Renvoie le centre du pied du groupe (effets).
function Reveal.Pop(key: Instance, parts: { BasePart }, seconds: number?, delay: number?): Vector3?
	local previous = anims[key]
	if previous then
		restore(previous)
		anims[key] = nil
	end
	local visible: { BasePart } = {}
	for _, part in parts do
		if part.Transparency < 1 and part.LocalTransparencyModifier < 1 then
			table.insert(visible, part)
		end
	end
	if #visible == 0 then
		return nil
	end
	-- Pied du groupe : centre du bas de sa boite englobante (axes du monde)
	local minV, maxV = visible[1].Position, visible[1].Position
	for _, part in visible do
		local half = part.Size / 2
		local corners = part.CFrame:PointToWorldSpace(-half)
		local corners2 = part.CFrame:PointToWorldSpace(half)
		minV = minV:Min(corners):Min(corners2)
		maxV = maxV:Max(corners):Max(corners2)
	end
	local pivot = CFrame.new((minV.X + maxV.X) / 2, minV.Y, (minV.Z + maxV.Z) / 2)
	local entries: { Entry } = {}
	for _, part in visible do
		table.insert(entries, { part = part, cframe = part.CFrame, size = part.Size, rel = pivot:ToObjectSpace(part.CFrame) })
	end
	local anim: Anim = { entries = entries, pivot = pivot, t = 0, duration = seconds or DEFAULT_SECONDS, delay = delay or 0 }
	anims[key] = anim
	-- Tout petit tout de suite (pas une image a la taille normale avant le depart)
	for _, e in entries do
		e.part.LocalTransparencyModifier = 1
	end
	if connection == nil then
		connection = RunService.RenderStepped:Connect(step)
	end
	return pivot.Position
end

-- Construction piece par piece : chaque piece visible tombe de `rise` studs avec un rebond, du bas
-- vers le haut, en ~`totalSeconds`. Renvoie la duree reelle (fin de la derniere piece).
type Fall = { part: BasePart, final: CFrame, t: number, delay: number }
local falls: { [Instance]: { Fall } } = {}
local fallConnection: RBXScriptConnection? = nil
local FALL_SECONDS = 0.35

local function stepFalls(dt: number)
	for key, list in falls do
		local busy = false
		for _, f in list do
			if f.t >= FALL_SECONDS or f.part.Parent == nil then
				continue
			end
			busy = true
			if f.delay > 0 then
				f.delay -= dt
				continue
			end
			f.t = math.min(f.t + dt, FALL_SECONDS)
			local x = f.t / FALL_SECONDS
			local drop = 1 - backOut(x)
			f.part.CFrame = f.final + Vector3.new(0, drop * 7, 0)
			f.part.LocalTransparencyModifier = 1 - math.clamp(x * 2.5, 0, 1)
			if x >= 1 then
				f.part.CFrame = f.final
				f.part.LocalTransparencyModifier = 0
			end
		end
		if not busy then
			falls[key] = nil
		end
	end
	if next(falls) == nil and fallConnection then
		fallConnection:Disconnect()
		fallConnection = nil
	end
end

function Reveal.Build(key: Instance, parts: { BasePart }, totalSeconds: number): number
	local old = falls[key]
	if old then
		for _, f in old do
			if f.part.Parent ~= nil then
				f.part.CFrame = f.final
				f.part.LocalTransparencyModifier = 0
			end
		end
	end
	local visible: { BasePart } = {}
	for _, part in parts do
		if part.Transparency < 1 and part.LocalTransparencyModifier < 1 then
			table.insert(visible, part)
		end
	end
	table.sort(visible, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	local stagger = if #visible > 0 then math.min(0.05, totalSeconds / #visible) else 0
	local list: { Fall } = {}
	for i, part in visible do
		part.LocalTransparencyModifier = 1
		table.insert(list, { part = part, final = part.CFrame, t = 0, delay = (i - 1) * stagger })
	end
	falls[key] = list
	if fallConnection == nil and #list > 0 then
		fallConnection = RunService.RenderStepped:Connect(stepFalls)
	end
	return stagger * #visible + FALL_SECONDS
end

function Reveal.IsBusy(key: Instance): boolean
	return anims[key] ~= nil
end

return Reveal
