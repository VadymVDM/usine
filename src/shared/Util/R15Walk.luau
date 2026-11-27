--!strict
-- Marche des PNJ R15 (employes : NpcRig, serveur ; clients : CustomerController, client) : meme
-- melange marche / course que le script Animate de Roblox (setRunSpeed). On joue les deux pistes
-- (Npcs.AnimationsR15.Walk et .Run) ; la course prend le dessus au-dessus de ~4 studs/s ;
-- vitesse de lecture = vitesse de marche / 16 x 1.25.
-- Doc : docs/systems/ameliorations-employes.md (Employes R15)

local R15Walk = {}

local SMALL_WEIGHT = 0.0001

-- Renvoie (vitesse de lecture, poids de la marche, poids de la course) pour une vitesse en studs/s.
function R15Walk.Blend(walkSpeed: number): (number, number, number)
	local speed = walkSpeed / 16 * 1.25
	local walkWeight, runWeight = 1, SMALL_WEIGHT
	if speed >= 0.66 then
		walkWeight, runWeight = SMALL_WEIGHT, 1
	elseif speed >= 0.33 then
		local w = (speed - 0.33) / 0.33
		walkWeight, runWeight = 1 - w + SMALL_WEIGHT, w + SMALL_WEIGHT
	end
	return speed, walkWeight, runWeight
end

-- Lance la marche (fondu `fade`) avec le bon melange pour `walkSpeed`.
function R15Walk.Play(walk: AnimationTrack?, run: AnimationTrack?, walkSpeed: number, fade: number)
	local speed, walkWeight, runWeight = R15Walk.Blend(walkSpeed)
	if walk then
		walk:Play(fade, walkWeight, speed)
	end
	if run then
		run:Play(fade, runWeight, speed)
	end
end

return R15Walk
